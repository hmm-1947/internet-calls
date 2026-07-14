#chat.py
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, Query, UploadFile, File, Form
import os
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import func, and_, or_
from app.core.database import get_db
from app.core.deps import get_current_user, get_current_listener
from app.models.models import ChatMessage, User, Listener, Session as SessionModel, ChatSettings
from app.schemas.schemas import ChatMessageSend, ListenerChatMessageSend, ChatMessageOut, ChatThreadOut, TypingEvent, MessageEdit, ChatSettingsUpdate
from app.utils.fcm import send_chat_message
from app.utils.coins import chat_message_coin_cost, deduct_chat_coins
from app.core.ws_manager import manager


router = APIRouter(prefix="/chat", tags=["chat"])


def _require_chat_coins(db: Session, user: User) -> None:
    """Reject a chat send before the message is persisted when funds are short."""
    cost = chat_message_coin_cost(db)
    if cost < 0:
        raise HTTPException(status_code=500, detail="Invalid chat coin setting")
    if user.coins < cost:
        raise HTTPException(status_code=402, detail="Not enough coins to send this message")

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
        "status": msg.status,
        "is_read": msg.is_read,
        "delivered_at": msg.delivered_at.isoformat() if msg.delivered_at else None,
        "read_at": msg.read_at.isoformat() if msg.read_at else None,
        "edited_at": msg.edited_at.isoformat() if msg.edited_at else None,
        "is_deleted": msg.is_deleted,
        "created_at": msg.created_at.isoformat(),
    }

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
            send_chat_message(listener.fcm_token, current_user.name, payload.message, current_user.id, listener.id, "user")
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
            send_chat_message(user.fcm_token, current_listener.name, payload.message, user.id, current_listener.id, "listener")
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
    _require_chat_coins(db, current_user)
    ext = os.path.splitext(file.filename)[1] or ".m4a"
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("voice_notes", filename)
    with open(filepath, "wb") as f:
        f.write(await file.read())
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
    await deduct_chat_coins(db, current_user, listener.id, msg.id)
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
    ext = os.path.splitext(file.filename)[1] or ".m4a"
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("voice_notes", filename)
    with open(filepath, "wb") as f:
        f.write(await file.read())
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
async def user_get_messages(listener_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    messages = db.query(ChatMessage).filter(
        ChatMessage.user_id == current_user.id,
        ChatMessage.listener_id == listener_id,
    ).order_by(ChatMessage.created_at.asc()).all()
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
async def listener_get_messages(user_id: int, db: Session = Depends(get_db), current_listener: Listener = Depends(get_current_listener)):
    messages = db.query(ChatMessage).filter(
        ChatMessage.user_id == user_id,
        ChatMessage.listener_id == current_listener.id,
    ).order_by(ChatMessage.created_at.asc()).all()
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

@router.post("/message/edit", response_model=ChatMessageOut)
async def edit_message(payload: MessageEdit, db: Session = Depends(get_db)):
    msg = db.query(ChatMessage).filter(ChatMessage.id == payload.message_id).first()
    if not msg:
        raise HTTPException(status_code=404, detail="Message not found")
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
async def delete_message(message_id: int, db: Session = Depends(get_db)):
    msg = db.query(ChatMessage).filter(ChatMessage.id == message_id).first()
    if not msg:
        raise HTTPException(status_code=404, detail="Message not found")
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
            is_online=manager.is_listener_online(lid),
            last_seen=listener.last_seen,
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
            raw = await websocket.receive_json()
            await _handle_user_ws_event(raw, user_id, db)
    except Exception:
        manager.disconnect_user(user_id, websocket)
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
    listener_id = session.listener_id
    listener_check = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener_check or not listener_check.is_active:
        await websocket.close(code=4003)
        return
    await manager.connect_listener(listener_id, websocket)
    await manager.broadcast_to_admins({"type": "listener_status", "id": listener_id, "is_online": True})
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if listener and not listener.is_online:
        listener.is_online = True
        db.commit()
    user_ids = [r[0] for r in db.query(ChatMessage.user_id).filter(ChatMessage.listener_id == listener_id).distinct().all()]
    for uid in manager.get_online_user_ids(user_ids):
        await manager.send_to_user(uid, {"type": "listener_online", "listener_id": listener_id})
    try:
        while True:
            raw = await websocket.receive_json()
            await _handle_listener_ws_event(raw, listener_id, db)
    except Exception:
        manager.disconnect_listener(listener_id, websocket)
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
