import json
import os
import uuid
import asyncio
from typing import Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Header, WebSocket, WebSocketDisconnect, Query, UploadFile, File

from sqlalchemy.orm import Session, aliased
from sqlalchemy import func, or_
from sqlalchemy.exc import IntegrityError
from app.core.database import get_db
from app.core.config import settings
from app.models.models import (
    Listener, User, Call, CallRecording, ChatMessage,
    CoinTransaction, CallRating, Session as SessionModel, AdminUser, AuditLog,
    GiftTransaction, ListenerCoinTransaction, ChatSettings, ReservedUsername,
    ListenerNote, UserBillingPurchase, ListenerBadgeTag, ListenerWeeklyChallengeProgress,
)
from datetime import timedelta
from app.schemas.schemas import ListenerCreate, AdminListenerProfileUpdate, AdminUserProfileUpdate, AdminActiveUpdate, AdminVideoCallUpdate, AdminListenerStatusUpdate, ListenerBadgeTagCreate, ListenerTagAssign, AdminListenerPasswordUpdate
from app.utils.security import hash_password
from app.utils.uploads import read_and_validate_image, write_file
from app.utils.media_urls import sign_media_url
from app.utils.audit import record_audit_event

# Admin recording playback links only need to stay valid for the length of a
# viewing session on the panel, not forever.
RECORDING_URL_TTL_SECONDS = 60 * 60

from app.core.ws_manager import manager
#admin
router = APIRouter(prefix="/admin", tags=["admin"])

def verify_admin(authorization: str = Header(...), db: Session = Depends(get_db)) -> AdminUser:
    from datetime import datetime, timezone
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    token = authorization.removeprefix("Bearer ")
    session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.admin_id.isnot(None)).first()
    if not session:
        raise HTTPException(status_code=401, detail="Invalid session")
    if session.expires_at and session.expires_at < datetime.now(timezone.utc):
        db.delete(session)
        db.commit()
        raise HTTPException(status_code=401, detail="Session expired")
    admin = db.query(AdminUser).filter(AdminUser.id == session.admin_id).first()
    if not admin or not admin.is_active:
        raise HTTPException(status_code=401, detail="Invalid session")
    return admin


ADMIN_WS_REVALIDATE_SECONDS = 60


@router.websocket("/ws")
async def admin_ws(websocket: WebSocket, token: str = Query(...)):
    db = next(get_db())
    try:
        session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.admin_id.isnot(None)).first()
        admin = db.query(AdminUser).filter(AdminUser.id == session.admin_id).first() if session else None
        if not admin or not admin.is_active:
            await websocket.close(code=4003)
            return
    finally:
        db.close()
    await manager.connect_admin(websocket)

    async def _revalidate_loop():
        while True:
            await asyncio.sleep(ADMIN_WS_REVALIDATE_SECONDS)
            check_db = next(get_db())
            try:
                check_session = check_db.query(SessionModel).filter(SessionModel.token == token, SessionModel.admin_id.isnot(None)).first()
                if not check_session or (check_session.expires_at and check_session.expires_at < datetime.now(timezone.utc)):
                    await websocket.close(code=4003)
                    return
                check_admin = check_db.query(AdminUser).filter(AdminUser.id == check_session.admin_id).first()
                if not check_admin or not check_admin.is_active:
                    await websocket.close(code=4003)
                    return
            finally:
                check_db.close()

    revalidate_task = asyncio.create_task(_revalidate_loop())
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect_admin(websocket)
    except Exception:
        manager.disconnect_admin(websocket)
    finally:
        revalidate_task.cancel()



def _assert_listener_name_available(db: Session, name: str, exclude_id: Optional[int] = None) -> None:
    """Users pick a listener by name, so two "Priya" rows are indistinguishable
    in the app. Matched case-insensitively, so "priya" collides with "Priya".
    `exclude_id` keeps a rename from clashing with the listener's own row.

    Also blocks a name that collides with an existing user's username, since
    listeners and users share the same namespace app-side.
    """
    q = db.query(Listener).filter(func.lower(Listener.name) == name.lower())
    if exclude_id is not None:
        q = q.filter(Listener.id != exclude_id)
    duplicate = q.first()
    if duplicate:
        raise HTTPException(
            status_code=400,
            detail=f'A listener named "{duplicate.name}" already exists. Please use a different name.',
        )

    user_match = db.query(User).filter(func.lower(User.username) == name.lower()).first()
    if user_match:
        raise HTTPException(
            status_code=400,
            detail=f'There is already a user with the username "{user_match.username}". Please use a different name.',
        )


def _reserved_username_warning(db: Session, name: str) -> Optional[dict]:
    """If `name` is currently sitting in another user's 45-day username
    reservation window, returns the confirmation payload the admin panel
    shows before letting the admin proceed anyway. Admin listener creation
    is exempt from the reservation itself - this is a heads-up only."""
    cleaned = name.strip().lower()
    reservation = (
        db.query(ReservedUsername)
        .filter(
            func.lower(ReservedUsername.username) == cleaned,
            ReservedUsername.released_at > datetime.now(timezone.utc),
        )
        .order_by(ReservedUsername.released_at.desc())
        .first()
    )
    if not reservation:
        return None
    remaining = reservation.released_at - datetime.now(timezone.utc)
    remaining_days = max(1, (remaining.days + (1 if remaining.seconds else 0)))
    owner = db.query(User).filter(User.id == reservation.reserved_by_user_id).first()
    return {
        "username": cleaned,
        "changed_to": owner.username if owner else None,
        "remaining_days": remaining_days,
        "message": (
            f'The username "{cleaned}" was being used by a user who changed to '
            f'"{owner.username if owner else "a different username"}", and is still in its '
            f'{remaining_days}-day reservation period. Continue anyway?'
        ),
    }


@router.post("/listeners")
def create_listener(payload: ListenerCreate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    name = (payload.name or "").strip()
    phone = (payload.phone or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Name is required")
    if not phone:
        raise HTTPException(status_code=400, detail="Phone is required")

    existing = db.query(Listener).filter(Listener.phone == phone).first()
    if existing:
        raise HTTPException(status_code=400, detail=f'Phone already registered to "{existing.name}"')

    _assert_listener_name_available(db, name)

    if not payload.confirm_reserved_username:
        warning = _reserved_username_warning(db, name)
        if warning:
            raise HTTPException(status_code=409, detail={"reserved_username_warning": warning})

    listener = Listener(
        name=name,
        phone=phone,
        password_hash=hash_password(payload.password),
    )
    db.add(listener)
    try:
        db.commit()
    except IntegrityError:
        # Two admins registering the same phone at once: the unique index wins.
        db.rollback()
        raise HTTPException(status_code=400, detail="Phone already registered")
    db.refresh(listener)
    return {"id": listener.id, "name": listener.name, "phone": listener.phone}

@router.get("/listeners")
def list_listeners(skip: int = Query(0, ge=0), limit: Optional[int] = Query(None, ge=1, le=5000), db: Session = Depends(get_db), _=Depends(verify_admin)):
    q = db.query(Listener).order_by(Listener.id).offset(skip)
    if limit is not None:
        q = q.limit(limit)
    listeners = q.all()
    tag_ids = {l.badge_tag_id for l in listeners if l.badge_tag_id}
    tags_by_id = {}
    if tag_ids:
        for t in db.query(ListenerBadgeTag).filter(ListenerBadgeTag.id.in_(tag_ids)).all():
            tags_by_id[t.id] = {"id": t.id, "name": t.name, "color": t.color}
    result = [{"id": l.id, "name": l.name, "phone": l.phone, "is_active": l.is_active, "is_online": l.effective_online, "is_logged_in": bool(l.is_logged_in), "status_on": bool(l.is_online) and not bool(l.admin_forced_offline), "admin_forced_offline": bool(l.admin_forced_offline), "about": l.about, "tags": l.tags, "languages": l.languages, "photo_url": l.photo_url, "age": l.age, "occupation": l.occupation, "badge_tag": tags_by_id.get(l.badge_tag_id), "video_call_disabled_by_admin": bool(l.video_call_disabled_by_admin)} for l in listeners]
    result.sort(key=lambda x: not x["is_online"])
    return result

@router.patch("/listeners/{listener_id}/profile")
def update_listener_profile(listener_id: int, payload: AdminListenerProfileUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    if payload.name is not None and payload.name != listener.name:
        _assert_listener_name_available(db, payload.name, exclude_id=listener.id)
        listener.name = payload.name
    if payload.about is not None:
        listener.about = payload.about
    if payload.tags is not None:
        listener.tags = json.dumps(payload.tags)
    if payload.languages is not None:
        listener.languages = json.dumps(payload.languages)
    if payload.age is not None:
        listener.age = payload.age
    if payload.occupation is not None:
        listener.occupation = payload.occupation
    db.commit()
    return {"id": listener.id, "name": listener.name, "about": listener.about, "tags": listener.tags, "languages": listener.languages, "age": listener.age, "occupation": listener.occupation}

@router.post("/listeners/{listener_id}/photo")
async def update_listener_photo(listener_id: int, file: UploadFile = File(...), db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    contents, ext = await read_and_validate_image(file)
    filename = f"listener_{listener.id}_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("profile_photos", filename)
    await write_file(filepath, contents)
    listener.photo_url = f"/profile_photos/{filename}"
    db.commit()
    return {"id": listener.id, "photo_url": listener.photo_url}


@router.patch("/listeners/{listener_id}/active")
async def set_listener_active(listener_id: int, payload: AdminActiveUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    listener.is_active = payload.is_active
    db.commit()
    if not listener.is_active:
        await manager.send_to_listener(listener_id, {"type": "force_logout"})
    return {"id": listener.id, "is_active": listener.is_active}


@router.patch("/listeners/{listener_id}/video-call")
async def set_listener_video_call_disabled(listener_id: int, payload: AdminVideoCallUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    listener.video_call_disabled_by_admin = payload.disabled
    db.commit()
    effective = bool(listener.video_call_enabled) and not bool(listener.video_call_disabled_by_admin)
    await manager.send_to_listener(listener.id, {
        "type": "video_call_admin_setting_changed",
        "video_call_disabled_by_admin": bool(listener.video_call_disabled_by_admin),
    })
    await manager.broadcast_to_all_users({
        "type": "listener_video_call_changed",
        "listener_id": listener.id,
        "video_call_enabled": effective,
    })
    return {"id": listener.id, "video_call_disabled_by_admin": listener.video_call_disabled_by_admin}


@router.patch("/listeners/{listener_id}/status")
async def set_listener_status(listener_id: int, payload: AdminListenerStatusUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    from app.utils.listener_presence import broadcast_listener_presence, reject_calls_if_offline
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    listener.is_online = payload.is_online
    listener.admin_forced_offline = not payload.is_online
    if not payload.is_online:
        listener.last_seen = datetime.now(timezone.utc)
    db.commit()
    await manager.send_to_listener(listener.id, {
        "type": "listener_status_changed",
        "is_online": bool(listener.is_online),
        "admin_forced_offline": bool(listener.admin_forced_offline),
    })
    await reject_calls_if_offline(db, listener)
    await broadcast_listener_presence(listener)
    return {
        "id": listener.id,
        "is_online": listener.effective_online,
        "status_on": bool(listener.is_online) and not bool(listener.admin_forced_offline),
        "is_logged_in": bool(listener.is_logged_in),
        "admin_forced_offline": bool(listener.admin_forced_offline),
    }


@router.post("/listeners/{listener_id}/password")
async def set_listener_password(listener_id: int, payload: AdminListenerPasswordUpdate, db: Session = Depends(get_db), admin: AdminUser = Depends(verify_admin)):
    """Let an admin reset a listener's password directly, no current-password
    check needed since the admin's own session already proves the right to
    act. Existing sessions for that listener are invalidated and any
    logged-in device is kicked out, mirroring how an admin's own
    change-password flow revokes sessions."""
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    listener.password_hash = hash_password(payload.new_password)
    db.query(SessionModel).filter(SessionModel.listener_id == listener_id).delete()
    record_audit_event(db, "listener", listener.id, listener.name, "password_reset_by_admin")
    db.commit()
    await manager.send_to_listener(listener_id, {"type": "force_logout"})
    return {"id": listener.id, "status": "password_changed"}


@router.get("/listener-tags")
def list_listener_tags(db: Session = Depends(get_db), _=Depends(verify_admin)):
    tags = db.query(ListenerBadgeTag).order_by(ListenerBadgeTag.name).all()
    result = []
    for t in tags:
        count = db.query(Listener).filter(Listener.badge_tag_id == t.id).count()
        result.append({"id": t.id, "name": t.name, "color": t.color, "listener_count": count})
    return result


@router.post("/listener-tags")
def create_listener_tag(payload: ListenerBadgeTagCreate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    name = (payload.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Name is required")
    existing = db.query(ListenerBadgeTag).filter(func.lower(ListenerBadgeTag.name) == name.lower()).first()
    if existing:
        raise HTTPException(status_code=400, detail=f'A tag named "{existing.name}" already exists.')
    tag = ListenerBadgeTag(name=name, color=(payload.color or "#E11D48").strip())
    db.add(tag)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="Tag already exists")
    db.refresh(tag)
    return {"id": tag.id, "name": tag.name, "color": tag.color}


@router.put("/listener-tags/{tag_id}")
def update_listener_tag(tag_id: int, payload: ListenerBadgeTagCreate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    tag = db.query(ListenerBadgeTag).filter(ListenerBadgeTag.id == tag_id).first()
    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")
    name = (payload.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Name is required")
    existing = db.query(ListenerBadgeTag).filter(func.lower(ListenerBadgeTag.name) == name.lower(), ListenerBadgeTag.id != tag_id).first()
    if existing:
        raise HTTPException(status_code=400, detail=f'A tag named "{existing.name}" already exists.')
    tag.name = name
    tag.color = (payload.color or tag.color or "#E11D48").strip()
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="Tag already exists")
    db.refresh(tag)
    return {"id": tag.id, "name": tag.name, "color": tag.color}


@router.delete("/listener-tags/{tag_id}")
def delete_listener_tag(tag_id: int, db: Session = Depends(get_db), _=Depends(verify_admin)):
    tag = db.query(ListenerBadgeTag).filter(ListenerBadgeTag.id == tag_id).first()
    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")
    db.query(Listener).filter(Listener.badge_tag_id == tag_id).update({Listener.badge_tag_id: None})
    db.delete(tag)
    db.commit()
    return {"id": tag_id, "deleted": True}


@router.get("/listener-tags/search-listeners")
def search_listeners_for_tag(q: str = Query("", alias="q"), db: Session = Depends(get_db), _=Depends(verify_admin)):
    query = db.query(Listener).outerjoin(
        ListenerBadgeTag, Listener.badge_tag_id == ListenerBadgeTag.id
    ).order_by(Listener.name)
    term = (q or "").strip()
    if term:
        like = f"%{term.lower()}%"
        query = query.filter(
            or_(
                func.lower(Listener.name).like(like),
                func.lower(ListenerBadgeTag.name).like(like),
            )
        )
    listeners = query.limit(50).all()
    tag_ids = {l.badge_tag_id for l in listeners if l.badge_tag_id}
    tags_by_id = {}
    if tag_ids:
        for t in db.query(ListenerBadgeTag).filter(ListenerBadgeTag.id.in_(tag_ids)).all():
            tags_by_id[t.id] = {"id": t.id, "name": t.name, "color": t.color}
    return [
        {
            "id": l.id,
            "name": l.name,
            "photo_url": l.photo_url,
            "badge_tag": tags_by_id.get(l.badge_tag_id),
        }
        for l in listeners
    ]


@router.post("/listeners/{listener_id}/tag")
def assign_listener_tag(listener_id: int, payload: ListenerTagAssign, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")
    if payload.tag_id is not None:
        tag = db.query(ListenerBadgeTag).filter(ListenerBadgeTag.id == payload.tag_id).first()
        if not tag:
            raise HTTPException(status_code=404, detail="Tag not found")
    listener.badge_tag_id = payload.tag_id
    db.commit()
    return {"id": listener.id, "badge_tag_id": listener.badge_tag_id}


@router.delete("/listeners/{listener_id}")
def delete_listener(listener_id: int, db: Session = Depends(get_db), _=Depends(verify_admin)):
    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")

    call_ids = [c.id for c in db.query(Call.id).filter(Call.callee_listener_id == listener_id).all()]

    try:
        db.query(CallRating).filter(CallRating.listener_id == listener_id).delete(synchronize_session=False)
        db.query(ChatMessage).filter(ChatMessage.listener_id == listener_id).delete(synchronize_session=False)
        db.query(SessionModel).filter(SessionModel.listener_id == listener_id).delete(synchronize_session=False)
        db.query(GiftTransaction).filter(GiftTransaction.listener_id == listener_id).delete(synchronize_session=False)
        db.query(ListenerCoinTransaction).filter(ListenerCoinTransaction.listener_id == listener_id).delete(synchronize_session=False)
        db.query(ListenerNote).filter(ListenerNote.listener_id == listener_id).delete(synchronize_session=False)
        db.query(ListenerWeeklyChallengeProgress).filter(ListenerWeeklyChallengeProgress.listener_id == listener_id).delete(synchronize_session=False)
        db.query(ChatSettings).filter(
            ((ChatSettings.owner_type == "listener") & (ChatSettings.owner_id == listener_id)) |
            ((ChatSettings.owner_type == "user") & (ChatSettings.other_id == listener_id))
        ).delete(synchronize_session=False)
        if call_ids:
            db.query(CallRecording).filter(CallRecording.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(CoinTransaction).filter(CoinTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(GiftTransaction).filter(GiftTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(ListenerCoinTransaction).filter(ListenerCoinTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(ListenerNote).filter(ListenerNote.call_id.in_(call_ids)).delete(synchronize_session=False)
        db.query(Call).filter(Call.callee_listener_id == listener_id).delete(synchronize_session=False)

        db.delete(listener)
        db.commit()

    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="Failed to delete listener due to related data")
    return {"detail": "Listener deleted"}

@router.get("/users")
def list_users(skip: int = Query(0, ge=0), limit: Optional[int] = Query(None, ge=1, le=5000), db: Session = Depends(get_db), _=Depends(verify_admin)):
    q = db.query(User).order_by(User.id).offset(skip)
    if limit is not None:
        q = q.limit(limit)
    users = q.all()
    result = [{"id": u.id, "name": u.name, "username": u.username, "email": u.email, "phone": u.phone, "is_active": u.is_active, "coins": u.coins, "is_online": manager.is_user_online(u.id), "bio": u.bio, "photo_url": u.photo_url, "video_call_disabled_by_admin": u.video_call_disabled_by_admin} for u in users]
    result.sort(key=lambda x: not x["is_online"])
    return result

@router.patch("/users/{user_id}/profile")
def update_user_profile(user_id: int, payload: AdminUserProfileUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if payload.bio is not None:
        user.bio = payload.bio
    db.commit()
    return {"id": user.id, "bio": user.bio}

@router.post("/users/{user_id}/photo")
async def update_user_photo(user_id: int, file: UploadFile = File(...), db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    contents, ext = await read_and_validate_image(file)
    filename = f"user_{user.id}_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join("profile_photos", filename)
    await write_file(filepath, contents)
    user.photo_url = f"/profile_photos/{filename}"
    db.commit()
    return {"id": user.id, "photo_url": user.photo_url}


@router.patch("/users/{user_id}/active")
async def set_user_active(user_id: int, payload: AdminActiveUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_active = payload.is_active
    db.commit()
    if not user.is_active:
        await manager.send_to_user(user_id, {"type": "force_logout"})
    return {"id": user.id, "is_active": user.is_active}

@router.patch("/users/{user_id}/video-call")
async def set_user_video_call_disabled(user_id: int, payload: AdminVideoCallUpdate, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.video_call_disabled_by_admin = payload.disabled
    db.commit()
    await manager.send_to_user(user_id, {
        "type": "video_call_setting_changed",
        "video_call_disabled_by_admin": user.video_call_disabled_by_admin,
    })
    return {"id": user.id, "video_call_disabled_by_admin": user.video_call_disabled_by_admin}


@router.delete("/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db), _=Depends(verify_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    call_ids = [c.id for c in db.query(Call.id).filter(Call.caller_user_id == user_id).all()]

    try:
        db.query(CallRating).filter(CallRating.user_id == user_id).delete(synchronize_session=False)
        db.query(ChatMessage).filter(ChatMessage.user_id == user_id).delete(synchronize_session=False)
        db.query(SessionModel).filter(SessionModel.user_id == user_id).delete(synchronize_session=False)
        db.query(CoinTransaction).filter(CoinTransaction.user_id == user_id).delete(synchronize_session=False)
        db.query(GiftTransaction).filter(GiftTransaction.user_id == user_id).delete(synchronize_session=False)
        db.query(ListenerNote).filter(ListenerNote.user_id == user_id).delete(synchronize_session=False)
        db.query(UserBillingPurchase).filter(UserBillingPurchase.user_id == user_id).delete(synchronize_session=False)
        db.query(ReservedUsername).filter(ReservedUsername.reserved_by_user_id == user_id).delete(synchronize_session=False)
        db.query(ChatSettings).filter(
            ((ChatSettings.owner_type == "user") & (ChatSettings.owner_id == user_id)) |
            ((ChatSettings.owner_type == "listener") & (ChatSettings.other_id == user_id))
        ).delete(synchronize_session=False)
        if call_ids:
            db.query(CallRecording).filter(CallRecording.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(GiftTransaction).filter(GiftTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(ListenerCoinTransaction).filter(ListenerCoinTransaction.call_id.in_(call_ids)).delete(synchronize_session=False)
            db.query(ListenerNote).filter(ListenerNote.call_id.in_(call_ids)).delete(synchronize_session=False)
        db.query(Call).filter(Call.caller_user_id == user_id).delete(synchronize_session=False)

        db.delete(user)
        db.commit()

    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="Failed to delete user due to related data")
    return {"detail": "User deleted"}

@router.get("/recordings")
def list_recordings(db: Session = Depends(get_db), _=Depends(verify_admin)):
    rows = (
        db.query(CallRecording, Call, User, Listener)
        .outerjoin(Call, Call.id == CallRecording.call_id)
        .outerjoin(User, User.id == Call.caller_user_id)
        .outerjoin(Listener, Listener.id == Call.callee_listener_id)
        .order_by(CallRecording.id.desc())
        .all()
    )
    result = []
    for r, call, caller, listener in rows:
        filename = r.file_path.replace("/out/", "") if r.file_path else None
        # Signed fresh on every request (this endpoint is only reachable by a
        # verified admin session already), rather than stored once, so the
        # link naturally expires instead of being a permanent public URL if
        # this JSON response ever leaked.
        file_url = sign_media_url("recordings", filename, RECORDING_URL_TTL_SECONDS) if filename else None
        result.append({
            "id": r.id,
            "call_id": r.call_id,
            "room_name": r.room_name,
            "file_path": file_url,
            "status": r.status,
            "started_at": r.started_at,
            "ended_at": r.ended_at,
            "caller_name": caller.name if caller else None,
            "listener_name": listener.name if listener else None,
        })
    return result

@router.get("/calls")
def list_calls(db: Session = Depends(get_db), _=Depends(verify_admin)):
    rows = (
        db.query(Call, User, Listener)
        .outerjoin(User, User.id == Call.caller_user_id)
        .outerjoin(Listener, Listener.id == Call.callee_listener_id)
        .order_by(Call.id.desc())
        .all()
    )
    result = []
    for c, caller, listener in rows:
        result.append({
            "id": c.id,
            "caller_name": caller.name if caller else None,
            "listener_name": listener.name if listener else None,
            "status": c.status,
            "created_at": c.created_at,
        })
    return result

@router.get("/chats")
def list_chats(limit: int = Query(5000, le=20000), db: Session = Depends(get_db), _=Depends(verify_admin)):
    UserAlias = aliased(User)
    ListenerAlias = aliased(Listener)
    rows = (
        db.query(ChatMessage, UserAlias, ListenerAlias)
        .outerjoin(UserAlias, UserAlias.id == ChatMessage.user_id)
        .outerjoin(ListenerAlias, ListenerAlias.id == ChatMessage.listener_id)
        .order_by(ChatMessage.created_at.desc())
        .limit(limit)
        .all()
    )
    result = []
    for m, user, listener in rows:
        result.append({
            "id": m.id,
            "user_id": m.user_id,
            "listener_id": m.listener_id,
            "caller_name": user.name if user else None,
            "listener_name": listener.name if listener else None,
            "sender_type": m.sender_type,
            "message": m.message,
            "message_type": m.message_type,
            "audio_url": m.audio_url,
            "is_deleted": m.is_deleted,
            "created_at": m.created_at,
        })
    return result

@router.get("/listener/{listener_id}/wallet")
def admin_listener_wallet(
    listener_id: int,
    from_date: str = None,
    to_date: str = None,
    db: Session = Depends(get_db),
    _=Depends(verify_admin),
):
    """Same breakdown as the listener app's own /listener/wallet screen, for
    any listener the admin selects — read-only, no coins are touched.
    from_date/to_date (YYYY-MM-DD) optionally scope the day/night breakdown
    to a date range; totals at the top are always all-time."""
    from datetime import datetime, timedelta
    from app.models.models import ListenerCoinTransaction, GiftTransaction
    from sqlalchemy import extract, func as sa_func

    listener = db.query(Listener).filter(Listener.id == listener_id).first()
    if not listener:
        raise HTTPException(status_code=404, detail="Listener not found")

    def in_date_range(time_col, filters):
        if from_date:
            filters = filters + [time_col >= datetime.strptime(from_date, "%Y-%m-%d")]
        if to_date:
            filters = filters + [time_col < datetime.strptime(to_date, "%Y-%m-%d") + timedelta(days=1)]
        return filters


    # created_at is stored in UTC; the day/night split is meant in IST, so
    # shift the column by the IST offset before pulling out the hour (same
    # fix as app/utils/wallet_stats.py, which the listener-facing wallet
    # screen uses).
    IST_OFFSET = timedelta(hours=5, minutes=30)

    def split_sum(amount_col, time_col, filters, whole_minutes: bool = False):
        ist_hour = extract('hour', time_col + IST_OFFSET)
        # Wallet minutes only count a call once it has run a full 60 seconds;
        # each row is floored to its own whole-minute boundary before
        # summing (see app/utils/wallet_stats.py for the same trick).
        col = (amount_col - amount_col % 60) if whole_minutes else amount_col
        day_sum = db.query(sa_func.coalesce(sa_func.sum(col), 0)).filter(
            *filters,
            ist_hour >= 5,
            ist_hour < 21,
        ).scalar()
        night_sum = db.query(sa_func.coalesce(sa_func.sum(col), 0)).filter(
            *filters,
            (ist_hour < 5) | (ist_hour >= 21),
        ).scalar()
        return int(day_sum), int(night_sum)

    def split_count(model, time_col, filters):
        ist_hour = extract('hour', time_col + IST_OFFSET)
        day_count = db.query(sa_func.count(model.id)).filter(
            *filters,
            ist_hour >= 5,
            ist_hour < 21,
        ).scalar()
        night_count = db.query(sa_func.count(model.id)).filter(
            *filters,
            (ist_hour < 5) | (ist_hour >= 21),
        ).scalar()
        return int(day_count), int(night_count)

    audio_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == listener.id,
        ListenerCoinTransaction.reason == "audio_call",
    ).scalar()
    video_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == listener.id,
        ListenerCoinTransaction.reason == "video_call",
    ).scalar()
    chat_coins = db.query(sa_func.coalesce(sa_func.sum(ListenerCoinTransaction.amount), 0)).filter(
        ListenerCoinTransaction.listener_id == listener.id,
        ListenerCoinTransaction.reason == "chat_message",
    ).scalar()

    audio_seconds_day, audio_seconds_night = split_sum(
        Call.duration_seconds, Call.created_at,
        in_date_range(Call.created_at, [Call.callee_listener_id == listener.id, Call.call_type == "audio"]),
        whole_minutes=True,
    )
    video_seconds_day, video_seconds_night = split_sum(
        Call.duration_seconds, Call.created_at,
        in_date_range(Call.created_at, [Call.callee_listener_id == listener.id, Call.call_type == "video"]),
        whole_minutes=True,
    )
    text_msgs_day, text_msgs_night = split_count(
        ChatMessage, ChatMessage.created_at,
        in_date_range(ChatMessage.created_at, [ChatMessage.listener_id == listener.id, ChatMessage.sender_type == "user", ChatMessage.message_type == "text"]),
    )
    voice_msgs_day, voice_msgs_night = split_count(
        ChatMessage, ChatMessage.created_at,
        in_date_range(ChatMessage.created_at, [ChatMessage.listener_id == listener.id, ChatMessage.sender_type == "user", ChatMessage.message_type == "audio"]),
    )
    gift_coins_day, gift_coins_night = split_sum(
        GiftTransaction.coins, GiftTransaction.created_at,
        in_date_range(GiftTransaction.created_at, [GiftTransaction.listener_id == listener.id]),
    )
    gift_coins_total = db.query(sa_func.coalesce(sa_func.sum(GiftTransaction.coins), 0)).filter(
        GiftTransaction.listener_id == listener.id,
    ).scalar()

    return {
        "coins": listener.coins,
        "audio_call_coins": int(audio_coins),
        "audio_call_minutes": (int(audio_seconds_day) + int(audio_seconds_night)) // 60,
        "video_call_coins": int(video_coins),
        "video_call_minutes": (int(video_seconds_day) + int(video_seconds_night)) // 60,
        "chat_coins": int(chat_coins),
        "gift_coins": int(gift_coins_total),
        "day": {
            "audio_call_minutes": audio_seconds_day // 60,
            "video_call_minutes": video_seconds_day // 60,
            "chat_messages": text_msgs_day,
            "voice_messages": voice_msgs_day,
            "gift_coins": gift_coins_day,
        },
        "night": {
            "audio_call_minutes": audio_seconds_night // 60,
            "video_call_minutes": video_seconds_night // 60,
            "chat_messages": text_msgs_night,
            "voice_messages": voice_msgs_night,
            "gift_coins": gift_coins_night,
        },
    }

@router.get("/calls/active")
def list_active_calls(db: Session = Depends(get_db), _=Depends(verify_admin)):
    rows = (
        db.query(Call, User, Listener)
        .outerjoin(User, User.id == Call.caller_user_id)
        .outerjoin(Listener, Listener.id == Call.callee_listener_id)
        .filter(Call.status.in_(["ringing", "accepted"]))
        .order_by(Call.id.desc())
        .all()
    )
    result = []
    for c, caller, listener in rows:
        result.append({
            "id": c.id,
            "room_name": c.room_name,
            "call_type": c.call_type,
            "status": c.status,
            "user_id": c.caller_user_id,
            "listener_id": c.callee_listener_id,
            "user_name": caller.name if caller else None,
            "listener_name": listener.name if listener else None,
            "connected_at": c.connected_at,
            "created_at": c.created_at,
        })
    return result

@router.get("/stats/overview")
def stats_overview(range: str = Query("month"), db: Session = Depends(get_db), _=Depends(verify_admin)):
    from datetime import datetime, timedelta, timezone

    total_users = db.query(func.count(User.id)).scalar() or 0
    active_users = db.query(func.count(User.id)).filter(User.is_active == True).scalar() or 0
    inactive_users = total_users - active_users

    total_listeners = db.query(func.count(Listener.id)).scalar() or 0
    active_listeners = db.query(func.count(Listener.id)).filter(Listener.is_active == True).scalar() or 0
    inactive_listeners = total_listeners - active_listeners

    # Presence is the live websocket, not the `is_online` column, so it matches
    # what the people lists show and can never go stale after a restart.
    online_users = sum(1 for (uid,) in db.query(User.id).all() if manager.is_user_online(uid))
    offline_users = total_users - online_users
    online_listeners = sum(1 for l in db.query(Listener).all() if l.effective_online)
    offline_listeners = total_listeners - online_listeners

    avg_duration = db.query(func.coalesce(func.avg(Call.duration_seconds), 0)).filter(Call.status == "ended").scalar() or 0

    paid_statuses = ["completed", "partially_refunded", "refunded"]
    gross_rupees, refunded_paise = db.query(
        func.coalesce(func.sum(UserBillingPurchase.price_paid), 0),
        func.coalesce(func.sum(UserBillingPurchase.refunded_amount_paise), 0),
    ).filter(UserBillingPurchase.status.in_(paid_statuses)).one()
    refunded_rupees = (refunded_paise or 0) / 100
    total_earnings = max((gross_rupees or 0) - refunded_rupees, 0)

    now = datetime.now(timezone.utc)
    ranges = {
        "day": (now - timedelta(days=1), "hour"),
        "week": (now - timedelta(days=7), "day"),
        "month": (now - timedelta(days=30), "day"),
        "6months": (now - timedelta(days=182), "week"),
        "all": (None, "month"),
    }
    since, bucket = ranges.get(range, ranges["month"])

    trunc_unit = {"hour": "hour", "day": "day", "week": "week", "month": "month"}[bucket]
    bucket_col = func.date_trunc(trunc_unit, Call.created_at)

    def format_label(ts, bucket):
        if bucket == "hour":
            return ts.strftime("%Y-%m-%d %H:00")
        if bucket == "day":
            return ts.strftime("%Y-%m-%d")
        if bucket == "week":
            iso = ts.isocalendar()
            return f"{iso[0]}-W{iso[1]:02d}"
        return ts.strftime("%Y-%m")

    def pivot_two_way(rows, primary_type):
        """Turns (timestamp, type_value, count) rows into one ordered list of
        labels plus a count-per-label dict for `primary_type` and one for
        everything else, so a bucket with only one type still gets an
        explicit 0 for the other (keeps both lines aligned on the same
        x-axis points)."""
        labels_seen = []
        primary_by_label = {}
        other_by_label = {}
        for ts, type_value, count in rows:
            label = format_label(ts, bucket)
            if label not in primary_by_label and label not in other_by_label:
                labels_seen.append(label)
            if type_value == primary_type:
                primary_by_label[label] = primary_by_label.get(label, 0) + count
            else:
                other_by_label[label] = other_by_label.get(label, 0) + count
        return labels_seen, primary_by_label, other_by_label

    call_rows = (
        db.query(bucket_col.label("bucket"), Call.call_type, func.count(Call.id))
        .filter(Call.status == "ended")
    )
    if since is not None:
        call_rows = call_rows.filter(Call.created_at >= since)
    call_rows = call_rows.group_by("bucket", Call.call_type).order_by("bucket").all()

    call_labels, video_by_label, audio_by_label = pivot_two_way(call_rows, "video")
    series = [
        {
            "label": label,
            "count": audio_by_label.get(label, 0) + video_by_label.get(label, 0),
            "audio_count": audio_by_label.get(label, 0),
            "video_count": video_by_label.get(label, 0),
        }
        for label in call_labels
    ]

    chat_bucket_col = func.date_trunc(trunc_unit, ChatMessage.created_at)
    chat_rows = (
        db.query(chat_bucket_col.label("bucket"), ChatMessage.message_type, func.count(ChatMessage.id))
        .filter(ChatMessage.message_type.in_(["text", "audio"]))
    )
    if since is not None:
        chat_rows = chat_rows.filter(ChatMessage.created_at >= since)
    chat_rows = chat_rows.group_by("bucket", ChatMessage.message_type).order_by("bucket").all()

    chat_labels, voice_chats_by_label, text_chats_by_label = pivot_two_way(chat_rows, "audio")
    chats_series = [
        {
            "label": label,
            "count": text_chats_by_label.get(label, 0) + voice_chats_by_label.get(label, 0),
            "text_count": text_chats_by_label.get(label, 0),
            "voice_count": voice_chats_by_label.get(label, 0),
        }
        for label in chat_labels
    ]

    return {
        "total_users": total_users,
        "active_users": active_users,
        "inactive_users": inactive_users,
        "online_users": online_users,
        "offline_users": offline_users,
        "total_listeners": total_listeners,
        "active_listeners": active_listeners,
        "inactive_listeners": inactive_listeners,
        "online_listeners": online_listeners,
        "offline_listeners": offline_listeners,
        "avg_call_duration_seconds": round(avg_duration),
        "total_earnings": round(total_earnings, 2),
        "total_refunded": round(refunded_rupees, 2),
        "calls_series": series,
        "chats_series": chats_series,
    }


@router.get("/stats/users")
def list_user_stats(db: Session = Depends(get_db), _=Depends(verify_admin)):
    call_stats = dict(
        db.query(Call.caller_user_id, func.count(Call.id))
        .filter(Call.status == "ended")
        .group_by(Call.caller_user_id).all()
    )
    duration_stats = dict(
        db.query(Call.caller_user_id, func.coalesce(func.sum(Call.duration_seconds), 0))
        .filter(Call.status == "ended")
        .group_by(Call.caller_user_id).all()
    )
    chat_stats = dict(
        db.query(ChatMessage.user_id, func.count(ChatMessage.id))
        .filter(ChatMessage.sender_type == "user")
        .group_by(ChatMessage.user_id).all()
    )
    users = db.query(User).all()
    result = []
    for u in users:
        result.append({
            "id": u.id,
            "name": u.name,
            "phone": u.phone,
            "total_calls": call_stats.get(u.id, 0),
            "total_call_seconds": duration_stats.get(u.id, 0),
            "total_chat_messages": chat_stats.get(u.id, 0),
        })
    result.sort(key=lambda x: x["total_calls"], reverse=True)
    return result

@router.get("/stats/listeners")
def list_listener_stats(db: Session = Depends(get_db), _=Depends(verify_admin)):
    call_stats = dict(
        db.query(Call.callee_listener_id, func.count(Call.id))
        .filter(Call.status == "ended")
        .group_by(Call.callee_listener_id).all()
    )
    duration_stats = dict(
        db.query(Call.callee_listener_id, func.coalesce(func.sum(Call.duration_seconds), 0))
        .filter(Call.status == "ended")
        .group_by(Call.callee_listener_id).all()
    )
    chat_stats = dict(
        db.query(ChatMessage.listener_id, func.count(ChatMessage.id))
        .filter(ChatMessage.sender_type == "listener")
        .group_by(ChatMessage.listener_id).all()
    )
    listeners = db.query(Listener).all()
    result = []
    for l in listeners:
        result.append({
            "id": l.id,
            "name": l.name,
            "phone": l.phone,
            "total_calls": call_stats.get(l.id, 0),
            "total_call_seconds": duration_stats.get(l.id, 0),
            "total_chat_messages": chat_stats.get(l.id, 0),
        })
    result.sort(key=lambda x: x["total_calls"], reverse=True)
    return result


def _paginated_audit_log(db: Session, subject_type: str, page: int, page_size: int):
    page = max(page, 1)
    page_size = min(max(page_size, 1), 100)

    query = db.query(AuditLog).filter(AuditLog.subject_type == subject_type)
    total = query.count()
    rows = (
        query.order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return {
        "items": [
            {
                "id": r.id,
                "subject_id": r.subject_id,
                "name": r.subject_name,
                "action": r.action,
                "created_at": r.created_at,
            }
            for r in rows
        ],
        "total": total,
        "page": page,
        "page_size": page_size,
    }


@router.get("/audit-log/users")
def list_user_audit_log(
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
    _=Depends(verify_admin),
):
    """Login/logout history for users, most recent first. Failed login
    attempts are never recorded, so only successful events appear here."""
    return _paginated_audit_log(db, "user", page, page_size)


@router.get("/audit-log/listeners")
def list_listener_audit_log(
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
    _=Depends(verify_admin),
):
    """Login/logout history for listeners, most recent first. Failed login
    attempts are never recorded, so only successful events appear here."""
    return _paginated_audit_log(db, "listener", page, page_size)
