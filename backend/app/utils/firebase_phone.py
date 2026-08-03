from firebase_admin import auth

import app.utils.fcm  # noqa: F401  ensures the firebase app is initialized
from app.utils.phone import normalize_indian_phone  # noqa: F401  re-exported


def verify_phone_token(id_token: str) -> str:
    """Return the phone number Firebase has verified for this ID token."""
    decoded = auth.verify_id_token(id_token)
    phone = decoded.get("phone_number")
    if not phone:
        raise ValueError("Token does not contain a verified phone number")
    return phone
