from __future__ import annotations

from typing import Protocol, runtime_checkable

from lexiquest_voice.models import AudioResult, SpeechRequest


@runtime_checkable
class SpeechEngine(Protocol):
    """Interface implemented by speech synthesis engines."""

    def synthesize(self, request: SpeechRequest) -> AudioResult:
        """Generate audio for a validated speech request."""

        ...
