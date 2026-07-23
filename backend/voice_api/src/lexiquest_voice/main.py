"""Production ASGI assembly for the LexiQuest Voice API."""

from lexiquest_voice.app import create_app
from lexiquest_voice.auth import FirebaseTokenVerifier
from lexiquest_voice.config import Settings
from lexiquest_voice.engines.omnivoice_engine import OmniVoiceEngine

settings = Settings()
token_verifier = FirebaseTokenVerifier()
engine = OmniVoiceEngine(settings=settings)
engine.load()

app = create_app(
    engine=engine,
    token_verifier=token_verifier,
    settings=settings,
)

__all__ = ["app"]
