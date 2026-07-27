from fastapi import HTTPException, status


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
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
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
