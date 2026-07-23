"""Tests for OmniVoice configuration models."""

import pytest
from pydantic import ValidationError

from lexiquest_voice.config import Settings
from lexiquest_voice.models import SpeechRequest


def test_settings_have_research_safe_defaults() -> None:
    settings = Settings()

    assert settings.model_id == "k2-fsa/OmniVoice"
    assert settings.model_version == "0.2.1"
    assert settings.device == "cuda:0"
    assert settings.max_text_length == 500
    assert settings.generation_timeout_seconds == 30
    assert settings.load_asr is False


def test_speech_request_normalizes_text() -> None:
    request = SpeechRequest(
        text="  The   cat is sleeping.  ",
        language="en",
        voice="teacher_female",
        speed=0.9,
    )

    assert request.text == "The cat is sleeping."


@pytest.mark.parametrize("speed", [0.49, 1.51])
def test_speech_request_rejects_unsafe_speed(speed: float) -> None:
    with pytest.raises(ValidationError):
        SpeechRequest(
            text="Cat",
            language="en",
            voice="teacher_female",
            speed=speed,
        )


def test_speech_request_rejects_client_model_selection() -> None:
    with pytest.raises(ValidationError):
        SpeechRequest.model_validate(
            {
                "text": "Cat",
                "language": "en",
                "voice": "teacher_female",
                "speed": 1.0,
                "model": "untrusted/model",
            }
        )
