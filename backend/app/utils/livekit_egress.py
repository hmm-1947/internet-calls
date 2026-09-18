import asyncio
import logging
from dataclasses import dataclass
from typing import Optional

from livekit import api
from app.core.config import settings

logger = logging.getLogger("livekit_egress")

# Minimum spacing enforced between consecutive start_room_composite_egress
# calls to LiveKit. Under burst conditions (many calls starting recording
# within a few seconds of each other) firing these near-simultaneously causes
# LiveKit's internal RPC to the egress worker to time out after ~20s of
# retries, even though the underlying system has capacity. Load testing
# confirmed 5s+ spacing gives 100% success; this starts conservatively at 2s.
EGRESS_START_MIN_SPACING_SECONDS = 2.0

# If a spaced-out start still fails, wait this long before the one retry.
EGRESS_START_RETRY_DELAY_SECONDS = 3.0


@dataclass
class _EgressStartJob:
    call_id: int
    room_name: str
    output_path: str


# In-process queue of pending egress-start requests. A single background
# worker (started once at app startup, see start_egress_worker) drains this
# one item at a time with a minimum delay between actual LiveKit calls, so
# call setup itself is never blocked or delayed by this spacing.
_egress_start_queue: "asyncio.Queue[_EgressStartJob]" = asyncio.Queue()
_worker_task: Optional[asyncio.Task] = None


async def _do_start_room_composite_egress(room_name: str, output_path: str) -> str:
    """The actual LiveKit RPC call, unspaced. Callers that need spacing go
    through enqueue_egress_start() instead of calling this directly."""
    lkapi = api.LiveKitAPI(settings.livekit_url, settings.livekit_api_key, settings.livekit_api_secret)
    try:
        req = api.RoomCompositeEgressRequest(
            room_name=room_name,
            audio_only=True,
            file_outputs=[api.EncodedFileOutput(filepath=output_path)],
        )
        res = await lkapi.egress.start_room_composite_egress(req)
        return res.egress_id
    finally:
        await lkapi.aclose()


def _apply_egress_start_result(call_id: int, egress_id: Optional[str], failed: bool) -> Optional[str]:
    """Updates the CallRecording row created (as 'pending') by the endpoint,
    now that we know whether the spaced-out start succeeded. Imported lazily
    to avoid a circular import between this module and app.models.models.

    Returns an egress_id that the caller must stop immediately (orphan
    cleanup — see below), or None in the common case."""
    from app.core.database import SessionLocal
    from app.models.models import CallRecording

    db = SessionLocal()
    try:
        recording = (
            db.query(CallRecording)
            .filter(CallRecording.call_id == call_id, CallRecording.status == "pending")
            .first()
        )
        if not recording:
            # The call ended (and its row moved to "cancelled"/"ended") while
            # this start was queued or in flight. If we did actually manage to
            # start an egress, it's now orphaned — nothing else will stop it,
            # since the call-end path only stops rows still "pending" or
            # "recording". Hand the egress_id back so the caller can stop it.
            return egress_id if not failed else None
        if failed:
            recording.status = "failed"
        else:
            recording.egress_id = egress_id
            recording.status = "recording"
        db.commit()
        return None
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


async def _stop_orphaned_egress(call_id: int, egress_id: str) -> None:
    """The call ended before we finished starting its egress, so no other
    code path will ever stop it. Stop it now so it doesn't keep recording an
    ended call indefinitely."""
    try:
        lkapi = api.LiveKitAPI(settings.livekit_url, settings.livekit_api_key, settings.livekit_api_secret)
        try:
            await lkapi.egress.stop_egress(api.StopEgressRequest(egress_id=egress_id))
        finally:
            await lkapi.aclose()
        logger.info("Stopped orphaned egress %s for already-ended call %s", egress_id, call_id)
    except Exception as e:
        logger.error("Failed to stop orphaned egress %s for call %s: %s", egress_id, call_id, e)


async def _process_egress_start_job(job: _EgressStartJob) -> None:
    try:
        egress_id = await _do_start_room_composite_egress(job.room_name, job.output_path)
        orphaned_id = _apply_egress_start_result(job.call_id, egress_id, failed=False)
        if orphaned_id:
            await _stop_orphaned_egress(job.call_id, orphaned_id)
        else:
            logger.info("Egress started for call %s (egress_id=%s)", job.call_id, egress_id)
        return
    except Exception as e:
        logger.warning(
            "Egress start failed for call %s, retrying once in %.1fs: %s",
            job.call_id, EGRESS_START_RETRY_DELAY_SECONDS, e,
        )

    # Single retry after a short delay. The call itself is already live
    # without a recording at this point, so we don't want to silently drop
    # the failure, but we also don't want to hammer LiveKit again immediately.
    await asyncio.sleep(EGRESS_START_RETRY_DELAY_SECONDS)
    try:
        egress_id = await _do_start_room_composite_egress(job.room_name, job.output_path)
        orphaned_id = _apply_egress_start_result(job.call_id, egress_id, failed=False)
        if orphaned_id:
            await _stop_orphaned_egress(job.call_id, orphaned_id)
        else:
            logger.info("Egress started for call %s on retry (egress_id=%s)", job.call_id, egress_id)
    except Exception as e:
        logger.error("Egress start failed for call %s after retry, giving up: %s", job.call_id, e)
        _apply_egress_start_result(job.call_id, None, failed=True)



async def _egress_worker_loop() -> None:
    """Pulls one egress-start request at a time and processes it, waiting at
    least EGRESS_START_MIN_SPACING_SECONDS between consecutive actual
    start_room_composite_egress calls (including the time a job itself took,
    so the queue drains as fast as spacing allows when only 1-2 requests come
    in, and doesn't fall further behind than necessary under sustained load).
    """
    loop = asyncio.get_event_loop()
    while True:
        job = await _egress_start_queue.get()
        started_at = loop.time()
        try:
            await _process_egress_start_job(job)
        except Exception:
            logger.exception("Unexpected error processing egress-start job for call %s", job.call_id)
        finally:
            _egress_start_queue.task_done()
        elapsed = loop.time() - started_at
        remaining = EGRESS_START_MIN_SPACING_SECONDS - elapsed
        if remaining > 0:
            await asyncio.sleep(remaining)


def start_egress_worker() -> None:
    """Starts the single background worker task. Call once at app startup."""
    global _worker_task
    if _worker_task is not None and not _worker_task.done():
        return
    _worker_task = asyncio.create_task(_egress_worker_loop())


def stop_egress_worker() -> None:
    """Cancels the background worker task. Call at app shutdown."""
    global _worker_task
    if _worker_task is not None:
        _worker_task.cancel()
        _worker_task = None


async def enqueue_egress_start(call_id: int, room_name: str, output_path: str) -> None:
    """Queues an egress-start request instead of calling LiveKit directly.
    Returns immediately — the caller (call-start endpoint) is never blocked
    on this, so call connection itself stays instant. The actual
    start_room_composite_egress call happens later on the background worker,
    spaced out from other queued starts."""
    await _egress_start_queue.put(_EgressStartJob(call_id=call_id, room_name=room_name, output_path=output_path))


async def start_recording(room_name: str, output_path: str) -> str:
    """Unspaced, direct start — kept for any caller that genuinely needs the
    egress_id synchronously. The call-start endpoint should prefer
    enqueue_egress_start() instead so bursts of calls get spaced out."""
    return await _do_start_room_composite_egress(room_name, output_path)

async def stop_recording(egress_id: str):
    lkapi = api.LiveKitAPI(settings.livekit_url, settings.livekit_api_key, settings.livekit_api_secret)
    await lkapi.egress.stop_egress(api.StopEgressRequest(egress_id=egress_id))
    await lkapi.aclose()
