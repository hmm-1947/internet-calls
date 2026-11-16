import os
import re
import uuid
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel, field_validator
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


@router.get("/version-check")
def get_version_check(db: Session = Depends(get_db)):
    """Public endpoint both apps can call on launch to check for a required
    update. The latest version IS the minimum required version: any
    installed build below it is considered outdated.

    The user app is distributed through the stores, so it gets a store_url
    to redirect to. The listener app is sideloaded (not on any store), so
    it only gets a required version number.
    """
    settings_row = _get_or_create_settings(db)
    return {
        "user": {
            "android": {
                "latest_version": settings_row.latest_app_version_android,
                "store_url": settings_row.android_store_url,
            },
            "ios": {
                "latest_version": settings_row.latest_app_version_ios,
                "store_url": settings_row.ios_store_url,
            },
        },
        "listener": {
            "latest_version": settings_row.latest_app_version_listener,
        },
    }


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


class VersionCheckPayload(BaseModel):
    latest_app_version_android: str | None = None
    android_store_url: str | None = None
    latest_app_version_ios: str | None = None
    ios_store_url: str | None = None
    latest_app_version_listener: str | None = None

    @field_validator("latest_app_version_android", "latest_app_version_ios", "latest_app_version_listener")
    @classmethod
    def _build_number_only(cls, value):
        if value is None:
            return None
        value = value.strip()
        if not value:
            return None
        if not value.isdigit():
            raise ValueError("Enter the build number as a whole number, e.g. 7")
        return str(int(value))


@router.put("/admin/version-check")
def admin_set_version_check(
    payload: VersionCheckPayload,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    settings_row = _get_or_create_settings(db)
    updates = payload.model_dump(exclude_unset=True)

    resulting_android_version = updates.get("latest_app_version_android", settings_row.latest_app_version_android)
    resulting_android_url = updates.get("android_store_url", settings_row.android_store_url)
    if resulting_android_version and not resulting_android_url:
        raise HTTPException(status_code=400, detail="Set the Play Store URL before saving an Android version")

    resulting_ios_version = updates.get("latest_app_version_ios", settings_row.latest_app_version_ios)
    resulting_ios_url = updates.get("ios_store_url", settings_row.ios_store_url)
    if resulting_ios_version and not resulting_ios_url:
        raise HTTPException(status_code=400, detail="Set the App Store URL before saving an iOS version")

    for field, value in updates.items():
        setattr(settings_row, field, value)
    db.commit()
    db.refresh(settings_row)
    return {
        "user": {
            "android": {
                "latest_version": settings_row.latest_app_version_android,
                "store_url": settings_row.android_store_url,
            },
            "ios": {
                "latest_version": settings_row.latest_app_version_ios,
                "store_url": settings_row.ios_store_url,
            },
        },
        "listener": {
            "latest_version": settings_row.latest_app_version_listener,
        },
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



