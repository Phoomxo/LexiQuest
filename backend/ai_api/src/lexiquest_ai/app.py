"""FastAPI application factory for the LexiQuest AI API.

The factory depends on a ``ContentGenerator`` and a ``TokenVerifier`` protocol
so tests inject small fakes and never touch the network, an LLM provider, or
Firebase. The endpoint contract mirrors ``lexiquest_voice`` so the same
Flutter client shape (401-refresh-retry, ``detail.code`` error mapping) works
against both services.
"""

from __future__ import annotations

import logging
from uuid import uuid4

from fastapi import FastAPI, Header
from fastapi.responses import JSONResponse
from starlette.datastructures import Headers
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from lexiquest_ai.auth import TokenVerifier, extract_bearer_token
from lexiquest_ai.config import Settings
from lexiquest_ai.errors import (
    content_generation_failed,
    provider_rate_limited,
    provider_unauthorized,
    provider_unavailable,
    text_too_long,
)
from lexiquest_ai.models import ContentRequest, ContentResponse
from lexiquest_ai.services.base import ContentGenerator
from lexiquest_ai.services.llm_content_service import (
    ProviderError,
    ProviderUnauthorized,
    ProviderUnavailable,
)
from lexiquest_ai.services.rate_limiter import ProviderRateLimited

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
    content_service: ContentGenerator,
    token_verifier: TokenVerifier,
    settings: Settings,
) -> FastAPI:
    """Create the HTTP API without loading production dependencies."""

    is_prod = settings.environment.lower() == "production"
    app = FastAPI(
        title="LexiQuest AI API",
        version=settings.model_version,
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
        # Real provider availability is checked per-request to avoid a probe
        # that would itself cost a request. ``is_ready`` reflects config.
        if not content_service.is_ready:
            return JSONResponse(
                status_code=503,
                content={
                    "detail": {
                        "code": "PROVIDER_UNAVAILABLE",
                        "message": "The content provider is not configured.",
                    }
                },
            )
        return {"status": "ready"}

    @app.post("/v1/content")
    def generate_content(
        request: ContentRequest,
        authorization: str | None = Header(default=None),
    ) -> ContentResponse:
        token = extract_bearer_token(authorization)
        token_verifier.verify(token)
        if len(request.text) > settings.max_text_length:
            raise text_too_long(settings.max_text_length)

        request_id = str(uuid4())
        try:
            result = content_service.generate(request)
        except ProviderUnauthorized:
            logger.warning(
                "Content provider rejected credentials (request_id=%s)", request_id
            )
            raise provider_unauthorized(request_id) from None
        except ProviderRateLimited as error:
            logger.warning(
                "Content chain fully rate limited (request_id=%s): retry after %ss",
                request_id,
                error.retry_after_seconds,
            )
            raise provider_rate_limited(
                request_id, error.retry_after_seconds
            ) from None
        except ProviderUnavailable as error:
            logger.warning(
                "Content provider unavailable (request_id=%s): %s",
                request_id,
                type(error).__name__,
            )
            raise provider_unavailable(request_id) from None
        except (ProviderError, Exception) as error:
            # Catch broad ``Exception`` last so an unexpected provider failure
            # is converted to a stable error rather than a 500 leak. We log
            # only the exception type to avoid leaking provider internals.
            logger.error(
                "Content generation failed (request_id=%s): %s",
                request_id,
                type(error).__name__,
            )
            raise content_generation_failed(request_id) from None

        return ContentResponse(
            text=result.text,
            kind=result.kind,
            language=request.language,
            cefr=request.cefr,
            model_version=result.model_version,
            cached=result.cached,
        )

    return app
