"""Application configuration for the LexiQuest AI API.

Settings are loaded from environment variables prefixed with
``LEXIQUEST_AI_`` and/or a local ``.env`` file located in the backend project
root (``backend/ai_api/.env``).
"""

from __future__ import annotations

from pathlib import Path
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from lexiquest_ai.models import MAX_TEXT_LENGTH_CEILING

# Resolve ``.env`` deterministically relative to this module so the service
# loads the same configuration regardless of the process working directory.
# ``config.py`` lives three levels below the backend project root.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
_ENV_FILE = _PROJECT_ROOT / ".env"

# Providers supported by ``LlmContentService``. All of them are consumed
# through the OpenAI-compatible HTTP contract, so adding a vendor amounts to a
# new base URL + model name rather than a new SDK.
_SUPPORTED_PROVIDERS = frozenset({"openai-compat"})


class Settings(BaseSettings):
    """Runtime configuration for the AI content service."""

    model_config = SettingsConfigDict(
        env_prefix="LEXIQUEST_AI_",
        env_file=_ENV_FILE,
        extra="ignore",
        frozen=True,
    )

    # --- Service identity ---
    model_version: str = "0.1.0"
    max_text_length: int = Field(default=500, ge=1, le=MAX_TEXT_LENGTH_CEILING)
    request_timeout_seconds: int = Field(default=20, ge=1, le=120)

    # --- Response cache (primary cost control) ---
    cache_ttl_seconds: int = Field(default=7 * 24 * 3600, ge=1, le=365 * 24 * 3600)
    cache_max_entries: int = Field(default=4096, ge=1, le=1_000_000)

    # --- Primary LLM provider (Ollama self-host by default) ---
    llm_provider: Literal["openai-compat"] = "openai-compat"
    llm_model: str = "qwen2.5:3b"
    llm_base_url: str = "http://127.0.0.1:11434/v1/"
    llm_api_key: str = "ollama"

    # --- Fallback LLM provider (Gemini OpenAI-compat, free tier) ---
    # Empty model/base_url disables the fallback chain. When enabled, the
    # fallback is tried automatically only when the primary is unavailable or
    # returns a hard error (never on a cache hit).
    fallback_llm_model: str = "gemini-2.0-flash"
    fallback_llm_base_url: str = (
        "https://generativelanguage.googleapis.com/v1beta/openai/"
    )
    fallback_llm_api_key: str = ""

    # --- Optional additional Gemini keys (round-robin to multiply quota) ---
    # Comma-separated. Each key has its own 1,500/day ceiling. Empty disables.
    gemini_keys: str = ""

    # --- Rate limiting (protects every provider in the chain) ---
    # Max requests per minute to a single provider endpoint. Set to the lowest
    # provider's limit so the limiter never lets a request through that the
    # provider will reject. Gemini free tier = 15.
    provider_rpm_limit: int = Field(default=15, ge=1, le=10_000)

    # --- Decoding parameters ---
    llm_temperature: float = Field(default=0.4, ge=0.0, le=2.0)
    llm_max_tokens: int = Field(default=512, ge=1, le=8192)

    @field_validator("llm_provider")
    @classmethod
    def _validate_provider(cls, value: str) -> str:
        if value not in _SUPPORTED_PROVIDERS:
            supported = ", ".join(sorted(_SUPPORTED_PROVIDERS))
            raise ValueError(
                f"Unsupported LLM provider {value!r}; supported: {supported}"
            )
        return value

    @field_validator("llm_base_url", "fallback_llm_base_url")
    @classmethod
    def _validate_base_url(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("LLM base URL must not be empty")
        if not (stripped.startswith("http://") or stripped.startswith("https://")):
            raise ValueError("LLM base URL must use http or https scheme")
        # Trailing slash keeps ``urllib.parse.urljoin`` predictable downstream.
        return stripped if stripped.endswith("/") else stripped + "/"

    @field_validator("gemini_keys")
    @classmethod
    def _normalize_gemini_keys(cls, value: str) -> str:
        # Strip whitespace and drop empties; preserve order. The provider chain
        # splits this string at runtime, so normalising once here avoids
        # surprising duplicates downstream.
        parts = [p.strip() for p in value.split(",") if p.strip()]
        return ",".join(parts)
