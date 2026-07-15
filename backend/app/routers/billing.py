from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.models import BillingPlan, UserBillingPurchase, User
from app.routers.admin import verify_admin
from app.schemas.schemas import BillingPlanCreate, BillingPlanUpdate

router = APIRouter(tags=["billing"])


def _plan_to_dict(p: BillingPlan) -> dict:
    return {
        "id": p.id,
        "name": p.name,
        "price": p.price,
        "coins": p.coins,
        "icon": p.icon,
        "is_featured": p.is_featured,
        "is_active": p.is_active,
        "created_at": p.created_at,
        "updated_at": p.updated_at,
    }


# ---------------- Admin endpoints ----------------

@router.get("/admin/billing/plans")
def admin_list_plans(db: Session = Depends(get_db), _=Depends(verify_admin)):
    plans = db.query(BillingPlan).order_by(BillingPlan.price.asc(), BillingPlan.id.asc()).all()
    return [_plan_to_dict(p) for p in plans]


@router.post("/admin/billing/plans")
def admin_create_plan(payload: BillingPlanCreate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    plan = BillingPlan(
        name=payload.name,
        price=payload.price,
        coins=payload.coins,
        icon=payload.icon,
        is_featured=payload.is_featured,
        is_active=payload.is_active,
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return _plan_to_dict(plan)


@router.put("/admin/billing/plans/{plan_id}")
def admin_update_plan(plan_id: int, payload: BillingPlanUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    plan = db.query(BillingPlan).filter(BillingPlan.id == plan_id).first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")
    plan.name = payload.name
    plan.price = payload.price
    plan.coins = payload.coins
    plan.icon = payload.icon
    plan.is_featured = payload.is_featured
    plan.is_active = payload.is_active
    db.commit()
    db.refresh(plan)
    return _plan_to_dict(plan)


@router.delete("/admin/billing/plans/{plan_id}")
def admin_delete_plan(plan_id: int, db: Session = Depends(get_db), _=Depends(verify_admin)):
    plan = db.query(BillingPlan).filter(BillingPlan.id == plan_id).first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")
    db.delete(plan)
    db.commit()
    return {"detail": "Plan deleted"}


# ---------------- User-facing endpoints ----------------

@router.get("/billing/plans")
def user_list_plans(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    plans = (
        db.query(BillingPlan)
        .filter(BillingPlan.is_active == True)  # noqa: E712
        .order_by(BillingPlan.price.asc())
        .all()
    )
    return [_plan_to_dict(p) for p in plans]


@router.post("/billing/purchase/{plan_id}")
def purchase_plan(plan_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    plan = db.query(BillingPlan).filter(BillingPlan.id == plan_id, BillingPlan.is_active == True).first()  # noqa: E712
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")

    user = db.query(User).filter(User.id == current_user.id).first()
    user.coins = (user.coins or 0) + plan.coins

    purchase = UserBillingPurchase(
        user_id=current_user.id,
        plan_id=plan.id,
        plan_name=plan.name,
        price_paid=plan.price,
        coins_purchased=plan.coins,
        status="completed",
    )
    db.add(purchase)
    db.commit()
    db.refresh(purchase)
    return {
        "id": purchase.id,
        "plan_id": purchase.plan_id,
        "plan_name": purchase.plan_name,
        "price_paid": purchase.price_paid,
        "coins_purchased": purchase.coins_purchased,
        "status": purchase.status,
        "coins_balance": user.coins,
    }


@router.get("/billing/my-purchases")
def my_purchases(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    purchases = (
        db.query(UserBillingPurchase)
        .filter(UserBillingPurchase.user_id == current_user.id)
        .order_by(UserBillingPurchase.created_at.desc())
        .all()
    )
    return [
        {
            "id": p.id,
            "plan_id": p.plan_id,
            "plan_name": p.plan_name,
            "price_paid": p.price_paid,
            "coins_purchased": p.coins_purchased,
            "status": p.status,
            "created_at": p.created_at,
        }
        for p in purchases
    ]
