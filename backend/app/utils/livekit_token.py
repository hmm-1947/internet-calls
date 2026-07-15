#livekit_token.py
from livekit import api
from app.core.config import settings

def generate_token(room_name: str, identity: str, name: str) -> str:
    token = api.AccessToken(settings.livekit_api_key, settings.livekit_api_secret)
    token = token.with_identity(identity).with_name(name).with_grants(
        api.VideoGrants(room_join=True, room=room_name)
    )
    return token.to_jwt()