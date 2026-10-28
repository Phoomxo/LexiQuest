from __future__ import annotations

import threading
import time
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from typing import Any

import pytest

from lexiquest_voice.config import Settings
from lexiquest_voice.engines.omnivoice_engine import OmniVoiceEngine
from lexiquest_voice.models import SpeechRequest


class FakeModel:
    def __init__(self, generated: list[object] | None = None) -> None:
        self.calls: list[dict[str, object]] = []
        self._generated = generated if generated is not None else [object()]

    def generate(self, **kwargs: Any) -> list[object]:
        self.calls.append(kwargs)
        return self._generated


def _request() -> SpeechRequest:
    return SpeechRequest(
        text="Cat",
        language="en",
        voice="teacher_female",
        speed=0.9,
    )


def test_engine_loads_once_and_forwards_locked_configuration() -> None:
    fake_model = FakeModel()
    load_count = 0

    def loader(settings: Settings) -> FakeModel:
        nonlocal load_count
        load_count += 1
        assert settings.load_asr is False
        assert settings.model_revision == "c5fdb5ccb189668d56333f77ba2629f4cd7535f4"
        return fake_model

    def writer(buffer: BytesIO, audio: object, sample_rate: int) -> None:
        assert sample_rate == 24_000
        buffer.write(b"RIFF-test")

    settings = Settings()
    engine = OmniVoiceEngine(
        settings=settings,
        model_loader=loader,
        wav_writer=writer,
    )

    first = engine.synthesize(_request())
    second = engine.synthesize(_request())

    assert load_count == 1
    assert first.data == b"RIFF-test"
    assert second.engine == "omnivoice"
    assert second.model_version == "0.2.1"
    assert fake_model.calls[0] == {
        "text": "Cat",
        "language": "en",
        "instruct": settings.voice_instruction,
        "speed": 0.9,
        "num_step": 32,
        "guidance_scale": 2.0,
        "position_temperature": 0.0,
        "class_temperature": 0.0,
    }


def test_engine_rejects_empty_generation() -> None:
    engine = OmniVoiceEngine(
        settings=Settings(),
        model_loader=lambda settings: FakeModel(generated=[]),
        wav_writer=lambda buffer, audio, sample_rate: None,
    )

    with pytest.raises(RuntimeError, match="no audio"):
        engine.synthesize(_request())


def test_engine_load_exposes_readiness_and_remains_idempotent() -> None:
    fake_model = FakeModel()
    load_count = 0

    def loader(settings: Settings) -> FakeModel:
        nonlocal load_count
        load_count += 1
        return fake_model

    engine = OmniVoiceEngine(
        settings=Settings(),
        model_loader=loader,
        wav_writer=lambda buffer, audio, sample_rate: None,
    )

    assert engine.is_ready is False
    assert engine.load() is fake_model
    assert engine.is_ready is True
    assert engine.load() is fake_model
    assert load_count == 1


def test_engine_serializes_concurrent_generation() -> None:
    state_lock = threading.Lock()

    class ConcurrentModel(FakeModel):
        def __init__(self) -> None:
            super().__init__()
            self.active = 0
            self.max_active = 0

        def generate(self, **kwargs: Any) -> list[object]:
            with state_lock:
                self.active += 1
                self.max_active = max(self.max_active, self.active)
            try:
                time.sleep(0.05)
                return [object()]
            finally:
                with state_lock:
                    self.active -= 1

    model = ConcurrentModel()

    def writer(buffer: BytesIO, audio: object, sample_rate: int) -> None:
        buffer.write(b"RIFF")

    engine = OmniVoiceEngine(
        settings=Settings(),
        model_loader=lambda settings: model,
        wav_writer=writer,
    )

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(engine.synthesize, _request()) for _ in range(2)]
        results = [future.result() for future in futures]

    assert model.max_active == 1
    assert [result.data for result in results] == [b"RIFF", b"RIFF"]
