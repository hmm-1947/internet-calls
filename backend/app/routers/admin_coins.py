from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.models.models import User, CoinSettings
from app.routers.admin import verify_admin
from app.utils.coins import get_coin_settings
from pydantic import BaseModel

router = APIRouter(prefix="/admin/coins", tags=["admin_coins"])

class CoinAdjust(BaseModel):
    user_id: int
    amount: int

class CoinSettingsUpdate(BaseModel):
    audio_coins_per_minute: int
    video_coins_per_minute: int

@router.get("/users")
def list_users(db: Session = Depends(get_db), _=Depends(verify_admin)):
    users = db.query(User).all()
    return [{"id": u.id, "name": u.name, "phone": u.phone, "coins": u.coins} for u in users]

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

@router.get("/settings")
def get_settings(db: Session = Depends(get_db), _=Depends(verify_admin)):
    s = get_coin_settings(db)
    return {"audio_coins_per_minute": s.audio_coins_per_minute, "video_coins_per_minute": s.video_coins_per_minute}

@router.post("/settings")
def update_settings(payload: CoinSettingsUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    s = get_coin_settings(db)
    s.audio_coins_per_minute = payload.audio_coins_per_minute
    s.video_coins_per_minute = payload.video_coins_per_minute
    db.commit()
    return {"audio_coins_per_minute": s.audio_coins_per_minute, "video_coins_per_minute": s.video_coins_per_minute}