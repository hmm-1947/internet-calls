from fastapi import APIRouter, Depends, HTTPException, Header, UploadFile, File
import os
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import func as sa_func
from app.core.database import get_db
from app.models.models import Listener, Session as SessionModel, Call, CallRating
from datetime import datetime, timezone
import json
from app.models.models import ChatMessage
from app.core.ws_manager import manager
from app.schemas.schemas import ListenerLogin, AuthResponse, ListenerStatusUpdate, FcmTokenUpdate, ListenerProfileUpdate, ListenerChangePassword
from app.utils.security import verify_password, generate_session_token, hash_password
from app.utils.audit import record_audit_event
from app.core.deps import get_current_listener

router = APIRouter(prefix="/listener", tags=["listener-auth"])

@router.get("/session/check")
def session_check(current_listener: Listener = Depends(get_current_listener)):
    return {"valid": True, "is_active": current_listener.is_active}


def _parse_list(value):
    if not value:
        return []
    try:
        return json.loads(value)
    except Exception:
        return []

@router.get("/me")
def get_me(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    total_seconds = db.query(sa_func.coalesce(sa_func.sum(Call.duration_seconds), 0)).filter(
        Call.callee_listener_id == current_listener.id
    ).scalar()
    avg_rating = db.query(sa_func.avg(CallRating.rating)).filter(CallRating.listener_id == current_listener.id).scalar()
    rating_count = db.query(sa_func.count(CallRating.id)).filter(CallRating.listener_id == current_listener.id).scalar()
    return {
        "id": current_listener.id,
        "name": current_listener.name,
        "phone": current_listener.phone,
        "total_talk_time_seconds": int(total_seconds),
        "about": current_listener.about,
        "tags": _parse_list(current_listener.tags),
        "languages": _parse_list(current_listener.languages),
        "avg_rating": round(avg_rating, 1) if avg_rating else None,
        "rating_count": rating_count or 0,
        "created_at": current_listener.created_at.isoformat() if current_listener.created_at else None,
        "photo_url": current_listener.photo_url,
    }

@router.get("/wallet")
def get_wallet(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    from app.models.models import ListenerCoinTransaction
    audio_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == current_listener.id,
        ListenerCoinTransaction.reason == "audio_call",
    ).scalar()
    video_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == current_listener.id,
        ListenerCoinTransaction.reason == "video_call",
    ).scalar()
    audio_seconds = db.query(sa_func.coalesce(sa_func.sum(Call.duration_seconds), 0)).filter(
        Call.callee_listener_id == current_listener.id, Call.call_type == "audio",
    ).scalar()
    video_seconds = db.query(sa_func.coalesce(sa_func.sum(Call.duration_seconds), 0)).filter(
        Call.callee_listener_id == current_listener.id, Call.call_type == "video",
    ).scalar()
    chat_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == current_listener.id,
        ListenerCoinTransaction.reason == "chat_message",
    ).scalar()
    return {
        "coins": current_listener.coins,
        "audio_call_coins": int(audio_coins),
        "audio_call_minutes": int(audio_seconds) // 60,
        "video_call_coins": int(video_coins),
        "video_call_minutes": int(video_seconds) // 60,
        "chat_coins": int(chat_coins),
        "gift_coins": 0,
    }


@router.put("/profile")

def update_profile(payload: ListenerProfileUpdate, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    if payload.about is not None:
        current_listener.about = payload.about
    if payload.tags is not None:
        current_listener.tags = json.dumps(payload.tags)
    if payload.languages is not None:
        current_listener.languages = json.dumps(payload.languages)
    db.commit()
    return {"status": "updated"}

@router.post("/photo")
async def update_photo(file: UploadFile = File(...), db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    ext = os.path.splitext(file.filename)[1] or ".jpg"
    filename = f"listener_{current_listener.id}_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("profile_photos", filename)
    with open(filepath, "wb") as f:
        f.write(await file.read())
    current_listener.photo_url = f"/profile_photos/{filename}"
    db.commit()
    return {"status": "updated", "photo_url": current_listener.photo_url}

@router.post("/login", response_model=AuthResponse)
def login(payload: ListenerLogin, db: Session = Depends(get_db)):
    listener = db.query(Listener).filter(Listener.phone == payload.phone).first()
    if not listener or not verify_password(payload.password, listener.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not listener.is_active:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = generate_session_token()
    db.add(SessionModel(token=token, listener_id=listener.id))
    listener.is_online = True
    record_audit_event(db, "listener", listener.id, listener.name, "login")
    db.commit()
    return AuthResponse(token=token, id=listener.id, name=listener.name)

@router.post("/status")
async def update_status(payload: ListenerStatusUpdate, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    current_listener.is_online = payload.is_online
    if not payload.is_online:
        current_listener.last_seen = datetime.now(timezone.utc)
    db.commit()
    event_type = "listener_online" if payload.is_online else "listener_offline"
    payload_out = {"type": event_type, "listener_id": current_listener.id}
    if not payload.is_online:
        payload_out["last_seen"] = current_listener.last_seen.isoformat()
    await manager.broadcast_to_all_users(payload_out)
    return {"status": "updated", "is_online": current_listener.is_online}


@router.post("/logout")
async def logout(authorization: str = Header(...), db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    token = authorization.replace("Bearer ", "")
    db.query(SessionModel).filter(SessionModel.token == token).delete()
    current_listener.is_online = False
    current_listener.last_seen = datetime.now(timezone.utc)
    record_audit_event(db, "listener", current_listener.id, current_listener.name, "logout")
    db.commit()
    manager.disconnect_listener(current_listener.id)
    await manager.broadcast_to_all_users({
        "type": "listener_offline",
        "listener_id": current_listener.id,
        "last_seen": current_listener.last_seen.isoformat(),
    })
    return {"status": "logged_out"}

@router.post("/change-password")
def change_password(payload: ListenerChangePassword, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    if not verify_password(payload.current_password, current_listener.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if verify_password(payload.new_password, current_listener.password_hash):
        raise HTTPException(status_code=400, detail="New password must be different from your current password")
    current_listener.password_hash = hash_password(payload.new_password)
    db.commit()
    return {"status": "password_changed"}


@router.post("/fcm-token")
def update_fcm_token(payload: FcmTokenUpdate, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    current_listener.fcm_token = payload.fcm_token
    db.commit()
    return {"status": "updated"}

@router.get("/users")
def get_users(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    from app.models.models import User
    users = db.query(User).filter(User.is_active == True).all()
    return [
        {"id": u.id, "name": u.name, "is_online": manager.is_user_online(u.id), "bio": u.bio, "photo_url": u.photo_url}
        for u in users
    ]