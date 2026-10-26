"""Default-off privileged account-deletion service contract.

No production data-store adapter lives here. The deployment must supply a
reviewed store and owner-isolated deleter before enabling the endpoint.
"""

from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Protocol
from uuid import uuid4

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from lexiquest_ai.auth import AuthenticatedUser

ACCOUNT_DELETION_SCOPES = frozenset(
    {
        "research_consents",
        "vocabulary_categories",
        "vocabulary_words",
        "vocabulary_imports",
        "vocabulary_import_rows",
        "learning_sessions",
        "answer_attempts",
        "srs_states",
        "reading_progress_entries",
        "reading_events",
        "points_ledger_entries",
        "achievement_unlocks",
        "reward_transactions",
        "owned_reward_items",
        "equipped_reward_items",
        "outbox_operations",
        "sync_checkpoints",
        "sync_conflicts",
        "events_v2",
        "quest_instances",
        "quest_objective_progress",
        "streak_states",
        "learning_day_log",
        "association_records",
        "associative_memory_states",
        "local_owners",
    }
)

_KEY_PATTERN = re.compile(r"^[A-Za-z0-9._:-]{16,128}$")
_OWNER_PATTERN = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")


class FullExportReceipt(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")

    owner_id: str = Field(alias="ownerId", min_length=1, max_length=128)
    artifact_id: str = Field(alias="artifactId", min_length=1, max_length=512)
    artifact_sha256: str = Field(
        alias="artifactSha256", pattern=r"^[A-Fa-f0-9]{64}$"
    )
    bytes_written: int = Field(alias="bytesWritten", gt=0)
    schema_version: int = Field(alias="schemaVersion", ge=1)
    covered_scopes: frozenset[str] = Field(alias="coveredScopes")
    completed_at_utc: datetime = Field(alias="completedAtUtc")

    @field_validator("covered_scopes")
    @classmethod
    def _require_complete_scope(cls, value: frozenset[str]) -> frozenset[str]:
        if value != ACCOUNT_DELETION_SCOPES:
            raise ValueError("export must cover the complete account scope")
        return value

    @field_validator("completed_at_utc")
    @classmethod
    def _require_utc(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() != timedelta(0):
            raise ValueError("completedAtUtc must be UTC")
        return value


class AccountDeletionRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")

    owner_id: str = Field(alias="ownerId")
    idempotency_key: str = Field(alias="idempotencyKey")
    export_receipt: FullExportReceipt = Field(alias="exportReceipt")

    @field_validator("owner_id")
    @classmethod
    def _validate_owner_id(cls, value: str) -> str:
        if not _OWNER_PATTERN.fullmatch(value):
            raise ValueError("ownerId is invalid")
        return value

    @field_validator("idempotency_key")
    @classmethod
    def _validate_idempotency_key(cls, value: str) -> str:
        if not _KEY_PATTERN.fullmatch(value):
            raise ValueError("idempotencyKey is invalid")
        return value

    @model_validator(mode="after")
    def _match_export_owner(self) -> AccountDeletionRequest:
        if self.export_receipt.owner_id != self.owner_id:
            raise ValueError("export owner does not match deletion owner")
        return self


class AccountDeletionResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    receipt_id: str = Field(alias="receiptId")
    owner_id: str = Field(alias="ownerId")
    firebase_uid: str = Field(alias="firebaseUid")
    idempotency_key: str = Field(alias="idempotencyKey")
    completed_at_utc: datetime = Field(alias="completedAtUtc")


@dataclass(frozen=True, slots=True)
class AccountDeletionReceipt:
    receipt_id: str
    owner_id: str
    firebase_uid: str
    idempotency_key: str
    completed_at_utc: datetime

    def response(self) -> AccountDeletionResponse:
        return AccountDeletionResponse(
            receiptId=self.receipt_id,
            ownerId=self.owner_id,
            firebaseUid=self.firebase_uid,
            idempotencyKey=self.idempotency_key,
            completedAtUtc=self.completed_at_utc,
        )


@dataclass(frozen=True, slots=True)
class AccountDeletionOperation:
    operation_id: str
    owner_id: str
    firebase_uid: str
    idempotency_key: str
    scopes: frozenset[str]
    requested_at_utc: datetime
    receipt: AccountDeletionReceipt | None = None


class AccountDeletionConflict(Exception):
    """A user already claimed account deletion with another key."""


class RecentAuthenticationRequired(Exception):
    """The verified Firebase token is missing a recent auth_time claim."""


class AccountDeletionOperationStore(Protocol):
    def claim(self, operation: AccountDeletionOperation) -> AccountDeletionOperation:
        """Atomically persist a tombstone or return the user's existing one."""

        ...

    def complete(
        self,
        operation: AccountDeletionOperation,
        receipt: AccountDeletionReceipt,
    ) -> AccountDeletionReceipt:
        """Atomically attach and return the canonical receipt."""

        ...


class OwnerIsolatedAccountDeleter(Protocol):
    def delete_owned_data(
        self,
        *,
        owner_id: str,
        firebase_uid: str,
        scopes: frozenset[str],
        operation_id: str,
    ) -> None:
        """Delete only data proven to belong to this UID, then its auth user."""

        ...


class AccountDeletionService:
    recent_authentication_window = timedelta(minutes=5)
    server_clock_skew = timedelta(minutes=5)

    def __init__(
        self,
        *,
        store: AccountDeletionOperationStore,
        deleter: OwnerIsolatedAccountDeleter,
        now_utc: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self._store = store
        self._deleter = deleter
        self._now_utc = now_utc

    def delete(
        self,
        request: AccountDeletionRequest,
        user: AuthenticatedUser,
    ) -> AccountDeletionReceipt:
        now = self._now_utc()
        authenticated_at = user.authenticated_at_utc
        if (
            authenticated_at is None
            or authenticated_at.tzinfo is None
            or authenticated_at.utcoffset() != timedelta(0)
            or authenticated_at > now + self.server_clock_skew
            or now - authenticated_at > self.recent_authentication_window
        ):
            raise RecentAuthenticationRequired
        if request.export_receipt.completed_at_utc > now + self.server_clock_skew:
            raise ValueError("export receipt is from the future")

        candidate = AccountDeletionOperation(
            operation_id=str(uuid4()),
            owner_id=request.owner_id,
            firebase_uid=user.uid,
            idempotency_key=request.idempotency_key,
            scopes=ACCOUNT_DELETION_SCOPES,
            requested_at_utc=now,
        )
        operation = self._store.claim(candidate)
        if (
            operation.firebase_uid != user.uid
            or operation.idempotency_key != request.idempotency_key
            or operation.owner_id != request.owner_id
            or operation.scopes != ACCOUNT_DELETION_SCOPES
        ):
            raise AccountDeletionConflict
        if operation.receipt is not None:
            return operation.receipt

        self._deleter.delete_owned_data(
            owner_id=operation.owner_id,
            firebase_uid=operation.firebase_uid,
            scopes=operation.scopes,
            operation_id=operation.operation_id,
        )
        receipt = AccountDeletionReceipt(
            receipt_id=operation.operation_id,
            owner_id=operation.owner_id,
            firebase_uid=operation.firebase_uid,
            idempotency_key=operation.idempotency_key,
            completed_at_utc=self._now_utc(),
        )
        return self._store.complete(operation, receipt)
