from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.orm import Session
from sqlalchemy import func as sa_func
from app.core.database import get_db
from app.models.models import Listener, Session as SessionModel, Call
from datetime import datetime, timezone
from app.models.models import ChatMessage
from app.core.ws_manager import manager
from app.schemas.schemas import ListenerLogin, AuthResponse, ListenerStatusUpdate, FcmTokenUpdate
from app.utils.security import verify_password, generate_session_token
from app.core.deps import get_current_listener

router = APIRouter(prefix="/listener", tags=["listener-auth"])

@router.get("/me")
def get_me(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    total_seconds = db.query(sa_func.coalesce(sa_func.sum(Call.duration_seconds), 0)).filter(
        Call.callee_listener_id == current_listener.id
    ).scalar()
    return {
        "id": current_listener.id,
        "name": current_listener.name,
        "phone": current_listener.phone,
        "total_talk_time_seconds": int(total_seconds),
    }

@router.post("/login", response_model=AuthResponse)
def login(payload: ListenerLogin, db: Session = Depends(get_db)):
    listener = db.query(Listener).filter(Listener.phone == payload.phone).first()
    if not listener or not verify_password(payload.password, listener.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not listener.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")
    token = generate_session_token()
    db.add(SessionModel(token=token, listener_id=listener.id))
    listener.is_online = True
    db.commit()
    return AuthResponse(token=token, id=listener.id, name=listener.name)

@router.post("/status")
async def update_status(payload: ListenerStatusUpdate, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    current_listener.is_online = payload.is_online
    if not payload.is_online:
        current_listener.last_seen = datetime.now(timezone.utc)
    db.commit()
    user_ids = [r[0] for r in db.query(ChatMessage.user_id).filter(ChatMessage.listener_id == current_listener.id).distinct().all()]
    event_type = "listener_online" if payload.is_online else "listener_offline"
    payload_out = {"type": event_type, "listener_id": current_listener.id}
    if not payload.is_online:
        payload_out["last_seen"] = current_listener.last_seen.isoformat()
    for uid in user_ids:
        await manager.send_to_user(uid, payload_out)
    return {"status": "updated", "is_online": current_listener.is_online}


@router.post("/logout")
async def logout(authorization: str = Header(...), db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    token = authorization.replace("Bearer ", "")
    db.query(SessionModel).filter(SessionModel.token == token).delete()
    current_listener.is_online = False
    current_listener.last_seen = datetime.now(timezone.utc)
    db.commit()
    manager.disconnect_listener(current_listener.id)
    user_ids = [r[0] for r in db.query(ChatMessage.user_id).filter(ChatMessage.listener_id == current_listener.id).distinct().all()]
    for uid in user_ids:
        await manager.send_to_user(uid, {
            "type": "listener_offline",
            "listener_id": current_listener.id,
            "last_seen": current_listener.last_seen.isoformat(),
        })
    return {"status": "logged_out"}

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
        {"id": u.id, "name": u.name, "is_online": manager.is_user_online(u.id)}
        for u in users
    ]