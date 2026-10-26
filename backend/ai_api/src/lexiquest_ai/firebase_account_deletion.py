"""Firebase Admin adapters for the privileged account-deletion contract."""

from __future__ import annotations

import base64
import hashlib
import json
import math
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from typing import Protocol, TypeVar

from firebase_admin import auth as firebase_auth
from firebase_admin import firestore as firebase_firestore
from google.cloud import firestore as google_firestore
from google.cloud.firestore_v1 import (
    DocumentReference,
    GeoPoint,
    LastUpdateOption,
)
from google.cloud.firestore_v1.base_query import FieldFilter

from lexiquest_ai.account_deletion import (
    ACCOUNT_DELETION_SCOPES,
    AccountDeletionRecoveryKeyAuthority,
    AccountDeletionOperation,
    AccountDeletionOperationStore,
    AccountDeletionReceipt,
    AccountDeletionService,
    OwnerIsolatedAccountDeleter,
    RecoveryKeyProof,
    ServerCompleteAccountExportAuthority,
)

T = TypeVar("T")
OperationUpdate = Callable[
    [dict[str, object] | None], tuple[dict[str, object] | None, T]
]


@dataclass(frozen=True, slots=True)
class FirebaseOwnedDataSource:
    collection: str
    owner_field: str | None
    recursive: bool


FIREBASE_ACCOUNT_DATA_SOURCES = (
    FirebaseOwnedDataSource("field_users", None, True),
    FirebaseOwnedDataSource("users", None, False),
    FirebaseOwnedDataSource("state", None, False),
    FirebaseOwnedDataSource("categories", "uid", True),
    FirebaseOwnedDataSource("purchased_items", "user_id", False),
    FirebaseOwnedDataSource("vocabulary", "uid", False),
)

_OPERATION_COMMON_KEYS = frozenset(
    {
        "operationId",
        "ownerId",
        "firebaseUid",
        "scopes",
        "requestedAtUtc",
        "identityDeleted",
        "serverExportCompleted",
        "recoveryExpiresAtUtc",
        "receipt",
    }
)
_RECOVERY_VERIFIER_KEYS = frozenset(
    {"algorithm", "kmsKeyVersion", "mac"}
)
_RECEIPT_KEYS = frozenset(
    {"receiptId", "ownerId", "firebaseUid", "completedAtUtc"}
)


@dataclass(frozen=True, slots=True)
class FirebaseExportDocument:
    path: str
    data: Mapping[str, object]


@dataclass(frozen=True, slots=True)
class FirebaseOwnedDeleteTarget:
    path: str
    update_time: datetime | None
    owner_field: str | None = None
    owner_value: str | None = None


ReadOwnedPath = Callable[[str, bool, datetime], Iterable[FirebaseExportDocument]]
FindOwnedPathsAt = Callable[[str, str, str, datetime], Iterable[str]]
ReadAuthUser = Callable[[str], object]
ReadTimeUtc = Callable[[str], datetime]


class FirebaseOwnedAccountSnapshotReader:
    def __init__(
        self,
        *,
        read_path: ReadOwnedPath,
        find_owned_paths: FindOwnedPathsAt,
        read_auth_user: ReadAuthUser,
        now_utc: Callable[[], datetime] = lambda: datetime.now(UTC),
        read_time_utc: ReadTimeUtc | None = None,
        maximum_documents: int = 10_000,
        maximum_bytes: int = 50 * 1024 * 1024,
    ) -> None:
        if maximum_documents <= 0 or maximum_bytes <= 0:
            raise ValueError("account export limits must be positive")
        self._read_path = read_path
        self._find_owned_paths = find_owned_paths
        self._read_auth_user = read_auth_user
        self._now_utc = now_utc
        self._read_time_utc = read_time_utc
        self._maximum_documents = maximum_documents
        self._maximum_bytes = maximum_bytes

    @classmethod
    def production(
        cls,
        *,
        maximum_documents: int = 10_000,
        maximum_bytes: int = 50 * 1024 * 1024,
    ) -> FirebaseOwnedAccountSnapshotReader:
        client = firebase_firestore.client()

        def read_path(
            path: str, recursive: bool, read_time: datetime
        ) -> Iterable[FirebaseExportDocument]:
            def collect(
                reference, snapshot=None  # type: ignore[no-untyped-def]
            ) -> Iterable[FirebaseExportDocument]:
                current = snapshot or reference.get(read_time=read_time)
                if current.exists:
                    yield FirebaseExportDocument(
                        path=current.reference.path,
                        data=current.to_dict() or {},
                    )
                if not recursive:
                    return
                for collection in reference.collections(read_time=read_time):
                    for child in collection.stream(read_time=read_time):
                        yield from collect(child.reference, child)

            return collect(client.document(path))

        def find_owned_paths(
            collection: str,
            field: str,
            uid: str,
            read_time: datetime,
        ) -> Iterable[str]:
            query = client.collection(collection).where(
                filter=FieldFilter(field, "==", uid)
            )
            return (
                snapshot.reference.path
                for snapshot in query.stream(read_time=read_time)
            )

        return cls(
            read_path=read_path,
            find_owned_paths=find_owned_paths,
            read_auth_user=firebase_auth.get_user,
            read_time_utc=lambda uid: client.document(
                f"users/{_segment(uid, 'firebase_uid')}"
            ).get().read_time,
            maximum_documents=maximum_documents,
            maximum_bytes=maximum_bytes,
        )

    def read_complete_snapshot(self, firebase_uid: str) -> dict[str, object]:
        uid = _segment(firebase_uid, "firebase_uid")
        read_time = (
            self._read_time_utc(uid)
            if self._read_time_utc is not None
            else self._now_utc()
        )
        if read_time.tzinfo is None or read_time.utcoffset() != timedelta(0):
            raise ValueError("account export read time must be UTC")
        documents: dict[str, dict[str, object]] = {}
        bytes_read = 0
        for source in FIREBASE_ACCOUNT_DATA_SOURCES:
            if source.owner_field is None:
                paths = [f"{source.collection}/{uid}"]
            else:
                paths = self._find_owned_paths(
                    source.collection,
                    source.owner_field,
                    uid,
                    read_time,
                )
            for path in paths:
                root = f"{source.collection}/"
                if not path.startswith(root) or path.count("/") != 1:
                    raise ValueError("owner query returned an unexpected path")
                for document in self._read_path(path, source.recursive, read_time):
                    if not (
                        document.path == path
                        or (
                            source.recursive
                            and document.path.startswith(f"{path}/")
                        )
                    ):
                        raise ValueError("account export returned an unexpected path")
                    if document.path in documents:
                        raise ValueError("account export returned a duplicate document")
                    if (
                        source.owner_field is not None
                        and document.path == path
                        and document.data.get(source.owner_field) != uid
                    ):
                        raise ValueError("account export owner field does not match")
                    encoded = _json_safe_map(document.data)
                    bytes_read += len(_canonical_json_bytes(encoded))
                    if bytes_read > self._maximum_bytes:
                        raise ValueError("account export exceeds the byte limit")
                    documents[document.path] = encoded
                    if len(documents) > self._maximum_documents:
                        raise ValueError("account export exceeds the document limit")
        snapshot = {
            "readAtUtc": read_time.isoformat().replace("+00:00", "Z"),
            "firebaseAuth": _auth_user_to_export(
                self._read_auth_user(uid), expected_uid=uid
            ),
            "firestoreDocuments": [
                {"path": path, "data": documents[path]}
                for path in sorted(documents)
            ],
        }
        if len(_canonical_json_bytes(snapshot)) > self._maximum_bytes:
            raise ValueError("account export exceeds the byte limit")
        return snapshot


class AtomicOperationDocuments(Protocol):
    def transact(self, firebase_uid: str, update: OperationUpdate[T]) -> T: ...


class FirestoreOperationDocuments:
    def __init__(self, client=None) -> None:  # type: ignore[no-untyped-def]
        self._client = client or firebase_firestore.client()

    def transact(self, firebase_uid: str, update: OperationUpdate[T]) -> T:
        ref = self._client.collection("account_deletion_operations").document(
            _segment(firebase_uid, "firebase_uid")
        )
        transaction = self._client.transaction()

        @google_firestore.transactional
        def run(current_transaction):  # type: ignore[no-untyped-def]
            snapshot = ref.get(transaction=current_transaction)
            current = snapshot.to_dict() if snapshot.exists else None
            value, result = update(current)
            if value is not None:
                current_transaction.set(ref, value)
            return result

        return run(transaction)


class FirestoreAccountDeletionOperationStore(AccountDeletionOperationStore):
    def __init__(
        self,
        documents: AtomicOperationDocuments,
        recovery_key_authority: AccountDeletionRecoveryKeyAuthority,
    ) -> None:
        self._documents = documents
        self._recovery_key_authority = recovery_key_authority

    @classmethod
    def production(
        cls, recovery_key_authority: AccountDeletionRecoveryKeyAuthority
    ) -> FirestoreAccountDeletionOperationStore:
        return cls(FirestoreOperationDocuments(), recovery_key_authority)

    def claim(self, operation: AccountDeletionOperation) -> AccountDeletionOperation:
        def update(current):  # type: ignore[no-untyped-def]
            if current is not None:
                canonical, existing, _ = _canonical_operation_document(
                    current, self._recovery_key_authority
                )
                return canonical, existing
            encoded = _operation_to_document(operation)
            return encoded, operation

        return self._documents.transact(operation.firebase_uid, update)

    def complete(
        self,
        operation: AccountDeletionOperation,
        receipt: AccountDeletionReceipt,
    ) -> AccountDeletionReceipt:
        def update(current):  # type: ignore[no-untyped-def]
            canonical, existing = _required_operation(
                current, operation, self._recovery_key_authority
            )
            if existing.receipt is not None:
                return canonical, existing.receipt
            completed = replace(existing, receipt=receipt)
            return _operation_to_document(completed), receipt

        return self._documents.transact(operation.firebase_uid, update)

    def get(self, firebase_uid: str) -> AccountDeletionOperation | None:
        def read(current):  # type: ignore[no-untyped-def]
            if current is None:
                return None, None
            canonical, operation, migrated = _canonical_operation_document(
                current, self._recovery_key_authority
            )
            return (canonical if migrated else None), operation

        return self._documents.transact(firebase_uid, read)

    def mark_server_export_completed(
        self, operation: AccountDeletionOperation
    ) -> AccountDeletionOperation:
        def update(current):  # type: ignore[no-untyped-def]
            canonical, existing = _required_operation(
                current, operation, self._recovery_key_authority
            )
            if existing.server_export_completed:
                return canonical, existing
            completed = replace(existing, server_export_completed=True)
            encoded = _operation_to_document(completed)
            return encoded, completed

        return self._documents.transact(operation.firebase_uid, update)

    def mark_identity_deleted(
        self, operation: AccountDeletionOperation
    ) -> AccountDeletionOperation:
        def update(current):  # type: ignore[no-untyped-def]
            canonical, existing = _required_operation(
                current, operation, self._recovery_key_authority
            )
            if existing.identity_deleted:
                return canonical, existing
            completed = replace(existing, identity_deleted=True)
            encoded = _operation_to_document(completed)
            return encoded, completed

        return self._documents.transact(operation.firebase_uid, update)


DeleteTree = Callable[[FirebaseOwnedDeleteTarget, str], None]
DeleteDocument = Callable[[FirebaseOwnedDeleteTarget], None]
ReadOwnedPath = Callable[[str], FirebaseOwnedDeleteTarget | None]
FindOwnedPaths = Callable[
    [str, str, str], Iterable[FirebaseOwnedDeleteTarget]
]
DeleteUser = Callable[[str], None]


class FirebaseOwnerIsolatedAccountDeleter(OwnerIsolatedAccountDeleter):
    def __init__(
        self,
        *,
        delete_tree: DeleteTree,
        delete_document: DeleteDocument,
        read_owned_path: ReadOwnedPath,
        find_owned_paths: FindOwnedPaths,
        delete_user: DeleteUser,
        user_not_found_errors: tuple[type[BaseException], ...] = (
            firebase_auth.UserNotFoundError,
        ),
    ) -> None:
        self._delete_tree = delete_tree
        self._delete_document = delete_document
        self._read_owned_path = read_owned_path
        self._find_owned_paths = find_owned_paths
        self._delete_user = delete_user
        self._user_not_found_errors = user_not_found_errors

    @classmethod
    def production(cls) -> FirebaseOwnerIsolatedAccountDeleter:
        client = firebase_firestore.client()

        def ref(path: str):  # type: ignore[no-untyped-def]
            collection, document = path.split("/", 1)
            return client.collection(collection).document(document)

        def target(snapshot) -> FirebaseOwnedDeleteTarget:  # type: ignore[no-untyped-def]
            if snapshot.update_time is None:
                raise ValueError("owner document update time is unavailable")
            return FirebaseOwnedDeleteTarget(
                path=snapshot.reference.path,
                update_time=snapshot.update_time,
            )

        def read(path: str) -> FirebaseOwnedDeleteTarget | None:
            snapshot = ref(path).get()
            return target(snapshot) if snapshot.exists else None

        def find(
            collection: str, field: str, uid: str
        ) -> Iterable[FirebaseOwnedDeleteTarget]:
            query = client.collection(collection).where(
                filter=FieldFilter(field, "==", uid)
            )
            return [
                replace(
                    target(snapshot),
                    owner_field=field,
                    owner_value=uid,
                )
                for snapshot in query.stream()
            ]

        def delete_document(target: FirebaseOwnedDeleteTarget) -> None:
            if target.update_time is None:
                raise ValueError("conditional delete requires an update time")
            ref(target.path).delete(
                option=LastUpdateOption(target.update_time)
            )

        def delete_tree(
            target: FirebaseOwnedDeleteTarget, operation_id: str
        ) -> None:
            reference = ref(target.path)
            if target.update_time is not None:
                transaction = client.transaction()

                @google_firestore.transactional
                def claim(current_transaction):  # type: ignore[no-untyped-def]
                    snapshot = reference.get(transaction=current_transaction)
                    data = snapshot.to_dict() if snapshot.exists else None
                    if (
                        not snapshot.exists
                        or snapshot.update_time != target.update_time
                        or (
                            target.owner_field is not None
                            and (
                                not isinstance(data, dict)
                                or data.get(target.owner_field)
                                != target.owner_value
                            )
                        )
                    ):
                        raise RuntimeError(
                            "owner delete update-time precondition failed"
                        )
                    current_transaction.update(
                        reference,
                        {"_accountDeletionOperationId": operation_id},
                        option=LastUpdateOption(target.update_time),
                    )

                claim(transaction)
            client.recursive_delete(reference)

        return cls(
            delete_tree=delete_tree,
            delete_document=delete_document,
            read_owned_path=read,
            find_owned_paths=find,
            delete_user=firebase_auth.delete_user,
        )

    def delete_owned_data(
        self,
        *,
        owner_id: str,
        firebase_uid: str,
        scopes: frozenset[str],
        operation_id: str,
    ) -> None:
        if not owner_id or scopes != ACCOUNT_DELETION_SCOPES:
            raise ValueError("account deletion scope is invalid")
        uid = _segment(firebase_uid, "firebase_uid")
        _segment(operation_id, "operation_id")
        for source in FIREBASE_ACCOUNT_DATA_SOURCES:
            if source.owner_field is None:
                path = f"{source.collection}/{uid}"
                existing = self._read_owned_path(path)
                targets = (
                    [
                        FirebaseOwnedDeleteTarget(
                            path=path, update_time=None
                        )
                    ]
                    if existing is None and source.recursive
                    else ([] if existing is None else [existing])
                )
            else:
                targets = self._find_owned_paths(
                    source.collection, source.owner_field, uid
                )
            for target in targets:
                path = target.path
                if (
                    not path.startswith(f"{source.collection}/")
                    or path.count("/") != 1
                    or (
                        source.owner_field is not None
                        and (
                            target.owner_field != source.owner_field
                            or target.owner_value != uid
                        )
                    )
                    or (
                        target.update_time is not None
                        and (
                            target.update_time.tzinfo is None
                            or target.update_time.utcoffset()
                            != timedelta(0)
                        )
                    )
                ):
                    raise ValueError("owner query returned an unexpected path")
                if source.recursive:
                    self._delete_tree(target, operation_id)
                else:
                    self._delete_document(target)

    def delete_auth_identity(
        self, *, firebase_uid: str, operation_id: str
    ) -> None:
        uid = _segment(firebase_uid, "firebase_uid")
        _segment(operation_id, "operation_id")
        try:
            self._delete_user(uid)
        except self._user_not_found_errors:
            return


def _required_operation(
    current: dict[str, object] | None,
    expected: AccountDeletionOperation,
    recovery_key_authority: AccountDeletionRecoveryKeyAuthority,
) -> tuple[dict[str, object], AccountDeletionOperation]:
    if current is None:
        raise RuntimeError("account deletion operation is missing")
    canonical, operation, _ = _canonical_operation_document(
        current, recovery_key_authority
    )
    if operation.operation_id != expected.operation_id:
        raise RuntimeError("account deletion operation changed")
    return canonical, operation


def _operation_to_document(
    operation: AccountDeletionOperation,
) -> dict[str, object]:
    document: dict[str, object] = {
        "operationId": operation.operation_id,
        "ownerId": operation.owner_id,
        "firebaseUid": operation.firebase_uid,
        "recoveryKeyVerifier": {
            "algorithm": operation.recovery_key_proof.algorithm,
            "kmsKeyVersion": operation.recovery_key_proof.key_version,
            "mac": base64.b64encode(operation.recovery_key_proof.mac).decode(
                "ascii"
            ),
        },
        "scopes": sorted(operation.scopes),
        "requestedAtUtc": operation.requested_at_utc.isoformat(),
        "identityDeleted": operation.identity_deleted,
        "serverExportCompleted": operation.server_export_completed,
        "recoveryExpiresAtUtc": (
            None
            if operation.recovery_expires_at_utc is None
            else _require_utc_datetime(
                operation.recovery_expires_at_utc,
                "recoveryExpiresAtUtc",
            )
        ),
        "receipt": None
        if operation.receipt is None
        else {
            "receiptId": operation.receipt.receipt_id,
            "ownerId": operation.receipt.owner_id,
            "firebaseUid": operation.receipt.firebase_uid,
            "completedAtUtc": operation.receipt.completed_at_utc.isoformat(),
        },
    }
    # The TTL field must not exist while the tombstone is active. Otherwise a
    # delayed deletion could expire the fence and allow owner writes again.
    if operation.identity_deleted:
        if operation.recovery_expires_at_utc is None:
            raise ValueError("completed deletion is missing recovery expiry")
        document["purgeAtUtc"] = _require_utc_datetime(
            operation.recovery_expires_at_utc, "purgeAtUtc"
        )
    return document


def _operation_from_document(document: dict[str, object]) -> AccountDeletionOperation:
    verifier = document.get("recoveryKeyVerifier")
    if (
        not isinstance(verifier, dict)
        or set(verifier) != _RECOVERY_VERIFIER_KEYS
        or not isinstance(verifier.get("algorithm"), str)
        or not isinstance(verifier.get("kmsKeyVersion"), str)
        or not isinstance(verifier.get("mac"), str)
    ):
        raise ValueError("recoveryKeyVerifier is invalid")
    try:
        algorithm = verifier["algorithm"]
        key_version = verifier["kmsKeyVersion"]
        mac = base64.b64decode(verifier["mac"], validate=True)
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("recoveryKeyVerifier is invalid") from error
    if (
        algorithm != "HMAC-SHA256"
        or not key_version
        or len(key_version) > 512
        or len(mac) != hashlib.sha256().digest_size
    ):
        raise ValueError("recoveryKeyVerifier is invalid")
    operation_id = _strict_segment(document.get("operationId"), "operationId")
    owner_id = _strict_segment(document.get("ownerId"), "ownerId")
    firebase_uid = _strict_segment(document.get("firebaseUid"), "firebaseUid")
    scopes_value = document.get("scopes")
    if (
        not isinstance(scopes_value, list)
        or not all(isinstance(scope, str) and scope for scope in scopes_value)
        or len(scopes_value) != len(set(scopes_value))
    ):
        raise ValueError("account deletion scopes are invalid")
    identity_deleted = document.get("identityDeleted")
    server_export_completed = document.get("serverExportCompleted")
    if type(identity_deleted) is not bool or type(server_export_completed) is not bool:
        raise ValueError("account deletion state is invalid")

    receipt_document = document.get("receipt")
    receipt = None
    if receipt_document is not None:
        if (
            not isinstance(receipt_document, dict)
            or set(receipt_document) != _RECEIPT_KEYS
        ):
            raise ValueError("account deletion receipt is invalid")
        receipt = AccountDeletionReceipt(
            receipt_id=_strict_segment(
                receipt_document.get("receiptId"), "receipt.receiptId"
            ),
            owner_id=_strict_segment(
                receipt_document.get("ownerId"), "receipt.ownerId"
            ),
            firebase_uid=_strict_segment(
                receipt_document.get("firebaseUid"), "receipt.firebaseUid"
            ),
            completed_at_utc=_decode_utc_datetime(
                receipt_document["completedAtUtc"],
                "receipt.completedAtUtc",
            ),
        )
        if (
            receipt.receipt_id != operation_id
            or receipt.owner_id != owner_id
            or receipt.firebase_uid != firebase_uid
            or not server_export_completed
        ):
            raise ValueError("account deletion receipt binding is invalid")
    recovery_expires_at = document.get("recoveryExpiresAtUtc")
    if recovery_expires_at is None:
        raise ValueError("recoveryExpiresAtUtc is required")
    decoded_expiry = _decode_utc_datetime(
        recovery_expires_at, "recoveryExpiresAtUtc"
    )
    purge_at = document.get("purgeAtUtc")
    if purge_at is not None:
        decoded_purge = _decode_utc_datetime(purge_at, "purgeAtUtc")
        if not identity_deleted or decoded_purge != decoded_expiry:
            raise ValueError("purgeAtUtc is invalid")
    if identity_deleted and (receipt is None or not server_export_completed):
        raise ValueError("completed account deletion state is invalid")

    return AccountDeletionOperation(
        operation_id=operation_id,
        owner_id=owner_id,
        firebase_uid=firebase_uid,
        recovery_key_proof=RecoveryKeyProof(
            algorithm=algorithm,
            key_version=key_version,
            mac=mac,
        ),
        scopes=frozenset(scopes_value),
        requested_at_utc=_decode_utc_datetime(
            document["requestedAtUtc"], "requestedAtUtc"
        ),
        receipt=receipt,
        identity_deleted=identity_deleted,
        server_export_completed=server_export_completed,
        recovery_expires_at_utc=decoded_expiry,
    )


def _canonical_operation_document(
    document: dict[str, object],
    recovery_key_authority: AccountDeletionRecoveryKeyAuthority,
) -> tuple[dict[str, object], AccountDeletionOperation, bool]:
    current = dict(document)
    keys = set(current)
    allowed = _OPERATION_COMMON_KEYS | {
        "recoveryKeyVerifier",
        "idempotencyKey",
        "purgeAtUtc",
    }
    if (
        not _OPERATION_COMMON_KEYS.issubset(keys)
        or not keys.issubset(allowed)
        or (("recoveryKeyVerifier" in keys) == ("idempotencyKey" in keys))
    ):
        raise ValueError("account deletion operation document is invalid")
    legacy_key = current.pop("idempotencyKey", None)
    if "recoveryKeyVerifier" not in current:
        if not isinstance(legacy_key, str):
            raise ValueError("account deletion recovery key is missing")
        current["recoveryKeyVerifier"] = _proof_to_document(
            recovery_key_authority.issue(legacy_key)
        )
        receipt = current.get("receipt")
        if isinstance(receipt, dict):
            receipt_copy = dict(receipt)
            receipt_key = receipt_copy.pop("idempotencyKey", None)
            if receipt_key != legacy_key:
                raise ValueError("legacy account deletion receipt is invalid")
            current["receipt"] = receipt_copy
    else:
        receipt = current.get("receipt")
        if isinstance(receipt, dict) and "idempotencyKey" in receipt:
            raise ValueError("account deletion receipt stores a recovery secret")

    operation = _operation_from_document(current)
    canonical = _operation_to_document(operation)
    return canonical, operation, canonical != document


def _proof_to_document(proof: RecoveryKeyProof) -> dict[str, str]:
    return {
        "algorithm": proof.algorithm,
        "kmsKeyVersion": proof.key_version,
        "mac": base64.b64encode(proof.mac).decode("ascii"),
    }


def _strict_segment(value: object, label: str) -> str:
    if not isinstance(value, str) or value != value.strip():
        raise ValueError(f"{label} is invalid")
    return _segment(value, label)


def _json_safe_map(value: Mapping[str, object]) -> dict[str, object]:
    if any(not isinstance(key, str) for key in value):
        raise ValueError("Firestore map keys must be strings")
    result: dict[str, object] = {}
    for key in sorted(value):
        result[key] = _json_safe_value(value[key])
    return result


def _json_safe_value(value: object) -> object:
    if value is None or isinstance(value, (bool, int, str)):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("Firestore floating-point value must be finite")
        return value
    if isinstance(value, bytes):
        return {
            "$firestoreType": "bytes",
            "base64": base64.b64encode(value).decode("ascii"),
        }
    if isinstance(value, datetime):
        return {
            "$firestoreType": "timestamp",
            "value": _require_utc_datetime(value, "Firestore timestamp")
            .isoformat()
            .replace("+00:00", "Z"),
        }
    if isinstance(value, GeoPoint):
        return {
            "$firestoreType": "geoPoint",
            "latitude": value.latitude,
            "longitude": value.longitude,
        }
    if isinstance(value, DocumentReference):
        return {"$firestoreType": "reference", "path": value.path}
    if isinstance(value, Mapping):
        return _json_safe_map(value)
    if isinstance(value, (list, tuple)):
        return [_json_safe_value(item) for item in value]
    raise ValueError("Firestore value type is not supported for account export")


def _canonical_json_bytes(value: object) -> bytes:
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise ValueError("Firestore value cannot be encoded for export") from error


def _require_utc_datetime(value: datetime, label: str) -> datetime:
    if value.tzinfo is None or value.utcoffset() != timedelta(0):
        raise ValueError(f"{label} must be UTC")
    return value


def _decode_utc_datetime(value: object, label: str) -> datetime:
    try:
        decoded = (
            value
            if isinstance(value, datetime)
            else datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        )
    except ValueError as error:
        raise ValueError(f"{label} must be a valid UTC timestamp") from error
    return _require_utc_datetime(decoded, label)


def _auth_user_to_export(user: object, *, expected_uid: str) -> dict[str, object]:
    uid = getattr(user, "uid", None)
    if uid != expected_uid:
        raise ValueError("Firebase Auth user does not match the deletion owner")
    metadata = getattr(user, "user_metadata", None)
    providers = []
    for provider in getattr(user, "provider_data", ()):
        providers.append(
            {
                "displayName": getattr(provider, "display_name", None),
                "email": getattr(provider, "email", None),
                "phoneNumber": getattr(provider, "phone_number", None),
                "photoUrl": getattr(provider, "photo_url", None),
                "providerId": getattr(provider, "provider_id", None),
                "uid": getattr(provider, "uid", None),
            }
        )
    providers.sort(key=lambda provider: str(provider["providerId"]))
    return {
        "uid": uid,
        "email": getattr(user, "email", None),
        "emailVerified": bool(getattr(user, "email_verified", False)),
        "displayName": getattr(user, "display_name", None),
        "phoneNumber": getattr(user, "phone_number", None),
        "photoUrl": getattr(user, "photo_url", None),
        "disabled": bool(getattr(user, "disabled", False)),
        "tenantId": getattr(user, "tenant_id", None),
        "providerData": providers,
        "createdAtEpochMillis": (
            None if metadata is None else metadata.creation_timestamp
        ),
        "lastSignInAtEpochMillis": (
            None if metadata is None else metadata.last_sign_in_timestamp
        ),
    }


def _segment(value: str, label: str) -> str:
    normalized = value.strip()
    if not normalized or "/" in normalized or len(normalized) > 128:
        raise ValueError(f"{label} is invalid")
    return normalized


def build_firebase_account_deletion_service(
    *,
    enabled: bool,
    server_export_authority: ServerCompleteAccountExportAuthority | None = None,
    recovery_key_authority: AccountDeletionRecoveryKeyAuthority | None = None,
    recovery_retention: timedelta | None = None,
    store_factory: Callable[
        [AccountDeletionRecoveryKeyAuthority], AccountDeletionOperationStore
    ] = (
        FirestoreAccountDeletionOperationStore.production
    ),
    deleter_factory: Callable[[], OwnerIsolatedAccountDeleter] = (
        FirebaseOwnerIsolatedAccountDeleter.production
    ),
) -> AccountDeletionService | None:
    if (
        not enabled
        or server_export_authority is None
        or recovery_key_authority is None
        or recovery_retention is None
    ):
        return None
    return AccountDeletionService(
        store=store_factory(recovery_key_authority),
        deleter=deleter_factory(),
        server_export_authority=server_export_authority,
        recovery_key_authority=recovery_key_authority,
        recovery_retention=recovery_retention,
    )
