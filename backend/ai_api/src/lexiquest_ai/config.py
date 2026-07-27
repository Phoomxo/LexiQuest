"""Application configuration for the LexiQuest AI API.

Settings are loaded from environment variables prefixed with
``LEXIQUEST_AI_`` and/or a local ``.env`` file located in the backend project
root (``backend/ai_api/.env``).
"""

from __future__ import annotations

import ipaddress
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

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
_CLOUD_METADATA_HOSTS = frozenset({"metadata.google.internal"})


def _canonical_ip_address(
    host: str,
) -> ipaddress.IPv4Address | ipaddress.IPv6Address | None:
    try:
        return ipaddress.ip_address(host)
    except ValueError:
        return None


def _inet_aton_ipv4(host: str) -> ipaddress.IPv4Address | None:
    """Parse legacy integer/octal/hex IPv4 forms without DNS resolution."""

    if not host:
        return None
    parts = host.split(".")
    if len(parts) > 4:
        return None
    values: list[int] = []
    for part in parts:
        if not part:
            return None
        lowered = part.lower()
        try:
            if lowered.startswith("0x"):
                number = int(part, 16)
            elif part.startswith("0") and len(part) > 1:
                number = int(part, 8)
            else:
                number = int(part, 10)
        except ValueError:
            return None
        values.append(number)

    try:
        if len(values) == 4:
            octets = values
        elif len(values) == 3:
            if values[2] > 0xFFFF:
                return None
            octets = [values[0], values[1], values[2] >> 8, values[2] & 0xFF]
        elif len(values) == 2:
            if values[1] > 0xFFFFFF:
                return None
            octets = [
                values[0],
                values[1] >> 16,
                (values[1] >> 8) & 0xFF,
                values[1] & 0xFF,
            ]
        else:
            return (
                ipaddress.IPv4Address(values[0])
                if values[0] <= 0xFFFFFFFF
                else None
            )
        if any(octet > 0xFF for octet in octets):
            return None
        return ipaddress.IPv4Address(".".join(str(octet) for octet in octets))
    except ValueError:
        return None


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
    environment: str = "development"
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
        if any(
            character.isspace()
            or ord(character) < 0x20
            or ord(character) == 0x7F
            or character in '<>"{}|\\^'
            for character in stripped
        ):
            raise ValueError("LLM base URL is malformed")

        try:
            parsed = urlsplit(stripped)
            hostname = parsed.hostname
            port = parsed.port
        except ValueError:
            raise ValueError("LLM base URL is malformed") from None

        if parsed.scheme not in {"http", "https"}:
            raise ValueError("LLM base URL must use http or https scheme")
        if not hostname or parsed.username is not None or parsed.password is not None:
            raise ValueError("LLM base URL is malformed")
        if port is not None and not 1 <= port <= 65535:
            raise ValueError("LLM base URL is malformed")
        if parsed.query or parsed.fragment:
            raise ValueError("LLM base URL is malformed")

        normalized_host = hostname.rstrip(".").casefold()
        host_ip = _canonical_ip_address(normalized_host)
        inet_ipv4 = _inet_aton_ipv4(normalized_host)

        if parsed.scheme == "http":
            is_loopback = normalized_host == "localhost" or (
                host_ip is not None and host_ip.is_loopback
            )
            if not is_loopback:
                raise ValueError(
                    "LLM base URL must use HTTPS unless the host is loopback"
                )

        if normalized_host in _CLOUD_METADATA_HOSTS:
            raise ValueError("LLM base URL must not target cloud metadata services")
        if inet_ipv4 is not None and host_ip is None:
            raise ValueError("LLM base URL must use canonical IP address notation")
        if host_ip is not None:
            effective_ip = host_ip
            if isinstance(host_ip, ipaddress.IPv6Address):
                effective_ip = host_ip.ipv4_mapped or host_ip
            if effective_ip.is_link_local:
                raise ValueError("LLM base URL must not target link-local addresses")

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
