import time
from typing import Dict
from fastapi import WebSocket

class ConnectionManager:
    def __init__(self):
        self.user_connections: Dict[int, WebSocket] = {}
        self.listener_connections: Dict[int, WebSocket] = {}

    async def connect_user(self, user_id: int, websocket: WebSocket):
        await websocket.accept()
        self.user_connections[user_id] = websocket

    async def connect_listener(self, listener_id: int, websocket: WebSocket):
        await websocket.accept()
        self.listener_connections[listener_id] = websocket

    def disconnect_user(self, user_id: int):
        self.user_connections.pop(user_id, None)

    def disconnect_listener(self, listener_id: int):
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

    def get_online_user_ids(self, user_ids: list) -> list:
        return [uid for uid in user_ids if uid in self.user_connections]

manager = ConnectionManager()