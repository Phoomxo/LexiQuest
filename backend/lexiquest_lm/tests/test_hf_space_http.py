"""CPU-only HTTP contracts for the standalone model service."""

from __future__ import annotations

import importlib
import os
from pathlib import Path
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from contextlib import nullcontext
from types import SimpleNamespace

from fastapi.testclient import TestClient
import pytest

from deploy.hf_space.auth import FirebaseTokenVerifier


_ROOT = Path(__file__).resolve().parent.parent
_REVISION = "0123456789abcdef0123456789abcdef01234567"
_AUTH = {"Authorization": "Bearer synthetic-valid-token"}


def _module():
    return importlib.import_module("deploy.hf_space.app")


def _verifier(configured=True):
    def decode(token):
        if token != "synthetic-valid-token":
            raise ValueError("synthetic revoked token")
        return {"uid": "synthetic-owner"}
    return FirebaseTokenVerifier("synthetic-project" if configured else None, decode)


class _Generator:
    def __init__(self):
        self.calls = []
        self.fail = False
        self.text = "A cat sleeps."

    def generate(self, prompt, max_new_tokens):
        self.calls.append((prompt, max_new_tokens))
        if self.fail:
            raise RuntimeError("must not be returned to the caller")
        return _module().GenerationResult(self.text, 20, 4)


def _app(generator=None, **kwargs):
    serving = _module()
    settings = kwargs.pop("settings", serving.ServingSettings(
        model_id="synthetic-owner/lexiquest-lm", model_revision=_REVISION,
        max_input_tokens=64, max_new_tokens=16,
    ))
    return serving.create_app(settings=settings, token_verifier=_verifier(),
                              generator=generator, **kwargs)


def test_import_has_no_model_or_firebase_sdk_side_effects():
    code = """
import importlib.abc, sys
class RejectHeavyImports(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname.split('.')[0] in {'torch', 'transformers', 'firebase_admin'}:
            raise AssertionError('heavy dependency imported: ' + fullname)
sys.meta_path.insert(0, RejectHeavyImports())
import deploy.hf_space.app
"""
    result = subprocess.run([sys.executable, "-c", code], cwd=_ROOT,
                            env={**os.environ, "MODEL_ID": "", "MODEL_REVISION": ""},
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize("kind", ["sentence", "story", "explanation"])
@pytest.mark.parametrize("language", ["en", "th"])
def test_flutter_content_contract(kind, language):
    generator = _Generator()
    with TestClient(_app(generator)) as client:
        assert client.get("/health/live").status_code == 200
        assert client.get("/health/ready").status_code == 200
        response = client.post("/v1/content", headers=_AUTH, json={
            "text": "  cat\n  sleeps  ", "kind": kind, "cefr": "a1", "language": language,
        })
    assert response.status_code == 200
    assert response.json() == {
        "text": "A cat sleeps.", "kind": kind, "cefr": "a1", "language": language,
        "model_version": f"synthetic-owner/lexiquest-lm@{_REVISION}", "cached": False,
    }
    assert len(generator.calls) == 1
    assert "cat sleeps" in generator.calls[0][0]
    assert "CEFR a1" in generator.calls[0][0]
    assert ("Thai" if language == "th" else "English") in generator.calls[0][0]


@pytest.mark.parametrize("header", [None, "Bearer", "Basic synthetic", "Bearer synthetic-revoked"])
@pytest.mark.parametrize("route,payload", [
    ("/v1/content", {"text": "cat", "kind": "sentence"}),
    ("/v1/chat/completions", {"messages": [{"role": "user", "content": "cat"}]}),
])
def test_authentication_rejects_missing_invalid_and_revoked_tokens(header, route, payload):
    generator = _Generator()
    with TestClient(_app(generator)) as client:
        response = client.post(route, json=payload,
                               headers={} if header is None else {"Authorization": header})
    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "UNAUTHENTICATED"
    assert generator.calls == []


@pytest.mark.parametrize("change", [
    {"text": " "}, {"text": "x" * 2001}, {"kind": "unknown"},
    {"cefr": "A1"}, {"language": "xx"}, {"model": "client-cannot-choose-model"},
])
def test_content_boundary_rejects_invalid_request(change):
    generator = _Generator()
    with TestClient(_app(generator)) as client:
        response = client.post("/v1/content", headers=_AUTH,
                               json={"text": "cat", "kind": "sentence", **change})
    assert response.status_code == 422
    assert generator.calls == []


@pytest.mark.parametrize("revision", ["", "main", "v1", "f" * 39, "g" * 40])
def test_unpinned_model_never_loads_or_serves(revision):
    serving = _module()
    loads = []
    settings = serving.ServingSettings(model_id="synthetic-owner/lexiquest-lm",
                                       model_revision=revision)
    with TestClient(_app(settings=settings, model_loader=lambda settings: loads.append(settings))) as client:
        assert client.get("/health/live").status_code == 200
        assert client.get("/health/ready").status_code == 503
        assert client.post("/v1/content", headers=_AUTH,
                           json={"text": "cat", "kind": "sentence"}).status_code == 503
    assert loads == []


@pytest.mark.parametrize("route,payload,expected_code", [
    ("/v1/content", {"text": "cat", "kind": "sentence"}, "PROVIDER_UNAVAILABLE"),
    ("/v1/chat/completions", {"messages": [{"role": "user", "content": "cat"}]}, "SERVICE_UNAVAILABLE"),
])
def test_loader_failure_keeps_liveness_and_fails_readiness(route, payload, expected_code):
    def fail(settings):
        raise RuntimeError("synthetic unavailable model")
    with TestClient(_app(model_loader=fail)) as client:
        assert client.get("/health/live").status_code == 200
        assert client.get("/health/ready").status_code == 503
        response = client.post(route, headers=_AUTH, json=payload)
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == expected_code


@pytest.mark.parametrize("model_id", ["", "https://example.invalid/model", "../local-model", "owner/..", "owner/model/extra"])
def test_missing_or_invalid_model_repository_never_loads(model_id):
    serving = _module()
    loads = []
    settings = serving.ServingSettings(model_id=model_id, model_revision=_REVISION)
    with TestClient(_app(settings=settings, model_loader=lambda settings: loads.append(settings))) as client:
        assert client.get("/health/ready").status_code == 503
    assert loads == []


@pytest.mark.parametrize("name", ["MAX_INPUT_TOKENS", "MAX_NEW_TOKENS"])
@pytest.mark.parametrize("value", ["0", "-1", "invalid"])
def test_invalid_token_limits_fail_closed_without_loading(monkeypatch, name, value):
    monkeypatch.setenv("MODEL_ID", "synthetic-owner/lexiquest-lm")
    monkeypatch.setenv("MODEL_REVISION", _REVISION)
    monkeypatch.setenv(name, value)
    loads = []
    app = _module().create_app(token_verifier=_verifier(),
                               model_loader=lambda settings: loads.append(settings))
    with TestClient(app) as client:
        assert client.get("/health/ready").status_code == 503
    assert loads == []


def test_unconfigured_firebase_does_not_load_or_serve():
    serving = _module()
    loads = []
    app = serving.create_app(
        settings=serving.ServingSettings(model_id="synthetic-owner/lexiquest-lm", model_revision=_REVISION),
        token_verifier=_verifier(configured=False),
        model_loader=lambda settings: loads.append(settings),
    )
    with TestClient(app) as client:
        assert client.get("/health/ready").status_code == 503
        assert client.post("/v1/content", headers=_AUTH,
                           json={"text": "cat", "kind": "sentence"}).status_code == 401
    assert loads == []


def test_real_generation_adapter_uses_pinned_model_and_both_token_caps(monkeypatch, tmp_path):
    calls = {}
    class Tokens(list):
        @property
        def shape(self):
            return (len(self),)
        def __getitem__(self, key):
            value = super().__getitem__(key)
            return Tokens(value) if isinstance(key, slice) else value
    class Batch(dict):
        def to(self, device):
            calls["device"] = device
            return self
    class Tokenizer:
        pad_token = None
        eos_token = "end"
        pad_token_id = 1
        eos_token_id = 1
        unk_token_id = 0
        def __call__(self, prompt, **kwargs):
            calls["tokenizer"] = kwargs
            count = min(len(prompt.split()), kwargs["max_length"])
            return Batch(input_ids=SimpleNamespace(shape=(1, count)))
        def convert_tokens_to_ids(self, token):
            return 2
        def decode(self, tokens, **kwargs):
            calls["decoded_tokens"] = len(tokens)
            return "A cat sleeps."
    class Model:
        device = "cpu"
        def eval(self):
            calls["eval"] = True
        def generate(self, input_ids, **kwargs):
            calls["generation"] = kwargs
            return [Tokens(range(input_ids.shape[1] + kwargs["max_new_tokens"]))]
    def tokenizer_load(model_id, **kwargs):
        calls["tokenizer_load"] = (model_id, kwargs)
        return Tokenizer()
    def model_load(model_id, **kwargs):
        calls["model_load"] = (model_id, kwargs)
        return Model()
    def download(**kwargs):
        calls["download"] = kwargs
        return str(tmp_path)
    (tmp_path / "config.json").write_text("{}")
    (tmp_path / "model.safetensors").write_bytes(b"synthetic weights")
    monkeypatch.setitem(sys.modules, "huggingface_hub", SimpleNamespace(snapshot_download=download))
    monkeypatch.setitem(sys.modules, "torch", SimpleNamespace(float32="float32", no_grad=nullcontext))
    monkeypatch.setitem(sys.modules, "transformers", SimpleNamespace(
        AutoTokenizer=SimpleNamespace(from_pretrained=tokenizer_load),
        AutoModelForCausalLM=SimpleNamespace(from_pretrained=model_load),
    ))
    monkeypatch.setenv("MODEL_ID", "synthetic-owner/lexiquest-lm")
    monkeypatch.setenv("MODEL_REVISION", _REVISION)
    monkeypatch.setenv("MAX_INPUT_TOKENS", "7")
    monkeypatch.setenv("MAX_NEW_TOKENS", "3")
    with TestClient(_module().create_app(token_verifier=_verifier())) as client:
        response = client.post("/v1/chat/completions", headers=_AUTH, json={
            "messages": [{"role": "user", "content": "cat " * 100}], "max_tokens": 1000,
        })
    assert response.status_code == 200
    assert response.json()["usage"] == {"prompt_tokens": 7, "completion_tokens": 3, "total_tokens": 10}
    assert calls["tokenizer"] == {"return_tensors": "pt", "truncation": True, "max_length": 7}
    assert calls["generation"]["max_new_tokens"] == 3
    assert calls["generation"]["do_sample"] is False
    assert set(calls["generation"]["eos_token_id"]) == {1, 2}
    for name in ("tokenizer_load", "model_load"):
        assert calls[name][0] == tmp_path
        assert calls[name][1]["local_files_only"] is True
        assert calls[name][1]["trust_remote_code"] is False
    assert calls["download"]["repo_id"] == "synthetic-owner/lexiquest-lm"
    assert calls["download"]["revision"] == _REVISION
    assert calls["model_load"][1]["use_safetensors"] is True
    assert calls["device"] == "cpu"
    assert calls["eval"] is True


@pytest.mark.parametrize("files", [
    [], ["adapter_config.json", "adapter_model.safetensors"], ["config.json"],
    ["config.json", "model.safetensors", "adapter_config.json"],
])
def test_missing_or_adapter_only_snapshot_fails_closed(monkeypatch, tmp_path, files):
    for name in files:
        (tmp_path / name).write_text("synthetic incomplete model artifact")
    model_loads = []
    monkeypatch.setitem(sys.modules, "torch", SimpleNamespace())
    monkeypatch.setitem(sys.modules, "huggingface_hub", SimpleNamespace(snapshot_download=lambda **kwargs: str(tmp_path)))
    monkeypatch.setitem(sys.modules, "transformers", SimpleNamespace(
        AutoTokenizer=SimpleNamespace(from_pretrained=lambda *args, **kwargs: model_loads.append(args)),
        AutoModelForCausalLM=SimpleNamespace(from_pretrained=lambda *args, **kwargs: model_loads.append(args)),
    ))
    with TestClient(_app()) as client:
        assert client.get("/health/ready").status_code == 503
        assert client.post("/v1/content", headers=_AUTH,
                           json={"text": "cat", "kind": "sentence"}).status_code == 503
    assert model_loads == []


@pytest.mark.parametrize("maximum,expected", [(-2, 1), (0, 1), (3, 3), (1000, 16), (None, 16)])
def test_chat_generation_uses_bounded_tokens_and_preserves_response(maximum, expected):
    generator = _Generator()
    with TestClient(_app(generator)) as client:
        response = client.post("/v1/chat/completions", headers=_AUTH, json={
            "messages": [{"role": "user", "content": "cat"}],
            "max_tokens": maximum, "temperature": 0.8,
        })
    assert response.status_code == 200
    assert response.json()["choices"][0]["message"]["content"] == "A cat sleeps."
    assert response.json()["usage"] == {"prompt_tokens": 20, "completion_tokens": 4, "total_tokens": 24}
    assert generator.calls[0][1] == expected


@pytest.mark.parametrize("route,payload,expected_code", [
    ("/v1/content", {"text": "cat", "kind": "sentence"}, "CONTENT_GENERATION_FAILED"),
    ("/v1/chat/completions", {"messages": [{"role": "user", "content": "cat"}]}, "GENERATION_FAILED"),
])
def test_generation_failure_releases_capacity_and_hides_details(route, payload, expected_code):
    generator = _Generator()
    generator.fail = True
    with TestClient(_app(generator)) as client:
        failed = client.post(route, headers=_AUTH, json=payload)
        generator.fail = False
        recovered = client.post(route, headers=_AUTH, json=payload)
    assert failed.status_code == 503
    assert failed.json()["detail"]["code"] == expected_code
    assert "must not be returned" not in failed.text
    assert recovered.status_code == 200


def test_empty_generation_does_not_claim_a_valid_content_result():
    generator = _Generator()
    generator.text = "  "
    with TestClient(_app(generator)) as client:
        failed = client.post("/v1/content", headers=_AUTH, json={"text": "cat", "kind": "sentence"})
        generator.text = "A cat sleeps."
        recovered = client.post("/v1/content", headers=_AUTH, json={"text": "cat", "kind": "sentence"})
    assert failed.status_code == 503
    assert failed.json()["detail"]["code"] == "CONTENT_GENERATION_FAILED"
    assert recovered.status_code == 200


@pytest.mark.parametrize("route,payload,expected_status,expected_code", [
    ("/v1/content", {"text": "cat", "kind": "sentence"}, 429, "RATE_LIMITED"),
    ("/v1/chat/completions", {"messages": [{"role": "user", "content": "cat"}]}, 503, "BUSY"),
])
def test_busy_generation_does_not_queue_another_request(route, payload, expected_status, expected_code):
    entered = threading.Event()
    release = threading.Event()
    class BlockingGenerator(_Generator):
        def generate(self, prompt, max_new_tokens):
            entered.set()
            assert release.wait(5)
            return super().generate(prompt, max_new_tokens)
    generator = BlockingGenerator()
    with TestClient(_app(generator)) as client, ThreadPoolExecutor(max_workers=1) as executor:
        first = executor.submit(client.post, route, headers=_AUTH, json=payload)
        try:
            assert entered.wait(5)
            second = client.post(route, headers=_AUTH, json=payload)
        finally:
            release.set()
        assert first.result().status_code == 200
    assert second.status_code == expected_status
    assert second.json()["detail"]["code"] == expected_code
    assert len(generator.calls) == 1


@pytest.mark.parametrize("header,body,expected", [
    ("invalid", b"{}", 400), ("-1", b"{}", 400),
    ("100001", b"{}", 413), (None, b"x" * 100001, 413),
    ("2", b"x" * 100001, 413),
], ids=["malformed", "negative", "declared-oversize", "chunked-oversize", "misleading-length"])
def test_actual_body_limit_rejects_malformed_or_oversize_streams(header, body, expected):
    app = _app(_Generator())
    import asyncio
    async def run():
        messages = [
            {"type": "http.request", "body": body[:50000], "more_body": True},
            {"type": "http.request", "body": body[50000:], "more_body": False},
        ]
        sent = []
        async def receive():
            return messages.pop(0)
        async def send(message):
            sent.append(message)
        scope = {"type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1",
                 "method": "POST", "scheme": "http", "path": "/v1/content", "raw_path": b"/v1/content",
                 "query_string": b"", "server": ("test", 80), "client": ("test", 1),
                 "headers": [] if header is None else [(b"content-length", header.encode())]}
        await app(scope, receive, send)
        return sent
    assert asyncio.run(run())[0]["status"] == expected
