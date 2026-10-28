from __future__ import annotations

import math
import sys
from collections.abc import Callable, Iterable
from io import BytesIO
from numbers import Real
from threading import Lock
from typing import Any

from lexiquest_voice.config import Settings
from lexiquest_voice.models import AudioResult, SpeechRequest

ModelLoader = Callable[[Settings], Any]
RuntimeGuard = Callable[[], None]
WavWriter = Callable[[BytesIO, Any, int], None]

VOXCPM_MODEL_ID = "openbmb/VoxCPM2"
VOXCPM_SAMPLE_RATE = 48_000


class VoxCpmEngine:
    """Lazy, serialized adapter for standard VoxCPM2 target speech."""

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

    @property
    def is_ready(self) -> bool:
        return self._model is not None

    def load(self) -> Any:
        return self._get_model()

    def _get_model(self) -> Any:
        if self._model is None:
            with self._load_lock:
                if self._model is None:
                    self._runtime_guard()
                    self._model = self._model_loader(self._settings)
        return self._model

    def synthesize(self, request: SpeechRequest) -> AudioResult:
        model = self._get_model()
        with self._generation_lock:
            generated = model.generate(
                text=request.text,
                cfg_value=self._settings.guidance_scale,
                inference_timesteps=self._settings.generation_num_steps,
                seed=42,
            )
            if _is_empty(generated) or _contains_non_finite(generated):
                raise RuntimeError("VoxCPM2 returned invalid audio.")

            buffer = BytesIO()
            self._wav_writer(buffer, generated, VOXCPM_SAMPLE_RATE)
            audio_bytes = buffer.getvalue()
            if not audio_bytes:
                raise RuntimeError("VoxCPM2 WAV encoding returned no audio.")

        return AudioResult(
            data=audio_bytes,
            media_type="audio/wav",
            sample_rate=VOXCPM_SAMPLE_RATE,
            engine="voxcpm2",
            model_version=self._settings.voxcpm_model_version,
        )


def _is_empty(value: Any) -> bool:
    if value is None:
        return True
    size = getattr(value, "size", None)
    if isinstance(size, int):
        return size == 0
    return isinstance(value, (list, tuple)) and not value


def _contains_non_finite(value: Any) -> bool:
    if isinstance(value, Real):
        return not math.isfinite(float(value))
    if isinstance(value, (str, bytes, bytearray)):
        return False
    flattened = getattr(value, "ravel", None)
    if callable(flattened):
        value = flattened().tolist()
    if isinstance(value, Iterable):
        return any(_contains_non_finite(item) for item in value)
    return False


def _require_supported_python() -> None:
    if not ((3, 10) <= sys.version_info[:2] < (3, 13)):
        raise RuntimeError("VoxCPM2 requires Python 3.10 through 3.12.")


def _load_model(settings: Settings) -> Any:
    from voxcpm import VoxCPM

    return VoxCPM.from_pretrained(
        settings.voxcpm_model_id,
        load_denoiser=False,
    )


def _write_wav(buffer: BytesIO, audio: Any, sample_rate: int) -> None:
    import soundfile as sf

    sf.write(buffer, audio, sample_rate, format="WAV")


__all__ = ["VOXCPM_SAMPLE_RATE", "VoxCpmEngine"]
