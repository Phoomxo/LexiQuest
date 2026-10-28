from __future__ import annotations

import asyncio
import logging
from uuid import uuid4

from fastapi import FastAPI, Header, HTTPException, status
from fastapi.responses import JSONResponse, Response
from starlette.datastructures import Headers
from starlette.types import ASGIApp, Message, Receive, Scope, Send

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

_MAX_BODY_BYTES = 100_000


class _RequestBodyLimitMiddleware:
    """Bound actual request bytes before JSON parsing or provider invocation."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] not in ("POST", "PUT", "PATCH"):
            await self.app(scope, receive, send)
            return

        declared = Headers(scope=scope).get("content-length")
        try:
            declared_size = int(declared) if declared is not None else 0
        except ValueError:
            # The transport normally validates this header; actual bytes
            # remain bounded even if it is absent or cannot be trusted.
            declared_size = 0
        if declared_size > _MAX_BODY_BYTES:
            await self._reject(scope, receive, send)
            return

        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            if len(body) + len(chunk) > _MAX_BODY_BYTES:
                # Never append the offending chunk or drain a remaining body.
                await self._reject(scope, receive, send)
                return
            body.extend(chunk)
            if not message.get("more_body", False):
                break

        payload = bytes(body)
        del body
        replayed = False

        async def replay() -> Message:
            nonlocal replayed
            if not replayed:
                replayed = True
                return {"type": "http.request", "body": payload, "more_body": False}
            return await receive()

        await self.app(scope, replay, send)

    async def _reject(self, scope: Scope, receive: Receive, send: Send) -> None:
        response = JSONResponse(
            status_code=413,
            content={
                "detail": {
                    "code": "PAYLOAD_TOO_LARGE",
                    "message": "Request body size exceeds maximum allowed threshold (100KB).",
                }
            },
        )
        await response(scope, receive, send)


def create_app(
    *,
    engine: SpeechEngine,
    token_verifier: TokenVerifier,
    settings: Settings,
) -> FastAPI:
    """Create the HTTP API without loading production dependencies."""

    is_prod = settings.environment.lower() == "production"
    app = FastAPI(
        title="LexiQuest Voice API",
        version="0.1.0",
        docs_url=None if is_prod else "/docs",
        redoc_url=None if is_prod else "/redoc",
        openapi_url=None if is_prod else "/openapi.json",
    )
    app.state.settings = settings

    app.add_middleware(_RequestBodyLimitMiddleware)

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
