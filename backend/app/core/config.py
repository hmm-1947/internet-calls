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
    razorpay_webhook_secret: str = ""

    web_razorpay_key_id: str = ""
    web_razorpay_key_secret: str = ""
    web_razorpay_webhook_secret: str = ""

    recaptcha_site_key: str = ""
    recaptcha_secret_key: str = ""

    renflair_api_key: str = ""

    # HMAC secret for signing time-limited media URLs (recordings, voice
    # notes) so those files aren't reachable by guessing/leaking a filename.
    # Falls back to admin_secret if not set explicitly, so existing deployments
    # don't need an .env change to pick this fix up.
    media_url_secret: str = ""


    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()