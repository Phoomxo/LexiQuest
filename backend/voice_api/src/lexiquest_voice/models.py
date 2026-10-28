from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

# Absolute schema ceiling for request text. This is a deliberate backstop that
# operates independently of the runtime-configured limit (Settings.max_text_length);
# it exists so an absurdly large payload is rejected by schema validation before
# the configured limit is even consulted. It is shared with Settings so the two
# cannot drift apart.
MAX_TEXT_LENGTH_CEILING = 2000


class SpeechRequest(BaseModel):
    """Request payload for speech synthesis."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    text: str = Field(..., min_length=1, max_length=MAX_TEXT_LENGTH_CEILING)
    language: Literal["en", "th"]
    voice: Literal["teacher_female"]
    speed: float = Field(default=1.0, ge=0.5, le=1.5)
    format: Literal["wav"] = "wav"

    @field_validator("text")
    @classmethod
    def _normalize_whitespace(cls, value: str) -> str:
        """Collapse all whitespace runs in text to a single space."""
        return re.sub(r"\s+", " ", value)


@dataclass(frozen=True, slots=True)
class AudioResult:
    """Immutable result of a speech synthesis operation."""

    data: bytes
    media_type: str
    sample_rate: int
    engine: str
    model_version: str
