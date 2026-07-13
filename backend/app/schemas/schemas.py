from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class UserRegisterInitiate(BaseModel):
    name: str
    email: str
    phone: str
    password: str

class UserRegisterVerifyOtp(BaseModel):
    email: str
    otp_code: str

class UserLogin(BaseModel):
    phone: str
    password: str

class UserBioUpdate(BaseModel):
    bio: str

class ListenerLogin(BaseModel):
    phone: str
    password: str

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

class AdminAuthResponse(BaseModel):
    token: str
    id: int
    username: str
    email: Optional[str] = None

