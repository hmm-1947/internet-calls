import os
import uuid
from datetime import date
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.models.models import SpecialOffer, SignupOfferSettings, CoinTransaction, User, AdminUser
from app.routers.admin import verify_admin

router = APIRouter(prefix="/special-offers", tags=["special_offers"])



def _offer_to_dict(o: SpecialOffer) -> dict:
    return {
        "id": o.id,
        "image_url": o.image_url,
        "sort_order": o.sort_order,
        "is_active": o.is_active,
    }


@router.get("")
def list_special_offers(db: Session = Depends(get_db)):
    offers = (
        db.query(SpecialOffer)
        .filter(SpecialOffer.is_active.is_(True))
        .order_by(SpecialOffer.sort_order.asc(), SpecialOffer.id.asc())
        .all()
    )
    return [_offer_to_dict(o) for o in offers]


@router.get("/admin/list")
def admin_list_special_offers(db: Session = Depends(get_db), _=Depends(verify_admin)):
    offers = db.query(SpecialOffer).order_by(SpecialOffer.sort_order.asc(), SpecialOffer.id.asc()).all()
    return [_offer_to_dict(o) for o in offers]


@router.post("/admin/create")
async def admin_create_special_offer(
    image_file: UploadFile = File(...),
    sort_order: int = Form(0),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    if not image_file.filename:
        raise HTTPException(status_code=400, detail="Image file is required")

    ext = os.path.splitext(image_file.filename)[1] or ".png"
    filename = f"offer_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("special_offers", filename)
    with open(filepath, "wb") as f:
        f.write(await image_file.read())

    offer = SpecialOffer(image_url=f"/special_offers/{filename}", sort_order=sort_order)
    db.add(offer)
    db.commit()
    db.refresh(offer)
    return _offer_to_dict(offer)


# ---------------------------------------------------------------------------
# Signup offer: a single admin-configured date range + coin amount. Any user
# whose account is created while today's date falls inside [from_date,
# to_date] (inclusive) is credited `coin_amount` coins once, at the moment
# the account is created. Users created outside the range - or while no
# range is configured - get nothing.
#
# NOTE: these routes are declared here, before /admin/{offer_id}, because
# FastAPI matches routes in registration order. If /admin/{offer_id} came
# first, a request to /admin/signup-offer would match it instead (trying to
# parse "signup-offer" as an int) and fail with a 422.
# ---------------------------------------------------------------------------

def _get_signup_offer_settings(db: Session) -> SignupOfferSettings:
    settings = db.query(SignupOfferSettings).first()
    if not settings:
        settings = SignupOfferSettings()
        db.add(settings)
        db.commit()
        db.refresh(settings)
    return settings


def _signup_offer_to_dict(settings: SignupOfferSettings) -> dict:
    return {
        "from_date": settings.from_date.isoformat() if settings.from_date else None,
        "to_date": settings.to_date.isoformat() if settings.to_date else None,
        "coin_amount": settings.coin_amount,
    }


@router.get("/admin/signup-offer")
def admin_get_signup_offer(db: Session = Depends(get_db), admin: AdminUser = Depends(verify_admin)):
    return _signup_offer_to_dict(_get_signup_offer_settings(db))


@router.put("/admin/signup-offer")
def admin_update_signup_offer(
    from_date: date,
    to_date: date,
    coin_amount: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    if coin_amount < 0:
        raise HTTPException(status_code=400, detail="Coin amount cannot be negative")
    if to_date < from_date:
        raise HTTPException(status_code=400, detail="'To' date cannot be before 'From' date")

    settings = _get_signup_offer_settings(db)
    settings.from_date = from_date
    settings.to_date = to_date
    settings.coin_amount = coin_amount
    db.commit()
    db.refresh(settings)
    return _signup_offer_to_dict(settings)


def credit_signup_offer_if_eligible(db: Session, user: User) -> None:
    """Call this right after a new `User` row is created (and flushed, so it
    has an id) but before the surrounding transaction commits. Credits the
    configured signup-offer coins if today's date falls inside the admin's
    configured date range. Silently does nothing if no range is configured,
    the amount is 0, or today is outside the range.
    """
    settings = db.query(SignupOfferSettings).first()
    if not settings or not settings.from_date or not settings.to_date:
        return
    if settings.coin_amount <= 0:
        return
    today = date.today()
    if not (settings.from_date <= today <= settings.to_date):
        return
    user.coins = (user.coins or 0) + settings.coin_amount
    db.add(CoinTransaction(user_id=user.id, amount=settings.coin_amount, reason="signup_offer"))


@router.put("/admin/{offer_id}")
async def admin_update_special_offer(
    offer_id: int,
    sort_order: int = Form(None),
    is_active: bool = Form(None),
    image_file: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    offer = db.query(SpecialOffer).filter(SpecialOffer.id == offer_id).first()
    if not offer:
        raise HTTPException(status_code=404, detail="Special offer not found")

    if sort_order is not None:
        offer.sort_order = sort_order
    if is_active is not None:
        offer.is_active = is_active

    if image_file is not None and image_file.filename:
        ext = os.path.splitext(image_file.filename)[1] or ".png"
        filename = f"offer_{uuid.uuid4().hex}{ext}"
        filepath = os.path.join("special_offers", filename)
        with open(filepath, "wb") as f:
            f.write(await image_file.read())
        offer.image_url = f"/special_offers/{filename}"

    db.commit()
    db.refresh(offer)
    return _offer_to_dict(offer)


@router.delete("/admin/{offer_id}")
def admin_delete_special_offer(offer_id: int, db: Session = Depends(get_db), admin: AdminUser = Depends(verify_admin)):
    offer = db.query(SpecialOffer).filter(SpecialOffer.id == offer_id).first()
    if not offer:
        raise HTTPException(status_code=404, detail="Special offer not found")
    db.delete(offer)
    db.commit()
    return {"detail": "Special offer deleted"}

