import json
import os
import uuid
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Header
from sqlalchemy.orm import Session
from app.models.models import ChatMessage
from app.core.ws_manager import manager
from app.schemas.schemas import ListenerStatusUpdate
from app.models.models import CallRating
from sqlalchemy import func as sqlfunc
from datetime import datetime, timedelta, timezone
from app.schemas.schemas import UserRegisterInitiate, UserRegisterVerifyOtp, UserLogin, AuthResponse, FcmTokenUpdate, UserBioUpdate, UserForgotPasswordRequestOtp, UserForgotPasswordVerifyOtp, UserForgotPasswordReset, UserChangePassword
from app.core.database import get_db
from app.models.models import User, Session as SessionModel, EmailOtp
from app.utils.email_otp import generate_otp_code, send_otp_email
from app.utils.security import hash_password, verify_password, generate_session_token
from app.utils.audit import record_audit_event
from app.models.models import Listener
from app.core.deps import get_current_user
from app.utils.coins import chat_message_coin_cost

router = APIRouter(prefix="/user", tags=["user-auth"])

@router.get("/session/check")
def session_check(current_user: User = Depends(get_current_user)):
    return {"valid": True, "is_active": current_user.is_active}


@router.post("/register/initiate")
def register_initiate(payload: UserRegisterInitiate, db: Session = Depends(get_db)):
    existing_user = db.query(User).filter(
        (User.phone == payload.phone) | (User.email == payload.email)
    ).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Phone or email already registered")

    otp_code = generate_otp_code()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=1)

    db.query(EmailOtp).filter(EmailOtp.email == payload.email).delete()
    db.add(EmailOtp(
        email=payload.email,
        otp_code=otp_code,
        name=payload.name,
        phone=payload.phone,
        password_hash=hash_password(payload.password),
        expires_at=expires_at,
    ))
    db.commit()

    send_otp_email(payload.email, otp_code)
    return {"status": "otp_sent"}


@router.post("/register/verify-otp", response_model=AuthResponse)
def register_verify_otp(payload: UserRegisterVerifyOtp, db: Session = Depends(get_db)):
    record = db.query(EmailOtp).filter(EmailOtp.email == payload.email).order_by(EmailOtp.id.desc()).first()
    if not record:
        raise HTTPException(status_code=400, detail="No OTP request found")
    if record.otp_code != payload.otp_code:
        raise HTTPException(status_code=400, detail="Invalid OTP")
    if record.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP expired")

    existing_user = db.query(User).filter(
        (User.phone == record.phone) | (User.email == record.email)
    ).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Phone or email already registered")

    user = User(
        name=record.name,
        email=record.email,
        phone=record.phone,
        password_hash=record.password_hash,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    db.query(EmailOtp).filter(EmailOtp.email == payload.email).delete()
    db.commit()

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
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = generate_session_token()
    db.add(SessionModel(token=token, user_id=user.id))
    record_audit_event(db, "user", user.id, user.name, "login")
    db.commit()
    return AuthResponse(token=token, id=user.id, name=user.name)


@router.post("/logout")
def logout(authorization: str = Header(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    token = authorization.replace("Bearer ", "")
    db.query(SessionModel).filter(SessionModel.token == token).delete()
    record_audit_event(db, "user", current_user.id, current_user.name, "logout")
    db.commit()
    return {"status": "logged_out"}


@router.post("/forgot-password/request-otp")
def forgot_password_request_otp(payload: UserForgotPasswordRequestOtp, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if not user:
        raise HTTPException(status_code=404, detail="enter a registered email id")

    otp_code = generate_otp_code()
    user.reset_otp_code = otp_code
    user.reset_otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=1)
    db.commit()

    send_otp_email(payload.email, otp_code)
    return {"status": "otp_sent"}


@router.post("/forgot-password/verify-otp")
def forgot_password_verify_otp(payload: UserForgotPasswordVerifyOtp, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if not user:
        raise HTTPException(status_code=404, detail="enter a registered email id")
    if not user.reset_otp_code or user.reset_otp_code != payload.otp_code:
        raise HTTPException(status_code=400, detail="Invalid OTP")
    if not user.reset_otp_expires_at or user.reset_otp_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP expired")

    return {"status": "otp_verified"}


@router.post("/forgot-password/reset")
def forgot_password_reset(payload: UserForgotPasswordReset, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if not user:
        raise HTTPException(status_code=404, detail="enter a registered email id")
    if not user.reset_otp_code or user.reset_otp_code != payload.otp_code:
        raise HTTPException(status_code=400, detail="Invalid OTP")
    if not user.reset_otp_expires_at or user.reset_otp_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP expired")

    if verify_password(payload.new_password, user.password_hash):
        raise HTTPException(status_code=400, detail="New password must be different from your current password")

    user.password_hash = hash_password(payload.new_password)
    user.reset_otp_code = None
    user.reset_otp_expires_at = None
    db.commit()

    return {"status": "password_reset"}


@router.post("/change-password")
def change_password(payload: UserChangePassword, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if not verify_password(payload.current_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if verify_password(payload.new_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="New password must be different from your current password")
    current_user.password_hash = hash_password(payload.new_password)
    db.commit()
    return {"status": "password_changed"}


@router.get("/listeners")
def get_listeners(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    listeners = db.query(Listener).filter(Listener.is_active == True).all()
    listener_ids = [l.id for l in listeners]
    rating_rows = db.query(
        CallRating.listener_id,
        sqlfunc.avg(CallRating.rating),
        sqlfunc.count(CallRating.id),
    ).filter(CallRating.listener_id.in_(listener_ids)).group_by(CallRating.listener_id).all()
    ratings_by_listener = {r[0]: (r[1], r[2]) for r in rating_rows}

    result = []
    for l in listeners:
        avg_rating, rating_count = ratings_by_listener.get(l.id, (None, 0))
        try:
            tags = json.loads(l.tags) if l.tags else []
        except (TypeError, json.JSONDecodeError):
            tags = []
        result.append({
            "id": l.id, "name": l.name, "is_online": bool(l.is_online) and manager.is_listener_online(l.id),
            "tags": tags,
            "avg_rating": round(avg_rating, 1) if avg_rating else None,
            "rating_count": rating_count or 0,
            "photo_url": l.photo_url,
        })
    return result

@router.get("/listener/{listener_id}")
def get_listener_profile(listener_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    l = db.query(Listener).filter(Listener.id == listener_id, Listener.is_active == True).first()
    if not l:
        raise HTTPException(status_code=404, detail="Listener not found")
    avg_rating = db.query(sqlfunc.avg(CallRating.rating)).filter(CallRating.listener_id == l.id).scalar()
    rating_count = db.query(sqlfunc.count(CallRating.id)).filter(CallRating.listener_id == l.id).scalar()
    try:
        tags = json.loads(l.tags) if l.tags else []
    except Exception:
        tags = []
    try:
        languages = json.loads(l.languages) if l.languages else []
    except Exception:
        languages = []
    return {
        "id": l.id,
        "name": l.name,
        "is_online": bool(l.is_online) and manager.is_listener_online(l.id),
        "about": l.about,
        "tags": tags,
        "languages": languages,
        "avg_rating": round(avg_rating, 1) if avg_rating else None,
        "rating_count": rating_count or 0,
        "created_at": l.created_at.isoformat() if l.created_at else None,
        "photo_url": l.photo_url,
    }

    
@router.get("/me")
def get_me(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "name": current_user.name,
        "email": current_user.email,
        "phone": current_user.phone,
        "coins": current_user.coins,
        "chat_message_coin_cost": chat_message_coin_cost(db),
        "bio": current_user.bio,
        "photo_url": current_user.photo_url,
    }

@router.post("/bio")
def update_bio(payload: UserBioUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    current_user.bio = payload.bio
    db.commit()
    return {"status": "updated", "bio": current_user.bio}

@router.post("/photo")
async def update_photo(file: UploadFile = File(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    ext = os.path.splitext(file.filename)[1] or ".jpg"
    filename = f"user_{current_user.id}_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("profile_photos", filename)
    with open(filepath, "wb") as f:
        f.write(await file.read())
    current_user.photo_url = f"/profile_photos/{filename}"
    db.commit()
    return {"status": "updated", "photo_url": current_user.photo_url}

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
    event_type = "user_online" if payload.is_online else "user_offline"
    await manager.broadcast_to_all_listeners({"type": event_type, "user_id": current_user.id})
    return {"status": "updated"}
