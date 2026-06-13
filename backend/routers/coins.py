from fastapi import APIRouter, Depends, HTTPException
from coin_service import get_user_coins, has_enough_coins, deduct_coins, get_coin_rate
from routers.livekit import decode_token
from database import get_pool

router = APIRouter(prefix="/coins", tags=["coins"])

@router.get("/balance")
async def balance(payload: dict = Depends(decode_token)):
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT id FROM users WHERE username = $1", payload["sub"])
    if not row:
        raise HTTPException(404, "User not found")
    coins = await get_user_coins(str(row["id"]))
    return {"coins": coins}

@router.get("/rate")
async def rate():
    r = await get_coin_rate()
    return {"coins_per_minute": r}

@router.get("/can-call")
async def can_call(payload: dict = Depends(decode_token)):
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT id FROM users WHERE username = $1", payload["sub"])
    if not row:
        raise HTTPException(404, "User not found")
    eligible = await has_enough_coins(str(row["id"]))
    return {"can_call": eligible}

@router.post("/deduct")
async def deduct(payload_body: dict, payload: dict = Depends(decode_token)):
    duration = payload_body.get("duration_seconds")
    if not duration or duration <= 0:
        raise HTTPException(400, "Invalid duration")
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT id FROM users WHERE username = $1", payload["sub"])
    if not row:
        raise HTTPException(404, "User not found")
    result = await deduct_coins(str(row["id"]), duration)
    return result

@router.post("/admin/rate")
async def set_rate(payload_body: dict, payload: dict = Depends(decode_token)):
    if payload.get("role") != "admin":
        raise HTTPException(403, "Forbidden")
    value = payload_body.get("coins_per_minute")
    if not value or value <= 0:
        raise HTTPException(400, "Invalid rate")
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO coin_settings (coins_per_minute, updated_at) VALUES ($1, NOW())",
            value
        )
    return {"coins_per_minute": value}

@router.post("/admin/add")
async def add_coins(payload: dict, payload_auth: dict = Depends(decode_token)):
    if payload_auth.get("role") != "admin":
        raise HTTPException(403, "Forbidden")
    username = payload.get("username")
    amount = payload.get("amount")
    if not username or not amount or amount <= 0:
        raise HTTPException(400, "Invalid input")
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT id, coins FROM users WHERE username = $1", username)
        if not row:
            raise HTTPException(404, "User not found")
        await conn.execute("UPDATE users SET coins = coins + $1 WHERE username = $2", amount, username)
        new_balance = float(row["coins"]) + amount
    return {"new_balance": new_balance}