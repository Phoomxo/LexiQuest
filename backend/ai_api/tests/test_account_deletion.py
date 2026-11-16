"""Privileged account-deletion boundary tests.

The production adapter is intentionally absent until a reviewed owner-data
store is available. These tests pin the destructive service contract without
touching Firebase or live user data.
"""

from __future__ import annotations

from dataclasses import replace
from datetime import UTC, datetime, timedelta

from fastapi.testclient import TestClient

from lexiquest_ai.account_deletion import (
    ACCOUNT_DELETION_SCOPES,
    AccountDeletionOperation,
    AccountDeletionReceipt,
    AccountDeletionService,
)
from lexiquest_ai.app import create_app
from lexiquest_ai.auth import AuthenticatedUser, FirebaseTokenVerifier
from lexiquest_ai.config import Settings

from conftest import FakeContentService

NOW = datetime(2026, 10, 24, 10, 0, tzinfo=UTC)
KEY = "delete:00000000-0000-4000-8000-000000000001"
OWNER = "owner-a"


class _Verifier:
    def __init__(self, *, uid: str = "firebase-user", authenticated_at=NOW):
        self.user = AuthenticatedUser(
            uid=uid,
            authenticated_at_utc=authenticated_at,
        )

    def verify(self, token: str) -> AuthenticatedUser:
        assert token == "valid-token"
        return self.user


class _Store:
    def __init__(self) -> None:
        self.operations: dict[str, AccountDeletionOperation] = {}
        self.claimed_before_delete = False

    def claim(self, operation: AccountDeletionOperation) -> AccountDeletionOperation:
        current = self.operations.setdefault(operation.firebase_uid, operation)
        self.claimed_before_delete = True
        return current

    def complete(
        self,
        operation: AccountDeletionOperation,
        receipt: AccountDeletionReceipt,
    ) -> AccountDeletionReceipt:
        completed = replace(operation, receipt=receipt)
        self.operations[operation.firebase_uid] = completed
        return receipt


class _Deleter:
    def __init__(self, store: _Store) -> None:
        self.store = store
        self.calls: list[tuple[str, str, frozenset[str], str]] = []

    def delete_owned_data(
        self,
        *,
        owner_id: str,
        firebase_uid: str,
        scopes: frozenset[str],
        operation_id: str,
    ) -> None:
        assert self.store.claimed_before_delete
        self.calls.append((owner_id, firebase_uid, scopes, operation_id))


def _body(key: str = KEY) -> dict[str, object]:
    return {
        "ownerId": OWNER,
        "idempotencyKey": key,
        "exportReceipt": {
            "ownerId": OWNER,
            "artifactId": "account-export.json",
            "artifactSha256": "a" * 64,
            "bytesWritten": 1024,
            "schemaVersion": 10,
            "coveredScopes": sorted(ACCOUNT_DELETION_SCOPES),
            "completedAtUtc": NOW.isoformat().replace("+00:00", "Z"),
        },
    }


def _client(
    *,
    enabled: bool = True,
    verifier: _Verifier | None = None,
    service: AccountDeletionService | None = None,
) -> TestClient:
    return TestClient(
        create_app(
            content_service=FakeContentService(),
            token_verifier=verifier or _Verifier(),
            settings=Settings(account_deletion_enabled=enabled),
            account_deletion_service=service,
        )
    )


def _service(store: _Store, deleter: _Deleter) -> AccountDeletionService:
    return AccountDeletionService(store=store, deleter=deleter, now_utc=lambda: NOW)


def test_account_deletion_is_disabled_by_default() -> None:
    assert Settings().account_deletion_enabled is False
    response = _client(enabled=False).post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=_body(),
    )
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "ACCOUNT_DELETION_DISABLED"


def test_deletion_uses_server_identity_and_writes_tombstone_first() -> None:
    store = _Store()
    deleter = _Deleter(store)
    response = _client(service=_service(store, deleter)).post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=_body(),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ownerId"] == OWNER
    assert body["firebaseUid"] == "firebase-user"
    assert body["idempotencyKey"] == KEY
    assert deleter.calls[0][:3] == (
        OWNER,
        "firebase-user",
        ACCOUNT_DELETION_SCOPES,
    )


def test_same_uid_and_key_replays_exact_receipt_without_deleting_twice() -> None:
    store = _Store()
    deleter = _Deleter(store)
    client = _client(service=_service(store, deleter))

    first = client.post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=_body(),
    )
    second = client.post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=_body(),
    )

    assert first.json() == second.json()
    assert len(deleter.calls) == 1


def test_same_uid_with_different_key_conflicts() -> None:
    store = _Store()
    deleter = _Deleter(store)
    client = _client(service=_service(store, deleter))
    headers = {"Authorization": "Bearer valid-token"}
    first = client.post(
        "/v1/account-deletions", headers=headers, json=_body()
    )
    assert first.status_code == 200

    response = client.post(
        "/v1/account-deletions",
        headers=headers,
        json=_body("delete:00000000-0000-4000-8000-000000000002"),
    )
    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "ACCOUNT_DELETION_CONFLICT"
    assert len(deleter.calls) == 1


def test_rejects_stale_server_verified_auth_time() -> None:
    store = _Store()
    deleter = _Deleter(store)
    response = _client(
        verifier=_Verifier(authenticated_at=NOW - timedelta(minutes=5, seconds=1)),
        service=_service(store, deleter),
    ).post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=_body(),
    )
    assert response.status_code == 403
    assert response.json()["detail"]["code"] == "RECENT_AUTHENTICATION_REQUIRED"
    assert not store.operations
    assert not deleter.calls


def test_rejects_invalid_key_or_incomplete_export_scope_contract() -> None:
    store = _Store()
    deleter = _Deleter(store)
    client = _client(service=_service(store, deleter))

    invalid_key = client.post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=_body("short"),
    )
    body = _body()
    body["exportReceipt"]["coveredScopes"] = ["vocabulary_words"]  # type: ignore[index]
    incomplete_export = client.post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=body,
    )

    assert invalid_key.status_code == 422
    assert incomplete_export.status_code == 422
    assert not deleter.calls


def test_firebase_verifier_reads_auth_time_from_verified_claims() -> None:
    verifier = FirebaseTokenVerifier(
        verify_id_token=lambda _: {
            "uid": "firebase-user",
            "auth_time": int(NOW.timestamp()),
        }
    )
    assert verifier.verify("opaque-token") == AuthenticatedUser(
        uid="firebase-user",
        authenticated_at_utc=NOW,
    )
