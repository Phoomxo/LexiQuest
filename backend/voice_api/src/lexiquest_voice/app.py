from __future__ import annotations

import logging
from uuid import uuid4

from fastapi import FastAPI, Header
from fastapi.responses import Response

from lexiquest_voice.auth import TokenVerifier, extract_bearer_token
from lexiquest_voice.config import Settings
from lexiquest_voice.engines.base import SpeechEngine
from lexiquest_voice.errors import (
    model_unavailable,
    synthesis_failed,
    text_too_long,
)
from lexiquest_voice.models import SpeechRequest

logger = logging.getLogger(__name__)


def create_app(
    *,
    engine: SpeechEngine,
    token_verifier: TokenVerifier,
    settings: Settings,
) -> FastAPI:
    """Create the HTTP API without loading production dependencies."""

    app = FastAPI(title="LexiQuest Voice API", version="0.1.0")
    app.state.settings = settings

    @app.get("/health/live")
    def live() -> dict[str, str]:
        return {"status": "live"}

    @app.get("/health/ready")
    def ready() -> dict[str, str]:
        if not engine.is_ready:
            raise model_unavailable()
        return {"status": "ready"}

    @app.post("/v1/speech")
    def synthesize(
        request: SpeechRequest,
        authorization: str | None = Header(default=None),
    ) -> Response:
        token = extract_bearer_token(authorization)
        token_verifier.verify(token)
        if len(request.text) > settings.max_text_length:
            raise text_too_long(settings.max_text_length)
        request_id = str(uuid4())
        try:
            audio = engine.synthesize(request)
        except Exception as error:
            logger.error(
                "Speech synthesis failed (request_id=%s): %s",
                request_id,
                type(error).__name__,
            )
            raise synthesis_failed(request_id) from None
        return Response(
            content=audio.data,
            media_type=audio.media_type,
            headers={
                "X-Request-ID": request_id,
                "X-Voice-Engine": audio.engine,
                "X-Model-Version": audio.model_version,
                "X-Audio-Sample-Rate": str(audio.sample_rate),
                "Cache-Control": "no-store",
            },
        )

    return app
