"""Tests for the FastAPI application factory and content endpoint."""

from __future__ import annotations

import logging

import pytest
from fastapi.testclient import TestClient

from lexiquest_ai.app import create_app
from lexiquest_ai.config import Settings

from conftest import (
    FailingContentService,
    FakeContentService,
    FakeTokenVerifier,
    ProviderErrorContentService,
    UnavailableContentService,
    UnauthorizedContentService,
    UnavailableProviderContentService,
)

_CONTENT_BODY = {
    "kind": "sentence",
    "cefr": "a1",
    "language": "en",
}


def test_health_endpoints(client: TestClient) -> None:
    assert client.get("/health/live").json() == {"status": "live"}
    assert client.get("/health/ready").json() == {"status": "ready"}


def test_content_rejects_missing_token(client: TestClient) -> None:
    response = client.post("/v1/content", json={"text": "Cat", **_CONTENT_BODY})

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "UNAUTHENTICATED"


def test_content_returns_generated_text(client: TestClient) -> None:
    response = client.post(
        "/v1/content",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "Cat", **_CONTENT_BODY},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["text"] == "The cat sleeps peacefully."
    assert body["kind"] == "sentence"
    assert body["language"] == "en"
    assert body["cefr"] == "a1"
    assert body["model_version"] == "test"
    assert body["cached"] is False


def test_ready_returns_503_when_service_not_configured(
    token_verifier: FakeTokenVerifier,
) -> None:
    app = create_app(
        content_service=UnavailableContentService(),
        token_verifier=token_verifier,
        settings=Settings(),
    )
    response = TestClient(app).get("/health/ready")

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "PROVIDER_UNAVAILABLE"


def test_content_enforces_configured_text_length(
    token_verifier: FakeTokenVerifier,
    make_client,
) -> None:
    settings = Settings(max_text_length=10)
    client = make_client(
        content_service=FakeContentService(), settings=settings
    )

    response = client.post(
        "/v1/content",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "x" * 11, **_CONTENT_BODY},
    )

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "TEXT_TOO_LONG"


def test_content_failure_hides_secret_detail_and_correlates_request_id(
    token_verifier: FakeTokenVerifier,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A generation failure returns a safe 503 correlated by ``request_id`` and
    never leaks the secret request text or the internal exception message."""

    secret_text = "TOPSECRET-payload-7c9f3a"
    app = create_app(
        content_service=FailingContentService(),
        token_verifier=token_verifier,
        settings=Settings(),
    )

    with caplog.at_level(logging.ERROR):
        response = TestClient(app).post(
            "/v1/content",
            headers={"Authorization": "Bearer valid-token"},
            json={"text": secret_text, **_CONTENT_BODY},
        )

    assert response.status_code == 503
    detail = response.json()["detail"]
    assert detail["code"] == "CONTENT_GENERATION_FAILED"
    assert detail["message"] == "Content generation could not be completed."
    assert response.headers["Retry-After"] == "5"

    request_id = detail["request_id"]
    assert request_id
    assert request_id == response.headers["X-Request-ID"]
    assert request_id in caplog.text

    captured = f"{response.text}\n{caplog.text}"
    assert secret_text not in captured
    assert FailingContentService.internal_error_message not in captured
    assert "RuntimeError" in caplog.text


def test_content_provider_unauthorized_maps_to_stable_error(
    token_verifier: FakeTokenVerifier,
    make_client,
) -> None:
    client = make_client(content_service=UnauthorizedContentService())

    response = client.post(
        "/v1/content",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "Cat", **_CONTENT_BODY},
    )

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "PROVIDER_UNAUTHORIZED"


def test_content_provider_unavailable_maps_to_stable_error(
    token_verifier: FakeTokenVerifier,
    make_client,
) -> None:
    client = make_client(content_service=UnavailableProviderContentService())

    response = client.post(
        "/v1/content",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "Cat", **_CONTENT_BODY},
    )

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "PROVIDER_UNAVAILABLE"


def test_content_provider_error_maps_to_generation_failed(
    token_verifier: FakeTokenVerifier,
    make_client,
) -> None:
    """A generic provider error (malformed response) is also surfaced as the
    stable CONTENT_GENERATION_FAILED, never a raw 500."""

    client = make_client(content_service=ProviderErrorContentService())

    response = client.post(
        "/v1/content",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "Cat", **_CONTENT_BODY},
    )

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "CONTENT_GENERATION_FAILED"
