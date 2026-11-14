"""Privileged account-deletion boundary tests.

The production adapter is intentionally absent until a reviewed owner-data
store is available. These tests pin the destructive service contract without
touching Firebase or live user data.
"""

from __future__ import annotations

import json
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from lexiquest_ai.account_deletion import (
    CLOUD_DELETION_SCOPES,
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
SCOPE_FIXTURE = json.loads(
    (Path(__file__).resolve().parents[3] / "test/fixtures/account_deletion_export_scopes.json")
    .read_text(encoding="utf-8")
)
V11_ADDITIONS = frozenset(SCOPE_FIXTURE["exportV11"]) - frozenset(
    SCOPE_FIXTURE["exportV10"]
)
V12_ADDITIONS = frozenset({"local_content_reports", "focus_sessions", "learning_preferences"})


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
            "coveredScopes": sorted(CLOUD_DELETION_SCOPES),
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


def _body_with_scopes(schema_version: int, scopes: frozenset[str]) -> dict:
    body = _body()
    body["exportReceipt"]["schemaVersion"] = schema_version
    body["exportReceipt"]["coveredScopes"] = sorted(scopes)
    return body


def test_export_fixture_separates_local_scopes_from_cloud_deletion() -> None:
    cloud = frozenset(SCOPE_FIXTURE["cloudDeletion"])
    old_export = frozenset(SCOPE_FIXTURE["exportV10"])
    new_export = frozenset(SCOPE_FIXTURE["exportV11"])
    assert len(cloud) == len(old_export) == 26
    assert len(new_export) == 32
    assert len(SCOPE_FIXTURE["exportV12"]) == 35
    assert frozenset(SCOPE_FIXTURE["exportV12"]) == new_export | V12_ADDITIONS
    assert cloud == old_export == CLOUD_DELETION_SCOPES
    assert V11_ADDITIONS == {
        "owner_calendar_epochs", "quest_claim_receipts", "streak_baselines",
        "streak_token_adjustments", "quest_definitions", "quest_definition_revisions",
    }


@pytest.mark.parametrize("version", range(1, 11))
def test_legacy_export_scope_versions_remain_accepted(version: int) -> None:
    store = _Store()
    deleter = _Deleter(store)
    response = _client(service=_service(store, deleter)).post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=_body_with_scopes(version, frozenset(SCOPE_FIXTURE["exportV10"])),
    )
    assert response.status_code == 200
    assert deleter.calls[0][2] == frozenset(SCOPE_FIXTURE["cloudDeletion"])


def test_v11_export_deletes_only_cloud_scopes_and_replays_receipt() -> None:
    store = _Store()
    deleter = _Deleter(store)
    client = _client(service=_service(store, deleter))
    headers = {"Authorization": "Bearer valid-token"}
    body = _body_with_scopes(11, frozenset(SCOPE_FIXTURE["exportV11"]))
    first = client.post("/v1/account-deletions", headers=headers, json=body)
    second = client.post("/v1/account-deletions", headers=headers, json=body)
    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    assert first.json()["ownerId"] == OWNER
    assert first.json()["firebaseUid"] == "firebase-user"
    assert first.json()["idempotencyKey"] == KEY
    assert len(deleter.calls) == 1
    assert deleter.calls[0][:3] == (
        OWNER, "firebase-user", frozenset(SCOPE_FIXTURE["cloudDeletion"])
    )
    body["idempotencyKey"] = "delete:00000000-0000-4000-8000-000000000002"
    assert client.post("/v1/account-deletions", headers=headers, json=body).status_code == 409
    assert len(deleter.calls) == 1


def test_v12_export_deletes_only_cloud_scopes_and_replays() -> None:
    store = _Store()
    deleter = _Deleter(store)
    client = _client(service=_service(store, deleter))
    body = _body_with_scopes(12, frozenset(SCOPE_FIXTURE["exportV12"]))
    headers = {"Authorization": "Bearer valid-token"}
    first = client.post("/v1/account-deletions", headers=headers, json=body)
    second = client.post("/v1/account-deletions", headers=headers, json=body)
    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    assert first.json()["ownerId"] == OWNER
    assert first.json()["firebaseUid"] == "firebase-user"
    assert first.json()["idempotencyKey"] == KEY
    assert len(deleter.calls) == 1
    assert deleter.calls[0][:3] == (OWNER, "firebase-user", CLOUD_DELETION_SCOPES)
    body["idempotencyKey"] = "delete:00000000-0000-4000-8000-000000000002"
    assert client.post("/v1/account-deletions", headers=headers, json=body).status_code == 409
    assert len(deleter.calls) == 1


@pytest.mark.parametrize("missing", sorted(V12_ADDITIONS))
def test_v12_export_requires_each_added_scope(missing: str) -> None:
    store = _Store()
    deleter = _Deleter(store)
    body = _body_with_scopes(12, frozenset(SCOPE_FIXTURE["exportV12"]) - {missing})
    response = _client(service=_service(store, deleter)).post(
        "/v1/account-deletions", headers={"Authorization": "Bearer valid-token"}, json=body,
    )
    assert response.status_code == 422
    assert not store.operations
    assert not deleter.calls


@pytest.mark.parametrize("invalid", ["owner", "sha", "bytes"])
def test_v12_rejects_invalid_receipt_without_deletion(invalid: str) -> None:
    store = _Store()
    deleter = _Deleter(store)
    body = _body_with_scopes(12, frozenset(SCOPE_FIXTURE["exportV12"]))
    receipt = body["exportReceipt"]
    if invalid == "owner":
        receipt["ownerId"] = "other-owner"
    elif invalid == "sha":
        receipt["artifactSha256"] = "invalid"
    else:
        receipt["bytesWritten"] = 0
    response = _client(service=_service(store, deleter)).post(
        "/v1/account-deletions", headers={"Authorization": "Bearer valid-token"}, json=body,
    )
    assert response.status_code == 422
    assert not store.operations
    assert not deleter.calls


@pytest.mark.parametrize("missing", sorted(V11_ADDITIONS))
def test_v11_export_requires_every_added_scope(missing: str) -> None:
    store = _Store()
    deleter = _Deleter(store)
    scopes = frozenset(SCOPE_FIXTURE["exportV11"]) - {missing}
    response = _client(service=_service(store, deleter)).post(
        "/v1/account-deletions", headers={"Authorization": "Bearer valid-token"},
        json=_body_with_scopes(11, scopes),
    )
    assert response.status_code == 422
    assert not store.operations
    assert not deleter.calls


@pytest.mark.parametrize(
    ("version", "scope_key", "extra"),
    [(11, "exportV11", True), (11, "exportV10", False),
     (10, "exportV11", False), (12, "exportV11", False),
     (12, "exportV10", False), (12, "exportV12", True),
     (11, "exportV12", False), (13, "exportV12", False)],
)
def test_export_rejects_extra_mismatched_or_future_scopes(
    version: int, scope_key: str, extra: bool,
) -> None:
    store = _Store()
    deleter = _Deleter(store)
    scopes = frozenset(SCOPE_FIXTURE[scope_key]) | ({"unexpected_scope"} if extra else set())
    response = _client(service=_service(store, deleter)).post(
        "/v1/account-deletions", headers={"Authorization": "Bearer valid-token"},
        json=_body_with_scopes(version, scopes),
    )
    assert response.status_code == 422
    assert not store.operations
    assert not deleter.calls


def test_v11_export_owner_mismatch_cannot_start_deletion() -> None:
    store = _Store()
    deleter = _Deleter(store)
    body = _body_with_scopes(11, frozenset(SCOPE_FIXTURE["exportV11"]))
    body["exportReceipt"]["ownerId"] = "owner-b"
    response = _client(service=_service(store, deleter)).post(
        "/v1/account-deletions", headers={"Authorization": "Bearer valid-token"},
        json=body,
    )
    assert response.status_code == 422
    assert not store.operations
    assert not deleter.calls


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
        CLOUD_DELETION_SCOPES,
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
