import os
import uuid
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.models.models import SpecialOffer, AdminUser
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
