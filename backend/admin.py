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

@router.get("/messages/{user1}/{user2}")
async def admin_get_messages(user1: str, user2: str):
    async with state.db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT sender, receiver, content, created_at, message_type FROM messages
            WHERE (sender=$1 AND receiver=$2) OR (sender=$2 AND receiver=$1)
            ORDER BY created_at ASC
            """,
            user1.strip().lower(), user2.strip().lower()
        )
    return [
        {"sender": r["sender"], "receiver": r["receiver"],
         "content": r["content"], "created_at": r["created_at"].isoformat(),
         "message_type": r["message_type"]}
        for r in rows
    ]

@router.get("/chats/{username}")
async def admin_get_chats(username: str):
    username = username.strip().lower()
    async with state.db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT other_user, content, created_at
            FROM (
                SELECT CASE WHEN sender=$1 THEN receiver ELSE sender END AS other_user,
                       content, created_at,
                       ROW_NUMBER() OVER (
                           PARTITION BY CASE WHEN sender=$1 THEN receiver ELSE sender END
                           ORDER BY created_at DESC
                       ) as rn
                FROM messages WHERE sender=$1 OR receiver=$1
            ) sub
            WHERE rn = 1
            ORDER BY created_at DESC
            """,
            username
        )
    return [
        {"other_user": r["other_user"], "last_message": r["content"],
         "last_at": r["created_at"].isoformat()}
        for r in rows
    ]


@router.get("/recordings/all/{username}")
async def admin_get_recordings(username: str):
    async with state.db_pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, caller, listener, filename, created_at FROM recordings WHERE caller=$1 OR listener=$1 ORDER BY created_at DESC",
            username.strip().lower()
        )
    return [{"id": r["id"], "caller": r["caller"], "listener": r["listener"], "filename": r["filename"], "created_at": r["created_at"].isoformat()} for r in rows]
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