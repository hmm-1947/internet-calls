from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.models import User, Listener, Gift, GiftTransaction, CoinTransaction, Call, ListenerCoinTransaction
from app.core.ws_manager import manager

router = APIRouter(prefix="/gift", tags=["gift"])


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
    listener = db.query(Listener).filter(Listener.id == payload.listener_id).first()
    if not listener or not listener.is_active:
        raise HTTPException(status_code=404, detail="Listener not found")
    if current_user.coins < gift.coins:
        raise HTTPException(status_code=402, detail="Not enough coins to send this gift")

    call_id = payload.call_id
    if call_id is not None:
        call = db.query(Call).filter(Call.id == call_id).first()
        if not call or call.caller_user_id != current_user.id or call.callee_listener_id != listener.id:
            call_id = None

    current_user.coins -= gift.coins
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

    db.commit()

    await manager.send_to_user(current_user.id, {"type": "coins_updated", "coins": current_user.coins})

    if is_online:
        await manager.send_to_listener(listener.id, {"type": "coins_updated", "coins": listener.coins})
        await manager.send_to_listener(listener.id, {
            "type": "gift_received",
            "gift_name": gift.name,
            "coins": gift.coins,
            "credited_coins": credit,
            "from_user_id": current_user.id,
            "from_user_name": current_user.name,
        })

    return {"coins": current_user.coins, "gift_coins": gift.coins, "gift_name": gift.name}
