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
from fastapi import HTTPException, status
from fastapi.responses import JSONResponse

from lexiquest_ai.auth import TokenVerifier, extract_bearer_token
from lexiquest_ai.account_deletion import (
    AccountDeletionConflict,
    AccountDeletionRecoveryRequest,
    AccountDeletionRequest,
    AccountDeletionResponse,
    AccountDeletionService,
    RecentAuthenticationRequired,
)
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


def create_app(
    *,
    content_service: ContentGenerator,
    token_verifier: TokenVerifier,
    settings: Settings,
    account_deletion_service: AccountDeletionService | None = None,
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

    @app.middleware("http")
    async def limit_body_size(request, call_next):
        if request.method in ("POST", "PUT", "PATCH"):
            content_length = request.headers.get("content-length")
            if content_length and int(content_length) > 100_000:
                return JSONResponse(
                    status_code=413,
                    content={
                        "detail": {
                            "code": "PAYLOAD_TOO_LARGE",
                            "message": "Request body size exceeds maximum allowed threshold (100KB).",
                        }
                    },
                )
        return await call_next(request)

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

    @app.post("/v1/account-deletions")
    def delete_account(
        request: AccountDeletionRequest,
        authorization: str | None = Header(default=None),
    ) -> AccountDeletionResponse:
        token = extract_bearer_token(authorization)
        user = token_verifier.verify(token)
        if not settings.account_deletion_enabled:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={
                    "code": "ACCOUNT_DELETION_DISABLED",
                    "message": "Account deletion is not enabled.",
                },
            )
        if account_deletion_service is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={
                    "code": "ACCOUNT_DELETION_UNAVAILABLE",
                    "message": "Account deletion is unavailable.",
                },
                headers={"Retry-After": "5"},
            )
        try:
            receipt = account_deletion_service.delete(request, user)
        except RecentAuthenticationRequired:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": "RECENT_AUTHENTICATION_REQUIRED",
                    "message": "Sign in again before deleting your account.",
                },
            ) from None
        except AccountDeletionConflict:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "code": "ACCOUNT_DELETION_CONFLICT",
                    "message": "A different deletion request already exists.",
                },
            ) from None
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail={
                    "code": "INVALID_ACCOUNT_DELETION_REQUEST",
                    "message": "The account deletion request is invalid.",
                },
            ) from None
        except Exception as error:
            logger.error("Account deletion failed: %s", type(error).__name__)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={
                    "code": "ACCOUNT_DELETION_FAILED",
                    "message": "Account deletion could not be completed.",
                },
                headers={"Retry-After": "5"},
            ) from None
        return receipt.response()

    @app.post("/v1/account-deletions/recover")
    def recover_account_deletion(
        request: AccountDeletionRecoveryRequest,
    ) -> AccountDeletionResponse:
        # The high-entropy idempotency key is a one-operation continuation
        # secret for the case where Firebase Auth was deleted before the
        # original HTTP response reached the device.
        if account_deletion_service is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={
                    "code": "ACCOUNT_DELETION_UNAVAILABLE",
                    "message": "Account deletion is unavailable.",
                },
                headers={"Retry-After": "5"},
            )
        try:
            receipt = account_deletion_service.recover(
                owner_id=request.owner_id,
                firebase_uid=request.firebase_uid,
                idempotency_key=request.idempotency_key,
            )
        except AccountDeletionConflict:
            # Do not disclose whether a UID, owner, or operation exists.
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={
                    "code": "ACCOUNT_DELETION_RECOVERY_NOT_FOUND",
                    "message": "The deletion operation could not be recovered.",
                },
            ) from None
        except Exception as error:
            logger.error(
                "Account deletion recovery failed: %s", type(error).__name__
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={
                    "code": "ACCOUNT_DELETION_FAILED",
                    "message": "Account deletion could not be completed.",
                },
                headers={"Retry-After": "5"},
            ) from None
        return receipt.response()

    return app
