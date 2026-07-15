from sqlalchemy.orm import Session
from app.models.models import CoinSettings, User, CoinTransaction, Call, Listener, ListenerCoinTransaction

def get_coin_settings(db: Session) -> CoinSettings:
    settings = db.query(CoinSettings).first()
    if not settings:
        settings = CoinSettings(audio_coins_per_minute=10, video_coins_per_minute=10, chat_message_coins=1)
        db.add(settings)
        db.commit()
        db.refresh(settings)
    return settings

def coins_per_minute(db: Session, call_type: str) -> int:
    settings = get_coin_settings(db)
    return settings.video_coins_per_minute if call_type == "video" else settings.audio_coins_per_minute

def chat_message_coin_cost(db: Session) -> int:
    settings = get_coin_settings(db)
    return settings.chat_message_coins

def max_call_seconds(db: Session, user: User, call_type: str) -> int:
    per_minute = coins_per_minute(db, call_type)
    if per_minute <= 0:
        return 0
    minutes_available = user.coins // per_minute
    return minutes_available * 60

async def _credit_listener(db: Session, listener_id: int, amount: int, reason: str, call_id: int | None = None):
    if amount <= 0:
        return
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        return
    listener.coins += amount
    db.add(ListenerCoinTransaction(listener_id=listener.id, amount=amount, reason=reason, call_id=call_id))
    db.commit()
    from app.core.ws_manager import manager
    await manager.send_to_listener(listener.id, {"type": "coins_updated", "coins": listener.coins})

async def deduct_coins(db: Session, user: User, call_id: int, duration_seconds: int, call_type: str) -> int:
    per_minute = coins_per_minute(db, call_type)
    minutes_used = max(1, duration_seconds // 60)
    amount = minutes_used * per_minute
    amount = min(amount, user.coins)
    user.coins -= amount
    db.add(CoinTransaction(user_id=user.id, amount=-amount, reason=f"{call_type}_call", call_id=call_id))
    db.commit()
    from app.core.ws_manager import manager
    await manager.send_to_user(user.id, {"type": "coins_updated", "coins": user.coins})

    call = db.query(Call).filter(Call.id == call_id).first()
    if call and call.callee_listener_id and amount > 0:
        await _credit_listener(db, call.callee_listener_id, amount // 2, f"{call_type}_call", call_id)

    return amount

async def deduct_chat_coins(db: Session, user: User, listener_id: int, message_id: int) -> int:
    cost = chat_message_coin_cost(db)
    if cost < 0:
        raise ValueError("Chat message coin cost cannot be negative")
    if user.coins < cost:
        raise ValueError("Not enough coins to send this message")

    # A message is always charged at its configured cost.  Do not use a
    # partial deduction here: that would allow messages when the balance is
    # below the required price (including a zero balance).
    user.coins -= cost
    db.add(CoinTransaction(user_id=user.id, amount=-cost, reason="chat_message", call_id=None))
    db.commit()
    from app.core.ws_manager import manager
    await manager.send_to_user(user.id, {"type": "coins_updated", "coins": user.coins})

    await _credit_listener(db, listener_id, cost // 2, "chat_message")

    return cost

