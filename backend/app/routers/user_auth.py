import json
import os
import secrets
import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Header
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from app.models.models import ChatMessage
from app.core.ws_manager import manager
from app.schemas.schemas import ListenerStatusUpdate
from app.models.models import Call, CallRating
from sqlalchemy import func as sqlfunc
from datetime import datetime, timedelta, timezone
from app.schemas.schemas import (
    UserRegisterInitiate,
    UserRegisterResendOtp,
    UserRegisterVerifyPhone,
    UserRegisterComplete,
    UserLoginInitiate,
    UserLoginVerify,
    AuthResponse,
    GoogleSignIn,
    GoogleAuthResponse,
    FcmTokenUpdate,
    UserBioUpdate,
    UserForgotPasswordRequestOtp,
    UserForgotPasswordVerifyOtp,
    UserForgotPasswordReset,
    UserChangePassword,
    UserContactChangeRequest,
    UserContactChangeVerify,
    UserProfileUpdate,
    UserVideoCallSettingUpdate,
    AccountDeletionRequestCreate,
    detect_identifier,
    validate_username,
)

from app.core.database import get_db
from app.models.models import AdminNotification, PendingSignup, User, Session as SessionModel, ReservedUsername
from app.routers.notifications import create_admin_notification
from app.utils.sms_otp import generate_otp_code as generate_sms_otp_code, send_otp_sms
from app.utils.phone import normalize_indian_phone
from app.utils.rate_limit import enforce_rate_limit, rate_limit
from app.utils.security import hash_password, verify_password, generate_session_token, session_expiry
from app.utils.audit import record_audit_event
from app.models.models import Listener, ListenerBadgeTag
from app.core.deps import get_current_user
from app.utils.coins import chat_message_coin_cost
from firebase_admin import auth as firebase_auth
import app.utils.fcm  # noqa: F401  ensures the default Firebase app is initialized


router = APIRouter(prefix="/user", tags=["user-auth"])

@router.get("/session/check")
def session_check(current_user: User = Depends(get_current_user)):
    return {"valid": True, "is_active": current_user.is_active}


MAX_OTP_ATTEMPTS = 5

# How long the user has to finish the profile step after verifying.
SIGNUP_TOKEN_TTL_MINUTES = 30
# Abandoned sign-ups are cleared out after this long.
PENDING_SIGNUP_TTL_HOURS = 24
# Per-identifier ceiling on OTP requests, on top of the per-IP limits.
MAX_OTP_SENDS = 5
OTP_SEND_WINDOW_SECONDS = 900

# The username and each contact detail can only be changed once a day. The
# display name and bio are free to change at any time.
USERNAME_CHANGE_COOLDOWN = timedelta(hours=24)
CONTACT_CHANGE_COOLDOWN = timedelta(hours=24)
# How long a code emailed for an email change stays valid. Phone changes get
# the same window to finish the Firebase flow.
CONTACT_OTP_TTL_MINUTES = 10
# How long a username stays reserved (unavailable to anyone else) after the
# user who held it changes to a different one.
USERNAME_RESERVATION_DAYS = 45


def _find_user_by_phone(db: Session, phone: str):
    user = db.query(User).filter(User.phone == phone).first()
    if user:
        return user
    try:
        normalized = normalize_indian_phone(phone)
    except ValueError:
        return None
    return db.query(User).filter(User.phone == normalized).first()


def _find_user_by_email(db: Session, email: str):
    return db.query(User).filter(
        sqlfunc.lower(User.email) == (email or "").strip().lower()
    ).first()


USERNAME_TAKEN_MESSAGE = "This username is already taken"
PHONE_TAKEN_MESSAGE = "This phone number is already registered. Please log in instead."
EMAIL_TAKEN_MESSAGE = "This email is already registered. Please log in instead."
SIGNUP_EXPIRED_MESSAGE = "Your verification has expired. Please start sign-up again."
EMAIL_CHANNEL_REMOVED_MESSAGE = "Use your phone number or Sign in with Google"
GOOGLE_ACCOUNT_PASSWORD_MESSAGE = (
    "You signed in with Google, so this account does not have a password"
)


def _is_google_account(user: User) -> bool:
    return bool(user.google_uid) and not user.password_hash


def _require_phone_identifier(identifier: str) -> str:
    """Normalize a phone identifier, refusing email addresses.

    Email is no longer a way in or out of an account: sign-up, login and
    password resets all go through the phone number or Google.
    """
    try:
        channel, normalized = detect_identifier(identifier)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    if channel != "phone":
        raise HTTPException(status_code=400, detail=EMAIL_CHANNEL_REMOVED_MESSAGE)
    return normalized


def _is_username_taken(db: Session, username: str, exclude_user_id: Optional[int] = None) -> bool:
    """Case-insensitive check so "Riya" and "riya" cannot both exist.

    `exclude_user_id` keeps a user's own handle from counting as taken when
    they re-save it from the edit profile screen. Also treats a username as
    taken while it is under an active 45-day reservation from a previous
    owner, unless the reservation belongs to `exclude_user_id` themself.
    """
    cleaned = username.strip().lower()
    query = db.query(User.id).filter(sqlfunc.lower(User.username) == cleaned)
    if exclude_user_id is not None:
        query = query.filter(User.id != exclude_user_id)
    if query.first() is not None:
        return True

    if db.query(Listener.id).filter(sqlfunc.lower(Listener.name) == cleaned).first() is not None:
        return True

    reservation_query = db.query(ReservedUsername.id).filter(
        sqlfunc.lower(ReservedUsername.username) == cleaned,
        ReservedUsername.released_at > _utcnow(),
    )
    if exclude_user_id is not None:
        reservation_query = reservation_query.filter(
            ReservedUsername.reserved_by_user_id != exclude_user_id
        )
    return reservation_query.first() is not None


def _taken_message(db: Session, channel: str, identifier: str):
    """Returns the user-facing reason the identifier cannot be used, else None."""
    if channel == "email":
        return EMAIL_TAKEN_MESSAGE if _find_user_by_email(db, identifier) else None
    return PHONE_TAKEN_MESSAGE if _find_user_by_phone(db, identifier) else None


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value):
    """SQLite hands back naive datetimes; compare everything in UTC."""
    if value is not None and value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def _cooldown_remaining(changed_at, cooldown: timedelta) -> int:
    """Seconds left before the field may be changed again; 0 when it is free."""
    changed_at = _as_utc(changed_at)
    if not changed_at:
        return 0
    remaining = (changed_at + cooldown) - _utcnow()
    return max(0, int(remaining.total_seconds()))


def _humanize_wait(seconds: int) -> str:
    """"23 hours 5 minutes" / "42 minutes" / "less than a minute"."""
    if seconds < 60:
        return "less than a minute"
    hours, minutes = divmod(seconds // 60, 60)
    parts = []
    if hours:
        parts.append(f"{hours} hour{'s' if hours != 1 else ''}")
    if minutes:
        parts.append(f"{minutes} minute{'s' if minutes != 1 else ''}")
    return " ".join(parts)


def _enforce_change_cooldown(changed_at, cooldown: timedelta, what: str) -> None:
    remaining = _cooldown_remaining(changed_at, cooldown)
    if remaining:
        raise HTTPException(
            status_code=429,
            detail=f"You can change your {what} again in {_humanize_wait(remaining)}",
            headers={"Retry-After": str(remaining)},
        )


def _purge_expired_pending_signups(db: Session) -> None:
    cutoff = _utcnow() - timedelta(hours=PENDING_SIGNUP_TTL_HOURS)
    db.query(PendingSignup).filter(PendingSignup.created_at < cutoff).delete(
        synchronize_session=False
    )


def _issue_phone_otp(db: Session, pending: PendingSignup) -> None:
    code = generate_sms_otp_code()
    pending.otp_code = code
    pending.otp_expires_at = _utcnow() + timedelta(minutes=5)
    pending.otp_attempts = 0
    pending.otp_sent_count = (pending.otp_sent_count or 0) + 1
    db.commit()
    send_otp_sms(pending.identifier, code)


def _issue_signup_token(db: Session, pending: PendingSignup) -> str:
    """Mark the identifier verified and hand out the token for the last step."""
    pending.is_verified = True
    pending.otp_code = None
    pending.otp_expires_at = None
    pending.otp_attempts = 0
    pending.signup_token = secrets.token_urlsafe(32)
    pending.signup_token_expires_at = _utcnow() + timedelta(minutes=SIGNUP_TOKEN_TTL_MINUTES)
    db.commit()
    return pending.signup_token


def _require_pending(db: Session, identifier: str, channel: str) -> PendingSignup:
    pending = db.query(PendingSignup).filter(
        PendingSignup.identifier == identifier,
        PendingSignup.channel == channel,
    ).first()
    if not pending:
        raise HTTPException(status_code=404, detail=SIGNUP_EXPIRED_MESSAGE)
    if _as_utc(pending.created_at) and _as_utc(pending.created_at) < _utcnow() - timedelta(
        hours=PENDING_SIGNUP_TTL_HOURS
    ):
        db.delete(pending)
        db.commit()
        raise HTTPException(status_code=404, detail=SIGNUP_EXPIRED_MESSAGE)
    return pending


def _optional_user_id(db: Session, authorization: Optional[str]) -> Optional[int]:
    """The signed-in user's id when a valid session is presented, else None.

    Used by endpoints that are open to anonymous callers but should behave
    differently for the account making the request.
    """
    if not authorization or not authorization.startswith("Bearer "):
        return None
    session = db.query(SessionModel).filter(
        SessionModel.token == authorization.removeprefix("Bearer "),
        SessionModel.user_id.isnot(None),
    ).first()
    return session.user_id if session else None


@router.get(
    "/username/available",
    dependencies=[Depends(rate_limit("username_available", limit=30, window_seconds=60))],
)
def username_available(
    username: str,
    db: Session = Depends(get_db),
    authorization: Optional[str] = Header(None),
):
    """Live availability check used while the user types.

    Always returns 200 so the client can render an inline hint: `available`
    tells it whether the handle can be used and `reason` explains why not.

    The session token is optional and only used to ignore the caller's own
    row: from the edit profile screen a user's current handle is still theirs
    to keep, so reporting it as taken would be wrong.
    """
    try:
        cleaned = validate_username(username)
    except ValueError as exc:
        return {"username": (username or "").strip(), "available": False, "reason": str(exc)}

    if _is_username_taken(db, cleaned, exclude_user_id=_optional_user_id(db, authorization)):
        return {"username": cleaned, "available": False, "reason": USERNAME_TAKEN_MESSAGE}
    return {"username": cleaned, "available": True, "reason": None}


@router.get(
    "/identifier/available",
    dependencies=[Depends(rate_limit("identifier_available", limit=10, window_seconds=60))],
)
def identifier_available(identifier: str, db: Session = Depends(get_db)):
    """Checked before we send any code.

    Texting a code to a number that already has an account costs money and
    leaves the user stuck at the OTP screen, so sign-up stops here instead.
    """
    try:
        channel, normalized = detect_identifier(identifier)
    except ValueError as exc:
        return {"available": False, "channel": None, "reason": str(exc)}
    if channel != "phone":
        return {
            "available": False,
            "channel": channel,
            "identifier": normalized,
            "reason": EMAIL_CHANNEL_REMOVED_MESSAGE,
        }

    reason = _taken_message(db, "phone", normalized)
    return {
        "available": reason is None,
        "channel": "phone",
        "identifier": normalized,
        "reason": reason,
    }


@router.post(
    "/register/initiate",
    dependencies=[Depends(rate_limit("register_initiate", limit=10, window_seconds=300))],
)
def register_initiate(payload: UserRegisterInitiate, db: Session = Depends(get_db)):
    """Step 1: take the email/phone and password, then start verification.

    Nothing is written to `users` yet. The details sit in `pending_signups`
    until the code is verified and the profile step is finished, so abandoning
    sign-up here does not reserve the phone number or username.
    """
    identifier = _require_phone_identifier(payload.identifier)
    channel = "phone"

    _purge_expired_pending_signups(db)

    taken = _taken_message(db, channel, identifier)
    if taken:
        raise HTTPException(status_code=409, detail=taken)

    pending = db.query(PendingSignup).filter(
        PendingSignup.identifier == identifier
    ).first()
    if pending is None:
        pending = PendingSignup(identifier=identifier, channel=channel)
        db.add(pending)

    # Restarting sign-up replaces whatever was there: the password may have
    # changed and any previously issued code or token must stop working.
    pending.channel = channel
    pending.password_hash = hash_password(payload.password)
    pending.is_verified = False
    pending.signup_token = None
    pending.signup_token_expires_at = None
    pending.otp_code = None
    pending.otp_expires_at = None
    pending.otp_attempts = 0
    db.commit()

    enforce_rate_limit(
        "signup_otp_send",
        identifier,
        MAX_OTP_SENDS,
        OTP_SEND_WINDOW_SECONDS,
        detail="Too many codes requested for this number. Please wait a few minutes and try again.",
    )
    _issue_phone_otp(db, pending)
    return {"channel": "phone", "identifier": identifier, "otp_sent": True}


@router.post(
    "/register/resend-otp",
    dependencies=[Depends(rate_limit("register_resend_otp", limit=5, window_seconds=300))],
)
def register_resend_otp(payload: UserRegisterResendOtp, db: Session = Depends(get_db)):
    """Re-send the sign-up verification code by SMS."""
    identifier = _require_phone_identifier(payload.identifier)

    pending = _require_pending(db, identifier, "phone")
    if _find_user_by_phone(db, identifier):
        raise HTTPException(status_code=409, detail=PHONE_TAKEN_MESSAGE)

    enforce_rate_limit(
        "signup_otp_send",
        identifier,
        MAX_OTP_SENDS,
        OTP_SEND_WINDOW_SECONDS,
        detail="Too many codes requested for this number. Please wait a few minutes and try again.",
    )
    _issue_phone_otp(db, pending)
    return {"status": "otp_sent"}


@router.post(
    "/register/verify-phone",
    dependencies=[Depends(rate_limit("register_verify_phone", limit=20, window_seconds=300))],
)
def register_verify_phone(payload: UserRegisterVerifyPhone, db: Session = Depends(get_db)):
    """Step 2 (phone): check the SMS code and hand back the sign-up token."""
    try:
        channel, identifier = detect_identifier(payload.identifier)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    if channel != "phone":
        raise HTTPException(status_code=400, detail="Use email verification for this address")

    pending = _require_pending(db, identifier, "phone")

    expires_at = _as_utc(pending.otp_expires_at)
    if not expires_at or expires_at < _utcnow():
        raise HTTPException(status_code=400, detail="OTP expired. Please request a new one.")
    if pending.otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Please request a new OTP.")
    if not pending.otp_code or pending.otp_code != (payload.otp_code or "").strip():
        pending.otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")

    # Someone may have registered this number while the OTP was in flight.
    if _find_user_by_phone(db, identifier):
        raise HTTPException(status_code=409, detail=PHONE_TAKEN_MESSAGE)

    return {"status": "verified", "signup_token": _issue_signup_token(db, pending)}


@router.post(
    "/register/complete",
    response_model=AuthResponse,
    dependencies=[Depends(rate_limit("register_complete", limit=10, window_seconds=300))],
)
def register_complete(payload: UserRegisterComplete, db: Session = Depends(get_db)):
    """Step 3: create the account from a verified sign-up and log the user in.

    The profile photo is optional and is uploaded separately through
    `/user/photo` with the session token returned here.
    """
    pending = db.query(PendingSignup).filter(
        PendingSignup.signup_token == payload.signup_token
    ).first()
    token_expires_at = _as_utc(pending.signup_token_expires_at) if pending else None
    if (
        not pending
        or not pending.is_verified
        or not token_expires_at
        or token_expires_at < _utcnow()
    ):
        raise HTTPException(status_code=401, detail=SIGNUP_EXPIRED_MESSAGE)

    taken = _taken_message(db, pending.channel, pending.identifier)
    if taken:
        db.delete(pending)
        db.commit()
        raise HTTPException(status_code=409, detail=taken)

    username = payload.username.strip()
    if _is_username_taken(db, username):
        raise HTTPException(status_code=409, detail=USERNAME_TAKEN_MESSAGE)

    user = User(
        name=payload.display_name,
        username=username.lower(),
        email=pending.identifier if pending.channel == "email" else None,
        phone=pending.identifier if pending.channel == "phone" else None,
        password_hash=pending.password_hash,
    )
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        # Someone claimed the username or the identifier itself in the moment
        # between the checks above and this insert.
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail=_taken_message(db, pending.channel, pending.identifier)
            or USERNAME_TAKEN_MESSAGE,
        )

    db.delete(pending)

    token = generate_session_token()
    db.add(SessionModel(token=token, user_id=user.id, expires_at=session_expiry()))
    record_audit_event(db, "user", user.id, user.name, "login")
    db.commit()
    db.refresh(user)
    return AuthResponse(token=token, id=user.id, name=user.name)


@router.post(
    "/login/initiate",
    dependencies=[Depends(rate_limit("login_initiate", limit=10, window_seconds=60))],
)
def login_initiate(payload: UserLoginInitiate, db: Session = Depends(get_db)):
    """Login step 1: check the password, then send the SMS OTP.

    Password login is phone-only. Google accounts come in through
    `/user/auth/google` instead and have no password to check here.
    """
    try:
        channel, identifier = detect_identifier(payload.identifier)
    except ValueError:
        # A malformed identifier cannot match an account; keep the same wording
        # as a wrong password so this cannot be used to probe for accounts.
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if channel != "phone":
        raise HTTPException(status_code=400, detail=EMAIL_CHANNEL_REMOVED_MESSAGE)

    user = _find_user_by_phone(db, identifier)
    if not user or not user.password_hash:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not user.is_active:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    try:
        otp_phone = normalize_indian_phone(user.phone)
    except ValueError:
        raise HTTPException(status_code=400, detail="This account has an invalid phone number. Please contact support.")
    enforce_rate_limit("login_otp_send", otp_phone, MAX_OTP_SENDS, OTP_SEND_WINDOW_SECONDS)
    code = generate_sms_otp_code()
    user.reset_otp_code = code
    user.reset_otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
    user.reset_otp_attempts = 0
    db.commit()
    send_otp_sms(otp_phone, code)
    return {"channel": "phone", "status": "credentials_ok", "phone": otp_phone}


@router.post("/login/verify", response_model=AuthResponse)
def login_verify(payload: UserLoginVerify, db: Session = Depends(get_db)):
    user = _find_user_by_phone(db, payload.phone)
    if not user or not user.password_hash:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not user.is_active:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    expires_at = _as_utc(user.reset_otp_expires_at)
    if not expires_at or expires_at < _utcnow():
        raise HTTPException(status_code=400, detail="OTP expired. Please request a new one.")
    if user.reset_otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Please request a new OTP.")
    if not user.reset_otp_code or user.reset_otp_code != (payload.otp_code or "").strip():
        user.reset_otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")

    user.reset_otp_code = None
    user.reset_otp_expires_at = None
    user.reset_otp_attempts = 0

    token = generate_session_token()
    db.add(SessionModel(token=token, user_id=user.id, expires_at=session_expiry()))
    record_audit_event(db, "user", user.id, user.name, "login")
    db.commit()
    return AuthResponse(token=token, id=user.id, name=user.name)


@router.post(
    "/auth/google",
    response_model=GoogleAuthResponse,
    dependencies=[Depends(rate_limit("auth_google", limit=20, window_seconds=300))],
)
def auth_google(payload: GoogleSignIn, db: Session = Depends(get_db)):
    """Signs in with a Google ID token, creating the account on first use.

    A returning `google_uid` logs straight in. A first-time signer whose
    Google email already matches an existing account (however that account
    was made) is linked instead of duplicated. Otherwise a new account is
    created with a placeholder username and `profile_complete` false, which
    is what sends the app to the profile setup screen to collect a photo,
    username and display name.
    """
    try:
        decoded = firebase_auth.verify_id_token(payload.id_token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid Google sign-in")

    google_uid = decoded.get("uid")
    if not google_uid:
        raise HTTPException(status_code=401, detail="Invalid Google sign-in")
    email = (decoded.get("email") or "").strip().lower() or None
    email_verified = decoded.get("email_verified", False)
    name = decoded.get("name") or (email.split("@")[0] if email else "User")

    user = db.query(User).filter(User.google_uid == google_uid).first()
    if not user and email and email_verified:
        user = _find_user_by_email(db, email)
        if user:
            user.google_uid = google_uid

    if user is None:
        # No username yet on purpose: that is what marks the profile as
        # unfinished, so the app opens the setup screen and the user picks
        # their own handle instead of being given a generated one.
        user = User(
            name=name,
            email=email if email_verified else None,
            password_hash=None,
            google_uid=google_uid,
        )
        db.add(user)
        db.flush()
    elif not user.is_active:
        raise HTTPException(status_code=401, detail="This account has been deactivated")

    token = generate_session_token()
    db.add(SessionModel(token=token, user_id=user.id, expires_at=session_expiry()))
    record_audit_event(db, "user", user.id, user.name, "login")
    db.commit()
    db.refresh(user)
    return GoogleAuthResponse(
        token=token,
        id=user.id,
        name=user.name,
        profile_complete=bool(user.username),
    )



@router.post("/logout")
def logout(authorization: str = Header(...), db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    token = authorization.replace("Bearer ", "")
    db.query(SessionModel).filter(SessionModel.token == token).delete()
    # Otherwise a chat message sent after logout still pushes to this device:
    # FCM delivery only checks for a stored token, not whether anyone is logged in.
    current_user.fcm_token = None
    record_audit_event(db, "user", current_user.id, current_user.name, "logout")
    db.commit()
    return {"status": "logged_out"}


ACCOUNT_DELETION_NOTIFICATION_TYPE = "account_deletion_request"


@router.post("/delete-account")
async def request_account_deletion(
    payload: AccountDeletionRequestCreate = AccountDeletionRequestCreate(),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Raises an account deletion request for the admins to action.

    The account is deliberately left untouched: deleting a user also removes
    their calls, chats and coin history, so that stays a manual admin step.
    Repeat taps do not pile up - while a request is still open the same
    confirmation is returned.
    """
    existing = (
        db.query(AdminNotification)
        .filter(
            AdminNotification.type == ACCOUNT_DELETION_NOTIFICATION_TYPE,
            AdminNotification.subject_type == "user",
            AdminNotification.subject_id == current_user.id,
            AdminNotification.is_done.is_(False),
        )
        .first()
    )
    if existing:
        return {"status": "already_requested", "requested_at": existing.created_at}

    contact = current_user.email or current_user.phone or "no contact on file"
    reason = (payload.reason or "").strip() if payload else ""
    body = f"{current_user.name} ({contact}) requested deletion of their account."
    if reason:
        body = f"{body} Reason: {reason}"

    notification = await create_admin_notification(
        db,
        type=ACCOUNT_DELETION_NOTIFICATION_TYPE,
        title="Account deletion request",
        body=body,
        subject_type="user",
        subject_id=current_user.id,
        subject_name=current_user.name,
    )
    return {"status": "requested", "requested_at": notification.created_at}


def _reset_account(db: Session, identifier: str):
    """Resolve the account a password reset is for.

    Returns `(normalized_phone, user)`. The reset code always goes to the
    registered phone number, so an email address is not a valid identifier
    here. Google accounts have no password and are turned away.
    """
    normalized = _require_phone_identifier(identifier)

    user = _find_user_by_phone(db, normalized)
    if not user:
        raise HTTPException(
            status_code=404, detail="enter a registered phone number"
        )
    if _is_google_account(user):
        raise HTTPException(status_code=400, detail=GOOGLE_ACCOUNT_PASSWORD_MESSAGE)
    return normalized, user


def _check_reset_otp(db: Session, user: User, otp_code: Optional[str]) -> None:
    """Validate the emailed reset code, counting failed attempts."""
    expires_at = _as_utc(user.reset_otp_expires_at)
    if not expires_at or expires_at < _utcnow():
        raise HTTPException(status_code=400, detail="OTP expired")
    if user.reset_otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Please request a new OTP.")
    if not user.reset_otp_code or user.reset_otp_code != (otp_code or "").strip():
        user.reset_otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")


@router.post(
    "/forgot-password/request-otp",
    dependencies=[Depends(rate_limit("forgot_password_otp", limit=5, window_seconds=300))],
)
def forgot_password_request_otp(payload: UserForgotPasswordRequestOtp, db: Session = Depends(get_db)):
    """Start a password reset by texting a code to the registered number."""
    identifier, user = _reset_account(db, payload.identifier)

    enforce_rate_limit("reset_otp_send", identifier, MAX_OTP_SENDS, OTP_SEND_WINDOW_SECONDS)

    otp_code = generate_sms_otp_code()
    user.reset_otp_code = otp_code
    user.reset_otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
    user.reset_otp_attempts = 0
    db.commit()
    send_otp_sms(identifier, otp_code)
    return {"channel": "phone", "identifier": identifier, "status": "otp_sent"}


@router.post("/forgot-password/verify-otp")
def forgot_password_verify_otp(payload: UserForgotPasswordVerifyOtp, db: Session = Depends(get_db)):
    _identifier, user = _reset_account(db, payload.identifier)
    _check_reset_otp(db, user, payload.otp_code)
    return {"status": "otp_verified"}


@router.post("/forgot-password/reset")
def forgot_password_reset(payload: UserForgotPasswordReset, db: Session = Depends(get_db)):
    identifier, user = _reset_account(db, payload.identifier)

    _check_reset_otp(db, user, payload.otp_code)

    if user.password_hash and verify_password(payload.new_password, user.password_hash):
        raise HTTPException(status_code=400, detail="New password must be different from your current password")

    user.password_hash = hash_password(payload.new_password)
    user.reset_otp_code = None
    user.reset_otp_expires_at = None
    user.reset_otp_attempts = 0
    db.query(SessionModel).filter(SessionModel.user_id == user.id).delete()
    db.commit()

    return {"status": "password_reset"}


@router.post("/change-password")
def change_password(payload: UserChangePassword, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if not current_user.password_hash:
        raise HTTPException(status_code=400, detail=GOOGLE_ACCOUNT_PASSWORD_MESSAGE)
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

    # Listeners this user has already called, with the time of the most recent
    # call. Drives the ordering below: someone the user has talked to before is
    # far more relevant than a stranger, so those cards are pinned to the top.
    # Every call counts, including ones that were never answered, because the
    # intent to reach that listener is what makes them relevant.
    last_call_rows = db.query(
        Call.callee_listener_id,
        sqlfunc.max(Call.created_at),
    ).filter(
        Call.caller_user_id == current_user.id,
        Call.callee_listener_id.in_(listener_ids),
    ).group_by(Call.callee_listener_id).all()
    last_call_by_listener = {r[0]: r[1] for r in last_call_rows}

    badge_tag_ids = {l.badge_tag_id for l in listeners if l.badge_tag_id}
    badge_tags_by_id = {}
    if badge_tag_ids:
        for t in db.query(ListenerBadgeTag).filter(ListenerBadgeTag.id.in_(badge_tag_ids)).all():
            badge_tags_by_id[t.id] = {"id": t.id, "name": t.name, "color": t.color}

    result = []
    for l in listeners:
        avg_rating, rating_count = ratings_by_listener.get(l.id, (None, 0))
        try:
            tags = json.loads(l.tags) if l.tags else []
        except (TypeError, json.JSONDecodeError):
            tags = []
        last_call_at = last_call_by_listener.get(l.id)
        result.append({
            "id": l.id, "name": l.name, "is_online": bool(l.is_online) and manager.is_listener_online(l.id),
            "tags": tags,
            "avg_rating": round(avg_rating, 1) if avg_rating else None,
            "rating_count": rating_count or 0,
            "photo_url": l.photo_url,
            "age": l.age,
            "occupation": l.occupation,
            "badge_tag": badge_tags_by_id.get(l.badge_tag_id),
            # Null for a listener this user has never called. The client sorts
            # on the same field so presence changes arriving over the socket
            # keep the list in this exact order without a refetch.
            "last_interacted_at": last_call_at.isoformat() if last_call_at else None,
        })

    def _order_key(item):
        last_call_at = last_call_by_listener.get(item["id"])
        return (
            # 1. previously called listeners, whether they are online or not
            0 if last_call_at else 1,
            # 2. online before offline, inside each of those two groups
            0 if item["is_online"] else 1,
            # 3. most recently called first (0 keeps strangers in id order)
            -last_call_at.timestamp() if last_call_at else 0,
            item["id"],
        )

    result.sort(key=_order_key)
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
    badge_tag = None
    if l.badge_tag_id:
        t = db.query(ListenerBadgeTag).filter(ListenerBadgeTag.id == l.badge_tag_id).first()
        if t:
            badge_tag = {"id": t.id, "name": t.name, "color": t.color}
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
        "age": l.age,
        "occupation": l.occupation,
        "badge_tag": badge_tag,
    }

    
@router.get("/me")
def get_me(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "name": current_user.name,
        "username": current_user.username,
        "email": current_user.email,
        "phone": current_user.phone,
        # An email/phone only ever reaches the account through an OTP, so
        # having one stored is the same thing as it being verified.
        "email_verified": bool(current_user.email),
        "phone_verified": bool(current_user.phone),
        # No password exists on a Google account, so the settings screen shows
        # an explanation instead of opening the change password form.
        "is_google_account": _is_google_account(current_user),
        # Seconds the edit profile screen has to keep each field locked for.
        # Sent as a duration rather than a timestamp so a wrong device clock
        # cannot unlock the field early or lock it forever.
        "username_cooldown_seconds": _cooldown_remaining(
            current_user.username_changed_at, USERNAME_CHANGE_COOLDOWN
        ),
        "email_cooldown_seconds": _cooldown_remaining(
            current_user.email_changed_at, CONTACT_CHANGE_COOLDOWN
        ),
        "phone_cooldown_seconds": _cooldown_remaining(
            current_user.phone_changed_at, CONTACT_CHANGE_COOLDOWN
        ),
        "coins": current_user.coins,
        "chat_message_coin_cost": chat_message_coin_cost(db),
        "bio": current_user.bio,
        "photo_url": current_user.photo_url,
        "video_call_enabled": current_user.video_call_enabled,
        "video_call_disabled_by_admin": current_user.video_call_disabled_by_admin,
    }


def _profile_state(current_user: User) -> dict:
    """The fields the edit profile screen re-renders after a change."""
    return {
        "name": current_user.name,
        "username": current_user.username,
        "email": current_user.email,
        "phone": current_user.phone,
        "bio": current_user.bio,
        "email_verified": bool(current_user.email),
        "phone_verified": bool(current_user.phone),
        "username_cooldown_seconds": _cooldown_remaining(
            current_user.username_changed_at, USERNAME_CHANGE_COOLDOWN
        ),
        "email_cooldown_seconds": _cooldown_remaining(
            current_user.email_changed_at, CONTACT_CHANGE_COOLDOWN
        ),
        "phone_cooldown_seconds": _cooldown_remaining(
            current_user.phone_changed_at, CONTACT_CHANGE_COOLDOWN
        ),
    }


@router.post("/profile")
def update_profile(
    payload: UserProfileUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Save the display name, username and bio from the edit profile screen.

    Only the fields present in the request are touched. The display name and
    bio can be changed at will; the username is limited to one change every
    24 hours, so an unchanged username in the payload is a no-op rather than
    an error.
    """
    if payload.display_name is not None:
        current_user.name = payload.display_name

    if payload.bio is not None:
        current_user.bio = payload.bio

    if payload.username is not None:
        username = payload.username.strip()
        # Re-saving the same handle (in any casing) must not burn the daily
        # change or trip the "already taken" check against the user's own row.
        if username.lower() != (current_user.username or "").lower():
            # Claiming a handle for the first time is part of setting the
            # account up (Google sign-in leaves it empty), not a change, so it
            # neither waits for nor starts the 24 hour cool-down.
            first_time = not current_user.username
            if not first_time:
                _enforce_change_cooldown(
                    current_user.username_changed_at, USERNAME_CHANGE_COOLDOWN, "username"
                )
            if _is_username_taken(db, username, exclude_user_id=current_user.id):
                raise HTTPException(status_code=409, detail=USERNAME_TAKEN_MESSAGE)
            if not first_time:
                db.add(
                    ReservedUsername(
                        username=current_user.username.lower(),
                        reserved_by_user_id=current_user.id,
                        released_at=_utcnow() + timedelta(days=USERNAME_RESERVATION_DAYS),
                    )
                )
            current_user.username = username.lower()
            if not first_time:
                current_user.username_changed_at = _utcnow()

    try:
        db.commit()
    except IntegrityError:
        # Someone claimed the handle between the check above and the write.
        db.rollback()
        raise HTTPException(status_code=409, detail=USERNAME_TAKEN_MESSAGE)

    db.refresh(current_user)
    return {"status": "updated", **_profile_state(current_user)}


EMAIL_LINKED_MESSAGE = "This email is already linked to another account"
PHONE_LINKED_MESSAGE = "This phone number is already linked to another account"
CONTACT_CHANGE_EXPIRED_MESSAGE = (
    "This verification has expired. Please start the change again."
)


def _contact_change_state(current_user: User, channel: str):
    """(current value, when it last changed, wording) for the given channel."""
    if channel == "email":
        return current_user.email, current_user.email_changed_at, "email address"
    return current_user.phone, current_user.phone_changed_at, "phone number"


def _assert_contact_free(db: Session, channel: str, identifier: str, user_id: int) -> None:
    """Reject a new email/phone that already belongs to somebody else."""
    other = (
        _find_user_by_email(db, identifier)
        if channel == "email"
        else _find_user_by_phone(db, identifier)
    )
    if other and other.id != user_id:
        raise HTTPException(
            status_code=409,
            detail=EMAIL_LINKED_MESSAGE if channel == "email" else PHONE_LINKED_MESSAGE,
        )


def _clear_pending_contact(current_user: User) -> None:
    current_user.pending_contact_channel = None
    current_user.pending_contact_identifier = None
    current_user.pending_contact_otp_code = None
    current_user.pending_contact_otp_expires_at = None
    current_user.pending_contact_otp_attempts = 0


@router.post(
    "/contact/request-otp",
    dependencies=[Depends(rate_limit("contact_change_otp", limit=10, window_seconds=300))],
)
def contact_change_request_otp(
    payload: UserContactChangeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Start changing the registered phone number.

    Nothing is written to the account yet: the new value waits in the
    `pending_contact_*` columns until `/user/contact/verify` confirms the user
    can actually receive on it, so a typo can never take away a working login.
    """
    identifier = _require_phone_identifier(payload.identifier)
    channel = "phone"

    current_value, changed_at, label = _contact_change_state(current_user, channel)
    if current_value and current_value.strip().lower() == identifier:
        raise HTTPException(status_code=400, detail=f"This is already your {label}")

    _enforce_change_cooldown(changed_at, CONTACT_CHANGE_COOLDOWN, label)
    _assert_contact_free(db, channel, identifier, current_user.id)

    current_user.pending_contact_channel = channel
    current_user.pending_contact_identifier = identifier
    current_user.pending_contact_otp_code = None
    current_user.pending_contact_otp_attempts = 0
    current_user.pending_contact_otp_expires_at = _utcnow() + timedelta(
        minutes=CONTACT_OTP_TTL_MINUTES
    )

    enforce_rate_limit(
        "contact_change_otp_send",
        identifier,
        MAX_OTP_SENDS,
        OTP_SEND_WINDOW_SECONDS,
        detail="Too many codes requested for this number. Please wait a few minutes and try again.",
    )
    code = generate_sms_otp_code()
    current_user.pending_contact_otp_code = code
    db.commit()
    send_otp_sms(identifier, code)
    return {"channel": "phone", "identifier": identifier, "otp_sent": True}


@router.post(
    "/contact/verify",
    dependencies=[Depends(rate_limit("contact_change_verify", limit=20, window_seconds=300))],
)
def contact_change_verify(
    payload: UserContactChangeVerify,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Finish the change: verify the new phone number and save it."""
    identifier = _require_phone_identifier(payload.identifier)
    channel = "phone"

    if (
        current_user.pending_contact_channel != channel
        or (current_user.pending_contact_identifier or "") != identifier
    ):
        raise HTTPException(status_code=400, detail=CONTACT_CHANGE_EXPIRED_MESSAGE)

    expires_at = _as_utc(current_user.pending_contact_otp_expires_at)
    if not expires_at or expires_at < _utcnow():
        _clear_pending_contact(current_user)
        db.commit()
        raise HTTPException(status_code=400, detail=CONTACT_CHANGE_EXPIRED_MESSAGE)

    if current_user.pending_contact_otp_attempts >= MAX_OTP_ATTEMPTS:
        raise HTTPException(
            status_code=429, detail="Too many attempts. Please request a new OTP."
        )
    if (
        not current_user.pending_contact_otp_code
        or current_user.pending_contact_otp_code != (payload.otp_code or "").strip()
    ):
        current_user.pending_contact_otp_attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Invalid OTP")

    # Re-checked here because both can change while the code is in flight, and
    # verifying earlier is no proof the write is still allowed.
    _, changed_at, label = _contact_change_state(current_user, channel)
    _enforce_change_cooldown(changed_at, CONTACT_CHANGE_COOLDOWN, label)
    _assert_contact_free(db, channel, identifier, current_user.id)

    current_user.phone = identifier
    current_user.phone_changed_at = _utcnow()
    _clear_pending_contact(current_user)

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail=EMAIL_LINKED_MESSAGE if channel == "email" else PHONE_LINKED_MESSAGE,
        )

    db.refresh(current_user)
    return {"status": "verified", "channel": channel, **_profile_state(current_user)}

@router.post("/video-call-setting")
def update_video_call_setting(payload: UserVideoCallSettingUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Let the user turn their own video-calling feature on/off."""
    current_user.video_call_enabled = payload.enabled
    db.commit()
    return {
        "status": "updated",
        "video_call_enabled": current_user.video_call_enabled,
        "video_call_disabled_by_admin": current_user.video_call_disabled_by_admin,
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
