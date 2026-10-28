from fastapi import HTTPException, status


def provider_disabled() -> HTTPException:
    """Return the stable error used by the provider kill switch."""

    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "code": "PROVIDER_DISABLED",
            "message": "The speech provider is disabled.",
        },
    )


def model_unavailable() -> HTTPException:
    """Return the stable readiness error exposed by the API."""

    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "code": "MODEL_UNAVAILABLE",
            "message": "The speech engine is not ready.",
        },
    )


def text_too_long(max_length: int) -> HTTPException:
    """Return the stable error for text exceeding the configured limit."""

    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        detail={
            "code": "TEXT_TOO_LONG",
            "message": (
                f"Text exceeds the maximum length of {max_length} characters."
            ),
        },
    )


def synthesis_failed(request_id: str) -> HTTPException:
    """Return the stable error for an unexpected synthesis failure."""

    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "code": "SYNTHESIS_FAILED",
            "message": "Speech synthesis could not be completed.",
            "request_id": request_id,
        },
        headers={
            "X-Request-ID": request_id,
            "Retry-After": "5",
        },
    )


def auth_unavailable() -> HTTPException:
    """Return the stable error when the auth backend cannot be reached."""

    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "code": "AUTH_UNAVAILABLE",
            "message": "Authentication is temporarily unavailable.",
        },
        headers={"Retry-After": "5"},
    )


def mirror_consent_missing() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail={
            "code": "CONSENT_MISSING",
            "message": "Voice-mirror consent is required.",
        },
    )


def mirror_session_not_found() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={
            "code": "SESSION_NOT_FOUND",
            "message": "The voice-mirror session is unavailable.",
        },
    )


def mirror_session_expired() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_410_GONE,
        detail={
            "code": "SESSION_EXPIRED",
            "message": "The voice-mirror session has expired.",
        },
    )


def mirror_rate_limited() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail={
            "code": "RATE_LIMITED",
            "message": "The voice-mirror session quota has been reached.",
        },
        headers={"Retry-After": "60"},
    )


def mirror_session_busy() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail={
            "code": "SESSION_BUSY",
            "message": "The voice-mirror session is busy.",
        },
    )


def mirror_media_error(
    *,
    status_code: int,
    code: str,
    message: str,
) -> HTTPException:
    return HTTPException(
        status_code=status_code,
        detail={"code": code, "message": message},
    )
