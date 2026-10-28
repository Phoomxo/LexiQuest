from __future__ import annotations

from lexiquest_voice.config import Settings
from lexiquest_voice.engines.base import SpeechEngine
from lexiquest_voice.engines.omnivoice_engine import OmniVoiceEngine
from lexiquest_voice.engines.voxcpm_engine import VoxCpmEngine


def create_speech_engine(settings: Settings) -> SpeechEngine:
    """Create exactly one configured engine without loading model weights."""

    if settings.engine_backend == "voxcpm2":
        return VoxCpmEngine(settings=settings)
    return OmniVoiceEngine(settings=settings)


__all__ = ["create_speech_engine"]
