import os
import firebase_admin
from firebase_admin import credentials
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import asyncpg
import state

from admin import router as admin_router
from routers.auth import router as auth_router
from routers.messages import router as messages_router
from routers.voice_messages import router as voice_messages_router
from routers.calls import router as calls_router
from routers.recordings import router as recordings_router


cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred)

app = FastAPI()
app.mount("/public", StaticFiles(directory="public"), name="public")

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app.include_router(recordings_router)
app.include_router(admin_router)
app.include_router(auth_router)
app.include_router(messages_router)
app.include_router(voice_messages_router)
app.include_router(calls_router)

DB_URL = os.getenv("DATABASE_URL", "postgresql://calluser:calluser@localhost:5432/callregistry")

@app.on_event("startup")
async def startup():
    state.db_pool = await asyncpg.create_pool(DB_URL)
    async with state.db_pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY, username TEXT UNIQUE NOT NULL,
                password TEXT, created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        await conn.execute("CREATE TABLE IF NOT EXISTS app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS password TEXT")
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT")
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT FALSE")
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'user'")
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS coins INTEGER NOT NULL DEFAULT 0")
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS total_call_duration INTEGER NOT NULL DEFAULT 0")
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_call_duration INTEGER NOT NULL DEFAULT 0")
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id SERIAL PRIMARY KEY, sender TEXT NOT NULL, receiver TEXT NOT NULL,
                content TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        await conn.execute("INSERT INTO app_settings(key,value) VALUES('coins_per_minute','1') ON CONFLICT (key) DO NOTHING")
        await conn.execute("UPDATE users SET is_online=FALSE")
        await conn.execute("ALTER TABLE messages ADD COLUMN IF NOT EXISTS message_type TEXT NOT NULL DEFAULT 'text'")
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS recordings (
                id SERIAL PRIMARY KEY,
                caller TEXT NOT NULL,
                listener TEXT NOT NULL,
                filename TEXT NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
                           
        """)
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS call_logs (
                id SERIAL PRIMARY KEY,
                caller TEXT NOT NULL,
                listener TEXT NOT NULL,
                duration_seconds INTEGER NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """)

@app.on_event("shutdown")
async def shutdown():
    await state.db_pool.close()