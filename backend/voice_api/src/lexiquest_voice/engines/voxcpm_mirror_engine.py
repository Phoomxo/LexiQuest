from __future__ import annotations

import os
import tempfile
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from io import BytesIO
from threading import Lock
from typing import Any

from lexiquest_voice.config import Settings
from lexiquest_voice.engines.voxcpm_engine import (
    VOXCPM_SAMPLE_RATE,
    _contains_non_finite,
    _is_empty,
    _require_supported_python,
    _write_wav,
)
from lexiquest_voice.models import AudioResult

ModelLoader = Callable[[Settings], Any]
RuntimeGuard = Callable[[], None]
WavWriter = Callable[[BytesIO, Any, int], None]

_INVALID_INPUT = "Invalid mirror synthesis input."
_SYNTHESIS_FAILED = "Mirror synthesis failed."


class VoxCpmMirrorEngine:
    """Serialized VoxCPM2 cloning with a one-call private reference file."""

    def __init__(
        self,
        *,
        settings: Settings,
        model_loader: ModelLoader | None = None,
        wav_writer: WavWriter | None = None,
        runtime_guard: RuntimeGuard | None = None,
    ) -> None:
        self._settings = settings
        self._model_loader = model_loader or _load_model
        self._wav_writer = wav_writer or _write_wav
        self._runtime_guard = runtime_guard or _require_supported_python
        self._model: Any | None = None
        self._load_lock = Lock()
        self._generation_lock = Lock()

    def synthesize(self, *, text: str, reference_audio: bytes) -> AudioResult:
        self._validate(text, reference_audio)
        try:
            model = self._get_model()
            with self._generation_lock:
                with _private_reference_file(reference_audio) as reference_path:
                    generated = model.generate(
                        text=text,
                        reference_wav_path=reference_path,
                        cfg_value=self._settings.guidance_scale,
                        inference_timesteps=self._settings.generation_num_steps,
                        seed=42,
                    )
                    if _is_empty(generated) or _contains_non_finite(generated):
                        raise RuntimeError(_SYNTHESIS_FAILED)
                    buffer = BytesIO()
                    self._wav_writer(buffer, generated, VOXCPM_SAMPLE_RATE)
                    audio_bytes = buffer.getvalue()
                    if not audio_bytes:
                        raise RuntimeError(_SYNTHESIS_FAILED)
            return AudioResult(
                data=audio_bytes,
                media_type="audio/wav",
                sample_rate=VOXCPM_SAMPLE_RATE,
                engine="voxcpm2-mirror",
                model_version=self._settings.voxcpm_model_version,
            )
        except Exception:
            raise RuntimeError(_SYNTHESIS_FAILED) from None

    def _get_model(self) -> Any:
        if self._model is None:
            with self._load_lock:
                if self._model is None:
                    self._runtime_guard()
                    self._model = self._model_loader(self._settings)
        return self._model

    def _validate(self, text: str, reference_audio: bytes) -> None:
        if (
            not isinstance(text, str)
            or not text
            or len(text) > self._settings.mirror_max_text_length
            or not isinstance(reference_audio, bytes)
            or len(reference_audio) < 12
            or len(reference_audio) > self._settings.mirror_max_reference_bytes
            or reference_audio[:4] != b"RIFF"
            or reference_audio[8:12] != b"WAVE"
        ):
            raise ValueError(_INVALID_INPUT)


@contextmanager
def _private_reference_file(reference_audio: bytes) -> Iterator[str]:
    descriptor, path = tempfile.mkstemp(
        prefix="lexiquest-mirror-",
        suffix=".wav",
    )
    try:
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
        with os.fdopen(descriptor, "wb") as output:
            descriptor = -1
            output.write(reference_audio)
            output.flush()
        yield path
    finally:
        if descriptor >= 0:
            try:
                os.close(descriptor)
            except OSError:
                pass
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def _load_model(settings: Settings) -> Any:
    from voxcpm import VoxCPM

    return VoxCPM.from_pretrained(
        settings.voxcpm_model_id,
        load_denoiser=False,
    )


__all__ = ["VoxCpmMirrorEngine"]
