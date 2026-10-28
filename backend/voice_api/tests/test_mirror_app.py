from __future__ import annotations

from typing import Any

import pytest
from fastapi.testclient import TestClient

from lexiquest_voice.app import create_app
from lexiquest_voice.auth import AuthenticatedUser
from lexiquest_voice.config import Settings
from lexiquest_voice.mirror_sessions import MirrorSessionStore
from lexiquest_voice.models import AudioResult

from conftest import FakeSpeechEngine

_WAV = b"RIFF\x24\x00\x00\x00WAVE" + bytes(range(32))


class FakeClock:
    def __init__(self) -> None:
        self.value = 1_000_000.0

    def now_utc(self) -> float:
        return self.value

    def advance(self, seconds: float) -> None:
        self.value += seconds


class TokenMap:
    def verify(self, token: str) -> AuthenticatedUser:
        users = {"owner-token": "owner", "other-token": "other"}
        uid = users.get(token)
        if uid is None:
            raise ValueError("invalid fixture token")
        return AuthenticatedUser(uid=uid)


class FakeMirrorEngine:
    def __init__(self) -> None:
        self.calls: list[dict[str, object]] = []
        self.failure: Exception | None = None

    def synthesize(self, *, text: str, reference_audio: bytes) -> AudioResult:
        self.calls.append({"text": text, "reference_audio": reference_audio})
        if self.failure is not None:
            raise self.failure
        return AudioResult(
            data=b"RIFF-generated",
            media_type="audio/wav",
            sample_rate=48_000,
            engine="voxcpm2-mirror",
            model_version="2.0.3",
        )


def _settings(**changes: Any) -> Settings:
    values = {
        "mirror_enabled": True,
        "mirror_max_reference_bytes": 65_536,
        "mirror_max_requests": 2,
        "mirror_max_characters": 20,
        "mirror_max_text_length": 10,
        **changes,
    }
    return Settings(**values)


def _client(
    *,
    settings: Settings | None = None,
) -> tuple[TestClient, FakeClock, FakeMirrorEngine, MirrorSessionStore]:
    resolved = settings or _settings()
    clock = FakeClock()
    mirror_engine = FakeMirrorEngine()
    sessions = MirrorSessionStore(
        clock=clock,
        lease_duration=resolved.mirror_lease_seconds,
        absolute_lifetime=resolved.mirror_absolute_lifetime_seconds,
        max_requests=resolved.mirror_max_requests,
        max_characters=resolved.mirror_max_characters,
    )
    app = create_app(
        engine=FakeSpeechEngine(),
        token_verifier=TokenMap(),
        settings=resolved,
        mirror_engine=mirror_engine,
        mirror_sessions=sessions,
    )
    return TestClient(app), clock, mirror_engine, sessions


def _auth(token: str = "owner-token") -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _enroll(
    client: TestClient,
    *,
    audio: bytes = _WAV,
    token: str = "owner-token",
    consent: str = "voice-mirror-v1",
    content_type: str = "audio/wav",
) -> Any:
    return client.post(
        "/v1/voice-mirror/sessions",
        content=audio,
        headers={
            **_auth(token),
            "Content-Type": content_type,
            "X-Voice-Mirror-Consent": consent,
        },
    )


def _speech(
    client: TestClient,
    session_id: str,
    *,
    token: str = "owner-token",
    text: str = "Cat",
) -> Any:
    return client.post(
        f"/v1/voice-mirror/sessions/{session_id}/speech",
        headers=_auth(token),
        json={"contentId": "word-cat", "text": text, "language": "en"},
    )


def test_mirror_kill_switch_blocks_enrollment_before_storage() -> None:
    client, _, engine, sessions = _client(
        settings=_settings(mirror_enabled=False),
    )

    response = _enroll(client)

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "PROVIDER_DISABLED"
    assert response.headers["cache-control"] == "no-store"
    assert engine.calls == []
    assert sessions.purge_expired() == 0


@pytest.mark.parametrize(
    ("headers", "audio", "expected"),
    [
        ({}, _WAV, 401),
        (
            {
                **_auth(),
                "Content-Type": "audio/wav",
                "X-Voice-Mirror-Consent": "wrong",
            },
            _WAV,
            403,
        ),
        (
            {
                **_auth(),
                "Content-Type": "audio/mpeg",
                "X-Voice-Mirror-Consent": "voice-mirror-v1",
            },
            _WAV,
            415,
        ),
        (
            {
                **_auth(),
                "Content-Type": "audio/wav",
                "X-Voice-Mirror-Consent": "voice-mirror-v1",
            },
            b"not-wave",
            422,
        ),
    ],
)
def test_enrollment_rejects_invalid_boundaries(
    headers: dict[str, str],
    audio: bytes,
    expected: int,
) -> None:
    client, _, engine, _ = _client()

    response = client.post(
        "/v1/voice-mirror/sessions",
        content=audio,
        headers=headers,
    )

    assert response.status_code == expected
    assert response.headers["cache-control"] == "no-store"
    assert engine.calls == []


def test_enrollment_rejects_oversized_body() -> None:
    client, _, engine, _ = _client()
    audio = _WAV + bytes(65_537 - len(_WAV))

    response = _enroll(client, audio=audio)

    assert response.status_code == 413
    assert engine.calls == []


def test_successful_owner_lifecycle_is_uncached_and_zeroes_reference() -> None:
    client, clock, engine, sessions = _client()
    enrolled = _enroll(client)
    assert enrolled.status_code == 201
    assert enrolled.headers["cache-control"] == "no-store"
    body = enrolled.json()
    session_id = body["sessionId"]
    assert body["leaseExpiresAtEpochMs"] == int((clock.value + 300) * 1000)
    assert body["absoluteExpiresAtEpochMs"] == int(
        (clock.value + 1200) * 1000
    )
    buffer = sessions._debug_reference_buffer(session_id)

    clock.advance(200)
    heartbeat = client.post(
        f"/v1/voice-mirror/sessions/{session_id}/heartbeat",
        headers=_auth(),
    )
    assert heartbeat.status_code == 200
    assert heartbeat.headers["cache-control"] == "no-store"

    generated = _speech(client, session_id)
    assert generated.status_code == 200
    assert generated.content == b"RIFF-generated"
    assert generated.headers["cache-control"] == "no-store"
    assert generated.headers["x-voice-engine"] == "voxcpm2-mirror"
    assert engine.calls == [{"text": "Cat", "reference_audio": _WAV}]

    assert (
        client.delete(
            f"/v1/voice-mirror/sessions/{session_id}",
            headers=_auth(),
        ).status_code
        == 204
    )
    assert not any(buffer)
    assert _speech(client, session_id).status_code == 404
    assert (
        client.delete(
            f"/v1/voice-mirror/sessions/{session_id}",
            headers=_auth(),
        ).status_code
        == 204
    )


def test_another_account_cannot_observe_or_use_a_session() -> None:
    client, _, engine, _ = _client()
    session_id = _enroll(client).json()["sessionId"]

    responses = [
        client.post(
            f"/v1/voice-mirror/sessions/{session_id}/heartbeat",
            headers=_auth("other-token"),
        ),
        _speech(client, session_id, token="other-token"),
        client.delete(
            f"/v1/voice-mirror/sessions/{session_id}",
            headers=_auth("other-token"),
        ),
    ]

    assert [response.status_code for response in responses] == [404, 404, 404]
    assert engine.calls == []


def test_expiry_quota_and_busy_have_stable_safe_codes() -> None:
    client, clock, _, sessions = _client()
    expired_id = _enroll(client).json()["sessionId"]
    clock.advance(301)
    expired = client.post(
        f"/v1/voice-mirror/sessions/{expired_id}/heartbeat",
        headers=_auth(),
    )
    assert expired.status_code == 410
    assert expired.json()["detail"]["code"] == "SESSION_EXPIRED"

    quota_id = _enroll(client).json()["sessionId"]
    assert _speech(client, quota_id, text="1234567890").status_code == 200
    assert _speech(client, quota_id, text="1234567890").status_code == 200
    quota = _speech(client, quota_id, text="x")
    assert quota.status_code == 429
    assert quota.json()["detail"]["code"] == "RATE_LIMITED"

    busy_id = _enroll(client).json()["sessionId"]
    with sessions.acquire(busy_id, "owner", "held"):
        busy = _speech(client, busy_id)
    assert busy.status_code == 409
    assert busy.json()["detail"]["code"] == "SESSION_BUSY"


def test_engine_failure_never_leaks_private_values() -> None:
    client, _, engine, _ = _client()
    session_id = _enroll(client).json()["sessionId"]
    target = "private"
    internal = "runtime-private"
    engine.failure = RuntimeError(internal)

    response = _speech(client, session_id, text=target)

    assert response.status_code == 503
    rendered = response.text
    assert response.json()["detail"]["code"] == "SYNTHESIS_FAILED"
    assert target not in rendered
    assert internal not in rendered
    assert session_id not in rendered


def test_body_middleware_keeps_standard_limit_but_allows_bounded_wav() -> None:
    client, _, _, _ = _client()
    bounded = _WAV + bytes(65_536 - len(_WAV))
    assert _enroll(client, audio=bounded).status_code == 201

    standard = client.post(
        "/v1/speech",
        headers={**_auth(), "Content-Type": "application/json"},
        content=b'{"text":"' + (b"x" * 100_001) + b'"}',
    )
    assert standard.status_code == 413
