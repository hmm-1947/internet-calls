import json
import os
import uuid
import asyncio
from typing import Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Header, WebSocket, WebSocketDisconnect, Query, UploadFile, File

from sqlalchemy.orm import Session, aliased
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from app.core.database import get_db
from app.core.config import settings
from app.models.models import (
    Listener, User, Call, CallRecording, ChatMessage,
    CoinTransaction, CallRating, Session as SessionModel, AdminUser, AuditLog,
    GiftTransaction, ListenerCoinTransaction, ChatSettings,
)
from app.schemas.schemas import ListenerCreate, AdminListenerProfileUpdate, AdminUserProfileUpdate, AdminActiveUpdate, AdminVideoCallUpdate
from app.utils.security import hash_password
from app.utils.uploads import read_and_validate_image, write_file

from app.core.ws_manager import manager
#admin
router = APIRouter(prefix="/admin", tags=["admin"])

def verify_admin(authorization: str = Header(...), db: Session = Depends(get_db)) -> AdminUser:
    from datetime import datetime, timezone
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    token = authorization.removeprefix("Bearer ")
    session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.admin_id.isnot(None)).first()
    if not session:
        raise HTTPException(status_code=401, detail="Invalid session")
    if session.expires_at and session.expires_at < datetime.now(timezone.utc):
        db.delete(session)
        db.commit()
        raise HTTPException(status_code=401, detail="Session expired")
    admin = db.query(AdminUser).filter(AdminUser.id == session.admin_id).first()
    if not admin or not admin.is_active:
        raise HTTPException(status_code=401, detail="Invalid session")
    return admin


ADMIN_WS_REVALIDATE_SECONDS = 60


@router.websocket("/ws")
async def admin_ws(websocket: WebSocket, token: str = Query(...)):
    db = next(get_db())
    try:
        session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.admin_id.isnot(None)).first()
        admin = db.query(AdminUser).filter(AdminUser.id == session.admin_id).first() if session else None
        if not admin or not admin.is_active:
            await websocket.close(code=4003)
            return
    finally:
        db.close()
    await manager.connect_admin(websocket)

    async def _revalidate_loop():
        while True:
            await asyncio.sleep(ADMIN_WS_REVALIDATE_SECONDS)
            check_db = next(get_db())
            try:
                check_session = check_db.query(SessionModel).filter(SessionModel.token == token, SessionModel.admin_id.isnot(None)).first()
                if not check_session or (check_session.expires_at and check_session.expires_at < datetime.now(timezone.utc)):
                    await websocket.close(code=4003)
                    return
                check_admin = check_db.query(AdminUser).filter(AdminUser.id == check_session.admin_id).first()
                if not check_admin or not check_admin.is_active:
                    await websocket.close(code=4003)
                    return
            finally:
                check_db.close()

    revalidate_task = asyncio.create_task(_revalidate_loop())
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect_admin(websocket)
    except Exception:
        manager.disconnect_admin(websocket)
    finally:
        revalidate_task.cancel()



def _assert_listener_name_available(db: Session, name: str, exclude_id: Optional[int] = None) -> None:
    """Users pick a listener by name, so two "Priya" rows are indistinguishable
    in the app. Matched case-insensitively, so "priya" collides with "Priya".
    `exclude_id` keeps a rename from clashing with the listener's own row."""
    q = db.query(Listener).filter(func.lower(Listener.name) == name.lower())
    if exclude_id is not None:
        q = q.filter(Listener.id != exclude_id)
    duplicate = q.first()
    if duplicate:
        raise HTTPException(
            status_code=400,
            detail=f'A listener named "{duplicate.name}" already exists. Please use a different name.',
        )


@router.post("/listeners")
def create_listener(payload: ListenerCreate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    name = (payload.name or "").strip()
    phone = (payload.phone or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Name is required")
    if not phone:
        raise HTTPException(status_code=400, detail="Phone is required")

    existing = db.query(Listener).filter(Listener.phone == phone).first()
    if existing:
        raise HTTPException(status_code=400, detail=f'Phone already registered to "{existing.name}"')

    _assert_listener_name_available(db, name)

    listener = Listener(
        name=name,
        phone=phone,
        password_hash=hash_password(payload.password),
    )
    db.add(listener)
    try:
        db.commit()
    except IntegrityError:
        # Two admins registering the same phone at once: the unique index wins.
        db.rollback()
        raise HTTPException(status_code=400, detail="Phone already registered")
    db.refresh(listener)
    return {"id": listener.id, "name": listener.name, "phone": listener.phone}

@router.get("/listeners")
def list_listeners(skip: int = Query(0, ge=0), limit: Optional[int] = Query(None, ge=1, le=5000), db: Session = Depends(get_db), _=Depends(verify_admin)):
    q = db.query(Listener).order_by(Listener.id).offset(skip)
    if limit is not None:
        q = q.limit(limit)
    listeners = q.all()
    result = [{"id": l.id, "name": l.name, "phone": l.phone, "is_active": l.is_active, "is_online": manager.is_listener_online(l.id), "about": l.about, "tags": l.tags, "languages": l.languages, "photo_url": l.photo_url} for l in listeners]
    result.sort(key=lambda x: not x["is_online"])
    return result

@router.patch("/listeners/{listener_id}/profile")
def update_listener_profile(listener_id: int, payload: AdminListenerProfileUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    if payload.name is not None and payload.name != listener.name:
        _assert_listener_name_available(db, payload.name, exclude_id=listener.id)
        listener.name = payload.name
    if payload.about is not None:
        listener.about = payload.about
    if payload.tags is not None:
        listener.tags = json.dumps(payload.tags)
    if payload.languages is not None:
        listener.languages = json.dumps(payload.languages)
    db.commit()
    return {"id": listener.id, "name": listener.name, "about": listener.about, "tags": listener.tags, "languages": listener.languages}

@router.post("/listeners/{listener_id}/photo")
async def update_listener_photo(listener_id: int, file: UploadFile = File(...), db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    contents, ext = await read_and_validate_image(file)
    filename = f"listener_{listener.id}_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("profile_photos", filename)
    await write_file(filepath, contents)
    listener.photo_url = f"/profile_photos/{filename}"
    db.commit()
    return {"id": listener.id, "photo_url": listener.photo_url}


@router.patch("/listeners/{listener_id}/active")
async def set_listener_active(listener_id: int, payload: AdminActiveUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    listener.is_active = payload.is_active
    db.commit()
    if not listener.is_active:
        await manager.send_to_listener(listener_id, {"type": "force_logout"})
    return {"id": listener.id, "is_active": listener.is_active}

@router.delete("/listeners/{listener_id}")
def delete_listener(listener_id: int, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")

    call_ids = [c.id for c in db.query(Call.id).filter(Call.callee_listener_id == listener_id).all()]

    try:
        db.query(CallRating).filter(CallRating.listener_id == listener_id).delete(synchronize_session=False)
        db.query(ChatMessage).filter(ChatMessage.listener_id == listener_id).delete(synchronize_session=False)
        db.query(SessionModel).filter(SessionModel.listener_id == listener_id).delete(synchronize_session=False)
        db.query(GiftTransaction).filter(GiftTransaction.listener_id == listener_id).delete(synchronize_session=False)
        db.query(ListenerCoinTransaction).filter(ListenerCoinTransaction.listener_id == listener_id).delete(synchronize_session=False)
        db.query(ChatSettings).filter(
            ((ChatSettings.owner_type == "listener") & (ChatSettings.owner_id == listener_id)) |
            ((ChatSettings.owner_type == "user") & (ChatSettings.other_id == listener_id))
        ).delete(synchronize_session=False)
        if call_ids:
            db.query(CallRecording).filter(CallRecording.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(CoinTransaction).filter(CoinTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(GiftTransaction).filter(GiftTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(ListenerCoinTransaction).filter(ListenerCoinTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
        db.query(Call).filter(Call.callee_listener_id == listener_id).delete(synchronize_session=False)

        db.delete(listener)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="Failed to delete listener due to related data")
    return {"detail": "Listener deleted"}

@router.get("/users")
def list_users(skip: int = Query(0, ge=0), limit: Optional[int] = Query(None, ge=1, le=5000), db: Session = Depends(get_db), _=Depends(verify_admin)):
    q = db.query(User).order_by(User.id).offset(skip)
    if limit is not None:
        q = q.limit(limit)
    users = q.all()
    result = [{"id": u.id, "name": u.name, "username": u.username, "email": u.email, "phone": u.phone, "is_active": u.is_active, "coins": u.coins, "is_online": manager.is_user_online(u.id), "bio": u.bio, "photo_url": u.photo_url, "video_call_disabled_by_admin": u.video_call_disabled_by_admin} for u in users]
    result.sort(key=lambda x: not x["is_online"])
    return result

@router.patch("/users/{user_id}/profile")
def update_user_profile(user_id: int, payload: AdminUserProfileUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if payload.bio is not None:
        user.bio = payload.bio
    db.commit()
    return {"id": user.id, "bio": user.bio}

@router.post("/users/{user_id}/photo")
async def update_user_photo(user_id: int, file: UploadFile = File(...), db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    contents, ext = await read_and_validate_image(file)
    filename = f"user_{user.id}_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("profile_photos", filename)
    await write_file(filepath, contents)
    user.photo_url = f"/profile_photos/{filename}"
    db.commit()
    return {"id": user.id, "photo_url": user.photo_url}


@router.patch("/users/{user_id}/active")
async def set_user_active(user_id: int, payload: AdminActiveUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_active = payload.is_active
    db.commit()
    if not user.is_active:
        await manager.send_to_user(user_id, {"type": "force_logout"})
    return {"id": user.id, "is_active": user.is_active}

@router.patch("/users/{user_id}/video-call")
async def set_user_video_call_disabled(user_id: int, payload: AdminVideoCallUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.video_call_disabled_by_admin = payload.disabled
    db.commit()
    await manager.send_to_user(user_id, {
        "type": "video_call_setting_changed",
        "video_call_disabled_by_admin": user.video_call_disabled_by_admin,
    })
    return {"id": user.id, "video_call_disabled_by_admin": user.video_call_disabled_by_admin}


@router.delete("/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    call_ids = [c.id for c in db.query(Call.id).filter(Call.caller_user_id == user_id).all()]

    try:
        db.query(CallRating).filter(CallRating.user_id == user_id).delete(synchronize_session=False)
        db.query(ChatMessage).filter(ChatMessage.user_id == user_id).delete(synchronize_session=False)
        db.query(SessionModel).filter(SessionModel.user_id == user_id).delete(synchronize_session=False)
        db.query(CoinTransaction).filter(CoinTransaction.user_id == user_id).delete(synchronize_session=False)
        db.query(GiftTransaction).filter(GiftTransaction.user_id == user_id).delete(synchronize_session=False)
        db.query(ChatSettings).filter(
            ((ChatSettings.owner_type == "user") & (ChatSettings.owner_id == user_id)) |
            ((ChatSettings.owner_type == "listener") & (ChatSettings.other_id == user_id))
        ).delete(synchronize_session=False)
        if call_ids:
            db.query(CallRecording).filter(CallRecording.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(GiftTransaction).filter(GiftTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(ListenerCoinTransaction).filter(ListenerCoinTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
        db.query(Call).filter(Call.caller_user_id == user_id).delete(synchronize_session=False)

        db.delete(user)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="Failed to delete user due to related data")
    return {"detail": "User deleted"}

@router.get("/recordings")
@router.get("/recordings")
def list_recordings(db: Session = Depends(get_db), _=Depends(verify_admin)):
    rows = (
        db.query(CallRecording, Call, User, Listener)
        .outerjoin(Call, Call.id == CallRecording.call_id)
        .outerjoin(User, User.id == Call.caller_user_id)
        .outerjoin(Listener, Listener.id == Call.callee_listener_id)
        .order_by(CallRecording.id.desc())
        .all()
    )
    result = []
    for r, call, caller, listener in rows:
        result.append({
            "id": r.id,
            "call_id": r.call_id,
            "room_name": r.room_name,
            "file_path": r.file_path.replace("/out/", ""),
            "status": r.status,
            "started_at": r.started_at,
            "ended_at": r.ended_at,
            "caller_name": caller.name if caller else None,
            "listener_name": listener.name if listener else None,
        })
    return result

@router.get("/calls")
def list_calls(db: Session = Depends(get_db), _=Depends(verify_admin)):
    rows = (
        db.query(Call, User, Listener)
        .outerjoin(User, User.id == Call.caller_user_id)
        .outerjoin(Listener, Listener.id == Call.callee_listener_id)
        .order_by(Call.id.desc())
        .all()
    )
    result = []
    for c, caller, listener in rows:
        result.append({
            "id": c.id,
            "caller_name": caller.name if caller else None,
            "listener_name": listener.name if listener else None,
            "status": c.status,
            "created_at": c.created_at,
        })
    return result

@router.get("/chats")
def list_chats(limit: int = Query(5000, le=20000), db: Session = Depends(get_db), _=Depends(verify_admin)):
    UserAlias = aliased(User)
    ListenerAlias = aliased(Listener)
    rows = (
        db.query(ChatMessage, UserAlias, ListenerAlias)
        .outerjoin(UserAlias, UserAlias.id == ChatMessage.user_id)
        .outerjoin(ListenerAlias, ListenerAlias.id == ChatMessage.listener_id)
        .order_by(ChatMessage.created_at.desc())
        .limit(limit)
        .all()
    )
    result = []
    for m, user, listener in rows:
        result.append({
            "id": m.id,
            "user_id": m.user_id,
            "listener_id": m.listener_id,
            "caller_name": user.name if user else None,
            "listener_name": listener.name if listener else None,
            "sender_type": m.sender_type,
            "message": m.message,
            "message_type": m.message_type,
            "audio_url": m.audio_url,
            "is_deleted": m.is_deleted,
            "created_at": m.created_at,
        })
    return result

@router.get("/listener/{listener_id}/wallet")
def admin_listener_wallet(listener_id: int, db: Session = Depends(get_db), _=Depends(verify_admin)):
    """Same breakdown as the listener app's own /listener/wallet screen, for
    any listener the admin selects — read-only, no coins are touched."""
    from app.models.models import ListenerCoinTransaction, GiftTransaction
    from sqlalchemy import extract, func as sa_func

    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")

    def split_sum(amount_col, time_col, filters):
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
        ListenerCoinTransaction.listener_id == listener.id,
        ListenerCoinTransaction.reason == "audio_call",
    ).scalar()
    video_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == listener.id,
        ListenerCoinTransaction.reason == "video_call",
    ).scalar()
    chat_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == listener.id,
        ListenerCoinTransaction.reason == "chat_message",
    ).scalar()

    audio_seconds_day, audio_seconds_night = split_sum(
        Call.duration_seconds, Call.created_at,
        [Call.callee_listener_id == listener.id, Call.call_type == "audio"],
    )
    video_seconds_day, video_seconds_night = split_sum(
        Call.duration_seconds, Call.created_at,
        [Call.callee_listener_id == listener.id, Call.call_type == "video"],
    )
    text_msgs_day, text_msgs_night = split_count(
        ChatMessage, ChatMessage.created_at,
        [ChatMessage.listener_id == listener.id, ChatMessage.sender_type == "user", ChatMessage.message_type == "text"],
    )
    voice_msgs_day, voice_msgs_night = split_count(
        ChatMessage, ChatMessage.created_at,
        [ChatMessage.listener_id == listener.id, ChatMessage.sender_type == "user", ChatMessage.message_type == "audio"],
    )
    gift_coins_day, gift_coins_night = split_sum(
        GiftTransaction.coins, GiftTransaction.created_at,
        [GiftTransaction.listener_id == listener.id],
    )
    gift_coins_total = db.query(sa_func.coalesce(sa_func.sum(GiftTransaction.coins), 0)).filter(
        GiftTransaction.listener_id == listener.id,
    ).scalar()

    return {
        "coins": listener.coins,
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

@router.get("/calls/active")
def list_active_calls(db: Session = Depends(get_db), _=Depends(verify_admin)):
    rows = (
        db.query(Call, User, Listener)
        .outerjoin(User, User.id == Call.caller_user_id)
        .outerjoin(Listener, Listener.id == Call.callee_listener_id)
        .filter(Call.status.in_(["ringing", "accepted"]))
        .order_by(Call.id.desc())
        .all()
    )
    result = []
    for c, caller, listener in rows:
        result.append({
            "id": c.id,
            "room_name": c.room_name,
            "call_type": c.call_type,
            "status": c.status,
            "user_id": c.caller_user_id,
            "listener_id": c.callee_listener_id,
            "user_name": caller.name if caller else None,
            "listener_name": listener.name if listener else None,
            "connected_at": c.connected_at,
            "created_at": c.created_at,
        })
    return result

@router.get("/stats/overview")
def stats_overview(range: str = Query("month"), db: Session = Depends(get_db), _=Depends(verify_admin)):
    from datetime import datetime, timedelta, timezone

    total_users = db.query(func.count(User.id)).scalar() or 0
    active_users = db.query(func.count(User.id)).filter(User.is_active == True).scalar() or 0
    inactive_users = total_users - active_users

    total_listeners = db.query(func.count(Listener.id)).scalar() or 0
    active_listeners = db.query(func.count(Listener.id)).filter(Listener.is_active == True).scalar() or 0
    inactive_listeners = total_listeners - active_listeners

    # Presence is the live websocket, not the `is_online` column, so it matches
    # what the people lists show and can never go stale after a restart.
    online_users = sum(1 for (uid,) in db.query(User.id).all() if manager.is_user_online(uid))
    offline_users = total_users - online_users
    online_listeners = sum(1 for (lid,) in db.query(Listener.id).all() if manager.is_listener_online(lid))
    offline_listeners = total_listeners - online_listeners

    avg_duration = db.query(func.coalesce(func.avg(Call.duration_seconds), 0)).filter(Call.status == "ended").scalar() or 0

    now = datetime.now(timezone.utc)
    ranges = {
        "day": (now - timedelta(days=1), "hour"),
        "week": (now - timedelta(days=7), "day"),
        "month": (now - timedelta(days=30), "day"),
        "6months": (now - timedelta(days=182), "week"),
        "all": (None, "month"),
    }
    since, bucket = ranges.get(range, ranges["month"])

    trunc_unit = {"hour": "hour", "day": "day", "week": "week", "month": "month"}[bucket]
    bucket_col = func.date_trunc(trunc_unit, Call.created_at)

    q = db.query(bucket_col.label("bucket"), func.count(Call.id)).filter(Call.status == "ended")
    if since is not None:
        q = q.filter(Call.created_at >= since)
    rows = q.group_by("bucket").order_by("bucket").all()

    def format_label(ts, bucket):
        if bucket == "hour":
            return ts.strftime("%Y-%m-%d %H:00")
        if bucket == "day":
            return ts.strftime("%Y-%m-%d")
        if bucket == "week":
            iso = ts.isocalendar()
            return f"{iso[0]}-W{iso[1]:02d}"
        return ts.strftime("%Y-%m")

    series = [{"label": format_label(ts, bucket), "count": count} for ts, count in rows]

    return {
        "total_users": total_users,
        "active_users": active_users,
        "inactive_users": inactive_users,
        "online_users": online_users,
        "offline_users": offline_users,
        "total_listeners": total_listeners,
        "active_listeners": active_listeners,
        "inactive_listeners": inactive_listeners,
        "online_listeners": online_listeners,
        "offline_listeners": offline_listeners,
        "avg_call_duration_seconds": round(avg_duration),
        "calls_series": series,
    }

@router.get("/stats/users")
def list_user_stats(db: Session = Depends(get_db), _=Depends(verify_admin)):
    call_stats = dict(
        db.query(Call.caller_user_id, func.count(Call.id))
        .filter(Call.status == "ended")
        .group_by(Call.caller_user_id).all()
    )
    duration_stats = dict(
        db.query(Call.caller_user_id, func.coalesce(func.sum(Call.duration_seconds), 0))
        .filter(Call.status == "ended")
        .group_by(Call.caller_user_id).all()
    )
    chat_stats = dict(
        db.query(ChatMessage.user_id, func.count(ChatMessage.id))
        .filter(ChatMessage.sender_type == "user")
        .group_by(ChatMessage.user_id).all()
    )
    users = db.query(User).all()
    result = []
    for u in users:
        result.append({
            "id": u.id,
            "name": u.name,
            "phone": u.phone,
            "total_calls": call_stats.get(u.id, 0),
            "total_call_seconds": duration_stats.get(u.id, 0),
            "total_chat_messages": chat_stats.get(u.id, 0),
        })
    result.sort(key=lambda x: x["total_calls"], reverse=True)
    return result

@router.get("/stats/listeners")
def list_listener_stats(db: Session = Depends(get_db), _=Depends(verify_admin)):
    call_stats = dict(
        db.query(Call.callee_listener_id, func.count(Call.id))
        .filter(Call.status == "ended")
        .group_by(Call.callee_listener_id).all()
    )
    duration_stats = dict(
        db.query(Call.callee_listener_id, func.coalesce(func.sum(Call.duration_seconds), 0))
        .filter(Call.status == "ended")
        .group_by(Call.callee_listener_id).all()
    )
    chat_stats = dict(
        db.query(ChatMessage.listener_id, func.count(ChatMessage.id))
        .filter(ChatMessage.sender_type == "listener")
        .group_by(ChatMessage.listener_id).all()
    )
    listeners = db.query(Listener).all()
    result = []
    for l in listeners:
        result.append({
            "id": l.id,
            "name": l.name,
            "phone": l.phone,
            "total_calls": call_stats.get(l.id, 0),
            "total_call_seconds": duration_stats.get(l.id, 0),
            "total_chat_messages": chat_stats.get(l.id, 0),
        })
    result.sort(key=lambda x: x["total_calls"], reverse=True)
    return result


def _paginated_audit_log(db: Session, subject_type: str, page: int, page_size: int):
    page = max(page, 1)
    page_size = min(max(page_size, 1), 100)

    query = db.query(AuditLog).filter(AuditLog.subject_type == subject_type)
    total = query.count()
    rows = (
        query.order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return {
        "items": [
            {
                "id": r.id,
                "subject_id": r.subject_id,
                "name": r.subject_name,
                "action": r.action,
                "created_at": r.created_at,
            }
            for r in rows
        ],
        "total": total,
        "page": page,
        "page_size": page_size,
    }


@router.get("/audit-log/users")
def list_user_audit_log(
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
    _=Depends(verify_admin),
):
    """Login/logout history for users, most recent first. Failed login
    attempts are never recorded, so only successful events appear here."""
    return _paginated_audit_log(db, "user", page, page_size)


@router.get("/audit-log/listeners")
def list_listener_audit_log(
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
    _=Depends(verify_admin),
):
    """Login/logout history for listeners, most recent first. Failed login
    attempts are never recorded, so only successful events appear here."""
    return _paginated_audit_log(db, "listener", page, page_size)
