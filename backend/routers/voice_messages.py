import os
import uuid
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse
import state

router = APIRouter()

VOICE_DIR = "voice_messages"
os.makedirs(VOICE_DIR, exist_ok=True)

@router.post("/voice_messages")
async def upload_voice_message(
    sender: str = Form(...),
    receiver: str = Form(...),
    file: UploadFile = File(...)
):
    sender = sender.strip().lower()
    receiver = receiver.strip().lower()
    
    filename = f"{uuid.uuid4()}.aac"
    filepath = os.path.join(VOICE_DIR, filename)
    
    content = await file.read()
    with open(filepath, "wb") as f:
        f.write(content)
    
    async with state.db_pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            INSERT INTO messages (sender, receiver, content, message_type)
            VALUES ($1, $2, $3, 'voice')
            RETURNING id, sender, receiver, content, created_at, message_type
            """,
            sender, receiver, filename
        )
    
    if receiver in state.clients:
        import json
        await state.clients[receiver].send_text(json.dumps({
            "type": "chat_message",
            "from": sender,
            "content": filename,
            "message_type": "voice",
        }))
    
    return {
        "id": row["id"],
        "sender": row["sender"],
        "receiver": row["receiver"],
        "content": row["content"],
        "message_type": row["message_type"],
        "created_at": row["created_at"].isoformat(),
    }

@router.get("/voice_messages/{filename}")
async def get_voice_message(filename: str):
    filepath = os.path.join(VOICE_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404)
    return FileResponse(filepath, media_type="audio/aac")