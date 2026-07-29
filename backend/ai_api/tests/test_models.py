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
    assert settings.llm_model == "qwen2.5:3b"
    assert settings.fallback_llm_model == "gemini-2.0-flash"
    assert settings.llm_temperature == 0.4
    assert settings.llm_max_tokens == 512
    # Default cache TTL is 7 days.
    assert settings.cache_ttl_seconds == 7 * 24 * 3600
    assert settings.cache_max_entries == 4096


def test_settings_reject_unsupported_provider() -> None:
    with pytest.raises(ValidationError, match="Input should be"):
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


_BASE_URL_FIELDS = ("llm_base_url", "fallback_llm_base_url")


@pytest.mark.parametrize(
    "url",
    [
        "https://api.openai.com/v1/",
        "https://generativelanguage.googleapis.com/v1beta/openai/",
        "https://proxy.example.internal",
    ],
)
def test_settings_accept_https_remote_base_url(url: str) -> None:
    assert Settings(llm_base_url=url).llm_base_url.endswith("/")


@pytest.mark.parametrize(
    "url",
    [
        "http://localhost:11434/v1/",
        "http://127.0.0.1:11434/v1/",
        "http://[::1]:11434/v1/",
        "http://localhost:8080",
    ],
)
def test_settings_accept_http_only_for_loopback_dev(url: str) -> None:
    assert Settings(llm_base_url=url).llm_base_url.endswith("/")


@pytest.mark.parametrize("field", _BASE_URL_FIELDS)
@pytest.mark.parametrize(
    "url",
    [
        "http://api.openai.com/v1/",
        "http://example.com",
        "http://192.168.1.10/v1/",
        "http://10.0.0.5/v1/",
        "http://169.254.169.254/",
    ],
)
def test_settings_reject_plain_http_to_non_loopback(
    field: str,
    url: str,
) -> None:
    with pytest.raises(ValidationError) as exc_info:
        Settings(**{field: url})
    message = str(exc_info.value).lower()
    assert "loopback" in message or "https" in message


def test_settings_reject_userinfo_credentials_in_base_url() -> None:
    with pytest.raises(ValidationError):
        Settings(llm_base_url="https://operator:hunter2@api.openai.com/v1/")


@pytest.mark.parametrize(
    "url",
    [
        "https://",
        "https:///",
        "http://",
        "https:// api.openai.com/",
        "https://example.com/</v1>",
    ],
)
def test_settings_reject_malformed_base_url(url: str) -> None:
    with pytest.raises(ValidationError):
        Settings(llm_base_url=url)


@pytest.mark.parametrize(
    "url",
    [
        "https://api.example.com/v1/\x00",
        "https://api.example.com/v1/\x7f",
        "https://api.example.com/v1/\x01",
        "http://localhost:11434/v1/\x00",
    ],
)
def test_settings_reject_control_chars_in_base_url(url: str) -> None:
    with pytest.raises(ValidationError):
        Settings(llm_base_url=url)


@pytest.mark.parametrize("field", _BASE_URL_FIELDS)
@pytest.mark.parametrize(
    "url",
    [
        "https://169.254.169.254/",
        "https://metadata.google.internal/",
        "https://[::ffff:169.254.169.254]/",
    ],
)
def test_settings_reject_cloud_metadata_base_url(
    field: str,
    url: str,
) -> None:
    with pytest.raises(ValidationError):
        Settings(**{field: url})


@pytest.mark.parametrize("field", _BASE_URL_FIELDS)
@pytest.mark.parametrize(
    "url",
    [
        "https://2852039166/",
        "https://0xA9.0xFE.0xA9.0xFE/",
        "https://0251.0376.0251.0376/",
    ],
)
def test_settings_reject_obfuscated_ip_base_url(
    field: str,
    url: str,
) -> None:
    with pytest.raises(ValidationError):
        Settings(**{field: url})


def test_settings_base_url_error_never_echoes_credentials() -> None:
    secret = "hunter2-leak-canary-9f3c"
    url = f"https://operator:{secret}@api.openai.com/v1/"
    with pytest.raises(ValidationError) as exc_info:
        Settings(llm_base_url=url)
    assert secret not in str(exc_info.value)


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
