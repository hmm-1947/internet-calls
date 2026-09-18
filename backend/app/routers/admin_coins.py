from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.models.models import User, CoinSettings, Listener
from app.routers.admin import verify_admin
from app.utils.coins import get_coin_settings, invalidate_coin_settings_cache
from app.core.ws_manager import manager
from pydantic import BaseModel

router = APIRouter(prefix="/admin/coins", tags=["admin_coins"])

class CoinAdjust(BaseModel):
    user_id: int
    amount: int

class ListenerCoinAdjust(BaseModel):
    listener_id: int
    amount: int

class CoinSettingsUpdate(BaseModel):
    audio_coins_per_minute: int
    video_coins_per_minute: int
    chat_message_coins: int
    voice_message_coins: int


@router.get("/users")
def list_users(db: Session = Depends(get_db), _=Depends(verify_admin)):
    users = db.query(User).all()
    # `username`/`email` are shown in the admin panel's user list and detail
    # header, and are searchable there, so they travel with every row.
    result = [{"id": u.id, "name": u.name, "username": u.username, "email": u.email, "phone": u.phone, "coins": u.coins, "is_active": u.is_active, "is_online": manager.is_user_online(u.id), "bio": u.bio, "photo_url": u.photo_url, "video_call_disabled_by_admin": u.video_call_disabled_by_admin} for u in users]
    result.sort(key=lambda x: not x["is_online"])
    return result

@router.post("/adjust")
def adjust_coins(payload: CoinAdjust, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == payload.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.coins += payload.amount
    if user.coins < 0:
        user.coins = 0
    db.commit()
    return {"id": user.id, "coins": user.coins}

@router.get("/listeners")
def list_listeners(db: Session = Depends(get_db), _=Depends(verify_admin)):
    listeners = db.query(Listener).all()
    result = [{"id": l.id, "name": l.name, "phone": l.phone, "coins": l.coins, "is_active": l.is_active, "is_online": manager.is_listener_online(l.id), "about": l.about, "tags": l.tags, "languages": l.languages, "photo_url": l.photo_url, "age": l.age, "occupation": l.occupation} for l in listeners]
    result.sort(key=lambda x: not x["is_online"])
    return result

@router.post("/listener/adjust")
def adjust_listener_coins(payload: ListenerCoinAdjust, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == payload.listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    listener.coins += payload.amount
    if listener.coins < 0:
        listener.coins = 0
    db.commit()
    return {"id": listener.id, "coins": listener.coins}

@router.get("/settings")
def get_settings(db: Session = Depends(get_db), _=Depends(verify_admin)):
    s = get_coin_settings(db)
    return {"audio_coins_per_minute": s.audio_coins_per_minute, "video_coins_per_minute": s.video_coins_per_minute, "chat_message_coins": s.chat_message_coins, "voice_message_coins": s.voice_message_coins}

@router.post("/settings")
def update_settings(payload: CoinSettingsUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    # Fetch the tracked row directly rather than through get_coin_settings(),
    # which may hand back a detached cached copy that db.commit() wouldn't
    # persist.
    s = db.query(CoinSettings).first()
    if not s:
        s = CoinSettings()
        db.add(s)
    s.audio_coins_per_minute = payload.audio_coins_per_minute
    s.video_coins_per_minute = payload.video_coins_per_minute
    s.chat_message_coins = payload.chat_message_coins
    s.voice_message_coins = payload.voice_message_coins
    db.commit()
    invalidate_coin_settings_cache()
    return {"audio_coins_per_minute": s.audio_coins_per_minute, "video_coins_per_minute": s.video_coins_per_minute, "chat_message_coins": s.chat_message_coins, "voice_message_coins": s.voice_message_coins}
