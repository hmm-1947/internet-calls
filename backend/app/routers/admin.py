from fastapi import APIRouter, Depends, HTTPException, Header, WebSocket, WebSocketDisconnect, Query
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.config import settings
from app.models.models import (
    Listener, User, Call, CallRecording, ChatMessage,
    CoinTransaction, CallRating, Session as SessionModel,
)
from app.schemas.schemas import ListenerCreate
from app.utils.security import hash_password
from app.core.ws_manager import manager
#admin
router = APIRouter(prefix="/admin", tags=["admin"])

def verify_admin(x_admin_secret: str = Header(...)):
    if x_admin_secret != settings.admin_secret:
        raise HTTPException(status_code=403, detail="Forbidden")

@router.websocket("/ws")
async def admin_ws(websocket: WebSocket, secret: str = Query(...)):
    if secret != settings.admin_secret:
        await websocket.close(code=4003)
        return
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