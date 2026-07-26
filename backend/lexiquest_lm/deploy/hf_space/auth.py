"""Firebase ID-token authentication for the Hugging Face Space.

The Firebase SDK is imported lazily so importing this module performs no
network access and remains safe in test and health-check processes.
"""

from __future__ import annotations

from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Any

_AUTH_FAILURE_MESSAGE = "Authentication failed."

TokenDecoder = Callable[[str], Mapping[str, Any]]


class AuthenticationError(Exception):
    """Uniform authentication failure that never exposes token contents."""

    def __init__(self) -> None:
        super().__init__(_AUTH_FAILURE_MESSAGE)


@dataclass(frozen=True, slots=True)
class VerifiedUser:
    """Identity extracted from a cryptographically verified Firebase token."""

    uid: str


def extract_bearer_token(authorization: str | None) -> str:
    """Extract a token from an exact, case-insensitive Bearer header."""

    if not authorization:
        raise AuthenticationError()
    parts = authorization.split()
    if len(parts) != 2 or parts[0].casefold() != "bearer" or not parts[1]:
        raise AuthenticationError()
    return parts[1]


def _build_default_decoder(project_id: str) -> TokenDecoder:
    """Create a Firebase decoder bound to the configured project."""

    import firebase_admin
    from firebase_admin import auth as firebase_auth

    app_name = f"lexiquest-hf-space-{project_id}"
    try:
        firebase_app = firebase_admin.get_app(app_name)
    except ValueError:
        try:
            firebase_app = firebase_admin.initialize_app(
                options={"projectId": project_id},
                name=app_name,
            )
        except ValueError:
            # Another request may have initialized the named app between the
            # get_app and initialize_app calls.
            firebase_app = firebase_admin.get_app(app_name)

    def decode(token: str) -> Mapping[str, Any]:
        return firebase_auth.verify_id_token(
            token,
            app=firebase_app,
            check_revoked=False,
        )

    return decode


class FirebaseTokenVerifier:
    """Verify Firebase ID tokens and fail closed on every uncertainty."""

    def __init__(
        self,
        project_id: str | None,
        verify_id_token: TokenDecoder | None = None,
    ) -> None:
        self._project_id = (project_id or "").strip()
        self._verify_id_token = verify_id_token
        self._default_decoder: TokenDecoder | None = None

    @property
    def is_configured(self) -> bool:
        return bool(self._project_id)

    def verify(self, token: str) -> VerifiedUser:
        if not self.is_configured:
            raise AuthenticationError()

        try:
            decoder = self._verify_id_token
            if decoder is None:
                if self._default_decoder is None:
                    self._default_decoder = _build_default_decoder(
                        self._project_id,
                    )
                decoder = self._default_decoder
            claims = decoder(token)
        except Exception:
            raise AuthenticationError() from None

        if not isinstance(claims, Mapping):
            raise AuthenticationError()

        candidate = claims.get("uid") or claims.get("sub")
        if not isinstance(candidate, str) or not candidate.strip():
            raise AuthenticationError()
        return VerifiedUser(uid=candidate.strip())
