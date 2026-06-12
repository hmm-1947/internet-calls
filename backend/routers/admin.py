from fastapi import APIRouter, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from jose import jwt, JWTError
import bcrypt
import os
from datetime import datetime, timedelta
from database import get_pool

router = APIRouter(prefix="/admin", tags=["admin"])

SECRET_KEY = os.getenv("SECRET_KEY", "supersecretkey")
ALGORITHM = "HS256"
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "adminpassword")

bearer = HTTPBearer()


def make_token(data: dict):
    payload = data.copy()
    payload["exp"] = datetime.utcnow() + timedelta(minutes=60 * 24)
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def verify_admin(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("role") != "admin":
            raise HTTPException(status_code=403, detail="Forbidden")
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")


class AdminLogin(BaseModel):
    username: str
    password: str


class CreateListener(BaseModel):
    username: str
    password: str


@router.post("/login")
async def admin_login(body: AdminLogin):
    if body.username != ADMIN_USERNAME or body.password != ADMIN_PASSWORD:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = make_token({"sub": body.username, "role": "admin"})
    return {"access_token": token, "token_type": "bearer"}


@router.get("/listeners")
async def list_listeners(payload: dict = Depends(verify_admin)):
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("SELECT username, is_online, created_at FROM listeners ORDER BY created_at DESC")
    return {"listeners": [dict(r) for r in rows]}


@router.post("/listener")
async def create_listener(body: CreateListener, payload: dict = Depends(verify_admin)):
    pool = await get_pool()
    hashed = bcrypt.hashpw(body.password.encode(), bcrypt.gensalt()).decode()
    async with pool.acquire() as conn:
        existing = await conn.fetchrow("SELECT id FROM listeners WHERE username = $1", body.username)
        if existing:
            raise HTTPException(status_code=400, detail="Username already taken")
        await conn.execute(
            "INSERT INTO listeners (username, password_hash) VALUES ($1, $2)",
            body.username, hashed
        )
    return {"message": "Listener created successfully"}


@router.delete("/listener/{username}")
async def delete_listener(username: str, payload: dict = Depends(verify_admin)):
    pool = await get_pool()
    async with pool.acquire() as conn:
        result = await conn.execute("DELETE FROM listeners WHERE username = $1", username)
    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="Listener not found")
    return {"message": "Listener deleted successfully"}