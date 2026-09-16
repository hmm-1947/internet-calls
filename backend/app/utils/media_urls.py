"""Signed URLs for serving call recordings and voice notes.

These files used to sit behind a plain, unauthenticated StaticFiles mount
(`/recordings/...`, `/voice_notes/...`) - anyone who obtained or guessed a
filename could download the audio directly, with no login and no check that
they were ever a participant. This module replaces that with short-lived
(or, for voice notes, effectively permanent) HMAC-signed links: the file is
only servable via a URL bearing a valid signature that only the backend can
produce, and only while that signature hasn't expired.

Deliberately URL-based (query-string signature) rather than an
Authorization-header check, because the existing mobile app and admin panel
both fetch this audio via plain <audio src="..."> / http.get with no way to
attach a bearer token to that request. Changing that would require an app
store release; signing the URL itself needs no client changes at all.
"""
import hashlib
import hmac
import time

from app.core.config import settings

_ALLOWED_PREFIXES = {"recordings", "voice_notes"}


def _secret() -> bytes:
    key = settings.media_url_secret or settings.admin_secret
    return key.encode()


def sign_media_url(prefix: str, filename: str, ttl_seconds: int) -> str:
    """Returns a `/media/{prefix}/{filename}?expires=...&sig=...` path.

    `prefix` must be one of the known media directories. `ttl_seconds` is how
    long the link stays valid from now.
    """
    if prefix not in _ALLOWED_PREFIXES:
        raise ValueError(f"Unknown media prefix: {prefix}")
    expires = int(time.time()) + ttl_seconds
    signature = _sign(prefix, filename, expires)
    return f"/media/{prefix}/{filename}?expires={expires}&sig={signature}"


def verify_media_signature(prefix: str, filename: str, expires: int, signature: str) -> bool:
    if prefix not in _ALLOWED_PREFIXES:
        return False
    if expires < int(time.time()):
        return False
    expected = _sign(prefix, filename, expires)
    return hmac.compare_digest(expected, signature)


def _sign(prefix: str, filename: str, expires: int) -> str:
    payload = f"{prefix}/{filename}:{expires}".encode()
    return hmac.new(_secret(), payload, hashlib.sha256).hexdigest()
