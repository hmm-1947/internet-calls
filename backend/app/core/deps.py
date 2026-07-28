from typing import Union
from datetime import datetime, timezone
from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.models.models import Session as SessionModel, User, Listener, AdminUser

def _extract_token(authorization: str) -> str:
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    return authorization.removeprefix("Bearer ")

def _check_expiry(session: SessionModel, db: Session) -> None:
    if session.expires_at and session.expires_at < datetime.now(timezone.utc):
        db.delete(session)
        db.commit()
        raise HTTPException(status_code=401, detail="Session expired")

def get_current_user(authorization: str = Header(...), db: Session = Depends(get_db)) -> User:
    token = _extract_token(authorization)
    session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.user_id.isnot(None)).first()
    if not session:
        raise HTTPException(status_code=401, detail="Invalid session")
    _check_expiry(session, db)
    user = db.query(User).filter(User.id == session.user_id).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="Invalid session")
    return user

def get_current_listener(authorization: str = Header(...), db: Session = Depends(get_db)) -> Listener:
    token = _extract_token(authorization)
    session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.listener_id.isnot(None)).first()
    if not session:
        raise HTTPException(status_code=401, detail="Invalid session")
    _check_expiry(session, db)
    listener = db.query(Listener).filter(Listener.id == session.listener_id).first()
    if not listener or not listener.is_active:
        raise HTTPException(status_code=401, detail="Invalid session")
    return listener

def get_current_admin(authorization: str = Header(...), db: Session = Depends(get_db)) -> AdminUser:
    token = _extract_token(authorization)
    session = db.query(SessionModel).filter(SessionModel.token == token, SessionModel.admin_id.isnot(None)).first()
    if not session:
        raise HTTPException(status_code=401, detail="Invalid session")
    _check_expiry(session, db)
    admin = db.query(AdminUser).filter(AdminUser.id == session.admin_id).first()
    if not admin or not admin.is_active:
        raise HTTPException(status_code=401, detail="Invalid session")
    return admin

def get_current_participant(authorization: str = Header(...), db: Session = Depends(get_db)) -> Union[User, Listener]:
    token = _extract_token(authorization)
    session = db.query(SessionModel).filter(SessionModel.token == token).first()
    if not session:
        raise HTTPException(status_code=401, detail="Invalid session")
    _check_expiry(session, db)
    if session.user_id:
        user = db.query(User).filter(User.id == session.user_id).first()
        if user and user.is_active:
            return user
    if session.listener_id:
        listener = db.query(Listener).filter(Listener.id == session.listener_id).first()
        if listener and listener.is_active:
            return listener
    raise HTTPException(status_code=401, detail="Invalid session")

