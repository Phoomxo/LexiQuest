from __future__ import annotations

import math
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from typing import Any

import pytest

from lexiquest_voice.config import Settings
from lexiquest_voice.engines.voxcpm_engine import VoxCpmEngine
from lexiquest_voice.models import SpeechRequest

#: Engine-name provenance emitted on every VoxCPM ``AudioResult``.
VOXCPM_ENGINE_NAME = "voxcpm2"

#: Fixed 48 kHz WAV output rate mandated by the P8-B VoxCPM contract.
VOXCPM_SAMPLE_RATE = 48_000

#: Request fields VoxCPM standard speech must never forward to the model.
FORBIDDEN_GENERATE_KEYS = frozenset(
    {
        "reference_wav_path",
        "prompt_wav_path",
        "prompt_text",
        "language",
        "instruct",
        "voice",
        "participant_id",
        "participant_audio",
        "speaker_embedding",
    }
)


class FakeModel:
    """Stand-in for the optional ``voxcpm`` model object."""

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


def test_is_ready_false_before_load_and_true_after() -> None:
    engine = VoxCpmEngine(
        settings=Settings(),
        model_loader=lambda settings: FakeModel(),
        runtime_guard=lambda: None,
        wav_writer=lambda buffer, audio, sample_rate: None,
    )

    assert engine.is_ready is False

    engine.load()

    assert engine.is_ready is True


def test_injected_model_loader_invoked_once() -> None:
    fake_model = FakeModel()
    load_count = 0

    def loader(settings: Settings) -> FakeModel:
        nonlocal load_count
        load_count += 1
        return fake_model

    engine = VoxCpmEngine(
        settings=Settings(),
        model_loader=loader,
        runtime_guard=lambda: None,
        wav_writer=lambda buffer, audio, sample_rate: buffer.write(b"RIFF"),
    )

    engine.load()
    engine.load()
    engine.synthesize(_request())

    assert load_count == 1


def test_injected_wav_writer_receives_48khz_and_produces_deterministic_bytes() -> None:
    captured: dict[str, Any] = {}

    def writer(buffer: BytesIO, audio: object, sample_rate: int) -> None:
        captured["sample_rate"] = sample_rate
        buffer.write(b"RIFF-voxcpm-deterministic")

    engine = VoxCpmEngine(
        settings=Settings(),
        model_loader=lambda settings: FakeModel(),
        runtime_guard=lambda: None,
        wav_writer=writer,
    )

    result = engine.synthesize(_request())

    assert captured["sample_rate"] == VOXCPM_SAMPLE_RATE
    assert result.sample_rate == VOXCPM_SAMPLE_RATE
    assert result.data == b"RIFF-voxcpm-deterministic"


def test_synthesize_forwards_text_plus_bounded_config_and_no_reference_or_participant_data() -> None:
    fake_model = FakeModel()
    settings = Settings()

    engine = VoxCpmEngine(
        settings=settings,
        model_loader=lambda s: fake_model,
        runtime_guard=lambda: None,
        wav_writer=lambda buffer, audio, sample_rate: buffer.write(b"RIFF"),
    )

    request = _request()
    result = engine.synthesize(request)

    assert fake_model.calls, "model.generate must be invoked"
    call = fake_model.calls[0]

    # Standard speech forwards only the request text.
    assert call["text"] == "Cat"

    # No reference, prompt, participant, language, or cloning parameters.
    forwarded_keys = set(call.keys())
    assert not (forwarded_keys & FORBIDDEN_GENERATE_KEYS)

    # Bounded VoxCPM generation configuration: every non-text value must be a
    # finite, numeric knob with no unbounded strings or paths.
    for key, value in call.items():
        if key == "text":
            continue
        assert isinstance(value, (int, float)), (
            f"generation knob {key!r} must be numeric, got {type(value).__name__}"
        )
        assert math.isfinite(float(value)), (
            f"generation knob {key!r} must be finite, got {value!r}"
        )
        assert value >= 0, f"generation knob {key!r} must be non-negative, got {value!r}"

    # Provenance matches the contract.
    assert result.engine == VOXCPM_ENGINE_NAME
    assert result.model_version == settings.voxcpm_model_version


def test_audio_result_engine_and_model_version_match_settings() -> None:
    fake_model = FakeModel()
    settings = Settings()

    engine = VoxCpmEngine(
        settings=settings,
        model_loader=lambda s: fake_model,
        runtime_guard=lambda: None,
        wav_writer=lambda buffer, audio, sample_rate: buffer.write(b"x"),
    )

    result = engine.synthesize(_request())

    assert result.engine == VOXCPM_ENGINE_NAME
    assert result.model_version == settings.voxcpm_model_version
    assert result.media_type == "audio/wav"


def test_empty_generation_fails_closed() -> None:
    engine = VoxCpmEngine(
        settings=Settings(),
        model_loader=lambda settings: FakeModel(generated=[]),
        runtime_guard=lambda: None,
        wav_writer=lambda buffer, audio, sample_rate: None,
    )

    with pytest.raises(RuntimeError):
        engine.synthesize(_request())


@pytest.mark.parametrize(
    "non_finite",
    [math.nan, math.inf, -math.inf],
)
def test_non_finite_numeric_audio_fails_closed(non_finite: float) -> None:
    class NonFiniteModel(FakeModel):
        def generate(self, **kwargs: Any) -> list[object]:
            super().generate(**kwargs)
            return [[0.0, non_finite, 1.0]]

    engine = VoxCpmEngine(
        settings=Settings(),
        model_loader=lambda settings: NonFiniteModel(),
        runtime_guard=lambda: None,
        wav_writer=lambda buffer, audio, sample_rate: buffer.write(b"should-not-reach"),
    )

    with pytest.raises(RuntimeError):
        engine.synthesize(_request())


def test_concurrent_synthesis_is_serialized() -> None:
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

    engine = VoxCpmEngine(
        settings=Settings(),
        model_loader=lambda settings: model,
        runtime_guard=lambda: None,
        wav_writer=writer,
    )

    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = [executor.submit(engine.synthesize, _request()) for _ in range(4)]
        results = [future.result() for future in futures]

    assert model.max_active == 1
    assert [result.data for result in results] == [b"RIFF"] * 4
