from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
import bcrypt
from jose import jwt
import os
from datetime import datetime, timedelta
from database import get_pool
from routers.livekit import decode_token

router = APIRouter(prefix="/auth", tags=["auth"])

SECRET_KEY = os.getenv("SECRET_KEY", "supersecretkey")
ALGORITHM = "HS256"
TOKEN_EXPIRE_MINUTES = 60 * 24


def make_token(data: dict):
    payload = data.copy()
    payload["exp"] = datetime.utcnow() + timedelta(minutes=TOKEN_EXPIRE_MINUTES)
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


class UserRegister(BaseModel):
    username: str
    password: str


class UserLogin(BaseModel):
    username: str
    password: str


@router.post("/user/register")
async def register(body: UserRegister):
    pool = await get_pool()
    hashed = bcrypt.hashpw(body.password.encode(), bcrypt.gensalt()).decode()
    async with pool.acquire() as conn:
        existing = await conn.fetchrow("SELECT id FROM users WHERE username = $1", body.username)
        if existing:
            raise HTTPException(status_code=400, detail="Username already taken")
        await conn.execute(
            "INSERT INTO users (username, password_hash) VALUES ($1, $2)",
            body.username, hashed
        )
    return {"message": "User registered successfully"}


@router.post("/user/login")
async def user_login(body: UserLogin):
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM users WHERE username = $1", body.username)
    if not row or not bcrypt.checkpw(body.password.encode(), row["password_hash"].encode()):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = make_token({"sub": row["username"], "role": "user"})
    return {"access_token": token, "token_type": "bearer"}


@router.post("/listener/login")
async def listener_login(body: UserLogin):
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM listeners WHERE username = $1", body.username)
    if not row or not bcrypt.checkpw(body.password.encode(), row["password_hash"].encode()):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = make_token({"sub": row["username"], "role": "listener"})
    return {"access_token": token, "token_type": "bearer"}


@router.post("/listener/online")
async def set_online(payload: dict = Depends(decode_token)):
    if payload.get("role") != "listener":
        raise HTTPException(status_code=403, detail="Forbidden")
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute("UPDATE listeners SET is_online = TRUE WHERE username = $1", payload["sub"])
    return {"status": "online"}


@router.post("/listener/offline")
async def set_offline(payload: dict = Depends(decode_token)):
    if payload.get("role") != "listener":
        raise HTTPException(status_code=403, detail="Forbidden")
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute("UPDATE listeners SET is_online = FALSE WHERE username = $1", payload["sub"])
    return {"status": "offline"}