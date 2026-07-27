import asyncio
import logging
import time
from typing import Dict
from fastapi import WebSocket

logger = logging.getLogger("ws_manager")

class ConnectionManager:
    def __init__(self):
        self.user_connections: Dict[int, WebSocket] = {}
        self.listener_connections: Dict[int, WebSocket] = {}
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
        for ws in list(self.admin_connections):
            try:
                await ws.send_json(data)
            except Exception as e:
                logger.debug(f"broadcast_to_admins: dropping dead connection: {e}")
                self.disconnect_admin(ws)


    async def connect_user(self, user_id: int, websocket: WebSocket):
        await websocket.accept()
        async with self._lock:
            old = self.user_connections.get(user_id)
            self.user_connections[user_id] = websocket
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
        if old is not None and old is not websocket:
            try:
                await old.close()
            except Exception as e:
                logger.debug(f"connect_listener({listener_id}): failed closing stale socket: {e}")

    async def disconnect_user(self, user_id: int, websocket: WebSocket = None):
        async with self._lock:
            if websocket is None or self.user_connections.get(user_id) is websocket:
                self.user_connections.pop(user_id, None)

    async def disconnect_listener(self, listener_id: int, websocket: WebSocket = None):
        async with self._lock:
            if websocket is None or self.listener_connections.get(listener_id) is websocket:
                self.listener_connections.pop(listener_id, None)


    def is_user_online(self, user_id: int) -> bool:
        return user_id in self.user_connections

    def is_listener_online(self, listener_id: int) -> bool:
        return listener_id in self.listener_connections

    async def send_to_user(self, user_id: int, data: dict):
        ws = self.user_connections.get(user_id)
        if ws:
            try:
                await ws.send_json(data)
            except Exception as e:
                logger.warning(f"send_to_user({user_id}) failed: {e}")
                await self.disconnect_user(user_id, ws)

    async def send_to_listener(self, listener_id: int, data: dict):
        ws = self.listener_connections.get(listener_id)
        if ws:
            try:
                await ws.send_json(data)
            except Exception as e:
                logger.warning(f"send_to_listener({listener_id}) failed: {e}")
                await self.disconnect_listener(listener_id, ws)


    def get_online_user_ids(self, user_ids: list) -> list:
        return [uid for uid in user_ids if uid in self.user_connections]

    async def broadcast_to_all_users(self, data: dict):
        for ws in list(self.user_connections.values()):
            try:
                await ws.send_json(data)
            except Exception as e:
                logger.debug(f"broadcast_to_all_users: dropping dead connection: {e}")

    async def broadcast_to_all_listeners(self, data: dict):
        for ws in list(self.listener_connections.values()):
            try:
                await ws.send_json(data)
            except Exception as e:
                logger.debug(f"broadcast_to_all_listeners: dropping dead connection: {e}")


manager = ConnectionManager()