from __future__ import annotations

from lexiquest_voice.config import Settings
from lexiquest_voice.engines.factory import create_speech_engine
from lexiquest_voice.engines.omnivoice_engine import OmniVoiceEngine
from lexiquest_voice.engines.voxcpm_engine import VoxCpmEngine


def test_factory_selects_voxcpm2_without_loading_the_model() -> None:
    engine = create_speech_engine(Settings(engine_backend="voxcpm2"))

    assert isinstance(engine, VoxCpmEngine)
    assert engine.is_ready is False


def test_factory_preserves_omnivoice_as_an_explicit_rollback() -> None:
    engine = create_speech_engine(Settings(engine_backend="omnivoice"))

    assert isinstance(engine, OmniVoiceEngine)
    assert engine.is_ready is False
