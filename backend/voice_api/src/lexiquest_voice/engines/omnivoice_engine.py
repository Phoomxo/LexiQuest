from __future__ import annotations

from collections.abc import Callable
from io import BytesIO
from threading import Lock
from typing import Any

from lexiquest_voice.config import Settings
from lexiquest_voice.models import AudioResult, SpeechRequest

ModelLoader = Callable[[Settings], Any]
WavWriter = Callable[[BytesIO, Any, int], None]


class OmniVoiceEngine:
    """Lazy, serialized adapter for the optional OmniVoice runtime."""

    def __init__(
        self,
        *,
        settings: Settings,
        model_loader: ModelLoader | None = None,
        wav_writer: WavWriter | None = None,
    ) -> None:
        self._settings = settings
        self._model_loader = model_loader or _load_model
        self._wav_writer = wav_writer or _write_wav
        self._model: Any | None = None
        self._load_lock = Lock()
        self._generation_lock = Lock()

    @property
    def is_ready(self) -> bool:
        """Whether the underlying model has loaded successfully."""

        return self._model is not None

    def load(self) -> Any:
        """Load the model once and return it."""

        return self._get_model()

    def _get_model(self) -> Any:
        if self._model is None:
            with self._load_lock:
                if self._model is None:
                    self._model = self._model_loader(self._settings)
        return self._model

    def synthesize(self, request: SpeechRequest) -> AudioResult:
        model = self._get_model()
        with self._generation_lock:
            generated = model.generate(
                text=request.text,
                language=request.language,
                instruct=self._settings.voice_instruction,
                speed=request.speed,
                num_step=self._settings.generation_num_steps,
                guidance_scale=self._settings.guidance_scale,
                position_temperature=self._settings.position_temperature,
                class_temperature=self._settings.class_temperature,
            )
            if not generated:
                raise RuntimeError("OmniVoice returned no audio.")

            buffer = BytesIO()
            self._wav_writer(
                buffer,
                generated[0],
                self._settings.sample_rate,
            )

        return AudioResult(
            data=buffer.getvalue(),
            media_type="audio/wav",
            sample_rate=self._settings.sample_rate,
            engine="omnivoice",
            model_version=self._settings.model_version,
        )


def _load_model(settings: Settings) -> Any:
    import torch
    from huggingface_hub import snapshot_download
    from omnivoice import OmniVoice

    snapshot_path = snapshot_download(
        repo_id=settings.model_id,
        revision=settings.model_revision,
    )
    return OmniVoice.from_pretrained(
        snapshot_path,
        device_map=settings.device,
        dtype=torch.float16,
        load_asr=settings.load_asr,
    )


def _write_wav(buffer: BytesIO, audio: Any, sample_rate: int) -> None:
    import soundfile as sf

    sf.write(buffer, audio, sample_rate, format="WAV")
