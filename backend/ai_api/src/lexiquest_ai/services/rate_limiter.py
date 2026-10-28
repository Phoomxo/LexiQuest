"""Sliding-window per-provider rate limiter.

The limiter sits in front of every provider endpoint in the chain so that a
burst of 150 simultaneous users cannot blow past the lowest provider's RPM
ceiling (e.g. Gemini free tier = 15 RPM). When a key would exceed the window,
the limiter raises ``ProviderRateLimited`` carrying the seconds remaining
until the oldest request in the window falls out — which becomes the
``Retry-After`` we hand back to the client.

Design notes:

* ``threading.Lock`` (not ``RLock``) is sufficient: every method does at most
  one critical section.
* The window is a ``deque`` of request timestamps; on each ``acquire`` we drop
  timestamps older than ``window`` and then decide. This is O(amortised-1)
  per acquire.
* The limiter never blocks; it raises immediately so the caller (the fallback
  chain) can try the next provider instead of stalling a request thread.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from dataclasses import dataclass, field


class ProviderRateLimited(Exception):
    """The provider would exceed its RPM limit if this request proceeded.

    Carries ``retry_after_seconds`` so the caller can honour back-off. Set by
    the limiter from the oldest in-window request, never guessed.
    """

    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__("provider rate limit reached")
        self.retry_after_seconds = max(1, int(retry_after_seconds))


@dataclass
class RateLimiter:
    """Sliding-window limiter keyed by provider endpoint."""

    max_per_minute: int
    window_seconds: float = 60.0
    _clock: callable = field(default=time.monotonic, repr=False)
    _hits: deque = field(default_factory=deque, repr=False)
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def __post_init__(self) -> None:
        if self.max_per_minute <= 0:
            raise ValueError("max_per_minute must be positive")
        if self.window_seconds <= 0:
            raise ValueError("window_seconds must be positive")

    def acquire(self) -> None:
        """Record a request now, or raise ``ProviderRateLimited``.

        Raises immediately on overflow (does not block) so the caller can
        fall through to the next provider.
        """

        now = self._clock()
        cutoff = now - self.window_seconds
        with self._lock:
            # Drop timestamps that have aged out of the window.
            while self._hits and self._hits[0] <= cutoff:
                self._hits.popleft()
            if len(self._hits) >= self.max_per_minute:
                # Time until the oldest in-window hit expires. Ceil so a
                # sub-second wait becomes at least 1 second of Retry-After.
                oldest = self._hits[0]
                wait = oldest + self.window_seconds - now
                raise ProviderRateLimited(
                    retry_after_seconds=int(wait) + 1
                )
            self._hits.append(now)

    def reset(self) -> None:
        """Test-only: clear the window so a fresh burst can be simulated."""

        with self._lock:
            self._hits.clear()


@dataclass
class RateLimitedClient:
    """Wrap an [HttpClient] with one [RateLimiter] per provider URL.

    A separate limiter per URL keeps independent providers independent: hitting
    Ollama's limit must not also block Gemini. Limiters are created lazily so
    only providers actually in use pay bookkeeping cost.
    """

    inner: object
    max_per_minute: int
    _limiters: dict[str, RateLimiter] = field(default_factory=dict, repr=False)
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def request(self, url: str, *, data: bytes, headers: dict[str, str], timeout: float):
        limiter = self._get_or_create(url)
        limiter.acquire()  # raises ProviderRateLimited on overflow
        return self.inner.request(
            url, data=data, headers=headers, timeout=timeout
        )

    def _get_or_create(self, url: str) -> RateLimiter:
        with self._lock:
            limiter = self._limiters.get(url)
            if limiter is None:
                limiter = RateLimiter(max_per_minute=self.max_per_minute)
                self._limiters[url] = limiter
            return limiter
