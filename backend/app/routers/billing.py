import hashlib
import hmac
from datetime import datetime, timezone

import razorpay
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.models import BillingPlan, UserBillingPurchase, User
from app.routers.admin import verify_admin
from app.schemas.schemas import (
    AdminPurchaseOut,
    BillingPlanCreate,
    BillingPlanUpdate,
    RazorpayOrderOut,
    RazorpayPaymentFailed,
    RazorpayVerifyPayment,
)

router = APIRouter(tags=["billing"])


def _razorpay_client() -> razorpay.Client:
    if not settings.razorpay_key_id or not settings.razorpay_key_secret:
        raise HTTPException(status_code=500, detail="Razorpay is not configured on the server")
    return razorpay.Client(auth=(settings.razorpay_key_id, settings.razorpay_key_secret))


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


@router.get("/admin/billing/purchases", response_model=list[AdminPurchaseOut])
def admin_list_purchases(db: Session = Depends(get_db), _=Depends(verify_admin)):
    rows = (
        db.query(UserBillingPurchase, User)
        .join(User, User.id == UserBillingPurchase.user_id)
        .order_by(UserBillingPurchase.created_at.desc())
        .all()
    )
    return [
        AdminPurchaseOut(
            id=p.id,
            user_id=u.id,
            user_name=u.name,
            user_phone=u.phone,
            plan_id=p.plan_id,
            plan_name=p.plan_name,
            price_paid=p.price_paid,
            coins_purchased=p.coins_purchased,
            status=p.status,
            razorpay_order_id=p.razorpay_order_id,
            razorpay_payment_id=p.razorpay_payment_id,
            failure_reason=p.failure_reason,
            created_at=p.created_at,
            updated_at=p.updated_at,
        )
        for p, u in rows
    ]


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


@router.post("/billing/purchase/{plan_id}", response_model=RazorpayOrderOut)
def purchase_plan(plan_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Create a Razorpay order for the selected plan. Coins are only credited
    once /billing/verify-payment confirms the payment succeeded."""
    plan = db.query(BillingPlan).filter(BillingPlan.id == plan_id, BillingPlan.is_active == True).first()  # noqa: E712
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")

    client = _razorpay_client()
    amount_paise = plan.price * 100
    try:
        order = client.order.create(
            {
                "amount": amount_paise,
                "currency": "INR",
                "notes": {"plan_id": str(plan.id), "user_id": str(current_user.id)},
            }
        )
    except Exception as e:  # razorpay SDK raises generic errors
        raise HTTPException(status_code=502, detail=f"Failed to create payment order: {e}")

    purchase = UserBillingPurchase(
        user_id=current_user.id,
        plan_id=plan.id,
        plan_name=plan.name,
        price_paid=plan.price,
        coins_purchased=plan.coins,
        status="pending",
        razorpay_order_id=order["id"],
    )
    db.add(purchase)
    db.commit()
    db.refresh(purchase)

    return RazorpayOrderOut(
        purchase_id=purchase.id,
        order_id=order["id"],
        amount=amount_paise,
        currency="INR",
        key_id=settings.razorpay_key_id,
        plan_name=plan.name,
        coins=plan.coins,
        name=current_user.name,
        email=current_user.email,
        contact=current_user.phone,
    )


@router.post("/billing/verify-payment")
def verify_payment(
    payload: RazorpayVerifyPayment,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Verify the Razorpay payment signature and, if valid, credit coins to
    the user and mark the purchase as completed."""
    purchase = (
        db.query(UserBillingPurchase)
        .filter(
            UserBillingPurchase.razorpay_order_id == payload.razorpay_order_id,
            UserBillingPurchase.user_id == current_user.id,
        )
        .first()
    )
    if not purchase:
        raise HTTPException(status_code=404, detail="Purchase not found")

    if purchase.status == "completed":
        # Already processed (e.g. duplicate callback) - respond idempotently.
        user = db.query(User).filter(User.id == current_user.id).first()
        return {
            "id": purchase.id,
            "plan_id": purchase.plan_id,
            "plan_name": purchase.plan_name,
            "price_paid": purchase.price_paid,
            "coins_purchased": purchase.coins_purchased,
            "status": purchase.status,
            "coins_balance": user.coins,
        }

    expected_signature = hmac.new(
        settings.razorpay_key_secret.encode(),
        f"{payload.razorpay_order_id}|{payload.razorpay_payment_id}".encode(),
        hashlib.sha256,
    ).hexdigest()

    if not hmac.compare_digest(expected_signature, payload.razorpay_signature):
        purchase.status = "failed"
        purchase.failure_reason = "Signature verification failed"
        purchase.razorpay_payment_id = payload.razorpay_payment_id
        db.commit()
        raise HTTPException(status_code=400, detail="Payment verification failed")

    purchase.status = "completed"
    purchase.razorpay_payment_id = payload.razorpay_payment_id
    purchase.razorpay_signature = payload.razorpay_signature
    purchase.failure_reason = None

    user = db.query(User).filter(User.id == current_user.id).first()
    user.coins = (user.coins or 0) + purchase.coins_purchased

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


@router.post("/billing/payment-failed")
def payment_failed(
    payload: RazorpayPaymentFailed,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Called by the app when the Razorpay checkout is cancelled or fails,
    so the purchase shows up as Failed in the admin panel instead of hanging
    as Pending forever."""
    purchase = (
        db.query(UserBillingPurchase)
        .filter(
            UserBillingPurchase.razorpay_order_id == payload.razorpay_order_id,
            UserBillingPurchase.user_id == current_user.id,
        )
        .first()
    )
    if not purchase:
        raise HTTPException(status_code=404, detail="Purchase not found")

    if purchase.status == "pending":
        purchase.status = "failed"
        purchase.failure_reason = payload.reason or "Payment cancelled or failed"
        db.commit()

    return {"status": purchase.status}


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
