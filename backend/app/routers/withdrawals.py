from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_listener
from app.core.ws_manager import manager
from app.models.models import Listener, ListenerCoinTransaction, WithdrawalRequest, AdminUser
from app.routers.notifications import create_admin_notification
from app.schemas.schemas import WithdrawalRequestCreate, WithdrawalRequestOut, WithdrawalDecision
from app.utils.fcm import send_withdrawal_decision, send_async

listener_router = APIRouter(prefix="/listener/withdrawals", tags=["listener-withdrawals"])
admin_router = APIRouter(prefix="/admin/withdrawals", tags=["admin-withdrawals"])


# ---------------------------------------------------------------------------
# Listener side
# ---------------------------------------------------------------------------

@listener_router.post("", response_model=WithdrawalRequestOut)
async def create_withdrawal_request(
    payload: WithdrawalRequestCreate,
    db: Session = Depends(get_db),
    listener: Listener = Depends(get_current_listener),
):
    if payload.coins < 0:
        raise HTTPException(status_code=400, detail="Coins cannot be negative")

    # Lock the row so a concurrent second request can't slip in between the
    # pending-request check below and the insert.
    locked_listener = db.query(Listener).filter(Listener.id == listener.id).with_for_update().first()
    if not locked_listener:
        raise HTTPException(status_code=404, detail="Listener not found")

    has_pending = (
        db.query(WithdrawalRequest)
        .filter(WithdrawalRequest.listener_id == listener.id, WithdrawalRequest.status == "pending")
        .first()
    )
    if has_pending:
        raise HTTPException(
            status_code=400,
            detail="You already have a withdrawal request pending admin review",
        )

    request = WithdrawalRequest(
        listener_id=listener.id,
        coins=payload.coins,
        status="pending",
    )
    db.add(request)
    db.commit()
    db.refresh(request)

    await create_admin_notification(
        db,
        type="withdrawal_request",
        title="Withdrawal request",
        body=f"{listener.name} requested to withdraw {payload.coins} coins.",
        subject_type="listener",
        subject_id=listener.id,
        subject_name=listener.name,
        related_id=request.id,
    )

    out = WithdrawalRequestOut.model_validate(request)
    out.listener_name = listener.name
    return out


@listener_router.get("", response_model=list[WithdrawalRequestOut])
def list_my_withdrawal_requests(
    skip: int = Query(0, ge=0),
    limit: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
    listener: Listener = Depends(get_current_listener),
):
    rows = (
        db.query(WithdrawalRequest)
        .filter(WithdrawalRequest.listener_id == listener.id)
        .order_by(WithdrawalRequest.created_at.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )
    return [WithdrawalRequestOut.model_validate(r) for r in rows]


# ---------------------------------------------------------------------------
# Admin side
# ---------------------------------------------------------------------------

from app.routers.admin import verify_admin  # reuse existing admin session/token auth


@admin_router.get("", response_model=list[WithdrawalRequestOut])
def list_withdrawal_requests(
    status: str | None = Query(None, description="pending | approved | rejected"),
    skip: int = Query(0, ge=0),
    limit: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
    _admin: AdminUser = Depends(verify_admin),
):
    q = db.query(WithdrawalRequest, Listener.name).join(Listener, Listener.id == WithdrawalRequest.listener_id)
    if status:
        q = q.filter(WithdrawalRequest.status == status)
    rows = q.order_by(WithdrawalRequest.created_at.desc()).offset(skip).limit(limit).all()

    result = []
    for req, listener_name in rows:
        out = WithdrawalRequestOut.model_validate(req)
        out.listener_name = listener_name
        result.append(out)
    return result


@admin_router.get("/{request_id}/details")
def get_withdrawal_request_details(
    request_id: int,
    db: Session = Depends(get_db),
    _admin: AdminUser = Depends(verify_admin),
):
    """Listener name + current-week day/night activity, for the admin panel's
    accept/reject popup opened from a withdrawal_request notification."""
    request = db.query(WithdrawalRequest).filter(WithdrawalRequest.id == request_id).first()
    if not request:
        raise HTTPException(status_code=404, detail="Withdrawal request not found")
    listener = db.query(Listener).filter(Listener.id == request.listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")

    from app.utils.wallet_stats import day_night_breakdown, week_bounds
    start, end = week_bounds(weeks_ago=0)
    current_week = day_night_breakdown(db, listener.id, start, end)

    from app.routers.weekly_challenge import (
        _get_settings as _wc_get_settings,
        _current_week_start as _wc_current_week_start,
        _serialize_goals as _wc_serialize_goals,
    )
    from app.models.models import ListenerWeeklyChallengeProgress

    wc_settings = _wc_get_settings(db)
    wc_week_start = _wc_current_week_start()
    wc_progress = (
        db.query(ListenerWeeklyChallengeProgress)
        .filter(
            ListenerWeeklyChallengeProgress.listener_id == listener.id,
            ListenerWeeklyChallengeProgress.week_start == wc_week_start,
        )
        .first()
    )
    weekly_challenge = {
        "week_start": wc_week_start.isoformat(),
        "talk_seconds": wc_progress.talk_seconds if wc_progress else 0,
        "goals": _wc_serialize_goals(wc_settings, wc_progress),
    }

    out = WithdrawalRequestOut.model_validate(request)
    out.listener_name = listener.name
    return {
        "request": out,
        "listener_id": listener.id,
        "listener_name": listener.name,
        "current_week": current_week,
        "weekly_challenge": weekly_challenge,
    }


@admin_router.get("/count")
def count_withdrawal_requests(
    status: str | None = Query(None),
    db: Session = Depends(get_db),
    _admin: AdminUser = Depends(verify_admin),
):
    q = db.query(WithdrawalRequest)
    if status:
        q = q.filter(WithdrawalRequest.status == status)
    return {"count": q.count()}


@admin_router.post("/{request_id}/approve", response_model=WithdrawalRequestOut)
async def approve_withdrawal_request(
    request_id: int,
    payload: WithdrawalDecision = WithdrawalDecision(),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    request = db.query(WithdrawalRequest).filter(WithdrawalRequest.id == request_id).with_for_update().first()
    if not request:
        raise HTTPException(status_code=404, detail="Withdrawal request not found")
    if request.status != "pending":
        raise HTTPException(status_code=400, detail=f"Request already {request.status}")

    listener = db.query(Listener).filter(Listener.id == request.listener_id).with_for_update().first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    if listener.coins < request.coins:
        # Balance may have shifted since the request was made (e.g. spent
        # elsewhere) — don't allow the deduction to go negative.
        raise HTTPException(status_code=400, detail="Listener no longer has enough coins for this withdrawal")

    listener.coins -= request.coins
    db.add(ListenerCoinTransaction(
        listener_id=listener.id,
        amount=-request.coins,
        reason="withdrawal_approved",
        call_id=None,
    ))
    request.status = "approved"
    request.admin_id = admin.id
    request.admin_username = admin.username
    request.decided_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(request)

    await manager.send_to_listener(listener.id, {
        "type": "withdrawal_decision",
        "request_id": request.id,
        "status": "approved",
        "coins": request.coins,
        "wallet_coins": listener.coins,
    })
    if listener.fcm_token:
        send_async(send_withdrawal_decision, listener.fcm_token, request.id, "approved", request.coins)

    out = WithdrawalRequestOut.model_validate(request)
    out.listener_name = listener.name
    return out


@admin_router.post("/{request_id}/reject", response_model=WithdrawalRequestOut)
async def reject_withdrawal_request(
    request_id: int,
    payload: WithdrawalDecision = WithdrawalDecision(),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    request = db.query(WithdrawalRequest).filter(WithdrawalRequest.id == request_id).with_for_update().first()
    if not request:
        raise HTTPException(status_code=404, detail="Withdrawal request not found")
    if request.status != "pending":
        raise HTTPException(status_code=400, detail=f"Request already {request.status}")

    listener = db.query(Listener).filter(Listener.id == request.listener_id).first()

    # No coin deduction on rejection — coins were never touched at request time.
    request.status = "rejected"
    request.admin_id = admin.id
    request.admin_username = admin.username
    request.decided_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(request)

    if listener:
        await manager.send_to_listener(listener.id, {
            "type": "withdrawal_decision",
            "request_id": request.id,
            "status": "rejected",
            "coins": request.coins,
        })
        if listener.fcm_token:
            send_async(send_withdrawal_decision, listener.fcm_token, request.id, "rejected", request.coins)

    out = WithdrawalRequestOut.model_validate(request)
    out.listener_name = listener.name if listener else None
    return out
