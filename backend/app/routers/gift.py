import os
import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.orm import Session
from pydantic import BaseModel
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.models import User, Listener, Gift, GiftAuditLog, GiftTransaction, CoinTransaction, Call, ListenerCoinTransaction, AdminUser, ChatMessage
from app.core.ws_manager import manager
from app.routers.admin import verify_admin
from app.routers.chat import _msg_dict
from app.schemas.schemas import GiftAuditLogOut
from app.utils.fcm import send_gift_received, send_async

router = APIRouter(prefix="/gift", tags=["gift"])


def _gift_to_dict(g: Gift) -> dict:
    return {"id": g.id, "name": g.name, "coins": g.coins, "icon": g.icon}


def _log_gift_action(db: Session, admin: AdminUser, action: str, gift_id: int | None, gift_name: str, details: str) -> None:
    db.add(
        GiftAuditLog(
            action=action,
            gift_id=gift_id,
            gift_name=gift_name,
            admin_id=admin.id,
            admin_username=admin.username,
            details=details,
        )
    )



@router.get("/admin/list")
def admin_list_gifts(db: Session = Depends(get_db), _=Depends(verify_admin)):
    gifts = db.query(Gift).order_by(Gift.coins.asc()).all()
    return [_gift_to_dict(g) for g in gifts]


@router.post("/admin/create")
async def admin_create_gift(
    name: str = Form(...),
    coins: int = Form(...),
    icon_file: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    name = (name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Gift name is required")
    if coins is None or coins <= 0:
        raise HTTPException(status_code=400, detail="Coins must be greater than 0")

    icon_path = None
    if icon_file is not None and icon_file.filename:
        ext = os.path.splitext(icon_file.filename)[1] or ".png"
        filename = f"gift_{uuid.uuid4().hex}{ext}"
        filepath = os.path.join("gift_icons", filename)
        with open(filepath, "wb") as f:
            f.write(await icon_file.read())
        icon_path = f"/gift_icons/{filename}"

    gift = Gift(name=name, coins=coins, icon=icon_path)
    db.add(gift)
    db.flush()  # assign gift.id before logging

    _log_gift_action(
        db,
        admin,
        action="created",
        gift_id=gift.id,
        gift_name=gift.name,
        details=f"{gift.coins} coins, icon={'set' if gift.icon else 'none'}",
    )

    db.commit()
    db.refresh(gift)
    return _gift_to_dict(gift)


@router.put("/admin/{gift_id}")
async def admin_update_gift(
    gift_id: int,
    name: str = Form(...),
    coins: int = Form(...),
    icon_file: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(verify_admin),
):
    gift = db.query(Gift).filter(Gift.id == gift_id).first()
    if not gift:
        raise HTTPException(status_code=404, detail="Gift not found")

    name = (name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Gift name is required")
    if coins is None or coins <= 0:
        raise HTTPException(status_code=400, detail="Coins must be greater than 0")

    changes = []
    if gift.name != name:
        changes.append(f"name: {gift.name} → {name}")
    if gift.coins != coins:
        changes.append(f"coins: {gift.coins} → {coins}")

    gift.name = name
    gift.coins = coins

    if icon_file is not None and icon_file.filename:
        ext = os.path.splitext(icon_file.filename)[1] or ".png"
        filename = f"gift_{uuid.uuid4().hex}{ext}"
        filepath = os.path.join("gift_icons", filename)
        with open(filepath, "wb") as f:
            f.write(await icon_file.read())
        gift.icon = f"/gift_icons/{filename}"
        changes.append("icon: updated")

    _log_gift_action(
        db,
        admin,
        action="updated",
        gift_id=gift.id,
        gift_name=gift.name,
        details="; ".join(changes) if changes else "No field changes",
    )

    db.commit()
    db.refresh(gift)
    return _gift_to_dict(gift)


@router.delete("/admin/{gift_id}")
def admin_delete_gift(gift_id: int, db: Session = Depends(get_db), admin: AdminUser = Depends(verify_admin)):
    gift = db.query(Gift).filter(Gift.id == gift_id).first()
    if not gift:
        raise HTTPException(status_code=404, detail="Gift not found")

    _log_gift_action(
        db,
        admin,
        action="deleted",
        gift_id=gift.id,
        gift_name=gift.name,
        details=f"Was: {gift.coins} coins, icon={'set' if gift.icon else 'none'}",
    )

    db.delete(gift)
    db.commit()
    return {"detail": "Gift deleted"}


@router.get("/admin/audit-log", response_model=list[GiftAuditLogOut])
def admin_gift_audit_log(db: Session = Depends(get_db), _=Depends(verify_admin)):
    """Returns gift add/update/delete history, most recent first."""
    return (
        db.query(GiftAuditLog)
        .order_by(GiftAuditLog.created_at.desc())
        .limit(200)
        .all()
    )


@router.get("/admin/transactions")
def admin_gift_transactions(db: Session = Depends(get_db), _=Depends(verify_admin)):
    rows = (
        db.query(GiftTransaction, User, Listener, Gift)
        .join(User, User.id == GiftTransaction.user_id)
        .join(Listener, Listener.id == GiftTransaction.listener_id)
        .join(Gift, Gift.id == GiftTransaction.gift_id)
        .order_by(GiftTransaction.created_at.desc())
        .all()
    )
    return [
        {
            "id": txn.id,
            "user_id": user.id,
            "user_name": user.name,
            "listener_id": listener.id,
            "listener_name": listener.name,
            "gift_id": gift.id,
            "gift_name": gift.name,
            "gift_icon": gift.icon,
            "coins": txn.coins,
            "call_id": txn.call_id,
            "created_at": txn.created_at.isoformat() if txn.created_at else None,
        }
        for txn, user, listener, gift in rows
    ]


class GiftSend(BaseModel):
    listener_id: int
    gift_id: int
    call_id: int | None = None


@router.get("/catalog")
def gift_catalog(db: Session = Depends(get_db)):
    gifts = db.query(Gift).order_by(Gift.coins.asc()).all()
    return [{"id": g.id, "name": g.name, "coins": g.coins, "icon": g.icon} for g in gifts]


@router.post("/send")
async def send_gift(payload: GiftSend, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    gift = db.query(Gift).filter(Gift.id == payload.gift_id).first()
    if not gift:
        raise HTTPException(status_code=404, detail="Gift not found")
    listener = db.query(Listener).filter(Listener.id == payload.listener_id, Listener.is_active == True).with_for_update().first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")

    call_id = payload.call_id
    if call_id is not None:
        call = db.query(Call).filter(Call.id == call_id).first()
        if not call or call.caller_user_id != current_user.id or call.callee_listener_id != listener.id:
            call_id = None

    locked_user = db.query(User).filter(User.id == current_user.id).with_for_update().first()
    if not locked_user or locked_user.coins < gift.coins:
        raise HTTPException(status_code=402, detail="Not enough coins to send this gift")

    locked_user.coins -= gift.coins
    current_user.coins = locked_user.coins
    db.add(CoinTransaction(user_id=current_user.id, amount=-gift.coins, reason="gift_sent", call_id=call_id))
    gift_txn = GiftTransaction(
        user_id=current_user.id,
        listener_id=listener.id,
        gift_id=gift.id,
        coins=gift.coins,
        call_id=call_id,
    )
    db.add(gift_txn)

    credit = gift.coins // 2
    listener.coins += credit
    db.add(ListenerCoinTransaction(listener_id=listener.id, amount=credit, reason="gift_received", call_id=call_id))

    is_online = manager.is_listener_online(listener.id)
    gift_txn.notified = is_online

    # Show the gift inline in the chat thread, same as a text/voice message.
    # sent_during_call marks whether it happened mid-call so the UI can show
    # "Sent during call" instead of a plain chat timestamp context.
    sent_during_call = call_id is not None
    gift_message_text = (
        f"Sent a gift during the call: {gift.name}" if sent_during_call else f"Sent a gift: {gift.name}"
    )
    gift_msg = ChatMessage(
        user_id=current_user.id,
        listener_id=listener.id,
        sender_type="user",
        message=gift_message_text,
        message_type="gift",
        gift_id=gift.id,
        gift_name=gift.name,
        gift_icon=gift.icon,
        gift_coins=gift.coins,
        call_id=call_id,
        status="delivered" if is_online else "sent",
        delivered_at=datetime.now(timezone.utc) if is_online else None,
    )
    db.add(gift_msg)

    db.commit()
    db.refresh(gift_msg)

    await manager.send_to_user(current_user.id, {"type": "coins_updated", "coins": current_user.coins})
    # Echo the gift message back to the sender too (listener already gets it
    # above) so it shows up inline in the sender's own chat pane right away,
    # the same way it does for the receiver — this is purely a UI push and
    # does not touch coins or the normal chat-message billing path.
    await manager.send_to_user(current_user.id, _msg_dict(gift_msg))
    await manager.send_to_listener(listener.id, _msg_dict(gift_msg))
    await manager.send_to_user(current_user.id, {"type": "message_status", "id": gift_msg.id, "client_id": gift_msg.client_id, "status": gift_msg.status})

    if is_online:
        await manager.send_to_listener(listener.id, {"type": "coins_updated", "coins": listener.coins})
        await manager.send_to_listener(listener.id, {
            "type": "gift_received",
            "gift_name": gift.name,
            "coins": gift.coins,
            "credited_coins": credit,
            "from_user_id": current_user.id,
            "from_user_name": current_user.name,
            "sent_during_call": sent_during_call,
        })

    if listener.fcm_token:
        send_async(
            send_gift_received,
            listener.fcm_token,
            gift.name,
            gift.coins,
            credit,
            current_user.id,
            current_user.name,
        )

    return {"coins": current_user.coins, "gift_coins": gift.coins, "gift_name": gift.name}
