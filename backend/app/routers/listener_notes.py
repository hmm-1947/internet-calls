from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_listener
from app.models.models import Listener, Call, ListenerNote, User
from app.schemas.schemas import ListenerNoteSave, ListenerNoteOut

router = APIRouter(prefix="/listener/notes", tags=["listener-notes"])


def _resolve_user_id(db: Session, listener_id: int, payload: ListenerNoteSave) -> int:
    if payload.user_id:
        return payload.user_id
    if payload.call_id:
        call = db.query(Call).filter(Call.id == payload.call_id, Call.callee_listener_id == listener_id).first()
        if not call:
            raise HTTPException(status_code=404, detail="Call not found")
        return call.caller_user_id
    raise HTTPException(status_code=400, detail="user_id or call_id required")


def _attach_user_context(db: Session, listener_id: int, user_id: int, note: ListenerNote) -> ListenerNoteOut:
    user = db.query(User).filter(User.id == user_id).first()
    last_call = (
        db.query(Call)
        .filter(Call.callee_listener_id == listener_id, Call.caller_user_id == user_id)
        .order_by(Call.created_at.desc())
        .first()
    )
    out = ListenerNoteOut.model_validate(note)
    out.user_name = user.name if user else None
    out.last_call_at = last_call.created_at if last_call else None
    return out


@router.get("/by-call/{call_id}", response_model=ListenerNoteOut | None)
def get_note_by_call(call_id: int, db: Session = Depends(get_db), listener: Listener = Depends(get_current_listener)):
    call = db.query(Call).filter(Call.id == call_id, Call.callee_listener_id == listener.id).first()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")
    note = (
        db.query(ListenerNote)
        .filter(ListenerNote.listener_id == listener.id, ListenerNote.user_id == call.caller_user_id)
        .order_by(ListenerNote.updated_at.desc())
        .first()
    )
    if note:
        return _attach_user_context(db, listener.id, call.caller_user_id, note)
    user = db.query(User).filter(User.id == call.caller_user_id).first()
    return ListenerNoteOut(
        id=0,
        listener_id=listener.id,
        user_id=call.caller_user_id,
        call_id=call.id,
        note="",
        updated_at=call.created_at,
        user_name=user.name if user else None,
        last_call_at=call.created_at,
    )


@router.get("/by-user/{user_id}", response_model=ListenerNoteOut | None)
def get_note_by_user(user_id: int, db: Session = Depends(get_db), listener: Listener = Depends(get_current_listener)):
    note = (
        db.query(ListenerNote)
        .filter(ListenerNote.listener_id == listener.id, ListenerNote.user_id == user_id)
        .order_by(ListenerNote.updated_at.desc())
        .first()
    )
    last_call = (
        db.query(Call)
        .filter(Call.callee_listener_id == listener.id, Call.caller_user_id == user_id)
        .order_by(Call.created_at.desc())
        .first()
    )
    if note:
        return _attach_user_context(db, listener.id, user_id, note)
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return ListenerNoteOut(
        id=0,
        listener_id=listener.id,
        user_id=user_id,
        call_id=last_call.id if last_call else None,
        note="",
        updated_at=last_call.created_at if last_call else user.created_at,
        user_name=user.name,
        last_call_at=last_call.created_at if last_call else None,
    )


@router.post("", response_model=ListenerNoteOut)
def save_note(payload: ListenerNoteSave, db: Session = Depends(get_db), listener: Listener = Depends(get_current_listener)):
    user_id = _resolve_user_id(db, listener.id, payload)
    note = (
        db.query(ListenerNote)
        .filter(ListenerNote.listener_id == listener.id, ListenerNote.user_id == user_id)
        .first()
    )
    if note:
        note.note = payload.note
        if payload.call_id:
            note.call_id = payload.call_id
    else:
        note = ListenerNote(
            listener_id=listener.id,
            user_id=user_id,
            call_id=payload.call_id,
            note=payload.note,
        )
        db.add(note)
    db.commit()
    db.refresh(note)
    return _attach_user_context(db, listener.id, user_id, note)
