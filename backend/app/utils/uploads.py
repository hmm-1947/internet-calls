import asyncio
import os
from fastapi import HTTPException, UploadFile

MAX_IMAGE_SIZE_BYTES = 5 * 1024 * 1024

_MAGIC_BYTES = {
    b"\xff\xd8\xff": ".jpg",
    b"\x89PNG\r\n\x1a\n": ".png",
    b"GIF87a": ".gif",
    b"GIF89a": ".gif",
    b"RIFF": ".webp",
}

_EXT_FOR_MAGIC = {
    b"\xff\xd8\xff": {".jpg", ".jpeg"},
    b"\x89PNG\r\n\x1a\n": {".png"},
    b"GIF87a": {".gif"},
    b"GIF89a": {".gif"},
    b"RIFF": {".webp"},
}


def _detect_image_ext(header: bytes) -> str | None:
    for magic, ext in _MAGIC_BYTES.items():
        if header.startswith(magic):
            return ext
    return None


async def read_and_validate_image(file: UploadFile) -> tuple[bytes, str]:
    contents = await file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(contents) > MAX_IMAGE_SIZE_BYTES:
        raise HTTPException(status_code=400, detail="File too large (max 5MB)")

    detected_ext = _detect_image_ext(contents[:12])
    if not detected_ext:
        raise HTTPException(status_code=400, detail="Unsupported or invalid image file")

    return contents, detected_ext


async def write_file(filepath: str, contents: bytes) -> None:
    def _write():
        with open(filepath, "wb") as f:
            f.write(contents)

    await asyncio.to_thread(_write)