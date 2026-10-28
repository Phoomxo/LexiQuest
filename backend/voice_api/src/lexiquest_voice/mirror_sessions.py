from __future__ import annotations

import secrets
from dataclasses import dataclass
from threading import RLock
from types import TracebackType
from typing import Protocol


class MirrorSessionNotFound(Exception):
    """The session is absent or belongs to another authenticated user."""


class MirrorSessionExpired(Exception):
    """The renewable lease or absolute lifetime has ended."""


class MirrorSessionQuotaExceeded(Exception):
    """The bounded request or character allowance has been consumed."""


class MirrorSessionBusy(Exception):
    """Another synthesis currently owns this session."""


class MirrorSessionClock(Protocol):
    def now_utc(self) -> float: ...


@dataclass(frozen=True, slots=True)
class MirrorSessionView:
    session_id: str
    lease_expires_at: float
    absolute_expires_at: float


@dataclass(slots=True)
class _MirrorSession:
    uid: str
    reference_audio: bytearray
    created_at: float
    lease_expires_at: float
    absolute_expires_at: float
    requests_used: int = 0
    characters_used: int = 0
    active: bool = False


class _MirrorLease:
    __slots__ = (
        "_store",
        "_session_id",
        "_uid",
        "_released",
        "reference_audio",
    )

    def __init__(
        self,
        *,
        store: MirrorSessionStore,
        session_id: str,
        uid: str,
        reference_audio: bytes,
    ) -> None:
        self._store = store
        self._session_id = session_id
        self._uid = uid
        self._released = False
        self.reference_audio = reference_audio

    def __enter__(self) -> _MirrorLease:
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self.release()

    def release(self) -> None:
        if self._released:
            return
        self._released = True
        self._store._release(self._session_id, self._uid)


class MirrorSessionStore:
    """Thread-safe volatile owner for participant voice-reference bytes."""

    def __init__(
        self,
        *,
        clock: MirrorSessionClock,
        lease_duration: float,
        absolute_lifetime: float,
        max_requests: int,
        max_characters: int,
    ) -> None:
        if (
            lease_duration <= 0
            or absolute_lifetime <= 0
            or absolute_lifetime < lease_duration
            or max_requests <= 0
            or max_characters <= 0
        ):
            raise ValueError("Mirror session limits must be positive and bounded.")
        self._clock = clock
        self._lease_duration = float(lease_duration)
        self._absolute_lifetime = float(absolute_lifetime)
        self._max_requests = max_requests
        self._max_characters = max_characters
        self._sessions: dict[str, _MirrorSession] = {}
        self._lock = RLock()

    def create(self, uid: str, reference_audio: bytes) -> MirrorSessionView:
        if not isinstance(uid, str) or not uid:
            raise ValueError("Authenticated owner is required.")
        if not isinstance(reference_audio, bytes) or not reference_audio:
            raise ValueError("Reference audio is required.")
        now = float(self._clock.now_utc())
        with self._lock:
            session_id = self._new_session_id()
            session = _MirrorSession(
                uid=uid,
                reference_audio=bytearray(reference_audio),
                created_at=now,
                lease_expires_at=now + self._lease_duration,
                absolute_expires_at=now + self._absolute_lifetime,
            )
            self._sessions[session_id] = session
            return self._view(session_id, session)

    def heartbeat(self, session_id: str, uid: str) -> MirrorSessionView:
        with self._lock:
            session = self._owned(session_id, uid)
            now = float(self._clock.now_utc())
            self._ensure_active(session, now)
            session.lease_expires_at = min(
                now + self._lease_duration,
                session.absolute_expires_at,
            )
            return self._view(session_id, session)

    def acquire(
        self,
        session_id: str,
        uid: str,
        text: str,
    ) -> _MirrorLease:
        if not isinstance(text, str) or not text:
            raise MirrorSessionQuotaExceeded()
        with self._lock:
            session = self._owned(session_id, uid)
            now = float(self._clock.now_utc())
            self._ensure_active(session, now)
            if session.active:
                raise MirrorSessionBusy()
            if (
                session.requests_used + 1 > self._max_requests
                or session.characters_used + len(text) > self._max_characters
            ):
                raise MirrorSessionQuotaExceeded()
            session.requests_used += 1
            session.characters_used += len(text)
            session.active = True
            return _MirrorLease(
                store=self,
                session_id=session_id,
                uid=uid,
                reference_audio=bytes(session.reference_audio),
            )

    def delete(self, session_id: str, uid: str) -> bool:
        with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                return True
            if session.uid != uid:
                raise MirrorSessionNotFound()
            self._destroy(session_id, session)
            return True

    def purge_expired(self) -> int:
        with self._lock:
            now = float(self._clock.now_utc())
            expired = [
                (session_id, session)
                for session_id, session in self._sessions.items()
                if self._is_expired(session, now)
            ]
            for session_id, session in expired:
                self._destroy(session_id, session)
            return len(expired)

    def _debug_reference_buffer(self, session_id: str) -> bytearray:
        with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                raise MirrorSessionNotFound()
            return session.reference_audio

    def _new_session_id(self) -> str:
        while True:
            candidate = secrets.token_urlsafe(32)
            if candidate not in self._sessions:
                return candidate

    def _owned(self, session_id: str, uid: str) -> _MirrorSession:
        session = self._sessions.get(session_id)
        if session is None or session.uid != uid:
            raise MirrorSessionNotFound()
        return session

    def _ensure_active(self, session: _MirrorSession, now: float) -> None:
        if self._is_expired(session, now):
            raise MirrorSessionExpired()

    def _is_expired(self, session: _MirrorSession, now: float) -> bool:
        return (
            now >= session.lease_expires_at
            or now >= session.absolute_expires_at
        )

    def _release(self, session_id: str, uid: str) -> None:
        with self._lock:
            session = self._sessions.get(session_id)
            if session is not None and session.uid == uid:
                session.active = False

    def _destroy(self, session_id: str, session: _MirrorSession) -> None:
        for index in range(len(session.reference_audio)):
            session.reference_audio[index] = 0
        self._sessions.pop(session_id, None)

    def _view(
        self,
        session_id: str,
        session: _MirrorSession,
    ) -> MirrorSessionView:
        return MirrorSessionView(
            session_id=session_id,
            lease_expires_at=session.lease_expires_at,
            absolute_expires_at=session.absolute_expires_at,
        )


__all__ = [
    "MirrorSessionBusy",
    "MirrorSessionExpired",
    "MirrorSessionNotFound",
    "MirrorSessionQuotaExceeded",
    "MirrorSessionStore",
    "MirrorSessionView",
]
