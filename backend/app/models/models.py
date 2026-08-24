from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.sql import func
from app.core.database import Base
from sqlalchemy import Index

#models.py
class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    # Lower-cased unique handle chosen by the user at sign-up. Stored lower-cased
    # so the unique index also makes the username case-insensitively unique.
    # Nullable because accounts created before usernames existed have none.
    username = Column(String, unique=True, index=True, nullable=True)
    # Exactly one of email / phone is filled at sign-up (the user picks the
    # channel), so both are nullable and the other can be added later.
    email = Column(String, unique=True, index=True, nullable=True)
    phone = Column(String, unique=True, index=True, nullable=True)
    password_hash = Column(String, nullable=True)
    google_uid = Column(String, unique=True, index=True, nullable=True)
    fcm_token = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)
    is_online = Column(Boolean, default=False)
    last_seen = Column(DateTime(timezone=True), nullable=True)
    coins = Column(Integer, default=0)
    bio = Column(String, nullable=True)
    photo_url = Column(String, nullable=True)
    reset_otp_code = Column(String, nullable=True)
    reset_otp_expires_at = Column(DateTime(timezone=True), nullable=True)
    reset_otp_attempts = Column(Integer, default=0, nullable=False, server_default="0")
    # Stamped every time the handle / contact details are set from the edit
    # profile screen, so the 24h cool-down on each of them can be enforced.
    # Null means "never changed", i.e. no cool-down is in force.
    username_changed_at = Column(DateTime(timezone=True), nullable=True)
    email_changed_at = Column(DateTime(timezone=True), nullable=True)
    phone_changed_at = Column(DateTime(timezone=True), nullable=True)
    # An email/phone change that has been requested but not verified yet. The
    # new value only lands on `email`/`phone` once the OTP is confirmed, so an
    # abandoned change never locks the user out of their account.
    # For phone changes Firebase sends and checks the SMS, so `otp_code` stays
    # null and the signed Firebase token is the proof instead.
    pending_contact_channel = Column(String, nullable=True)
    pending_contact_identifier = Column(String, nullable=True)
    pending_contact_otp_code = Column(String, nullable=True)
    pending_contact_otp_expires_at = Column(DateTime(timezone=True), nullable=True)
    pending_contact_otp_attempts = Column(Integer, default=0, nullable=False, server_default="0")
    video_call_enabled = Column(Boolean, default=True, nullable=False, server_default="1")
    video_call_disabled_by_admin = Column(Boolean, default=False, nullable=False, server_default="0")
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
    age = Column(Integer, nullable=True)
    occupation = Column(String, nullable=True)
    coins = Column(Integer, default=0, nullable=False)
    photo_url = Column(String, nullable=True)
    badge_tag_id = Column(Integer, ForeignKey("listener_badge_tags.id"), nullable=True)
    video_call_enabled = Column(Boolean, default=True, nullable=False, server_default="1")
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class ListenerBadgeTag(Base):
    __tablename__ = "listener_badge_tags"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, nullable=False)
    color = Column(String, nullable=False, server_default="#E11D48")
    created_at = Column(DateTime(timezone=True), server_default=func.now())



class Session(Base):
    __tablename__ = "sessions"

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String, unique=True, index=True, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    listener_id = Column(Integer, ForeignKey("listeners.id"), nullable=True)
    admin_id = Column(Integer, ForeignKey("admin_users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=False)

class AdminUser(Base):
    __tablename__ = "admin_users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    email = Column(String, unique=True, index=True, nullable=True)
    phone = Column(String, nullable=True)
    photo_url = Column(String, nullable=True)
    password_hash = Column(String, nullable=False)
    failed_login_attempts = Column(Integer, default=0, nullable=False)
    locked_until = Column(DateTime(timezone=True), nullable=True)
    is_active = Column(Boolean, default=True)
    is_support = Column(Boolean, default=False)
    reset_otp_code = Column(String, nullable=True)
    reset_otp_expires_at = Column(DateTime(timezone=True), nullable=True)
    reset_otp_attempts = Column(Integer, default=0, nullable=False, server_default="0")
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class AdminInvite(Base):
    __tablename__ = "admin_invites"

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String, unique=True, index=True, nullable=False)
    email = Column(String, nullable=True)
    otp_code = Column(String, nullable=True)
    otp_expires_at = Column(DateTime(timezone=True), nullable=True)
    otp_attempts = Column(Integer, default=0, nullable=False, server_default="0")
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
    billed_minutes = Column(Integer, default=0)
    duration_seconds = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        Index(
            'ix_one_active_call_per_listener',
            'callee_listener_id',
            unique=True,
            postgresql_where=Column('status').in_(['ringing', 'accepted']),
        ),
        Index('ix_calls_caller_status', 'caller_user_id', 'status'),
        Index('ix_calls_callee_status', 'callee_listener_id', 'status'),
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
    gift_id = Column(Integer, nullable=True, index=True)  # kept even if the gift is later deleted/renamed
    gift_name = Column(String, nullable=True)
    gift_icon = Column(String, nullable=True)
    gift_coins = Column(Integer, nullable=True)  # full gift cost paid by the sender
    call_id = Column(Integer, nullable=True)  # set when the gift/message was sent during an active call
    # Populated only when message_type == "call": denormalized so the chat
    # list/history can render a call-log row without a join back to `calls`.
    call_type = Column(String, nullable=True)  # "audio" | "video"
    call_status = Column(String, nullable=True)  # "completed" | "missed" | "declined" | "cancelled"
    call_duration_seconds = Column(Integer, nullable=True)
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
    voice_message_coins = Column(Integer, default=1, nullable=False)


class AppSettings(Base):
    __tablename__ = "app_settings"

    id = Column(Integer, primary_key=True, index=True)
    ringtone_url = Column(String, nullable=True)
    ringtone_version = Column(Integer, default=0, nullable=False)
    upgrade_banner_url = Column(String, nullable=True)
    terms_of_service = Column(Text, nullable=True)
    privacy_policy = Column(Text, nullable=True)



class WeeklyChallengeSettings(Base):
    __tablename__ = "weekly_challenge_settings"

    id = Column(Integer, primary_key=True, index=True)
    goal1_minutes = Column(Integer, default=30, nullable=False)
    goal2_minutes = Column(Integer, default=60, nullable=False)
    goal3_minutes = Column(Integer, default=120, nullable=False)
    is_active = Column(Boolean, default=False, nullable=False, server_default="0")
    activated_at = Column(DateTime(timezone=True), nullable=True)


class ListenerWeeklyChallengeProgress(Base):
    __tablename__ = "listener_weekly_challenge_progress"

    id = Column(Integer, primary_key=True, index=True)
    listener_id = Column(Integer, ForeignKey("listeners.id"), nullable=False, index=True)
    week_start = Column(DateTime(timezone=True), nullable=False, index=True)
    talk_seconds = Column(Integer, default=0, nullable=False)
    goal1_minutes = Column(Integer, nullable=True)
    goal2_minutes = Column(Integer, nullable=True)
    goal3_minutes = Column(Integer, nullable=True)
    goal1_completed_at = Column(DateTime(timezone=True), nullable=True)
    goal2_completed_at = Column(DateTime(timezone=True), nullable=True)
    goal3_completed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        Index(
            "ix_one_progress_row_per_listener_per_week",
            "listener_id",
            "week_start",
            unique=True,
        ),
    )


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


class GiftAuditLog(Base):
    __tablename__ = "gift_audit_logs"

    id = Column(Integer, primary_key=True, index=True)
    action = Column(String, nullable=False, index=True)  # created | updated | deleted
    gift_id = Column(Integer, nullable=True, index=True)  # kept even if the gift is later deleted
    gift_name = Column(String, nullable=False)
    admin_id = Column(Integer, ForeignKey("admin_users.id"), nullable=True)
    admin_username = Column(String, nullable=True)  # snapshot in case the admin is later removed
    details = Column(Text, nullable=True)  # human-readable summary of what changed
    created_at = Column(DateTime(timezone=True), server_default=func.now())

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

class SpecialOffer(Base):
    __tablename__ = "special_offers"

    id = Column(Integer, primary_key=True, index=True)
    image_url = Column(String, nullable=False)
    sort_order = Column(Integer, nullable=False, server_default="0")
    is_active = Column(Boolean, nullable=False, server_default="true")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

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
    status = Column(String, default="pending", nullable=False)  # pending | completed | failed | partially_refunded | refunded
    razorpay_order_id = Column(String, nullable=True, index=True)
    razorpay_payment_id = Column(String, nullable=True, index=True)
    razorpay_signature = Column(String, nullable=True)
    failure_reason = Column(String, nullable=True)
    # Refunds are always initiated outside this app (Razorpay dashboard, or
    # Razorpay's own auto-refund of an uncaptured payment). These three
    # columns are a record of money that left the account; the coins are NOT
    # clawed back automatically because they may already have been spent.
    razorpay_refund_id = Column(String, nullable=True, index=True)  # most recent refund seen
    refunded_amount_paise = Column(Integer, nullable=False, default=0, server_default="0")
    refunded_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())



class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, index=True)
    subject_type = Column(String, nullable=False, index=True)  # "user" | "listener"
    subject_id = Column(Integer, nullable=False, index=True)
    subject_name = Column(String, nullable=False)  # snapshot in case the account is later renamed/deleted
    action = Column(String, nullable=False, index=True)  # "login" | "logout"
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)

    __table_args__ = (
        Index('ix_audit_logs_subject_type_created_at', 'subject_type', 'created_at'),
    )


class AdminNotification(Base):
    """Something that happened in the apps and needs an admin's attention.

    Rows are never deleted: "mark as done" only flips `is_done`, so the panel
    stops showing it while the trail of who handled it stays intact.
    `is_read` is separate and only drives the red counter in the sidebar - it
    is cleared as soon as an admin opens the notifications page.
    """

    __tablename__ = "admin_notifications"

    id = Column(Integer, primary_key=True, index=True)
    type = Column(String, nullable=False, index=True)  # e.g. "account_deletion_request"
    title = Column(String, nullable=False)
    body = Column(Text, nullable=True)
    subject_type = Column(String, nullable=True)  # "user" | "listener"
    subject_id = Column(Integer, nullable=True, index=True)
    subject_name = Column(String, nullable=True)  # snapshot in case the account is later removed
    # Id of a related row the panel needs to look the notification up by,
    # e.g. the withdrawal_requests.id for a "withdrawal_request" notification
    # (subject_id/subject_type point at the listener, not the request).
    related_id = Column(Integer, nullable=True)
    is_read = Column(Boolean, default=False, nullable=False, server_default="false")
    is_done = Column(Boolean, default=False, nullable=False, server_default="false")
    done_at = Column(DateTime(timezone=True), nullable=True)
    done_by_admin_id = Column(Integer, ForeignKey("admin_users.id", ondelete="SET NULL"), nullable=True)
    done_by_admin_username = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)

    __table_args__ = (
        Index('ix_admin_notifications_done_created', 'is_done', 'created_at'),
    )


class WithdrawalRequest(Base):
    __tablename__ = "withdrawal_requests"

    id = Column(Integer, primary_key=True, index=True)
    listener_id = Column(Integer, ForeignKey("listeners.id", ondelete="CASCADE"), nullable=False, index=True)
    coins = Column(Integer, nullable=False)
    status = Column(String, nullable=False, default="pending", server_default="pending", index=True)  # pending | approved | rejected
    admin_id = Column(Integer, ForeignKey("admin_users.id", ondelete="SET NULL"), nullable=True)
    admin_username = Column(String, nullable=True)  # snapshot in case the admin is later removed
    decided_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)

    __table_args__ = (
        Index('ix_withdrawal_requests_listener_created', 'listener_id', 'created_at'),
    )


class PendingSignup(Base):
    """A sign-up that has been started but not finished.

    The row is created when the user submits their email/phone and password,
    and is deleted once the account exists. No `users` row is written until the
    identifier is verified and the profile step is done, so an abandoned
    sign-up never occupies an email, phone or username.

    `channel` is "email" or "phone":
    - email: we generate `otp_code` ourselves and mail it.
    - phone: Firebase sends and checks the SMS code, so `otp_code` stays null
      and we only trust the signed Firebase token handed back to us.
    """

    __tablename__ = "pending_signups"

    id = Column(Integer, primary_key=True, index=True)
    # Lower-cased email or 10-digit phone; unique so a retry reuses the row.
    identifier = Column(String, nullable=False, unique=True, index=True)
    channel = Column(String, nullable=False)
    password_hash = Column(String, nullable=False)
    otp_code = Column(String, nullable=True)
    otp_expires_at = Column(DateTime(timezone=True), nullable=True)
    otp_attempts = Column(Integer, default=0, nullable=False, server_default="0")
    otp_sent_count = Column(Integer, default=0, nullable=False, server_default="0")
    is_verified = Column(Boolean, default=False, nullable=False, server_default="0")
    # Handed to the client after verification and exchanged for the account in
    # the final profile step, so that step cannot be called without verifying.
    signup_token = Column(String, nullable=True, unique=True, index=True)
    signup_token_expires_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class ReservedUsername(Base):
    """Holds a username a user has moved away from so nobody else can claim it
    for a cool-down period after the change.

    A row is inserted whenever `User.username` is changed away from a value,
    with `released_at` set 45 days out. Availability checks treat the
    username as taken until `released_at` passes, after which the row is
    just stale data that can be ignored or purged.
    """

    __tablename__ = "reserved_usernames"

    id = Column(Integer, primary_key=True, index=True)
    # Lower-cased, matching how `User.username` is stored.
    username = Column(String, nullable=False, index=True)
    reserved_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    released_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

