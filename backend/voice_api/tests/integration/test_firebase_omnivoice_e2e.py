from __future__ import annotations

import io
import os
import wave

import pytest
from fastapi.testclient import TestClient

from lexiquest_voice.app import create_app
from lexiquest_voice.auth import FirebaseTokenVerifier
from lexiquest_voice.config import Settings
from lexiquest_voice.engines.omnivoice_engine import OmniVoiceEngine


@pytest.mark.integration
def test_real_firebase_omnivoice_e2e() -> None:
    enable = os.getenv("LEXIQUEST_E2E_ENABLE")
    token = os.getenv("LEXIQUEST_E2E_TEST_TOKEN")

    if enable != "1" or not token:
        pytest.skip(
            "Opt-in E2E tests require environment variables "
            "LEXIQUEST_E2E_ENABLE=1 and LEXIQUEST_E2E_TEST_TOKEN set."
        )

    settings = Settings()
    app = create_app(
        engine=OmniVoiceEngine(settings=settings),
        token_verifier=FirebaseTokenVerifier(),
        settings=settings,
    )
    client = TestClient(app)

    response = client.post(
        "/v1/speech",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "text": "Hello world",
            "language": "en",
            "voice": "teacher_female",
            "speed": 1.0,
        },
    )

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/wav"
    assert len(response.content) > 0
    assert response.content[:4] == b"RIFF"

    with wave.open(io.BytesIO(response.content), "rb") as wav:
        assert wav.getnchannels() == 1
        assert wav.getframerate() == 24_000
        frame_count = wav.getnframes()
        assert frame_count > 0
        duration = frame_count / wav.getframerate()
        assert 0 < duration < 30
