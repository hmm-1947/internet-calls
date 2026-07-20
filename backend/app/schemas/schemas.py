import re

from pydantic import BaseModel, field_validator
from typing import Optional
from datetime import datetime

ALLOWED_PLAN_ICONS = {"coin", "diamond", "star"}


def validate_password_strength(v: str) -> str:
    v = v or ""
    if len(v) < 8:
        raise ValueError("Password must be at least 8 characters long")
    if " " in v:
        raise ValueError("Password must not contain spaces")
    if not re.search(r"[A-Z]", v):
        raise ValueError("Password must contain at least one uppercase letter")
    if not re.search(r"[a-z]", v):
        raise ValueError("Password must contain at least one lowercase letter")
    if not re.search(r"[0-9]", v):
        raise ValueError("Password must contain at least one number")
    if not re.search(r"[^A-Za-z0-9]", v):
        raise ValueError("Password must contain at least one special character")
    return v



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
    created_at: datetime
    updated_at: Optional[datetime] = None

class UserRegisterInitiate(BaseModel):
    name: str
    email: str
    phone: str
    password: str

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return validate_password_strength(v)

class UserRegisterVerifyOtp(BaseModel):
    email: str
    otp_code: str

class UserLogin(BaseModel):
    phone: str
    password: str

class UserBioUpdate(BaseModel):
    bio: str

class UserForgotPasswordRequestOtp(BaseModel):
    email: str

class UserForgotPasswordVerifyOtp(BaseModel):
    email: str
    otp_code: str

class UserForgotPasswordReset(BaseModel):
    email: str
    otp_code: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return validate_password_strength(v)

class UserChangePassword(BaseModel):
    current_password: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return validate_password_strength(v)

class ListenerLogin(BaseModel):
    phone: str
    password: str

class ListenerChangePassword(BaseModel):
    current_password: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return validate_password_strength(v)

class ListenerCreate(BaseModel):
    name: str
    phone: str
    password: str

class AuthResponse(BaseModel):
    token: str
    id: int
    name: str

class FcmTokenUpdate(BaseModel):
    fcm_token: str

class CallInitiate(BaseModel):
    listener_id: int
    call_type: Optional[str] = "audio"

class ListenerStatusUpdate(BaseModel):
    is_online: bool

class ListenerProfileUpdate(BaseModel):
    about: Optional[str] = None
    tags: Optional[list[str]] = None
    languages: Optional[list[str]] = None

    
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
    unread_count: int
    is_pinned: bool = False
    is_archived: bool = False
    is_muted: bool = False
    is_online: bool = False
    last_seen: Optional[datetime] = None
    photo_url: Optional[str] = None

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

    class Config:
        from_attributes = True

class CallRatingSubmit(BaseModel):
    rating: int
    review: Optional[str] = None

class CallSummaryOut(BaseModel):
    call_id: int
    listener_id: int
    listener_name: str
    duration_seconds: int
    coins_deducted: int
    existing_rating: Optional[int] = None
    existing_review: Optional[str] = None

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

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return validate_password_strength(v)

class AdminLogin(BaseModel):
    identifier: str
    password: str

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

