from livekit import api
from app.core.config import settings
import asyncio

async def delete_room(room_name: str):
    try:
        lkapi = api.LiveKitAPI(settings.livekit_url, settings.livekit_api_key, settings.livekit_api_secret)
        try:
            await asyncio.wait_for(
                lkapi.room.delete_room(api.DeleteRoomRequest(room=room_name)),
                timeout=5,
            )
        finally:
            await lkapi.aclose()
    except Exception as e:
        print(f"[LIVEKIT] delete_room failed for {room_name}: {e}")

def delete_room_background(room_name: str):
    """Fire-and-forget room deletion — never let this block an HTTP response."""
    asyncio.create_task(delete_room(room_name))
