import logging
import re

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.database import Base, engine
from app.routers import user_auth, listener_auth, admin, admin_coins, admin_auth, call, chat, listener_notes, gift, billing, app_settings, special_offers, weekly_challenge, withdrawals, notifications, media
from fastapi.staticfiles import StaticFiles
from app.core.database import SessionLocal
from app.models.models import User, Listener
from app.utils.livekit_egress import start_egress_worker, stop_egress_worker

# Base.metadata.create_all(bind=engine)
# test
import os
os.makedirs("recordings", exist_ok=True)
os.makedirs("voice_notes", exist_ok=True)
os.makedirs("profile_photos", exist_ok=True)
os.makedirs("gift_icons", exist_ok=True)
os.makedirs("ringtones", exist_ok=True)
os.makedirs("upgrade_banners", exist_ok=True)
os.makedirs("special_offers", exist_ok=True)


def _configure_app_logging() -> None:
    """Make the app's own presence/websocket loggers visible on the uvicorn
    console. Without a handler Python only surfaces WARNING and above, so the
    INFO lines for "user X connected/disconnected" were silently dropped.
    uvicorn itself (websockets sans-I/O backend) logs "connection open" but
    never "connection closed", so these are the only disconnect logs there are."""
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(levelname)s:     %(message)s"))
    for name in ("chat_ws", "ws_manager"):
        app_logger = logging.getLogger(name)
        if not app_logger.handlers:
            app_logger.addHandler(handler)
        app_logger.setLevel(logging.INFO)
        app_logger.propagate = False


_configure_app_logging()


_TOKEN_QS = re.compile(r"((?:token|sig|authorization)=)[^&\s\"']+", re.IGNORECASE)


class _RedactTokens(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.msg, str):
            record.msg = _TOKEN_QS.sub(r"\1***", record.msg)
        if isinstance(record.args, tuple):
            record.args = tuple(_TOKEN_QS.sub(r"\1***", a) if isinstance(a, str) else a for a in record.args)
        return True


for _name in ("uvicorn", "uvicorn.error", "uvicorn.access", "websockets", "websockets.server"):
    logging.getLogger(_name).addFilter(_RedactTokens())

app = FastAPI(title="Calling App Backend")

# /recordings and /voice_notes used to be public StaticFiles mounts here -
# anyone who obtained/guessed a filename could download that call's audio or
# a voice note directly, no login required. Both are now served only through
# app.routers.media, behind a signed, time-limited URL (see media_urls.py).
app.mount("/profile_photos", StaticFiles(directory="profile_photos"), name="profile_photos")
app.mount("/gift_icons", StaticFiles(directory="gift_icons"), name="gift_icons")
app.mount("/ringtones", StaticFiles(directory="ringtones"), name="ringtones")
app.mount("/upgrade_banners", StaticFiles(directory="upgrade_banners"), name="upgrade_banners")
app.mount("/special_offers", StaticFiles(directory="special_offers"), name="special_offers")
app.mount("/assets", StaticFiles(directory="app/assets"), name="assets")

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
app.include_router(withdrawals.listener_router)
app.include_router(withdrawals.admin_router)
app.include_router(notifications.router)
app.include_router(gift.router)
app.include_router(billing.router)
app.include_router(app_settings.router)
app.include_router(special_offers.router)
app.include_router(weekly_challenge.router)
app.include_router(media.router)

@app.get("/health")
def health():
    return {"status": "ok"}

_WEBAPP_DIST = os.environ.get("USER_WEBAPP_DIST") or os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "userwebapp", "dist")
)
if os.path.isdir(_WEBAPP_DIST):
    app.mount("/app", StaticFiles(directory=_WEBAPP_DIST, html=True), name="userwebapp")

app.mount("/", StaticFiles(directory="landing", html=True), name="landing")

    
@app.on_event("startup")
def reset_online_status():
    """`User.is_online` mirrors a live websocket, so it is stale after a restart
    and gets cleared. Listener presence is not socket-based: it is stored
    (`is_logged_in`, `is_online`, `admin_forced_offline`) and survives restarts."""
    db = SessionLocal()
    try:
        db.query(User).update({User.is_online: False})
        db.commit()
    finally:
        db.close()


@app.on_event("startup")
async def start_egress_start_worker():
    """Starts the single background worker that drains queued egress-start
    requests one at a time with spacing between LiveKit calls. See
    app/utils/livekit_egress.py for why this exists."""
    start_egress_worker()


@app.on_event("shutdown")
async def stop_egress_start_worker():
    stop_egress_worker()