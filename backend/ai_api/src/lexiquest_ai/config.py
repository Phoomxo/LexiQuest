"""Application configuration for the LexiQuest AI API.

Settings are loaded from environment variables prefixed with
``LEXIQUEST_AI_`` and/or a local ``.env`` file located in the backend project
root (``backend/ai_api/.env``).
"""

from __future__ import annotations

import ipaddress
import re
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from pydantic import Field, field_validator, model_validator
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
_KMS_KEY_VERSION_PATTERN = re.compile(
    r"projects/[^/\s]+/locations/[^/\s]+/keyRings/[^/\s]+/"
    r"cryptoKeys/[^/\s]+/cryptoKeyVersions/[1-9][0-9]*"
)


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
    account_deletion_enabled: bool = False
    account_deletion_server_export_authority: Literal[
        "", "gcp-kms-hmac-sha256-v1"
    ] = ""
    account_deletion_export_bucket: str = Field(default="", max_length=255)
    account_deletion_export_kms_key_version: str = Field(
        default="", max_length=512
    )
    account_deletion_export_trusted_kms_key_versions: str = Field(
        default="", max_length=4096
    )
    account_deletion_export_retention_seconds: int = Field(
        default=0, ge=0, le=30 * 24 * 3600
    )
    account_deletion_recovery_retention_seconds: int = Field(
        default=0, ge=0, le=30 * 24 * 3600
    )
    account_deletion_export_maximum_documents: int = Field(
        default=10_000, ge=1, le=100_000
    )
    account_deletion_export_maximum_bytes: int = Field(
        default=50 * 1024 * 1024,
        ge=1,
        le=512 * 1024 * 1024,
    )

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

    # --- Optional additional Gemini credentials for fallback ---
    # Comma-separated. Provider/project quotas still apply. Empty disables.
    gemini_keys: str = ""

    # --- Rate limiting (protects every provider in the chain) ---
    # Max requests per minute per provider credential. Set to the lowest
    # credential's limit so the limiter never lets a request through that the
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

    @field_validator("account_deletion_export_bucket")
    @classmethod
    def _validate_export_bucket(cls, value: str) -> str:
        bucket = value.strip()
        if not bucket:
            return ""
        labels = bucket.split(".")
        if (
            not 3 <= len(bucket) <= 222
            or any(not 1 <= len(label) <= 63 for label in labels)
            or any(
                re.fullmatch(
                    r"[a-z0-9](?:[a-z0-9_-]*[a-z0-9])?", label
                )
                is None
                for label in labels
            )
        ):
            raise ValueError("account deletion export bucket name is invalid")
        try:
            ipaddress.ip_address(bucket)
        except ValueError:
            return bucket
        raise ValueError("account deletion export bucket must not be an IP address")

    @field_validator("account_deletion_export_kms_key_version")
    @classmethod
    def _validate_export_kms_key_version(cls, value: str) -> str:
        key_version = value.strip()
        if not key_version:
            return ""
        if _KMS_KEY_VERSION_PATTERN.fullmatch(key_version) is None:
            raise ValueError("account deletion KMS key version is invalid")
        return key_version

    @field_validator("account_deletion_export_trusted_kms_key_versions")
    @classmethod
    def _validate_trusted_export_kms_key_versions(cls, value: str) -> str:
        versions: list[str] = []
        for raw in value.split(","):
            version = raw.strip()
            if not version:
                continue
            if _KMS_KEY_VERSION_PATTERN.fullmatch(version) is None:
                raise ValueError("trusted account deletion KMS key is invalid")
            if version not in versions:
                versions.append(version)
        return ",".join(versions)

    @model_validator(mode="after")
    def _validate_account_deletion_export(self) -> Settings:
        authority = self.account_deletion_server_export_authority
        bucket = self.account_deletion_export_bucket.strip()
        key_version = self.account_deletion_export_kms_key_version.strip()
        trusted_versions = (
            self.account_deletion_export_trusted_kms_key_versions.strip()
        )
        export_retention = self.account_deletion_export_retention_seconds
        recovery_retention = self.account_deletion_recovery_retention_seconds
        if not authority:
            if (
                bucket
                or key_version
                or trusted_versions
                or export_retention
                or recovery_retention
            ):
                raise ValueError(
                    "account deletion export configuration is partial"
                )
            return self
        if (
            not bucket
            or not key_version
            or export_retention <= 0
            or recovery_retention <= 0
            or export_retention < recovery_retention
        ):
            raise ValueError(
                "account deletion export configuration is incomplete"
            )
        return self
