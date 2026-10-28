from __future__ import annotations

from fastapi.testclient import TestClient

from lexiquest_voice.app import create_app
from lexiquest_voice.config import Settings

from conftest import FakeTokenVerifier, UnavailableSpeechEngine


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
