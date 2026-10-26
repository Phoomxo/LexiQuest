from __future__ import annotations

import base64
import hashlib
import hmac
import json
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest
from google.cloud.firestore_v1 import GeoPoint

import lexiquest_ai.firebase_account_deletion as firebase_adapter
from lexiquest_ai.account_deletion import (
    ACCOUNT_DELETION_SCOPES,
    AccountDeletionOperation,
    AccountDeletionReceipt,
    RecoveryKeyProof,
)
from lexiquest_ai.firebase_account_deletion import (
    FIREBASE_ACCOUNT_DATA_SOURCES,
    FirebaseOwnerIsolatedAccountDeleter,
    FirebaseOwnedDeleteTarget,
    FirebaseOwnedAccountSnapshotReader,
    FirebaseExportDocument,
    FirestoreAccountDeletionOperationStore,
    build_firebase_account_deletion_service,
)

NOW = datetime(2026, 10, 26, 9, 0, tzinfo=UTC)
KEY = "delete:operation-0001"


class _RecoveryKeys:
    key_version = "test-recovery-key-v1"
    secret = b"synthetic-test-recovery-secret"

    def issue(self, idempotency_key: str) -> RecoveryKeyProof:
        return RecoveryKeyProof(
            algorithm="HMAC-SHA256",
            key_version=self.key_version,
            mac=hmac.new(
                self.secret,
                idempotency_key.encode("utf-8"),
                hashlib.sha256,
            ).digest(),
        )

    def verify(
        self, idempotency_key: str, proof: RecoveryKeyProof
    ) -> bool:
        return hmac.compare_digest(proof.mac, self.issue(idempotency_key).mac)


RECOVERY_KEYS = _RecoveryKeys()


class _Documents:
    def __init__(self) -> None:
        self.values: dict[str, dict[str, object]] = {}

    def transact(self, uid, update):  # type: ignore[no-untyped-def]
        value, result = update(self.values.get(uid))
        if value is not None:
            self.values[uid] = value
        return result


def _operation(*, key: str = KEY) -> AccountDeletionOperation:
    return AccountDeletionOperation(
        operation_id="operation-1",
        owner_id="owner-a",
        firebase_uid="firebase-user",
        recovery_key_proof=RECOVERY_KEYS.issue(key),
        scopes=ACCOUNT_DELETION_SCOPES,
        requested_at_utc=NOW,
        recovery_expires_at_utc=NOW + timedelta(days=7),
    )


def test_firestore_store_atomically_preserves_the_canonical_operation() -> None:
    documents = _Documents()
    store = FirestoreAccountDeletionOperationStore(documents, RECOVERY_KEYS)
    first = _operation()

    assert store.claim(first) == first
    assert store.claim(_operation(key="delete:different-key")) == first

    exported = store.mark_server_export_completed(first)
    assert exported.server_export_completed is True

    receipt = AccountDeletionReceipt(
        receipt_id="operation-1",
        owner_id="owner-a",
        firebase_uid="firebase-user",
        completed_at_utc=NOW,
    )
    assert store.complete(exported, receipt) == receipt
    assert store.complete(exported, replace(receipt, completed_at_utc=NOW)) == receipt
    completed = store.get("firebase-user")
    assert completed is not None and completed.receipt == receipt

    marked = store.mark_identity_deleted(completed)
    assert marked.identity_deleted is True
    assert store.get("firebase-user") == marked


def test_firestore_store_writes_native_ttl_and_decodes_legacy_iso_timestamp() -> None:
    documents = _Documents()
    store = FirestoreAccountDeletionOperationStore(documents, RECOVERY_KEYS)
    expiry = NOW + timedelta(days=7)

    operation = replace(_operation(), recovery_expires_at_utc=expiry)
    store.claim(operation)

    stored = documents.values["firebase-user"]
    assert stored["recoveryExpiresAtUtc"] == expiry
    assert isinstance(stored["recoveryExpiresAtUtc"], datetime)
    assert "purgeAtUtc" not in stored

    stored["recoveryExpiresAtUtc"] = expiry.isoformat()
    assert store.get("firebase-user") == operation

    completed = replace(operation, identity_deleted=True)
    store.mark_identity_deleted(completed)
    assert documents.values["firebase-user"]["purgeAtUtc"] == expiry


def test_firestore_store_never_persists_the_plaintext_recovery_key() -> None:
    documents = _Documents()
    store = FirestoreAccountDeletionOperationStore(documents, RECOVERY_KEYS)

    store.claim(_operation())

    encoded = json.dumps(
        documents.values["firebase-user"], default=str, sort_keys=True
    )
    assert KEY not in encoded
    assert "idempotencyKey" not in encoded
    assert documents.values["firebase-user"]["recoveryKeyVerifier"] == {
        "algorithm": "HMAC-SHA256",
        "kmsKeyVersion": RECOVERY_KEYS.key_version,
        "mac": base64.b64encode(RECOVERY_KEYS.issue(KEY).mac).decode("ascii"),
    }


def test_firestore_store_migrates_a_legacy_plaintext_key_atomically() -> None:
    documents = _Documents()
    documents.values["firebase-user"] = {
        "operationId": "operation-1",
        "ownerId": "owner-a",
        "firebaseUid": "firebase-user",
        "idempotencyKey": KEY,
        "scopes": sorted(ACCOUNT_DELETION_SCOPES),
        "requestedAtUtc": NOW.isoformat(),
        "identityDeleted": False,
        "serverExportCompleted": True,
        "recoveryExpiresAtUtc": NOW + timedelta(days=7),
        "receipt": {
            "receiptId": "operation-1",
            "ownerId": "owner-a",
            "firebaseUid": "firebase-user",
            "idempotencyKey": KEY,
            "completedAtUtc": NOW.isoformat(),
        },
    }

    operation = FirestoreAccountDeletionOperationStore(
        documents, RECOVERY_KEYS
    ).get("firebase-user")

    assert operation is not None
    assert RECOVERY_KEYS.verify(KEY, operation.recovery_key_proof)
    encoded = json.dumps(documents.values["firebase-user"], default=str)
    assert KEY not in encoded
    assert "idempotencyKey" not in encoded


def test_firestore_store_fails_closed_when_legacy_key_cannot_be_migrated() -> None:
    class _UnavailableRecoveryKeys(_RecoveryKeys):
        def issue(self, idempotency_key: str) -> RecoveryKeyProof:
            raise RuntimeError("synthetic KMS unavailable")

    documents = _Documents()
    legacy = {
        "operationId": "operation-1",
        "ownerId": "owner-a",
        "firebaseUid": "firebase-user",
        "idempotencyKey": KEY,
        "scopes": sorted(ACCOUNT_DELETION_SCOPES),
        "requestedAtUtc": NOW.isoformat(),
        "identityDeleted": False,
        "serverExportCompleted": False,
        "recoveryExpiresAtUtc": NOW + timedelta(days=7),
        "receipt": None,
    }
    documents.values["firebase-user"] = dict(legacy)

    with pytest.raises(RuntimeError, match="KMS unavailable"):
        FirestoreAccountDeletionOperationStore(
            documents, _UnavailableRecoveryKeys()
        ).get("firebase-user")

    assert documents.values["firebase-user"] == legacy


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("identityDeleted", "false"),
        ("serverExportCompleted", 1),
        ("scopes", "research_consents"),
        ("receipt", []),
        ("unexpectedField", "must-not-be-normalized-away"),
        ("purgeAtUtc", NOW + timedelta(days=7)),
    ],
)
def test_firestore_store_fails_closed_on_malformed_operation_types(
    field: str,
    value: object,
) -> None:
    documents = _Documents()
    store = FirestoreAccountDeletionOperationStore(documents, RECOVERY_KEYS)
    store.claim(_operation())
    documents.values["firebase-user"][field] = value
    original = dict(documents.values["firebase-user"])

    with pytest.raises(ValueError):
        store.get("firebase-user")

    assert documents.values["firebase-user"] == original


@pytest.mark.parametrize(
    "invalid_expiry",
    ["not-a-timestamp", datetime(2026, 10, 26, 9, 0)],
)
def test_firestore_store_rejects_invalid_or_naive_ttl_timestamp(
    invalid_expiry: object,
) -> None:
    documents = _Documents()
    documents.values["firebase-user"] = {
        "operationId": "operation-1",
        "ownerId": "owner-a",
        "firebaseUid": "firebase-user",
        "recoveryKeyVerifier": {
            "algorithm": "HMAC-SHA256",
            "kmsKeyVersion": RECOVERY_KEYS.key_version,
            "mac": base64.b64encode(RECOVERY_KEYS.issue(KEY).mac).decode("ascii"),
        },
        "scopes": sorted(ACCOUNT_DELETION_SCOPES),
        "requestedAtUtc": NOW.isoformat(),
        "identityDeleted": False,
        "serverExportCompleted": False,
        "recoveryExpiresAtUtc": invalid_expiry,
        "receipt": None,
    }

    with pytest.raises(ValueError, match="recoveryExpiresAtUtc"):
        FirestoreAccountDeletionOperationStore(
            documents, RECOVERY_KEYS
        ).get("firebase-user")


def test_deleter_targets_only_uid_owned_namespaces_and_auth_last() -> None:
    calls: list[tuple[str, str]] = []
    owned = {
        ("categories", "uid"): [
            FirebaseOwnedDeleteTarget(
                path="categories/category-a",
                update_time=NOW,
                owner_field="uid",
                owner_value="firebase-user",
            )
        ],
        ("purchased_items", "user_id"): [
            FirebaseOwnedDeleteTarget(
                path="purchased_items/purchase-a",
                update_time=NOW,
                owner_field="user_id",
                owner_value="firebase-user",
            )
        ],
        ("vocabulary", "uid"): [
            FirebaseOwnedDeleteTarget(
                path="vocabulary/private-a",
                update_time=NOW,
                owner_field="uid",
                owner_value="firebase-user",
            )
        ],
    }
    deleter = FirebaseOwnerIsolatedAccountDeleter(
        delete_tree=lambda target, operation_id: calls.append(
            ("tree", target.path)
        ),
        delete_document=lambda target: calls.append(
            ("document", target.path)
        ),
        read_owned_path=lambda path: FirebaseOwnedDeleteTarget(
            path=path, update_time=NOW
        ),
        find_owned_paths=lambda collection, field, uid: owned.get(
            (collection, field), []
        ),
        delete_user=lambda uid: calls.append(("auth", uid)),
    )

    deleter.delete_owned_data(
        owner_id="owner-a",
        firebase_uid="firebase-user",
        scopes=ACCOUNT_DELETION_SCOPES,
        operation_id="operation-1",
    )
    deleter.delete_auth_identity(
        firebase_uid="firebase-user", operation_id="operation-1"
    )

    assert calls == [
        ("tree", "field_users/firebase-user"),
        ("document", "users/firebase-user"),
        ("document", "state/firebase-user"),
        ("tree", "categories/category-a"),
        ("document", "purchased_items/purchase-a"),
        ("document", "vocabulary/private-a"),
        ("auth", "firebase-user"),
    ]
    assert all("products/" not in path for _, path in calls)


def test_deleter_stops_when_a_queried_owner_document_loses_its_race() -> None:
    calls: list[tuple[str, str]] = []
    stale = FirebaseOwnedDeleteTarget(
        path="categories/category-a",
        update_time=NOW,
        owner_field="uid",
        owner_value="firebase-user",
    )

    def conditional_tree(
        target: FirebaseOwnedDeleteTarget, operation_id: str
    ) -> None:
        if target.path == stale.path:
            calls.append(("conditional", target.path))
            raise RuntimeError("synthetic update-time precondition failed")
        calls.append(("tree", target.path))

    deleter = FirebaseOwnerIsolatedAccountDeleter(
        delete_tree=conditional_tree,
        delete_document=lambda target: calls.append(
            ("document", target.path)
        ),
        read_owned_path=lambda path: FirebaseOwnedDeleteTarget(
            path=path, update_time=NOW
        ),
        find_owned_paths=lambda collection, *_: (
            [stale] if collection == "categories" else []
        ),
        delete_user=lambda uid: calls.append(("auth", uid)),
    )

    with pytest.raises(RuntimeError, match="precondition failed"):
        deleter.delete_owned_data(
            owner_id="owner-a",
            firebase_uid="firebase-user",
            scopes=ACCOUNT_DELETION_SCOPES,
            operation_id="operation-1",
        )

    assert calls[-1] == ("conditional", stale.path)
    assert ("auth", "firebase-user") not in calls


def test_production_deleter_uses_update_time_before_recursive_delete(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[tuple[object, ...]] = []

    class _Snapshot:
        def __init__(self, reference, update_time):  # type: ignore[no-untyped-def]
            self.reference = reference
            self.update_time = update_time
            self.exists = True

        def to_dict(self):  # type: ignore[no-untyped-def]
            return {"uid": "firebase-user"}

    class _Reference:
        def __init__(self, path: str) -> None:
            self.path = path

        def get(self, transaction=None):  # type: ignore[no-untyped-def]
            if transaction is not None and self.path == "categories/category-a":
                return _Snapshot(self, NOW + timedelta(seconds=1))
            return SimpleNamespace(exists=False)

        def delete(self, *, option):  # type: ignore[no-untyped-def]
            calls.append(("delete", self.path, type(option).__name__))

    class _Query:
        def __init__(self, collection: str) -> None:
            self.collection = collection

        def stream(self):  # type: ignore[no-untyped-def]
            if self.collection != "categories":
                return []
            return [
                _Snapshot(_Reference("categories/category-a"), NOW)
            ]

    class _Collection:
        def __init__(self, name: str) -> None:
            self.name = name

        def document(self, document: str) -> _Reference:
            return _Reference(f"{self.name}/{document}")

        def where(self, *, filter):  # type: ignore[no-untyped-def]
            assert filter is not None
            return _Query(self.name)

    class _Transaction:
        def update(self, reference, data, *, option):  # type: ignore[no-untyped-def]
            calls.append(
                ("claim", reference.path, data, type(option).__name__)
            )

    class _Client:
        def collection(self, name: str) -> _Collection:
            return _Collection(name)

        def transaction(self) -> _Transaction:
            return _Transaction()

        def recursive_delete(self, reference):  # type: ignore[no-untyped-def]
            calls.append(("recursive", reference.path))

    monkeypatch.setattr(firebase_adapter.firebase_firestore, "client", _Client)
    monkeypatch.setattr(
        firebase_adapter.google_firestore,
        "transactional",
        lambda function: lambda transaction: function(transaction),
    )
    monkeypatch.setattr(
        firebase_adapter.firebase_auth, "delete_user", lambda uid: None
    )

    deleter = FirebaseOwnerIsolatedAccountDeleter.production()
    with pytest.raises(RuntimeError, match="update-time precondition failed"):
        deleter.delete_owned_data(
            owner_id="owner-a",
            firebase_uid="firebase-user",
            scopes=ACCOUNT_DELETION_SCOPES,
            operation_id="operation-1",
        )

    assert ("recursive", "categories/category-a") not in calls
    assert not any(call[0] == "claim" for call in calls)


def test_export_and_delete_share_the_exact_owner_data_inventory() -> None:
    assert [
        (source.collection, source.owner_field, source.recursive)
        for source in FIREBASE_ACCOUNT_DATA_SOURCES
    ] == [
        ("field_users", None, True),
        ("users", None, False),
        ("state", None, False),
        ("categories", "uid", True),
        ("purchased_items", "user_id", False),
        ("vocabulary", "uid", False),
    ]


def test_snapshot_reader_uses_one_read_time_and_allowlists_auth_metadata() -> None:
    calls: list[tuple[object, ...]] = []
    read_time = NOW - timedelta(seconds=1)
    documents = {
        "field_users/firebase-user": [
            FirebaseExportDocument(
                path="field_users/firebase-user/words/word-1",
                data={"word": "safe"},
            )
        ],
        "users/firebase-user": [
            FirebaseExportDocument(
                path="users/firebase-user", data={"email": "a@example.test"}
            )
        ],
        "state/firebase-user": [],
        "categories/category-a": [
            FirebaseExportDocument(
                path="categories/category-a", data={"uid": "firebase-user"}
            ),
            FirebaseExportDocument(
                path="categories/category-a/words/word-a",
                data={"word": "cat"},
            ),
        ],
        "purchased_items/purchase-a": [
            FirebaseExportDocument(
                path="purchased_items/purchase-a",
                data={"user_id": "firebase-user"},
            )
        ],
        "vocabulary/private-a": [
            FirebaseExportDocument(
                path="vocabulary/private-a", data={"uid": "firebase-user"}
            )
        ],
    }

    def read_path(path: str, recursive: bool, at: datetime):
        calls.append(("read", path, recursive, at))
        return documents[path]

    def find(collection: str, field: str, uid: str, at: datetime):
        calls.append(("find", collection, field, uid, at))
        return {
            "categories": ["categories/category-a"],
            "purchased_items": ["purchased_items/purchase-a"],
            "vocabulary": ["vocabulary/private-a"],
        }[collection]

    provider = SimpleNamespace(
        provider_id="google.com",
        uid="provider-uid",
        email="a@example.test",
        display_name="Learner",
        phone_number=None,
        photo_url=None,
        refresh_token="must-not-export",
    )
    auth_user = SimpleNamespace(
        uid="firebase-user",
        email="a@example.test",
        email_verified=True,
        display_name="Learner",
        phone_number=None,
        photo_url=None,
        disabled=False,
        tenant_id=None,
        provider_data=[provider],
        user_metadata=SimpleNamespace(
            creation_timestamp=1_700_000_000_000,
            last_sign_in_timestamp=1_700_000_100_000,
        ),
        custom_claims={"admin": True},
        password_hash=b"must-not-export",
        password_salt=b"must-not-export",
        tokens_valid_after_timestamp=NOW,
    )
    reader = FirebaseOwnedAccountSnapshotReader(
        read_path=read_path,
        find_owned_paths=find,
        read_auth_user=lambda uid: auth_user,
        now_utc=lambda: read_time,
        maximum_documents=20,
    )

    snapshot = reader.read_complete_snapshot("firebase-user")

    assert [item["path"] for item in snapshot["firestoreDocuments"]] == sorted(
        document.path for rows in documents.values() for document in rows
    )
    assert {call[-1] for call in calls} == {read_time}
    encoded_auth = snapshot["firebaseAuth"]
    assert encoded_auth["uid"] == "firebase-user"
    assert encoded_auth["providerData"] == [
        {
            "displayName": "Learner",
            "email": "a@example.test",
            "phoneNumber": None,
            "photoUrl": None,
            "providerId": "google.com",
            "uid": "provider-uid",
        }
    ]
    assert "customClaims" not in encoded_auth
    assert "passwordHash" not in encoded_auth
    assert "tokensValidAfterTimestamp" not in encoded_auth


def test_production_snapshot_reader_anchors_all_firestore_reads_to_server_time(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[tuple[str, object, object]] = []

    class _Snapshot:
        def __init__(
            self,
            reference,  # type: ignore[no-untyped-def]
            *,
            read_time: datetime,
        ) -> None:
            self.reference = reference
            self.read_time = read_time
            self.exists = reference.path == "users/firebase-user"

        def to_dict(self):  # type: ignore[no-untyped-def]
            return {"displayName": "Learner"}

    class _Reference:
        def __init__(self, path: str) -> None:
            self.path = path

        def get(self, *, read_time=None):  # type: ignore[no-untyped-def]
            calls.append(("get", self.path, read_time))
            return _Snapshot(self, read_time=NOW)

        def collections(self, *, read_time):  # type: ignore[no-untyped-def]
            calls.append(("collections", self.path, read_time))
            return []

    class _Query:
        def __init__(self, collection: str) -> None:
            self.collection = collection

        def stream(self, *, read_time):  # type: ignore[no-untyped-def]
            calls.append(("query", self.collection, read_time))
            return []

    class _Collection:
        def __init__(self, collection: str) -> None:
            self.collection = collection

        def where(self, *, filter):  # type: ignore[no-untyped-def]
            assert filter is not None
            return _Query(self.collection)

    class _Client:
        def document(self, path: str) -> _Reference:
            return _Reference(path)

        def collection(self, name: str) -> _Collection:
            return _Collection(name)

    monkeypatch.setattr(firebase_adapter.firebase_firestore, "client", _Client)
    monkeypatch.setattr(
        firebase_adapter.firebase_auth,
        "get_user",
        lambda uid: _auth_user(uid),
    )

    snapshot = FirebaseOwnedAccountSnapshotReader.production().read_complete_snapshot(
        "firebase-user"
    )

    assert snapshot["readAtUtc"] == "2026-10-26T09:00:00Z"
    assert calls[0] == ("get", "users/firebase-user", None)
    assert all(call[2] == NOW for call in calls[1:])


def test_snapshot_reader_rejects_a_query_path_outside_its_collection() -> None:
    reader = FirebaseOwnedAccountSnapshotReader(
        read_path=lambda *_: [],
        find_owned_paths=lambda collection, *_: (
            ["users/victim"] if collection == "categories" else []
        ),
        read_auth_user=lambda uid: SimpleNamespace(
            uid=uid,
            email=None,
            email_verified=False,
            display_name=None,
            phone_number=None,
            photo_url=None,
            disabled=False,
            tenant_id=None,
            provider_data=[],
            user_metadata=None,
        ),
        now_utc=lambda: NOW,
    )

    with pytest.raises(ValueError, match="unexpected path"):
        reader.read_complete_snapshot("firebase-user")


def test_snapshot_reader_revalidates_the_stored_owner_field() -> None:
    reader = FirebaseOwnedAccountSnapshotReader(
        read_path=lambda path, *_: [
            FirebaseExportDocument(path=path, data={"uid": "another-user"})
        ],
        find_owned_paths=lambda collection, *_: (
            ["categories/category-a"] if collection == "categories" else []
        ),
        read_auth_user=lambda uid: _auth_user(uid),
        now_utc=lambda: NOW,
    )

    with pytest.raises(ValueError, match="owner field"):
        reader.read_complete_snapshot("firebase-user")


def test_snapshot_reader_encodes_supported_firestore_types_losslessly() -> None:
    timestamp = NOW - timedelta(seconds=5)
    reader = FirebaseOwnedAccountSnapshotReader(
        read_path=lambda path, *_: (
            [
                FirebaseExportDocument(
                    path=path,
                    data={
                        "blob": b"\x00\xff",
                        "double": 1.25,
                        "geo": GeoPoint(13.7563, 100.5018),
                        "timestamp": timestamp,
                    },
                )
            ]
            if path == "users/firebase-user"
            else []
        ),
        find_owned_paths=lambda *_: [],
        read_auth_user=lambda uid: _auth_user(uid),
        now_utc=lambda: NOW,
    )

    snapshot = reader.read_complete_snapshot("firebase-user")
    data = snapshot["firestoreDocuments"][0]["data"]
    assert data == {
        "blob": {
            "$firestoreType": "bytes",
            "base64": base64.b64encode(b"\x00\xff").decode("ascii"),
        },
        "double": 1.25,
        "geo": {
            "$firestoreType": "geoPoint",
            "latitude": 13.7563,
            "longitude": 100.5018,
        },
        "timestamp": {
            "$firestoreType": "timestamp",
            "value": timestamp.isoformat().replace("+00:00", "Z"),
        },
    }


@pytest.mark.parametrize(
    "value",
    [
        float("nan"),
        float("inf"),
        datetime(2026, 10, 26, 9, 0),
        {1: "non-string-key"},
        object(),
    ],
)
def test_snapshot_reader_rejects_unsafe_firestore_values(value: object) -> None:
    reader = FirebaseOwnedAccountSnapshotReader(
        read_path=lambda path, *_: (
            [FirebaseExportDocument(path=path, data={"unsafe": value})]
            if path == "users/firebase-user"
            else []
        ),
        find_owned_paths=lambda *_: [],
        read_auth_user=lambda uid: _auth_user(uid),
        now_utc=lambda: NOW,
    )

    with pytest.raises(ValueError, match="Firestore"):
        reader.read_complete_snapshot("firebase-user")


def test_snapshot_reader_enforces_document_and_byte_limits() -> None:
    documents = [
        FirebaseExportDocument(
            path="field_users/firebase-user/words/word-a",
            data={"word": "a" * 128},
        ),
        FirebaseExportDocument(
            path="field_users/firebase-user/words/word-b",
            data={"word": "b"},
        ),
    ]
    common = {
        "read_path": lambda path, *_: (
            documents if path == "field_users/firebase-user" else []
        ),
        "find_owned_paths": lambda *_: [],
        "read_auth_user": lambda uid: _auth_user(uid),
        "now_utc": lambda: NOW,
    }

    with pytest.raises(ValueError, match="document limit"):
        FirebaseOwnedAccountSnapshotReader(
            **common, maximum_documents=1, maximum_bytes=1_000
        ).read_complete_snapshot("firebase-user")
    with pytest.raises(ValueError, match="byte limit"):
        FirebaseOwnedAccountSnapshotReader(
            **common, maximum_documents=10, maximum_bytes=64
        ).read_complete_snapshot("firebase-user")


def test_auth_deletion_is_idempotent_for_an_already_missing_user() -> None:
    class _MissingUser(Exception):
        pass

    def missing(_: str) -> None:
        raise _MissingUser

    deleter = FirebaseOwnerIsolatedAccountDeleter(
        delete_tree=lambda *_: None,
        delete_document=lambda _: None,
        read_owned_path=lambda _: None,
        find_owned_paths=lambda *_: [],
        delete_user=missing,
        user_not_found_errors=(_MissingUser,),
    )

    deleter.delete_auth_identity(
        firebase_uid="firebase-user", operation_id="operation-1"
    )


def _auth_user(uid: str) -> SimpleNamespace:
    return SimpleNamespace(
        uid=uid,
        email=None,
        email_verified=False,
        display_name=None,
        phone_number=None,
        photo_url=None,
        disabled=False,
        tenant_id=None,
        provider_data=[],
        user_metadata=None,
    )


def test_production_service_is_constructed_only_when_explicitly_enabled() -> None:
    calls: list[str] = []
    assert (
        build_firebase_account_deletion_service(
            enabled=False,
            store_factory=lambda: calls.append("store"),
            deleter_factory=lambda: calls.append("deleter"),
        )
        is None
    )
    assert calls == []

    assert (
        build_firebase_account_deletion_service(
            enabled=True,
            store_factory=lambda: calls.append("store"),
            deleter_factory=lambda: calls.append("deleter"),
        )
        is None
    )
    assert calls == []

    class _ExportAuthority:
        def ensure_complete_export(self, **kwargs) -> None:  # type: ignore[no-untyped-def]
            pass

    service = build_firebase_account_deletion_service(
        enabled=True,
        server_export_authority=_ExportAuthority(),
        recovery_key_authority=RECOVERY_KEYS,
        recovery_retention=timedelta(days=7),
        store_factory=lambda recovery_keys: (
            calls.append("store"),
            FirestoreAccountDeletionOperationStore(
                _Documents(), recovery_keys
            ),
        )[1],
        deleter_factory=lambda: (
            calls.append("deleter"),
            FirebaseOwnerIsolatedAccountDeleter(
                delete_tree=lambda *_: None,
                delete_document=lambda _: None,
                read_owned_path=lambda _: None,
                find_owned_paths=lambda *_: [],
                delete_user=lambda _: None,
            ),
        )[1],
    )

    assert service is not None
    assert calls == ["store", "deleter"]
