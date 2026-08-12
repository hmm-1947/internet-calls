from fastapi import APIRouter, Depends, HTTPException, Header, UploadFile, File
import os
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import func as sa_func
from app.core.database import get_db
from app.models.models import Listener, Session as SessionModel, Call, CallRating, ListenerBadgeTag
from datetime import datetime, timezone
import json
from app.models.models import ChatMessage
from app.core.ws_manager import manager
from app.schemas.schemas import ListenerLogin, AuthResponse, ListenerStatusUpdate, FcmTokenUpdate, ListenerProfileUpdate, ListenerChangePassword
from app.utils.security import verify_password, generate_session_token, hash_password, session_expiry
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
    total_calls = db.query(sa_func.count(Call.id)).filter(
        Call.callee_listener_id == current_listener.id,
        Call.status == "ended",
    ).scalar()
    avg_rating = db.query(sa_func.avg(CallRating.rating)).filter(CallRating.listener_id == current_listener.id).scalar()
    rating_count = db.query(sa_func.count(CallRating.id)).filter(CallRating.listener_id == current_listener.id).scalar()
    badge_tag = None
    if current_listener.badge_tag_id:
        t = db.query(ListenerBadgeTag).filter(ListenerBadgeTag.id == current_listener.badge_tag_id).first()
        if t:
            badge_tag = {"id": t.id, "name": t.name, "color": t.color}
    return {
        "id": current_listener.id,
        "name": current_listener.name,
        "phone": current_listener.phone,
        "total_talk_time_seconds": int(total_seconds),
        "total_calls": total_calls or 0,
        # The listener's own availability switch, not their socket state, so the
        # settings toggle keeps its position across restarts and reconnects.
        "is_online": bool(current_listener.is_online),
        "is_connected": manager.is_listener_online(current_listener.id),
        "about": current_listener.about,
        "tags": _parse_list(current_listener.tags),
        "languages": _parse_list(current_listener.languages),
        "avg_rating": round(avg_rating, 1) if avg_rating else None,
        "rating_count": rating_count or 0,
        "created_at": current_listener.created_at.isoformat() if current_listener.created_at else None,
        "photo_url": current_listener.photo_url,
        "age": current_listener.age,
        "occupation": current_listener.occupation,
        "badge_tag": badge_tag,
    }


@router.get("/wallet")
def get_wallet(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    from app.models.models import ListenerCoinTransaction, GiftTransaction
    from sqlalchemy import extract, case

    def is_day(col):
        return extract('hour', col) >= 5 and extract('hour', col) < 21

    def split_sum(model, amount_col, time_col, filters):
        day_sum = db.query(sa_func.coalesce(sa_func.sum(amount_col), 0)).filter(
            *filters,
            extract('hour', time_col) >= 5,
            extract('hour', time_col) < 21,
        ).scalar()
        night_sum = db.query(sa_func.coalesce(sa_func.sum(amount_col), 0)).filter(
            *filters,
            (extract('hour', time_col) < 5) | (extract('hour', time_col) >= 21),
        ).scalar()
        return int(day_sum), int(night_sum)

    def split_count(model, time_col, filters):
        day_count = db.query(sa_func.count(model.id)).filter(
            *filters,
            extract('hour', time_col) >= 5,
            extract('hour', time_col) < 21,
        ).scalar()
        night_count = db.query(sa_func.count(model.id)).filter(
            *filters,
            (extract('hour', time_col) < 5) | (extract('hour', time_col) >= 21),
        ).scalar()
        return int(day_count), int(night_count)

    audio_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == current_listener.id,
        ListenerCoinTransaction.reason == "audio_call",
    ).scalar()
    video_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == current_listener.id,
        ListenerCoinTransaction.reason == "video_call",
    ).scalar()
    chat_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == current_listener.id,
        ListenerCoinTransaction.reason == "chat_message",
    ).scalar()

    audio_seconds_day, audio_seconds_night = split_sum(
        Call, Call.duration_seconds, Call.created_at,
        [Call.callee_listener_id == current_listener.id, Call.call_type == "audio"],
    )
    video_seconds_day, video_seconds_night = split_sum(
        Call, Call.duration_seconds, Call.created_at,
        [Call.callee_listener_id == current_listener.id, Call.call_type == "video"],
    )
    text_msgs_day, text_msgs_night = split_count(
        ChatMessage, ChatMessage.created_at,
        [ChatMessage.listener_id == current_listener.id, ChatMessage.sender_type == "user", ChatMessage.message_type == "text"],
    )
    voice_msgs_day, voice_msgs_night = split_count(
        ChatMessage, ChatMessage.created_at,
        [ChatMessage.listener_id == current_listener.id, ChatMessage.sender_type == "user", ChatMessage.message_type == "audio"],
    )
    gift_coins_day, gift_coins_night = split_sum(
        GiftTransaction, GiftTransaction.coins, GiftTransaction.created_at,
        [GiftTransaction.listener_id == current_listener.id],
    )
    gift_coins_total = db.query(sa_func.coalesce(sa_func.sum(GiftTransaction.coins), 0)).filter(
        GiftTransaction.listener_id == current_listener.id,
    ).scalar()

    return {
        "coins": current_listener.coins,
        "audio_call_coins": int(audio_coins),
        "audio_call_minutes": (int(audio_seconds_day) + int(audio_seconds_night)) // 60,
        "video_call_coins": int(video_coins),
        "video_call_minutes": (int(video_seconds_day) + int(video_seconds_night)) // 60,
        "chat_coins": int(chat_coins),
        "gift_coins": int(gift_coins_total),
        "day": {
            "audio_call_minutes": audio_seconds_day // 60,
            "video_call_minutes": video_seconds_day // 60,
            "chat_messages": text_msgs_day,
            "voice_messages": voice_msgs_day,
            "gift_coins": gift_coins_day,
        },
        "night": {
            "audio_call_minutes": audio_seconds_night // 60,
            "video_call_minutes": video_seconds_night // 60,
            "chat_messages": text_msgs_night,
            "voice_messages": voice_msgs_night,
            "gift_coins": gift_coins_night,
        },
    }


@router.put("/profile")

def update_profile(payload: ListenerProfileUpdate, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    if payload.about is not None:
        current_listener.about = payload.about
    if payload.tags is not None:
        current_listener.tags = json.dumps(payload.tags)
    if payload.languages is not None:
        current_listener.languages = json.dumps(payload.languages)
    if payload.age is not None:
        current_listener.age = payload.age
    if payload.occupation is not None:
        current_listener.occupation = payload.occupation
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
    db.add(SessionModel(token=token, listener_id=listener.id, expires_at=session_expiry()))
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
    # Otherwise a call placed after logout still reaches this device: the
    # push only checks for a stored token, not whether anyone is logged in.
    current_listener.fcm_token = None
    record_audit_event(db, "listener", current_listener.id, current_listener.name, "logout")
    db.commit()
    await manager.disconnect_listener(current_listener.id)
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
        {
            "id": u.id,
            "name": u.name,
            "username": u.username,
            "is_online": manager.is_user_online(u.id),
            "bio": u.bio,
            "photo_url": u.photo_url,
        }
        for u in users
    ]


@router.get("/user/{user_id}")
def get_user_profile(
    user_id: int,
    db: Session = Depends(get_db),
    current_listener: Listener = Depends(get_current_listener),
):
    """The public profile a listener sees when they tap a user.

    Deliberately limited to what the listener needs to recognise who they are
    talking to: the contact details, coin balance and settings on the account
    are never exposed here.
    """
    from app.models.models import User

    user = db.query(User).filter(User.id == user_id, User.is_active == True).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "id": user.id,
        "name": user.name,
        "username": user.username,
        "bio": user.bio,
        "photo_url": user.photo_url,
        "is_online": manager.is_user_online(user.id),
        "last_seen": user.last_seen.isoformat() if user.last_seen else None,
        "created_at": user.created_at.isoformat() if user.created_at else None,
    }