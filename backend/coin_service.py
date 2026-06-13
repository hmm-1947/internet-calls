from datetime import datetime
import math
from database import get_pool

async def get_coin_rate() -> float:
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT coins_per_minute FROM coin_settings ORDER BY id DESC LIMIT 1")
    return float(row["coins_per_minute"]) if row else 1.0

async def get_user_coins(user_id: str) -> float:
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT coins FROM users WHERE id = $1", int(user_id))
    return float(row["coins"]) if row else 0.0

async def has_enough_coins(user_id: str) -> bool:
    rate = await get_coin_rate()
    coins = await get_user_coins(user_id)
    return coins >= rate

async def deduct_coins(user_id: str, duration_seconds: int) -> dict:
    rate = await get_coin_rate()
    minutes = math.ceil(duration_seconds / 60)
    total = rate * minutes
    coins = await get_user_coins(user_id)

    if coins < total:
        total = coins

    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute("UPDATE users SET coins = coins - $1 WHERE id = $2", total, int(user_id))
        await conn.execute("INSERT INTO coin_transactions (user_id, amount, minutes, created_at) VALUES ($1, $2, $3, $4)",
        int(user_id), total, minutes, datetime.utcnow()
)
    return {"deducted": total, "minutes_billed": minutes, "remaining": coins - total}