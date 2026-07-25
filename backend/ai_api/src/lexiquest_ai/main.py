"""Production ASGI assembly for the LexiQuest AI API.

Importing this module initializes Firebase Admin (via Application Default
Credentials) and constructs the caching content service around the
configured LLM provider. Importing it does **not** make a network call to the
LLM provider; the first real request does.

Run locally::

    uv run --project backend/ai_api uvicorn lexiquest_ai.main:app --host 127.0.0.1 --port 8001
"""

from datetime import timedelta

from lexiquest_ai.app import create_app
from lexiquest_ai.auth import FirebaseTokenVerifier
from lexiquest_ai.config import Settings
from lexiquest_ai.services.cache import CachingContentGenerator, ContentCache
from lexiquest_ai.services.llm_content_service import LlmContentService

settings = Settings()
token_verifier = FirebaseTokenVerifier()
inner = LlmContentService(settings=settings)
cache = ContentCache(
    ttl=timedelta(seconds=settings.cache_ttl_seconds),
    max_entries=settings.cache_max_entries,
)


# Wrap the inner generator in the caching layer. This object still satisfies the
# ``ContentGenerator`` protocol, so the app factory treats it uniformly.
class _CachedService:
    """Adapter that threads ``model_version`` into the cache key on each call."""

    def __init__(self, *, delegate: CachingContentGenerator, version: str) -> None:
        self._delegate = delegate
        self._version = version

    @property
    def is_ready(self) -> bool:
        return self._delegate.is_ready

    def generate(self, request):  # type: ignore[no-untyped-def]
        return self._delegate.generate(request, model_version=self._version)


content_service = _CachedService(
    delegate=CachingContentGenerator(inner=inner, cache=cache),
    version=settings.model_version,
)

app = create_app(
    content_service=content_service,
    token_verifier=token_verifier,
    settings=settings,
)

__all__ = ["app"]
