import hashlib
import hmac
import os
import re
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

import requests
from fastapi import APIRouter, Depends, Header, HTTPException, Request, UploadFile, File
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.models.models import AdminUser, AdminInvite, AdminAuditLog, Session as SessionModel
from app.routers.admin import verify_admin
from app.schemas.schemas import (
    AdminInviteCreate,
    AdminInviteRequestOtp,
    AdminInviteVerifyOtp,
    AdminInviteComplete,
    AdminLogin,
    AdminLoginVerifyOtp,
    AdminLogout,
    AdminForgotPasswordRequestOtp,
    AdminForgotPasswordVerifyOtp,
    AdminForgotPasswordReset,
    AdminAuthResponse,
    AdminProfileOut,
    AdminProfileUpdate,
    AdminChangePassword,
    CurrentPasswordCheck,
    validate_password_strength,
    EMAIL_PATTERN,
)

from app.utils.email_otp import generate_otp_code, send_otp_email
from app.utils.rate_limit import client_ip, enforce_rate_limit
from app.utils.security import hash_password, verify_password, generate_session_token, session_expiry
from app.utils.uploads import read_and_validate_image, write_file

router = APIRouter(prefix="/admin/auth", tags=["admin-auth"])


@router.post("/invite")
def create_invite(payload: AdminInviteCreate, db: Session = Depends(get_db), admin: AdminUser = Depends(verify_admin)):
    if getattr(admin, "is_support", False):
        raise HTTPException(status_code=403, detail="Not allowed")
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
    expires_at = datetime.now(timezone.utc) + timedelta(hours=min(max(payload.expires_in_hours or 72, 1), 168))
    invite = AdminInvite(token=token, expires_at=expires_at)
    db.add(invite)
    db.commit()
    return {"invite_token": token, "expires_at": expires_at}


@router.get("/admins")
def list_admins(db: Session = Depends(get_db), _=Depends(verify_admin)):
    last_login = dict(
        db.query(AdminAuditLog.admin_id, func.max(AdminAuditLog.created_at))
        .filter(AdminAuditLog.action == "login")
        .group_by(AdminAuditLog.admin_id)
        .all()
    )
    admins = db.query(AdminUser).order_by(AdminUser.created_at.asc(), AdminUser.id.asc()).all()
    return [
        {
            "id": a.id,
            "username": a.username,
            "email": a.email,
            "is_active": bool(a.is_active),
            "created_at": a.created_at,
            "last_login_at": last_login.get(a.id),
        }
        for a in admins
    ]


@router.post("/invite/request-otp")
def request_invite_otp(payload: AdminInviteRequestOtp, db: Session = Depends(get_db)):
    invite = db.query(AdminInvite).filter(AdminInvite.token == payload.invite_token).first()
    if not invite:
        raise HTTPException(status_code=404, detail="Invalid invite link")
    if invite.is_used:
        raise HTTPException(status_code=400, detail="Invite already used")
    if invite.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Invite link expired")

    if invite.email_verified:
        raise HTTPException(status_code=400, detail="This invite is already being completed")

    email = (payload.email or "").strip().lower()
    if not EMAIL_PATTERN.match(email):
        raise HTTPException(status_code=400, detail="Enter a valid email address")
    existing = db.query(AdminUser).filter(func.lower(AdminUser.email) == email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    enforce_rate_limit(
        "admin_invite_otp", payload.invite_token, limit=5, window_seconds=600,
        detail="Too many codes requested. Please wait a few minutes and try again.",
    )
    otp_code = generate_otp_code()
    invite.email = email
    invite.otp_code = _hash_login_otp(otp_code)
    invite.otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
    invite.otp_attempts = 0
    invite.email_verified = False
    db.commit()

    send_otp_email(email, otp_code, purpose="invite")
    return {"status": "otp_sent"}


MAX_OTP_ATTEMPTS = 5


@router.post("/invite/verify-otp")
def verify_invite_otp(payload: AdminInviteVerifyOtp, request: Request, db: Session = Depends(get_db)):
    enforce_rate_limit("admin_invite_verify", client_ip(request), limit=20, window_seconds=600)
    enforce_rate_limit("admin_invite_verify_token", payload.invite_token, limit=10, window_seconds=600)
    invite = db.query(AdminInvite).filter(AdminInvite.token == payload.invite_token).first()
    if not invite:
        raise HTTPException(status_code=404, detail="Invalid invite link")
    if invite.is_used:
        raise HTTPException(status_code=400, detail="Invite already used")
    if invite.email != (payload.email or "").strip().lower():
        raise HTTPException(status_code=400, detail="Email does not match this invite")
    if not invite.otp_expires_at or invite.otp_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP expired")
    if invite.otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Please request a new OTP.")
    if not invite.otp_code or not hmac.compare_digest(_hash_login_otp((payload.otp_code or "").strip()), invite.otp_code):
        invite.otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")

    invite.email_verified = True
    invite.otp_attempts = 0
    db.commit()
    return {"status": "email_verified"}


@router.post("/invite/complete", response_model=AdminAuthResponse)
def complete_invite(payload: AdminInviteComplete, request: Request, db: Session = Depends(get_db)):
    enforce_rate_limit("admin_invite_complete", client_ip(request), limit=10, window_seconds=600)
    enforce_rate_limit("admin_invite_complete_token", payload.invite_token, limit=10, window_seconds=600)
    lat, lng = payload.latitude, payload.longitude
    if lat is None or lng is None or not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
        raise HTTPException(status_code=400, detail="Location access is required to create your account. Please allow location permission and try again.")
    invite = db.query(AdminInvite).filter(AdminInvite.token == payload.invite_token).with_for_update().first()
    if not invite:
        raise HTTPException(status_code=404, detail="Invalid invite link")
    if invite.is_used:
        raise HTTPException(status_code=400, detail="Invite already used")
    if not invite.email_verified:
        raise HTTPException(status_code=400, detail="Email not verified")
    if invite.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Invite link expired")

    username = (payload.username or "").strip()
    if not re.fullmatch(r"[A-Za-z0-9_.-]{3,32}", username):
        raise HTTPException(status_code=400, detail="Username must be 3-32 characters: letters, numbers, dot, dash or underscore")
    existing_username = db.query(AdminUser).filter(func.lower(AdminUser.username) == username.lower()).first()
    if existing_username:
        raise HTTPException(status_code=400, detail="Username already taken")

    admin = AdminUser(
        username=username,
        email=invite.email,
        password_hash=hash_password(payload.password),
    )
    db.add(admin)
    invite.is_used = True
    db.commit()
    db.refresh(admin)

    token = generate_session_token()
    db.add(SessionModel(token=token, admin_id=admin.id, expires_at=session_expiry()))
    db.add(
        AdminAuditLog(
            admin_id=admin.id,
            admin_username=admin.username,
            action="login",
            ip_address=client_ip(request),
            latitude=lat,
            longitude=lng,
            accuracy_m=payload.accuracy_m,
            location_label=(payload.location_label or "").strip()[:255] or None,
        )
    )
    db.commit()

    return AdminAuthResponse(token=token, id=admin.id, username=admin.username, email=admin.email)



def _profile_out(admin: AdminUser) -> AdminProfileOut:
    return AdminProfileOut(id=admin.id, username=admin.username, email=admin.email, phone=admin.phone, photo_url=admin.photo_url)


@router.get("/me", response_model=AdminProfileOut)
def get_admin_profile(admin: AdminUser = Depends(verify_admin)):
    return _profile_out(admin)


@router.post("/me/photo", response_model=AdminProfileOut)
async def update_admin_photo(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_admin: AdminUser = Depends(verify_admin),
):
    admin = db.query(AdminUser).filter(AdminUser.id == current_admin.id).first()
    if not admin:
        raise HTTPException(status_code=404, detail="Admin not found")

    contents, ext = await read_and_validate_image(file)
    filename = f"admin_{admin.id}_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("profile_photos", filename)
    await write_file(filepath, contents)
    admin.photo_url = f"/profile_photos/{filename}"
    db.commit()
    db.refresh(admin)

    return _profile_out(admin)


@router.patch("/me", response_model=AdminProfileOut)
def update_admin_profile(
    payload: AdminProfileUpdate,
    db: Session = Depends(get_db),
    current_admin: AdminUser = Depends(verify_admin),
):
    # Re-read through this request's session so the row is always attached to `db`.
    admin = db.query(AdminUser).filter(AdminUser.id == current_admin.id).first()
    if not admin:
        raise HTTPException(status_code=404, detail="Admin not found")

    if payload.email != (admin.email or "").strip().lower():
        clash = (
            db.query(AdminUser)
            .filter(func.lower(AdminUser.email) == payload.email, AdminUser.id != admin.id)
            .first()
        )
        if clash:
            raise HTTPException(
                status_code=400,
                detail=f"Email already in use by another admin account (@{clash.username})",
            )
        # A new recovery email invalidates any pending password reset OTP.
        admin.reset_otp_code = None
        admin.reset_otp_expires_at = None
        admin.reset_otp_attempts = 0

    admin.email = payload.email
    admin.phone = payload.phone
    db.commit()
    db.refresh(admin)

    return _profile_out(admin)


@router.post("/me/verify-password")
def verify_admin_current_password(
    payload: CurrentPasswordCheck,
    db: Session = Depends(get_db),
    current_admin: AdminUser = Depends(verify_admin),
):
    """Checks only whether the current password is correct. Used by the admin
    panel to surface that error before evaluating confirm-password / rules."""
    admin = db.query(AdminUser).filter(AdminUser.id == current_admin.id).first()
    if not admin:
        raise HTTPException(status_code=404, detail="Admin not found")
    if not verify_password(payload.current_password, admin.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    return {"status": "ok"}


@router.post("/me/change-password")
def change_admin_password(
    payload: AdminChangePassword,
    db: Session = Depends(get_db),
    current_admin: AdminUser = Depends(verify_admin),
):
    admin = db.query(AdminUser).filter(AdminUser.id == current_admin.id).first()
    if not admin:
        raise HTTPException(status_code=404, detail="Admin not found")

    if not verify_password(payload.current_password, admin.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if verify_password(payload.new_password, admin.password_hash):
        raise HTTPException(status_code=400, detail="New password must be different from your current password")
    try:
        validate_password_strength(payload.new_password)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    admin.password_hash = hash_password(payload.new_password)
    db.query(SessionModel).filter(SessionModel.admin_id == admin.id).delete()
    db.commit()
    return {"status": "password_changed"}


def _find_admin_by_email(db: Session, email: str) -> Optional[AdminUser]:
    """Admins are looked up case-insensitively so the email saved in Edit Profile always matches."""
    normalized = (email or "").strip().lower()
    if not normalized:
        return None
    return db.query(AdminUser).filter(func.lower(AdminUser.email) == normalized).first()


@router.post("/forgot-password/request-otp")
def forgot_password_request_otp(payload: AdminForgotPasswordRequestOtp, request: Request, db: Session = Depends(get_db)):
    enforce_rate_limit(
        "admin_reset_otp_ip", client_ip(request), limit=10, window_seconds=600,
        detail="Too many codes requested. Please wait a few minutes and try again.",
    )
    enforce_rate_limit(
        "admin_reset_otp", (payload.email or "").strip().lower(), limit=5, window_seconds=600,
        detail="Too many codes requested. Please wait a few minutes and try again.",
    )
    admin = _find_admin_by_email(db, payload.email)
    if not admin:
        return {"status": "otp_sent"}

    otp_code = generate_otp_code()
    admin.reset_otp_code = _hash_login_otp(otp_code)
    admin.reset_otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
    admin.reset_otp_attempts = 0
    db.commit()

    # Always send to the email stored on the admin profile, never to the raw input.
    send_otp_email(admin.email, otp_code, purpose="reset")
    return {"status": "otp_sent"}


@router.post("/forgot-password/verify-otp")
def forgot_password_verify_otp(payload: AdminForgotPasswordVerifyOtp, db: Session = Depends(get_db)):
    admin = _find_admin_by_email(db, payload.email)
    if not admin:
        raise HTTPException(status_code=400, detail="Invalid or expired code")
    if not admin.reset_otp_expires_at or admin.reset_otp_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP expired")
    if admin.reset_otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Please request a new OTP.")
    if not admin.reset_otp_code or not hmac.compare_digest(_hash_login_otp((payload.otp_code or "").strip()), admin.reset_otp_code):
        admin.reset_otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")

    return {"status": "otp_verified"}


@router.post("/forgot-password/reset")
def forgot_password_reset(payload: AdminForgotPasswordReset, db: Session = Depends(get_db)):
    admin = _find_admin_by_email(db, payload.email)
    if not admin:
        raise HTTPException(status_code=400, detail="Invalid or expired code")
    if not admin.reset_otp_expires_at or admin.reset_otp_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP expired")
    if admin.reset_otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Please request a new OTP.")
    if not admin.reset_otp_code or not hmac.compare_digest(_hash_login_otp((payload.otp_code or "").strip()), admin.reset_otp_code):
        admin.reset_otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")

    if verify_password(payload.new_password, admin.password_hash):
        raise HTTPException(status_code=400, detail="New password must be different from your current password")

    admin.password_hash = hash_password(payload.new_password)
    admin.reset_otp_code = None
    admin.reset_otp_expires_at = None
    admin.reset_otp_attempts = 0
    admin.failed_login_attempts = 0
    admin.locked_until = None
    db.query(SessionModel).filter(SessionModel.admin_id == admin.id).delete()
    db.commit()

    return {"status": "password_reset"}


@router.post("/unlock/verify-otp", response_model=AdminAuthResponse)
def unlock_verify_otp(payload: AdminForgotPasswordVerifyOtp, db: Session = Depends(get_db)):
    admin = _find_admin_by_email(db, payload.email)
    if not admin:
        raise HTTPException(status_code=400, detail="Invalid or expired code")
    if not admin.reset_otp_expires_at or admin.reset_otp_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="OTP expired")
    if admin.reset_otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Please request a new OTP.")
    if not admin.reset_otp_code or not hmac.compare_digest(_hash_login_otp((payload.otp_code or "").strip()), admin.reset_otp_code):
        admin.reset_otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")
    if not admin.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")

    admin.failed_login_attempts = 0
    admin.locked_until = None
    admin.reset_otp_code = None
    admin.reset_otp_expires_at = None
    admin.reset_otp_attempts = 0

    token = generate_session_token()
    db.add(SessionModel(token=token, admin_id=admin.id, expires_at=session_expiry()))
    db.commit()

    return AdminAuthResponse(token=token, id=admin.id, username=admin.username, email=admin.email)


LOGIN_OTP_TTL_MINUTES = 5


def _hash_login_otp(code: str) -> str:
    return hashlib.sha256(code.encode()).hexdigest()


def _mask_email(email: str) -> str:
    name, _, domain = email.partition("@")
    return (name[:1] + "***" if name else "***") + "@" + domain


MAX_LOGIN_ATTEMPTS = 6
LOGIN_ATTEMPT_WINDOW_HOURS = 24
_unknown_login_attempts: dict = {}
LOGIN_LOCKED_MESSAGE = "Account locked after 6 failed login attempts. Use 'Forgot password' to reset your password and unlock it."


def _verify_recaptcha(token: str) -> bool:
    if not settings.recaptcha_secret_key:
        # Not configured — don't block login, but this should be set in production.
        return True
    if not token:
        return False
    try:
        resp = requests.post(
            "https://www.google.com/recaptcha/api/siteverify",
            data={"secret": settings.recaptcha_secret_key, "response": token},
            timeout=6,
        )
        result = resp.json()
        return bool(result.get("success"))
    except requests.RequestException:
        return False


@router.post("/login")
def admin_login(payload: AdminLogin, request: Request, db: Session = Depends(get_db)):
    lat, lng = payload.latitude, payload.longitude
    if lat is None or lng is None or not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
        raise HTTPException(status_code=400, detail="Location access is required to log in. Please allow location permission and try again.")

    if not _verify_recaptcha(payload.captcha_token):
        raise HTTPException(status_code=400, detail="Captcha verification failed. Please try again.")

    identifier = (payload.identifier or "").strip()
    admin = db.query(AdminUser).filter(
        (AdminUser.username == identifier) | (func.lower(AdminUser.email) == identifier.lower())
    ).first()

    now = datetime.now(timezone.utc)

    if admin and admin.failed_login_attempts >= MAX_LOGIN_ATTEMPTS:
        raise HTTPException(status_code=423, detail=LOGIN_LOCKED_MESSAGE)

    unknown_key = identifier.lower()
    if not admin:
        entry = _unknown_login_attempts.get(unknown_key)
        if entry and entry[1] > now and entry[0] >= MAX_LOGIN_ATTEMPTS:
            raise HTTPException(status_code=423, detail=LOGIN_LOCKED_MESSAGE)

    if not admin or not verify_password(payload.password, admin.password_hash):
        if admin:
            if not admin.locked_until or admin.locked_until <= now:
                admin.failed_login_attempts = 0
                admin.locked_until = now + timedelta(hours=LOGIN_ATTEMPT_WINDOW_HOURS)
            admin.failed_login_attempts += 1
            count = admin.failed_login_attempts
            if count >= MAX_LOGIN_ATTEMPTS:
                admin.failed_login_attempts = MAX_LOGIN_ATTEMPTS
            db.commit()
        else:
            if len(_unknown_login_attempts) > 5000:
                for k in [k for k, v in _unknown_login_attempts.items() if v[1] <= now]:
                    _unknown_login_attempts.pop(k, None)
            entry = _unknown_login_attempts.get(unknown_key)
            if not entry or entry[1] <= now:
                entry = [0, now + timedelta(hours=LOGIN_ATTEMPT_WINDOW_HOURS)]
            entry[0] += 1
            _unknown_login_attempts[unknown_key] = entry
            count = entry[0]
        remaining = MAX_LOGIN_ATTEMPTS - count
        if remaining <= 0:
            raise HTTPException(status_code=423, detail=LOGIN_LOCKED_MESSAGE)
        raise HTTPException(
            status_code=401,
            detail=f"Invalid credentials. {remaining} attempt{'s' if remaining != 1 else ''} remaining before your account is locked.",
        )

    if not admin.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")

    admin.failed_login_attempts = 0
    admin.locked_until = None

    if not admin.email:
        raise HTTPException(
            status_code=400,
            detail="This account has no email address, so a login code cannot be sent. Ask another admin for help.",
        )

    enforce_rate_limit(
        "admin_login_otp", str(admin.id), limit=5, window_seconds=600,
        detail="Too many login codes requested. Please wait a few minutes and try again.",
    )
    otp_code = generate_otp_code()
    admin.login_otp_code = _hash_login_otp(otp_code)
    admin.login_otp_expires_at = now + timedelta(minutes=LOGIN_OTP_TTL_MINUTES)
    admin.login_otp_attempts = 0
    db.commit()

    send_otp_email(admin.email, otp_code, LOGIN_OTP_TTL_MINUTES)
    return {"otp_required": True, "email_hint": _mask_email(admin.email)}


@router.post("/login/verify-otp", response_model=AdminAuthResponse)
def admin_login_verify_otp(payload: AdminLoginVerifyOtp, request: Request, db: Session = Depends(get_db)):
    lat, lng = payload.latitude, payload.longitude
    if lat is None or lng is None or not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
        raise HTTPException(status_code=400, detail="Location access is required to log in. Please allow location permission and try again.")

    identifier = (payload.identifier or "").strip()
    admin = db.query(AdminUser).filter(
        (AdminUser.username == identifier) | (func.lower(AdminUser.email) == identifier.lower())
    ).first()
    if not admin:
        raise HTTPException(status_code=400, detail="Invalid or expired code. Please log in again.")

    now = datetime.now(timezone.utc)
    if not admin.login_otp_code or not admin.login_otp_expires_at or admin.login_otp_expires_at < now:
        raise HTTPException(status_code=400, detail="Code expired. Please log in again to get a new one.")
    if admin.login_otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many incorrect attempts. Please log in again to get a new code.")
    if not hmac.compare_digest(_hash_login_otp((payload.otp_code or "").strip()), admin.login_otp_code):
        admin.login_otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid code")
    if not admin.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")

    admin.login_otp_code = None
    admin.login_otp_expires_at = None
    admin.login_otp_attempts = 0

    token = generate_session_token()
    db.add(SessionModel(token=token, admin_id=admin.id, expires_at=session_expiry()))
    db.add(
        AdminAuditLog(
            admin_id=admin.id,
            admin_username=admin.username,
            action="login",
            ip_address=client_ip(request),
            latitude=lat,
            longitude=lng,
            accuracy_m=payload.accuracy_m,
            location_label=(payload.location_label or "").strip()[:255] or None,
        )
    )
    db.commit()

    return AdminAuthResponse(token=token, id=admin.id, username=admin.username, email=admin.email)


@router.post("/logout")
def admin_logout(
    request: Request,
    payload: Optional[AdminLogout] = None,
    authorization: str = Header(...),
    admin: AdminUser = Depends(verify_admin),
    db: Session = Depends(get_db),
):
    token = authorization.removeprefix("Bearer ")
    lat = payload.latitude if payload else None
    lng = payload.longitude if payload else None
    if lat is None or lng is None or not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
        lat = lng = None
    db.query(SessionModel).filter(SessionModel.token == token, SessionModel.admin_id == admin.id).delete()
    db.add(
        AdminAuditLog(
            admin_id=admin.id,
            admin_username=admin.username,
            action="logout",
            ip_address=client_ip(request),
            latitude=lat,
            longitude=lng,
            accuracy_m=payload.accuracy_m if payload else None,
            location_label=((payload.location_label if payload else "") or "").strip()[:255] or None,
        )
    )
    db.commit()
    return {"detail": "Logged out"}



