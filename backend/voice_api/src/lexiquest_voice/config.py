"""Application configuration for the LexiQuest Voice API.

Settings are loaded from environment variables (prefixed with
``LEXIQUEST_VOICE_``) and/or a local ``.env`` file.
"""

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration for the voice synthesis service."""

    model_config = SettingsConfigDict(
        env_prefix="LEXIQUEST_VOICE_",
        env_file=".env",
        extra="ignore",
        frozen=True,
    )

    model_id: str = "k2-fsa/OmniVoice"
    model_version: str = "0.2.1"
    model_revision: str = "c5fdb5ccb189668d56333f77ba2629f4cd7535f4"
    device: str = "cuda:0"
    voice_instruction: str = "female, young adult, clear teacher voice"
    sample_rate: int = Field(default=24_000, gt=0)
    max_text_length: int = Field(default=500, ge=1, le=2000)
    generation_timeout_seconds: int = Field(default=30, ge=1, le=120)
    generation_num_steps: int = Field(default=32, ge=1, le=128)
    guidance_scale: float = Field(default=2.0, ge=0.0, le=20.0)
    position_temperature: float = Field(default=0.0, ge=0.0, le=20.0)
    class_temperature: float = Field(default=0.0, ge=0.0, le=20.0)
    load_asr: bool = False
