from __future__ import annotations

from uuid import uuid4

from fastapi import FastAPI, Header
from fastapi.responses import Response

from lexiquest_voice.auth import TokenVerifier, extract_bearer_token
from lexiquest_voice.config import Settings
from lexiquest_voice.engines.base import SpeechEngine
from lexiquest_voice.models import SpeechRequest


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
        return {"status": "ready"}

    @app.post("/v1/speech")
    def synthesize(
        request: SpeechRequest,
        authorization: str | None = Header(default=None),
    ) -> Response:
        token = extract_bearer_token(authorization)
        token_verifier.verify(token)
        audio = engine.synthesize(request)
        return Response(
            content=audio.data,
            media_type=audio.media_type,
            headers={
                "X-Request-ID": str(uuid4()),
                "X-Voice-Engine": audio.engine,
                "X-Model-Version": audio.model_version,
                "X-Audio-Sample-Rate": str(audio.sample_rate),
                "Cache-Control": "no-store",
            },
        )

    return app
