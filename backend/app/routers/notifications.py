"""Admin notification feed.

Events raised by the apps (currently account deletion requests) land in
`admin_notifications` and are shown on the Notifications page of the panel.
An admin clears an entry with "mark as done", which only flips `is_done` so
the audit trail of who handled what survives.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.ws_manager import manager
from app.models.models import AdminNotification, AdminUser
from app.routers.admin import verify_admin
from app.schemas.schemas import AdminNotificationOut

router = APIRouter(prefix="/admin/notifications", tags=["admin-notifications"])


async def create_admin_notification(
    db: Session,
    *,
    type: str,
    title: str,
    body: str | None = None,
    subject_type: str | None = None,
    subject_id: int | None = None,
    subject_name: str | None = None,
    related_id: int | None = None,
) -> AdminNotification:
    """Stores a notification and pushes it to every connected admin panel.

    The caller is responsible for nothing else: the row is committed here so
    a failed websocket broadcast can never lose the notification.
    """
    notification = AdminNotification(
        type=type,
        title=title,
        body=body,
        subject_type=subject_type,
        subject_id=subject_id,
        subject_name=subject_name,
        related_id=related_id,
    )
    db.add(notification)
    db.commit()
    db.refresh(notification)

    payload = AdminNotificationOut.model_validate(notification).model_dump(mode="json")
    try:
        await manager.broadcast_to_admins({"type": "admin_notification", "notification": payload})
    except Exception:
        # The panel also polls on page open, so a dead socket is not fatal.
        pass
    return notification


@router.get("", response_model=list[AdminNotificationOut])
def list_notifications(
    include_done: bool = Query(False, description="Also return notifications already marked as done"),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    _admin: AdminUser = Depends(verify_admin),
):
    q = db.query(AdminNotification)
    if not include_done:
        q = q.filter(AdminNotification.is_done.is_(False))
    rows = q.order_by(AdminNotification.created_at.desc(), AdminNotification.id.desc()).offset(skip).limit(limit).all()
    return [AdminNotificationOut.model_validate(r) for r in rows]


@router.get("/unread-count")
def unread_notification_count(
    db: Session = Depends(get_db),
    _admin: AdminUser = Depends(verify_admin),
):
    count = (
        db.query(AdminNotification)
        .filter(AdminNotification.is_done.is_(False), AdminNotification.is_read.is_(False))
        .count()
    )
    return {"count": count}


@router.post("/mark-seen")
def mark_notifications_seen(
    db: Session = Depends(get_db),
    _admin: AdminUser = Depends(verify_admin),
):
    """Clears the red counter. Entries stay in the list until marked done."""
    db.query(AdminNotification).filter(AdminNotification.is_read.is_(False)).update(
        {AdminNotification.is_read: True}, synchronize_session=False
    )
    db.commit()
    return {"status": "ok"}


@router.post("/{notification_id}/done", response_model=AdminNotificationOut)
def mark_notification_done(
    notification_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    notification = db.query(AdminNotification).filter(AdminNotification.id == notification_id).first()
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")
    if notification.is_done:
        return AdminNotificationOut.model_validate(notification)

    notification.is_done = True
    notification.is_read = True
    notification.done_at = datetime.now(timezone.utc)
    notification.done_by_admin_id = admin.id
    notification.done_by_admin_username = admin.username
    db.commit()
    db.refresh(notification)
    return AdminNotificationOut.model_validate(notification)
