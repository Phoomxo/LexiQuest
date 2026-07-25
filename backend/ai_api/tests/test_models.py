"""Tests for LexiQuest AI configuration and request models."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from lexiquest_ai.config import Settings
from lexiquest_ai.models import ContentRequest


def test_settings_have_safe_defaults() -> None:
    settings = Settings()

    assert settings.model_version == "0.1.0"
    assert settings.max_text_length == 500
    assert settings.llm_provider == "openai-compat"
    assert settings.llm_model == "gemini-2.0-flash"
    assert settings.llm_temperature == 0.4
    assert settings.llm_max_tokens == 512
    # Default cache TTL is 7 days.
    assert settings.cache_ttl_seconds == 7 * 24 * 3600
    assert settings.cache_max_entries == 4096


def test_settings_reject_unsupported_provider() -> None:
    with pytest.raises(ValidationError, match="Unsupported LLM provider"):
        Settings(llm_provider="claude-native")  # type: ignore[arg-type]


def test_settings_normalize_base_url_trailing_slash() -> None:
    settings = Settings(
        llm_base_url="https://api.example.com/v1"
    )
    assert settings.llm_base_url == "https://api.example.com/v1/"


def test_settings_reject_non_http_base_url() -> None:
    with pytest.raises(ValidationError, match="http or https scheme"):
        Settings(llm_base_url="ftp://example.com")


def test_settings_reject_empty_base_url() -> None:
    with pytest.raises(ValidationError, match="empty"):
        Settings(llm_base_url="   ")


def test_content_request_normalizes_text() -> None:
    request = ContentRequest(
        text="  The   cat is sleeping.  ",
        kind="sentence",
        cefr="a1",
    )
    assert request.text == "The cat is sleeping."


def test_content_request_rejects_client_model_selection() -> None:
    with pytest.raises(ValidationError):
        ContentRequest.model_validate(
            {
                "text": "Cat",
                "kind": "sentence",
                "model": "untrusted/model",
            }
        )


def test_content_request_rejects_unknown_kind() -> None:
    with pytest.raises(ValidationError):
        ContentRequest.model_validate(
            {"text": "Cat", "kind": "essay"}
        )


def test_content_request_rejects_unknown_cefr() -> None:
    with pytest.raises(ValidationError):
        ContentRequest.model_validate(
            {"text": "Cat", "kind": "sentence", "cefr": "x9"}
        )


def test_content_request_defaults_language_and_cefr() -> None:
    request = ContentRequest(text="Cat", kind="sentence")
    assert request.language == "en"
    assert request.cefr == "unknown"
