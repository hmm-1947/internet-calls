import secrets
import hashlib
import base64
import bcrypt


def _prehash(password: str) -> bytes:
    """
    SHA-256 pre-hash then base64-encode the password before passing to bcrypt.
    This removes bcrypt's 72-byte limit while maintaining full cryptographic strength.
    (Same approach used by Django's BCryptSHA256PasswordHasher.)
    """
    digest = hashlib.sha256(password.encode("utf-8")).digest()
    return base64.b64encode(digest)  # always 44 bytes, well within bcrypt's 72-byte limit


def hash_password(password: str) -> str:
    hashed = bcrypt.hashpw(_prehash(password), bcrypt.gensalt())
    return hashed.decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(_prehash(plain_password), hashed_password.encode("utf-8"))


def generate_session_token() -> str:
    return secrets.token_hex(32)

