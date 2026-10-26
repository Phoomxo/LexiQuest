"""Production ASGI assembly for the LexiQuest AI API.

Importing this module initializes Firebase Admin (via Application Default
Credentials) and constructs the caching content service around the
configured LLM provider. Importing it does **not** make a network call to the
LLM provider; the first real request does.

Run locally::

    uv run --project backend/ai_api uvicorn lexiquest_ai.main:app --host 127.0.0.1 --port 8001
"""

import logging
from datetime import timedelta

from lexiquest_ai.app import create_app
from lexiquest_ai.auth import FirebaseTokenVerifier
from lexiquest_ai.config import Settings
from lexiquest_ai.firebase_account_deletion import (
    build_firebase_account_deletion_service,
)
from lexiquest_ai.gcp_account_export import (
    KmsRecoveryKeyAuthority,
    build_gcp_account_deletion_readiness_probe,
    build_gcp_account_export_authority,
    build_trusted_kms_mac_authority,
)
from lexiquest_ai.services.cache import CachingContentGenerator, ContentCache
from lexiquest_ai.services.llm_content_service import LlmContentService

logger = logging.getLogger(__name__)

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
try:
    mac_authority = build_trusted_kms_mac_authority(settings)
    server_export_authority = build_gcp_account_export_authority(
        settings, mac_authority=mac_authority
    )
    recovery_key_authority = (
        None
        if mac_authority is None
        else KmsRecoveryKeyAuthority(mac_authority)
    )
    account_deletion_service = build_firebase_account_deletion_service(
        # The public endpoint flag controls only new requests. A configured
        # service stays composed while disabled so committed recovery can finish.
        enabled=server_export_authority is not None,
        server_export_authority=server_export_authority,
        recovery_key_authority=recovery_key_authority,
        recovery_retention=timedelta(
            seconds=settings.account_deletion_recovery_retention_seconds
        ),
    )
    account_deletion_readiness_probe = (
        build_gcp_account_deletion_readiness_probe(
            settings,
            mac_authority=mac_authority,
        )
    )
except Exception as error:
    # Keep liveness available but fail readiness; never log credentials or the
    # provider exception message because either may contain deployment detail.
    logger.error(
        "Account deletion service composition failed: %s",
        type(error).__name__,
    )
    account_deletion_service = None
    account_deletion_readiness_probe = None

app = create_app(
    content_service=content_service,
    token_verifier=token_verifier,
    settings=settings,
    account_deletion_service=account_deletion_service,
    account_deletion_readiness_probe=account_deletion_readiness_probe,
)

__all__ = ["app"]
