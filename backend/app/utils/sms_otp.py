import random
import logging
import requests
from app.core.config import settings

logger = logging.getLogger("sms_otp")

RENFLAIR_URL = "https://sms.renflair.in/V1.php"


def generate_otp_code() -> str:
    return str(random.randint(1000, 9999))


def send_otp_sms(phone: str, otp_code: str) -> bool:
    params = {
        "API": settings.renflair_api_key,
        "PHONE": phone,
        "OTP": otp_code,
    }
    try:
        resp = requests.get(RENFLAIR_URL, params=params, timeout=10)
        data = resp.json()
        logger.info(f"Renflair OTP response for {phone}: {data}")
        return True
    except Exception as e:
        logger.exception(f"Failed to send OTP SMS to {phone}: {e}")
        return False
