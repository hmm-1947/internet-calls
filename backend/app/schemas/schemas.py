import re

from pydantic import BaseModel, field_validator
from typing import Optional
from datetime import datetime

from app.utils.phone import normalize_indian_phone

ALLOWED_PLAN_ICONS = {"coin", "diamond", "star"}


def validate_password_strength(v: str) -> str:
    v = v or ""
    if len(v) < 8:
        raise ValueError("Password must be at least 8 characters long")
    if not re.search(r"[A-Za-z]", v):
        raise ValueError("Password must contain at least one alphabet")
    if not re.search(r"[0-9]", v):
        raise ValueError("Password must contain at least one number")
    if not re.search(r"[^A-Za-z0-9]", v):
        raise ValueError("Password must contain at least one special character")
    return v


USERNAME_MIN_LENGTH = 3
USERNAME_MAX_LENGTH = 20
_USERNAME_ALLOWED = re.compile(r"^[A-Za-z0-9._]+$")
# Handles we never hand out, so they stay available for system/support use.
RESERVED_USERNAMES = {"admin", "administrator", "support", "root", "system", "listener", "me"}


def validate_username(v: str) -> str:
    """Validate a user-chosen handle and return it trimmed (original casing kept).

    Raises ValueError with a user-facing message when the handle is unusable.
    """
    v = (v or "").strip()
    if len(v) < USERNAME_MIN_LENGTH:
        raise ValueError(f"Username must be at least {USERNAME_MIN_LENGTH} characters long")
    if len(v) > USERNAME_MAX_LENGTH:
        raise ValueError(f"Username must be at most {USERNAME_MAX_LENGTH} characters long")
    if not _USERNAME_ALLOWED.match(v):
        raise ValueError("Username can only contain letters, numbers, dots and underscores")
    if not re.search(r"[A-Za-z]", v):
        raise ValueError("Username must contain at least one letter")
    if v.startswith(".") or v.endswith("."):
        raise ValueError("Username cannot start or end with a dot")
    if v.lower() in RESERVED_USERNAMES:
        raise ValueError("This username is reserved. Please choose another one.")
    return v


DISPLAY_NAME_MAX_LENGTH = 30


def validate_display_name(v: str) -> str:
    """The name shown to listeners. Not unique, but must not be blank."""
    v = " ".join((v or "").split())
    if len(v) < 2:
        raise ValueError("Display name must be at least 2 characters long")
    if len(v) > DISPLAY_NAME_MAX_LENGTH:
        raise ValueError(
            f"Display name must be at most {DISPLAY_NAME_MAX_LENGTH} characters long"
        )
    return v


# Deliberately permissive: the OTP mail is the real proof the address works,
# so this only rejects input that clearly is not an address.
_EMAIL_ALLOWED = re.compile(r"^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$")
EMAIL_MAX_LENGTH = 254


def validate_email_address(v: str) -> str:
    """Return the address lower-cased so lookups are case-insensitive."""
    v = (v or "").strip().lower()
    if not v:
        raise ValueError("Enter your email address")
    if len(v) > EMAIL_MAX_LENGTH or not _EMAIL_ALLOWED.match(v):
        raise ValueError("Enter a valid email address")
    return v


def detect_identifier(v: str) -> tuple[str, str]:
    """Work out whether the user typed an email or a phone number.

    Returns `(channel, normalized)` where channel is "email" or "phone".
    Anything containing "@" is treated as an email attempt so a typo in an
    address reports an email error instead of a confusing phone-number one.
    Raises ValueError with a user-facing message when neither form is valid.
    """
    raw = (v or "").strip()
    if not raw:
        raise ValueError("Enter your email address or phone number")
    if "@" in raw:
        return "email", validate_email_address(raw)
    return "phone", normalize_indian_phone(raw)



class AdminListenerProfileUpdate(BaseModel):
    # Renaming a listener from the panel. Uniqueness is enforced by the
    # endpoint, which needs the database to check it against.
    name: Optional[str] = None
    about: Optional[str] = None
    tags: Optional[list[str]] = None
    languages: Optional[list[str]] = None
    age: Optional[int] = None
    occupation: Optional[str] = None

    @field_validator("name")
    @classmethod
    def name_format(cls, v: Optional[str]) -> Optional[str]:
        return None if v is None else validate_display_name(v)

    @field_validator("about")
    @classmethod
    def about_length(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and len(v) > 2000:
            raise ValueError("About must be under 2000 characters")
        return v

    @field_validator("age")
    @classmethod
    def age_range(cls, v: Optional[int]) -> Optional[int]:
        # Admins may set any age here, including under 18 (e.g. for
        # placeholder/incomplete listener records); just guard against
        # nonsensical zero/negative values.
        if v is not None and v < 1:
            raise ValueError("Please enter a valid age")
        return v

    @field_validator("occupation")
    @classmethod
    def occupation_length(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and len(v) > 100:
            raise ValueError("Occupation must be under 100 characters")
        return v

    @field_validator("tags", "languages")
    @classmethod
    def list_of_short_strings(cls, v: Optional[list]) -> Optional[list]:
        if v is None:
            return v
        cleaned = []
        for item in v:
            if not isinstance(item, str):
                raise ValueError("Each item must be a string")
            item = item.strip()
            if not item:
                continue
            if len(item) > 50:
                raise ValueError("Each item must be under 50 characters")
            cleaned.append(item)
        return cleaned


class AdminUserProfileUpdate(BaseModel):
    bio: Optional[str] = None

    @field_validator("bio")
    @classmethod
    def bio_length(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and len(v) > 2000:
            raise ValueError("Bio must be under 2000 characters")
        return v


class AdminActiveUpdate(BaseModel):
    is_active: bool


class AdminVideoCallUpdate(BaseModel):
    disabled: bool


class ListenerBadgeTagCreate(BaseModel):
    name: str
    color: Optional[str] = "#E11D48"


class ListenerTagAssign(BaseModel):
    tag_id: Optional[int] = None


class BillingPlanBase(BaseModel):
    name: str
    price: int
    coins: int
    icon: str = "coin"
    is_featured: bool = False
    is_active: bool = True

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        v = (v or "").strip()
        if not v:
            raise ValueError("Plan name is required")
        if len(v) > 100:
            raise ValueError("Plan name must be under 100 characters")
        return v

    @field_validator("price")
    @classmethod
    def price_positive(cls, v: int) -> int:
        if v is None or v <= 0:
            raise ValueError("Price must be greater than 0")
        return v

    @field_validator("coins")
    @classmethod
    def coins_positive(cls, v: int) -> int:
        if v is None or v <= 0:
            raise ValueError("Number of coins must be greater than 0")
        return v

    @field_validator("icon")
    @classmethod
    def icon_allowed(cls, v: str) -> str:
        v = (v or "").strip().lower()
        if v not in ALLOWED_PLAN_ICONS:
            raise ValueError("icon must be one of: coin, diamond, star")
        return v


class BillingPlanCreate(BillingPlanBase):
    pass


class BillingPlanUpdate(BillingPlanBase):
    pass


class BillingPlanOut(BillingPlanBase):
    id: int
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class GiftOut(BaseModel):
    id: int
    name: str
    coins: int
    icon: Optional[str] = None

    class Config:
        from_attributes = True


class BillingPurchaseOut(BaseModel):
    id: int
    plan_id: int
    plan_name: str
    price_paid: int
    coins_purchased: int
    status: str

    class Config:
        from_attributes = True


class RazorpayOrderOut(BaseModel):
    purchase_id: int
    order_id: str
    amount: int  # in paise
    currency: str = "INR"
    key_id: str
    plan_name: str
    coins: int
    name: str
    email: Optional[str] = None
    contact: Optional[str] = None


class RazorpayVerifyPayment(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


class RazorpayPaymentFailed(BaseModel):
    razorpay_order_id: str
    reason: Optional[str] = None


class BillingPlanAuditLogOut(BaseModel):
    id: int
    action: str
    plan_id: Optional[int] = None
    plan_name: str
    admin_id: Optional[int] = None
    admin_username: Optional[str] = None
    details: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class GiftAuditLogOut(BaseModel):
    id: int
    action: str
    gift_id: Optional[int] = None
    gift_name: str
    admin_id: Optional[int] = None
    admin_username: Optional[str] = None
    details: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class AdminPurchaseOut(BaseModel):
    id: int
    user_id: int
    user_name: str
    user_phone: Optional[str] = None
    plan_id: int
    plan_name: str
    price_paid: int
    coins_purchased: int
    status: str
    razorpay_order_id: Optional[str] = None
    razorpay_payment_id: Optional[str] = None
    failure_reason: Optional[str] = None
    razorpay_refund_id: Optional[str] = None
    refunded_amount_paise: int = 0
    refunded_at: Optional[datetime] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

class UserRegisterInitiate(BaseModel):
    """Step 1: the phone number to verify, plus the account password.

    `confirm_password` is optional because the app already compares the two
    fields; when it is sent we check it again so an API client cannot create an
    account with a password the user never confirmed.
    """

    identifier: str
    password: str
    confirm_password: Optional[str] = None

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return validate_password_strength(v)

    @field_validator("confirm_password")
    @classmethod
    def passwords_match(cls, v: Optional[str], info) -> Optional[str]:
        password = info.data.get("password")
        if v is not None and password is not None and v != password:
            raise ValueError("Passwords do not match")
        return v

class UserRegisterResendOtp(BaseModel):
    identifier: str

class UserRegisterVerifyPhone(BaseModel):
    identifier: str
    otp_code: str

class UserRegisterComplete(BaseModel):
    """Step 3: the profile details, exchanged for a real account."""

    signup_token: str
    username: str
    display_name: str

    @field_validator("username")
    @classmethod
    def username_format(cls, v: str) -> str:
        return validate_username(v)

    @field_validator("display_name")
    @classmethod
    def display_name_format(cls, v: str) -> str:
        return validate_display_name(v)

class UserLoginInitiate(BaseModel):
    identifier: str
    password: str

class UserLoginVerify(BaseModel):
    phone: str
    password: str
    otp_code: str

class UserBioUpdate(BaseModel):
    bio: str


class UserProfileUpdate(BaseModel):
    """Edit profile screen: any subset of the freely editable fields.

    Omitted fields are left untouched, so the client can send only what the
    user actually changed. The display name may be changed as often as the
    user likes; the username is rate limited to once every 24 hours by the
    endpoint, not here.
    """

    display_name: Optional[str] = None
    username: Optional[str] = None
    bio: Optional[str] = None

    @field_validator("display_name")
    @classmethod
    def display_name_format(cls, v: Optional[str]) -> Optional[str]:
        return None if v is None else validate_display_name(v)

    @field_validator("username")
    @classmethod
    def username_format(cls, v: Optional[str]) -> Optional[str]:
        return None if v is None else validate_username(v)

    @field_validator("bio")
    @classmethod
    def bio_length(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and len(v) > 2000:
            raise ValueError("Bio must be under 2000 characters")
        return v


class UserContactChangeRequest(BaseModel):
    """`identifier` is the new phone number to verify."""

    identifier: str


class UserContactChangeVerify(BaseModel):
    identifier: str
    otp_code: Optional[str] = None

class UserVideoCallSettingUpdate(BaseModel):
    enabled: bool

class ListenerVideoCallSettingUpdate(BaseModel):
    enabled: bool

class UserForgotPasswordRequestOtp(BaseModel):
    """`identifier` is the phone number registered on the account."""

    identifier: str

class UserForgotPasswordVerifyOtp(BaseModel):
    identifier: str
    otp_code: Optional[str] = None

class UserForgotPasswordReset(BaseModel):
    identifier: str
    otp_code: Optional[str] = None
    new_password: str

    @field_validator("new_password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return validate_password_strength(v)

class UserChangePassword(BaseModel):
    current_password: str
    new_password: str
    # Strength is validated inside the route handler, after the current
    # password is confirmed to be correct - not here at request-parse time -
    # so a wrong current password is always reported before a weak new one.


class CurrentPasswordCheck(BaseModel):
    """Body for the dedicated 'verify current password' endpoints. These do
    not change anything; they let the client confirm the current password
    before evaluating confirm-password / strength rules, so the current
    password's correctness is always the first thing the user is told about.
    """

    current_password: str

class ListenerLogin(BaseModel):
    phone: str
    password: str

class ListenerChangePassword(BaseModel):
    current_password: str
    new_password: str
    # Strength is validated inside the route handler, after the current
    # password is confirmed to be correct - see UserChangePassword above.

class ListenerCreate(BaseModel):
    name: str
    phone: str
    password: str
    confirm_reserved_username: bool = False


class AdminListenerPasswordUpdate(BaseModel):
    """Body for an admin resetting a listener's password. No current-password
    check here - the admin's own session (verify_admin) is the authority."""

    new_password: str

    @field_validator("new_password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return validate_password_strength(v)

class AuthResponse(BaseModel):
    token: str
    id: int
    name: str

class GoogleSignIn(BaseModel):
    id_token: str


class GoogleAuthResponse(AuthResponse):
    profile_complete: bool


class FcmTokenUpdate(BaseModel):
    fcm_token: str

class CallInitiate(BaseModel):
    listener_id: int
    call_type: Optional[str] = "audio"

class ListenerStatusUpdate(BaseModel):
    is_online: bool

class AdminListenerStatusUpdate(BaseModel):
    is_online: bool

class ListenerProfileUpdate(BaseModel):
    about: Optional[str] = None
    tags: Optional[list[str]] = None
    languages: Optional[list[str]] = None
    age: Optional[int] = None
    occupation: Optional[str] = None

    
class LiveKitTokenResponse(BaseModel):
    call_id: int
    room_name: str
    token: str
    livekit_url: str

class CallRecordingOut(BaseModel):
    id: int
    call_id: int
    egress_id: str | None
    room_name: str
    file_path: str | None
    status: str
    started_at: datetime
    ended_at: datetime | None

    class Config:
        from_attributes = True
class ChatMessageSend(BaseModel):
    listener_id: int
    message: str
    client_id: Optional[str] = None

class ListenerChatMessageSend(BaseModel):
    user_id: int
    message: str
    client_id: Optional[str] = None

class ChatMessageOut(BaseModel):
    id: int
    client_id: Optional[str] = None
    user_id: int
    listener_id: int
    sender_type: str
    message: str
    message_type: str
    audio_url: Optional[str] = None
    audio_duration: Optional[int] = None
    gift_id: Optional[int] = None
    gift_name: Optional[str] = None
    gift_icon: Optional[str] = None
    gift_coins: Optional[int] = None
    call_id: Optional[int] = None
    call_type: Optional[str] = None
    call_status: Optional[str] = None
    call_duration_seconds: Optional[int] = None
    status: str
    is_read: bool
    delivered_at: Optional[datetime] = None
    read_at: Optional[datetime] = None
    edited_at: Optional[datetime] = None
    is_deleted: bool
    created_at: datetime

    class Config:
        from_attributes = True

class ChatThreadOut(BaseModel):
    user_id: int
    user_name: str
    listener_id: int
    listener_name: str
    last_message: str
    last_message_at: datetime
    last_message_type: str = "text"
    last_call_type: Optional[str] = None
    last_call_status: Optional[str] = None
    last_call_duration_seconds: Optional[int] = None
    unread_count: int
    is_pinned: bool = False
    is_archived: bool = False
    is_muted: bool = False
    is_online: bool = False
    presence_online: bool = False
    last_seen: Optional[datetime] = None
    photo_url: Optional[str] = None
    badge_tag: Optional[dict] = None

class TypingEvent(BaseModel):
    listener_id: Optional[int] = None
    user_id: Optional[int] = None
    is_typing: bool

class MessageEdit(BaseModel):
    message_id: int
    message: str

class ChatSettingsUpdate(BaseModel):
    other_id: int
    is_pinned: Optional[bool] = None
    is_archived: Optional[bool] = None
    is_muted: Optional[bool] = None

class CallHistoryOut(BaseModel):
    id: int
    room_name: str
    user_id: int
    user_name: str
    listener_id: int
    listener_name: str
    call_type: str
    status: str
    duration_seconds: int
    coins_deducted: int
    created_at: datetime
    connected_at: Optional[datetime] = None
    other_party_photo_url: Optional[str] = None
    badge_tag: Optional[dict] = None
    class Config:
        from_attributes = True

class CallRatingSubmit(BaseModel):
    rating: int
    review: Optional[str] = None

class CallSummaryOut(BaseModel):
    call_id: int
    listener_id: int
    listener_name: str
    listener_photo_url: Optional[str] = None
    duration_seconds: int
    coins_deducted: int
    existing_rating: Optional[int] = None
    existing_review: Optional[str] = None
    badge_tag: Optional[dict] = None

class ListenerNoteSave(BaseModel):
    call_id: Optional[int] = None
    user_id: Optional[int] = None
    note: str

class ListenerNoteOut(BaseModel):
    id: int
    listener_id: int
    user_id: int
    call_id: Optional[int] = None
    note: str
    updated_at: datetime
    user_name: Optional[str] = None
    last_call_at: Optional[datetime] = None

    class Config:
        from_attributes = True

class ListenerReviewOut(BaseModel):
    user_name: str
    user_photo_url: Optional[str] = None
    rating: int
    review: Optional[str] = None
    created_at: datetime

class WithdrawalRequestCreate(BaseModel):
    coins: int

class WithdrawalRequestOut(BaseModel):
    id: int
    listener_id: int
    coins: int
    status: str
    admin_username: Optional[str] = None
    decided_at: Optional[datetime] = None
    created_at: datetime
    listener_name: Optional[str] = None

    class Config:
        from_attributes = True

class WithdrawalDecision(BaseModel):
    reason: Optional[str] = None


class AdminNotificationOut(BaseModel):
    id: int
    type: str
    title: str
    body: Optional[str] = None
    subject_type: Optional[str] = None
    subject_id: Optional[int] = None
    subject_name: Optional[str] = None
    related_id: Optional[int] = None
    is_read: bool
    is_done: bool
    done_at: Optional[datetime] = None
    done_by_admin_username: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class AccountDeletionRequestCreate(BaseModel):
    """Optional free-text reason typed by the user before confirming."""
    reason: Optional[str] = None


class AdminInviteCreate(BaseModel):
    expires_in_hours: Optional[int] = 72

class AdminInviteRequestOtp(BaseModel):
    invite_token: str
    email: str

class AdminInviteVerifyOtp(BaseModel):
    invite_token: str
    email: str
    otp_code: str

class AdminInviteComplete(BaseModel):
    invite_token: str
    username: str
    password: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    accuracy_m: Optional[float] = None
    location_label: Optional[str] = None

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return validate_password_strength(v)

class AdminLogin(BaseModel):
    identifier: str
    password: str
    captcha_token: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    accuracy_m: Optional[float] = None
    location_label: Optional[str] = None

class AdminLoginVerifyOtp(BaseModel):
    identifier: str
    otp_code: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    accuracy_m: Optional[float] = None
    location_label: Optional[str] = None

class AdminLogout(BaseModel):
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    accuracy_m: Optional[float] = None
    location_label: Optional[str] = None

class AdminForgotPasswordRequestOtp(BaseModel):
    email: str

class AdminForgotPasswordVerifyOtp(BaseModel):
    email: str
    otp_code: str

class AdminForgotPasswordReset(BaseModel):
    email: str
    otp_code: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return validate_password_strength(v)

class AdminAuthResponse(BaseModel):
    token: str
    id: int
    username: str
    email: Optional[str] = None


EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$")
PHONE_PATTERN = re.compile(r"^\+?\d{7,15}$")


class AdminProfileOut(BaseModel):
    id: int
    username: str
    email: Optional[str] = None
    phone: Optional[str] = None
    photo_url: Optional[str] = None


class AdminProfileUpdate(BaseModel):
    email: str
    phone: Optional[str] = None

    @field_validator("email")
    @classmethod
    def valid_email(cls, v: str) -> str:
        v = (v or "").strip().lower()
        if not EMAIL_PATTERN.match(v):
            raise ValueError("Enter a valid email address")
        if len(v) > 254:
            raise ValueError("Email address is too long")
        return v

    @field_validator("phone")
    @classmethod
    def valid_phone(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        compact = re.sub(r"[\s\-()]", "", v.strip())
        if not compact:
            return None
        if not PHONE_PATTERN.match(compact):
            raise ValueError("Enter a valid phone number (7-15 digits, optional leading +)")
        return compact


class AdminChangePassword(BaseModel):
    current_password: str
    new_password: str
    # Strength is validated inside the route handler, after the current
    # password is confirmed to be correct - see UserChangePassword above.


