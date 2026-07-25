"""Stable, machine-readable API error payloads for the LexiQuest AI API.

Every error surfaced to the client uses the same shape as ``lexiquest_voice``::

    {"detail": {"code": "<STABLE_CODE>", "message": "..."}}

so the Flutter client can read ``detail.code`` to map a response to a typed
``AiFailure`` category without parsing free-text messages.
"""

from __future__ import annotations

from fastapi import HTTPException, status


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


def content_generation_failed(request_id: str) -> HTTPException:
    """Return the stable error for an unexpected content generation failure."""

    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "code": "CONTENT_GENERATION_FAILED",
            "message": "Content generation could not be completed.",
            "request_id": request_id,
        },
        headers={
            "X-Request-ID": request_id,
            "Retry-After": "5",
        },
    )


def provider_unavailable(request_id: str) -> HTTPException:
    """Return the stable error when the LLM provider is unreachable/overloaded."""

    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "code": "PROVIDER_UNAVAILABLE",
            "message": "The content provider is temporarily unavailable.",
            "request_id": request_id,
        },
        headers={
            "X-Request-ID": request_id,
            "Retry-After": "5",
        },
    )


def provider_rate_limited(request_id: str, retry_after_seconds: int) -> HTTPException:
    """Return the stable error when every provider in the chain is rate limited.

    Surfaced only after the entire fallback chain is exhausted; the caller can
    honour ``Retry-After`` to back off cleanly instead of hammering the API.
    """

    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail={
            "code": "RATE_LIMITED",
            "message": "All content providers are rate limited. Please retry shortly.",
            "request_id": request_id,
        },
        headers={
            "X-Request-ID": request_id,
            "Retry-After": str(max(1, int(retry_after_seconds))),
        },
    )


def provider_unauthorized(request_id: str) -> HTTPException:
    """Return the stable error when the LLM provider rejects the API key.

    Distinct from the client's 401 (which is about the Firebase ID token): this
    surfaces a server-side provider key problem and must never leak the key.
    """

    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "code": "PROVIDER_UNAUTHORIZED",
            "message": "The content provider rejected server credentials.",
            "request_id": request_id,
        },
        headers={
            "X-Request-ID": request_id,
            "Retry-After": "30",
        },
    )
