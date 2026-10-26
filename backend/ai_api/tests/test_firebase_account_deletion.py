from __future__ import annotations

from dataclasses import replace
from datetime import UTC, datetime, timedelta

from lexiquest_ai.account_deletion import (
    ACCOUNT_DELETION_SCOPES,
    AccountDeletionOperation,
    AccountDeletionReceipt,
)
from lexiquest_ai.firebase_account_deletion import (
    FirebaseOwnerIsolatedAccountDeleter,
    FirestoreAccountDeletionOperationStore,
    build_firebase_account_deletion_service,
)

NOW = datetime(2026, 10, 26, 9, 0, tzinfo=UTC)


class _Documents:
    def __init__(self) -> None:
        self.values: dict[str, dict[str, object]] = {}

    def transact(self, uid, update):  # type: ignore[no-untyped-def]
        value, result = update(self.values.get(uid))
        if value is not None:
            self.values[uid] = value
        return result


def _operation(*, key: str = "delete:operation-0001") -> AccountDeletionOperation:
    return AccountDeletionOperation(
        operation_id="operation-1",
        owner_id="owner-a",
        firebase_uid="firebase-user",
        idempotency_key=key,
        scopes=ACCOUNT_DELETION_SCOPES,
        requested_at_utc=NOW,
    )


def test_firestore_store_atomically_preserves_the_canonical_operation() -> None:
    documents = _Documents()
    store = FirestoreAccountDeletionOperationStore(documents)
    first = _operation()

    assert store.claim(first) == first
    assert store.claim(_operation(key="delete:different-key")) == first

    exported = store.mark_server_export_completed(first)
    assert exported.server_export_completed is True

    receipt = AccountDeletionReceipt(
        receipt_id="operation-1",
        owner_id="owner-a",
        firebase_uid="firebase-user",
        idempotency_key="delete:operation-0001",
        completed_at_utc=NOW,
    )
    assert store.complete(exported, receipt) == receipt
    assert store.complete(exported, replace(receipt, completed_at_utc=NOW)) == receipt
    completed = store.get("firebase-user")
    assert completed is not None and completed.receipt == receipt

    marked = store.mark_identity_deleted(completed)
    assert marked.identity_deleted is True
    assert store.get("firebase-user") == marked


def test_deleter_targets_only_uid_owned_namespaces_and_auth_last() -> None:
    calls: list[tuple[str, str]] = []
    owned = {
        ("categories", "uid"): ["categories/category-a"],
        ("purchased_items", "user_id"): ["purchased_items/purchase-a"],
        ("vocabulary", "uid"): ["vocabulary/private-a"],
    }
    deleter = FirebaseOwnerIsolatedAccountDeleter(
        delete_tree=lambda path: calls.append(("tree", path)),
        delete_document=lambda path: calls.append(("document", path)),
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


def test_auth_deletion_is_idempotent_for_an_already_missing_user() -> None:
    class _MissingUser(Exception):
        pass

    def missing(_: str) -> None:
        raise _MissingUser

    deleter = FirebaseOwnerIsolatedAccountDeleter(
        delete_tree=lambda _: None,
        delete_document=lambda _: None,
        find_owned_paths=lambda *_: [],
        delete_user=missing,
        user_not_found_errors=(_MissingUser,),
    )

    deleter.delete_auth_identity(
        firebase_uid="firebase-user", operation_id="operation-1"
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
        recovery_retention=timedelta(days=7),
        store_factory=lambda: (
            calls.append("store"),
            FirestoreAccountDeletionOperationStore(_Documents()),
        )[1],
        deleter_factory=lambda: (
            calls.append("deleter"),
            FirebaseOwnerIsolatedAccountDeleter(
                delete_tree=lambda _: None,
                delete_document=lambda _: None,
                find_owned_paths=lambda *_: [],
                delete_user=lambda _: None,
            ),
        )[1],
    )

    assert service is not None
    assert calls == ["store", "deleter"]
