import asyncpg
import os

from dotenv import load_dotenv
from pathlib import Path

load_dotenv(Path(__file__).parent / ".env")
DATABASE_URL = os.getenv("DATABASE_URL")

pool: asyncpg.Pool = None

async def get_pool():
    return pool


async def connect():
    global pool

    print("DATABASE_URL =", DATABASE_URL)

    pool = await asyncpg.create_pool(DATABASE_URL)

    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT current_database(), current_user
        """)
        print("DB INFO:", row)

async def disconnect():
    await pool.close()