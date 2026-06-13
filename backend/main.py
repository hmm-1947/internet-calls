import asyncio
import sys
from fastapi import FastAPI
from database import connect, disconnect, get_pool
from models import ALL_TABLES
from dotenv import load_dotenv
from routers.chats import router as chats_router

load_dotenv()

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

app = FastAPI()

app.include_router(chats_router)

from routers.auth import router as auth_router
app.include_router(auth_router)

from routers.livekit import router as livekit_router
app.include_router(livekit_router)

from routers.websocket import router as ws_router
app.include_router(ws_router)

from routers.admin import router as admin_router
app.include_router(admin_router)

from routers.coins import router as coin_router
app.include_router(coin_router)

from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup():
    await connect()
    pool = await get_pool()
    async with pool.acquire() as conn:
        for query in ALL_TABLES:
            await conn.execute(query)

@app.on_event("shutdown")
async def shutdown():
    await disconnect()