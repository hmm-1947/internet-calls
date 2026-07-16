from sqlalchemy.orm import Session

from app.models.models import AuditLog


def record_audit_event(db: Session, subject_type: str, subject_id: int, subject_name: str, action: str) -> None:
    """Records a login/logout event for a user or listener.

    Only ever call this for events that actually happened (i.e. after
    credential checks have already passed) - failed login attempts must
    never be recorded here.
    """
    db.add(
        AuditLog(
            subject_type=subject_type,
            subject_id=subject_id,
            subject_name=subject_name,
            action=action,
        )
    )
