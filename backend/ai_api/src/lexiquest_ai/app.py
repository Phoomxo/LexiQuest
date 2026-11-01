"""FastAPI application factory for the LexiQuest AI API.

The factory depends on a ``ContentGenerator`` and a ``TokenVerifier`` protocol
so tests inject small fakes and never touch the network, an LLM provider, or
Firebase. The endpoint contract mirrors ``lexiquest_voice`` so the same
Flutter client shape (401-refresh-retry, ``detail.code`` error mapping) works
against both services.
"""

from __future__ import annotations

import logging
from pydantic import BaseModel, ConfigDict, Field
from typing import Protocol
from uuid import uuid4

from fastapi import FastAPI, Header
from fastapi import HTTPException, status
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from fastapi.exception_handlers import request_validation_exception_handler
from starlette.types import ASGIApp, Message, Receive, Scope, Send

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
from lexiquest_ai.billing import BillingError, BillingService
from lexiquest_ai.play_billing import GooglePubSubPushVerifier, decode_play_notification
from lexiquest_ai.research import (
    ResearchConsentRequest, ResearchError, ResearchRefreshRequest, ResearchService,
    StudyUploadRequest, unique_json,
)
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


class PlayVerifyRequest(BaseModel):
    model_config = ConfigDict(extra='forbid', hide_input_in_errors=True)
    purchaseToken: str = Field(min_length=1, max_length=4096, repr=False)
    requestId: str = Field(pattern=r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$')


class RequestBodyLimitMiddleware:
    maximum_bytes = 100_000

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] not in ("POST", "PUT", "PATCH"):
            await self.app(scope, receive, send)
            return

        maximum_bytes = 768 * 1024 if scope.get('path') == '/v1/research/study-archives' else self.maximum_bytes

        async def reject(status_code: int) -> None:
            response = JSONResponse(
                status_code=status_code,
                content={
                    "detail": {
                        "code": (
                            "PAYLOAD_TOO_LARGE"
                            if status_code == 413 else "INVALID_CONTENT_LENGTH"
                        ),
                        "message": (
                            "Request body exceeds the route limit."
                            if status_code == 413 else "Content-Length is invalid."
                        ),
                    }
                },
            )
            await response(scope, receive, send)

        lengths = [
            value.strip() for name, value in scope["headers"]
            if name.lower() == b"content-length"
        ]
        if len(lengths) > 1 or (
            lengths and (not lengths[0].isdigit() or len(lengths[0]) > 20)
        ):
            await reject(400)
            return
        if lengths and int(lengths[0]) > maximum_bytes:
            await reject(413)
            return

        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            if len(body) + len(chunk) > maximum_bytes:
                await reject(413)
                return
            body.extend(chunk)
            if not message.get("more_body", False):
                break

        if scope.get('path', '').startswith('/v1/research/'):
            try:
                unique_json(bytes(body), maximum_bytes)
            except ResearchError:
                await JSONResponse(status_code=400, content={'detail': {
                    'code': 'RESEARCH_INVALID_REQUEST', 'message': 'The research request is invalid.'}})(scope, receive, send)
                return

        delivered = False

        async def replay() -> Message:
            nonlocal delivered
            if not delivered:
                delivered = True
                return {
                    "type": "http.request",
                    "body": bytes(body),
                    "more_body": False,
                }
            return await receive()

        await self.app(scope, replay, send)


class AccountDeletionReadinessProbe(Protocol):
    def is_ready(self) -> bool:
        """Return true only after runtime infrastructure attestation."""

        ...


def create_app(
    *,
    content_service: ContentGenerator,
    token_verifier: TokenVerifier,
    settings: Settings,
    account_deletion_service: AccountDeletionService | None = None,
    account_deletion_readiness_probe: (
        AccountDeletionReadinessProbe | None
    ) = None,
    billing_service: BillingService | None = None,
    billing_notification_verifier: GooglePubSubPushVerifier | None = None,
    research_service: ResearchService | None = None,
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
    app.add_middleware(RequestBodyLimitMiddleware)

    def require_billing():
        if not settings.billing_enabled:
            raise HTTPException(503, detail={'code': 'BILLING_DISABLED', 'message': 'Billing is not enabled.'})
        if billing_service is None:
            raise HTTPException(503, detail={'code': 'BILLING_UNAVAILABLE', 'message': 'Billing is unavailable.'})
        return billing_service

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, error):
        if request.url.path.startswith('/v1/research/'):
            return JSONResponse(status_code=422, content={'detail': {
                'code': 'RESEARCH_INVALID_REQUEST', 'message': 'The research request is invalid.'}})
        if request.url.path.startswith('/v1/billing/'):
            return JSONResponse(status_code=422, content={'detail': {
                'code': 'BILLING_INVALID_REQUEST', 'message': 'The billing request is invalid.'}})
        return await request_validation_exception_handler(request, error)

    def registered_user(user):
        if user.is_anonymous is not False:
            raise HTTPException(403, detail={'code': 'BILLING_ACCOUNT_REQUIRED', 'message': 'A registered account is required.'})
        return user

    def billing_error(error):
        statuses = {'invalid_request': 400, 'owner_mismatch': 403, 'purchase_denied': 403,
            'entitlement_required': 402, 'quota_exhausted': 429, 'verification_rate_limited': 429,
            'request_conflict': 409,
            'operation_uncertain': 409, 'purchase_refresh_pending': 409,
            'owner_deletion_pending': 409, 'authority_changed': 409}
        statuses['notification_unauthenticated'] = 401
        code = error.code if error.code in statuses else 'billing_unavailable'
        return HTTPException(statuses.get(code, 503), detail={
            'code': 'BILLING_' + code.upper(), 'message': 'The billing operation could not be completed.'},
            headers={'Retry-After': '60'} if code == 'verification_rate_limited' else None)

    def snapshot_json(snapshot):
        return {'schemaVersion': 1, 'serverTimeUtc': snapshot.checked_at_utc.isoformat(),
            'acknowledgementPending': snapshot.acknowledgement_pending,
            'refreshRequired': snapshot.refresh_required,
            'grants': [{'entitlement': grant.entitlement, 'expiresAtUtc': grant.expires_at_utc.isoformat(),
                'checkedAtUtc': grant.checked_at_utc.isoformat(), 'dailyManagedUnits': grant.daily_managed_units}
                for grant in snapshot.grants]}

    @app.get('/v1/billing/catalog')
    def billing_catalog(authorization: str | None = Header(default=None)):
        user = token_verifier.verify(extract_bearer_token(authorization))
        service = require_billing()
        registered_user(user)
        return {'schemaVersion': 1, 'packageName': service.policy.package_name,
            'policyRevision': service.policy.revision, 'accountIdentifier': service.account_identifier(user.uid),
            'products': [{'productId': product.product_id, 'basePlanId': product.base_plan_id,
                'entitlements': sorted(product.entitlements)} for product in service.policy.products]}

    @app.post('/v1/billing/play/verify')
    def billing_verify(request: PlayVerifyRequest, authorization: str | None = Header(default=None)):
        user = token_verifier.verify(extract_bearer_token(authorization))
        service = require_billing()
        registered_user(user)
        try:
            return snapshot_json(service.verify_purchase(firebase_uid=user.uid, purchase_token=request.purchaseToken))
        except BillingError as error:
            raise billing_error(error) from None
        except Exception:
            raise billing_error(BillingError('billing_unavailable')) from None

    @app.get('/v1/billing/entitlements')
    def billing_entitlements(authorization: str | None = Header(default=None)):
        user = token_verifier.verify(extract_bearer_token(authorization))
        service = require_billing()
        registered_user(user)
        try:
            return snapshot_json(service.entitlements(firebase_uid=user.uid))
        except BillingError as error:
            raise billing_error(error) from None
        except Exception:
            raise billing_error(BillingError('billing_unavailable')) from None

    @app.post('/v1/billing/play/notifications')
    def billing_notification(request: dict, authorization: str | None = Header(default=None)):
        service = require_billing()
        if billing_notification_verifier is None:
            raise HTTPException(503, detail={'code': 'BILLING_NOTIFICATION_UNAVAILABLE',
                'message': 'Authenticated billing notifications are not configured.'})
        try:
            billing_notification_verifier.verify(extract_bearer_token(authorization))
            token = decode_play_notification(request, package_name=service.policy.package_name)
            handled = token is not None and service.refresh_notification(purchase_token=token)
            return {'accepted': True, 'knownPurchase': handled}
        except HTTPException:
            raise
        except BillingError as error:
            raise billing_error(error) from None
        except Exception:
            raise billing_error(BillingError('billing_unavailable')) from None

    def research_call(authorization, command):
        user = token_verifier.verify(extract_bearer_token(authorization))
        if not settings.research_enabled:
            raise HTTPException(503, detail={'code': 'RESEARCH_DISABLED', 'message': 'Research is disabled.'})
        if user.is_anonymous is not False:
            raise HTTPException(403, detail={'code': 'RESEARCH_ACCOUNT_REQUIRED', 'message': 'A registered account is required.'})
        if research_service is None:
            raise HTTPException(503, detail={'code': 'RESEARCH_AUTHORITY_UNAVAILABLE', 'message': 'Research authority is unavailable.'})
        try:
            result = command(research_service, user.uid)
            return JSONResponse(content=result, headers={'Cache-Control': 'no-store'})
        except ResearchError as error:
            statuses = {'not_enrolled': 404, 'invalid_payload': 400, 'invalid_time': 400,
                'digest_mismatch': 400, 'owner_mismatch': 403, 'archive_denied': 403,
                'authority_denied': 403, 'invalid_signature': 403, 'consent_required': 409,
                'request_conflict': 409, 'deletion_pending': 409}
            raise HTTPException(statuses.get(error.code, 503), detail={
                'code': 'RESEARCH_' + error.code.upper(), 'message': 'The research operation could not be completed.'}) from None
        except Exception:
            raise HTTPException(503, detail={'code': 'RESEARCH_AUTHORITY_UNAVAILABLE',
                'message': 'Research authority is unavailable.'}) from None

    @app.get('/v1/research/enrollment-context')
    def research_context(authorization: str | None = Header(default=None)):
        return research_call(authorization, lambda service, uid: service.context(uid))

    @app.post('/v1/research/consent')
    def research_consent(request: ResearchConsentRequest, authorization: str | None = Header(default=None)):
        return research_call(authorization, lambda service, uid: service.decide(uid, request))

    @app.post('/v1/research/authority/refresh')
    def research_refresh(request: ResearchRefreshRequest, authorization: str | None = Header(default=None)):
        return research_call(authorization, lambda service, uid: service.refresh(uid, request))

    @app.post('/v1/research/study-archives')
    def research_upload(request: StudyUploadRequest, authorization: str | None = Header(default=None)):
        return research_call(authorization, lambda service, uid: service.upload(uid, request))

    def account_deletion_infrastructure_ready() -> bool:
        if (
            account_deletion_service is None
            or account_deletion_readiness_probe is None
        ):
            return False
        try:
            return account_deletion_readiness_probe.is_ready()
        except Exception as error:
            logger.error(
                "Account deletion readiness failed: %s",
                type(error).__name__,
            )
            return False

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
        if settings.billing_enabled and (billing_service is None
                or (settings.environment.lower() == 'production' and billing_notification_verifier is None)):
            return JSONResponse(status_code=503, content={'detail': {
                'code': 'BILLING_UNAVAILABLE', 'message': 'Billing is unavailable.'}})
        deletion_configured = bool(
            settings.account_deletion_enabled
            or settings.account_deletion_server_export_authority
        )
        deletion_ready = (
            account_deletion_infrastructure_ready()
            if deletion_configured
            else False
        )
        if deletion_configured and not deletion_ready:
            return JSONResponse(
                status_code=503,
                content={
                    "detail": {
                        "code": "ACCOUNT_DELETION_UNAVAILABLE",
                        "message": "Account deletion is not configured.",
                    }
                },
                headers={"Retry-After": "5"},
            )
        return {"status": "ready"}

    @app.post("/v1/content")
    def generate_content(
        request: ContentRequest,
        authorization: str | None = Header(default=None),
        idempotency_key: str | None = Header(default=None),
    ) -> ContentResponse:
        token = extract_bearer_token(authorization)
        user = token_verifier.verify(token)
        if len(request.text) > settings.max_text_length:
            raise text_too_long(settings.max_text_length)

        request_id = str(uuid4())
        try:
            if settings.billing_managed_content_required:
                service = require_billing()
                if user.is_anonymous is not False:
                    raise HTTPException(403, detail={'code': 'BILLING_ACCOUNT_REQUIRED', 'message': 'A registered account is required.'})
                if not idempotency_key:
                    raise HTTPException(400, detail={'code': 'BILLING_REQUEST_ID_REQUIRED', 'message': 'Idempotency-Key is required.'})

                def managed_result():
                    value = content_service.generate(request)
                    return ContentResponse(text=value.text, kind=value.kind, language=request.language,
                        cefr=request.cefr, model_version=value.model_version, cached=value.cached).model_dump_json()

                encoded = service.run_managed(firebase_uid=user.uid, request_id=idempotency_key,
                    entitlement='managedContent', request_json=request.model_dump_json(), generate=managed_result)
                return ContentResponse.model_validate_json(encoded)
            result = content_service.generate(request)
        except HTTPException:
            raise
        except BillingError as error:
            raise billing_error(error) from None
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
        if not account_deletion_infrastructure_ready():
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
        return receipt.response(idempotency_key=request.idempotency_key)

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
        return receipt.response(idempotency_key=request.idempotency_key)

    return app
