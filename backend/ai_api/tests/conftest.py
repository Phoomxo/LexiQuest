from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from lexiquest_ai.app import create_app
from lexiquest_ai.auth import AuthenticatedUser
from lexiquest_ai.config import Settings
from lexiquest_ai.models import ContentRequest, ContentResult
from lexiquest_ai.services.llm_content_service import (
    ProviderError,
    ProviderUnauthorized,
    ProviderUnavailable,
)


class FakeTokenVerifier:
    def verify(self, token: str) -> AuthenticatedUser:
        assert token == "valid-token"
        return AuthenticatedUser(uid="test-user")


class FakeContentService:
    """Deterministic content generator that records calls for assertions."""

    def __init__(self, *, text: str = "The cat sleeps peacefully.") -> None:
        self._text = text
        self.calls: list[ContentRequest] = []

    @property
    def is_ready(self) -> bool:
        return True

    def generate(self, request: ContentRequest) -> ContentResult:
        self.calls.append(request)
        return ContentResult(
            text=self._text,
            kind=request.kind,
            model_version="test",
            cached=False,
        )


class UnavailableContentService:
    @property
    def is_ready(self) -> bool:
        return False

    def generate(self, request: ContentRequest) -> ContentResult:  # pragma: no cover
        raise RuntimeError("not ready")


class FailingContentService:
    """Generator whose ``generate`` always raises an internal secret error.

    The message is a distinctive secret that must never reach the client or
    the captured log; tests assert its absence.
    """

    internal_error_message = "internal-llm-blowout-7c9f3a"

    @property
    def is_ready(self) -> bool:
        return True

    def generate(self, request: ContentRequest) -> ContentResult:
        raise RuntimeError(self.internal_error_message)


class UnauthorizedContentService:
    @property
    def is_ready(self) -> bool:
        return True

    def generate(self, request: ContentRequest) -> ContentResult:
        raise ProviderUnauthorized("provider rejected credentials")


class UnavailableProviderContentService:
    @property
    def is_ready(self) -> bool:
        return True

    def generate(self, request: ContentRequest) -> ContentResult:
        raise ProviderUnavailable("provider down")


class ProviderErrorContentService:
    """Generator that raises a generic ProviderError (malformed response)."""

    @property
    def is_ready(self) -> bool:
        return True

    def generate(self, request: ContentRequest) -> ContentResult:
        raise ProviderError("malformed provider payload")


@pytest.fixture
def token_verifier() -> FakeTokenVerifier:
    return FakeTokenVerifier()


@pytest.fixture
def content_service() -> FakeContentService:
    return FakeContentService()


@pytest.fixture
def client(
    token_verifier: FakeTokenVerifier,
    content_service: FakeContentService,
) -> TestClient:
    app = create_app(
        content_service=content_service,
        token_verifier=token_verifier,
        settings=Settings(),
    )
    return TestClient(app)


@pytest.fixture
def make_client(token_verifier: FakeTokenVerifier):
    """Factory to build a client with a specific content service + settings."""

    def _factory(*, content_service, settings=None) -> TestClient:
        return TestClient(
            create_app(
                content_service=content_service,
                token_verifier=token_verifier,
                settings=settings or Settings(),
            )
        )

    return _factory
