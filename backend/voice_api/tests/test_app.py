from __future__ import annotations

import asyncio
import json
import logging

import pytest
from fastapi.testclient import TestClient
from starlette.requests import ClientDisconnect

from lexiquest_voice.app import create_app
from lexiquest_voice.config import Settings

from conftest import (
    FailingSpeechEngine,
    FakeSpeechEngine,
    FakeTokenVerifier,
    UnavailableSpeechEngine,
)

# Valid speech-request body shared by the length-limit tests, minus the
# ``text`` field each test supplies individually.
_SPEECH_BODY = {
    "language": "en",
    "voice": "teacher_female",
    "speed": 1.0,
}


class _CountingSpeechEngine(FakeSpeechEngine):
    def __init__(self):
        self.calls = []

    def synthesize(self, request):
        self.calls.append(request)
        return super().synthesize(request)


class _BodyExchange:
    """Deliver actual ASGI chunks without an HTTP client fixing their headers."""

    def __init__(self, messages):
        self.messages = messages
        self.read_count = 0
        self.sent = []

    async def run(self, app, headers):
        async def receive():
            if self.read_count < len(self.messages):
                message = self.messages[self.read_count]
                self.read_count += 1
                return message
            # A completed body is not a disconnect. Wait until the response
            # finishes; middleware may concurrently listen for disconnects.
            await asyncio.Event().wait()

        async def send(message):
            self.sent.append(message)

        await asyncio.wait_for(
            app(
                {
                    "type": "http",
                    "asgi": {"version": "3.0", "spec_version": "2.4"},
                    "http_version": "1.1",
                    "method": "POST",
                    "scheme": "http",
                    "path": "/v1/speech",
                    "raw_path": b"/v1/speech",
                    "query_string": b"",
                    "root_path": "",
                    "headers": [(b"content-type", b"application/json"), *headers],
                    "client": ("127.0.0.1", 12345),
                    "server": ("testserver", 80),
                },
                receive,
                send,
            ),
            timeout=5,
        )

    @property
    def status(self):
        starts = [item for item in self.sent if item["type"] == "http.response.start"]
        assert len(starts) == 1
        return starts[0]["status"]

    @property
    def body(self):
        return b"".join(
            item.get("body", b"")
            for item in self.sent
            if item["type"] == "http.response.body"
        )


def _body_headers(mode, size, authenticated=True):
    headers = []
    if authenticated:
        headers.append((b"authorization", b"Bearer valid-token"))
    if mode == "declared":
        headers.append((b"content-length", str(size).encode("ascii")))
    elif mode == "lying":
        headers.append((b"content-length", b"1"))
    elif mode == "chunked":
        headers.append((b"transfer-encoding", b"chunked"))
    return headers


def _padded_body(size):
    # JSON whitespace tests transport size without hitting the text/schema
    # ceiling. Non-ASCII text also distinguishes byte counts from characters.
    body = json.dumps(
        {"text": "แมว", **_SPEECH_BODY}, ensure_ascii=False
    ).encode("utf-8")
    assert len(body) <= size
    return body + b" " * (size - len(body))


def _body_app():
    provider = _CountingSpeechEngine()
    return create_app(
        engine=provider,
        token_verifier=FakeTokenVerifier(),
        settings=Settings(),
    ), provider


@pytest.mark.parametrize("mode", ["missing", "lying", "chunked", "declared"])
@pytest.mark.parametrize("authenticated", [False, True])
def test_asgi_body_limit_rejects_oversize_before_provider(mode, authenticated):
    app, provider = _body_app()
    body = _padded_body(100_001)
    exchange = _BodyExchange([
        {"type": "http.request", "body": body[:50_000], "more_body": True},
        {"type": "http.request", "body": body[50_000:100_000], "more_body": True},
        {"type": "http.request", "body": body[100_000:], "more_body": True},
        # Rejection must not drain the rest of a potentially unbounded stream.
        {"type": "http.request", "body": b" ", "more_body": False},
    ])

    asyncio.run(exchange.run(app, _body_headers(mode, len(body), authenticated)))

    assert exchange.status == 413
    assert json.loads(exchange.body)["detail"]["code"] == "PAYLOAD_TOO_LARGE"
    assert provider.calls == []
    assert exchange.read_count == (0 if mode == "declared" else 3)


@pytest.mark.parametrize("mode", ["missing", "lying", "chunked", "declared"])
@pytest.mark.parametrize("size", [99_999, 100_000])
def test_asgi_body_limit_replays_valid_body_at_boundary(mode, size):
    app, provider = _body_app()
    body = _padded_body(size)
    exchange = _BodyExchange([
        {"type": "http.request", "body": body[:17], "more_body": True},
        {"type": "http.request", "body": b"", "more_body": True},
        {"type": "http.request", "body": body[17:50_000], "more_body": True},
        {"type": "http.request", "body": body[50_000:], "more_body": False},
    ])

    asyncio.run(exchange.run(app, _body_headers(mode, size)))

    assert exchange.status == 200
    assert len(provider.calls) == 1
    assert provider.calls[0].text == "แมว"
    assert exchange.body == b"RIFF-test-wav"
    assert exchange.read_count == 4


@pytest.mark.parametrize("body", [b"", b'{"text":'])
def test_asgi_body_limit_preserves_invalid_json_rejection(body):
    app, provider = _body_app()
    exchange = _BodyExchange([
        {"type": "http.request", "body": body, "more_body": False},
    ])

    asyncio.run(exchange.run(app, _body_headers("missing", len(body))))

    assert exchange.status == 422
    assert provider.calls == []


def test_asgi_body_limit_disconnect_does_not_invoke_provider():
    app, provider = _body_app()
    exchange = _BodyExchange([
        {"type": "http.request", "body": b'{"text":', "more_body": True},
        {"type": "http.disconnect"},
    ])

    try:
        asyncio.run(exchange.run(app, _body_headers("missing", 0)))
    except ClientDisconnect:
        # ASGI may propagate the transport disconnect instead of replying.
        pass

    assert exchange.read_count == 2
    assert provider.calls == []
    starts = [item for item in exchange.sent if item["type"] == "http.response.start"]
    assert all(400 <= item["status"] < 500 for item in starts)


def test_health_endpoints(client: TestClient) -> None:
    assert client.get("/health/live").json() == {"status": "live"}
    assert client.get("/health/ready").json() == {"status": "ready"}


def test_speech_rejects_missing_token(client: TestClient) -> None:
    response = client.post(
        "/v1/speech",
        json={
            "text": "Cat",
            "language": "en",
            "voice": "teacher_female",
            "speed": 1.0,
        },
    )

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "UNAUTHENTICATED"


def test_speech_returns_wav_with_provenance_headers(
    client: TestClient,
) -> None:
    response = client.post(
        "/v1/speech",
        headers={"Authorization": "Bearer valid-token"},
        json={
            "text": "Cat",
            "language": "en",
            "voice": "teacher_female",
            "speed": 1.0,
        },
    )

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/wav"
    assert response.headers["x-voice-engine"] == "fake-omnivoice"
    assert response.headers["x-model-version"] == "test"
    assert response.headers["x-audio-sample-rate"] == "24000"
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-request-id"]
    assert response.content == b"RIFF-test-wav"


def test_ready_returns_503_when_engine_is_unavailable(
    token_verifier: FakeTokenVerifier,
) -> None:
    app = create_app(
        engine=UnavailableSpeechEngine(),
        token_verifier=token_verifier,
        settings=Settings(),
    )
    response = TestClient(app).get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "detail": {
            "code": "MODEL_UNAVAILABLE",
            "message": "The speech engine is not ready.",
        }
    }


def test_speech_enforces_configured_text_length(
    token_verifier: FakeTokenVerifier,
) -> None:
    """The configured ``max_text_length`` must drive the HTTP limit."""

    settings = Settings(max_text_length=10)
    app = create_app(
        engine=FakeSpeechEngine(),
        token_verifier=token_verifier,
        settings=settings,
    )

    response = TestClient(app).post(
        "/v1/speech",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "x" * 11, **_SPEECH_BODY},
    )

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "TEXT_TOO_LONG"


def test_speech_accepts_text_at_configured_text_length(
    token_verifier: FakeTokenVerifier,
) -> None:
    """Text at exactly the configured limit is accepted (boundary)."""

    settings = Settings(max_text_length=10)
    app = create_app(
        engine=FakeSpeechEngine(),
        token_verifier=token_verifier,
        settings=settings,
    )

    response = TestClient(app).post(
        "/v1/speech",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "x" * 10, **_SPEECH_BODY},
    )

    assert response.status_code == 200


def test_speech_schema_ceiling_still_rejects_oversized_text(
    token_verifier: FakeTokenVerifier,
) -> None:
    """An absolute schema ceiling remains as a backstop above the limit."""

    settings = Settings(max_text_length=10)
    app = create_app(
        engine=FakeSpeechEngine(),
        token_verifier=token_verifier,
        settings=settings,
    )

    response = TestClient(app).post(
        "/v1/speech",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "x" * 2001, **_SPEECH_BODY},
    )

    assert response.status_code == 422


def test_speech_failure_hides_secret_detail_and_correlates_request_id(
    token_verifier: FakeTokenVerifier,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A synthesis failure returns a safe 503 correlated by ``request_id`` and
    never leaks the secret request text or the internal exception message."""

    secret_text = "TOPSECRET-payload-7c9f3a"
    app = create_app(
        engine=FailingSpeechEngine(),
        token_verifier=token_verifier,
        settings=Settings(),
    )

    with caplog.at_level(logging.ERROR):
        response = TestClient(app).post(
            "/v1/speech",
            headers={"Authorization": "Bearer valid-token"},
            json={"text": secret_text, **_SPEECH_BODY},
        )

    # Status and the stable failure contract.
    assert response.status_code == 503
    detail = response.json()["detail"]
    assert detail["code"] == "SYNTHESIS_FAILED"
    assert detail["message"] == "Speech synthesis could not be completed."
    assert response.headers["Retry-After"] == "5"

    # The same request_id appears in both the body and the response header.
    request_id = detail["request_id"]
    assert request_id
    assert request_id == response.headers["X-Request-ID"]
    assert request_id in caplog.text

    # The secret request text and the internal exception message must never
    # appear in either the response body or the captured log.
    captured = f"{response.text}\n{caplog.text}"
    assert secret_text not in captured
    assert FailingSpeechEngine.internal_error_message not in captured

    # The log records the failure with the exception type only.
    assert "RuntimeError" in caplog.text
