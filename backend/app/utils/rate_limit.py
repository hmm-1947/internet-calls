"""Small in-process rate limiter for unauthenticated endpoints.

Endpoints that answer "does this username/phone exist?" are open to anyone, so
without a limit a script can walk through them and harvest which handles and
numbers are registered, and in the phone case make the app burn paid SMS. This
keeps a sliding window of request timestamps per (bucket, client IP) and returns
429 once the window is full.

State lives in the process, so with multiple uvicorn workers the effective limit
is `limit x workers`. That is fine for slowing down abuse; if the deployment ever
grows past a single machine, back this with Redis instead.
"""

import time
from collections import deque
from threading import Lock
from typing import Optional

from fastapi import HTTPException, Request

# Keys untouched for this long are dropped so the table cannot grow forever.
_EVICT_AFTER_SECONDS = 3600
_EVICT_EVERY_CALLS = 500


class _SlidingWindow:
    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = {}
        self._lock = Lock()
        self._calls_since_evict = 0

    def register_hit(self, key: str, limit: int, window_seconds: float) -> Optional[int]:
        """Record a request. Returns None when allowed, else seconds to wait."""
        now = time.monotonic()
        with self._lock:
            hits = self._hits.setdefault(key, deque())
            cutoff = now - window_seconds
            while hits and hits[0] <= cutoff:
                hits.popleft()
            if len(hits) >= limit:
                return max(1, int(hits[0] + window_seconds - now) + 1)
            hits.append(now)
            self._evict_stale(now)
            return None

    def _evict_stale(self, now: float) -> None:
        self._calls_since_evict += 1
        if self._calls_since_evict < _EVICT_EVERY_CALLS:
            return
        self._calls_since_evict = 0
        cutoff = now - _EVICT_AFTER_SECONDS
        for key in [k for k, hits in self._hits.items() if not hits or hits[-1] <= cutoff]:
            del self._hits[key]

    def reset(self) -> None:
        """Only used by tests."""
        with self._lock:
            self._hits.clear()
            self._calls_since_evict = 0


_window = _SlidingWindow()


def client_ip(request: Request) -> str:
    """Best-effort caller identity.

    X-Forwarded-For is only meaningful when a reverse proxy sets it; a direct
    caller can spoof it, which is why the limits below stay generous enough for
    real users and are a speed bump rather than an access control.
    """
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def rate_limit(bucket: str, limit: int, window_seconds: int):
    """FastAPI dependency that allows `limit` requests per `window_seconds` per IP."""

    def dependency(request: Request) -> None:
        enforce_rate_limit(bucket, client_ip(request), limit, window_seconds)

    return dependency


def enforce_rate_limit(
    bucket: str,
    key: str,
    limit: int,
    window_seconds: int,
    detail: str = "Too many requests. Please wait a moment and try again.",
) -> None:
    """Rate limit on an arbitrary key, for use inside an endpoint body.

    An IP limit alone does not stop someone from mailing OTP after OTP to one
    address from a pool of IPs, so OTP sends are limited per identifier too.
    """
    retry_after = _window.register_hit(f"{bucket}:{key}", limit, window_seconds)
    if retry_after is not None:
        raise HTTPException(
            status_code=429,
            detail=detail,
            headers={"Retry-After": str(retry_after)},
        )
