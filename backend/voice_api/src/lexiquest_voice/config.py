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
    device: str = "cuda:0"
    voice_instruction: str = "female, young adult, clear teacher voice"
    max_text_length: int = Field(default=500, ge=1, le=2000)
    generation_timeout_seconds: int = Field(default=30, ge=1, le=120)
    load_asr: bool = False
