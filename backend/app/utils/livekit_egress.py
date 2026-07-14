from livekit import api
from app.core.config import settings

async def start_recording(room_name: str, output_path: str) -> str:
    lkapi = api.LiveKitAPI(settings.livekit_url, settings.livekit_api_key, settings.livekit_api_secret)
    req = api.RoomCompositeEgressRequest(
        room_name=room_name,
        audio_only=True,
        file_outputs=[api.EncodedFileOutput(filepath=output_path)],
    )
    res = await lkapi.egress.start_room_composite_egress(req)
    await lkapi.aclose()
    return res.egress_id

async def stop_recording(egress_id: str):
    lkapi = api.LiveKitAPI(settings.livekit_url, settings.livekit_api_key, settings.livekit_api_secret)
    await lkapi.egress.stop_egress(api.StopEgressRequest(egress_id=egress_id))
    await lkapi.aclose()