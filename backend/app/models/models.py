from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.sql import func
from app.core.database import Base
from sqlalchemy import Index

#models.py
class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    phone = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    fcm_token = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)
    is_online = Column(Boolean, default=False)
    last_seen = Column(DateTime(timezone=True), nullable=True)
    coins = Column(Integer, default=0)
    bio = Column(String, nullable=True)
    photo_url = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Listener(Base):
    __tablename__ = "listeners"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    phone = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    fcm_token = Column(String, nullable=True)
    is_online = Column(Boolean, default=False)
    is_active = Column(Boolean, default=True)
    last_seen = Column(DateTime(timezone=True), nullable=True)
    about = Column(String, nullable=True)
    tags = Column(String, nullable=True)
    languages = Column(String, nullable=True)
    coins = Column(Integer, default=0, nullable=False)
    photo_url = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())



class Session(Base):
    __tablename__ = "sessions"

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String, unique=True, index=True, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    listener_id = Column(Integer, ForeignKey("listeners.id"), nullable=True)
    admin_id = Column(Integer, ForeignKey("admin_users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class AdminUser(Base):
    __tablename__ = "admin_users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    email = Column(String, unique=True, index=True, nullable=True)
    password_hash = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)
    is_support = Column(Boolean, default=False)
    reset_otp_code = Column(String, nullable=True)
    reset_otp_expires_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class AdminInvite(Base):
    __tablename__ = "admin_invites"

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String, unique=True, index=True, nullable=False)
    email = Column(String, nullable=True)
    otp_code = Column(String, nullable=True)
    otp_expires_at = Column(DateTime(timezone=True), nullable=True)
    email_verified = Column(Boolean, default=False)
    is_used = Column(Boolean, default=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Call(Base):
    __tablename__ = "calls"

    id = Column(Integer, primary_key=True, index=True)
    room_name = Column(String, nullable=False)
    caller_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    callee_listener_id = Column(Integer, ForeignKey("listeners.id"), nullable=False)
    status = Column(String, default="ringing", index=True)
    call_type = Column(String, default="audio")
    connected_at = Column(DateTime(timezone=True), nullable=True)
    coins_deducted = Column(Integer, default=0)
    duration_seconds = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        Index(
            'ix_one_active_call_per_listener',
            'callee_listener_id',
            unique=True,
            postgresql_where=Column('status').in_(['ringing', 'accepted']),
        ),
    )

class CallRecording(Base):
    __tablename__ = "call_recordings"

    id = Column(Integer, primary_key=True, index=True)
    call_id = Column(Integer, ForeignKey("calls.id"), nullable=False)
    egress_id = Column(String, nullable=True)
    room_name = Column(String, nullable=False)
    file_path = Column(String, nullable=True)
    status = Column(String, default="recording")
    started_at = Column(DateTime(timezone=True), server_default=func.now())
    ended_at = Column(DateTime(timezone=True), nullable=True)

class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id = Column(Integer, primary_key=True, index=True)
    client_id = Column(String, nullable=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    listener_id = Column(Integer, ForeignKey("listeners.id"), nullable=False, index=True)
    sender_type = Column(String, nullable=False)
    message = Column(String, nullable=False)
    message_type = Column(String, default="text")
    audio_url = Column(String, nullable=True)
    audio_duration = Column(Integer, nullable=True)
    status = Column(String, default="sent")
    is_read = Column(Boolean, default=False)
    delivered_at = Column(DateTime(timezone=True), nullable=True)
    read_at = Column(DateTime(timezone=True), nullable=True)
    edited_at = Column(DateTime(timezone=True), nullable=True)
    is_deleted = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class ChatSettings(Base):
    __tablename__ = "chat_settings"

    id = Column(Integer, primary_key=True, index=True)
    owner_type = Column(String, nullable=False)
    owner_id = Column(Integer, nullable=False)
    other_id = Column(Integer, nullable=False)
    is_pinned = Column(Boolean, default=False)
    is_archived = Column(Boolean, default=False)
    is_muted = Column(Boolean, default=False)

class CoinSettings(Base):
    __tablename__ = "coin_settings"

    id = Column(Integer, primary_key=True, index=True)
    audio_coins_per_minute = Column(Integer, default=10)
    video_coins_per_minute = Column(Integer, default=10)
    chat_message_coins = Column(Integer, default=1, nullable=False)


class CoinTransaction(Base):
    __tablename__ = "coin_transactions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    amount = Column(Integer, nullable=False)
    reason = Column(String, nullable=False)
    call_id = Column(Integer, ForeignKey("calls.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class ListenerCoinTransaction(Base):
    __tablename__ = "listener_coin_transactions"

    id = Column(Integer, primary_key=True, index=True)
    listener_id = Column(Integer, ForeignKey("listeners.id"), nullable=False)
    amount = Column(Integer, nullable=False)
    reason = Column(String, nullable=False)
    call_id = Column(Integer, ForeignKey("calls.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Gift(Base):
    __tablename__ = "gifts"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    coins = Column(Integer, nullable=False)
    icon = Column(String, nullable=True)

class GiftTransaction(Base):
    __tablename__ = "gift_transactions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    listener_id = Column(Integer, ForeignKey("listeners.id"), nullable=False)
    gift_id = Column(Integer, ForeignKey("gifts.id"), nullable=False)
    coins = Column(Integer, nullable=False)
    call_id = Column(Integer, ForeignKey("calls.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    notified = Column(Boolean, nullable=False, server_default="false")

class CallRating(Base):

    __tablename__ = "call_ratings"

    id = Column(Integer, primary_key=True, index=True)
    call_id = Column(Integer, ForeignKey("calls.id"), nullable=False, unique=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    listener_id = Column(Integer, ForeignKey("listeners.id"), nullable=False, index=True)
    rating = Column(Integer, nullable=False)
    review = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class ListenerNote(Base):
    __tablename__ = "listener_notes"

    id = Column(Integer, primary_key=True, index=True)
    listener_id = Column(Integer, ForeignKey("listeners.id"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    call_id = Column(Integer, ForeignKey("calls.id"), nullable=True, index=True)
    note = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index('ix_listener_notes_pair', 'listener_id', 'user_id'),
    )

class BillingPlan(Base):
    __tablename__ = "billing_plans"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    price = Column(Integer, nullable=False)
    coins = Column(Integer, nullable=False)  # coins granted to the user on purchase
    icon = Column(String, nullable=False, default="coin")  # coin | diamond | star
    is_featured = Column(Boolean, default=False, nullable=False)  # "Best Seller" style badge
    is_active = Column(Boolean, default=True, nullable=False)  # visible to users
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class BillingPlanAuditLog(Base):
    __tablename__ = "billing_plan_audit_logs"

    id = Column(Integer, primary_key=True, index=True)
    action = Column(String, nullable=False, index=True)  # created | updated | deleted
    plan_id = Column(Integer, nullable=True, index=True)  # kept even if the plan is later deleted
    plan_name = Column(String, nullable=False)
    admin_id = Column(Integer, ForeignKey("admin_users.id"), nullable=True)
    admin_username = Column(String, nullable=True)  # snapshot in case the admin is later removed
    details = Column(Text, nullable=True)  # human-readable summary of what changed
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class UserBillingPurchase(Base):
    __tablename__ = "user_billing_purchases"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    plan_id = Column(Integer, ForeignKey("billing_plans.id"), nullable=False, index=True)
    plan_name = Column(String, nullable=False)
    price_paid = Column(Integer, nullable=False)
    coins_purchased = Column(Integer, nullable=False, default=0)
    status = Column(String, default="pending", nullable=False)  # pending | completed | failed
    razorpay_order_id = Column(String, nullable=True, index=True)
    razorpay_payment_id = Column(String, nullable=True, index=True)
    razorpay_signature = Column(String, nullable=True)
    failure_reason = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())



class EmailOtp(Base):
    __tablename__ = "email_otps"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, nullable=False, index=True)
    otp_code = Column(String, nullable=False)
    name = Column(String, nullable=False)
    phone = Column(String, nullable=False)
    password_hash = Column(String, nullable=False)
    is_verified = Column(Boolean, default=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())