import time
from typing import Dict
from fastapi import WebSocket

class ConnectionManager:
    def __init__(self):
        self.user_connections: Dict[int, WebSocket] = {}
        self.listener_connections: Dict[int, WebSocket] = {}
        self.admin_connections: list = []

    async def connect_admin(self, websocket: WebSocket):
        await websocket.accept()
        self.admin_connections.append(websocket)

    def disconnect_admin(self, websocket: WebSocket):
        if websocket in self.admin_connections:
            self.admin_connections.remove(websocket)

    async def broadcast_to_admins(self, data: dict):
        for ws in list(self.admin_connections):
            try:
                await ws.send_json(data)
            except Exception:
                self.disconnect_admin(ws)

    async def connect_user(self, user_id: int, websocket: WebSocket):
        await websocket.accept()
        self.user_connections[user_id] = websocket

    async def connect_listener(self, listener_id: int, websocket: WebSocket):
        await websocket.accept()
        self.listener_connections[listener_id] = websocket

    def disconnect_user(self, user_id: int, websocket: WebSocket = None):
        if websocket is None or self.user_connections.get(user_id) is websocket:
            self.user_connections.pop(user_id, None)

    def disconnect_listener(self, listener_id: int, websocket: WebSocket = None):
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
            except Exception:
                pass

    async def send_to_listener(self, listener_id: int, data: dict):
        ws = self.listener_connections.get(listener_id)
        if ws:
            try:
                await ws.send_json(data)
            except Exception:
                pass

    def get_online_user_ids(self, user_ids: list) -> list:
        return [uid for uid in user_ids if uid in self.user_connections]

    async def broadcast_to_all_users(self, data: dict):
        for ws in list(self.user_connections.values()):
            try:
                await ws.send_json(data)
            except Exception:
                pass

    async def broadcast_to_all_listeners(self, data: dict):
        for ws in list(self.listener_connections.values()):
            try:
                await ws.send_json(data)
            except Exception:
                pass

manager = ConnectionManager()