import secrets
import logging
import requests
from app.core.config import settings

logger = logging.getLogger("sms_otp")

RENFLAIR_URL = "https://sms.renflair.in/V1.php"


def generate_otp_code() -> str:
    return str(secrets.randbelow(9000) + 1000)


def send_otp_sms(phone: str, otp_code: str) -> bool:
    params = {
        "API": settings.renflair_api_key,
        "PHONE": phone,
        "OTP": otp_code,
    }
    try:
        resp = requests.get(RENFLAIR_URL, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        logger.info(f"Renflair OTP response for {phone}: {data}")
        # Renflair can return 200 with a body that says the send itself
        # failed (bad number, out of credits, etc). Treat anything that
        # isn't an explicit success as a failure so callers don't tell the
        # user an OTP is on its way when it never left the server.
        status = str(data.get("STATUS") or data.get("status") or "").strip().lower()
        if status and status not in ("success", "ok", "sent", "1", "true"):
            logger.warning(f"Renflair OTP send reported failure for {phone}: {data}")
            return False
        return True
    except Exception as e:
        logger.exception(f"Failed to send OTP SMS to {phone}: {e}")
        return False
