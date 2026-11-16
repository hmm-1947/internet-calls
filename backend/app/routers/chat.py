#chat.py
import asyncio
import logging
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, Query, UploadFile, File, Form
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel
import os
import shutil
import subprocess
import tempfile
import uuid
from starlette.websockets import WebSocketState
from sqlalchemy.orm import Session
from sqlalchemy import func, and_, or_
from app.core.database import get_db, SessionLocal
from app.core.deps import get_current_user, get_current_listener, get_current_participant
from app.models.models import ChatMessage, User, Listener, Session as SessionModel, ChatSettings, GiftTransaction, Gift, Call, ListenerBadgeTag, WebPushToken
from app.schemas.schemas import ChatMessageSend, ListenerChatMessageSend, ChatMessageOut, ChatThreadOut, TypingEvent, MessageEdit, ChatSettingsUpdate
from app.utils.fcm import send_chat_message, send_delivery_status, send_chat_summary, send_async, send_web_chat_push
from app.utils.coins import chat_message_coin_cost, deduct_chat_coins, voice_message_coin_cost, deduct_voice_message_coins
from app.utils.media_urls import sign_media_url
from app.core.ws_manager import manager

logger = logging.getLogger("chat_ws")

ACTIVE_CALL_STATUSES = ("ringing", "accepted")

VOICE_NOTES_DIR = "voice_notes"
ALLOWED_VOICE_EXTENSIONS = {".m4a", ".aac", ".mp3", ".wav", ".ogg", ".opus", ".webm"}
ALLOWED_VOICE_CONTENT_TYPES = {
    "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac", "audio/mpeg", "audio/mp3",
    "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave",
    "audio/ogg", "audio/opus", "audio/webm", "audio/3gpp", "audio/amr",
}
# Multipart clients frequently omit a real media type and fall back to a
# generic binary type (package:http's MultipartFile does exactly this), so
# these must not be treated as "not an audio file".
GENERIC_UPLOAD_CONTENT_TYPES = {
    "application/octet-stream", "binary/octet-stream", "application/binary",
}
MAX_VOICE_NOTE_BYTES = 10 * 1024 * 1024  # 10 MB
# Voice notes are chat history, potentially replayed years later, so this is
# effectively permanent rather than a short-lived link - the point is only to
# require a valid signature (i.e. that the backend actually issued this URL to
# a real conversation participant), not to force re-authentication on replay.
VOICE_NOTE_URL_TTL_SECONDS = 20 * 365 * 24 * 60 * 60


def _validate_voice_upload(file: UploadFile) -> str:
    """Validates a voice-note upload's extension/content-type and returns a
    safe extension to use for the stored filename. Raises HTTPException on
    anything that doesn't look like an audio file.

    The extension is the authoritative check. The content type is only
    rejected when the client explicitly claims a non-audio, non-generic type
    (for example "text/html"), because many clients send a generic binary
    content type for file uploads.
    """
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in ALLOWED_VOICE_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Unsupported voice note file type")
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    if (
        content_type
        and content_type not in ALLOWED_VOICE_CONTENT_TYPES
        and content_type not in GENERIC_UPLOAD_CONTENT_TYPES
    ):
        raise HTTPException(status_code=400, detail="Unsupported voice note content type")
    return ext


def _write_voice_file_sync(filepath: str, data: bytes) -> None:
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "wb") as f:
        f.write(data)


def _webm_to_m4a_sync(data: bytes) -> bytes | None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    try:
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "in.webm")
            dst = os.path.join(tmp, "out.m4a")
            with open(src, "wb") as f:
                f.write(data)
            proc = subprocess.run(
                [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", src,
                 "-vn", "-c:a", "aac", "-b:a", "64k", dst],
                capture_output=True, timeout=30,
            )
            if proc.returncode != 0 or not os.path.exists(dst):
                return None
            with open(dst, "rb") as f:
                return f.read()
    except Exception:
        return None


async def _save_voice_upload(file: UploadFile) -> str:
    """Validates, reads (with a size cap), and writes a voice-note upload off
    the event loop. Returns the filename (not the full path) to store."""
    ext = _validate_voice_upload(file)
    data = await file.read(MAX_VOICE_NOTE_BYTES + 1)
    if not data:
        raise HTTPException(status_code=400, detail="Empty voice note")
    if len(data) > MAX_VOICE_NOTE_BYTES:
        raise HTTPException(status_code=413, detail="Voice note exceeds maximum allowed size")
    if ext == ".webm":
        converted = await run_in_threadpool(_webm_to_m4a_sync, data)
        if converted:
            data = converted
            ext = ".m4a"
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(VOICE_NOTES_DIR, filename)
    await run_in_threadpool(_write_voice_file_sync, filepath, data)
    return filename

CALL_DISCONNECT_GRACE_SECONDS = 20

# Presence heartbeat. The apps send {"type": "ping"} every 10s while they are
# alive. If nothing at all arrives for WS_IDLE_TIMEOUT_SECONDS we send our own
# ping (so a merely quiet client keeps the socket warm), and after
# WS_MAX_IDLE_CYCLES consecutive silent windows we declare the peer gone.
#
# This is what catches "internet switched off" / "phone died": in those cases
# the OS never sends a TCP FIN, so receive() would otherwise block forever and
# the listener/user would stay marked online. A killed app or a clean close
# does send a FIN and is detected instantly regardless of these values.
WS_IDLE_TIMEOUT_SECONDS = 12
WS_MAX_IDLE_CYCLES = 2  # -> declared dead after ~24s of total silence


async def _run_ws_loop(websocket: WebSocket, handle_event) -> str:
    """Pump events off `websocket` until it dies and return *why*, as a short
    human-readable reason for the disconnect log. Never raises.

    Whatever ends the loop, the caller must run its offline cleanup: every
    return path here means this socket is no longer usable for presence.
    """
    idle_cycles = 0
    while True:
        try:
            raw = await asyncio.wait_for(websocket.receive_json(), timeout=WS_IDLE_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            idle_cycles += 1
            if idle_cycles >= WS_MAX_IDLE_CYCLES:
                silent_for = idle_cycles * WS_IDLE_TIMEOUT_SECONDS
                return f"no heartbeat for {silent_for}s (network lost or app killed without closing)"
            try:
                await websocket.send_json({"type": "ping"})
            except Exception as exc:
                return f"ping failed: {exc!r}"
            continue
        except WebSocketDisconnect as exc:
            return f"client closed (code={exc.code})"
        except RuntimeError as exc:
            # Starlette raises RuntimeError from receive_json() once *we* have
            # closed this socket, which only happens when the same account
            # opened a newer connection and ConnectionManager evicted this one.
            if websocket.application_state == WebSocketState.DISCONNECTED:
                return "superseded by a newer connection from the same account"
            return f"error: {exc!r}"
        except Exception as exc:
            return f"error: {exc!r}"
        idle_cycles = 0
        try:
            await handle_event(raw)
        except Exception as exc:
            return f"error handling {raw.get('type')!r} event: {exc!r}"


async def _finalize_active_calls_for_user(user_id: int, db: Session):
    from app.routers.call import finalize_abandoned_call
    calls = db.query(Call).filter(
        Call.caller_user_id == user_id,
        Call.status.in_(ACTIVE_CALL_STATUSES),
    ).all()
    for call in calls:
        await finalize_abandoned_call(db, call)

async def _finalize_active_calls_for_listener(listener_id: int, db: Session):
    from app.routers.call import finalize_abandoned_call
    calls = db.query(Call).filter(
        Call.callee_listener_id == listener_id,
        Call.status.in_(ACTIVE_CALL_STATUSES),
    ).all()
    for call in calls:
        await finalize_abandoned_call(db, call)

async def _finalize_active_calls_for_user_after_grace(user_id: int):
    await asyncio.sleep(CALL_DISCONNECT_GRACE_SECONDS)
    if manager.is_user_online(user_id):
        return
    db = SessionLocal()
    try:
        await _finalize_active_calls_for_user(user_id, db)
    finally:
        db.close()

async def _finalize_active_calls_for_listener_after_grace(listener_id: int):
    await asyncio.sleep(CALL_DISCONNECT_GRACE_SECONDS)
    if manager.is_listener_online(listener_id):
        return
    db = SessionLocal()
    try:
        await _finalize_active_calls_for_listener(listener_id, db)
    finally:
        db.close()


router = APIRouter(prefix="/chat", tags=["chat"])


def _require_chat_coins(db: Session, user: User) -> None:
    """Reject a chat send before the message is persisted when funds are short."""
    cost = chat_message_coin_cost(db)
    if cost < 0:
        raise HTTPException(status_code=500, detail="Invalid chat coin setting")
    if user.coins < cost:
        raise HTTPException(status_code=402, detail="Not enough coins to send this message")

def _require_voice_coins(db: Session, user: User) -> None:
    """Reject a voice-note send before the message is persisted when funds are short."""
    cost = voice_message_coin_cost(db)
    if cost < 0:
        raise HTTPException(status_code=500, detail="Invalid voice coin setting")
    if user.coins < cost:
        raise HTTPException(status_code=402, detail="Not enough coins to send this voice message")

def _get_settings(db, owner_type, owner_id, other_id):
    return db.query(ChatSettings).filter(
        ChatSettings.owner_type == owner_type,
        ChatSettings.owner_id == owner_id,
        ChatSettings.other_id == other_id,
    ).first()

def _is_muted(db, owner_type, owner_id, other_id) -> bool:
    """Whether owner_type/owner_id has muted their thread with other_id.
    Muted threads stay visible in the chat list; only push notifications
    are suppressed for them."""
    settings = _get_settings(db, owner_type, owner_id, other_id)
    return bool(settings and settings.is_muted)


def _web_push(db, user_id, sender_name, body, listener_id, message_id, photo_url):
    try:
        if manager.is_user_online(user_id) or _is_muted(db, "user", user_id, listener_id):
            return
        tokens = [t.token for t in db.query(WebPushToken).filter(WebPushToken.user_id == user_id).all()]
        if tokens:
            send_async(send_web_chat_push, tokens, sender_name, body, listener_id, message_id, photo_url)
    except Exception as e:
        print(f"[WEBPUSH ERROR] user {user_id}: {e}")


def _msg_dict(msg):
    return {
        "type": "chat_message",
        "id": msg.id,
        "client_id": msg.client_id,
        "user_id": msg.user_id,
        "listener_id": msg.listener_id,
        "sender_type": msg.sender_type,
        "message": msg.message,
        "message_type": msg.message_type,
        "audio_url": msg.audio_url,
        "audio_duration": msg.audio_duration,
        "gift_id": msg.gift_id,
        "gift_name": msg.gift_name,
        "gift_icon": msg.gift_icon,
        "gift_coins": msg.gift_coins,
        "call_id": msg.call_id,
        "call_type": msg.call_type,
        "call_status": msg.call_status,
        "call_duration_seconds": msg.call_duration_seconds,
        "status": msg.status,
        "is_read": msg.is_read,
        "delivered_at": msg.delivered_at.isoformat() if msg.delivered_at else None,
        "read_at": msg.read_at.isoformat() if msg.read_at else None,
        "edited_at": msg.edited_at.isoformat() if msg.edited_at else None,
        "is_deleted": msg.is_deleted,
        "created_at": msg.created_at.isoformat(),
    }


def _undelivered_summary_payload(db: Session, user_id: int, listener_id: int, sender_type: str):
    """Fetch messages sent by `sender_type` between this user/listener pair
    that are still 'sent' (i.e. not yet delivered), for an FCM chat summary."""
    undelivered = db.query(ChatMessage).filter(
        ChatMessage.user_id == user_id,
        ChatMessage.listener_id == listener_id,
        ChatMessage.sender_type == sender_type,
        ChatMessage.status == "sent",
    ).order_by(ChatMessage.id.asc()).all()
    return [
        {"id": m.id, "client_id": m.client_id, "message": m.message}
        for m in undelivered
    ]


CALL_LOG_PREVIEWS = {
    ("audio", "completed"): "📞 Voice call",
    ("video", "completed"): "📹 Video call",
    ("audio", "missed"): "📞 Missed voice call",
    ("video", "missed"): "📹 Missed video call",
    ("audio", "declined"): "📞 Voice call declined",
    ("video", "declined"): "📹 Video call declined",
    ("audio", "cancelled"): "📞 Voice call",
    ("video", "cancelled"): "📹 Video call",
}


async def record_call_message(
    db: Session,
    *,
    user_id: int,
    listener_id: int,
    call_id: int,
    call_type: str,
    call_status: str,
    duration_seconds: int = 0,
):
    """Appends a WhatsApp-style call-log entry to the chat between this user
    and listener, so a call — regardless of how it ended — shows up inline in
    the conversation on both sides, the same way a text or voice message does.

    `call_status` is one of "completed" (the call connected), "missed" (never
    answered), "declined" (listener rejected it), or "cancelled" (the caller
    hung up before it was answered). The caller (the user) is always
    `sender_type`, since only users initiate calls in this app.
    """
    preview = CALL_LOG_PREVIEWS.get((call_type, call_status), "📞 Call")
    msg = ChatMessage(
        user_id=user_id,
        listener_id=listener_id,
        sender_type="user",
        message=preview,
        message_type="call",
        call_id=call_id,
        call_type=call_type,
        call_status=call_status,
        call_duration_seconds=duration_seconds,
        status="delivered",
        delivered_at=datetime.now(timezone.utc),
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)
    payload = _msg_dict(msg)
    await manager.send_to_user(user_id, payload)
    await manager.send_to_listener(listener_id, payload)
    return msg

@router.post("/user/send", response_model=ChatMessageOut)
async def user_send_message(payload: ChatMessageSend, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if len(payload.message) > 100:
        raise HTTPException(status_code=400, detail="Message too long, only 100 characters allowed")
    listener = db.query(Listener).filter(Listener.id == payload.listener_id, Listener.is_active == True).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    _require_chat_coins(db, current_user)
    if payload.client_id:
        existing = db.query(ChatMessage).filter(
            ChatMessage.client_id == payload.client_id,
            ChatMessage.user_id == current_user.id,
            ChatMessage.listener_id == listener.id,
            ChatMessage.sender_type == "user",
        ).first()
        if existing:
            return existing
    listener_online = manager.is_listener_online(listener.id)
    msg = ChatMessage(
        client_id=payload.client_id,
        user_id=current_user.id,
        listener_id=listener.id,
        sender_type="user",
        message=payload.message,
        status="delivered" if listener_online else "sent",
        delivered_at=datetime.now(timezone.utc) if listener_online else None,
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)
    await deduct_chat_coins(db, current_user, listener.id, msg.id)
    await manager.send_to_listener(listener.id, _msg_dict(msg))

    await manager.send_to_user(current_user.id, {"type": "message_status", "id": msg.id, "client_id": msg.client_id, "status": msg.status})
    if listener.fcm_token and not _is_muted(db, "listener", listener.id, current_user.id):
        try:
            if listener_online:
                send_async(send_chat_message, listener.fcm_token, current_user.name, payload.message, current_user.id, listener.id, "user", msg.id, msg.client_id, current_user.photo_url)
            else:
                payload_msgs = _undelivered_summary_payload(db, current_user.id, listener.id, "user")
                send_async(send_chat_summary, listener.fcm_token, current_user.name, payload_msgs, current_user.id, listener.id, "user", current_user.photo_url)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify listener {listener.id} of chat message: {e}")
    return msg

@router.post("/listener/send", response_model=ChatMessageOut)
async def listener_send_message(payload: ListenerChatMessageSend, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    user = db.query(User).filter(User.id == payload.user_id, User.is_active == True).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if payload.client_id:
        existing = db.query(ChatMessage).filter(
            ChatMessage.client_id == payload.client_id,
            ChatMessage.user_id == user.id,
            ChatMessage.listener_id == current_listener.id,
            ChatMessage.sender_type == "listener",
        ).first()
        if existing:
            return existing
    user_online = manager.is_user_online(user.id)
    msg = ChatMessage(
        client_id=payload.client_id,
        user_id=user.id,
        listener_id=current_listener.id,
        sender_type="listener",
        message=payload.message,
        status="delivered" if user_online else "sent",
        delivered_at=datetime.now(timezone.utc) if user_online else None,
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)
    await manager.send_to_user(user.id, _msg_dict(msg))
    await manager.send_to_listener(current_listener.id, {"type": "message_status", "id": msg.id, "client_id": msg.client_id, "status": msg.status})
    if user.fcm_token and not _is_muted(db, "user", user.id, current_listener.id):
        try:
            if user_online:
                send_async(send_chat_message, user.fcm_token, current_listener.name, payload.message, user.id, current_listener.id, "listener", msg.id, msg.client_id, current_listener.photo_url)
            else:
                payload_msgs = _undelivered_summary_payload(db, user.id, current_listener.id, "listener")
                send_async(send_chat_summary, user.fcm_token, current_listener.name, payload_msgs, user.id, current_listener.id, "listener", current_listener.photo_url)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify user {user.id} of chat message: {e}")
    _web_push(db, user.id, current_listener.name, payload.message, current_listener.id, msg.id, current_listener.photo_url)
    return msg

@router.post("/user/send-voice", response_model=ChatMessageOut)
async def user_send_voice(
    listener_id: int = Form(...),
    client_id: str = Form(None),
    duration: int = Form(0),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    listener = db.query(Listener).filter(Listener.id == listener_id, Listener.is_active == True).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    _require_voice_coins(db, current_user)
    filename = await _save_voice_upload(file)
    listener_online = manager.is_listener_online(listener.id)
    msg = ChatMessage(
        client_id=client_id,
        user_id=current_user.id,
        listener_id=listener.id,
        sender_type="user",
        message="",
        message_type="audio",
        audio_url=sign_media_url("voice_notes", filename, VOICE_NOTE_URL_TTL_SECONDS),
        audio_duration=duration,
        status="delivered" if listener_online else "sent",
        delivered_at=datetime.now(timezone.utc) if listener_online else None,
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)
    await deduct_voice_message_coins(db, current_user, listener.id, msg.id)
    await manager.send_to_listener(listener.id, _msg_dict(msg))
    await manager.send_to_user(current_user.id, {"type": "message_status", "id": msg.id, "client_id": msg.client_id, "status": msg.status})
    if listener.fcm_token and not _is_muted(db, "listener", listener.id, current_user.id):
        try:
            send_async(send_chat_message, listener.fcm_token, current_user.name, "🎤 Voice message", current_user.id, listener.id, "user", msg.id, msg.client_id, current_user.photo_url)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify listener {listener.id} of voice message: {e}")
    return msg

@router.post("/listener/send-voice", response_model=ChatMessageOut)
async def listener_send_voice(
    user_id: int = Form(...),
    client_id: str = Form(None),
    duration: int = Form(0),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_listener: Listener = Depends(get_current_listener),
):
    user = db.query(User).filter(User.id == user_id, User.is_active == True).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    filename = await _save_voice_upload(file)
    user_online = manager.is_user_online(user.id)
    msg = ChatMessage(
        client_id=client_id,
        user_id=user.id,
        listener_id=current_listener.id,
        sender_type="listener",
        message="",
        message_type="audio",
        audio_url=sign_media_url("voice_notes", filename, VOICE_NOTE_URL_TTL_SECONDS),
        audio_duration=duration,
        status="delivered" if user_online else "sent",
        delivered_at=datetime.now(timezone.utc) if user_online else None,
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)
    await manager.send_to_user(user.id, _msg_dict(msg))
    await manager.send_to_listener(current_listener.id, {"type": "message_status", "id": msg.id, "client_id": msg.client_id, "status": msg.status})
    if user.fcm_token and not _is_muted(db, "user", user.id, current_listener.id):
        try:
            send_async(send_chat_message, user.fcm_token, current_listener.name, "🎤 Voice message", user.id, current_listener.id, "listener", msg.id, msg.client_id, current_listener.photo_url)
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify user {user.id} of voice message: {e}")
    _web_push(db, user.id, current_listener.name, "🎤 Voice message", current_listener.id, msg.id, current_listener.photo_url)
    return msg

@router.get("/user/{listener_id}/messages", response_model=list[ChatMessageOut])
async def user_get_messages(listener_id: int, before_id: int | None = None, limit: int = 25, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    limit = max(1, min(limit, 100))
    query = db.query(ChatMessage).filter(
        ChatMessage.user_id == current_user.id,
        ChatMessage.listener_id == listener_id,
    )
    if before_id is not None:
        query = query.filter(ChatMessage.id < before_id)
    messages = query.order_by(ChatMessage.id.desc()).limit(limit).all()
    messages.reverse()
    unread = db.query(ChatMessage).filter(
        ChatMessage.user_id == current_user.id,
        ChatMessage.listener_id == listener_id,
        ChatMessage.sender_type == "listener",
        ChatMessage.is_read == False,
    ).all()
    now = datetime.now(timezone.utc)
    for m in unread:
        m.is_read = True
        m.status = "read"
        m.read_at = now
    db.commit()
    if unread:
        await manager.send_to_listener(listener_id, {
            "type": "read_receipt", "user_id": current_user.id, "listener_id": listener_id,
            "message_ids": [m.id for m in unread],
            "client_ids": [m.client_id for m in unread if m.client_id],
            "read_at": now.isoformat(),
        })
    return messages

@router.get("/listener/{user_id}/messages", response_model=list[ChatMessageOut])
async def listener_get_messages(user_id: int, before_id: int | None = None, limit: int = 25, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    limit = max(1, min(limit, 100))
    query = db.query(ChatMessage).filter(
        ChatMessage.user_id == user_id,
        ChatMessage.listener_id == current_listener.id,
    )
    if before_id is not None:
        query = query.filter(ChatMessage.id < before_id)
    messages = query.order_by(ChatMessage.id.desc()).limit(limit).all()
    messages.reverse()
    unread = db.query(ChatMessage).filter(
        ChatMessage.user_id == user_id,
        ChatMessage.listener_id == current_listener.id,
        ChatMessage.sender_type == "user",
        ChatMessage.is_read == False,
    ).all()
    if not current_listener.is_online:
        unread = []
    now = datetime.now(timezone.utc)
    for m in unread:
        m.is_read = True
        m.status = "read"
        m.read_at = now
    db.commit()
    if unread:
        await manager.send_to_user(user_id, {
            "type": "read_receipt", "user_id": user_id, "listener_id": current_listener.id,
            "message_ids": [m.id for m in unread],
            "client_ids": [m.client_id for m in unread if m.client_id],
            "read_at": now.isoformat(),
        })
    return messages

class DeliveredAck(BaseModel):
    message_ids: list[int]

@router.post("/user/delivered")
async def user_mark_delivered(payload: DeliveredAck, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    msgs = db.query(ChatMessage).filter(
        ChatMessage.id.in_(payload.message_ids),
        ChatMessage.user_id == current_user.id,
        ChatMessage.sender_type == "listener",
        ChatMessage.status == "sent",
    ).all()
    now = datetime.now(timezone.utc)
    for m in msgs:
        m.status = "delivered"
        m.delivered_at = now
    db.commit()
    if msgs:
        listener_id = msgs[0].listener_id
        ids = [m.id for m in msgs]
        if manager.is_listener_online(listener_id):
            await manager.send_to_listener(listener_id, {
                "type": "message_status_bulk",
                "ids": ids,
                "client_ids": [m.client_id for m in msgs if m.client_id],
                "status": "delivered",
            })
        else:
            listener = db.query(Listener).filter(Listener.id == listener_id).first()
            if listener and listener.fcm_token:
                send_async(send_delivery_status, listener.fcm_token, ids, "delivered", current_user.id, listener_id)
    return {"updated": len(msgs)}

@router.post("/listener/delivered")
async def listener_mark_delivered(payload: DeliveredAck, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    msgs = db.query(ChatMessage).filter(
        ChatMessage.id.in_(payload.message_ids),
        ChatMessage.listener_id == current_listener.id,
        ChatMessage.sender_type == "user",
        ChatMessage.status == "sent",
    ).all()
    now = datetime.now(timezone.utc)
    for m in msgs:
        m.status = "delivered"
        m.delivered_at = now
    db.commit()
    if msgs:
        user_id = msgs[0].user_id
        ids = [m.id for m in msgs]
        if manager.is_user_online(user_id):
            await manager.send_to_user(user_id, {
                "type": "message_status_bulk",
                "ids": ids,
                "client_ids": [m.client_id for m in msgs if m.client_id],
                "status": "delivered",
            })
        else:
            user = db.query(User).filter(User.id == user_id).first()
            if user and user.fcm_token:
                send_async(send_delivery_status, user.fcm_token, ids, "delivered", user_id, current_listener.id)
    return {"updated": len(msgs)}



@router.post("/message/edit", response_model=ChatMessageOut)
async def edit_message(payload: MessageEdit, db: Session = Depends(get_db), current=Depends(get_current_participant)):
    msg = db.query(ChatMessage).filter(ChatMessage.id == payload.message_id).first()
    if not msg:
        raise HTTPException(status_code=404, detail="Message not found")
    is_owner = (
        (isinstance(current, User) and msg.sender_type == "user" and msg.user_id == current.id) or
        (isinstance(current, Listener) and msg.sender_type == "listener" and msg.listener_id == current.id)
    )
    if not is_owner:
        raise HTTPException(status_code=403, detail="Not allowed to edit this message")
    msg.message = payload.message
    msg.edited_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(msg)
    payload_dict = {**_msg_dict(msg), "type": "message_edited"}
    await manager.send_to_user(msg.user_id, payload_dict)
    await manager.send_to_listener(msg.listener_id, payload_dict)
    return msg


@router.post("/user/{listener_id}/mark_read")
async def user_mark_read(listener_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    unread = db.query(ChatMessage).filter(
        ChatMessage.user_id == current_user.id,
        ChatMessage.listener_id == listener_id,
        ChatMessage.sender_type == "listener",
        ChatMessage.is_read == False,
    ).all()
    now = datetime.now(timezone.utc)
    for m in unread:
        m.is_read = True
        m.status = "read"
        m.read_at = now
    db.commit()
    if unread:
        await manager.send_to_listener(listener_id, {
            "type": "read_receipt", "user_id": current_user.id, "listener_id": listener_id,
            "message_ids": [m.id for m in unread],
            "client_ids": [m.client_id for m in unread if m.client_id],
            "read_at": now.isoformat(),
        })
    return {"marked": len(unread)}

@router.post("/listener/{user_id}/mark_read")
async def listener_mark_read(user_id: int, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    unread = db.query(ChatMessage).filter(
        ChatMessage.user_id == user_id,
        ChatMessage.listener_id == current_listener.id,
        ChatMessage.sender_type == "user",
        ChatMessage.is_read == False,
    ).all()
    if not current_listener.is_online:
        unread = []
    now = datetime.now(timezone.utc)
    for m in unread:
        m.is_read = True
        m.status = "read"
        m.read_at = now
    db.commit()
    if unread:
        await manager.send_to_user(user_id, {
            "type": "read_receipt", "user_id": user_id, "listener_id": current_listener.id,
            "message_ids": [m.id for m in unread],
            "client_ids": [m.client_id for m in unread if m.client_id],
            "read_at": now.isoformat(),
        })
    return {"marked": len(unread)}

@router.delete("/message/{message_id}")
async def delete_message(message_id: int, db: Session = Depends(get_db), current=Depends(get_current_participant)):
    msg = db.query(ChatMessage).filter(ChatMessage.id == message_id).first()
    if not msg:
        raise HTTPException(status_code=404, detail="Message not found")
    is_owner = (
        (isinstance(current, User) and msg.sender_type == "user" and msg.user_id == current.id) or
        (isinstance(current, Listener) and msg.sender_type == "listener" and msg.listener_id == current.id)
    )
    if not is_owner:
        raise HTTPException(status_code=403, detail="Not allowed to delete this message")
    msg.is_deleted = True
    msg.message = ""
    db.commit()
    data = {"type": "message_deleted", "id": msg.id, "user_id": msg.user_id, "listener_id": msg.listener_id}
    await manager.send_to_user(msg.user_id, data)
    await manager.send_to_listener(msg.listener_id, data)
    return {"status": "deleted"}


@router.post("/settings")
def update_chat_settings(payload: ChatSettingsUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    settings = _get_settings(db, "user", current_user.id, payload.other_id)
    if not settings:
        settings = ChatSettings(owner_type="user", owner_id=current_user.id, other_id=payload.other_id)
        db.add(settings)
    if payload.is_pinned is not None:
        settings.is_pinned = payload.is_pinned
    if payload.is_archived is not None:
        settings.is_archived = payload.is_archived
    if payload.is_muted is not None:
        settings.is_muted = payload.is_muted
    db.commit()
    return {"status": "ok"}

@router.post("/listener/settings")
def update_listener_chat_settings(payload: ChatSettingsUpdate, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    settings = _get_settings(db, "listener", current_listener.id, payload.other_id)
    if not settings:
        settings = ChatSettings(owner_type="listener", owner_id=current_listener.id, other_id=payload.other_id)
        db.add(settings)
    if payload.is_pinned is not None:
        settings.is_pinned = payload.is_pinned
    if payload.is_archived is not None:
        settings.is_archived = payload.is_archived
    if payload.is_muted is not None:
        settings.is_muted = payload.is_muted
    db.commit()
    return {"status": "ok"}

def _thread_preview(msg: ChatMessage) -> str:
    """Text shown in the chats list for a thread's last message. `message` is
    blank for voice notes and empty gifts/calls store their own preview
    text, so this fills in a readable stand-in instead of a blank line."""
    if msg.message_type == "audio":
        return "🎤 Voice message"
    if msg.message_type == "gift":
        return f"🎁 {msg.gift_name}" if msg.gift_name else "🎁 Gift"
    if msg.message and msg.message.strip():
        return msg.message
    return msg.message


@router.get("/user/threads", response_model=list[ChatThreadOut])
def user_get_threads(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    listener_ids = [r[0] for r in db.query(ChatMessage.listener_id).filter(ChatMessage.user_id == current_user.id).distinct().all()]
    if not listener_ids:
        return []

    listeners = {l.id: l for l in db.query(Listener).filter(Listener.id.in_(listener_ids), Listener.is_active == True).all()}

    last_ids = [r[0] for r in db.query(func.max(ChatMessage.id)).filter(
        ChatMessage.user_id == current_user.id,
        ChatMessage.listener_id.in_(listener_ids),
    ).group_by(ChatMessage.listener_id).all()]
    last_msg_by_listener = {
        m.listener_id: m
        for m in db.query(ChatMessage).filter(ChatMessage.id.in_(last_ids)).all()
    } if last_ids else {}

    unread_rows = db.query(
        ChatMessage.listener_id, func.count(ChatMessage.id)
    ).filter(
        ChatMessage.user_id == current_user.id,
        ChatMessage.listener_id.in_(listener_ids),
        ChatMessage.sender_type == "listener",
        ChatMessage.is_read == False,
    ).group_by(ChatMessage.listener_id).all()
    unread_by_listener = dict(unread_rows)

    settings_rows = db.query(ChatSettings).filter(
        ChatSettings.owner_type == "user",
        ChatSettings.owner_id == current_user.id,
        ChatSettings.other_id.in_(listener_ids),
    ).all()
    settings_by_listener = {s.other_id: s for s in settings_rows}

    badge_tag_ids = {l.badge_tag_id for l in listeners.values() if l.badge_tag_id}
    badge_tags_by_id = {}
    if badge_tag_ids:
        for t in db.query(ListenerBadgeTag).filter(ListenerBadgeTag.id.in_(badge_tag_ids)).all():
            badge_tags_by_id[t.id] = {"id": t.id, "name": t.name, "color": t.color}
    result = []
    for lid in listener_ids:
        listener = listeners.get(lid)
        last = last_msg_by_listener.get(lid)
        if not listener or not last:
            continue
        settings = settings_by_listener.get(lid)
        result.append(ChatThreadOut(
            user_id=current_user.id, user_name=current_user.name, listener_id=lid, listener_name=listener.name,
            last_message=_thread_preview(last), last_message_at=last.created_at,
            last_message_type=last.message_type or "text",
            last_call_type=last.call_type, last_call_status=last.call_status,
            last_call_duration_seconds=last.call_duration_seconds,
            unread_count=unread_by_listener.get(lid, 0),
            is_pinned=settings.is_pinned if settings else False,
            is_archived=settings.is_archived if settings else False,
            is_muted=settings.is_muted if settings else False,
            is_online=listener.effective_online,
            presence_online=listener.effective_online,
            last_seen=listener.last_seen,
            photo_url=listener.photo_url,
            badge_tag=badge_tags_by_id.get(listener.badge_tag_id),
        ))
    result.sort(key=lambda t: t.last_message_at, reverse=True)
    result.sort(key=lambda t: t.is_pinned, reverse=True)
    return result

@router.get("/listener/threads", response_model=list[ChatThreadOut])
def listener_get_threads(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    user_ids = [r[0] for r in db.query(ChatMessage.user_id).filter(ChatMessage.listener_id == current_listener.id).distinct().all()]
    if not user_ids:
        return []

    users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids), User.is_active == True).all()}

    last_ids = [r[0] for r in db.query(func.max(ChatMessage.id)).filter(
        ChatMessage.listener_id == current_listener.id,
        ChatMessage.user_id.in_(user_ids),
    ).group_by(ChatMessage.user_id).all()]
    last_msg_by_user = {
        m.user_id: m
        for m in db.query(ChatMessage).filter(ChatMessage.id.in_(last_ids)).all()
    } if last_ids else {}

    unread_rows = db.query(
        ChatMessage.user_id, func.count(ChatMessage.id)
    ).filter(
        ChatMessage.listener_id == current_listener.id,
        ChatMessage.user_id.in_(user_ids),
        ChatMessage.sender_type == "user",
        ChatMessage.is_read == False,
    ).group_by(ChatMessage.user_id).all()
    unread_by_user = dict(unread_rows)

    settings_rows = db.query(ChatSettings).filter(
        ChatSettings.owner_type == "listener",
        ChatSettings.owner_id == current_listener.id,
        ChatSettings.other_id.in_(user_ids),
    ).all()
    settings_by_user = {s.other_id: s for s in settings_rows}

    result = []
    for uid in user_ids:
        user = users.get(uid)
        last = last_msg_by_user.get(uid)
        if not user or not last:
            continue
        settings = settings_by_user.get(uid)
        result.append(ChatThreadOut(
            user_id=uid, user_name=user.name, listener_id=current_listener.id, listener_name=current_listener.name,
            last_message=_thread_preview(last), last_message_at=last.created_at,
            last_message_type=last.message_type or "text",
            last_call_type=last.call_type, last_call_status=last.call_status,
            last_call_duration_seconds=last.call_duration_seconds,
            unread_count=unread_by_user.get(uid, 0),
            is_pinned=settings.is_pinned if settings else False,
            is_archived=settings.is_archived if settings else False,
            is_muted=settings.is_muted if settings else False,
            is_online=manager.is_user_online(uid),
            last_seen=user.last_seen,
            photo_url=user.photo_url,
        ))
    result.sort(key=lambda t: t.last_message_at, reverse=True)
    result.sort(key=lambda t: t.is_pinned, reverse=True)
    return result
    
def _authenticate_user_ws(token: str) -> tuple[int | None, int, str | None]:
    db = SessionLocal()
    try:
        session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.user_id.isnot(None)).first()
        if not session:
            return None, 4001, None
        if session.expires_at and session.expires_at < datetime.now(timezone.utc):
            db.delete(session)
            db.commit()
            return None, 4001, None
        user = db.query(User).filter(User.id == session.user_id).first()
        if not user or not user.is_active:
            db.delete(session)
            db.commit()
            return None, 4003, "deactivated"
        return user.id, 0, None
    finally:
        db.close()


def _set_user_online_flag(user_id: int, is_online: bool) -> None:
    db = SessionLocal()
    try:
        db.query(User).filter(User.id == user_id, User.is_online != is_online).update(
            {User.is_online: is_online}, synchronize_session=False
        )
        db.commit()
    finally:
        db.close()


@router.websocket("/ws/user")
async def user_chat_ws(websocket: WebSocket, token: str = Query(...)):
    user_id, close_code, close_reason = await run_in_threadpool(_authenticate_user_ws, token)
    if user_id is None:
        if close_reason:
            await websocket.close(code=close_code, reason=close_reason)
        else:
            await websocket.close(code=close_code)
        return
    await manager.connect_user(user_id, websocket, token)
    logger.info(f"WebSocket user={user_id} connected -> online")
    await manager.broadcast_to_admins({"type": "user_status", "id": user_id, "is_online": True})
    await run_in_threadpool(_set_user_online_flag, user_id, True)
    await manager.broadcast_to_all_listeners({"type": "user_online", "user_id": user_id})
    typing_targets: set[int] = set()

    reason = await _run_ws_loop(websocket, lambda raw: _handle_user_ws_event(raw, user_id, typing_targets))

    for target_listener_id in typing_targets:
        await manager.send_to_listener(target_listener_id, {"type": "typing", "user_id": user_id, "is_typing": False})
    typing_targets.clear()
    await manager.disconnect_user(user_id, websocket)
    asyncio.create_task(_finalize_active_calls_for_user_after_grace(user_id))
    if manager.is_user_online(user_id):
        logger.info(f"WebSocket user={user_id} disconnected: {reason} (another connection is still open, stays online)")
        return

    logger.info(f"WebSocket user={user_id} disconnected: {reason} -> offline")
    await manager.broadcast_to_admins({"type": "user_status", "id": user_id, "is_online": False})
    await run_in_threadpool(_set_user_online_flag, user_id, False)
    await manager.broadcast_to_all_listeners({"type": "user_offline", "user_id": user_id})

async def _handle_user_ws_event(raw: dict, user_id: int, typing_targets: set | None = None):
    etype = raw.get("type")
    if etype == "typing":
        listener_id = raw.get("listener_id")
        if listener_id is None:
            return
        is_typing = bool(raw.get("is_typing", False))
        if typing_targets is not None:
            if is_typing:
                typing_targets.add(listener_id)
            else:
                typing_targets.discard(listener_id)
        await manager.send_to_listener(listener_id, {"type": "typing", "user_id": user_id, "is_typing": is_typing})
    elif etype == "ping":
        pass

def _authenticate_listener_ws(token: str) -> tuple[int | None, int]:
    db = SessionLocal()
    try:
        session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.listener_id.isnot(None)).first()
        if not session:
            return None, 4001
        if session.expires_at and session.expires_at < datetime.now(timezone.utc):
            db.delete(session)
            db.commit()
            return None, 4001
        listener = db.query(Listener).filter(Listener.id == session.listener_id).first()
        if not listener or not listener.is_active:
            return None, 4003
        return listener.id, 0
    finally:
        db.close()


def _load_listener_ws_state(listener_id: int) -> tuple[bool, bool, list[int], list[dict]]:
    db = SessionLocal()
    try:
        listener = db.query(Listener).filter(Listener.id == listener_id).first()
        availability_on = bool(listener and listener.is_online)
        admin_forced = bool(listener and listener.admin_forced_offline)
        user_ids = [r[0] for r in db.query(ChatMessage.user_id).filter(ChatMessage.listener_id == listener_id).distinct().all()]
        pending = db.query(GiftTransaction).filter(
            GiftTransaction.listener_id == listener_id,
            GiftTransaction.notified == False,
        ).order_by(GiftTransaction.created_at.asc()).all()
        gift_events: list[dict] = []
        if pending:
            gift_names = {g.id: g.name for g in db.query(Gift.id, Gift.name).filter(Gift.id.in_({gt.gift_id for gt in pending})).all()}
            sender_names = {u.id: u.name for u in db.query(User.id, User.name).filter(User.id.in_({gt.user_id for gt in pending})).all()}
            for gt in pending:
                gift_events.append({
                    "type": "gift_received",
                    "gift_name": gift_names.get(gt.gift_id, ""),
                    "coins": gt.coins,
                    "credited_coins": gt.coins // 2,
                    "from_user_id": gt.user_id,
                    "from_user_name": sender_names.get(gt.user_id, ""),
                })
                gt.notified = True
            db.commit()
        return availability_on, admin_forced, user_ids, gift_events
    finally:
        db.close()


def _stamp_listener_last_seen(listener_id: int) -> bool:
    db = SessionLocal()
    try:
        listener = db.query(Listener).filter(Listener.id == listener_id).first()
        if not listener:
            return False
        listener.last_seen = datetime.now(timezone.utc)
        db.commit()
        return bool(listener.is_online)
    finally:
        db.close()


@router.websocket("/ws/listener")
async def listener_chat_ws(websocket: WebSocket, token: str = Query(...)):
    listener_id, close_code = await run_in_threadpool(_authenticate_listener_ws, token)
    if listener_id is None:
        await websocket.close(code=close_code)
        return
    was_live = manager.is_listener_online(listener_id)
    await manager.connect_listener(listener_id, websocket)
    if not was_live:
        from app.utils.listener_presence import broadcast_listener_live
        asyncio.create_task(broadcast_listener_live(listener_id, True))
    availability_on, admin_forced, user_ids, gift_events = await run_in_threadpool(_load_listener_ws_state, listener_id)
    logger.info(f"WebSocket listener={listener_id} connected (availability switch is_online={availability_on})")
    await manager.send_to_listener(listener_id, {"type": "listener_status_changed", "is_online": availability_on, "admin_forced_offline": admin_forced})
    for event in gift_events:
        await manager.send_to_listener(listener_id, event)
    typing_targets: set[int] = set()

    reason = await _run_ws_loop(websocket, lambda raw: _handle_listener_ws_event(raw, listener_id, typing_targets))

    for target_user_id in typing_targets:
        await manager.send_to_user(target_user_id, {"type": "typing", "listener_id": listener_id, "is_typing": False})
    typing_targets.clear()
    await manager.disconnect_listener(listener_id, websocket)
    asyncio.create_task(_finalize_active_calls_for_listener_after_grace(listener_id))
    if manager.is_listener_online(listener_id):
        logger.info(f"WebSocket listener={listener_id} disconnected: {reason} (another connection is still open, stays online)")
        return
    from app.utils.listener_presence import broadcast_listener_live
    asyncio.create_task(broadcast_listener_live(listener_id, False))

    logger.info(f"WebSocket listener={listener_id} disconnected: {reason} (presence unchanged, it is not socket-based)")
    await run_in_threadpool(_stamp_listener_last_seen, listener_id)


async def _handle_listener_ws_event(raw: dict, listener_id: int, typing_targets: set | None = None):
    etype = raw.get("type")
    if etype == "typing":
        user_id = raw.get("user_id")
        if user_id is None:
            return
        is_typing = bool(raw.get("is_typing", False))
        if typing_targets is not None:
            if is_typing:
                typing_targets.add(user_id)
            else:
                typing_targets.discard(user_id)
        await manager.send_to_user(user_id, {"type": "typing", "listener_id": listener_id, "is_typing": is_typing})
    elif etype == "ping":
        pass
