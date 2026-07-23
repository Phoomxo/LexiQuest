from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from lexiquest_voice.app import create_app
from lexiquest_voice.auth import AuthenticatedUser
from lexiquest_voice.config import Settings
from lexiquest_voice.models import AudioResult, SpeechRequest


class FakeTokenVerifier:
    def verify(self, token: str) -> AuthenticatedUser:
        assert token == "valid-token"
        return AuthenticatedUser(uid="test-user")


class FakeSpeechEngine:
    def synthesize(self, request: SpeechRequest) -> AudioResult:
        return AudioResult(
            data=b"RIFF-test-wav",
            media_type="audio/wav",
            sample_rate=24_000,
            engine="fake-omnivoice",
            model_version="test",
        )


@pytest.fixture
def client() -> TestClient:
    app = create_app(
        engine=FakeSpeechEngine(),
        token_verifier=FakeTokenVerifier(),
        settings=Settings(),
    )
    return TestClient(app)
