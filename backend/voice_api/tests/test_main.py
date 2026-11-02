from __future__ import annotations

import builtins
import importlib
import sys
from collections.abc import Iterator
from typing import Any

import pytest
from fastapi.testclient import TestClient

import lexiquest_voice
from lexiquest_voice import auth, config
from lexiquest_voice.engines import omnivoice_engine

from conftest import FakeSpeechEngine, FakeTokenVerifier


@pytest.fixture(autouse=True)
def isolated_assembly(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    settings = config.Settings(_env_file=None)
    monkeypatch.setattr(config, "Settings", lambda: settings)
    monkeypatch.setattr(auth, "FirebaseTokenVerifier", FakeTokenVerifier)
    monkeypatch.delitem(sys.modules, "lexiquest_voice.main", raising=False)
    monkeypatch.delattr(lexiquest_voice, "main", raising=False)
    yield
    sys.modules.pop("lexiquest_voice.main", None)
    if hasattr(lexiquest_voice, "main"):
        delattr(lexiquest_voice, "main")


def test_policy_rejection_keeps_http_live_without_heavy_load_or_request_retry(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    versions = {
        "torch": "2.11.0+cu128",
        "torchaudio": "2.11.0+cu128",
        "omnivoice": "0.2.1",
        "setuptools": "81.0.0",
    }
    inspected: list[str] = []

    def version_of(package: str) -> str:
        inspected.append(package)
        return versions[package]

    monkeypatch.setattr(
        "lexiquest_voice.runtime_compat.importlib.metadata.version", version_of
    )
    original_import = builtins.__import__

    def checked_import(name: str, *args: Any, **kwargs: Any) -> Any:
        if name.partition(".")[0] in {
            "torch", "torchaudio", "omnivoice", "huggingface_hub", "soundfile"
        }:
            pytest.fail(f"Policy rejection attempted a heavy import: {name}")
        return original_import(name, *args, **kwargs)

    def forbidden_loader(settings: config.Settings) -> Any:
        pytest.fail("Policy rejection reached the model loader.")

    monkeypatch.setattr(builtins, "__import__", checked_import)
    monkeypatch.setattr(omnivoice_engine, "_load_model", forbidden_loader)

    main = importlib.import_module("lexiquest_voice.main")
    assert isinstance(main.engine, omnivoice_engine.OmniVoiceEngine)
    assert main.engine.is_ready is False
    assert inspected == ["torch", "torchaudio", "omnivoice", "setuptools"]
    client = TestClient(main.app)
    assert client.get("/health/live").json() == {"status": "live"}
    ready = client.get("/health/ready")
    assert ready.status_code == 503
    assert ready.json()["detail"]["code"] == "MODEL_UNAVAILABLE"

    body = {"text": "Cat", "language": "en", "voice": "teacher_female", "speed": 1.0}
    assert client.post("/v1/speech", json=body).status_code == 401
    for _ in range(2):
        response = client.post(
            "/v1/speech", json=body,
            headers={"Authorization": "Bearer valid-token"},
        )
        assert response.status_code == 503
        assert response.json()["detail"]["code"] == "MODEL_UNAVAILABLE"
    assert inspected == ["torch", "torchaudio", "omnivoice", "setuptools"]
    assert "Speech engine startup blocked by runtime policy." in caplog.text
    assert "2.11.0" not in caplog.text


def test_healthy_assembly_loads_once_before_serving(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[str] = []

    class StartupEngine(FakeSpeechEngine):
        def load(self) -> object:
            calls.append("load")
            return self

    engine = StartupEngine()
    monkeypatch.setattr(
        omnivoice_engine, "OmniVoiceEngine", lambda **kwargs: engine
    )
    main = importlib.import_module("lexiquest_voice.main")
    client = TestClient(main.app)
    assert client.get("/health/ready").json() == {"status": "ready"}
    response = client.post(
        "/v1/speech", headers={"Authorization": "Bearer valid-token"},
        json={"text": "Cat", "language": "en", "voice": "teacher_female", "speed": 1.0},
    )
    assert response.status_code == 200
    assert response.content == b"RIFF-test-wav"
    assert calls == ["load"]


def test_unexpected_startup_failure_still_propagates(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class BrokenEngine(FakeSpeechEngine):
        def load(self) -> object:
            raise RuntimeError("synthetic unexpected startup failure")

    monkeypatch.setattr(
        omnivoice_engine, "OmniVoiceEngine", lambda **kwargs: BrokenEngine()
    )
    with pytest.raises(RuntimeError, match="synthetic unexpected startup failure"):
        importlib.import_module("lexiquest_voice.main")
