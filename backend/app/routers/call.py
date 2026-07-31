#calls.py
import asyncio
import uuid
from datetime import datetime, timezone, timedelta
# pyrefly: ignore [missing-import]
from fastapi import APIRouter, Depends, HTTPException
# pyrefly: ignore [missing-import]
from app.schemas.schemas import CallHistoryOut
from sqlalchemy.orm import Session
from app.models.models import CallRating
from app.core.config import settings
from fastapi import Request
from app.core.database import get_db, SessionLocal
from app.core.deps import get_current_user, get_current_listener, get_current_participant
from app.models.models import Listener, Call, User
from app.schemas.schemas import CallInitiate
from app.utils.livekit_token import generate_token
from app.utils.fcm import send_call_notification, send_call_cancelled, send_call_rejected, send_call_accepted, send_call_ended, send_call_coin_exceeded, send_call_missed, send_async
from app.models.models import CallRecording
from app.utils.livekit_egress import start_recording, stop_recording
from app.utils.livekit_room import delete_room_background


from app.utils.coins import max_call_seconds, reconcile_call_billing, bill_call_minute, coins_per_minute
from app.routers.weekly_challenge import add_talktime_seconds
from app.schemas.schemas import CallInitiate
from app.core.ws_manager import manager
from app.schemas.schemas import CallRatingSubmit, CallSummaryOut, ListenerReviewOut
from livekit import api as livekit_api

RINGING_TIMEOUT = timedelta(seconds=60)
BILLING_ACTIVE_STATUSES = ("accepted",)

router = APIRouter(prefix="/call", tags=["call"])


def _clear_invalid_fcm_token(db: Session, entity, token_attr: str, error: Exception) -> None:
    if "not found" in str(error).lower() or "registration-token-not-registered" in str(error).lower():
        setattr(entity, token_attr, None)
        db.commit()


async def _finalize_call_billing(db: Session, call: Call, duration_seconds: int) -> None:
    call.duration_seconds = duration_seconds
    user = db.query(User).filter(User.id == call.caller_user_id).first()
    if user:
        await reconcile_call_billing(db, call, duration_seconds)
    if call.callee_listener_id:
        add_talktime_seconds(db, call.callee_listener_id, duration_seconds)
    db.commit()


def _elapsed_since_connected(call: Call) -> int:
    """Seconds since the call clock started, computed server side so both apps
    agree regardless of their own clocks."""
    if not call.connected_at:
        return 0
    connected_at = call.connected_at
    if connected_at.tzinfo is None:
        connected_at = connected_at.replace(tzinfo=timezone.utc)
    return max(0, int((datetime.now(timezone.utc) - connected_at).total_seconds()))


def _compute_call_duration(call: Call, override_seconds: int | None = None) -> int:
    if override_seconds is not None:
        return int(override_seconds)
    if call.connected_at:
        connected_at = call.connected_at
        if connected_at.tzinfo is None:
            connected_at = connected_at.replace(tzinfo=timezone.utc)
        return int((datetime.now(timezone.utc) - connected_at).total_seconds())
    return 0

async def run_call_billing(call_id: int):
    """Background task: bills one minute immediately, then every 60s while
    the call is active. Ends the call if the user runs out of coins."""
    db = SessionLocal()
    try:
        call = db.query(Call).filter(Call.id == call_id).first()
        if not call or call.status not in BILLING_ACTIVE_STATUSES:
            return
        result = await bill_call_minute(db, call)
        if result is None:
            await _end_call_insufficient_coins(db, call_id)
            return
        while True:
            await asyncio.sleep(60)
            db.expire_all()
            call = db.query(Call).filter(Call.id == call_id).first()
            if not call or call.status not in BILLING_ACTIVE_STATUSES:
                return
            result = await bill_call_minute(db, call)
            if result is None:
                await _end_call_insufficient_coins(db, call_id)
                return
    finally:
        db.close()

async def _end_call_insufficient_coins(db: Session, call_id: int):
    call = db.query(Call).filter(Call.id == call_id).first()
    if not call:
        return
    listener = db.query(Listener).filter(Listener.id == call.callee_listener_id).first()
    # Delegate to finalize_abandoned_call so this path gets the exact same
    # billing reconciliation, weekly-challenge talktime credit, and egress
    # stop as every other way a call can end. Skip its generic "call ended"
    # push so we can send the more specific "coin exceeded" one below instead.
    claimed = await finalize_abandoned_call(db, call, notify_user=False, notify_listener=False)
    if not claimed:
        return
    user = db.query(User).filter(User.id == call.caller_user_id).first()
    if user and user.fcm_token:
        try:
            send_call_coin_exceeded(user.fcm_token, call_id)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify user {user.id} of coin exceeded: {e}")
    if listener and listener.fcm_token:
        try:
            send_call_coin_exceeded(listener.fcm_token, call_id)
        except Exception:
            pass



@router.post("/initiate")
def initiate_call(payload: CallInitiate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    listener = db.query(Listener).filter(Listener.id == payload.listener_id).first()
    if not listener or not listener.is_active:
        raise HTTPException(status_code=404, detail="Listener not found")
    call_type = payload.call_type if payload.call_type in ("audio", "video") else "audio"
    if call_type == "video" and current_user.video_call_disabled_by_admin:
        raise HTTPException(status_code=403, detail="Admin has disabled video calls for your account")
    if call_type == "video" and not current_user.video_call_enabled:
        raise HTTPException(status_code=403, detail="Video calls are disabled in your settings")
    per_minute = coins_per_minute(db, call_type)
    if current_user.coins < per_minute:
        raise HTTPException(status_code=402, detail="Not enough coins to start this call")
    db.query(Call).filter(
        Call.caller_user_id == current_user.id,
        Call.status == "ringing",
    ).update({"status": "cancelled"}, synchronize_session=False)
    db.commit()
    room_name = f"call-{uuid.uuid4().hex[:12]}"
    call = Call(room_name=room_name, caller_user_id=current_user.id, callee_listener_id=listener.id, status="ringing", call_type=call_type)
    db.add(call)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=409, detail="Listener is busy")
    db.refresh(call)
    # No token returned yet — user joins LiveKit only after listener accepts.
    # The push goes out on a worker thread so the caller gets `call_id` back and
    # can start ringing without waiting on the FCM round trip.
    if listener.fcm_token:
        send_async(
            send_call_notification,
            listener.fcm_token, room_name, current_user.name, current_user.id, call.id,
            call_type=call_type, caller_photo_url=current_user.photo_url or "",
        )
    return {"call_id": call.id}

async def _notify_caller_accepted(db: Session, call: Call) -> None:
    """Hand the caller their LiveKit token the moment the listener accepts, so
    both sides negotiate with LiveKit at the same time instead of the caller
    waiting for the listener to finish joining first.

    The websocket is the fast path (the caller is sitting on the call screen
    with it open); the push is the fallback for a socket that just dropped."""
    user = db.query(User).filter(User.id == call.caller_user_id).first()
    if not user:
        return
    user_token = generate_token(call.room_name, f"user-{user.id}", user.name)
    await manager.send_to_user(user.id, {
        "type": "call_accepted",
        "call_id": call.id,
        "room_name": call.room_name,
        "token": user_token,
        "livekit_url": settings.livekit_url,
        "call_type": call.call_type,
    })
    if user.fcm_token:
        send_async(send_call_accepted, user.fcm_token, call.id, call.room_name, user_token, settings.livekit_url)


@router.post("/{call_id}/accept")
async def accept_call(call_id: int, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    call = db.query(Call).filter(Call.id == call_id, Call.callee_listener_id == current_listener.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    if call.status == "accepted":
        listener_token = generate_token(call.room_name, f"listener-{current_listener.id}", current_listener.name)
        await _notify_caller_accepted(db, call)
        return {"room_name": call.room_name, "token": listener_token, "livekit_url": settings.livekit_url, "call_type": call.call_type}
    if call.status != "ringing":
        raise HTTPException(status_code=400, detail="Call has already been cancelled, ended, or accepted")
    if datetime.now(timezone.utc) - call.created_at.replace(tzinfo=timezone.utc) > RINGING_TIMEOUT:
        call.status = "missed"
        db.commit()
        raise HTTPException(status_code=408, detail="Call timed out")
    call.status = "accepted"
    db.commit()
    listener_token = generate_token(call.room_name, f"listener-{current_listener.id}", current_listener.name)
    await _notify_caller_accepted(db, call)
    return {"room_name": call.room_name, "token": listener_token, "livekit_url": settings.livekit_url, "call_type": call.call_type}

@router.post("/{call_id}/ready")
async def ready_call(call_id: int, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    call = db.query(Call).filter(Call.id == call_id, Call.callee_listener_id == current_listener.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    if call.status != "accepted":
        raise HTTPException(status_code=400, detail="Call is not in accepted state")
    if call.connected_at is None:
        call.connected_at = datetime.now(timezone.utc)
        db.commit()
        asyncio.create_task(run_call_billing(call.id))
    user = db.query(User).filter(User.id == call.caller_user_id).first()
    max_seconds = max_call_seconds(db, user, call.call_type) if user else 0
    # The caller was already handed their token at accept time; repeat it here so
    # a socket that reconnected in between still gets it. The client ignores the
    # duplicate.
    await _notify_caller_accepted(db, call)
    # Both call screens seed their timer from this, so they tick together and
    # match the billed duration instead of each starting whenever its own device
    # happened to finish setting up. The server sends the already-elapsed time
    # rather than a timestamp, so a skewed device clock cannot shift it.
    elapsed = _elapsed_since_connected(call)
    if user:
        await manager.send_to_user(user.id, {
            "type": "call_connected",
            "call_id": call.id,
            "elapsed_seconds": elapsed,
        })
    return {"status": "ready", "max_seconds": max_seconds, "elapsed_seconds": elapsed}


@router.post("/{call_id}/recording/start")
async def start_call_recording(call_id: int, db: Session = Depends(get_db), current=Depends(get_current_participant)):
    call = db.query(Call).filter(Call.id == call_id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    is_participant = (
        (isinstance(current, User) and call.caller_user_id == current.id) or
        (isinstance(current, Listener) and call.callee_listener_id == current.id)
    )
    if not is_participant:
        raise HTTPException(status_code=403, detail="Not a participant of this call")
    existing = db.query(CallRecording).filter(CallRecording.call_id == call_id, CallRecording.status == "recording").first()
    if existing:
        return {"egress_id": existing.egress_id}
    output_path = f"/out/{call.room_name}.ogg"
    try:
        egress_id = await start_recording(call.room_name, output_path)
        recording = CallRecording(call_id=call_id, egress_id=egress_id, room_name=call.room_name, file_path=output_path)
        db.add(recording)
        db.commit()
        return {"egress_id": egress_id}
    except Exception as e:
        print(f"[EGRESS ERROR] Failed to start recording for call {call_id}: {e}")
        return {"status": "failed"}

@router.post("/{call_id}/reject")
async def reject_call(call_id: int, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    call = db.query(Call).filter(Call.id == call_id, Call.callee_listener_id == current_listener.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    if call.status in ("rejected", "ended", "cancelled", "missed"):
        return {"status": call.status}
    if call.status != "ringing":
        raise HTTPException(status_code=400, detail="Call is not in a rejectable state")
    call.status = "rejected"
    db.commit()
    delete_room_background(call.room_name)
    user = db.query(User).filter(User.id == call.caller_user_id).first()

    if user and user.fcm_token:
        try:
            send_call_rejected(user.fcm_token, call_id)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify user {user.id} of rejection: {e}")
            _clear_invalid_fcm_token(db, user, "fcm_token", e)
    return {"status": "rejected"}

@router.post("/{call_id}/cancel")
async def cancel_call(call_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    call = db.query(Call).filter(Call.id == call_id, Call.caller_user_id == current_user.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    if call.status in ("rejected", "ended", "cancelled", "missed"):
        return {"status": call.status}
    call.status = "cancelled"
    db.commit()
    delete_room_background(call.room_name)
    listener = db.query(Listener).filter(Listener.id == call.callee_listener_id).first()
    if listener and listener.fcm_token:
        try:
            send_call_cancelled(listener.fcm_token, call_id)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify listener {listener.id} of cancellation: {e}")
            _clear_invalid_fcm_token(db, listener, "fcm_token", e)
    return {"status": "cancelled"}

@router.post("/{call_id}/timeout")
async def timeout_call(call_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Called by the caller's app when the listener has not responded within the ringing window.
    Marks the call as missed (distinct from a user-initiated cancel or listener rejection)."""
    call = db.query(Call).filter(Call.id == call_id, Call.caller_user_id == current_user.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    if call.status in ("rejected", "ended", "cancelled", "missed", "accepted"):
        return {"status": call.status}
    call.status = "missed"
    db.commit()
    delete_room_background(call.room_name)
    listener = db.query(Listener).filter(Listener.id == call.callee_listener_id).first()
    if listener and listener.fcm_token:
        try:
            send_call_missed(listener.fcm_token, call_id)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify listener {listener.id} of missed call: {e}")
            _clear_invalid_fcm_token(db, listener, "fcm_token", e)
    return {"status": "missed"}


@router.post("/{call_id}/end")
async def end_call(call_id: int, db: Session = Depends(get_db), current=Depends(get_current_participant)):
    call = db.query(Call).filter(Call.id == call_id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    is_participant = (
        (isinstance(current, User) and call.caller_user_id == current.id) or
        (isinstance(current, Listener) and call.callee_listener_id == current.id)
    )
    if not is_participant:
        raise HTTPException(status_code=403, detail="Not a participant of this call")
    await finalize_abandoned_call(db, call)
    return {"status": "ended"}


async def finalize_abandoned_call(
    db: Session,
    call: Call,
    override_seconds: int | None = None,
    stop_egress: bool = True,
    notify_user: bool = True,
    notify_listener: bool = True,
):
    already_ended = call.status == "ended"
    claimed = db.query(Call).filter(Call.id == call.id, Call.status != "ended").update(
        {"status": "ended"}, synchronize_session=False
    )
    db.commit()
    if claimed == 0 and not (already_ended and override_seconds is not None):
        return False
    db.refresh(call)

    if call.connected_at:
        duration = _compute_call_duration(call, override_seconds=override_seconds)
        await _finalize_call_billing(db, call, duration)
    db.commit()

    if claimed == 0:
        return False

    if stop_egress:
        recording = db.query(CallRecording).filter(CallRecording.call_id == call.id, CallRecording.status == "recording").first()
        if recording:
            try:
                await stop_recording(recording.egress_id)
            except Exception as e:
                print(f"[EGRESS ERROR] Failed to stop recording for call {call.id}: {e}")
            recording.status = "ended"
            recording.ended_at = datetime.now(timezone.utc)
            db.commit()

    if notify_user:
        user = db.query(User).filter(User.id == call.caller_user_id).first()
        if user and user.fcm_token:
            try:
                send_call_ended(user.fcm_token, call.id)
            except Exception as e:
                print(f"[FCM ERROR] Failed to notify user of call end: {e}")
                _clear_invalid_fcm_token(db, user, "fcm_token", e)

    if notify_listener:
        listener = db.query(Listener).filter(Listener.id == call.callee_listener_id).first()
        if listener and listener.fcm_token:
            try:
                send_call_ended(listener.fcm_token, call.id)
            except Exception as e:
                print(f"[FCM ERROR] Failed to notify listener of call end: {e}")
                _clear_invalid_fcm_token(db, listener, "fcm_token", e)

    return True


@router.get("/{call_id}/status")
def call_status(call_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Caller-side polling fallback for the `call_accepted` signal.

    Both the websocket event and the push can be lost, which would leave the
    caller stuck on the ringing screen. Returns the same token, only to the
    authenticated caller of this call, as soon as the listener has accepted —
    waiting for `connected_at` here used to hold the caller back until the
    listener had finished joining the room.
    """
    call = db.query(Call).filter(Call.id == call_id, Call.caller_user_id == current_user.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    response = {"status": call.status, "call_type": call.call_type}
    if call.status == "accepted":
        response["room_name"] = call.room_name
        response["token"] = generate_token(call.room_name, f"user-{current_user.id}", current_user.name)
        response["livekit_url"] = settings.livekit_url
        if call.connected_at:
            response["elapsed_seconds"] = _elapsed_since_connected(call)
    return response


@router.get("/{call_id}/coin-status")
def coin_status(call_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    call = db.query(Call).filter(Call.id == call_id, Call.caller_user_id == current_user.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    max_seconds = max_call_seconds(db, current_user, call.call_type)
    return {"coins": current_user.coins, "max_seconds": max_seconds}

@router.post("/{call_id}/coin-exceeded")
async def coin_exceeded(call_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    call = db.query(Call).filter(Call.id == call_id, Call.caller_user_id == current_user.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    listener = db.query(Listener).filter(Listener.id == call.callee_listener_id).first()
    claimed = await finalize_abandoned_call(db, call, notify_user=False, notify_listener=False)
    if claimed and listener and listener.fcm_token:
        try:
            send_call_coin_exceeded(listener.fcm_token, call_id)
        except Exception:
            pass
    return {"status": "ended"}

@router.post("/livekit/webhook")
async def livekit_webhook(request: Request, db: Session = Depends(get_db)):
    raw_body = await request.body()
    auth_header = request.headers.get("Authorization", "")
    try:
        receiver = livekit_api.WebhookReceiver(settings.livekit_api_key, settings.livekit_api_secret)
        event_data = receiver.receive(raw_body.decode("utf-8"), auth_header)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid webhook signature")

    if event_data.event != "room_finished":
        return {"ok": True}
    room = event_data.room
    room_name = room.name if room else None
    livekit_duration = getattr(room, "duration", None) if room else None
    call = db.query(Call).filter(Call.room_name == room_name).first()
    if not call:
        return {"ok": True}
    await finalize_abandoned_call(db, call, override_seconds=livekit_duration, stop_egress=False)
    return {"ok": True}


@router.get("/user/history", response_model=list[CallHistoryOut])
def user_call_history(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    calls = db.query(Call).filter(Call.caller_user_id == current_user.id).order_by(Call.created_at.desc()).all()
    listener_ids = {c.callee_listener_id for c in calls if c.callee_listener_id}
    listeners_by_id = {l.id: l for l in db.query(Listener).filter(Listener.id.in_(listener_ids)).all()}
    result = []
    for c in calls:
        listener = listeners_by_id.get(c.callee_listener_id)
        result.append(CallHistoryOut(
            id=c.id, room_name=c.room_name, user_id=current_user.id, user_name=current_user.name,
            listener_id=c.callee_listener_id, listener_name=listener.name if listener else "Unknown",
            call_type=c.call_type, status=c.status, duration_seconds=c.duration_seconds,
            coins_deducted=c.coins_deducted, created_at=c.created_at, connected_at=c.connected_at,
            other_party_photo_url=listener.photo_url if listener else None,
        ))
    return result

@router.get("/listener/history", response_model=list[CallHistoryOut])
def listener_call_history(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    calls = db.query(Call).filter(Call.callee_listener_id == current_listener.id).order_by(Call.created_at.desc()).all()
    user_ids = {c.caller_user_id for c in calls if c.caller_user_id}
    users_by_id = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()}
    result = []
    for c in calls:
        user = users_by_id.get(c.caller_user_id)
        result.append(CallHistoryOut(
            id=c.id, room_name=c.room_name, user_id=c.caller_user_id, user_name=user.name if user else "Unknown",
            listener_id=current_listener.id, listener_name=current_listener.name,
            call_type=c.call_type, status=c.status, duration_seconds=c.duration_seconds,
            coins_deducted=c.coins_deducted, created_at=c.created_at, connected_at=c.connected_at,
            other_party_photo_url=user.photo_url if user else None,
        ))
    return result

@router.get("/{call_id}/summary", response_model=CallSummaryOut)
def call_summary(call_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    call = db.query(Call).filter(Call.id == call_id, Call.caller_user_id == current_user.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    listener = db.query(Listener).filter(Listener.id == call.callee_listener_id).first()
    existing = db.query(CallRating).filter(CallRating.call_id == call_id).first()
    return CallSummaryOut(
        call_id=call.id, listener_id=call.callee_listener_id,
        listener_name=listener.name if listener else "Unknown",
        listener_photo_url=listener.photo_url if listener else None,
        duration_seconds=call.duration_seconds, coins_deducted=call.coins_deducted,
        existing_rating=existing.rating if existing else None,
        existing_review=existing.review if existing else None,
    )

@router.post("/{call_id}/rate")
async def rate_call(call_id: int, payload: CallRatingSubmit, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if payload.rating < 1 or payload.rating > 5:
        raise HTTPException(status_code=400, detail="Rating must be between 1 and 5")
    call = db.query(Call).filter(Call.id == call_id, Call.caller_user_id == current_user.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    existing = db.query(CallRating).filter(CallRating.call_id == call_id).first()
    if existing:
        existing.rating = payload.rating
        existing.review = payload.review
    else:
        existing = CallRating(
            call_id=call_id, user_id=current_user.id, listener_id=call.callee_listener_id,
            rating=payload.rating, review=payload.review,
        )
        db.add(existing)
    db.commit()

    from sqlalchemy import func as sqlfunc
    avg_rating = db.query(sqlfunc.avg(CallRating.rating)).filter(CallRating.listener_id == call.callee_listener_id).scalar()
    rating_count = db.query(sqlfunc.count(CallRating.id)).filter(CallRating.listener_id == call.callee_listener_id).scalar()
    await manager.broadcast_to_all_users({
        "type": "listener_rating_updated",
        "listener_id": call.callee_listener_id,
        "avg_rating": round(avg_rating, 1) if avg_rating else None,
        "rating_count": rating_count or 0,
    })
    return {"status": "ok"}

@router.get("/listener/reviews", response_model=list[ListenerReviewOut])
def listener_reviews(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    ratings = db.query(CallRating).filter(
        CallRating.listener_id == current_listener.id
    ).order_by(CallRating.created_at.desc()).all()
    result = []
    for r in ratings:
        user = db.query(User).filter(User.id == r.user_id).first()
        result.append(ListenerReviewOut(
            user_name=user.name if user else "Unknown",
            user_photo_url=user.photo_url if user else None,
            rating=r.rating,
            review=r.review,
            created_at=r.created_at,
        ))
    return result