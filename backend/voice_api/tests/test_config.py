"""Tests for Settings configuration and environment loading."""

from __future__ import annotations

from pathlib import Path

import pytest
from pydantic import ValidationError

from lexiquest_voice.config import Settings

# Backend project root derived from this test file's own location
# (backend/voice_api/tests/test_config.py -> backend/voice_api). This is
# independent of how Settings resolves the .env path internally, so it does
# not make the test circular.
_BACKEND_ROOT = Path(__file__).resolve().parent.parent


def test_env_file_resolves_relative_to_backend_project_regardless_of_cwd(
    tmp_path: Path,
    monkeypatch,
) -> None:
    """The configured path must remain anchored to the backend project."""

    expected_env_path = _BACKEND_ROOT / ".env"
    monkeypatch.chdir(tmp_path)

    assert Path(Settings.model_config["env_file"]) == expected_env_path


def test_settings_loads_an_absolute_env_file_from_another_cwd(
    tmp_path: Path,
    monkeypatch,
) -> None:
    """An absolute dotenv path must load independently of the caller cwd."""

    env_path = tmp_path / "voice.env"
    env_path.write_text("LEXIQUEST_VOICE_SAMPLE_RATE=48000\n", encoding="utf-8")
    unrelated_cwd = tmp_path / "cwd"
    unrelated_cwd.mkdir()
    monkeypatch.chdir(unrelated_cwd)
    monkeypatch.delenv("LEXIQUEST_VOICE_SAMPLE_RATE", raising=False)

    settings = Settings(_env_file=env_path)

    assert settings.sample_rate == 48000


def test_voxcpm2_is_the_default_standard_speech_backend() -> None:
    settings = Settings()

    assert settings.engine_backend == "voxcpm2"
    assert settings.provider_enabled is True
    assert settings.voxcpm_model_id == "openbmb/VoxCPM2"
    assert settings.voxcpm_model_version == "2.0.3"
    assert settings.voxcpm_sample_rate == 48_000
    assert 1 <= settings.max_concurrent_requests <= 8


def test_engine_backend_rejects_unknown_values() -> None:
    with pytest.raises(ValidationError):
        Settings(engine_backend="unknown")


def test_mirror_defaults_are_disabled_and_retention_is_bounded() -> None:
    settings = Settings()

    assert settings.mirror_enabled is False
    assert settings.mirror_consent_version == "voice-mirror-v1"
    assert settings.mirror_lease_seconds == 300
    assert settings.mirror_absolute_lifetime_seconds == 1200
    assert settings.mirror_max_reference_bytes == 2 * 1024 * 1024
    assert settings.mirror_max_requests == 20
    assert settings.mirror_max_characters == 4000
    assert settings.mirror_max_text_length == 300

    with pytest.raises(ValidationError):
        Settings(mirror_lease_seconds=301)
    with pytest.raises(ValidationError):
        Settings(mirror_absolute_lifetime_seconds=1201)
    with pytest.raises(ValidationError):
        Settings(mirror_max_reference_bytes=0)
    with pytest.raises(ValidationError):
        Settings(mirror_enabled=True, engine_backend="omnivoice")
