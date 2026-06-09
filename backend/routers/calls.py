import json
import asyncio
import math
import time

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
import firebase_admin.messaging as messaging
import state

router = APIRouter()

async def send_push(token, caller):
    message = messaging.Message(
        data={"type": "incoming_call", "caller": caller},
        android=messaging.AndroidConfig(
            priority="high",
            ttl=30,
        ),
        token=token,
    )
    try:
        response = messaging.send(message)
        print("FCM:", response)
        return True
    except messaging.UnregisteredError:
        async with state.db_pool.acquire() as conn:
            await conn.execute("UPDATE users SET fcm_token=NULL WHERE fcm_token=$1", token)
        return False
    except Exception as e:
        print(f"[FCM] Send failed: {e}")
        return False

async def monitor_call(caller):
    while True:
        await asyncio.sleep(5)
        
        if caller not in state.call_sessions:
            break

        session = state.call_sessions.get(caller)
        if not session:
            break

        async with state.db_pool.acquire() as conn:
            user = await conn.fetchrow("SELECT coins FROM users WHERE username=$1", caller)
            setting = await conn.fetchrow("SELECT value FROM app_settings WHERE key='coins_per_minute'")

        if not user or not setting:
            break

        coins_per_minute = max(1, int(setting["value"]))
        elapsed_minutes = math.ceil((time.time() - session["started"]) / 60)
        coins_needed = elapsed_minutes * coins_per_minute

        if user["coins"] < coins_needed:
            listener = session["listener"]
            
            # deduct coins before clearing session
            duration_seconds = int(time.time() - session["started"])
            async with state.db_pool.acquire() as conn:
                setting2 = await conn.fetchrow("SELECT value FROM app_settings WHERE key='coins_per_minute'")
                cpm = int(setting2["value"])
                coins_used = math.ceil(duration_seconds / 60) * cpm
                await conn.execute(
                    "UPDATE users SET coins=GREATEST(coins-$1,0) WHERE username=$2",
                    coins_used, caller
                )
                await conn.execute(
                    "UPDATE users SET total_call_duration=total_call_duration+$1, daily_call_duration=daily_call_duration+$1 WHERE username=$2",
                    duration_seconds, caller
                )
                
                await conn.execute(
                    "INSERT INTO call_logs (caller, listener, duration_seconds) VALUES ($1, $2, $3)",
                    caller, listener, duration_seconds
                )

            session["charged"] = True

            for uid in [caller, listener]:
                if uid in state.clients:
                    try:
                        await state.clients[uid].send_text(json.dumps({
                            "type": "error",
                            "message": "Not enough coins to continue the call"
                        }))
                        await state.clients[uid].send_text(json.dumps({
                            "from": uid,
                            "data": {"type": "hangup"}
                        }))
                    except RuntimeError:
                        state.clients.pop(uid, None)

            state.active_calls.pop(caller, None)
            state.active_calls.pop(listener, None)
            state.call_sessions.pop(caller, None)
            break

async def _try_fcm_fallback(ws, client_id, target, offer_data):
    async with state.db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT fcm_token FROM users WHERE username=$1", target.lower())
    if row and row["fcm_token"]:
        state.pending_offers[target] = {"from": client_id, "data": offer_data}
        sent = await send_push(row["fcm_token"], client_id)
        if sent:
            await ws.send_text(json.dumps({"type": "ringing", "target": target}))
        else:
            state.pending_offers.pop(target, None)
            await ws.send_text(json.dumps({"type": "error", "message": f"User '{target}' is not online"}))
    else:
        await ws.send_text(json.dumps({"type": "error", "message": f"User '{target}' is not online"}))

@router.get("/test_push/{username}")
async def test_push(username: str):
    async with state.db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT fcm_token FROM users WHERE username=$1", username.lower())
    if not row:
        raise HTTPException(404)
    await send_push(row["fcm_token"], "Joshua")
    return {"status": "sent"}

@router.get("/users/{username}/coins")
async def get_coins(username: str):
    async with state.db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT coins FROM users WHERE username=$1", username.lower())
    if not row:
        raise HTTPException(404)
    return {"coins": row["coins"]}

@router.websocket("/ws/{client_id}")
async def websocket_endpoint(ws: WebSocket, client_id: str):
    await ws.accept()
    state.clients[client_id] = ws
    async with state.db_pool.acquire() as conn:
        await conn.execute("UPDATE users SET is_online=TRUE WHERE username=$1", client_id)

    try:
        await ws.send_text(json.dumps({"type": "connected", "id": client_id}))
    except (WebSocketDisconnect, OSError):
        state.clients.pop(client_id, None)
        async with state.db_pool.acquire() as conn:
            await conn.execute("UPDATE users SET is_online=FALSE WHERE username=$1", client_id)
        return

    if client_id in state.pending_offers:
        offer = state.pending_offers.pop(client_id)
        await ws.send_text(json.dumps({"from": offer["from"], "data": offer["data"]}))

    try:
        while True:
            raw = await ws.receive_text()
            message = json.loads(raw)
            if message.get("type") == "chat_message":
                chat_target = message.get("target")
                content = message.get("content")
                message_type = message.get("message_type", "text")
                if chat_target and content and chat_target in state.clients:
                    try:
                        await state.clients[chat_target].send_text(json.dumps({
                            "type": "chat_message",
                            "from": client_id,
                            "content": content,
                            "message_type": message_type,
                        }))
                    except RuntimeError:
                        state.clients.pop(chat_target, None)
                continue
            target = message.get("target")
            msg_type = message.get("data", {}).get("type", "")

            if msg_type == "offer":
                if not target:
                    await ws.send_text(json.dumps({"type": "error", "message": "No target specified"}))
                    continue
                async with state.db_pool.acquire() as conn:
                    caller = await conn.fetchrow("SELECT role FROM users WHERE username=$1", client_id.lower())
                    receiver = await conn.fetchrow("SELECT role FROM users WHERE username=$1", target.lower())
                    row = await conn.fetchrow("SELECT coins FROM users WHERE username=$1", client_id)

                if not caller or not receiver:
                    await ws.send_text(json.dumps({"type": "error", "message": "Invalid users"}))
                    continue
                if caller["role"] != "user":
                    await ws.send_text(json.dumps({"type": "error", "message": "Only users can initiate calls"}))
                    continue
                if receiver["role"] != "listener":
                    await ws.send_text(json.dumps({"type": "error", "message": "You can only call listeners"}))
                    continue
                if row["coins"] < 1:
                    await ws.send_text(json.dumps({"type": "error", "message": "Not enough coins"}))
                    continue

                if target in state.clients:
                    try:
                        await state.clients[target].send_text(json.dumps({
                            "type": "incoming_call", "from": client_id, "data": message["data"]
                        }))
                        await ws.send_text(json.dumps({"type": "ringing", "target": target}))
                    except Exception:
                        state.clients.pop(target, None)
                        await _try_fcm_fallback(ws, client_id, target, message["data"])
                else:
                    await _try_fcm_fallback(ws, client_id, target, message["data"])

            elif msg_type == "answer":
                print(f"[ANSWER] listener={client_id} user={target}")
                print(f"[ANSWER] target in clients: {target in state.clients}")
                state.active_calls[client_id] = target
                state.active_calls[target] = client_id
                state.call_sessions[target] = {"listener": client_id, "started": time.time(), "charged": False}
                asyncio.create_task(monitor_call(target))
                if target in state.clients:
                    await state.clients[target].send_text(json.dumps({"from": client_id, "data": message["data"]}))
            elif msg_type == "video_offer":
                async with state.db_pool.acquire() as conn:
                    caller = await conn.fetchrow("SELECT role FROM users WHERE username=$1", client_id.lower())
                    receiver = await conn.fetchrow("SELECT role FROM users WHERE username=$1", target.lower())
                    row = await conn.fetchrow("SELECT coins FROM users WHERE username=$1", client_id)
                if not caller or not receiver:
                    await ws.send_text(json.dumps({"type": "error", "message": "Invalid users"}))
                    continue
                if caller["role"] != "user":
                    await ws.send_text(json.dumps({"type": "error", "message": "Only users can initiate calls"}))
                    continue
                print("========== CALL DEBUG ==========")
                print("client_id:", client_id)
                print("target:", target)
                print("caller role:", caller["role"] if caller else None)
                print("receiver role:", receiver["role"] if receiver else None)
                print("message:", message)
                print("================================")
                if receiver["role"] != "listener":
                    await ws.send_text(json.dumps({"type": "error", "message": "You can only call listeners"}))
                    continue
                if row["coins"] < 1:
                    await ws.send_text(json.dumps({"type": "error", "message": "Not enough coins"}))
                    continue
                if target in state.clients:
                    await state.clients[target].send_text(json.dumps({
                        "type": "incoming_call", "from": client_id, "data": message["data"]
                    }))
                else:
                    await ws.send_text(json.dumps({"type": "error", "message": f"User '{target}' is not online"}))

            elif msg_type in ["video_answer", "video_candidate", "video_hangup"]:
                if target in state.clients:
                    await state.clients[target].send_text(json.dumps({"from": client_id, "data": message["data"]}))

            elif msg_type in ["hangup", "call_ended"]:
                other = state.active_calls.pop(client_id, None)
                session = state.call_sessions.pop(client_id, None)

                if not session:
                    for user, data in list(state.call_sessions.items()):
                        if data["listener"] == client_id:
                            session = data
                            state.call_sessions.pop(user, None)
                            client_id = user
                            break

                if session and not session.get("charged"):
                    session["charged"] = True
                    duration_seconds = int(time.time() - session["started"])
                    async with state.db_pool.acquire() as conn:
                        setting = await conn.fetchrow("SELECT value FROM app_settings WHERE key='coins_per_minute'")
                        coins_per_minute = int(setting["value"])
                        coins_used = math.ceil(duration_seconds / 60) * coins_per_minute
                        await conn.execute(
                            "UPDATE users SET coins=GREATEST(coins-$1,0) WHERE username=$2",
                            coins_used, client_id
                        )
                        await conn.execute(
                            "UPDATE users SET total_call_duration=total_call_duration+$1, daily_call_duration=daily_call_duration+$1 WHERE username=$2",
                            duration_seconds, client_id
                        )

                        await conn.execute(
                            "INSERT INTO call_logs (caller, listener, duration_seconds) VALUES ($1, $2, $3)",
                            client_id, session["listener"], duration_seconds
                        )

                if other:
                    state.active_calls.pop(other, None)
                if target in state.clients:
                    try:
                        await state.clients[target].send_text(json.dumps({"from": client_id, "data": message["data"]}))
                    except RuntimeError:
                        state.clients.pop(target, None)

            elif target in state.clients:
                print(f"[RELAY] type={msg_type} from={client_id} to={target}")
                try:
                    await state.clients[target].send_text(json.dumps({"from": client_id, "data": message["data"]}))
                except Exception:
                    state.clients.pop(target, None)
            else:
                print(f"[RELAY_FAIL] type={msg_type} from={client_id} to={target} | target_online={target in state.clients}")

    except (WebSocketDisconnect, OSError, Exception):
        other = state.active_calls.pop(client_id, None)
        if other:
            state.active_calls.pop(other, None)
        state.clients.pop(client_id, None)
        try:
            async with state.db_pool.acquire() as conn:
                await conn.execute("UPDATE users SET is_online=FALSE WHERE username=$1", client_id)
        except Exception:
            pass