"""Deterministic, bounded in-memory response cache for generated content.

This is the **primary cost-control mechanism** for the AI API. Repeated
requests for the same ``(text, kind, cefr, language, model_version)`` tuple
are served from memory instead of calling the LLM provider, so the recurring
cost of generating, say, an example sentence for the word "cat" at A1 is paid
exactly once.

Design notes:

* Keys are a deterministic SHA-256 over a stable canonical string, mirroring
  ``VoiceAudioCacheKey`` on the Flutter side.
* Eviction is LRU bounded by entry count. Byte-size bounding is intentionally
  omitted because generated text is small and bounded by ``llm_max_tokens``;
  per-entry bytes would add bookkeeping for negligible benefit.
* TTL is wall-clock and is checked lazily on read.
* Values are stored as ``ContentResult`` with ``cached`` rewritten to ``True``
  on read so callers can attribute hits.
* The cache stores only generated text and metadata that the client already
  sent in the request. It never stores the user identity, the bearer token,
  or any personally identifying input beyond the request text the user typed.
"""

from __future__ import annotations

import hashlib
import threading
from collections import OrderedDict
from datetime import datetime, timedelta, timezone

from lexiquest_ai.models import ContentRequest, ContentResult


def content_cache_key(request: ContentRequest, model_version: str) -> str:
    """Return a stable SHA-256 cache key for a content request.

    The canonical string is deliberately ordered and pipe-delimited so that
    field reordering does not silently change the key, and ``model_version``
    is included so that bumping the model invalidates the cache (a generated
    sentence from model v0.1 is never served as if it came from v0.2).
    """

    canonical = "|".join(
        [
            "v1",
            model_version,
            request.kind,
            request.cefr,
            request.language,
            request.text.casefold(),
        ]
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


class ContentCache:
    """Thread-safe, TTL'd, LRU-bounded cache of generated content."""

    def __init__(
        self,
        *,
        ttl: timedelta,
        max_entries: int,
        clock: type[datetime] | None = None,
    ) -> None:
        if ttl.total_seconds() <= 0:
            raise ValueError("ttl must be positive")
        if max_entries <= 0:
            raise ValueError("max_entries must be positive")
        self._ttl = ttl
        self._max_entries = max_entries
        self._now = clock or datetime.now
        self._entries: OrderedDict[str, tuple[datetime, ContentResult]] = (
            OrderedDict()
        )
        self._lock = threading.RLock()

    def get(self, key: str) -> ContentResult | None:
        """Return the cached result if present and unexpired, else ``None``.

        Marks the returned result as ``cached=True`` and refreshes LRU order.
        """

        now = self._now(timezone.utc)
        with self._lock:
            entry = self._entries.get(key)
            if entry is None:
                return None
            stored_at, result = entry
            if now - stored_at > self._ttl:
                # Expired: drop the entry so the next miss is a clean miss.
                self._entries.pop(key, None)
                return None
            # Refresh LRU recency.
            self._entries.move_to_end(key)
            return ContentResult(
                text=result.text,
                kind=result.kind,
                model_version=result.model_version,
                cached=True,
            )

    def put(self, key: str, result: ContentResult) -> None:
        """Store a fresh result, evicting the least-recently-used if needed.

        Only non-cached results are stored; a cached result never re-enters
        the cache (it would carry stale provenance).
        """

        if result.cached:
            return
        now = self._now(timezone.utc)
        stored = ContentResult(
            text=result.text,
            kind=result.kind,
            model_version=result.model_version,
            cached=False,
        )
        with self._lock:
            self._entries[key] = (now, stored)
            self._entries.move_to_end(key)
            while len(self._entries) > self._max_entries:
                self._entries.popitem(last=False)

    def __len__(self) -> int:
        with self._lock:
            return len(self._entries)


class CachingContentGenerator:
    """Wrap a [ContentGenerator] with a [ContentCache].

    Cache misses delegate to ``inner``; hits short-circuit and never touch the
    provider. This keeps provider call volume (and therefore cost) proportional
    to the number of *distinct* requests rather than the number of *total*
    requests, which is what makes the free-tier strategy viable.
    """

    def __init__(
        self,
        *,
        inner: ContentGenerator,
        cache: ContentCache,
    ) -> None:
        self._inner = inner
        self._cache = cache

    @property
    def is_ready(self) -> bool:
        return self._inner.is_ready

    def generate(self, request: ContentRequest, *, model_version: str) -> ContentResult:
        # ``ContentGenerator.generate`` itself does not take ``model_version``
        # (it stays provider-pure), so this wrapper threads the version through
        # to the key builder separately. The inner provider already knows its
        # own version via its own construction.
        key = content_cache_key(request, model_version)
        hit = self._cache.get(key)
        if hit is not None:
            return hit
        result = self._inner.generate(request)
        self._cache.put(key, result)
        return result
