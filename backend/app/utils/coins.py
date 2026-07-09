from sqlalchemy.orm import Session
from app.models.models import CoinSettings, User, CoinTransaction

def get_coin_settings(db: Session) -> CoinSettings:
    settings = db.query(CoinSettings).first()
    if not settings:
        settings = CoinSettings(audio_coins_per_minute=10, video_coins_per_minute=10)
        db.add(settings)
        db.commit()
        db.refresh(settings)
    return settings

def coins_per_minute(db: Session, call_type: str) -> int:
    settings = get_coin_settings(db)
    return settings.video_coins_per_minute if call_type == "video" else settings.audio_coins_per_minute

def max_call_seconds(db: Session, user: User, call_type: str) -> int:
    per_minute = coins_per_minute(db, call_type)
    if per_minute <= 0:
        return 0
    minutes_available = user.coins // per_minute
    return minutes_available * 60

def deduct_coins(db: Session, user: User, call_id: int, duration_seconds: int, call_type: str) -> int:
    per_minute = coins_per_minute(db, call_type)
    minutes_used = max(1, duration_seconds // 60)
    amount = minutes_used * per_minute
    amount = min(amount, user.coins)
    user.coins -= amount
    db.add(CoinTransaction(user_id=user.id, amount=-amount, reason=f"{call_type}_call", call_id=call_id))
    db.commit()
    return amount