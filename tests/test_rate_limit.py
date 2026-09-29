from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend import rate_limit
from backend.rate_limit import RateLimitMiddleware, SlidingWindowRateLimiter


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def _build_app(limiter: SlidingWindowRateLimiter) -> FastAPI:
    test_app = FastAPI()
    test_app.add_middleware(RateLimitMiddleware, limiter=limiter)

    @test_app.get("/health")
    def health() -> dict:
        return {"status": "ok"}

    @test_app.get("/stations")
    def stations() -> dict:
        return {"stations": []}

    return test_app


def test_allows_requests_up_to_limit():
    limiter = SlidingWindowRateLimiter(2, clock=FakeClock())
    assert limiter.check("client")[0] is True
    assert limiter.check("client")[0] is True
    allowed, retry_after = limiter.check("client")
    assert allowed is False
    assert retry_after >= 1


def test_window_slides_after_expiry():
    clock = FakeClock()
    limiter = SlidingWindowRateLimiter(1, window_seconds=60.0, clock=clock)
    assert limiter.check("client")[0] is True
    assert limiter.check("client")[0] is False
    clock.now = 60.0
    assert limiter.check("client")[0] is True


def test_clients_are_isolated():
    limiter = SlidingWindowRateLimiter(1, clock=FakeClock())
    assert limiter.check("a")[0] is True
    assert limiter.check("a")[0] is False
    assert limiter.check("b")[0] is True


def test_stale_clients_are_pruned(monkeypatch):
    monkeypatch.setattr(rate_limit, "MAX_TRACKED_CLIENTS", 2)
    clock = FakeClock()
    limiter = SlidingWindowRateLimiter(5, window_seconds=60.0, clock=clock)
    assert limiter.check("a")[0] is True
    assert limiter.check("b")[0] is True
    clock.now = 120.0
    assert limiter.check("c")[0] is True
    assert limiter.check("d")[0] is True
    assert len(limiter._hits) <= 2


def test_middleware_returns_429_and_exempts_health():
    limiter = SlidingWindowRateLimiter(1)
    client = TestClient(_build_app(limiter))
    assert client.get("/health").status_code == 200
    assert client.get("/health").status_code == 200
    assert client.get("/stations").status_code == 200
    blocked = client.get("/stations")
    assert blocked.status_code == 429
    assert "Retry-After" in blocked.headers


def test_forwarded_headers_identify_clients():
    limiter = SlidingWindowRateLimiter(1)
    client = TestClient(_build_app(limiter))
    first = client.get("/stations", headers={"x-forwarded-for": "1.1.1.1, 2.2.2.2"})
    assert first.status_code == 200
    second = client.get("/stations", headers={"x-forwarded-for": "3.3.3.3"})
    assert second.status_code == 200
    third = client.get("/stations", headers={"x-forwarded-for": "1.1.1.1, 9.9.9.9"})
    assert third.status_code == 429
