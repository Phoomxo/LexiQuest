from __future__ import annotations

import pytest
from fastapi import HTTPException
from firebase_admin import auth as firebase_auth

from lexiquest_voice.auth import FirebaseTokenVerifier, extract_bearer_token


@pytest.mark.parametrize(
    "header",
    [
        None,
        "",
        "Basic abc",
        "Bearer",
        "Bearer  ",
    ],
    ids=[
        "missing_header",
        "empty_string",
        "basic_scheme",
        "bearer_no_token",
        "bearer_two_spaces",
    ],
)
def test_extract_bearer_token_rejects_invalid_headers(
    header: str | None,
) -> None:
    with pytest.raises(HTTPException) as exc_info:
        extract_bearer_token(header)

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail["code"] == "UNAUTHENTICATED"
    assert exc_info.value.headers is not None
    assert exc_info.value.headers["WWW-Authenticate"] == "Bearer"


def test_extract_bearer_token_returns_valid_token() -> None:
    result = extract_bearer_token("Bearer valid-token")

    assert result == "valid-token"


def test_firebase_verifier_returns_authenticated_user() -> None:
    def decoder(token: str) -> dict[str, object]:
        assert token == "token-abc"
        return {"uid": "user-123"}

    verifier = FirebaseTokenVerifier(verify_id_token=decoder)

    assert verifier.verify("token-abc").uid == "user-123"


def test_firebase_verifier_hides_rejected_token() -> None:
    secret_token = "super-secret-token-value"

    def decoder(token: str) -> dict[str, object]:
        raise ValueError("bad token")

    verifier = FirebaseTokenVerifier(verify_id_token=decoder)

    with pytest.raises(HTTPException) as exc_info:
        verifier.verify(secret_token)

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail["code"] == "UNAUTHENTICATED"
    assert secret_token not in str(exc_info.value.detail)
    assert exc_info.value.__cause__ is None


def test_firebase_verifier_rejects_payload_without_uid() -> None:
    def decoder(token: str) -> dict[str, object]:
        return {"email": "no-uid@example.com"}

    verifier = FirebaseTokenVerifier(verify_id_token=decoder)

    with pytest.raises(HTTPException) as exc_info:
        verifier.verify("some-token")

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail["code"] == "UNAUTHENTICATED"


@pytest.mark.parametrize(
    "error",
    [
        firebase_auth.InvalidIdTokenError("invalid id token"),
        firebase_auth.ExpiredIdTokenError(
            "expired id token",
            RuntimeError("expired"),
        ),
        firebase_auth.RevokedIdTokenError("revoked id token"),
        firebase_auth.UserDisabledError("user disabled"),
        ValueError("malformed token"),
    ],
    ids=[
        "invalid_id_token",
        "expired_id_token",
        "revoked_id_token",
        "user_disabled",
        "malformed_token",
    ],
)
def test_firebase_verifier_rejects_invalid_credentials_as_unauthenticated(
    error: Exception,
) -> None:
    secret_token = "super-secret-token-value"

    def decoder(token: str) -> dict[str, object]:
        raise error

    verifier = FirebaseTokenVerifier(verify_id_token=decoder)

    with pytest.raises(HTTPException) as exc_info:
        verifier.verify(secret_token)

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail["code"] == "UNAUTHENTICATED"
    assert secret_token not in str(exc_info.value.detail)


def test_firebase_verifier_reports_unavailable_on_certificate_fetch_error(
    caplog: pytest.LogCaptureFixture,
) -> None:
    secret_token = "super-secret-token-value"
    internal_message = "certificate fetch failed"

    def decoder(token: str) -> dict[str, object]:
        raise firebase_auth.CertificateFetchError(
            internal_message,
            RuntimeError("network unavailable"),
        )

    verifier = FirebaseTokenVerifier(verify_id_token=decoder)

    with caplog.at_level("WARNING", logger="lexiquest_voice.auth"):
        with pytest.raises(HTTPException) as exc_info:
            verifier.verify(secret_token)

    assert exc_info.value.status_code == 503
    assert exc_info.value.detail["code"] == "AUTH_UNAVAILABLE"
    assert exc_info.value.headers is not None
    assert exc_info.value.headers["Retry-After"] == "5"
    assert secret_token not in str(exc_info.value.detail)
    assert "CertificateFetchError" in caplog.text
    assert secret_token not in caplog.text
    assert internal_message not in caplog.text
