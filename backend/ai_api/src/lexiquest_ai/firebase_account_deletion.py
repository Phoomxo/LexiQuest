"""Firebase Admin adapters for the privileged account-deletion contract."""

from __future__ import annotations

from collections.abc import Callable, Iterable
from datetime import datetime, timedelta
from typing import Protocol, TypeVar

from firebase_admin import auth as firebase_auth
from firebase_admin import firestore as firebase_firestore
from google.cloud import firestore as google_firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from lexiquest_ai.account_deletion import (
    ACCOUNT_DELETION_SCOPES,
    AccountDeletionOperation,
    AccountDeletionOperationStore,
    AccountDeletionReceipt,
    AccountDeletionService,
    OwnerIsolatedAccountDeleter,
    ServerCompleteAccountExportAuthority,
)

T = TypeVar("T")
OperationUpdate = Callable[
    [dict[str, object] | None], tuple[dict[str, object] | None, T]
]


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
    def __init__(self, documents: AtomicOperationDocuments) -> None:
        self._documents = documents

    @classmethod
    def production(cls) -> FirestoreAccountDeletionOperationStore:
        return cls(FirestoreOperationDocuments())

    def claim(self, operation: AccountDeletionOperation) -> AccountDeletionOperation:
        def update(current):  # type: ignore[no-untyped-def]
            if current is not None:
                existing = _operation_from_document(current)
                return current, existing
            encoded = _operation_to_document(operation)
            return encoded, operation

        return self._documents.transact(operation.firebase_uid, update)

    def complete(
        self,
        operation: AccountDeletionOperation,
        receipt: AccountDeletionReceipt,
    ) -> AccountDeletionReceipt:
        def update(current):  # type: ignore[no-untyped-def]
            existing = _required_operation(current, operation)
            if existing.receipt is not None:
                return current, existing.receipt
            completed = AccountDeletionOperation(
                operation_id=existing.operation_id,
                owner_id=existing.owner_id,
                firebase_uid=existing.firebase_uid,
                idempotency_key=existing.idempotency_key,
                scopes=existing.scopes,
                requested_at_utc=existing.requested_at_utc,
                receipt=receipt,
                identity_deleted=existing.identity_deleted,
                server_export_completed=existing.server_export_completed,
                recovery_expires_at_utc=existing.recovery_expires_at_utc,
            )
            return _operation_to_document(completed), receipt

        return self._documents.transact(operation.firebase_uid, update)

    def get(self, firebase_uid: str) -> AccountDeletionOperation | None:
        def read(current):  # type: ignore[no-untyped-def]
            return None, None if current is None else _operation_from_document(current)

        return self._documents.transact(firebase_uid, read)

    def mark_server_export_completed(
        self, operation: AccountDeletionOperation
    ) -> AccountDeletionOperation:
        def update(current):  # type: ignore[no-untyped-def]
            existing = _required_operation(current, operation)
            if existing.server_export_completed:
                return current, existing
            completed = AccountDeletionOperation(
                operation_id=existing.operation_id,
                owner_id=existing.owner_id,
                firebase_uid=existing.firebase_uid,
                idempotency_key=existing.idempotency_key,
                scopes=existing.scopes,
                requested_at_utc=existing.requested_at_utc,
                receipt=existing.receipt,
                identity_deleted=existing.identity_deleted,
                server_export_completed=True,
                recovery_expires_at_utc=existing.recovery_expires_at_utc,
            )
            encoded = _operation_to_document(completed)
            return encoded, completed

        return self._documents.transact(operation.firebase_uid, update)

    def mark_identity_deleted(
        self, operation: AccountDeletionOperation
    ) -> AccountDeletionOperation:
        def update(current):  # type: ignore[no-untyped-def]
            existing = _required_operation(current, operation)
            if existing.identity_deleted:
                return current, existing
            completed = AccountDeletionOperation(
                operation_id=existing.operation_id,
                owner_id=existing.owner_id,
                firebase_uid=existing.firebase_uid,
                idempotency_key=existing.idempotency_key,
                scopes=existing.scopes,
                requested_at_utc=existing.requested_at_utc,
                receipt=existing.receipt,
                identity_deleted=True,
                server_export_completed=existing.server_export_completed,
                recovery_expires_at_utc=existing.recovery_expires_at_utc,
            )
            encoded = _operation_to_document(completed)
            return encoded, completed

        return self._documents.transact(operation.firebase_uid, update)


DeleteTree = Callable[[str], None]
DeleteDocument = Callable[[str], None]
FindOwnedPaths = Callable[[str, str, str], Iterable[str]]
DeleteUser = Callable[[str], None]


class FirebaseOwnerIsolatedAccountDeleter(OwnerIsolatedAccountDeleter):
    def __init__(
        self,
        *,
        delete_tree: DeleteTree,
        delete_document: DeleteDocument,
        find_owned_paths: FindOwnedPaths,
        delete_user: DeleteUser,
        user_not_found_errors: tuple[type[BaseException], ...] = (
            firebase_auth.UserNotFoundError,
        ),
    ) -> None:
        self._delete_tree = delete_tree
        self._delete_document = delete_document
        self._find_owned_paths = find_owned_paths
        self._delete_user = delete_user
        self._user_not_found_errors = user_not_found_errors

    @classmethod
    def production(cls) -> FirebaseOwnerIsolatedAccountDeleter:
        client = firebase_firestore.client()

        def ref(path: str):  # type: ignore[no-untyped-def]
            collection, document = path.split("/", 1)
            return client.collection(collection).document(document)

        def find(collection: str, field: str, uid: str) -> Iterable[str]:
            query = client.collection(collection).where(
                filter=FieldFilter(field, "==", uid)
            )
            return [snapshot.reference.path for snapshot in query.stream()]

        return cls(
            delete_tree=lambda path: client.recursive_delete(ref(path)),
            delete_document=lambda path: ref(path).delete(),
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
        self._delete_tree(f"field_users/{uid}")
        self._delete_document(f"users/{uid}")
        self._delete_document(f"state/{uid}")
        for collection, field, recursive in (
            ("categories", "uid", True),
            ("purchased_items", "user_id", False),
            ("vocabulary", "uid", False),
        ):
            for path in self._find_owned_paths(collection, field, uid):
                if not path.startswith(f"{collection}/"):
                    raise ValueError("owner query returned an unexpected path")
                (self._delete_tree if recursive else self._delete_document)(path)

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
) -> AccountDeletionOperation:
    if current is None:
        raise RuntimeError("account deletion operation is missing")
    operation = _operation_from_document(current)
    if operation.operation_id != expected.operation_id:
        raise RuntimeError("account deletion operation changed")
    return operation


def _operation_to_document(
    operation: AccountDeletionOperation,
) -> dict[str, object]:
    return {
        "operationId": operation.operation_id,
        "ownerId": operation.owner_id,
        "firebaseUid": operation.firebase_uid,
        "idempotencyKey": operation.idempotency_key,
        "scopes": sorted(operation.scopes),
        "requestedAtUtc": operation.requested_at_utc.isoformat(),
        "identityDeleted": operation.identity_deleted,
        "serverExportCompleted": operation.server_export_completed,
        "recoveryExpiresAtUtc": (
            None
            if operation.recovery_expires_at_utc is None
            else operation.recovery_expires_at_utc.isoformat()
        ),
        "receipt": None
        if operation.receipt is None
        else {
            "receiptId": operation.receipt.receipt_id,
            "ownerId": operation.receipt.owner_id,
            "firebaseUid": operation.receipt.firebase_uid,
            "idempotencyKey": operation.receipt.idempotency_key,
            "completedAtUtc": operation.receipt.completed_at_utc.isoformat(),
        },
    }


def _operation_from_document(document: dict[str, object]) -> AccountDeletionOperation:
    receipt_document = document.get("receipt")
    receipt = None
    if isinstance(receipt_document, dict):
        receipt = AccountDeletionReceipt(
            receipt_id=str(receipt_document["receiptId"]),
            owner_id=str(receipt_document["ownerId"]),
            firebase_uid=str(receipt_document["firebaseUid"]),
            idempotency_key=str(receipt_document["idempotencyKey"]),
            completed_at_utc=datetime.fromisoformat(
                str(receipt_document["completedAtUtc"])
            ),
        )
    recovery_expires_at = document.get("recoveryExpiresAtUtc")
    return AccountDeletionOperation(
        operation_id=str(document["operationId"]),
        owner_id=str(document["ownerId"]),
        firebase_uid=str(document["firebaseUid"]),
        idempotency_key=str(document["idempotencyKey"]),
        scopes=frozenset(str(value) for value in document["scopes"]),  # type: ignore[union-attr]
        requested_at_utc=datetime.fromisoformat(str(document["requestedAtUtc"])),
        receipt=receipt,
        identity_deleted=bool(document.get("identityDeleted", False)),
        server_export_completed=bool(
            document.get("serverExportCompleted", False)
        ),
        recovery_expires_at_utc=(
            None
            if recovery_expires_at is None
            else datetime.fromisoformat(str(recovery_expires_at))
        ),
    )


def _segment(value: str, label: str) -> str:
    normalized = value.strip()
    if not normalized or "/" in normalized or len(normalized) > 128:
        raise ValueError(f"{label} is invalid")
    return normalized


def build_firebase_account_deletion_service(
    *,
    enabled: bool,
    server_export_authority: ServerCompleteAccountExportAuthority | None = None,
    recovery_retention: timedelta | None = None,
    store_factory: Callable[[], AccountDeletionOperationStore] = (
        FirestoreAccountDeletionOperationStore.production
    ),
    deleter_factory: Callable[[], OwnerIsolatedAccountDeleter] = (
        FirebaseOwnerIsolatedAccountDeleter.production
    ),
) -> AccountDeletionService | None:
    if (
        not enabled
        or server_export_authority is None
        or recovery_retention is None
    ):
        return None
    return AccountDeletionService(
        store=store_factory(),
        deleter=deleter_factory(),
        server_export_authority=server_export_authority,
        recovery_retention=recovery_retention,
    )
