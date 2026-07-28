#chat.py
import asyncio
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, Query, UploadFile, File, Form
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel
import os
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import func, and_, or_
from app.core.database import get_db
from app.core.deps import get_current_user, get_current_listener, get_current_participant
from app.models.models import ChatMessage, User, Listener, Session as SessionModel, ChatSettings, GiftTransaction, Gift, Call
from app.schemas.schemas import ChatMessageSend, ListenerChatMessageSend, ChatMessageOut, ChatThreadOut, TypingEvent, MessageEdit, ChatSettingsUpdate
from app.utils.fcm import send_chat_message, send_delivery_status, send_chat_summary
from app.utils.coins import chat_message_coin_cost, deduct_chat_coins, voice_message_coin_cost, deduct_voice_message_coins
from app.core.ws_manager import manager

ACTIVE_CALL_STATUSES = ("ringing", "accepted")

VOICE_NOTES_DIR = "voice_notes"
ALLOWED_VOICE_EXTENSIONS = {".m4a", ".aac", ".mp3", ".wav", ".ogg", ".opus", ".webm"}
ALLOWED_VOICE_CONTENT_TYPES = {
    "audio/mp4", "audio/m4a", "audio/aac", "audio/mpeg", "audio/mp3",
    "audio/wav", "audio/x-wav", "audio/ogg", "audio/opus", "audio/webm",
}
MAX_VOICE_NOTE_BYTES = 10 * 1024 * 1024  # 10 MB


def _validate_voice_upload(file: UploadFile) -> str:
    """Validates a voice-note upload's extension/content-type and returns a
    safe extension to use for the stored filename. Raises HTTPException on
    anything that doesn't look like an audio file."""
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in ALLOWED_VOICE_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Unsupported voice note file type")
    if file.content_type and file.content_type not in ALLOWED_VOICE_CONTENT_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported voice note content type")
    return ext


def _write_voice_file_sync(filepath: str, data: bytes) -> None:
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "wb") as f:
        f.write(data)


async def _save_voice_upload(file: UploadFile) -> str:
    """Validates, reads (with a size cap), and writes a voice-note upload off
    the event loop. Returns the filename (not the full path) to store."""
    ext = _validate_voice_upload(file)
    data = await file.read(MAX_VOICE_NOTE_BYTES + 1)
    if len(data) > MAX_VOICE_NOTE_BYTES:
        raise HTTPException(status_code=413, detail="Voice note exceeds maximum allowed size")
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(VOICE_NOTES_DIR, filename)
    await run_in_threadpool(_write_voice_file_sync, filepath, data)
    return filename

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

@router.post("/user/send", response_model=ChatMessageOut)
async def user_send_message(payload: ChatMessageSend, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if len(payload.message) > 100:
        raise HTTPException(status_code=400, detail="Message too long, only 100 characters allowed")
    listener = db.query(Listener).filter(Listener.id == payload.listener_id, Listener.is_active == True).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    _require_chat_coins(db, current_user)
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
    if listener.fcm_token:
        try:
            if listener_online:
                send_chat_message(listener.fcm_token, current_user.name, payload.message, current_user.id, listener.id, "user", msg.id, msg.client_id)
            else:
                payload_msgs = _undelivered_summary_payload(db, current_user.id, listener.id, "user")
                send_chat_summary(listener.fcm_token, current_user.name, payload_msgs, current_user.id, listener.id, "user")
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify listener {listener.id} of chat message: {e}")
    return msg

@router.post("/listener/send", response_model=ChatMessageOut)
async def listener_send_message(payload: ListenerChatMessageSend, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    user = db.query(User).filter(User.id == payload.user_id, User.is_active == True).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
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
    if user.fcm_token:
        try:
            if user_online:
                send_chat_message(user.fcm_token, current_listener.name, payload.message, user.id, current_listener.id, "listener", msg.id, msg.client_id)
            else:
                payload_msgs = _undelivered_summary_payload(db, user.id, current_listener.id, "listener")
                send_chat_summary(user.fcm_token, current_listener.name, payload_msgs, user.id, current_listener.id, "listener")
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify user {user.id} of chat message: {e}")
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
        audio_url=f"/voice_notes/{filename}",
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
    if listener.fcm_token:
        try:
            send_chat_message(listener.fcm_token, current_user.name, "🎤 Voice message", current_user.id, listener.id, "user")
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
        audio_url=f"/voice_notes/{filename}",
        audio_duration=duration,
        status="delivered" if user_online else "sent",
        delivered_at=datetime.now(timezone.utc) if user_online else None,
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)
    await manager.send_to_user(user.id, _msg_dict(msg))
    await manager.send_to_listener(current_listener.id, {"type": "message_status", "id": msg.id, "client_id": msg.client_id, "status": msg.status})
    if user.fcm_token:
        try:
            send_chat_message(user.fcm_token, current_listener.name, "🎤 Voice message", user.id, current_listener.id, "listener")
        except Exception as e:
            print(f"[FCM ERROR] Failed to notify user {user.id} of voice message: {e}")
    return msg

@router.get("/user/{listener_id}/messages", response_model=list[ChatMessageOut])
async def user_get_messages(listener_id: int, before_id: int | None = None, limit: int = 25, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
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
            "message_ids": [m.id for m in unread], "read_at": now.isoformat(),
        })
    return messages

@router.get("/listener/{user_id}/messages", response_model=list[ChatMessageOut])
async def listener_get_messages(user_id: int, before_id: int | None = None, limit: int = 25, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
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
    now = datetime.now(timezone.utc)
    for m in unread:
        m.is_read = True
        m.status = "read"
        m.read_at = now
    db.commit()
    if unread:
        await manager.send_to_user(user_id, {
            "type": "read_receipt", "user_id": user_id, "listener_id": current_listener.id,
            "message_ids": [m.id for m in unread], "read_at": now.isoformat(),
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
                "status": "delivered",
            })
        else:
            listener = db.query(Listener).filter(Listener.id == listener_id).first()
            if listener and listener.fcm_token:
                try:
                    send_delivery_status(listener.fcm_token, ids, "delivered", current_user.id, listener_id)
                except Exception as e:
                    print(f"[FCM ERROR] Failed to notify listener {listener_id} of delivery status: {e}")
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
                "status": "delivered",
            })
        else:
            user = db.query(User).filter(User.id == user_id).first()
            if user and user.fcm_token:
                try:
                    send_delivery_status(user.fcm_token, ids, "delivered", user_id, current_listener.id)
                except Exception as e:
                    print(f"[FCM ERROR] Failed to notify user {user_id} of delivery status: {e}")
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
            "message_ids": [m.id for m in unread], "read_at": now.isoformat(),
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
    now = datetime.now(timezone.utc)
    for m in unread:
        m.is_read = True
        m.status = "read"
        m.read_at = now
    db.commit()
    if unread:
        await manager.send_to_user(user_id, {
            "type": "read_receipt", "user_id": user_id, "listener_id": current_listener.id,
            "message_ids": [m.id for m in unread], "read_at": now.isoformat(),
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

@router.get("/user/threads", response_model=list[ChatThreadOut])
def user_get_threads(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    listener_ids = [r[0] for r in db.query(ChatMessage.listener_id).filter(ChatMessage.user_id == current_user.id).distinct().all()]
    if not listener_ids:
        return []

    listeners = {l.id: l for l in db.query(Listener).filter(Listener.id.in_(listener_ids)).all()}

    all_msgs = db.query(ChatMessage).filter(
        ChatMessage.user_id == current_user.id,
        ChatMessage.listener_id.in_(listener_ids),
    ).order_by(ChatMessage.created_at.asc()).all()
    last_msg_by_listener = {}
    for m in all_msgs:
        last_msg_by_listener[m.listener_id] = m

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

    result = []
    for lid in listener_ids:
        listener = listeners.get(lid)
        last = last_msg_by_listener.get(lid)
        if not listener or not last:
            continue
        settings = settings_by_listener.get(lid)
        result.append(ChatThreadOut(
            user_id=current_user.id, user_name=current_user.name, listener_id=lid, listener_name=listener.name,
            last_message=last.message, last_message_at=last.created_at, unread_count=unread_by_listener.get(lid, 0),
            is_pinned=settings.is_pinned if settings else False,
            is_archived=settings.is_archived if settings else False,
            is_muted=settings.is_muted if settings else False,
            is_online=bool(listener.is_online) and manager.is_listener_online(lid),
            last_seen=listener.last_seen,
            photo_url=listener.photo_url,
        ))
    result.sort(key=lambda t: (not t.is_pinned, t.last_message_at), reverse=False)
    result.sort(key=lambda t: t.is_pinned, reverse=True)
    return result

@router.get("/listener/threads", response_model=list[ChatThreadOut])
def listener_get_threads(db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    user_ids = [r[0] for r in db.query(ChatMessage.user_id).filter(ChatMessage.listener_id == current_listener.id).distinct().all()]
    if not user_ids:
        return []

    users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()}

    all_msgs = db.query(ChatMessage).filter(
        ChatMessage.listener_id == current_listener.id,
        ChatMessage.user_id.in_(user_ids),
    ).order_by(ChatMessage.created_at.asc()).all()
    last_msg_by_user = {}
    for m in all_msgs:
        last_msg_by_user[m.user_id] = m

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
            last_message=last.message, last_message_at=last.created_at, unread_count=unread_by_user.get(uid, 0),
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
    
@router.websocket("/ws/user")
async def user_chat_ws(websocket: WebSocket, token: str = Query(...), db: Session = Depends(get_db)):
    session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.user_id.isnot(None)).first()
    if not session:
        await websocket.close(code=4001)
        return
    if session.expires_at and session.expires_at < datetime.now(timezone.utc):
        db.delete(session)
        db.commit()
        await websocket.close(code=4001)
        return
    user_id = session.user_id
    user_check = db.query(User).filter(User.id == user_id).first()
    if not user_check or not user_check.is_active:
        db.delete(session)
        db.commit()
        await websocket.close(code=4003, reason="deactivated")
        return
    await manager.connect_user(user_id, websocket)
    await manager.broadcast_to_admins({"type": "user_status", "id": user_id, "is_online": True})
    user = db.query(User).filter(User.id == user_id).first()
    if user and not user.is_online:
        user.is_online = True
        db.commit()
    await manager.broadcast_to_all_listeners({"type": "user_online", "user_id": user_id})
    try:
        while True:
            try:
                raw = await asyncio.wait_for(websocket.receive_json(), timeout=15)
            except asyncio.TimeoutError:
                await websocket.send_json({"type": "ping"})
                continue
            await _handle_user_ws_event(raw, user_id, db)
    except Exception:
        await manager.disconnect_user(user_id, websocket)
        await _finalize_active_calls_for_user(user_id, db)
        if manager.is_user_online(user_id):
            return

        await manager.broadcast_to_admins({"type": "user_status", "id": user_id, "is_online": False})
        user = db.query(User).filter(User.id == user_id).first()
        if user:
            user.is_online = False
            db.commit()
        await manager.broadcast_to_all_listeners({"type": "user_offline", "user_id": user_id})

async def _handle_user_ws_event(raw: dict, user_id: int, db: Session):
    etype = raw.get("type")
    if etype == "typing":
        listener_id = raw.get("listener_id")
        await manager.send_to_listener(listener_id, {"type": "typing", "user_id": user_id, "is_typing": raw.get("is_typing", False)})
    elif etype == "ping":
        pass

@router.websocket("/ws/listener")
async def listener_chat_ws(websocket: WebSocket, token: str = Query(...), db: Session = Depends(get_db)):
    session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.listener_id.isnot(None)).first()
    if not session:
        await websocket.close(code=4001)
        return
    if session.expires_at and session.expires_at < datetime.now(timezone.utc):
        db.delete(session)
        db.commit()
        await websocket.close(code=4001)
        return
    listener_id = session.listener_id
    listener_check = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener_check or not listener_check.is_active:
        await websocket.close(code=4003)
        return
    await manager.connect_listener(listener_id, websocket)
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    await manager.broadcast_to_admins({"type": "listener_status", "id": listener_id, "is_online": bool(listener and listener.is_online)})
    user_ids = [r[0] for r in db.query(ChatMessage.user_id).filter(ChatMessage.listener_id == listener_id).distinct().all()]
    if listener and listener.is_online:
        for uid in manager.get_online_user_ids(user_ids):
            await manager.send_to_user(uid, {"type": "listener_online", "listener_id": listener_id})


    pending_gifts = db.query(GiftTransaction).filter(GiftTransaction.listener_id == listener_id, GiftTransaction.notified == False).order_by(GiftTransaction.created_at.asc()).all()
    for gt in pending_gifts:
        gift_row = db.query(Gift).filter(Gift.id == gt.gift_id).first()
        sender = db.query(User).filter(User.id == gt.user_id).first()
        await manager.send_to_listener(listener_id, {
            "type": "gift_received",
            "gift_name": gift_row.name if gift_row else "",
            "coins": gt.coins,
            "credited_coins": gt.coins // 2,
            "from_user_id": gt.user_id,
            "from_user_name": sender.name if sender else "",
        })
        gt.notified = True
    if pending_gifts:
        db.commit()
    try:
        while True:
            try:
                raw = await asyncio.wait_for(websocket.receive_json(), timeout=15)
            except asyncio.TimeoutError:
                await websocket.send_json({"type": "ping"})
                continue
            await _handle_listener_ws_event(raw, listener_id, db)
    except Exception:
        await manager.disconnect_listener(listener_id, websocket)
        await _finalize_active_calls_for_listener(listener_id, db)
        if manager.is_listener_online(listener_id):
            return

        await manager.broadcast_to_admins({"type": "listener_status", "id": listener_id, "is_online": False})
        listener = db.query(Listener).filter(Listener.id == listener_id).first()
        if listener:
            listener.is_online = False
            listener.last_seen = datetime.now(timezone.utc)
            db.commit()
        for uid in manager.get_online_user_ids(user_ids):
            await manager.send_to_user(uid, {"type": "listener_offline", "listener_id": listener_id})
        user_ids = [r[0] for r in db.query(ChatMessage.user_id).filter(ChatMessage.listener_id == listener_id).distinct().all()]
        for uid in user_ids:
            await manager.send_to_user(uid, {"type": "listener_offline", "listener_id": listener_id})



async def _handle_listener_ws_event(raw: dict, listener_id: int, db: Session):
    etype = raw.get("type")
    if etype == "typing":
        user_id = raw.get("user_id")
        await manager.send_to_user(user_id, {"type": "typing", "listener_id": listener_id, "is_typing": raw.get("is_typing", False)})
    elif etype == "ping":
        pass
