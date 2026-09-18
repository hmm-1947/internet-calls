"""Day/night activity breakdown for a listener, scoped to a calendar week.

Used by the listener wallet screen (current + previous week) and by the
admin panel's withdrawal-request popup (current week only). Kept in one
place so the "day" window (05:00-21:00) and "week" boundary (Monday) can't
drift between the two call sites.
"""
from datetime import datetime, timedelta, timezone

from sqlalchemy import extract
from sqlalchemy import func as sa_func
from sqlalchemy.orm import Session

DAY_START_HOUR = 5
DAY_END_HOUR = 21

# Timestamps are stored in UTC (see models.py `created_at` columns), but the
# day/night split is meant in IST — the same convention already used for the
# weekly-challenge boundary (see routers/weekly_challenge.py). Shifting the
# column by the IST offset before calling extract('hour', ...) turns the UTC
# instant into the equivalent IST wall-clock hour.
IST_OFFSET = timedelta(hours=5, minutes=30)


def week_bounds(reference: datetime | None = None, weeks_ago: int = 0):
    """Returns (start, end) datetimes [inclusive, exclusive) for the Monday-
    Sunday week `weeks_ago` weeks before the week containing `reference`."""
    now = reference or datetime.now(timezone.utc)
    start_of_this_week = (now - timedelta(days=now.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    start = start_of_this_week - timedelta(weeks=weeks_ago)
    end = start + timedelta(weeks=1)
    return start, end


def day_night_breakdown(db: Session, listener_id: int, start: datetime, end: datetime) -> dict:
    """Audio/video minutes, chat/voice message counts and gift coins earned
    by `listener_id` in [start, end), split into day (05:00-21:00) and
    night buckets."""
    from app.models.models import Call, ChatMessage, GiftTransaction

    def split_sum(amount_col, time_col, filters, whole_minutes: bool = False):
        base = [*filters, time_col >= start, time_col < end]
        ist_hour = extract('hour', time_col + IST_OFFSET)
        # For call durations, wallet minutes should only count a call once it
        # has run a full 60 seconds - a 59-second call contributes 0, not a
        # rounded-up 1. Each row is floored to its own whole-minute boundary
        # *before* summing, so two 59-second calls don't add up to a
        # "minute" together either.
        col = (amount_col - amount_col % 60) if whole_minutes else amount_col
        day_sum = db.query(sa_func.coalesce(sa_func.sum(col), 0)).filter(
            *base, ist_hour >= DAY_START_HOUR, ist_hour < DAY_END_HOUR,
        ).scalar()
        night_sum = db.query(sa_func.coalesce(sa_func.sum(col), 0)).filter(
            *base, (ist_hour < DAY_START_HOUR) | (ist_hour >= DAY_END_HOUR),
        ).scalar()
        return int(day_sum), int(night_sum)

    def split_count(id_col, time_col, filters):
        base = [*filters, time_col >= start, time_col < end]
        ist_hour = extract('hour', time_col + IST_OFFSET)
        day_count = db.query(sa_func.count(id_col)).filter(
            *base, ist_hour >= DAY_START_HOUR, ist_hour < DAY_END_HOUR,
        ).scalar()
        night_count = db.query(sa_func.count(id_col)).filter(
            *base, (ist_hour < DAY_START_HOUR) | (ist_hour >= DAY_END_HOUR),
        ).scalar()
        return int(day_count), int(night_count)

    audio_day, audio_night = split_sum(
        Call.duration_seconds, Call.created_at,
        [Call.callee_listener_id == listener_id, Call.call_type == "audio"],
        whole_minutes=True,
    )
    video_day, video_night = split_sum(
        Call.duration_seconds, Call.created_at,
        [Call.callee_listener_id == listener_id, Call.call_type == "video"],
        whole_minutes=True,
    )
    text_day, text_night = split_count(
        ChatMessage.id, ChatMessage.created_at,
        [ChatMessage.listener_id == listener_id, ChatMessage.sender_type == "user", ChatMessage.message_type == "text"],
    )
    voice_day, voice_night = split_count(
        ChatMessage.id, ChatMessage.created_at,
        [ChatMessage.listener_id == listener_id, ChatMessage.sender_type == "user", ChatMessage.message_type == "audio"],
    )
    gift_day, gift_night = split_sum(
        GiftTransaction.coins, GiftTransaction.created_at,
        [GiftTransaction.listener_id == listener_id],
    )

    return {
        "day": {
            "audio_call_minutes": audio_day // 60,
            "video_call_minutes": video_day // 60,
            "chat_messages": text_day,
            "voice_messages": voice_day,
            "gift_coins": gift_day,
        },
        "night": {
            "audio_call_minutes": audio_night // 60,
            "video_call_minutes": video_night // 60,
            "chat_messages": text_night,
            "voice_messages": voice_night,
            "gift_coins": gift_night,
        },
    }


def current_and_previous_week(db: Session, listener_id: int) -> dict:
    cur_start, cur_end = week_bounds(weeks_ago=0)
    prev_start, prev_end = week_bounds(weeks_ago=1)
    return {
        "current_week": day_night_breakdown(db, listener_id, cur_start, cur_end),
        "previous_week": day_night_breakdown(db, listener_id, prev_start, prev_end),
    }
