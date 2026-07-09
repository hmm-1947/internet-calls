from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.models.models import ChatMessage
from app.core.ws_manager import manager
from app.schemas.schemas import ListenerStatusUpdate
from app.models.models import CallRating
from sqlalchemy import func as sqlfunc
from app.schemas.schemas import UserRegister, UserLogin, AuthResponse, FcmTokenUpdate
from app.core.database import get_db
from app.models.models import User, Session as SessionModel
from app.schemas.schemas import UserRegister, UserLogin, AuthResponse
from app.utils.security import hash_password, verify_password, generate_session_token
from app.models.models import Listener
from app.core.deps import get_current_user

router = APIRouter(prefix="/user", tags=["user-auth"])

@router.post("/register", response_model=AuthResponse)
def register(payload: UserRegister, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.phone == payload.phone).first()
    if existing:
        raise HTTPException(status_code=400, detail="Phone already registered")
    user = User(
        name=payload.name,
        phone=payload.phone,
        password_hash=hash_password(payload.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    token = generate_session_token()
    db.add(SessionModel(token=token, user_id=user.id))
    db.commit()
    return AuthResponse(token=token, id=user.id, name=user.name)

@router.post("/login", response_model=AuthResponse)
def login(payload: UserLogin, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.phone == payload.phone).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")
    token = generate_session_token()
    db.add(SessionModel(token=token, user_id=user.id))
    db.commit()
    return AuthResponse(token=token, id=user.id, name=user.name)


@router.get("/listeners")
def get_listeners(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    listeners = db.query(Listener).filter(Listener.is_active == True).all()
    result = []
    for l in listeners:
        avg_rating = db.query(sqlfunc.avg(CallRating.rating)).filter(CallRating.listener_id == l.id).scalar()
        rating_count = db.query(sqlfunc.count(CallRating.id)).filter(CallRating.listener_id == l.id).scalar()
        result.append({
            "id": l.id, "name": l.name, "is_online": manager.is_listener_online(l.id),
            "avg_rating": round(avg_rating, 1) if avg_rating else None,
            "rating_count": rating_count or 0,
        })
    return result
    
@router.get("/me")
def get_me(current_user: User = Depends(get_current_user)):
    return {"id": current_user.id, "name": current_user.name, "phone": current_user.phone, "coins": current_user.coins}

@router.post("/fcm-token")
def update_fcm_token(payload: FcmTokenUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Store the user's FCM token so the backend can push call_rejected events."""
    if not payload.fcm_token:
        raise HTTPException(status_code=400, detail="fcm_token is required")
    current_user.fcm_token = payload.fcm_token
    db.commit()
    return {"status": "ok"}

@router.post("/status")
async def update_status(payload: ListenerStatusUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    listener_ids = [r[0] for r in db.query(ChatMessage.listener_id).filter(ChatMessage.user_id == current_user.id).distinct().all()]
    event_type = "user_online" if payload.is_online else "user_offline"
    for lid in listener_ids:
        await manager.send_to_listener(lid, {"type": event_type, "user_id": current_user.id})
    return {"status": "updated"}