import hashlib
import hmac
from datetime import datetime, timezone
from typing import Optional

import razorpay
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.deps import get_current_user
from app.utils.rate_limit import client_ip, enforce_rate_limit
from app.models.models import AdminUser, BillingPlan, BillingPlanAuditLog, UserBillingPurchase, User
from app.routers.admin import verify_admin
from app.routers.notifications import create_admin_notification
from app.core.ws_manager import manager
from app.schemas.schemas import (
    AdminPurchaseOut,
    BillingPlanAuditLogOut,
    BillingPlanCreate,
    BillingPlanUpdate,
    RazorpayOrderOut,
    RazorpayPaymentFailed,
    RazorpayVerifyPayment,
)

router = APIRouter(tags=["billing"])


def _is_web_request(request: Request) -> bool:
    return (request.headers.get("X-Client") or "").strip().lower() == "web"


def _razorpay_credentials(request: Request) -> tuple[str, str]:
    if _is_web_request(request):
        key_id, key_secret = settings.web_razorpay_key_id, settings.web_razorpay_key_secret
        if not key_id or not key_secret:
            raise HTTPException(status_code=500, detail="Razorpay is not configured for the web app")
        return key_id, key_secret
    if not settings.razorpay_key_id or not settings.razorpay_key_secret:
        raise HTTPException(status_code=500, detail="Razorpay is not configured on the server")
    return settings.razorpay_key_id, settings.razorpay_key_secret


def _razorpay_client(request: Request) -> razorpay.Client:
    key_id, key_secret = _razorpay_credentials(request)
    return razorpay.Client(auth=(key_id, key_secret))


def _log_plan_action(db: Session, admin: AdminUser, action: str, plan_id: Optional[int], plan_name: str, details: str) -> None:
    db.add(
        BillingPlanAuditLog(
            action=action,
            plan_id=plan_id,
            plan_name=plan_name,
            admin_id=admin.id,
            admin_username=admin.username,
            details=details,
        )
    )


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
def admin_create_plan(payload: BillingPlanCreate, db: Session = Depends(get_db), admin: AdminUser = Depends(verify_admin)):
    plan = BillingPlan(
        name=payload.name,
        price=payload.price,
        coins=payload.coins,
        icon=payload.icon,
        is_featured=payload.is_featured,
        is_active=payload.is_active,
    )
    db.add(plan)
    db.flush()  # assign plan.id before logging

    _log_plan_action(
        db,
        admin,
        action="created",
        plan_id=plan.id,
        plan_name=plan.name,
        details=f"Price ₹{plan.price}, {plan.coins} coins, icon={plan.icon}, "
        f"featured={plan.is_featured}, visible={plan.is_active}",
    )

    db.commit()
    db.refresh(plan)
    return _plan_to_dict(plan)


@router.put("/admin/billing/plans/{plan_id}")
def admin_update_plan(plan_id: int, payload: BillingPlanUpdate, db: Session = Depends(get_db), admin: AdminUser = Depends(verify_admin)):
    plan = db.query(BillingPlan).filter(BillingPlan.id == plan_id).first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")

    changes = []
    for field, new_value in (
        ("name", payload.name),
        ("price", payload.price),
        ("coins", payload.coins),
        ("icon", payload.icon),
        ("is_featured", payload.is_featured),
        ("is_active", payload.is_active),
    ):
        old_value = getattr(plan, field)
        if old_value != new_value:
            changes.append(f"{field}: {old_value} → {new_value}")

    plan.name = payload.name
    plan.price = payload.price
    plan.coins = payload.coins
    plan.icon = payload.icon
    plan.is_featured = payload.is_featured
    plan.is_active = payload.is_active

    _log_plan_action(
        db,
        admin,
        action="updated",
        plan_id=plan.id,
        plan_name=plan.name,
        details="; ".join(changes) if changes else "No field changes",
    )

    db.commit()
    db.refresh(plan)
    return _plan_to_dict(plan)


@router.delete("/admin/billing/plans/{plan_id}")
def admin_delete_plan(plan_id: int, db: Session = Depends(get_db), admin: AdminUser = Depends(verify_admin)):
    plan = db.query(BillingPlan).filter(BillingPlan.id == plan_id).first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")

    _log_plan_action(
        db,
        admin,
        action="deleted",
        plan_id=plan.id,
        plan_name=plan.name,
        details=f"Was: price ₹{plan.price}, {plan.coins} coins, icon={plan.icon}, "
        f"featured={plan.is_featured}, visible={plan.is_active}",
    )

    db.delete(plan)
    db.commit()
    return {"detail": "Plan deleted"}


@router.get("/admin/billing/plans/audit-log", response_model=list[BillingPlanAuditLogOut])
def admin_billing_plan_audit_log(db: Session = Depends(get_db), _=Depends(verify_admin)):
    """Returns coin pack add/update/delete history, most recent first."""
    return (
        db.query(BillingPlanAuditLog)
        .order_by(BillingPlanAuditLog.created_at.desc())
        .limit(200)
        .all()
    )


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
            razorpay_refund_id=p.razorpay_refund_id,
            refunded_amount_paise=p.refunded_amount_paise or 0,
            refunded_at=p.refunded_at,
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
def purchase_plan(plan_id: int, request: Request, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
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
        key_id=key_id,
        plan_name=plan.name,
        coins=plan.coins,
        name=current_user.name,
        email=current_user.email,
        contact=current_user.phone,
    )


@router.post("/billing/verify-payment")
async def verify_payment(
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
        .with_for_update()
        .first()
    )
    if not purchase:
        raise HTTPException(status_code=404, detail="Purchase not found")

    if purchase.status == "completed":
        # Already processed (e.g. duplicate callback, or the webhook already
        # landed first) - respond idempotently.
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
        _razorpay_credentials(request)[1].encode(),
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

    user = db.query(User).filter(User.id == current_user.id).with_for_update().first()
    user.coins = (user.coins or 0) + purchase.coins_purchased

    db.commit()
    db.refresh(purchase)

    await manager.send_to_user(user.id, {"type": "coins_updated", "coins": user.coins})

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


REFUND_NOTIFICATION_TYPE = "payment_refunded"


async def _record_refund(db: Session, refund_entity: dict, fallback_order_id: Optional[str]) -> None:
    """Marks a purchase as (partially) refunded and asks an admin to reconcile.

    Deliberately does NOT touch `user.coins`. By the time a refund lands the
    coins have usually been spent on calls and gifts, so deducting them would
    push the balance negative. An admin decides what to do and applies it
    through Coins -> Adjust.
    """
    refund_id = refund_entity.get("id")
    payment_id = refund_entity.get("payment_id")
    amount_paise = int(refund_entity.get("amount") or 0)

    q = db.query(UserBillingPurchase)
    if payment_id:
        purchase = q.filter(UserBillingPurchase.razorpay_payment_id == payment_id).with_for_update().first()
    elif fallback_order_id:
        purchase = q.filter(UserBillingPurchase.razorpay_order_id == fallback_order_id).with_for_update().first()
    else:
        purchase = None

    if not purchase:
        # A refund for a payment we have no record of (e.g. a test payment, or
        # an order whose row was never created). Still worth an admin's eyes.
        await create_admin_notification(
            db,
            type=REFUND_NOTIFICATION_TYPE,
            title="Refund for an unknown payment",
            body=(
                f"Razorpay refund {refund_id} of ₹{amount_paise / 100:.2f} was processed for "
                f"payment {payment_id or '—'}, which does not match any purchase in the database. "
                "Check the Razorpay dashboard."
            ),
        )
        return

    # Guards against Razorpay re-delivering the same refund event. Distinct
    # partial refunds each carry their own id and are summed correctly; only a
    # redelivery of an *older* partial refund after a newer one could double
    # count, which the cap below keeps harmless.
    if refund_id and purchase.razorpay_refund_id == refund_id:
        return

    order_total_paise = purchase.price_paid * 100
    already_refunded = purchase.refunded_amount_paise or 0
    purchase.refunded_amount_paise = min(already_refunded + amount_paise, order_total_paise)
    purchase.razorpay_refund_id = refund_id
    purchase.refunded_at = datetime.now(timezone.utc)
    purchase.status = "refunded" if purchase.refunded_amount_paise >= order_total_paise else "partially_refunded"
    db.commit()

    user = db.query(User).filter(User.id == purchase.user_id).first()
    await create_admin_notification(
        db,
        type=REFUND_NOTIFICATION_TYPE,
        title=f"Refund processed: ₹{amount_paise / 100:.2f}",
        body=(
            f"Purchase #{purchase.id} ({purchase.plan_name}, {purchase.coins_purchased} coins, "
            f"₹{purchase.price_paid}) was refunded via Razorpay refund {refund_id}. "
            f"Total refunded so far: ₹{purchase.refunded_amount_paise / 100:.2f}. "
            f"The user still holds the coins ({user.coins if user else '—'} in wallet) - "
            "deduct them manually under Coins if that is appropriate."
        ),
        subject_type="user",
        subject_id=purchase.user_id,
        subject_name=user.name if user else None,
    )


@router.post("/billing/webhook/razorpay")
async def razorpay_webhook(request: Request, db: Session = Depends(get_db)):
    """Server-to-server notification from Razorpay. This is the source of
    truth for marking a purchase completed - unlike /billing/verify-payment,
    it does not depend on the client staying online after payment.

    Not behind get_current_user: Razorpay calls this directly, with no user
    JWT, only its own HMAC signature over the raw body.
    """
    # Signature verification below already rejects forged payloads. This is
    # only a backstop against a flood of junk requests, NOT a per-user limit:
    # Razorpay's webhook calls all come from its own small set of server IPs,
    # so every real customer's payment webhook shares this same bucket. The
    # limit must stay well above realistic concurrent-payment volume or it
    # will start rejecting genuine webhooks during busy periods.
    enforce_rate_limit("razorpay_webhook", client_ip(request), limit=600, window_seconds=60)

    raw_body = await request.body()
    signature = request.headers.get("X-Razorpay-Signature", "")

    secrets = [s for s in (settings.razorpay_webhook_secret, settings.web_razorpay_webhook_secret) if s]
    if not secrets:
        raise HTTPException(status_code=500, detail="Razorpay webhook secret is not configured on the server")

    valid = any(
        hmac.compare_digest(
            hmac.new(s.encode(), raw_body, hashlib.sha256).hexdigest(),
            signature,
        )
        for s in secrets
    )
    if not valid:
        raise HTTPException(status_code=400, detail="Invalid webhook signature")

    payload = await request.json()
    event = payload.get("event", "")
    payment_entity = payload.get("payload", {}).get("payment", {}).get("entity", {})
    order_id = payment_entity.get("order_id")
    payment_id = payment_entity.get("id")

    if event in ("payment.captured", "order.paid") and order_id:
        purchase = (
            db.query(UserBillingPurchase)
            .filter(UserBillingPurchase.razorpay_order_id == order_id)
            .with_for_update()
            .first()
        )
        if purchase and purchase.status != "completed":
            purchase.status = "completed"
            purchase.razorpay_payment_id = payment_id
            purchase.failure_reason = None

            user = db.query(User).filter(User.id == purchase.user_id).with_for_update().first()
            if user:
                user.coins = (user.coins or 0) + purchase.coins_purchased
                db.commit()
                await manager.send_to_user(user.id, {"type": "coins_updated", "coins": user.coins})
            else:
                db.commit()
        # Already completed (e.g. duplicate webhook delivery, or the client's
        # own /verify-payment call already landed first) - nothing to do.

    elif event == "payment.failed" and order_id:
        purchase = (
            db.query(UserBillingPurchase)
            .filter(UserBillingPurchase.razorpay_order_id == order_id)
            .with_for_update()
            .first()
        )
        if purchase and purchase.status == "pending":
            purchase.status = "failed"
            purchase.failure_reason = payment_entity.get("error_description") or "Payment failed"
            db.commit()

    elif event == "refund.processed":
        # Refund events carry their own entity; the refund itself has no
        # order_id, so the lookup goes through payment_id. `refund.created` is
        # deliberately ignored - only a processed refund means money left.
        refund_entity = payload.get("payload", {}).get("refund", {}).get("entity", {})
        if refund_entity:
            await _record_refund(db, refund_entity, order_id)

    # Razorpay only needs a 2xx to stop retrying; unhandled event types are
    # acknowledged and ignored.
    return {"status": "ok"}


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
