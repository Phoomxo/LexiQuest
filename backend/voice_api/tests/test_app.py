from __future__ import annotations

import logging

import pytest
from fastapi.testclient import TestClient

from lexiquest_voice.app import create_app
from lexiquest_voice.config import Settings

from conftest import (
    FailingSpeechEngine,
    FakeSpeechEngine,
    FakeTokenVerifier,
    UnavailableSpeechEngine,
)

# Valid speech-request body shared by the length-limit tests, minus the
# ``text`` field each test supplies individually.
_SPEECH_BODY = {
    "language": "en",
    "voice": "teacher_female",
    "speed": 1.0,
}


def test_health_endpoints(client: TestClient) -> None:
    assert client.get("/health/live").json() == {"status": "live"}
    assert client.get("/health/ready").json() == {"status": "ready"}


def test_speech_rejects_missing_token(client: TestClient) -> None:
    response = client.post(
        "/v1/speech",
        json={
            "text": "Cat",
            "language": "en",
            "voice": "teacher_female",
            "speed": 1.0,
        },
    )

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "UNAUTHENTICATED"


def test_speech_returns_wav_with_provenance_headers(
    client: TestClient,
) -> None:
    response = client.post(
        "/v1/speech",
        headers={"Authorization": "Bearer valid-token"},
        json={
            "text": "Cat",
            "language": "en",
            "voice": "teacher_female",
            "speed": 1.0,
        },
    )

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/wav"
    assert response.headers["x-voice-engine"] == "fake-omnivoice"
    assert response.headers["x-model-version"] == "test"
    assert response.headers["x-audio-sample-rate"] == "24000"
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-request-id"]
    assert response.content == b"RIFF-test-wav"


def test_ready_returns_503_when_engine_is_unavailable(
    token_verifier: FakeTokenVerifier,
) -> None:
    app = create_app(
        engine=UnavailableSpeechEngine(),
        token_verifier=token_verifier,
        settings=Settings(),
    )
    response = TestClient(app).get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "detail": {
            "code": "MODEL_UNAVAILABLE",
            "message": "The speech engine is not ready.",
        }
    }


def test_speech_enforces_configured_text_length(
    token_verifier: FakeTokenVerifier,
) -> None:
    """The configured ``max_text_length`` must drive the HTTP limit."""

    settings = Settings(max_text_length=10)
    app = create_app(
        engine=FakeSpeechEngine(),
        token_verifier=token_verifier,
        settings=settings,
    )

    response = TestClient(app).post(
        "/v1/speech",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "x" * 11, **_SPEECH_BODY},
    )

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "TEXT_TOO_LONG"


def test_speech_accepts_text_at_configured_text_length(
    token_verifier: FakeTokenVerifier,
) -> None:
    """Text at exactly the configured limit is accepted (boundary)."""

    settings = Settings(max_text_length=10)
    app = create_app(
        engine=FakeSpeechEngine(),
        token_verifier=token_verifier,
        settings=settings,
    )

    response = TestClient(app).post(
        "/v1/speech",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "x" * 10, **_SPEECH_BODY},
    )

    assert response.status_code == 200


def test_speech_schema_ceiling_still_rejects_oversized_text(
    token_verifier: FakeTokenVerifier,
) -> None:
    """An absolute schema ceiling remains as a backstop above the limit."""

    settings = Settings(max_text_length=10)
    app = create_app(
        engine=FakeSpeechEngine(),
        token_verifier=token_verifier,
        settings=settings,
    )

    response = TestClient(app).post(
        "/v1/speech",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "x" * 2001, **_SPEECH_BODY},
    )

    assert response.status_code == 422


def test_speech_failure_hides_secret_detail_and_correlates_request_id(
    token_verifier: FakeTokenVerifier,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A synthesis failure returns a safe 503 correlated by ``request_id`` and
    never leaks the secret request text or the internal exception message."""

    secret_text = "TOPSECRET-payload-7c9f3a"
    app = create_app(
        engine=FailingSpeechEngine(),
        token_verifier=token_verifier,
        settings=Settings(),
    )

    with caplog.at_level(logging.ERROR):
        response = TestClient(app).post(
            "/v1/speech",
            headers={"Authorization": "Bearer valid-token"},
            json={"text": secret_text, **_SPEECH_BODY},
        )

    # Status and the stable failure contract.
    assert response.status_code == 503
    detail = response.json()["detail"]
    assert detail["code"] == "SYNTHESIS_FAILED"
    assert detail["message"] == "Speech synthesis could not be completed."
    assert response.headers["Retry-After"] == "5"

    # The same request_id appears in both the body and the response header.
    request_id = detail["request_id"]
    assert request_id
    assert request_id == response.headers["X-Request-ID"]
    assert request_id in caplog.text

    # The secret request text and the internal exception message must never
    # appear in either the response body or the captured log.
    captured = f"{response.text}\n{caplog.text}"
    assert secret_text not in captured
    assert FailingSpeechEngine.internal_error_message not in captured

    # The log records the failure with the exception type only.
    assert "RuntimeError" in caplog.text
