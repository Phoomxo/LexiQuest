"""Privileged account-deletion boundary tests.

Production adapters are covered separately; these tests pin the destructive
service contract without touching Firebase or live user data.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
from dataclasses import replace
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from lexiquest_ai.account_deletion import (
    ACCOUNT_DELETION_SCOPES,
    AccountDeletionOperation,
    AccountDeletionRequest,
    AccountDeletionReceipt,
    AccountDeletionService,
    RecoveryKeyProof,
)
from lexiquest_ai.app import create_app
from lexiquest_ai.auth import AuthenticatedUser, FirebaseTokenVerifier
from lexiquest_ai.config import Settings

from conftest import FakeContentService

NOW = datetime(2026, 10, 24, 10, 0, tzinfo=UTC)
KEY = "delete:00000000-0000-4000-8000-000000000001"
OWNER = "owner-a"


class _RecoveryKeys:
    key_version = "test-recovery-key-v1"
    secret = b"synthetic-recovery-verifier-key"

    def issue(self, idempotency_key: str) -> RecoveryKeyProof:
        return RecoveryKeyProof(
            algorithm="HMAC-SHA256",
            key_version=self.key_version,
            mac=hmac.new(
                self.secret, idempotency_key.encode("utf-8"), hashlib.sha256
            ).digest(),
        )

    def verify(
        self, idempotency_key: str, proof: RecoveryKeyProof
    ) -> bool:
        return proof == self.issue(idempotency_key)


class _Verifier:
    def __init__(self, *, uid: str = "firebase-user", authenticated_at=NOW):
        self.user = AuthenticatedUser(
            uid=uid,
            authenticated_at_utc=authenticated_at,
        )

    def verify(self, token: str) -> AuthenticatedUser:
        assert token == "valid-token"
        return self.user


class _ReadinessProbe:
    def __init__(
        self, *, ready: bool = True, failure: Exception | None = None
    ) -> None:
        self.ready = ready
        self.failure = failure

    def is_ready(self) -> bool:
        if self.failure is not None:
            raise self.failure
        return self.ready


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

    def get(self, firebase_uid: str) -> AccountDeletionOperation | None:
        return self.operations.get(firebase_uid)

    def mark_server_export_completed(
        self, operation: AccountDeletionOperation
    ) -> AccountDeletionOperation:
        completed = replace(operation, server_export_completed=True)
        self.operations[operation.firebase_uid] = completed
        return completed

    def mark_identity_deleted(
        self, operation: AccountDeletionOperation
    ) -> AccountDeletionOperation:
        completed = replace(operation, identity_deleted=True)
        self.operations[operation.firebase_uid] = completed
        return completed


class _Deleter:
    def __init__(self, store: _Store) -> None:
        self.store = store
        self.calls: list[tuple[str, str, frozenset[str], str]] = []
        self.identity_calls: list[tuple[str, str]] = []
        self.data_failure: Exception | None = None
        self.fail_identity_once = False

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
        if self.data_failure is not None:
            raise self.data_failure

    def delete_auth_identity(
        self, *, firebase_uid: str, operation_id: str
    ) -> None:
        self.identity_calls.append((firebase_uid, operation_id))
        if self.fail_identity_once:
            self.fail_identity_once = False
            raise RuntimeError("synthetic lost acknowledgement")


class _ServerExportAuthority:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str, str, str]] = []
        self.failure: Exception | None = None

    def ensure_complete_export(
        self,
        *,
        owner_id: str,
        firebase_uid: str,
        idempotency_key: str,
        operation_id: str,
        client_export_receipt,
    ) -> None:  # type: ignore[no-untyped-def]
        assert client_export_receipt.covered_scopes == ACCOUNT_DELETION_SCOPES
        self.calls.append(
            (owner_id, firebase_uid, idempotency_key, operation_id)
        )
        if self.failure is not None:
            raise self.failure


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
    readiness_probe: _ReadinessProbe | None = None,
) -> TestClient:
    return TestClient(
        create_app(
            content_service=FakeContentService(),
            token_verifier=verifier or _Verifier(),
            settings=Settings(account_deletion_enabled=enabled),
            account_deletion_service=service,
            account_deletion_readiness_probe=(
                readiness_probe
                if readiness_probe is not None
                else (_ReadinessProbe() if service is not None else None)
            ),
        )
    )


def _service(
    store: _Store,
    deleter: _Deleter,
    authority: _ServerExportAuthority | None = None,
) -> AccountDeletionService:
    return AccountDeletionService(
        store=store,
        deleter=deleter,
        server_export_authority=authority or _ServerExportAuthority(),
        recovery_key_authority=_RecoveryKeys(),
        recovery_retention=timedelta(days=7),
        now_utc=lambda: NOW,
    )


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
    authority = _ServerExportAuthority()
    response = _client(service=_service(store, deleter, authority)).post(
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
    assert authority.calls[0][:3] == (OWNER, "firebase-user", KEY)
    assert store.operations["firebase-user"].server_export_completed is True


@pytest.mark.parametrize(
    "probe",
    [
        _ReadinessProbe(ready=False),
        _ReadinessProbe(failure=RuntimeError("synthetic attestation failure")),
    ],
)
def test_new_deletion_fails_before_tombstone_when_readiness_fails(
    probe: _ReadinessProbe,
) -> None:
    store = _Store()
    deleter = _Deleter(store)
    authority = _ServerExportAuthority()

    response = _client(
        service=_service(store, deleter, authority),
        readiness_probe=probe,
    ).post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=_body(),
    )

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "ACCOUNT_DELETION_UNAVAILABLE"
    assert store.operations == {}
    assert not authority.calls
    assert not deleter.calls


def test_export_authority_failure_never_marks_or_starts_deletion(
    caplog: pytest.LogCaptureFixture,
) -> None:
    store = _Store()
    deleter = _Deleter(store)
    authority = _ServerExportAuthority()
    authority.failure = RuntimeError(f"synthetic KMS unavailable: {KEY}")

    with caplog.at_level(logging.ERROR):
        response = _client(service=_service(store, deleter, authority)).post(
            "/v1/account-deletions",
            headers={"Authorization": "Bearer valid-token"},
            json=_body(),
        )

    assert response.status_code == 503
    operation = store.operations["firebase-user"]
    assert operation.server_export_completed is False
    assert operation.receipt is None
    assert not deleter.calls
    assert not deleter.identity_calls
    assert KEY not in f"{response.text}\n{caplog.text}"


def test_owner_delete_lost_race_never_attaches_receipt_or_deletes_auth() -> None:
    store = _Store()
    deleter = _Deleter(store)
    deleter.data_failure = RuntimeError(
        "synthetic update-time precondition failed"
    )

    response = _client(service=_service(store, deleter)).post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=_body(),
    )

    assert response.status_code == 503
    operation = store.operations["firebase-user"]
    assert operation.server_export_completed is True
    assert operation.receipt is None
    assert operation.identity_deleted is False
    assert not deleter.identity_calls


def test_recovery_does_not_start_data_deletion_without_a_committed_receipt() -> None:
    store = _Store()
    deleter = _Deleter(store)
    operation = AccountDeletionOperation(
        operation_id="operation-without-export",
        owner_id=OWNER,
        firebase_uid="firebase-user",
        recovery_key_proof=_RecoveryKeys().issue(KEY),
        scopes=ACCOUNT_DELETION_SCOPES,
        requested_at_utc=NOW,
        server_export_completed=True,
        recovery_expires_at_utc=NOW + timedelta(days=7),
    )
    store.operations[operation.firebase_uid] = operation

    response = _client(service=_service(store, deleter)).post(
        "/v1/account-deletions/recover",
        json={
            "ownerId": OWNER,
            "firebaseUid": "firebase-user",
            "idempotencyKey": KEY,
        },
    )

    assert response.status_code == 404
    assert not deleter.calls


def test_disabled_new_deletions_still_finish_a_committed_recovery() -> None:
    store = _Store()
    deleter = _Deleter(store)
    receipt = AccountDeletionReceipt(
        receipt_id="committed-operation",
        owner_id=OWNER,
        firebase_uid="firebase-user",
        completed_at_utc=NOW,
    )
    committed = AccountDeletionOperation(
        operation_id=receipt.receipt_id,
        owner_id=OWNER,
        firebase_uid="firebase-user",
        recovery_key_proof=_RecoveryKeys().issue(KEY),
        scopes=ACCOUNT_DELETION_SCOPES,
        requested_at_utc=NOW,
        receipt=receipt,
        server_export_completed=True,
        recovery_expires_at_utc=NOW + timedelta(days=7),
    )
    store.operations[committed.firebase_uid] = committed

    response = _client(enabled=False, service=_service(store, deleter)).post(
        "/v1/account-deletions/recover",
        json={
            "ownerId": OWNER,
            "firebaseUid": "firebase-user",
            "idempotencyKey": KEY,
        },
    )

    assert response.status_code == 200
    assert response.json()["receiptId"] == receipt.receipt_id
    assert not deleter.calls
    assert len(deleter.identity_calls) == 1


def test_recovery_fails_closed_after_the_bounded_retention_window() -> None:
    store = _Store()
    deleter = _Deleter(store)
    expired = AccountDeletionOperation(
        operation_id="expired-operation",
        owner_id=OWNER,
        firebase_uid="firebase-user",
        recovery_key_proof=_RecoveryKeys().issue(KEY),
        scopes=ACCOUNT_DELETION_SCOPES,
        requested_at_utc=NOW,
        server_export_completed=True,
        recovery_expires_at_utc=NOW + timedelta(days=7),
    )
    store.operations[expired.firebase_uid] = expired
    service = AccountDeletionService(
        store=store,
        deleter=deleter,
        server_export_authority=_ServerExportAuthority(),
        recovery_key_authority=_RecoveryKeys(),
        recovery_retention=timedelta(days=7),
        now_utc=lambda: NOW + timedelta(days=8),
    )

    response = _client(service=service).post(
        "/v1/account-deletions/recover",
        json={
            "ownerId": OWNER,
            "firebaseUid": "firebase-user",
            "idempotencyKey": KEY,
        },
    )

    assert response.status_code == 404
    assert not deleter.calls


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


def test_secret_recovery_finishes_auth_after_a_lost_response() -> None:
    store = _Store()
    deleter = _Deleter(store)
    deleter.fail_identity_once = True
    service = _service(store, deleter)

    try:
        service.delete(
            AccountDeletionRequest.model_validate(_body()),
            AuthenticatedUser(uid="firebase-user", authenticated_at_utc=NOW),
        )
    except RuntimeError:
        pass
    else:
        raise AssertionError("expected the first identity deletion to fail")

    operation = store.operations["firebase-user"]
    assert operation.receipt is not None
    assert operation.identity_deleted is False

    recovered = service.recover(
        owner_id=OWNER,
        firebase_uid="firebase-user",
        idempotency_key=KEY,
    )

    assert recovered == operation.receipt
    assert len(deleter.calls) == 1
    assert len(deleter.identity_calls) == 2
    assert store.operations["firebase-user"].identity_deleted is True


def test_http_recovery_uses_the_secret_after_auth_deletion_ack_is_lost() -> None:
    store = _Store()
    deleter = _Deleter(store)
    deleter.fail_identity_once = True
    client = _client(service=_service(store, deleter))

    first = client.post(
        "/v1/account-deletions",
        headers={"Authorization": "Bearer valid-token"},
        json=_body(),
    )
    recovered = client.post(
        "/v1/account-deletions/recover",
        json={
            "ownerId": OWNER,
            "firebaseUid": "firebase-user",
            "idempotencyKey": KEY,
        },
    )

    assert first.status_code == 503
    assert recovered.status_code == 200
    assert recovered.json()["idempotencyKey"] == KEY
    assert len(deleter.calls) == 1
    assert len(deleter.identity_calls) == 2


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
