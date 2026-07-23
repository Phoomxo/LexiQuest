from __future__ import annotations

import logging
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Protocol

from fastapi import HTTPException, status
from firebase_admin import auth as firebase_auth
from firebase_admin import get_app, initialize_app

from lexiquest_voice.errors import auth_unavailable

logger = logging.getLogger(__name__)

TokenDecoder = Callable[[str], Mapping[str, object]]

# Firebase signals a bad, expired, revoked or disabled credential with these.
# Anything else is treated as the auth backend being unreachable.
_INVALID_CREDENTIAL_ERRORS: tuple[type[BaseException], ...] = (
    ValueError,
    firebase_auth.InvalidIdTokenError,
    firebase_auth.ExpiredIdTokenError,
    firebase_auth.RevokedIdTokenError,
    firebase_auth.UserDisabledError,
)


@dataclass(frozen=True, slots=True)
class AuthenticatedUser:
    """Identity established from a verified Firebase ID token."""

    uid: str


class TokenVerifier(Protocol):
    """Authentication boundary consumed by the HTTP layer."""

    def verify(self, token: str) -> AuthenticatedUser:
        """Verify an opaque bearer token and return its user identity."""

        ...


def extract_bearer_token(authorization: str | None) -> str:
    """Extract an opaque token from an HTTP Authorization header."""

    if not authorization:
        raise _unauthenticated()

    parts = authorization.strip().split()
    if len(parts) != 2:
        raise _unauthenticated()

    scheme, token = parts
    if scheme.lower() != "bearer" or not token:
        raise _unauthenticated()
    return token


def _unauthenticated() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail={
            "code": "UNAUTHENTICATED",
            "message": "A valid Firebase ID token is required.",
        },
        headers={"WWW-Authenticate": "Bearer"},
    )


class FirebaseTokenVerifier:
    """Verify Firebase tokens without exposing their contents."""

    def __init__(
        self,
        verify_id_token: TokenDecoder | None = None,
    ) -> None:
        if verify_id_token is None:
            _ensure_default_firebase_app()
            verify_id_token = _decode_firebase_token
        self._verify_id_token = verify_id_token

    def verify(self, token: str) -> AuthenticatedUser:
        try:
            claims = self._verify_id_token(token)
        except _INVALID_CREDENTIAL_ERRORS as error:
            raise _unauthenticated() from error
        except Exception as error:
            # Log only the exception type; never the token or its message,
            # which could leak secrets into logs.
            logger.warning(
                "Firebase token verification failed: %s",
                type(error).__name__,
            )
            raise auth_unavailable() from None

        uid = claims.get("uid")
        if not isinstance(uid, str) or not uid:
            raise _unauthenticated()
        return AuthenticatedUser(uid=uid)


def _ensure_default_firebase_app() -> None:
    try:
        get_app()
    except ValueError:
        initialize_app()


def _decode_firebase_token(token: str) -> Mapping[str, object]:
    return firebase_auth.verify_id_token(token, check_revoked=True)
