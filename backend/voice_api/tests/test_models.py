"""Tests for OmniVoice configuration models."""

from lexiquest_voice.config import Settings


def test_settings_have_research_safe_defaults() -> None:
    settings = Settings()

    assert settings.model_id == "k2-fsa/OmniVoice"
    assert settings.model_version == "0.2.1"
    assert settings.device == "cuda:0"
    assert settings.max_text_length == 500
    assert settings.generation_timeout_seconds == 30
    assert settings.load_asr is False
