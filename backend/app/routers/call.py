#calls.py
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
from app.core.database import get_db
from app.core.deps import get_current_user, get_current_listener, get_current_participant
from app.models.models import Listener, Call, User
from app.schemas.schemas import CallInitiate
from app.utils.livekit_token import generate_token
from app.utils.fcm import send_call_notification, send_call_cancelled, send_call_rejected, send_call_accepted, send_call_ended, send_call_coin_exceeded
from app.models.models import CallRecording
from app.utils.livekit_egress import start_recording, stop_recording
from app.utils.coins import max_call_seconds, deduct_coins, coins_per_minute
from app.schemas.schemas import CallInitiate
from app.core.ws_manager import manager
from app.schemas.schemas import CallRatingSubmit, CallSummaryOut, ListenerReviewOut

RINGING_TIMEOUT = timedelta(seconds=60)

router = APIRouter(prefix="/call", tags=["call"])

@router.post("/initiate")
def initiate_call(payload: CallInitiate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    listener = db.query(Listener).filter(Listener.id == payload.listener_id).first()
    if not listener or not listener.is_active:
        raise HTTPException(status_code=404, detail="Listener not found")
    call_type = payload.call_type if payload.call_type in ("audio", "video") else "audio"
    per_minute = coins_per_minute(db, call_type)
    if current_user.coins < per_minute:
        raise HTTPException(status_code=402, detail="Not enough coins to start this call")
    # Auto-cancel any stale ringing calls from this user (leftover from crashes,
    # disconnects, or previous sessions) before creating a fresh one.
    stale_calls = db.query(Call).filter(
        Call.caller_user_id == current_user.id,
        Call.status == "ringing",
    ).all()
    for stale in stale_calls:
        stale.status = "cancelled"
        print(f"[INITIATE] Auto-cancelled stale ringing call id={stale.id}")
    if stale_calls:
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
    # No token returned yet — user joins LiveKit only after listener accepts
    if listener.fcm_token:
        try:
            send_call_notification(listener.fcm_token, room_name, current_user.name, current_user.id, call.id, call_type=call_type, caller_photo_url=current_user.photo_url or "")
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify listener {listener.id}: {e}")
    return {"call_id": call.id}

@router.post("/listener-initiate")
def listener_initiate_call(payload: CallInitiate, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    raise HTTPException(status_code=403, detail="Listener to user calls are disabled")

@router.post("/{call_id}/accept")
def accept_call(call_id: int, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    call = db.query(Call).filter(Call.id == call_id, Call.callee_listener_id == current_listener.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    if call.status == "accepted":
        listener_token = generate_token(call.room_name, f"listener-{current_listener.id}", current_listener.name)
        return {"room_name": call.room_name, "token": listener_token, "livekit_url": settings.livekit_url, "call_type": call.call_type}
    if call.status != "ringing":
        raise HTTPException(status_code=400, detail="Call has already been cancelled, ended, or accepted")
    if datetime.now(timezone.utc) - call.created_at.replace(tzinfo=timezone.utc) > RINGING_TIMEOUT:
        call.status = "cancelled"
        db.commit()
        raise HTTPException(status_code=408, detail="Call timed out")
    call.status = "accepted"
    pass
    db.commit()
    listener_token = generate_token(call.room_name, f"listener-{current_listener.id}", current_listener.name)
    return {"room_name": call.room_name, "token": listener_token, "livekit_url": settings.livekit_url, "call_type": call.call_type}

@router.post("/{call_id}/ready")
async def ready_call(call_id: int, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    call = db.query(Call).filter(Call.id == call_id, Call.callee_listener_id == current_listener.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    if call.status != "accepted":
        raise HTTPException(status_code=400, detail="Call is not in accepted state")
    call.connected_at = datetime.now(timezone.utc)
    db.commit()
    user = db.query(User).filter(User.id == call.caller_user_id).first()
    max_seconds = max_call_seconds(db, user, call.call_type) if user else 0
    if user:
        user_token = generate_token(call.room_name, f"user-{user.id}", user.name)
        if user.fcm_token:
            try:
                send_call_accepted(user.fcm_token, call.id, call.room_name, user_token, settings.livekit_url)
            except Exception as e:
                print(f"[FCM ERROR] Failed to notify user {user.id} of acceptance: {e}")
    return {"status": "ready", "max_seconds": max_seconds}


@router.post("/{call_id}/recording/start")
async def start_call_recording(call_id: int, db: Session = Depends(get_db), _=Depends(get_current_participant)):
    call = db.query(Call).filter(Call.id == call_id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
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
def reject_call(call_id: int, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    call = db.query(Call).filter(Call.id == call_id, Call.callee_listener_id == current_listener.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    if call.status in ("rejected", "ended", "cancelled"):
        return {"status": call.status}
    if call.status != "ringing":
        raise HTTPException(status_code=400, detail="Call is not in a rejectable state")
    call.status = "rejected"
    db.commit()
    user = db.query(User).filter(User.id == call.caller_user_id).first()
    if user and user.fcm_token:
        try:
            send_call_rejected(user.fcm_token, call_id)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify user {user.id} of rejection: {e}")
            if "not found" in str(e).lower() or "registration-token-not-registered" in str(e).lower():
                user.fcm_token = None
                db.commit()
    return {"status": "rejected"}

@router.post("/{call_id}/cancel")
def cancel_call(call_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    call = db.query(Call).filter(Call.id == call_id, Call.caller_user_id == current_user.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    if call.status in ("rejected", "ended", "cancelled"):
        return {"status": call.status}
    call.status = "cancelled"
    db.commit()
    listener = db.query(Listener).filter(Listener.id == call.callee_listener_id).first()
    if listener and listener.fcm_token:
        try:
            send_call_cancelled(listener.fcm_token, call_id)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify listener {listener.id} of cancellation: {e}")
            if "not found" in str(e).lower() or "registration-token-not-registered" in str(e).lower():
                listener.fcm_token = None
                db.commit()
    return {"status": "cancelled"}

@router.post("/{call_id}/end")
async def end_call(call_id: int, db: Session = Depends(get_db), _=Depends(get_current_participant)):
    call = db.query(Call).filter(Call.id == call_id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")

    if call.status == "ended":
        return {"status": "ended"}

    call.status = "ended"
    if call.connected_at:
        connected_at = call.connected_at
        if connected_at.tzinfo is None:
            connected_at = connected_at.replace(tzinfo=timezone.utc)
        duration = (datetime.now(timezone.utc) - connected_at).total_seconds()
        call.duration_seconds = int(duration)
        user = db.query(User).filter(User.id == call.caller_user_id).first()
        if user:
            deducted = await deduct_coins(db, user, call.id, int(duration), call.call_type)
            call.coins_deducted = deducted
    db.commit()
    recording = db.query(CallRecording).filter(CallRecording.call_id == call_id, CallRecording.status == "recording").first()
    if recording:
        try:
            await stop_recording(recording.egress_id)
        except Exception as e:
            print(f"[EGRESS ERROR] Failed to stop recording for call {call_id}: {e}")
        recording.status = "ended"
        recording.ended_at = datetime.utcnow()
        db.commit()

    user = db.query(User).filter(User.id == call.caller_user_id).first()
    if user and user.fcm_token:
        try:
            send_call_ended(user.fcm_token, call_id)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify user of call end: {e}")
            if "not found" in str(e).lower() or "registration-token-not-registered" in str(e).lower():
                user.fcm_token = None
                db.commit()

    listener = db.query(Listener).filter(Listener.id == call.callee_listener_id).first()
    if listener and listener.fcm_token:
        try:
            send_call_ended(listener.fcm_token, call_id)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify listener of call end: {e}")
            if "not found" in str(e).lower() or "registration-token-not-registered" in str(e).lower():
                listener.fcm_token = None
                db.commit()

    return {"status": "ended"}

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
    if call.status == "ended":
        return {"status": "ended"}
    call.status = "ended"
    if call.connected_at:
        connected_at = call.connected_at
        if connected_at.tzinfo is None:
            connected_at = connected_at.replace(tzinfo=timezone.utc)
        duration = (datetime.now(timezone.utc) - connected_at).total_seconds()
        call.duration_seconds = int(duration)
        deducted = await deduct_coins(db, current_user, call.id, int(duration), call.call_type)
        call.coins_deducted = deducted
    db.commit()
    listener = db.query(Listener).filter(Listener.id == call.callee_listener_id).first()
    if listener and listener.fcm_token:
        try:
            send_call_coin_exceeded(listener.fcm_token, call_id)
        except Exception:
            pass
    return {"status": "ended"}

@router.post("/livekit/webhook")
async def livekit_webhook(request: Request, db: Session = Depends(get_db)):
    body = await request.json()
    event = body.get("event")
    if event != "room_finished":
        return {"ok": True}
    room = body.get("room", {})
    room_name = room.get("name")
    livekit_duration = room.get("duration")
    call = db.query(Call).filter(Call.room_name == room_name).first()
    if not call or call.status == "ended":
        return {"ok": True}
    call.status = "ended"
    if livekit_duration is not None:
        duration = int(livekit_duration)
    elif call.connected_at:
        connected_at = call.connected_at
        if connected_at.tzinfo is None:
            connected_at = connected_at.replace(tzinfo=timezone.utc)
        duration = int((datetime.now(timezone.utc) - connected_at).total_seconds())
    else:
        duration = 0
    call.duration_seconds = duration
    user = db.query(User).filter(User.id == call.caller_user_id).first()
    if user:
        call.coins_deducted = await deduct_coins(db, user, call.id, duration, call.call_type)
    db.commit()
    return {"ok": True}

@router.get("/user/history", response_model=list[CallHistoryOut])
def user_call_history(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    calls = db.query(Call).filter(Call.caller_user_id == current_user.id).order_by(Call.created_at.desc()).all()
    result = []
    for c in calls:
        listener = db.query(Listener).filter(Listener.id == c.callee_listener_id).first()
        result.append(CallHistoryOut(
            id=c.id, room_name=c.room_name, user_id=current_user.id, user_name=current_user.name,
            listener_id=c.callee_listener_id, listener_name=listener.name if listener else "Unknown",
            call_type=c.call_type, status=c.status, duration_seconds=c.duration_seconds,
            coins_deducted=c.coins_deducted, created_at=c.created_at, connected_at=c.connected_at,
        ))
    return result

@router.get("/listener/history", response_model=list[CallHistoryOut])
def listener_call_history(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    calls = db.query(Call).filter(Call.callee_listener_id == current_listener.id).order_by(Call.created_at.desc()).all()
    result = []
    for c in calls:
        user = db.query(User).filter(User.id == c.caller_user_id).first()
        result.append(CallHistoryOut(
            id=c.id, room_name=c.room_name, user_id=c.caller_user_id, user_name=user.name if user else "Unknown",
            listener_id=current_listener.id, listener_name=current_listener.name,
            call_type=c.call_type, status=c.status, duration_seconds=c.duration_seconds,
            coins_deducted=c.coins_deducted, created_at=c.created_at, connected_at=c.connected_at,
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