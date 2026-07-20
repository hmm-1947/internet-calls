from fastapi import APIRouter, Depends, HTTPException, Header, WebSocket, WebSocketDisconnect, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from app.core.database import get_db
from app.core.config import settings
from app.models.models import (
    Listener, User, Call, CallRecording, ChatMessage,
    CoinTransaction, CallRating, Session as SessionModel, AdminUser, AuditLog,
)
from app.schemas.schemas import ListenerCreate
from app.utils.security import hash_password
from app.core.ws_manager import manager
#admin
router = APIRouter(prefix="/admin", tags=["admin"])

def verify_admin(authorization: str = Header(...), db: Session = Depends(get_db)) -> AdminUser:
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    token = authorization.removeprefix("Bearer ")
    session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.admin_id.isnot(None)).first()
    if not session:
        raise HTTPException(status_code=401, detail="Invalid session")
    admin = db.query(AdminUser).filter(AdminUser.id == session.admin_id).first()
    if not admin or not admin.is_active:
        raise HTTPException(status_code=401, detail="Invalid session")
    return admin

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
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect_admin(websocket)
    except Exception:
        manager.disconnect_admin(websocket)


@router.post("/listeners")
def create_listener(payload: ListenerCreate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    existing = db.query(Listener).filter(Listener.phone == payload.phone).first()
    if existing:
        raise HTTPException(status_code=400, detail="Phone already registered")
    listener = Listener(
        name=payload.name,
        phone=payload.phone,
        password_hash=hash_password(payload.password),
    )
    db.add(listener)
    db.commit()
    db.refresh(listener)
    return {"id": listener.id, "name": listener.name, "phone": listener.phone}

@router.get("/listeners")
def list_listeners(db: Session = Depends(get_db), _=Depends(verify_admin)):
    listeners = db.query(Listener).all()
    result = [{"id": l.id, "name": l.name, "phone": l.phone, "is_active": l.is_active, "is_online": manager.is_listener_online(l.id)} for l in listeners]
    result.sort(key=lambda x: not x["is_online"])
    return result

@router.patch("/listeners/{listener_id}/active")
async def set_listener_active(listener_id: int, payload: dict, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    listener.is_active = bool(payload.get("is_active"))
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

    db.query(CallRating).filter(CallRating.listener_id == listener_id).delete(synchronize_session=False)
    db.query(ChatMessage).filter(ChatMessage.listener_id == listener_id).delete(synchronize_session=False)
    db.query(SessionModel).filter(SessionModel.listener_id == listener_id).delete(synchronize_session=False)
    if call_ids:
        db.query(CallRecording).filter(CallRecording.call_id.in_(call_ids)).delete(synchronize_session=False)
        db.query(CoinTransaction).filter(CoinTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
    db.query(Call).filter(Call.callee_listener_id == listener_id).delete(synchronize_session=False)

    db.delete(listener)
    db.commit()
    return {"detail": "Listener deleted"}

@router.get("/users")
def list_users(db: Session = Depends(get_db), _=Depends(verify_admin)):
    users = db.query(User).all()
    result = [{"id": u.id, "name": u.name, "email": u.email, "phone": u.phone, "is_active": u.is_active, "coins": u.coins, "is_online": manager.is_user_online(u.id)} for u in users]
    result.sort(key=lambda x: not x["is_online"])
    return result

@router.patch("/users/{user_id}/active")
async def set_user_active(user_id: int, payload: dict, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_active = bool(payload.get("is_active"))
    db.commit()
    if not user.is_active:
        await manager.send_to_user(user_id, {"type": "force_logout"})
    return {"id": user.id, "is_active": user.is_active}

@router.delete("/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    call_ids = [c.id for c in db.query(Call.id).filter(Call.caller_user_id == user_id).all()]

    db.query(CallRating).filter(CallRating.user_id == user_id).delete(synchronize_session=False)
    db.query(ChatMessage).filter(ChatMessage.user_id == user_id).delete(synchronize_session=False)
    db.query(SessionModel).filter(SessionModel.user_id == user_id).delete(synchronize_session=False)
    db.query(CoinTransaction).filter(CoinTransaction.user_id == user_id).delete(synchronize_session=False)
    if call_ids:
        db.query(CallRecording).filter(CallRecording.call_id.in_(call_ids)).delete(synchronize_session=False)
    db.query(Call).filter(Call.caller_user_id == user_id).delete(synchronize_session=False)

    db.delete(user)
    db.commit()
    return {"detail": "User deleted"}

@router.get("/recordings")
def list_recordings(db: Session = Depends(get_db), _=Depends(verify_admin)):
    recordings = db.query(CallRecording).order_by(CallRecording.id.desc()).all()
    result = []
    for r in recordings:
        call = db.query(Call).filter(Call.id == r.call_id).first()
        caller = db.query(User).filter(User.id == call.caller_user_id).first() if call else None
        listener = db.query(Listener).filter(Listener.id == call.callee_listener_id).first() if call else None
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
    calls = db.query(Call).order_by(Call.id.desc()).all()
    result = []
    for c in calls:
        caller = db.query(User).filter(User.id == c.caller_user_id).first()
        listener = db.query(Listener).filter(Listener.id == c.callee_listener_id).first()
        result.append({
            "id": c.id,
            "caller_name": caller.name if caller else None,
            "listener_name": listener.name if listener else None,
            "status": c.status,
            "created_at": c.created_at,
        })
    return result

@router.get("/chats")
def list_chats(db: Session = Depends(get_db), _=Depends(verify_admin)):
    messages = db.query(ChatMessage).order_by(ChatMessage.created_at.desc()).all()
    result = []
    for m in messages:
        user = db.query(User).filter(User.id == m.user_id).first()
        listener = db.query(Listener).filter(Listener.id == m.listener_id).first()
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
    calls = db.query(Call).filter(Call.status.in_(["ringing", "accepted"])).order_by(Call.id.desc()).all()
    result = []
    for c in calls:
        caller = db.query(User).filter(User.id == c.caller_user_id).first()
        listener = db.query(Listener).filter(Listener.id == c.callee_listener_id).first()
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

    q = db.query(Call).filter(Call.status == "ended")
    if since is not None:
        q = q.filter(Call.created_at >= since)
    calls = q.all()

    buckets = {}
    for c in calls:
        ts = c.created_at
        if bucket == "hour":
            key = ts.strftime("%Y-%m-%d %H:00")
        elif bucket == "day":
            key = ts.strftime("%Y-%m-%d")
        elif bucket == "week":
            key = ts.strftime("%Y-W%W")
        else:
            key = ts.strftime("%Y-%m")
        buckets[key] = buckets.get(key, 0) + 1

    series = [{"label": k, "count": v} for k, v in sorted(buckets.items())]

    return {
        "total_users": total_users,
        "active_users": active_users,
        "inactive_users": inactive_users,
        "total_listeners": total_listeners,
        "active_listeners": active_listeners,
        "inactive_listeners": inactive_listeners,
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
