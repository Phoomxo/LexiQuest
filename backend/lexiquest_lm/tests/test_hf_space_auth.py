"""Tests for the Hugging Face Space authentication boundary."""

from __future__ import annotations

import sys
import types
from collections.abc import Callable, Mapping

import pytest

from deploy.hf_space.auth import (
    AuthenticationError,
    FirebaseTokenVerifier,
    extract_bearer_token,
)


@pytest.mark.parametrize(
    "authorization",
    [
        None,
        "",
        "Basic abc",
        "Bearer",
        "Bearer   ",
        "token-without-scheme",
        "Bearer token extra",
    ],
)
def test_extract_bearer_token_rejects_invalid_values(
    authorization: str | None,
) -> None:
    with pytest.raises(AuthenticationError):
        extract_bearer_token(authorization)


@pytest.mark.parametrize(
    "authorization",
    ["Bearer token-abc", "bearer token-abc", "BEARER token-abc", "BeArEr token-abc"],
)
def test_extract_bearer_token_accepts_scheme_case_insensitively(
    authorization: str,
) -> None:
    assert extract_bearer_token(authorization) == "token-abc"


def test_verifier_without_project_id_fails_closed() -> None:
    decoder_calls: list[str] = []

    def decoder(token: str) -> dict[str, object]:
        decoder_calls.append(token)
        return {"uid": "must-not-reach"}

    verifier = FirebaseTokenVerifier(project_id=None, verify_id_token=decoder)
    assert verifier.is_configured is False
    with pytest.raises(AuthenticationError):
        verifier.verify("token")
    assert decoder_calls == []


def test_verifier_hides_decoder_exceptions() -> None:
    secret = "super-secret-token-value"

    def decoder(token: str) -> dict[str, object]:
        raise ValueError(f"decoder failed for {token}")

    verifier = FirebaseTokenVerifier(project_id="project", verify_id_token=decoder)
    with pytest.raises(AuthenticationError) as exc_info:
        verifier.verify(secret)
    assert secret not in str(exc_info.value)


@pytest.mark.parametrize(
    "claims",
    [{}, {"uid": ""}, {"sub": ""}, {"email": "missing@example.com"}],
)
def test_verifier_rejects_missing_or_empty_identity(
    claims: dict[str, object],
) -> None:
    verifier = FirebaseTokenVerifier(
        project_id="project",
        verify_id_token=lambda token: claims,
    )
    with pytest.raises(AuthenticationError):
        verifier.verify("token")


@pytest.mark.parametrize(
    ("claims", "expected_uid"),
    [
        ({"uid": "user-from-uid"}, "user-from-uid"),
        ({"sub": "user-from-sub"}, "user-from-sub"),
    ],
)
def test_verifier_accepts_non_empty_identity(
    claims: dict[str, object],
    expected_uid: str,
) -> None:
    verifier = FirebaseTokenVerifier(
        project_id="project",
        verify_id_token=lambda token: claims,
    )
    assert verifier.is_configured is True
    assert verifier.verify("token").uid == expected_uid


def _install_fake_firebase_admin(
    monkeypatch: pytest.MonkeyPatch,
    *,
    get_app: Callable[[str], object],
    initialize_app: Callable[..., object],
    verify_id_token: Callable[..., Mapping[str, object]],
) -> None:
    admin = types.ModuleType("firebase_admin")
    admin.get_app = get_app
    admin.initialize_app = initialize_app
    auth_module = types.ModuleType("firebase_admin.auth")
    auth_module.verify_id_token = verify_id_token
    admin.auth = auth_module
    monkeypatch.setitem(sys.modules, "firebase_admin", admin)
    monkeypatch.setitem(sys.modules, "firebase_admin.auth", auth_module)


def test_default_decoder_is_built_and_cached_once_across_verify_calls(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    get_app_calls: list[str] = []
    init_app_calls: list[str] = []
    token_calls: list[str] = []

    def fake_get_app(name: str) -> object:
        get_app_calls.append(name)
        raise ValueError("not initialised")

    def fake_initialize_app(*, options: Mapping[str, str], name: str) -> object:
        init_app_calls.append(name)
        return object()

    def fake_verify_id_token(
        token: str,
        *,
        app: object,
        check_revoked: bool,
    ) -> Mapping[str, object]:
        token_calls.append(token)
        return {"uid": "cached-user"}

    _install_fake_firebase_admin(
        monkeypatch,
        get_app=fake_get_app,
        initialize_app=fake_initialize_app,
        verify_id_token=fake_verify_id_token,
    )
    verifier = FirebaseTokenVerifier(project_id="lexiquest")
    for index in range(3):
        assert verifier.verify(f"token-{index}").uid == "cached-user"

    expected_app = "lexiquest-hf-space-lexiquest"
    assert get_app_calls == [expected_app]
    assert init_app_calls == [expected_app]
    assert token_calls == ["token-0", "token-1", "token-2"]


def test_named_app_init_race_falls_back_to_get_app(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    get_app_calls: list[str] = []
    init_app_calls: list[str] = []
    raced = {"won_by_other": False}
    fake_app = object()

    def fake_get_app(name: str) -> object:
        get_app_calls.append(name)
        if raced["won_by_other"]:
            return fake_app
        raise ValueError("not initialised")

    def fake_initialize_app(*, options: Mapping[str, str], name: str) -> object:
        init_app_calls.append(name)
        raced["won_by_other"] = True
        raise ValueError("already exists")

    def fake_verify_id_token(
        token: str,
        *,
        app: object,
        check_revoked: bool,
    ) -> Mapping[str, object]:
        assert app is fake_app
        return {"uid": "race-user"}

    _install_fake_firebase_admin(
        monkeypatch,
        get_app=fake_get_app,
        initialize_app=fake_initialize_app,
        verify_id_token=fake_verify_id_token,
    )
    verifier = FirebaseTokenVerifier(project_id="lexiquest")
    assert verifier.verify("valid-token").uid == "race-user"
    expected_app = "lexiquest-hf-space-lexiquest"
    assert get_app_calls == [expected_app, expected_app]
    assert init_app_calls == [expected_app]
