from __future__ import annotations

import os
import threading
import time
from collections import defaultdict, deque
from typing import Callable

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.types import ASGIApp

DEFAULT_LIMIT_PER_MINUTE = 120
WINDOW_SECONDS = 60.0
MAX_TRACKED_CLIENTS = 10_000
EXEMPT_PATHS = frozenset({"/health"})


class SlidingWindowRateLimiter:
    def __init__(
        self,
        limit_per_minute: int,
        window_seconds: float = WINDOW_SECONDS,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if limit_per_minute < 1:
            raise ValueError("limit_per_minute must be at least 1")
        self.limit = limit_per_minute
        self.window = window_seconds
        self._clock = clock
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def check(self, client_key: str) -> tuple[bool, int]:
        now = self._clock()
        with self._lock:
            hits = self._hits[client_key]
            while hits and now - hits[0] >= self.window:
                hits.popleft()
            if len(hits) >= self.limit:
                retry_after = max(1, int(self.window - (now - hits[0])) + 1)
                return False, retry_after
            hits.append(now)
            if len(self._hits) > MAX_TRACKED_CLIENTS:
                self._prune(now)
            return True, 0

    def _prune(self, now: float) -> None:
        stale = [
            key
            for key, hits in self._hits.items()
            if not hits or now - hits[-1] >= self.window
        ]
        for key in stale:
            del self._hits[key]


def _client_key(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        first = forwarded.split(",")[0].strip()
        if first:
            return first
    if request.client is not None and request.client.host:
        return request.client.host
    return "unknown"


def rate_limit_from_env() -> SlidingWindowRateLimiter:
    raw = os.getenv("RATE_LIMIT_PER_MINUTE", str(DEFAULT_LIMIT_PER_MINUTE))
    try:
        limit = int(raw)
    except ValueError:
        limit = DEFAULT_LIMIT_PER_MINUTE
    return SlidingWindowRateLimiter(limit)


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app: ASGIApp, limiter: SlidingWindowRateLimiter) -> None:
        super().__init__(app)
        self.limiter = limiter

    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        if request.url.path in EXEMPT_PATHS:
            return await call_next(request)
        allowed, retry_after = self.limiter.check(_client_key(request))
        if not allowed:
            return JSONResponse(
                status_code=429,
                content={"detail": "Too many requests. Please try again shortly."},
                headers={"Retry-After": str(retry_after)},
            )
        return await call_next(request)
