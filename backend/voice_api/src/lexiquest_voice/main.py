"""Production ASGI assembly for the LexiQuest Voice API."""

import time

from lexiquest_voice.app import create_app
from lexiquest_voice.auth import FirebaseTokenVerifier
from lexiquest_voice.config import Settings
from lexiquest_voice.engines.factory import create_speech_engine
from lexiquest_voice.engines.voxcpm_mirror_engine import VoxCpmMirrorEngine
from lexiquest_voice.mirror_sessions import MirrorSessionStore


class _SystemClock:
    def now_utc(self) -> float:
        return time.time()


settings = Settings()
token_verifier = FirebaseTokenVerifier()
engine = create_speech_engine(settings)
if settings.provider_enabled:
    engine.load()

mirror_engine = None
mirror_sessions = None
if settings.mirror_enabled:
    mirror_engine = VoxCpmMirrorEngine(
        settings=settings,
        model_loader=lambda _: engine.load(),
    )
    mirror_sessions = MirrorSessionStore(
        clock=_SystemClock(),
        lease_duration=settings.mirror_lease_seconds,
        absolute_lifetime=settings.mirror_absolute_lifetime_seconds,
        max_requests=settings.mirror_max_requests,
        max_characters=settings.mirror_max_characters,
    )

app = create_app(
    engine=engine,
    token_verifier=token_verifier,
    settings=settings,
    mirror_engine=mirror_engine,
    mirror_sessions=mirror_sessions,
)

__all__ = ["app"]
