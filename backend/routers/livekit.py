from fastapi import APIRouter, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
import os
from database import get_pool
from livekit.api import AccessToken, VideoGrants
from routers.websocket import send_to, registry

router = APIRouter(prefix="/livekit", tags=["livekit"])

SECRET_KEY = os.getenv("SECRET_KEY", "supersecretkey")
ALGORITHM = "HS256"
LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY", "devkey")
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET", "devsecret")

bearer = HTTPBearer()


def decode_token(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")


@router.get("/online-listeners")
async def online_listeners(payload: dict = Depends(decode_token)):
    if payload.get("role") != "user":
        raise HTTPException(status_code=403, detail="Only users can view listeners")
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("SELECT username FROM listeners WHERE is_online = TRUE")
    return {"listeners": [r["username"] for r in rows]}



@router.post("/token")
async def get_token(listener_username: str, payload: dict = Depends(decode_token)):
    if payload.get("role") != "user":
        raise HTTPException(status_code=403, detail="Only users can initiate calls")
    if listener_username not in registry:
        raise HTTPException(status_code=404, detail="Listener not connected")
    pool = await get_pool()
    async with pool.acquire() as conn:
        listener = await conn.fetchrow(
            "SELECT username FROM listeners WHERE username = $1 AND is_online = TRUE",
            listener_username
        )
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not available")
    caller = payload["sub"]
    room_name = f"room_{caller}_{listener_username}"
    user_token = (
        AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        .with_identity(caller)
        .with_grants(VideoGrants(room_join=True, room=room_name))
        .to_jwt()
    )
    listener_token = (
        AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        .with_identity(listener_username)
        .with_grants(VideoGrants(room_join=True, room=room_name))
        .to_jwt()
    )
    await send_to(listener_username, {
        "event": "incoming_call",
        "from": caller,
        "room": room_name,
        "token": listener_token,
    })
    return {"token": user_token, "room": room_name}


@router.post("/video-token")
async def get_video_token(listener_username: str, payload: dict = Depends(decode_token)):
    if payload.get("role") != "user":
        raise HTTPException(status_code=403, detail="Only users can initiate calls")
    if listener_username not in registry:
        raise HTTPException(status_code=404, detail="Listener not connected")
    pool = await get_pool()
    async with pool.acquire() as conn:
        listener = await conn.fetchrow(
            "SELECT username FROM listeners WHERE username = $1 AND is_online = TRUE",
            listener_username
        )
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not available")
    caller = payload["sub"]
    room_name = f"video_{caller}_{listener_username}"
    user_token = (
        AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        .with_identity(caller)
        .with_grants(VideoGrants(room_join=True, room=room_name))
        .to_jwt()
    )
    listener_token = (
        AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        .with_identity(listener_username)
        .with_grants(VideoGrants(room_join=True, room=room_name))
        .to_jwt()
    )
    await send_to(listener_username, {
        "event": "incoming_video_call",
        "from": caller,
        "room": room_name,
        "token": listener_token,
    })
    return {"token": user_token, "room": room_name}