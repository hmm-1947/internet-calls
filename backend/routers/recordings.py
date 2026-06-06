import os
import uuid
from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
import state
from fastapi import UploadFile, File, Form


router = APIRouter()

RECORDINGS_DIR = "recordings"
os.makedirs(RECORDINGS_DIR, exist_ok=True)


@router.post("/recordings/upload")
async def upload_recording(
    caller: str = Form(...),
    listener: str = Form(...),
    file: UploadFile = File(...)
):
    caller = caller.strip().lower()
    listener = listener.strip().lower()
    filename = f"{uuid.uuid4()}.aac"
    filepath = os.path.join(RECORDINGS_DIR, filename)
    content = await file.read()
    with open(filepath, "wb") as f:
        f.write(content)
    async with state.db_pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO recordings (caller, listener, filename) VALUES ($1, $2, $3)",
            caller, listener, filename
        )
    return {"status": "ok", "filename": filename}

@router.get("/recordings/{listener}")
async def get_recordings(listener: str):
    async with state.db_pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, caller, filename, created_at FROM recordings WHERE listener=$1 ORDER BY created_at DESC",
            listener.strip().lower()
        )
    return [{"id": r["id"], "caller": r["caller"], "filename": r["filename"], "created_at": r["created_at"].isoformat()} for r in rows]

@router.get("/recordings/file/{filename}")
async def get_recording_file(filename: str):
    filepath = os.path.join(RECORDINGS_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404)
    return FileResponse(filepath, media_type="audio/aac")