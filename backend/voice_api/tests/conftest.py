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
    @property
    def is_ready(self) -> bool:
        return True

    def synthesize(self, request: SpeechRequest) -> AudioResult:
        return AudioResult(
            data=b"RIFF-test-wav",
            media_type="audio/wav",
            sample_rate=24_000,
            engine="fake-omnivoice",
            model_version="test",
        )


class UnavailableSpeechEngine:
    @property
    def is_ready(self) -> bool:
        return False

    def synthesize(self, request: SpeechRequest) -> AudioResult:
        raise RuntimeError("not ready")


class FailingSpeechEngine:
    """Engine whose ``synthesize`` always raises with an internal message.

    The message is a distinctive secret that must never reach the client or
    the captured log; tests assert its absence.
    """

    internal_error_message = "internal-tts-blowout-7c9f3a"

    @property
    def is_ready(self) -> bool:
        return True

    def synthesize(self, request: SpeechRequest) -> AudioResult:
        raise RuntimeError(self.internal_error_message)


@pytest.fixture
def token_verifier() -> FakeTokenVerifier:
    return FakeTokenVerifier()


@pytest.fixture
def client(token_verifier: FakeTokenVerifier) -> TestClient:
    app = create_app(
        engine=FakeSpeechEngine(),
        token_verifier=token_verifier,
        settings=Settings(),
    )
    return TestClient(app)
