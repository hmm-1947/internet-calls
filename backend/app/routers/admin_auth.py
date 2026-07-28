import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models.models import AdminUser, AdminInvite, Session as SessionModel
from app.routers.admin import verify_admin
from app.schemas.schemas import (
    AdminInviteCreate,
    AdminInviteRequestOtp,
    AdminInviteVerifyOtp,
    AdminInviteComplete,
    AdminLogin,
    AdminForgotPasswordRequestOtp,
    AdminForgotPasswordVerifyOtp,
    AdminForgotPasswordReset,
    AdminAuthResponse,
)

from app.utils.email_otp import generate_otp_code, send_otp_email
from app.utils.security import hash_password, verify_password, generate_session_token, session_expiry

router = APIRouter(prefix="/admin/auth", tags=["admin-auth"])


@router.post("/invite")
def create_invite(payload: AdminInviteCreate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    existing = (
        db.query(AdminInvite)
        .filter(AdminInvite.is_used.is_(False))
        .filter(AdminInvite.expires_at > datetime.now(timezone.utc))
        .order_by(AdminInvite.expires_at.desc())
        .first()
    )
    if existing:
        return {"invite_token": existing.token, "expires_at": existing.expires_at}
    token = secrets.token_urlsafe(24)
    expires_at = datetime.now(timezone.utc) + timedelta(hours=payload.expires_in_hours or 72)
    invite = AdminInvite(token=token, expires_at=expires_at)
    db.add(invite)
    db.commit()
    return {"invite_token": token, "expires_at": expires_at}


@router.post("/invite/request-otp")
def request_invite_otp(payload: AdminInviteRequestOtp, db: Session = Depends(get_db)):
    invite = db.query(AdminInvite).filter(AdminInvite.token == payload.invite_token).first()
    if not invite:
        raise HTTPException(status_code=404, detail="Invalid invite link")
    if invite.is_used:
        raise HTTPException(status_code=400, detail="Invite already used")
    if invite.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Invite link expired")

    existing = db.query(AdminUser).filter(AdminUser.email == payload.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    otp_code = generate_otp_code()
    invite.email = payload.email
    invite.otp_code = otp_code
    invite.otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
    invite.otp_attempts = 0
    invite.email_verified = False
    db.commit()

    send_otp_email(payload.email, otp_code)
    return {"status": "otp_sent"}


MAX_OTP_ATTEMPTS = 5


@router.post("/invite/verify-otp")
def verify_invite_otp(payload: AdminInviteVerifyOtp, db: Session = Depends(get_db)):
    invite = db.query(AdminInvite).filter(AdminInvite.token == payload.invite_token).first()
    if not invite:
        raise HTTPException(status_code=404, detail="Invalid invite link")
    if invite.is_used:
        raise HTTPException(status_code=400, detail="Invite already used")
    if invite.email != payload.email:
        raise HTTPException(status_code=400, detail="Email does not match this invite")
    if not invite.otp_expires_at or invite.otp_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP expired")
    if invite.otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Please request a new OTP.")
    if not invite.otp_code or invite.otp_code != payload.otp_code:
        invite.otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")

    invite.email_verified = True
    invite.otp_attempts = 0
    db.commit()
    return {"status": "email_verified"}


@router.post("/invite/complete", response_model=AdminAuthResponse)
def complete_invite(payload: AdminInviteComplete, db: Session = Depends(get_db)):
    invite = db.query(AdminInvite).filter(AdminInvite.token == payload.invite_token).first()
    if not invite:
        raise HTTPException(status_code=404, detail="Invalid invite link")
    if invite.is_used:
        raise HTTPException(status_code=400, detail="Invite already used")
    if not invite.email_verified:
        raise HTTPException(status_code=400, detail="Email not verified")
    if invite.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Invite link expired")

    existing_username = db.query(AdminUser).filter(AdminUser.username == payload.username).first()
    if existing_username:
        raise HTTPException(status_code=400, detail="Username already taken")

    admin = AdminUser(
        username=payload.username,
        email=invite.email,
        password_hash=hash_password(payload.password),
    )
    db.add(admin)
    invite.is_used = True
    db.commit()
    db.refresh(admin)

    token = generate_session_token()
    db.add(SessionModel(token=token, admin_id=admin.id, expires_at=session_expiry()))

    db.commit()

    return AdminAuthResponse(token=token, id=admin.id, username=admin.username, email=admin.email)



@router.post("/forgot-password/request-otp")
def forgot_password_request_otp(payload: AdminForgotPasswordRequestOtp, db: Session = Depends(get_db)):
    admin = db.query(AdminUser).filter(AdminUser.email == payload.email).first()
    if not admin:
        raise HTTPException(status_code=404, detail="Email not registered")

    otp_code = generate_otp_code()
    admin.reset_otp_code = otp_code
    admin.reset_otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
    admin.reset_otp_attempts = 0
    db.commit()

    send_otp_email(payload.email, otp_code)
    return {"status": "otp_sent"}


@router.post("/forgot-password/verify-otp")
def forgot_password_verify_otp(payload: AdminForgotPasswordVerifyOtp, db: Session = Depends(get_db)):
    admin = db.query(AdminUser).filter(AdminUser.email == payload.email).first()
    if not admin:
        raise HTTPException(status_code=404, detail="Email not registered")
    if not admin.reset_otp_expires_at or admin.reset_otp_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP expired")
    if admin.reset_otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Please request a new OTP.")
    if not admin.reset_otp_code or admin.reset_otp_code != payload.otp_code:
        admin.reset_otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")

    return {"status": "otp_verified"}


@router.post("/forgot-password/reset")
def forgot_password_reset(payload: AdminForgotPasswordReset, db: Session = Depends(get_db)):
    admin = db.query(AdminUser).filter(AdminUser.email == payload.email).first()
    if not admin:
        raise HTTPException(status_code=404, detail="Email not registered")
    if not admin.reset_otp_expires_at or admin.reset_otp_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP expired")
    if admin.reset_otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Please request a new OTP.")
    if not admin.reset_otp_code or admin.reset_otp_code != payload.otp_code:
        admin.reset_otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")

    if verify_password(payload.new_password, admin.password_hash):
        raise HTTPException(status_code=400, detail="New password must be different from your current password")

    admin.password_hash = hash_password(payload.new_password)
    admin.reset_otp_code = None
    admin.reset_otp_expires_at = None
    admin.reset_otp_attempts = 0
    db.query(SessionModel).filter(SessionModel.admin_id == admin.id).delete()
    db.commit()

    return {"status": "password_reset"}


MAX_LOGIN_ATTEMPTS = 5
LOGIN_LOCKOUT_MINUTES = 15


@router.post("/login", response_model=AdminAuthResponse)
def admin_login(payload: AdminLogin, db: Session = Depends(get_db)):
    admin = db.query(AdminUser).filter(
        (AdminUser.username == payload.identifier) | (AdminUser.email == payload.identifier)
    ).first()

    if admin and admin.locked_until and admin.locked_until > datetime.now(timezone.utc):
        raise HTTPException(status_code=429, detail="Account temporarily locked due to too many failed attempts. Try again later.")

    if not admin or not verify_password(payload.password, admin.password_hash):
        if admin:
            admin.failed_login_attempts += 1
            if admin.failed_login_attempts >= MAX_LOGIN_ATTEMPTS:
                admin.locked_until = datetime.now(timezone.utc) + timedelta(minutes=LOGIN_LOCKOUT_MINUTES)
                admin.failed_login_attempts = 0
            db.commit()
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not admin.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")

    admin.failed_login_attempts = 0
    admin.locked_until = None

    token = generate_session_token()
    db.add(SessionModel(token=token, admin_id=admin.id, expires_at=session_expiry()))

    db.commit()

    return AdminAuthResponse(token=token, id=admin.id, username=admin.username, email=admin.email)



