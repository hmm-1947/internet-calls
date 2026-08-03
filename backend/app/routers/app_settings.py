import os
import re
import uuid
from fastapi import APIRouter, Depends, UploadFile, File
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.models.models import AppSettings, AdminUser
from app.routers.admin import verify_admin

router = APIRouter(prefix="/app-settings", tags=["app_settings"])


def _get_or_create_settings(db: Session) -> AppSettings:
    settings_row = db.query(AppSettings).first()
    if settings_row is None:
        settings_row = AppSettings(upgrade_banner_url=None)
        db.add(settings_row)
        db.commit()
        db.refresh(settings_row)
    return settings_row


@router.get("/upgrade-banner")
def get_upgrade_banner(db: Session = Depends(get_db)):
    settings_row = _get_or_create_settings(db)
    return {"upgrade_banner_url": settings_row.upgrade_banner_url}


@router.get("/enroll-contact")
def get_enroll_contact(db: Session = Depends(get_db)):
    """WhatsApp number the user app opens for "Enroll as a listener" requests.

    The number is the phone saved on the admin profile (admin panel -> Edit Profile).
    When several admins have one, the lowest id wins so the destination stays stable
    as more admins are added. Returns null when no admin has saved a phone yet.
    """
    admin = (
        db.query(AdminUser)
        .filter(AdminUser.phone.isnot(None), func.trim(AdminUser.phone) != "")
        .order_by(AdminUser.id)
        .first()
    )
    # wa.me only accepts digits in international format, so drop "+", spaces and dashes.
    number = re.sub(r"\D", "", admin.phone) if admin else ""
    return {"whatsapp_number": number or None}


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


@router.get("/terms-privacy")
def get_terms_privacy(db: Session = Depends(get_db)):
    """Public endpoint used by both apps to display the admin-authored
    Terms of Service and Privacy Policy. Content is stored as sanitized-ish
    HTML produced by the admin panel's rich text editor."""
    settings_row = _get_or_create_settings(db)
    return {
        "terms_of_service": settings_row.terms_of_service or "",
        "privacy_policy": settings_row.privacy_policy or "",
    }


class TermsPrivacyPayload(BaseModel):
    terms_of_service: str | None = None
    privacy_policy: str | None = None


@router.put("/admin/terms-privacy")
def admin_set_terms_privacy(
    payload: TermsPrivacyPayload,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    settings_row = _get_or_create_settings(db)
    if payload.terms_of_service is not None:
        settings_row.terms_of_service = payload.terms_of_service
    if payload.privacy_policy is not None:
        settings_row.privacy_policy = payload.privacy_policy
    db.commit()
    db.refresh(settings_row)
    return {
        "terms_of_service": settings_row.terms_of_service or "",
        "privacy_policy": settings_row.privacy_policy or "",
    }



