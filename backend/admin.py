from fastapi import APIRouter, Query
import state
from pydantic import BaseModel

router = APIRouter(prefix="/admin")

@router.get("/stats")
async def admin_stats():

    async with state.db_pool.acquire() as conn:
        users = await conn.fetch("""
            SELECT
            username,
            created_at,
            role,
            is_online,
            coins,
            total_call_duration,
            daily_call_duration
            FROM users
        """)

    return {
        "users": [
            {
                "username": u["username"],
                "created_at": str(u["created_at"]),
                "online": u["is_online"],
                "coins": u["coins"],
                "total_duration": u["total_call_duration"],
                "daily_duration": u["daily_call_duration"]
            }
            for u in users
            if u["role"] == "user"
        ],

        "listeners": [
            {
                "username": u["username"],
                "created_at": str(u["created_at"]),
                "online": u["is_online"],
                "coins": u["coins"],
                "total_duration": u["total_call_duration"],
                "daily_duration": u["daily_call_duration"]
            }
            for u in users
            if u["role"] == "listener"
        ],

        "online_users": list(state.clients.keys()),

        "active_calls": [
            {
                "caller": a,
                "target": b
            }
            for a, b in state.active_calls.items()
            if a < b
        ]
    }

class SetCoinsRequest(BaseModel):
    username: str
    coins: int

@router.post("/set_coins")
async def set_coins(req: SetCoinsRequest):
    async with state.db_pool.acquire() as conn:
        await conn.execute("UPDATE users SET coins=$1 WHERE username=$2", req.coins, req.username.lower())
    return {"status": "ok"}


@router.post("/coins")
async def update_coins(
    username: str = Query(...),
    coins: int = Query(...)
):
    async with state.db_pool.acquire() as conn:
        await conn.execute(
            "UPDATE users SET coins=$1 WHERE username=$2",
            coins,
            username.lower()
        )
    return {"status": "ok"}
    
    
@router.post("/rate")
async def update_rate(
    coins_per_minute: int = Query(...)
):
    async with state.db_pool.acquire() as conn:
        await conn.execute(
            "UPDATE app_settings SET value=$1 WHERE key=$2",
            str(coins_per_minute),
            "coins_per_minute"
        )
    return {"status": "ok"}