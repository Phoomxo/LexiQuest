from __future__ import annotations

import math
import threading
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from pathlib import Path
from typing import Any

import pytest

from lexiquest_voice.config import Settings
from lexiquest_voice.engines.voxcpm_mirror_engine import VoxCpmMirrorEngine

_REFERENCE = b"RIFF\x24\x00\x00\x00WAVE" + bytes(range(32))


class FakeModel:
    def __init__(
        self,
        *,
        generated: object | None = None,
        failure: Exception | None = None,
    ) -> None:
        self.generated = [0.1, -0.1] if generated is None else generated
        self.failure = failure
        self.calls: list[dict[str, object]] = []

    def generate(self, **kwargs: Any) -> object:
        path = Path(str(kwargs["reference_wav_path"]))
        self.calls.append(
            {
                **kwargs,
                "path_existed": path.is_file(),
                "reference": path.read_bytes(),
            }
        )
        if self.failure is not None:
            raise self.failure
        return self.generated


def _engine(
    model: FakeModel,
    *,
    settings: Settings | None = None,
) -> VoxCpmMirrorEngine:
    return VoxCpmMirrorEngine(
        settings=settings or Settings(),
        model_loader=lambda _: model,
        runtime_guard=lambda: None,
        wav_writer=lambda buffer, audio, sample_rate: buffer.write(
            b"RIFF-mirror"
        ),
    )


def test_synthesize_uses_reference_only_for_one_generation_call() -> None:
    model = FakeModel()
    settings = Settings(guidance_scale=1.5, generation_num_steps=10)
    result = _engine(model, settings=settings).synthesize(
        text="Target phrase.",
        reference_audio=_REFERENCE,
    )

    assert len(model.calls) == 1
    call = model.calls[0]
    assert call["text"] == "Target phrase."
    assert call["cfg_value"] == 1.5
    assert call["inference_timesteps"] == 10
    assert call["path_existed"] is True
    assert call["reference"] == _REFERENCE
    assert not Path(str(call["reference_wav_path"])).exists()
    assert result.data == b"RIFF-mirror"
    assert result.media_type == "audio/wav"
    assert result.sample_rate == 48_000
    assert result.engine == "voxcpm2-mirror"
    assert result.model_version == settings.voxcpm_model_version


@pytest.mark.parametrize(
    "reference",
    [b"", b"not-a-wave", b"RIFF\x00\x00\x00\x00NOPE"],
)
def test_invalid_reference_fails_before_model(reference: bytes) -> None:
    model = FakeModel()

    with pytest.raises(ValueError):
        _engine(model).synthesize(text="Target.", reference_audio=reference)

    assert model.calls == []


def test_oversized_reference_fails_before_model() -> None:
    model = FakeModel()
    settings = Settings(mirror_max_reference_bytes=65_536)
    reference = _REFERENCE + bytes(65_537 - len(_REFERENCE))

    with pytest.raises(ValueError):
        _engine(model, settings=settings).synthesize(
            text="Target.",
            reference_audio=reference,
        )

    assert model.calls == []


@pytest.mark.parametrize("generated", [[], [0.0, math.nan], [math.inf]])
def test_invalid_model_output_fails_closed(generated: object) -> None:
    engine = _engine(FakeModel(generated=generated))

    with pytest.raises(RuntimeError, match="Mirror synthesis failed"):
        engine.synthesize(text="Target.", reference_audio=_REFERENCE)


def test_model_failure_deletes_work_file_and_hides_private_values() -> None:
    target = "private-target-sentinel"
    internal = "private-runtime-sentinel"
    model = FakeModel(failure=RuntimeError(internal))

    with pytest.raises(RuntimeError) as raised:
        _engine(model).synthesize(text=target, reference_audio=_REFERENCE)

    work_path = Path(str(model.calls[0]["reference_wav_path"]))
    rendered = f"{raised.value!s}\n{raised.value!r}"
    assert not work_path.exists()
    assert target not in rendered
    assert internal not in rendered
    assert str(work_path) not in rendered


def test_model_loading_occurs_once_and_generation_is_serialized() -> None:
    first_entered = threading.Event()
    release_first = threading.Event()
    second_entered = threading.Event()
    state_lock = threading.Lock()

    class BlockingModel(FakeModel):
        def __init__(self) -> None:
            super().__init__()
            self.active = 0
            self.max_active = 0
            self.entries = 0

        def generate(self, **kwargs: Any) -> object:
            with state_lock:
                self.active += 1
                self.max_active = max(self.max_active, self.active)
                self.entries += 1
                entry = self.entries
            try:
                if entry == 1:
                    first_entered.set()
                    assert release_first.wait(timeout=2)
                else:
                    second_entered.set()
                return super().generate(**kwargs)
            finally:
                with state_lock:
                    self.active -= 1

    model = BlockingModel()
    loads = 0

    def loader(_: Settings) -> BlockingModel:
        nonlocal loads
        loads += 1
        return model

    engine = VoxCpmMirrorEngine(
        settings=Settings(),
        model_loader=loader,
        runtime_guard=lambda: None,
        wav_writer=lambda buffer, audio, sample_rate: buffer.write(b"RIFF"),
    )
    with ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(
            engine.synthesize,
            text="First.",
            reference_audio=_REFERENCE,
        )
        assert first_entered.wait(timeout=2)
        second = executor.submit(
            engine.synthesize,
            text="Second.",
            reference_audio=_REFERENCE,
        )
        assert not second_entered.wait(timeout=0.05)
        release_first.set()
        first.result(timeout=2)
        second.result(timeout=2)

    assert loads == 1
    assert model.max_active == 1


def test_public_api_rejects_identity_and_permanent_profile_fields() -> None:
    engine = _engine(FakeModel())
    for field in (
        "prompt_transcript",
        "participant_id",
        "uid",
        "session_id",
        "permanent_profile",
    ):
        with pytest.raises(TypeError):
            engine.synthesize(
                text="Target.",
                reference_audio=_REFERENCE,
                **{field: "forbidden"},
            )
