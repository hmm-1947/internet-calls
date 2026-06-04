from fastapi import APIRouter
from pydantic import BaseModel
import state

router = APIRouter()

class SendMessageRequest(BaseModel):
    sender: str
    receiver: str
    content: str

@router.post("/messages")
async def send_message(req: SendMessageRequest):
    async with state.db_pool.acquire() as conn:
        row = await conn.fetchrow(
            "INSERT INTO messages (sender, receiver, content) VALUES ($1, $2, $3) RETURNING id, sender, receiver, content, created_at",
            req.sender.strip().lower(), req.receiver.strip().lower(), req.content.strip()
        )
    return {
        "id": row["id"], "sender": row["sender"], "receiver": row["receiver"],
        "content": row["content"], "created_at": row["created_at"].isoformat(),
    }

@router.get("/messages/{user1}/{user2}")
async def get_messages(user1: str, user2: str):
    async with state.db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, sender, receiver, content, created_at FROM messages
            WHERE (sender=$1 AND receiver=$2) OR (sender=$2 AND receiver=$1)
            ORDER BY created_at ASC
            """,
            user1.strip().lower(), user2.strip().lower()
        )
    return [
        {"id": r["id"], "sender": r["sender"], "receiver": r["receiver"],
         "content": r["content"], "created_at": r["created_at"].isoformat()}
        for r in rows
    ]

@router.get("/chats/{username}")
async def get_chats(username: str):
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