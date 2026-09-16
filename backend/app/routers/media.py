"""Serves call recordings and voice notes, replacing the old public
StaticFiles mounts at /recordings and /voice_notes (see media_urls.py for
why this is signed-URL based instead of a normal auth dependency)."""
import os

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

from app.utils.media_urls import verify_media_signature

router = APIRouter(prefix="/media", tags=["media"])

_DIRS = {
    "recordings": "recordings",
    "voice_notes": "voice_notes",
}


@router.get("/{prefix}/{filename}")
def serve_media(prefix: str, filename: str, expires: int = Query(...), sig: str = Query(...)):
    directory = _DIRS.get(prefix)
    if not directory:
        raise HTTPException(status_code=404, detail="Not found")
    if not verify_media_signature(prefix, filename, expires, sig):
        raise HTTPException(status_code=403, detail="Invalid or expired link")
    # basename() strips any path separators the client might sneak into
    # `filename`, so this can never escape `directory` (no `../../etc/passwd`).
    safe_name = os.path.basename(filename)
    path = os.path.join(directory, safe_name)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(path)
