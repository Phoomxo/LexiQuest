from __future__ import annotations

import logging
from typing import Protocol
from uuid import uuid4

from fastapi import FastAPI, Header, HTTPException, Request, status
from fastapi.responses import JSONResponse, Response

from lexiquest_voice.auth import (
    AuthenticatedUser,
    TokenVerifier,
    extract_bearer_token,
)
from lexiquest_voice.config import Settings
from lexiquest_voice.engines.base import SpeechEngine
from lexiquest_voice.errors import (
    model_unavailable,
    mirror_consent_missing,
    mirror_media_error,
    mirror_rate_limited,
    mirror_session_busy,
    mirror_session_expired,
    mirror_session_not_found,
    provider_disabled,
    synthesis_failed,
    text_too_long,
)
from lexiquest_voice.mirror_sessions import (
    MirrorSessionBusy,
    MirrorSessionExpired,
    MirrorSessionNotFound,
    MirrorSessionQuotaExceeded,
    MirrorSessionStore,
    MirrorSessionView,
)
from lexiquest_voice.models import AudioResult, MirrorSpeechRequest, SpeechRequest

logger = logging.getLogger(__name__)


class MirrorSpeechEngine(Protocol):
    def synthesize(self, *, text: str, reference_audio: bytes) -> AudioResult: ...


def create_app(
    *,
    engine: SpeechEngine,
    token_verifier: TokenVerifier,
    settings: Settings,
    mirror_engine: MirrorSpeechEngine | None = None,
    mirror_sessions: MirrorSessionStore | None = None,
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

    @app.middleware("http")
    async def limit_body_size(request, call_next):
        if request.method in ("POST", "PUT", "PATCH"):
            content_length = request.headers.get("content-length")
            is_mirror_enrollment = (
                request.method == "POST"
                and request.url.path == "/v1/voice-mirror/sessions"
            )
            byte_limit = (
                settings.mirror_max_reference_bytes
                if is_mirror_enrollment
                else 100_000
            )
            try:
                length = int(content_length) if content_length else None
            except ValueError:
                length = -1
            if length is not None and (length < 0 or length > byte_limit):
                return JSONResponse(
                    status_code=(
                        status.HTTP_413_CONTENT_TOO_LARGE
                        if length > byte_limit
                        else status.HTTP_400_BAD_REQUEST
                    ),
                    content={
                        "detail": {
                            "code": (
                                "PAYLOAD_TOO_LARGE"
                                if length > byte_limit
                                else "INVALID_CONTENT_LENGTH"
                            ),
                            "message": "Request body size is invalid.",
                        }
                    },
                )
        response = await call_next(request)
        if request.url.path.startswith("/v1/voice-mirror/"):
            response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/health/live")
    def live() -> dict[str, str]:
        return {"status": "live"}

    @app.get("/health/ready")
    def ready() -> dict[str, str]:
        if not settings.provider_enabled:
            raise provider_disabled()
        if not engine.is_ready:
            raise model_unavailable()
        return {"status": "ready"}

    @app.post("/v1/speech")
    def synthesize(
        request: SpeechRequest,
        authorization: str | None = Header(default=None),
    ) -> Response:
        if not settings.provider_enabled:
            raise provider_disabled()
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

    def mirror_dependencies() -> tuple[MirrorSpeechEngine, MirrorSessionStore]:
        if (
            not settings.provider_enabled
            or not settings.mirror_enabled
            or mirror_engine is None
            or mirror_sessions is None
        ):
            raise provider_disabled()
        return mirror_engine, mirror_sessions

    def authenticated_user(authorization: str | None) -> AuthenticatedUser:
        token = extract_bearer_token(authorization)
        return token_verifier.verify(token)

    @app.post("/v1/voice-mirror/sessions", status_code=status.HTTP_201_CREATED)
    async def create_mirror_session(
        request: Request,
        authorization: str | None = Header(default=None),
        x_voice_mirror_consent: str | None = Header(default=None),
    ) -> JSONResponse:
        _, sessions = mirror_dependencies()
        user = authenticated_user(authorization)
        if x_voice_mirror_consent != settings.mirror_consent_version:
            raise mirror_consent_missing()
        if request.headers.get("content-type", "").split(";")[0].lower() != (
            "audio/wav"
        ):
            raise mirror_media_error(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                code="UNSUPPORTED_MEDIA_TYPE",
                message="Enrollment audio must be WAV.",
            )
        content_length = request.headers.get("content-length")
        if content_length is None:
            raise mirror_media_error(
                status_code=status.HTTP_411_LENGTH_REQUIRED,
                code="LENGTH_REQUIRED",
                message="Enrollment audio length is required.",
            )
        reference_audio = await request.body()
        if int(content_length) != len(reference_audio):
            raise mirror_media_error(
                status_code=status.HTTP_400_BAD_REQUEST,
                code="INVALID_CONTENT_LENGTH",
                message="Enrollment audio length is invalid.",
            )
        if len(reference_audio) > settings.mirror_max_reference_bytes:
            raise mirror_media_error(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                code="PAYLOAD_TOO_LARGE",
                message="Enrollment audio exceeds the byte limit.",
            )
        if (
            len(reference_audio) < 12
            or reference_audio[:4] != b"RIFF"
            or reference_audio[8:12] != b"WAVE"
        ):
            raise mirror_media_error(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="INVALID_AUDIO",
                message="Enrollment audio is invalid.",
            )
        sessions.purge_expired()
        view = sessions.create(user.uid, reference_audio)
        return JSONResponse(
            status_code=status.HTTP_201_CREATED,
            content=_mirror_view_json(view),
        )

    @app.post("/v1/voice-mirror/sessions/{session_id}/heartbeat")
    def heartbeat_mirror_session(
        session_id: str,
        authorization: str | None = Header(default=None),
    ) -> dict[str, object]:
        _, sessions = mirror_dependencies()
        user = authenticated_user(authorization)
        try:
            view = sessions.heartbeat(session_id, user.uid)
        except Exception as error:
            raise _mirror_session_failure(error, sessions) from None
        sessions.purge_expired()
        return _mirror_view_json(view)

    @app.post("/v1/voice-mirror/sessions/{session_id}/speech")
    def synthesize_mirror_speech(
        session_id: str,
        request: MirrorSpeechRequest,
        authorization: str | None = Header(default=None),
    ) -> Response:
        selected_engine, sessions = mirror_dependencies()
        user = authenticated_user(authorization)
        if len(request.text) > settings.mirror_max_text_length:
            raise text_too_long(settings.mirror_max_text_length)
        try:
            with sessions.acquire(
                session_id,
                user.uid,
                request.text,
            ) as lease:
                audio = selected_engine.synthesize(
                    text=request.text,
                    reference_audio=lease.reference_audio,
                )
        except (
            MirrorSessionNotFound,
            MirrorSessionExpired,
            MirrorSessionQuotaExceeded,
            MirrorSessionBusy,
        ) as error:
            raise _mirror_session_failure(error, sessions) from None
        except Exception as error:
            request_id = str(uuid4())
            logger.error(
                "Mirror synthesis failed (request_id=%s): %s",
                request_id,
                type(error).__name__,
            )
            raise synthesis_failed(request_id) from None
        sessions.purge_expired()
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

    @app.delete(
        "/v1/voice-mirror/sessions/{session_id}",
        status_code=status.HTTP_204_NO_CONTENT,
    )
    def delete_mirror_session(
        session_id: str,
        authorization: str | None = Header(default=None),
    ) -> Response:
        _, sessions = mirror_dependencies()
        user = authenticated_user(authorization)
        try:
            sessions.delete(session_id, user.uid)
        except MirrorSessionNotFound:
            raise mirror_session_not_found() from None
        sessions.purge_expired()
        return Response(
            status_code=status.HTTP_204_NO_CONTENT,
            headers={"Cache-Control": "no-store"},
        )

    return app


def _mirror_view_json(view: MirrorSessionView) -> dict[str, object]:
    return {
        "sessionId": view.session_id,
        "leaseExpiresAtEpochMs": int(view.lease_expires_at * 1000),
        "absoluteExpiresAtEpochMs": int(view.absolute_expires_at * 1000),
    }


def _mirror_session_failure(
    error: Exception,
    sessions: MirrorSessionStore,
) -> HTTPException:
    if isinstance(error, MirrorSessionExpired):
        sessions.purge_expired()
        return mirror_session_expired()
    if isinstance(error, MirrorSessionQuotaExceeded):
        return mirror_rate_limited()
    if isinstance(error, MirrorSessionBusy):
        return mirror_session_busy()
    return mirror_session_not_found()
