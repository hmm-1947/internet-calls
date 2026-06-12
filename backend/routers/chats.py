from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from database import get_pool
from routers.websocket import send_to
import os

router = APIRouter(prefix="/chats", tags=["Chats"])

SECRET_KEY = os.getenv("SECRET_KEY", "supersecretkey")
ALGORITHM = "HS256"

bearer = HTTPBearer()

def decode_token(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    try:
        return jwt.decode(
            credentials.credentials,
            SECRET_KEY,
            algorithms=[ALGORITHM]
        )
    except JWTError:
        raise HTTPException(status_code=401)


@router.post("/start")
async def start_chat(
    listener_username: str,
    payload: dict = Depends(decode_token)
):
    if payload["role"] != "user":
        raise HTTPException(status_code=403)

    user = payload["sub"]

    pool = await get_pool()

    async with pool.acquire() as conn:

        await conn.execute(
            """
            INSERT INTO conversations
            (user_username, listener_username)
            VALUES ($1,$2)
            ON CONFLICT DO NOTHING
            """,
            user,
            listener_username
        )

        row = await conn.fetchrow(
            """
            SELECT *
            FROM conversations
            WHERE user_username=$1
            AND listener_username=$2
            """,
            user,
            listener_username
        )

    return {"conversation_id": row["id"]}

@router.get("/list")
async def get_chat_list(
    payload: dict = Depends(decode_token)
):
    username = payload["sub"]
    role = payload["role"]

    pool = await get_pool()

    async with pool.acquire() as conn:

        if role == "user":

            rows = await conn.fetch(
                """
                SELECT id,
                       listener_username AS partner
                FROM conversations
                WHERE user_username=$1
                ORDER BY id DESC
                """,
                username
            )

        else:

            rows = await conn.fetch(
                """
                SELECT id,
                       user_username AS partner
                FROM conversations
                WHERE listener_username=$1
                ORDER BY id DESC
                """,
                username
            )

    return [dict(r) for r in rows]

@router.get("/{conversation_id}/messages")
async def get_messages(
    conversation_id: int,
    payload: dict = Depends(decode_token)
):
    pool = await get_pool()

    async with pool.acquire() as conn:

        rows = await conn.fetch(
            """
            SELECT *
            FROM messages
            WHERE conversation_id=$1
            ORDER BY created_at ASC
            """,
            conversation_id
        )

    return [dict(r) for r in rows]

@router.post("/send")
async def send_message(
    conversation_id: int,
    message: str,
    payload: dict = Depends(decode_token)
):
    sender = payload["sub"]
    role = payload["role"]

    pool = await get_pool()

    async with pool.acquire() as conn:

        convo = await conn.fetchrow(
            """
            SELECT *
            FROM conversations
            WHERE id=$1
            """,
            conversation_id
        )

        if not convo:
            raise HTTPException(status_code=404)

        await conn.execute(
            """
            INSERT INTO messages
            (
                conversation_id,
                sender_username,
                sender_role,
                message
            )
            VALUES ($1,$2,$3,$4)
            """,
            conversation_id,
            sender,
            role,
            message
        )

    receiver = (
        convo["listener_username"]
        if role == "user"
        else convo["user_username"]
    )

    await send_to(
        receiver,
        {
            "event": "chat_message",
            "conversation_id": conversation_id,
            "sender": sender,
            "message": message
        }
    )

    return {"success": True}