from fastapi import WebSocket
from typing import Dict
import json

class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[int, WebSocket] = {}

    async def connect(self, user_id: int, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[user_id] = websocket

    def disconnect(self, user_id: int):
        if user_id in self.active_connections:
            del self.active_connections[user_id]

    async def send_personal_message(self, message: dict, user_id: int) -> bool:
        websocket = self.active_connections.get(user_id)
        if websocket:
            try:
                await websocket.send_text(json.dumps(message))
                return True
            except Exception:
                self.disconnect(user_id)
                return False
        return False

    async def broadcast_status(self, message: dict, sender_id: int):
        inactive_users = []
        for user_id, websocket in self.active_connections.items():
            if user_id != sender_id:
                try:
                    await websocket.send_text(json.dumps(message))
                except Exception as e:
                    print(f"Error broadcasting to user {user_id}: {e}")
                    inactive_users.append(user_id)
        
        for user_id in inactive_users:
            self.disconnect(user_id)

manager = ConnectionManager()
