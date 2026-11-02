"""Production ASGI assembly for the LexiQuest Voice API."""

import logging

from lexiquest_voice.app import create_app
from lexiquest_voice.auth import FirebaseTokenVerifier
from lexiquest_voice.config import Settings
from lexiquest_voice.engines.omnivoice_engine import OmniVoiceEngine
from lexiquest_voice.runtime_compat import RuntimeCompatibilityError

logger = logging.getLogger(__name__)

settings = Settings()
token_verifier = FirebaseTokenVerifier()
engine = OmniVoiceEngine(settings=settings)
try:
    engine.load()
except RuntimeCompatibilityError:
    logger.warning("Speech engine startup blocked by runtime policy.")

app = create_app(
    engine=engine,
    token_verifier=token_verifier,
    settings=settings,
)

__all__ = ["app"]
