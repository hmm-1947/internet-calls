import os
import uuid
from fastapi import APIRouter, Depends, UploadFile, File
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.models.models import AppSettings, Listener, AdminUser
from app.core.ws_manager import manager
from app.utils.fcm import send_ringtone_updated
from app.routers.admin import verify_admin

router = APIRouter(prefix="/app-settings", tags=["app_settings"])


def _get_or_create_settings(db: Session) -> AppSettings:
    settings_row = db.query(AppSettings).first()
    if settings_row is None:
        settings_row = AppSettings(ringtone_url=None, ringtone_version=0, upgrade_banner_url=None)
        db.add(settings_row)
        db.commit()
        db.refresh(settings_row)
    return settings_row


@router.get("/upgrade-banner")
def get_upgrade_banner(db: Session = Depends(get_db)):
    settings_row = _get_or_create_settings(db)
    return {"upgrade_banner_url": settings_row.upgrade_banner_url}


@router.post("/admin/upgrade-banner")
async def admin_set_upgrade_banner(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    ext = os.path.splitext(file.filename)[1] or ".png"
    filename = f"upgrade_banner_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("upgrade_banners", filename)
    with open(filepath, "wb") as f:
        f.write(await file.read())

    settings_row = _get_or_create_settings(db)
    settings_row.upgrade_banner_url = f"/upgrade_banners/{filename}"
    db.commit()
    db.refresh(settings_row)

    return {"upgrade_banner_url": settings_row.upgrade_banner_url}


@router.delete("/admin/upgrade-banner")
def admin_clear_upgrade_banner(db: Session = Depends(get_db), admin: AdminUser = Depends(verify_admin)):
    settings_row = _get_or_create_settings(db)
    settings_row.upgrade_banner_url = None
    db.commit()
    return {"upgrade_banner_url": None}


@router.get("/ringtone")
def get_ringtone(db: Session = Depends(get_db)):
    settings_row = _get_or_create_settings(db)
    return {
        "ringtone_url": settings_row.ringtone_url,
        "ringtone_version": settings_row.ringtone_version,
    }


@router.post("/admin/ringtone")
async def admin_set_ringtone(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    ext = os.path.splitext(file.filename)[1] or ".mp3"
    filename = f"ringtone_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("ringtones", filename)
    with open(filepath, "wb") as f:
        f.write(await file.read())


    settings_row = _get_or_create_settings(db)
    settings_row.ringtone_url = f"/ringtones/{filename}"
    settings_row.ringtone_version += 1
    db.commit()
    db.refresh(settings_row)

    listeners = db.query(Listener).filter(Listener.fcm_token.isnot(None)).all()
    for listener in listeners:
        try:
            send_ringtone_updated(listener.fcm_token, settings_row.ringtone_url, settings_row.ringtone_version)
        except Exception:
            pass

    await manager.broadcast_to_all_listeners({
        "type": "ringtone_updated",
        "ringtone_url": settings_row.ringtone_url,
        "ringtone_version": settings_row.ringtone_version,
    })

    return {
        "ringtone_url": settings_row.ringtone_url,
        "ringtone_version": settings_row.ringtone_version,
    }
