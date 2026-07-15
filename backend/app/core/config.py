from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    livekit_api_key: str
    livekit_api_secret: str
    livekit_url: str
    firebase_credentials_path: str
    admin_secret: str
    smtp_host: str
    smtp_port: int
    smtp_user: str
    smtp_password: str
    smtp_from_email: str

    razorpay_key_id: str = ""
    razorpay_key_secret: str = ""

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()