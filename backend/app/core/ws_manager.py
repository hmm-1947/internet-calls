import asyncio
import logging
from datetime import datetime, timezone
from typing import Dict, Iterable
from fastapi import WebSocket

logger = logging.getLogger("ws_manager")

SEND_TIMEOUT_SECONDS = 5


async def _send_with_timeout(ws: WebSocket, data: dict) -> bool:
    try:
        await asyncio.wait_for(ws.send_json(data), timeout=SEND_TIMEOUT_SECONDS)
        return True
    except Exception as e:
        logger.debug(f"websocket send failed: {e!r}")
        return False


class ConnectionManager:
    def __init__(self):
        self.user_connections: Dict[int, WebSocket] = {}
        self.user_tokens: Dict[int, str] = {}
        self.listener_connections: Dict[int, WebSocket] = {}
        self.listener_connected: Dict[int, datetime] = {}
        self.admin_connections: list = []
        self._lock = asyncio.Lock()

    async def connect_admin(self, websocket: WebSocket):
        await websocket.accept()
        async with self._lock:
            self.admin_connections.append(websocket)

    def disconnect_admin(self, websocket: WebSocket):
        if websocket in self.admin_connections:
            self.admin_connections.remove(websocket)

    async def broadcast_to_admins(self, data: dict):
        targets = list(self.admin_connections)
        if not targets:
            return
        results = await asyncio.gather(*(_send_with_timeout(ws, data) for ws in targets))
        for ws, ok in zip(targets, results):
            if not ok:
                self.disconnect_admin(ws)


    async def connect_user(self, user_id: int, websocket: WebSocket, token: str = None):
        await websocket.accept()
        async with self._lock:
            old = self.user_connections.get(user_id)
            self.user_connections[user_id] = websocket
            if token:
                self.user_tokens[user_id] = token
        if old is not None and old is not websocket:
            try:
                await old.close()
            except Exception as e:
                logger.debug(f"connect_user({user_id}): failed closing stale socket: {e}")

    async def connect_listener(self, listener_id: int, websocket: WebSocket):
        await websocket.accept()
        async with self._lock:
            old = self.listener_connections.get(listener_id)
            self.listener_connections[listener_id] = websocket
            if old is None:
                self.listener_connected[listener_id] = datetime.now(timezone.utc)
        if old is not None and old is not websocket:
            try:
                await old.close()
            except Exception as e:
                logger.debug(f"connect_listener({listener_id}): failed closing stale socket: {e}")

    async def disconnect_user(self, user_id: int, websocket: WebSocket = None):
        async with self._lock:
            if websocket is None or self.user_connections.get(user_id) is websocket:
                self.user_connections.pop(user_id, None)
                self.user_tokens.pop(user_id, None)

    async def disconnect_listener(self, listener_id: int, websocket: WebSocket = None):
        async with self._lock:
            if websocket is None or self.listener_connections.get(listener_id) is websocket:
                self.listener_connections.pop(listener_id, None)
                self.listener_connected.pop(listener_id, None)


    def is_user_online(self, user_id: int) -> bool:
        return user_id in self.user_connections

    def is_listener_online(self, listener_id: int) -> bool:
        return listener_id in self.listener_connections

    def listener_connected_at(self, listener_id: int):
        return self.listener_connected.get(listener_id)

    async def send_to_user(self, user_id: int, data: dict):
        ws = self.user_connections.get(user_id)
        if ws and not await _send_with_timeout(ws, data):
            logger.warning(f"send_to_user({user_id}) failed, dropping connection")
            await self.disconnect_user(user_id, ws)

    async def send_to_listener(self, listener_id: int, data: dict):
        ws = self.listener_connections.get(listener_id)
        if ws and not await _send_with_timeout(ws, data):
            logger.warning(f"send_to_listener({listener_id}) failed, dropping connection")
            await self.disconnect_listener(listener_id, ws)

    async def send_to_users(self, user_ids: Iterable[int], data: dict):
        targets = [(uid, self.user_connections[uid]) for uid in user_ids if uid in self.user_connections]
        if not targets:
            return
        results = await asyncio.gather(*(_send_with_timeout(ws, data) for _, ws in targets))
        for (uid, ws), ok in zip(targets, results):
            if not ok:
                await self.disconnect_user(uid, ws)

    def get_online_user_ids(self, user_ids: list) -> list:
        return [uid for uid in user_ids if uid in self.user_connections]

    async def broadcast_to_all_users(self, data: dict):
        targets = list(self.user_connections.values())
        if targets:
            await asyncio.gather(*(_send_with_timeout(ws, data) for ws in targets))

    async def broadcast_to_all_listeners(self, data: dict):
        targets = list(self.listener_connections.values())
        if targets:
            await asyncio.gather(*(_send_with_timeout(ws, data) for ws in targets))


manager = ConnectionManager()