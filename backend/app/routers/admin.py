from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.orm import Session
from app.models.models import CallRecording
from app.core.database import get_db
from app.core.config import settings
from app.models.models import Listener
from app.models.models import CallRecording, ChatMessage
from app.schemas.schemas import ListenerCreate
from app.models.models import Call, User
from app.utils.security import hash_password
#admin
router = APIRouter(prefix="/admin", tags=["admin"])

def verify_admin(x_admin_secret: str = Header(...)):
    if x_admin_secret != settings.admin_secret:
        raise HTTPException(status_code=403, detail="Forbidden")

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
    return [{"id": l.id, "name": l.name, "phone": l.phone, "is_active": l.is_active, "is_online": l.is_online} for l in listeners]

@router.delete("/listeners/{listener_id}")
def delete_listener(listener_id: int, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    db.delete(listener)
    db.commit()
    return {"detail": "Listener deleted"}

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