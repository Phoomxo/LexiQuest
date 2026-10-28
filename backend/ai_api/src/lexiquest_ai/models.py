"""Validated request and response models for the LexiQuest AI API."""

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

# Supported CEFR levels. ``unknown`` allows requests that are not level-bound
# (e.g. free-form tutor questions) without forcing a bogus level.
CefrLevel = Literal["a1", "a2", "b1", "b2", "c1", "c2", "unknown"]

# Content kinds the API knows how to generate. Each kind maps to a dedicated
# system prompt in ``LlmContentService``. Adding a kind is a one-line change
# to the Literal plus a prompt entry.
ContentKind = Literal["sentence", "story", "explanation"]


class ContentRequest(BaseModel):
    """Request payload for AI content generation.

    ``model`` is intentionally forbidden: clients cannot choose the underlying
    LLM model. The server pins the model in configuration for reproducibility
    and cost control.
    """

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    text: str = Field(..., min_length=1, max_length=MAX_TEXT_LENGTH_CEILING)
    kind: ContentKind
    cefr: CefrLevel = "unknown"
    language: Literal["en", "th"] = "en"

    @field_validator("text")
    @classmethod
    def _normalize_whitespace(cls, value: str) -> str:
        """Collapse all whitespace runs in text to a single space."""

        return re.sub(r"\s+", " ", value)


@dataclass(frozen=True, slots=True)
class ContentResult:
    """Immutable result of a content generation operation.

    ``cached`` is filled by the service layer (not the provider) so the provider
    stays unaware of the cache boundary.
    """

    text: str
    kind: str
    model_version: str
    cached: bool = False


class ContentResponse(BaseModel):
    """Response payload for AI content generation."""

    text: str
    kind: str
    language: str
    cefr: str
    model_version: str
    cached: bool
