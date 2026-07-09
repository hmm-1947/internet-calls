from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    livekit_api_key: str
    livekit_api_secret: str
    livekit_url: str
    firebase_credentials_path: str
    admin_secret: str

    class Config:
        env_file = ".env"

settings = Settings()
