"""Tests for Settings configuration and environment loading."""

from __future__ import annotations

from pathlib import Path

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
