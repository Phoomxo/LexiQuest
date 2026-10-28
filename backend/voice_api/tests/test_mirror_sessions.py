import pytest

from lexiquest_voice.mirror_sessions import (
    MirrorSessionBusy,
    MirrorSessionExpired,
    MirrorSessionNotFound,
    MirrorSessionQuotaExceeded,
    MirrorSessionStore,
)


class FakeClock:
    def __init__(self) -> None:
        self.t = 0.0

    def now_utc(self) -> float:
        return self.t

    def advance(self, seconds: float) -> None:
        self.t += seconds


@pytest.fixture
def store() -> tuple[MirrorSessionStore, FakeClock]:
    clock = FakeClock()
    session_store = MirrorSessionStore(
        clock=clock,
        lease_duration=300,
        absolute_lifetime=1200,
        max_requests=100,
        max_characters=1000,
    )
    return session_store, clock


def test_create_generates_unique_opaque_ids(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, clock = store
    first = session_store.create("user1", b"audio-data")
    second = session_store.create("user1", b"audio-data")
    third = session_store.create("user2", b"audio-data")

    assert isinstance(first.session_id, str) and len(first.session_id) >= 32
    assert len({first.session_id, second.session_id, third.session_id}) == 3
    assert first.lease_expires_at == clock.t + 300
    assert first.absolute_expires_at == clock.t + 1200


def test_heartbeat_renews_lease_but_cannot_extend_absolute_expiry(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, clock = store
    session = session_store.create("user1", b"audio")

    clock.advance(200)
    assert (
        session_store.heartbeat(session.session_id, "user1").lease_expires_at
        == 500
    )
    clock.advance(200)
    assert (
        session_store.heartbeat(session.session_id, "user1").lease_expires_at
        == 700
    )
    clock.advance(600)
    with pytest.raises(MirrorSessionExpired):
        session_store.heartbeat(session.session_id, "user1")

    replacement = session_store.create("user1", b"audio")
    clock.advance(200)
    session_store.heartbeat(replacement.session_id, "user1")
    clock.advance(200)
    session_store.heartbeat(replacement.session_id, "user1")
    clock.advance(200)
    session_store.heartbeat(replacement.session_id, "user1")
    clock.advance(200)
    session_store.heartbeat(replacement.session_id, "user1")
    clock.advance(200)
    final = session_store.heartbeat(replacement.session_id, "user1")
    assert final.lease_expires_at == replacement.absolute_expires_at


def test_owner_isolation(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, _ = store
    session = session_store.create("user1", b"audio")

    with pytest.raises(MirrorSessionNotFound):
        session_store.heartbeat(session.session_id, "user2")
    with pytest.raises(MirrorSessionNotFound):
        session_store.acquire(session.session_id, "user2", "text")
    with pytest.raises(MirrorSessionNotFound):
        session_store.delete(session.session_id, "user2")
    assert session_store._debug_reference_buffer(session.session_id) is not None


def test_acquire_returns_immutable_reference_bytes(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, _ = store
    session = session_store.create("user1", b"abc")

    with session_store.acquire(session.session_id, "user1", "hello") as lease:
        reference = lease.reference_audio
        assert reference == b"abc"
        with pytest.raises(TypeError):
            reference[0] = 1  # type: ignore[index]


def test_acquire_releases_after_exception(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, _ = store
    session = session_store.create("user1", b"abc")

    with pytest.raises(RuntimeError):
        with session_store.acquire(session.session_id, "user1", "hello"):
            raise RuntimeError("fixture failure")
    with session_store.acquire(session.session_id, "user1", "world") as lease:
        assert lease.reference_audio == b"abc"


def test_one_active_synthesis_per_session(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, _ = store
    session = session_store.create("user1", b"abc")

    with session_store.acquire(session.session_id, "user1", "hello"):
        with pytest.raises(MirrorSessionBusy):
            session_store.acquire(session.session_id, "user1", "world")


def test_expired_sessions_are_unusable_and_purged(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, clock = store
    session = session_store.create("user1", b"abc")
    clock.advance(301)

    with pytest.raises(MirrorSessionExpired):
        session_store.acquire(session.session_id, "user1", "hi")
    assert session_store.purge_expired() == 1
    with pytest.raises(MirrorSessionNotFound):
        session_store.heartbeat(session.session_id, "user1")
    assert session_store.purge_expired() == 0


def test_delete_is_idempotent_for_owner_and_overwrites_buffer(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, _ = store
    session = session_store.create("user1", b"abc")
    buffer = session_store._debug_reference_buffer(session.session_id)

    assert session_store.delete(session.session_id, "user1") is True
    assert session_store.delete(session.session_id, "user1") is True
    assert not any(buffer)


def test_purge_overwrites_buffer(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, clock = store
    session = session_store.create("user1", b"abcdef")
    buffer = session_store._debug_reference_buffer(session.session_id)
    assert any(buffer)

    clock.advance(1201)
    assert session_store.purge_expired() == 1
    assert not any(buffer)


def test_request_quota_is_bounded(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, _ = store
    session = session_store.create("user1", b"abc")
    for _ in range(100):
        with session_store.acquire(session.session_id, "user1", "hi"):
            pass

    with pytest.raises(MirrorSessionQuotaExceeded):
        session_store.acquire(session.session_id, "user1", "hi")


def test_character_quota_is_bounded(
    store: tuple[MirrorSessionStore, FakeClock],
) -> None:
    session_store, _ = store
    session = session_store.create("user1", b"abc")
    with session_store.acquire(session.session_id, "user1", "x" * 800):
        pass

    with pytest.raises(MirrorSessionQuotaExceeded):
        session_store.acquire(session.session_id, "user1", "y" * 300)
