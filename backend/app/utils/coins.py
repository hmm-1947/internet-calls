from sqlalchemy.orm import Session
from app.models.models import CoinSettings, User, CoinTransaction, Call, Listener, ListenerCoinTransaction

def get_coin_settings(db: Session) -> CoinSettings:
    settings = db.query(CoinSettings).first()
    if not settings:
        settings = CoinSettings(audio_coins_per_minute=10, video_coins_per_minute=10, chat_message_coins=1, voice_message_coins=1)
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

def voice_message_coin_cost(db: Session) -> int:
    settings = get_coin_settings(db)
    return settings.voice_message_coins

# A call that cannot be billed at all (the per-minute rate is 0) has no coin
# cut-off. The apps end the call when the allowance runs out, so hand them a
# value no real call will ever reach instead of 0, which would end it at once.
UNLIMITED_CALL_SECONDS = 24 * 60 * 60


def remaining_call_seconds(db: Session, user: User, call: Call, elapsed_seconds: int = 0) -> int:
    """How much longer this call may run, counting from now.

    The balance on its own is not the answer once a call is live. The first
    minute is charged the instant the call connects, so a user who could afford
    exactly one minute is left on zero coins while still having a paid minute
    ahead of them. The caller's app arms its cut-off timer from this value right
    after joining the room, so reading the bare balance there ended video calls
    within seconds of them connecting, without the user getting the minute they
    had just paid for.
    """
    per_minute = coins_per_minute(db, call.call_type)
    if per_minute <= 0:
        return UNLIMITED_CALL_SECONDS
    paid_seconds = (call.billed_minutes or 0) * 60
    remaining_paid = max(0, paid_seconds - max(0, elapsed_seconds))
    affordable_seconds = (user.coins // per_minute) * 60
    return remaining_paid + affordable_seconds

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

async def bill_call_minute(db: Session, call: Call) -> int | None:
    """Bill exactly one minute for the given call's user, at current settings.
    Returns the amount deducted, or None if the user doesn't have enough coins."""
    user = db.query(User).filter(User.id == call.caller_user_id).first()
    if not user:
        return None
    per_minute = coins_per_minute(db, call.call_type)
    if per_minute <= 0:
        call.billed_minutes += 1
        db.commit()
        return 0
    if user.coins < per_minute:
        return None
    user.coins -= per_minute
    call.billed_minutes += 1
    call.coins_deducted = (call.coins_deducted or 0) + per_minute
    db.add(CoinTransaction(user_id=user.id, amount=-per_minute, reason=f"{call.call_type}_call", call_id=call.id))
    db.commit()
    from app.core.ws_manager import manager
    await manager.send_to_user(user.id, {"type": "coins_updated", "coins": user.coins})
    return per_minute

async def reconcile_call_billing(db: Session, call: Call, duration_seconds: int) -> int:
    """Called when a call ends. The live per-minute loop already bills each
    minute as it starts (ceil-style billing). This only charges for any
    final minute that started but wasn't billed yet by the loop, e.g. if the
    call ends in the same tick the loop is about to run. Returns the total
    coins deducted for the whole call (call.coins_deducted)."""
    user = db.query(User).filter(User.id == call.caller_user_id).first()
    if not user:
        return call.coins_deducted or 0
    per_minute = coins_per_minute(db, call.call_type)
    total_minutes = max(1, -(-duration_seconds // 60)) if duration_seconds > 0 else 0
    remaining_minutes = max(0, total_minutes - (call.billed_minutes or 0))
    if remaining_minutes > 0 and per_minute > 0:
        amount = min(remaining_minutes * per_minute, user.coins)
        user.coins -= amount
        call.billed_minutes = (call.billed_minutes or 0) + remaining_minutes
        call.coins_deducted = (call.coins_deducted or 0) + amount
        db.add(CoinTransaction(user_id=user.id, amount=-amount, reason=f"{call.call_type}_call", call_id=call.id))
        db.commit()
        from app.core.ws_manager import manager
        await manager.send_to_user(user.id, {"type": "coins_updated", "coins": user.coins})
    return call.coins_deducted or 0



async def deduct_chat_coins(db: Session, user: User, listener_id: int, message_id: int) -> int:
    cost = chat_message_coin_cost(db)
    if cost < 0:
        raise ValueError("Chat message coin cost cannot be negative")
    locked_user = db.query(User).filter(User.id == user.id).with_for_update().first()
    if not locked_user or locked_user.coins < cost:
        raise ValueError("Not enough coins to send this message")

    # A message is always charged at its configured cost.  Do not use a
    # partial deduction here: that would allow messages when the balance is
    # below the required price (including a zero balance).
    locked_user.coins -= cost
    user.coins = locked_user.coins
    db.add(CoinTransaction(user_id=user.id, amount=-cost, reason="chat_message", call_id=None))
    db.commit()
    from app.core.ws_manager import manager
    await manager.send_to_user(user.id, {"type": "coins_updated", "coins": user.coins})

    return cost

async def deduct_voice_message_coins(db: Session, user: User, listener_id: int, message_id: int) -> int:
    cost = voice_message_coin_cost(db)
    if cost < 0:
        raise ValueError("Voice message coin cost cannot be negative")
    locked_user = db.query(User).filter(User.id == user.id).with_for_update().first()
    if not locked_user or locked_user.coins < cost:
        raise ValueError("Not enough coins to send this voice message")

    locked_user.coins -= cost
    user.coins = locked_user.coins
    db.add(CoinTransaction(user_id=user.id, amount=-cost, reason="voice_message", call_id=None))
    db.commit()
    from app.core.ws_manager import manager
    await manager.send_to_user(user.id, {"type": "coins_updated", "coins": user.coins})

    return cost

