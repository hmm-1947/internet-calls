from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.database import Base, engine
from app.routers import user_auth, listener_auth, admin, admin_coins, admin_auth, call, chat, listener_notes, gift, billing
from fastapi.staticfiles import StaticFiles
from app.core.database import SessionLocal
from app.models.models import User, Listener

# Base.metadata.create_all(bind=engine)
# test
import os
os.makedirs("recordings", exist_ok=True)
os.makedirs("voice_notes", exist_ok=True)

app = FastAPI(title="Calling App Backend")

app.mount("/recordings", StaticFiles(directory=r"recordings"), name="recordings")
app.mount("/voice_notes", StaticFiles(directory="voice_notes"), name="voice_notes")
app.mount("/panel", StaticFiles(directory="admin_panel", html=True), name="admin_panel")


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(user_auth.router)
app.include_router(listener_auth.router)
app.include_router(admin.router)
app.include_router(admin_coins.router)
app.include_router(admin_auth.router)
app.include_router(call.router)
app.include_router(chat.router)
app.include_router(listener_notes.router)
app.include_router(gift.router)
app.include_router(billing.router)

@app.get("/health")
def health():
    return {"status": "ok"}
    
@app.on_event("startup")
def reset_online_status():
    db = SessionLocal()
    try:
        db.query(User).update({User.is_online: False})
        db.query(Listener).update({Listener.is_online: False})
        db.commit()
    finally:
        db.close()