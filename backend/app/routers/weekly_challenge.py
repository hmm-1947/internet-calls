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

# This app only follows Indian time for the weekly challenge: the week
# boundary (and the Saturday 11:59pm cutoff) is always computed in IST,
# regardless of what timezone the server itself runs in.
IST = timezone(timedelta(hours=5, minutes=30))


def _current_week_start(now: datetime | None = None) -> datetime:
    """Sunday 00:00 IST of the current week, returned as a UTC instant so it
    stays comparable with the rest of the (UTC-stored) timestamps. The week
    runs Sunday through Saturday IST, so everything resets right after
    Saturday 11:59pm IST."""
    now = now or datetime.now(timezone.utc)
    now_ist = now.astimezone(IST)
    days_since_sunday = (now_ist.weekday() + 1) % 7  # Mon=0..Sun=6 -> Sun=0..Sat=6
    sunday_ist = now_ist - timedelta(days=days_since_sunday)
    sunday_ist = sunday_ist.replace(hour=0, minute=0, second=0, microsecond=0)
    return sunday_ist.astimezone(timezone.utc)


def _get_settings(db: Session) -> WeeklyChallengeSettings:
    settings = db.query(WeeklyChallengeSettings).first()
    if not settings:
        settings = WeeklyChallengeSettings()
        db.add(settings)
        db.commit()
        db.refresh(settings)
    return settings


def _challenge_expiry(activated_at: datetime) -> datetime:
    """Saturday 23:59:59.999999 IST of the week the challenge was activated
    in, returned as a UTC instant."""
    week_start = _current_week_start(activated_at)  # UTC instant of Sunday 00:00 IST
    saturday_ist = week_start.astimezone(IST) + timedelta(days=6)
    saturday_ist = saturday_ist.replace(hour=23, minute=59, second=59, microsecond=999999)
    return saturday_ist.astimezone(timezone.utc)


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



def _get_or_create_progress(db: Session, listener_id: int, week_start: datetime, settings: WeeklyChallengeSettings) -> ListenerWeeklyChallengeProgress:
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
            goal1_minutes=settings.goal1_minutes,
            goal2_minutes=settings.goal2_minutes,
            goal3_minutes=settings.goal3_minutes,
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
    progress = _get_or_create_progress(db, listener_id, week_start, settings)

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
    # Prefer the minutes snapshotted on the progress row itself (the goals
    # that were actually live during that week). Older rows created before
    # this snapshot existed fall back to the current settings.
    goal1_minutes = (progress.goal1_minutes if progress and progress.goal1_minutes is not None else settings.goal1_minutes)
    goal2_minutes = (progress.goal2_minutes if progress and progress.goal2_minutes is not None else settings.goal2_minutes)
    goal3_minutes = (progress.goal3_minutes if progress and progress.goal3_minutes is not None else settings.goal3_minutes)
    goal_defs = [
        (goal1_minutes, progress.goal1_completed_at if progress else None),
        (goal2_minutes, progress.goal2_completed_at if progress else None),
        (goal3_minutes, progress.goal3_completed_at if progress else None),
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

    # Re-sync any progress rows already recorded for the current week so the
    # goals/ticks shown to listeners reflect the *new* targets, not whatever
    # was snapshotted when their row was first created. Without this, a
    # listener who already crossed the old (smaller) goals keeps showing all
    # 3 ticks as completed even though they haven't reached the new targets,
    # while the progress bar (which reads live talk_seconds against the new
    # max goal) correctly shows them short of it.
    week_start = _current_week_start()
    current_week_progress = (
        db.query(ListenerWeeklyChallengeProgress)
        .filter(ListenerWeeklyChallengeProgress.week_start == week_start)
        .all()
    )
    resync_now = datetime.now(timezone.utc)
    for progress in current_week_progress:
        progress.goal1_minutes = goal1_minutes
        progress.goal2_minutes = goal2_minutes
        progress.goal3_minutes = goal3_minutes
        for new_minutes, attr in (
            (goal1_minutes, "goal1_completed_at"),
            (goal2_minutes, "goal2_completed_at"),
            (goal3_minutes, "goal3_completed_at"),
        ):
            reached = progress.talk_seconds >= new_minutes * 60
            already_completed = getattr(progress, attr) is not None
            if reached and not already_completed:
                setattr(progress, attr, resync_now)
            elif not reached:
                setattr(progress, attr, None)
    db.commit()

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


@router.get("/admin/history")
def get_history(db: Session = Depends(get_db), _=Depends(get_current_admin)):
    """Admin-facing endpoint: weekly challenge results for every week before
    the current one, grouped by week. The current (still-live) week is
    intentionally excluded since it belongs to the leaderboard/completions
    logs above and only settles once the week rolls over."""
    settings = _get_settings(db)
    week_start_now = _current_week_start()
    rows = (
        db.query(ListenerWeeklyChallengeProgress)
        .filter(ListenerWeeklyChallengeProgress.week_start < week_start_now)
        .filter(ListenerWeeklyChallengeProgress.talk_seconds > 0)
        .order_by(
            ListenerWeeklyChallengeProgress.week_start.desc(),
            ListenerWeeklyChallengeProgress.talk_seconds.desc(),
        )
        .all()
    )

    weeks: dict[datetime, list] = {}
    for progress in rows:
        listener = db.query(Listener).filter(Listener.id == progress.listener_id).first()
        weeks.setdefault(progress.week_start, []).append(
            {
                "listener_id": progress.listener_id,
                "listener_name": listener.name if listener else "Unknown",
                "talk_seconds": progress.talk_seconds,
                "goals": _serialize_goals(settings, progress),
            }
        )

    result = []
    for week_start in sorted(weeks.keys(), reverse=True):
        week_end = week_start + timedelta(days=6)
        listeners = weeks[week_start]
        result.append(
            {
                "week_start": week_start.isoformat(),
                "week_end": week_end.isoformat(),
                "listeners": listeners,
                "top_listener_name": listeners[0]["listener_name"] if listeners else None,
            }
        )
    return result


@router.delete("/admin/challenge")
def delete_challenge(db: Session = Depends(get_db), _=Depends(get_current_admin)):
    """Manually deactivate the current weekly challenge immediately.
    Sets is_active=False so the listener app hides the weekly challenge icon
    at their next /progress poll without waiting for the Saturday expiry."""
    settings = _get_settings(db)
    settings.is_active = False
    db.commit()
    db.refresh(settings)
    return {"detail": "Weekly challenge deactivated successfully.", "active": False}

