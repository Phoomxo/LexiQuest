from __future__ import annotations

from typing import Protocol, runtime_checkable

from lexiquest_voice.models import AudioResult, SpeechRequest


@runtime_checkable
class SpeechEngine(Protocol):
    """Interface implemented by speech synthesis engines."""

    @property
    def is_ready(self) -> bool:
        """Whether the engine can accept synthesis requests."""

        ...

    def load(self) -> object:
        """Load the engine and return its underlying model."""

        ...

    def synthesize(self, request: SpeechRequest) -> AudioResult:
        """Generate audio for a validated speech request."""

        ...
