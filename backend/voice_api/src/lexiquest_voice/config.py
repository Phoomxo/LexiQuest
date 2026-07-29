"""Application configuration for the LexiQuest Voice API.

Settings are loaded from environment variables (prefixed with
``LEXIQUEST_VOICE_``) and/or a local ``.env`` file.
"""

from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from lexiquest_voice.models import MAX_TEXT_LENGTH_CEILING

# Resolve ``.env`` deterministically relative to this module so the service
# loads the same configuration regardless of the process working directory.
# The README places ``.env`` in the backend project root
# (``backend/voice_api/.env``); ``config.py`` lives three levels below it.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
_ENV_FILE = _PROJECT_ROOT / ".env"

_OMNIVOICE_ENGLISH_INSTRUCTION_ITEMS = frozenset(
    {
        "american accent",
        "australian accent",
        "british accent",
        "canadian accent",
        "child",
        "chinese accent",
        "elderly",
        "female",
        "high pitch",
        "indian accent",
        "japanese accent",
        "korean accent",
        "low pitch",
        "male",
        "middle-aged",
        "moderate pitch",
        "portuguese accent",
        "russian accent",
        "teenager",
        "very high pitch",
        "very low pitch",
        "whisper",
        "young adult",
    }
)


class Settings(BaseSettings):
    """Runtime configuration for the voice synthesis service."""

    model_config = SettingsConfigDict(
        env_prefix="LEXIQUEST_VOICE_",
        env_file=_ENV_FILE,
        extra="ignore",
        frozen=True,
    )

    model_id: str = "k2-fsa/OmniVoice"
    model_version: str = "0.2.1"
    environment: str = "development"
    model_revision: str = "c5fdb5ccb189668d56333f77ba2629f4cd7535f4"
    device: str = "cuda:0"
    voice_instruction: str = (
        "female, young adult, american accent, moderate pitch"
    )
    sample_rate: int = Field(default=24_000, gt=0)
    max_text_length: int = Field(default=500, ge=1, le=MAX_TEXT_LENGTH_CEILING)
    generation_num_steps: int = Field(default=32, ge=1, le=128)
    guidance_scale: float = Field(default=2.0, ge=0.0, le=20.0)
    position_temperature: float = Field(default=0.0, ge=0.0, le=20.0)
    class_temperature: float = Field(default=0.0, ge=0.0, le=20.0)
    load_asr: bool = False

    @field_validator("voice_instruction")
    @classmethod
    def validate_voice_instruction(cls, value: str) -> str:
        items = [item.strip() for item in value.split(",")]
        unsupported = sorted(
            {
                item
                for item in items
                if not item
                or item not in _OMNIVOICE_ENGLISH_INSTRUCTION_ITEMS
            }
        )
        if unsupported:
            formatted = ", ".join(repr(item) for item in unsupported)
            raise ValueError(
                f"Unsupported OmniVoice instruction item(s): {formatted}"
            )
        return ", ".join(items)
