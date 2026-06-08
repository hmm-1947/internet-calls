from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import state
import math

router = APIRouter()

class RegisterRequest(BaseModel):
    username: str
    password: str
    role: str

class LoginRequest(BaseModel):
    username: str
    password: str
    app_type: str = "user"

class SaveFCMRequest(BaseModel):
    username: str
    token: str

@router.post("/register")
async def register_user(req: RegisterRequest):
    username = req.username.strip().lower()
    if not username or len(username) < 2:
        raise HTTPException(status_code=400, detail="Username too short")
    if len(username) > 24:
        raise HTTPException(status_code=400, detail="Username too long")
    try:
        async with state.db_pool.acquire() as conn:
            existing = await conn.fetchrow("SELECT username FROM users WHERE username=$1", username)
            if existing:
                raise HTTPException(status_code=409, detail="Username already taken")
            await conn.execute(
                "INSERT INTO users (username, password, role) VALUES ($1, $2, $3)",
                username, req.password, req.role
            )
        return {"status": "ok", "username": username, "role": req.role}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/login")
async def login_user(req: LoginRequest):
    username = req.username.strip().lower()
    async with state.db_pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT username, role FROM users WHERE username=$1 AND password=$2",
            username, req.password,
        )
    if row and req.app_type == "user" and row["role"] == "listener":
        raise HTTPException(status_code=401, detail="Invalid username or password")
    if row and req.app_type == "listener" and row["role"] == "user":
        raise HTTPException(status_code=401, detail="Invalid username or password")
    if row:
        return {"status": "ok", "username": row["username"], "role": row["role"]}
    raise HTTPException(status_code=401, detail="Invalid username or password")

@router.post("/save_fcm")
async def save_fcm(req: SaveFCMRequest):
    username = req.username.strip().lower()
    async with state.db_pool.acquire() as conn:
        await conn.execute("UPDATE users SET fcm_token=$1 WHERE username=$2", req.token, username)
    return {"status": "ok"}

@router.get("/profile/{username}")
async def get_profile(username: str):
    async with state.db_pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT username, coins, role, total_call_duration FROM users WHERE username=$1",
            username.strip().lower()
        )
        if not row:
            raise HTTPException(status_code=404)
        
        top_users = await conn.fetch(
            """
            SELECT CASE WHEN caller=$1 THEN listener ELSE caller END as other_user,
                   SUM(duration_seconds) as total_seconds
            FROM call_logs
            WHERE caller=$1 OR listener=$1
            GROUP BY other_user
            ORDER BY total_seconds DESC
            LIMIT 3
            """,
            username.strip().lower()
        )

    return {
        "username": row["username"],
        "coins": row["coins"],
        "role": row["role"],
        "total_call_duration": row["total_call_duration"],
        "top_users": [
            {"username": r["other_user"], "minutes": math.ceil(r["total_seconds"] / 60)}
            for r in top_users
        ]
    }
@router.get("/user/{username}")
async def check_user(username: str):
    username = username.strip().lower()
    async with state.db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT username, coins FROM users WHERE username=$1", username)
    if row:
        return {"exists": True, "username": row["username"], "coins": row["coins"]}
    raise HTTPException(status_code=404, detail="User not found")

@router.get("/listeners")
async def listeners():
    async with state.db_pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT username, is_online FROM users WHERE role='listener' ORDER BY username"
        )
    return [{"username": r["username"], "online": r["is_online"]} for r in rows]

@router.get("/users")
async def list_users():
    async with state.db_pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT username, is_online FROM users WHERE role='user' ORDER BY username"
        )
    return [{"username": r["username"], "online": r["is_online"]} for r in rows]