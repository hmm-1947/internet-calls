from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from jose import jwt, JWTError
import os
import json

router = APIRouter(prefix="/ws")

SECRET_KEY = os.getenv("SECRET_KEY", "supersecretkey")
ALGORITHM = "HS256"

registry: dict[str, WebSocket] = {}


def get_registry():
    return registry


async def send_to(username: str, message: dict) -> bool:
    ws = registry.get(username)
    if not ws:
        return False
    await ws.send_text(json.dumps(message))
    return True


@router.websocket("/{username}")
async def websocket_endpoint(websocket: WebSocket, username: str, token: str = Query(...)):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("sub") != username:
            await websocket.close(code=4001)
            return
    except JWTError:
        await websocket.close(code=4001)
        return

    await websocket.accept()
    registry[username] = websocket

    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            if message.get("event") == "call_rejected":
                caller = message.get("to")
                if caller:
                    await send_to(caller, {"event": "call_rejected", "from": username})
            elif message.get("event") == "call_accepted":
                caller = message.get("to")
                if caller:
                    await send_to(caller, {"event": "call_accepted", "from": username})
            elif message.get("event") == "call_ended":
                target = message.get("to")
                if target:
                    await send_to(target, {"event": "call_ended", "from": username})
            elif message.get("event") == "chat_message":
                target = message.get("to")

                if target:
                    await send_to(target, message)
    except WebSocketDisconnect:
        registry.pop(username, None)