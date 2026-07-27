#weekly_challenge.py
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_listener, get_current_admin
from app.models.models import (
    Listener,
    WeeklyChallengeSettings,
    ListenerWeeklyChallengeProgress,
)

router = APIRouter(prefix="/weekly-challenge", tags=["weekly-challenge"])


def _current_week_start(now: datetime | None = None) -> datetime:
    """Monday 00:00 UTC of the current week."""
    now = now or datetime.now(timezone.utc)
    monday = now - timedelta(days=now.weekday())
    return monday.replace(hour=0, minute=0, second=0, microsecond=0)


def _get_settings(db: Session) -> WeeklyChallengeSettings:
    settings = db.query(WeeklyChallengeSettings).first()
    if not settings:
        settings = WeeklyChallengeSettings()
        db.add(settings)
        db.commit()
        db.refresh(settings)
    return settings


def _challenge_expiry(activated_at: datetime) -> datetime:
    """Saturday 23:59:59.999999 of the week the challenge was activated in."""
    week_start = _current_week_start(activated_at)
    saturday = week_start + timedelta(days=5)
    return saturday.replace(hour=23, minute=59, second=59, microsecond=999999)


def _is_challenge_active(db: Session, settings: WeeklyChallengeSettings) -> bool:
    """True if the admin has set a challenge and it hasn't passed Saturday
    11:59pm of that week yet. Lazily flips is_active off (and persists it)
    once the deadline has passed, so the listener icon disappears without
    needing a cron job."""
    if not settings.is_active or not settings.activated_at:
        return False
    now = datetime.now(timezone.utc)
    if now > _challenge_expiry(settings.activated_at):
        settings.is_active = False
        db.commit()
        return False
    return True



def _get_or_create_progress(db: Session, listener_id: int, week_start: datetime) -> ListenerWeeklyChallengeProgress:
    progress = (
        db.query(ListenerWeeklyChallengeProgress)
        .filter(
            ListenerWeeklyChallengeProgress.listener_id == listener_id,
            ListenerWeeklyChallengeProgress.week_start == week_start,
        )
        .first()
    )
    if not progress:
        progress = ListenerWeeklyChallengeProgress(
            listener_id=listener_id,
            week_start=week_start,
            talk_seconds=0,
        )
        db.add(progress)
        db.commit()
        db.refresh(progress)
    return progress


def add_talktime_seconds(db: Session, listener_id: int, seconds: int) -> ListenerWeeklyChallengeProgress:
    """Add talktime from a completed audio or video call to the listener's
    weekly challenge progress, and stamp any goals that just got crossed.
    Called from the call finalization paths in app/routers/call.py.
    """
    if seconds <= 0:
        return None

    settings = _get_settings(db)
    week_start = _current_week_start()
    progress = _get_or_create_progress(db, listener_id, week_start)

    progress.talk_seconds += int(seconds)

    now = datetime.now(timezone.utc)
    if progress.goal1_completed_at is None and progress.talk_seconds >= settings.goal1_minutes * 60:
        progress.goal1_completed_at = now
    if progress.goal2_completed_at is None and progress.talk_seconds >= settings.goal2_minutes * 60:
        progress.goal2_completed_at = now
    if progress.goal3_completed_at is None and progress.talk_seconds >= settings.goal3_minutes * 60:
        progress.goal3_completed_at = now

    db.commit()
    db.refresh(progress)
    return progress


def _serialize_goals(settings: WeeklyChallengeSettings, progress: ListenerWeeklyChallengeProgress | None):
    goal_defs = [
        (settings.goal1_minutes, progress.goal1_completed_at if progress else None),
        (settings.goal2_minutes, progress.goal2_completed_at if progress else None),
        (settings.goal3_minutes, progress.goal3_completed_at if progress else None),
    ]
    return [
        {
            "minutes": minutes,
            "completed": completed_at is not None,
            "completed_at": completed_at.isoformat() if completed_at else None,
        }
        for minutes, completed_at in goal_defs
    ]


@router.get("/progress")
def get_my_progress(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    """Listener-facing endpoint: current week's talktime + the 3 admin-set
    goals, plus whether a challenge is currently active. The Flutter app
    should hide the weekly-challenge icon entirely when active is false."""
    settings = _get_settings(db)
    active = _is_challenge_active(db, settings)
    if not active:
        return {"active": False, "talk_seconds": 0, "goals": []}

    week_start = _current_week_start()
    progress = (
        db.query(ListenerWeeklyChallengeProgress)
        .filter(
            ListenerWeeklyChallengeProgress.listener_id == current_listener.id,
            ListenerWeeklyChallengeProgress.week_start == week_start,
        )
        .first()
    )
    return {
        "active": True,
        "talk_seconds": progress.talk_seconds if progress else 0,
        "goals": _serialize_goals(settings, progress),
    }



@router.get("/admin/goals")
def get_goals(db: Session = Depends(get_db), _=Depends(get_current_admin)):
    settings = _get_settings(db)
    active = _is_challenge_active(db, settings)
    return {
        "goal1_minutes": settings.goal1_minutes,
        "goal2_minutes": settings.goal2_minutes,
        "goal3_minutes": settings.goal3_minutes,
        "active": active,
        "expires_at": _challenge_expiry(settings.activated_at).isoformat()
        if active and settings.activated_at
        else None,
    }


@router.put("/admin/goals")
def update_goals(
    goal1_minutes: int,
    goal2_minutes: int,
    goal3_minutes: int,
    db: Session = Depends(get_db),
    _=Depends(get_current_admin),
):
    """Saving goals (re)starts the weekly challenge: it goes live immediately
    and expires Saturday 11:59pm of the current week, at which point it
    disappears from the listener app until the admin sets a new one."""
    settings = _get_settings(db)
    settings.goal1_minutes = goal1_minutes
    settings.goal2_minutes = goal2_minutes
    settings.goal3_minutes = goal3_minutes
    settings.is_active = True
    settings.activated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(settings)
    return {
        "goal1_minutes": settings.goal1_minutes,
        "goal2_minutes": settings.goal2_minutes,
        "goal3_minutes": settings.goal3_minutes,
        "active": True,
        "expires_at": _challenge_expiry(settings.activated_at).isoformat(),
    }



@router.get("/admin/leaderboard")
def get_leaderboard(db: Session = Depends(get_db), _=Depends(get_current_admin)):
    """Top 3 listeners this week by talktime, for the admin panel."""
    settings = _get_settings(db)
    week_start = _current_week_start()
    rows = (
        db.query(ListenerWeeklyChallengeProgress)
        .filter(ListenerWeeklyChallengeProgress.week_start == week_start)
        .filter(ListenerWeeklyChallengeProgress.talk_seconds > 0)
        .order_by(ListenerWeeklyChallengeProgress.talk_seconds.desc())
        .limit(3)
        .all()
    )
    result = []
    for rank, progress in enumerate(rows, start=1):
        listener = db.query(Listener).filter(Listener.id == progress.listener_id).first()
        result.append(
            {
                "rank": rank,
                "listener_id": progress.listener_id,
                "listener_name": listener.name if listener else "Unknown",
                "listener_photo_url": listener.photo_url if listener else None,
                "talk_seconds": progress.talk_seconds,
                "goals": _serialize_goals(settings, progress),
            }
        )
    return result


@router.get("/admin/completions")
def get_completions(db: Session = Depends(get_db), _=Depends(get_current_admin)):
    """Admin-facing endpoint: every listener who has logged talktime this
    week, with only the 3 goal statuses shown (no in-between progress)."""
    settings = _get_settings(db)
    week_start = _current_week_start()
    rows = (
        db.query(ListenerWeeklyChallengeProgress)
        .filter(ListenerWeeklyChallengeProgress.week_start == week_start)
        .filter(ListenerWeeklyChallengeProgress.talk_seconds > 0)
        .order_by(ListenerWeeklyChallengeProgress.talk_seconds.desc())
        .all()
    )
    result = []
    for progress in rows:
        listener = db.query(Listener).filter(Listener.id == progress.listener_id).first()
        result.append(
            {
                "listener_id": progress.listener_id,
                "listener_name": listener.name if listener else "Unknown",
                "talk_seconds": progress.talk_seconds,
                "goals": _serialize_goals(settings, progress),
            }
        )
    return result
