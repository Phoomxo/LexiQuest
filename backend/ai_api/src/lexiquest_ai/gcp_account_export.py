"""KMS-authenticated, create-only server export for account deletion."""

from __future__ import annotations

import base64
import hashlib
import json
import re
import time
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from threading import Lock
from typing import Protocol

import google_crc32c
from firebase_admin import auth as firebase_auth
from firebase_admin import firestore as firebase_firestore
from firebase_admin import storage as firebase_storage
from google.api_core.exceptions import NotFound
from google.cloud.firestore_v1 import ExistsOption
from google.cloud.firestore_v1.base_query import FieldFilter

from lexiquest_ai.account_deletion import (
    ACCOUNT_DELETION_SCOPES,
    FullExportReceipt,
    RecoveryKeyProof,
    ServerCompleteAccountExportAuthority,
)
from lexiquest_ai.config import Settings


_FORMAT_VERSION = 1
_OBJECT_PREFIX = "account-deletion-exports/v1"
_MAC_ALGORITHM = "HMAC-SHA256"
_PRODUCTION_AUTHORITY = "gcp-kms-hmac-sha256-v1"
_RECOVERY_KEY_PATTERN = re.compile(r"^[A-Za-z0-9._:-]{16,128}$")
_RECOVERY_PROOF_DOMAIN = b"lexiquest/account-deletion/recovery-key/v1\x00"
_READINESS_MESSAGE = b"lexiquest/account-deletion/readiness/v1"
_BUCKET_PERMISSIONS = frozenset(
    {"storage.objects.create", "storage.objects.get"}
)
_METADATA_KEYS = frozenset(
    {
        "formatVersion",
        "payloadSha256",
        "bytesWritten",
        "expiresAtUtc",
        "kmsKeyVersion",
        "macAlgorithm",
        "receiptMac",
    }
)


@dataclass(frozen=True, slots=True)
class ImmutableExportObject:
    object_name: str
    contents: bytes
    metadata: dict[str, str]


@dataclass(frozen=True, slots=True)
class MacSignature:
    key_version: str
    mac: bytes


class CompleteAccountSnapshotReader(Protocol):
    def read_complete_snapshot(self, firebase_uid: str) -> dict[str, object]: ...


class ImmutableExportObjectStore(Protocol):
    def read(self, object_name: str) -> ImmutableExportObject | None: ...

    def create(
        self,
        *,
        object_name: str,
        contents: bytes,
        metadata: dict[str, str],
    ) -> ImmutableExportObject: ...


class ReceiptMacAuthority(Protocol):
    key_version: str

    def sign(self, message: bytes) -> MacSignature: ...

    def verify(self, *, key_version: str, message: bytes, mac: bytes) -> bool: ...


class GcsImmutableExportObjectStore:
    def __init__(self, bucket) -> None:  # type: ignore[no-untyped-def]
        self._bucket = bucket

    @classmethod
    def production(cls, bucket_name: str) -> GcsImmutableExportObjectStore:
        normalized = bucket_name.strip()
        if not normalized:
            raise ValueError("account deletion export bucket is required")
        return cls(firebase_storage.bucket(normalized))

    def read(self, object_name: str) -> ImmutableExportObject | None:
        blob = self._bucket.blob(_object_name(object_name))
        try:
            blob.reload()
        except NotFound:
            return None
        generation = blob.generation
        if generation is None:
            raise ValueError("GCS object generation is unavailable")
        contents = blob.download_as_bytes(if_generation_match=generation)
        return ImmutableExportObject(
            object_name=object_name,
            contents=contents,
            metadata=dict(blob.metadata or {}),
        )

    def create(
        self,
        *,
        object_name: str,
        contents: bytes,
        metadata: dict[str, str],
    ) -> ImmutableExportObject:
        blob = self._bucket.blob(_object_name(object_name))
        blob.metadata = dict(metadata)
        blob.cache_control = "no-store"
        blob.upload_from_string(
            contents,
            content_type="application/json; charset=utf-8",
            if_generation_match=0,
        )
        return ImmutableExportObject(
            object_name=object_name,
            contents=contents,
            metadata=dict(metadata),
        )


class CloudKmsHmacSha256Authority:
    def __init__(
        self, *, client, key_version: str  # type: ignore[no-untyped-def]
    ) -> None:
        self._client = client
        self.key_version = _kms_key_version(key_version)

    @classmethod
    def production(cls, key_version: str) -> CloudKmsHmacSha256Authority:
        from google.cloud import kms_v1

        return cls(
            client=kms_v1.KeyManagementServiceClient(),
            key_version=key_version,
        )

    def sign(self, message: bytes) -> MacSignature:
        response = self._client.mac_sign(
            request={
                "name": self.key_version,
                "data": message,
                "data_crc32c": _crc32c(message),
            }
        )
        mac = bytes(response.mac)
        if (
            response.name != self.key_version
            or not response.verified_data_crc32c
            or len(mac) != hashlib.sha256().digest_size
            or response.mac_crc32c != _crc32c(mac)
        ):
            raise ValueError("Cloud KMS MAC integrity check failed")
        return MacSignature(key_version=self.key_version, mac=mac)

    def verify(self, *, key_version: str, message: bytes, mac: bytes) -> bool:
        if (
            key_version != self.key_version
            or len(mac) != hashlib.sha256().digest_size
        ):
            return False
        response = self._client.mac_verify(
            request={
                "name": self.key_version,
                "data": message,
                "data_crc32c": _crc32c(message),
                "mac": mac,
                "mac_crc32c": _crc32c(mac),
            }
        )
        return bool(
            response.name == self.key_version
            and response.success
            and response.verified_data_crc32c
            and response.verified_mac_crc32c
            and response.verified_success_integrity
        )


class TrustedKmsMacAuthority:
    def __init__(
        self,
        *,
        active: ReceiptMacAuthority,
        trusted: Mapping[str, ReceiptMacAuthority],
    ) -> None:
        authorities = dict(trusted)
        if authorities.get(active.key_version) is not active:
            raise ValueError("active KMS key version must be trusted")
        if any(version != authority.key_version for version, authority in authorities.items()):
            raise ValueError("trusted KMS authority binding is invalid")
        self._active = active
        self._trusted = authorities
        self.key_version = active.key_version

    @property
    def trusted_key_versions(self) -> frozenset[str]:
        return frozenset(self._trusted)

    @property
    def trusted_authorities(self) -> Mapping[str, ReceiptMacAuthority]:
        return dict(self._trusted)

    def sign(self, message: bytes) -> MacSignature:
        return self._active.sign(message)

    def verify(self, *, key_version: str, message: bytes, mac: bytes) -> bool:
        authority = self._trusted.get(key_version)
        return authority is not None and authority.verify(
            key_version=key_version,
            message=message,
            mac=mac,
        )


class KmsRecoveryKeyAuthority:
    def __init__(self, mac_authority: ReceiptMacAuthority) -> None:
        self._mac_authority = mac_authority

    def issue(self, idempotency_key: str) -> RecoveryKeyProof:
        message = _recovery_key_message(idempotency_key)
        signature = self._mac_authority.sign(message)
        return RecoveryKeyProof(
            algorithm=_MAC_ALGORITHM,
            key_version=signature.key_version,
            mac=signature.mac,
        )

    def verify(
        self, idempotency_key: str, proof: RecoveryKeyProof
    ) -> bool:
        if proof.algorithm != _MAC_ALGORITHM:
            return False
        try:
            message = _recovery_key_message(idempotency_key)
        except ValueError:
            return False
        return self._mac_authority.verify(
            key_version=proof.key_version,
            message=message,
            mac=proof.mac,
        )


class GcpAccountDeletionReadinessProbe:
    def __init__(
        self,
        *,
        bucket_attestation: Callable[[], bool],
        kms_attestation: Callable[[], bool],
        firestore_iam_attestation: Callable[[], bool],
        firebase_auth_iam_attestation: Callable[[], bool],
        cache_ttl: timedelta = timedelta(seconds=30),
        monotonic: Callable[[], float] = time.monotonic,
    ) -> None:
        if cache_ttl <= timedelta(0):
            raise ValueError("readiness cache TTL must be positive")
        self._attestations = (
            bucket_attestation,
            kms_attestation,
            firestore_iam_attestation,
            firebase_auth_iam_attestation,
        )
        self._cache_seconds = cache_ttl.total_seconds()
        self._monotonic = monotonic
        self._cached_until = 0.0
        self._cached_result = False
        self._lock = Lock()

    def is_ready(self) -> bool:
        now = self._monotonic()
        with self._lock:
            if now < self._cached_until:
                return self._cached_result
            try:
                result = all(check() is True for check in self._attestations)
            except Exception:
                result = False
            self._cached_result = result
            self._cached_until = now + self._cache_seconds
            return result


class KmsBackedServerCompleteAccountExportAuthority(
    ServerCompleteAccountExportAuthority
):
    maximum_retention = timedelta(days=30)

    def __init__(
        self,
        *,
        snapshot_reader: CompleteAccountSnapshotReader,
        object_store: ImmutableExportObjectStore,
        mac_authority: ReceiptMacAuthority,
        retention: timedelta,
        maximum_bytes: int = 50 * 1024 * 1024,
        now_utc: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        if (
            retention <= timedelta(0)
            or retention > self.maximum_retention
            or maximum_bytes <= 0
        ):
            raise ValueError("account deletion export configuration is invalid")
        if not mac_authority.key_version.strip():
            raise ValueError("KMS key version is required")
        self._snapshot_reader = snapshot_reader
        self._object_store = object_store
        self._mac_authority = mac_authority
        self._retention = retention
        self._maximum_bytes = maximum_bytes
        self._now_utc = now_utc

    def ensure_complete_export(
        self,
        *,
        owner_id: str,
        firebase_uid: str,
        idempotency_key: str,
        operation_id: str,
        client_export_receipt: FullExportReceipt,
    ) -> None:
        _require_identifier(owner_id, "owner_id")
        _require_identifier(firebase_uid, "firebase_uid")
        _require_identifier(operation_id, "operation_id")
        if _RECOVERY_KEY_PATTERN.fullmatch(idempotency_key) is None:
            raise ValueError("idempotency key is invalid")
        if (
            client_export_receipt.owner_id != owner_id
            or client_export_receipt.covered_scopes != ACCOUNT_DELETION_SCOPES
        ):
            raise ValueError("client export binding is invalid")

        now = self._now()
        object_name = f"{_OBJECT_PREFIX}/{operation_id}.json"
        existing = self._object_store.read(object_name)
        if existing is not None:
            self._verify_existing(
                existing,
                owner_id=owner_id,
                firebase_uid=firebase_uid,
                idempotency_key=idempotency_key,
                operation_id=operation_id,
                client_export_receipt=client_export_receipt,
                now=now,
            )
            return

        snapshot = self._snapshot_reader.read_complete_snapshot(firebase_uid)
        payload = {
            "formatVersion": _FORMAT_VERSION,
            "operationId": operation_id,
            "ownerId": owner_id,
            "firebaseUid": firebase_uid,
            "generatedAtUtc": _utc_text(now),
            "clientExportReceipt": _client_receipt(client_export_receipt),
            "serverSnapshot": snapshot,
        }
        contents = _canonical_json(payload)
        if not contents or len(contents) > self._maximum_bytes:
            raise ValueError("server export exceeds the configured size limit")
        payload_sha256 = hashlib.sha256(contents).hexdigest()
        expires_at = now + self._retention
        binding = self._receipt_binding(
            owner_id=owner_id,
            firebase_uid=firebase_uid,
            idempotency_key=idempotency_key,
            operation_id=operation_id,
            client_export_receipt=client_export_receipt,
            object_name=object_name,
            payload_sha256=payload_sha256,
            bytes_written=len(contents),
            expires_at=expires_at,
            kms_key_version=self._mac_authority.key_version,
        )
        signature = self._mac_authority.sign(_canonical_json(binding))
        if (
            signature.key_version != self._mac_authority.key_version
            or not signature.mac
        ):
            raise ValueError("KMS returned an invalid MAC")
        metadata = {
            "formatVersion": str(_FORMAT_VERSION),
            "payloadSha256": payload_sha256,
            "bytesWritten": str(len(contents)),
            "expiresAtUtc": _utc_text(expires_at),
            "kmsKeyVersion": signature.key_version,
            "macAlgorithm": _MAC_ALGORITHM,
            "receiptMac": base64.b64encode(signature.mac).decode("ascii"),
        }
        try:
            stored = self._object_store.create(
                object_name=object_name,
                contents=contents,
                metadata=metadata,
            )
        except Exception:
            stored = self._object_store.read(object_name)
            if stored is None:
                raise
        self._verify_existing(
            stored,
            owner_id=owner_id,
            firebase_uid=firebase_uid,
            idempotency_key=idempotency_key,
            operation_id=operation_id,
            client_export_receipt=client_export_receipt,
            now=now,
        )

    def _verify_existing(
        self,
        stored: ImmutableExportObject,
        *,
        owner_id: str,
        firebase_uid: str,
        idempotency_key: str,
        operation_id: str,
        client_export_receipt: FullExportReceipt,
        now: datetime,
    ) -> None:
        expected_name = f"{_OBJECT_PREFIX}/{operation_id}.json"
        if stored.object_name != expected_name:
            raise ValueError("server export binding is invalid")
        metadata = stored.metadata
        if (
            set(metadata) != _METADATA_KEYS
            or metadata.get("formatVersion") != str(_FORMAT_VERSION)
        ):
            raise ValueError("server export binding is invalid")
        actual_digest = hashlib.sha256(stored.contents).hexdigest()
        if metadata.get("payloadSha256") != actual_digest:
            raise ValueError("server export digest is invalid")
        try:
            bytes_written = int(metadata["bytesWritten"])
            expires_at = _parse_utc(metadata["expiresAtUtc"])
            receipt_mac = base64.b64decode(
                metadata["receiptMac"], validate=True
            )
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError("server export binding is invalid") from error
        if bytes_written != len(stored.contents):
            raise ValueError("server export digest is invalid")
        if now > expires_at:
            raise ValueError("server export receipt expired")
        key_version = metadata.get("kmsKeyVersion", "")
        if (
            metadata.get("macAlgorithm") != _MAC_ALGORITHM
            or not key_version
        ):
            raise ValueError("server export MAC authority is invalid")
        try:
            payload = json.loads(stored.contents)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError("server export binding is invalid") from error
        if not isinstance(payload, dict) or _canonical_json(payload) != stored.contents:
            raise ValueError("server export binding is invalid")
        if (
            payload.get("formatVersion") != _FORMAT_VERSION
            or payload.get("operationId") != operation_id
            or payload.get("ownerId") != owner_id
            or payload.get("firebaseUid") != firebase_uid
            or payload.get("clientExportReceipt")
            != _client_receipt(client_export_receipt)
            or not isinstance(payload.get("serverSnapshot"), dict)
        ):
            raise ValueError("server export binding is invalid")
        binding = self._receipt_binding(
            owner_id=owner_id,
            firebase_uid=firebase_uid,
            idempotency_key=idempotency_key,
            operation_id=operation_id,
            client_export_receipt=client_export_receipt,
            object_name=stored.object_name,
            payload_sha256=actual_digest,
            bytes_written=bytes_written,
            expires_at=expires_at,
            kms_key_version=key_version,
        )
        if not self._mac_authority.verify(
            key_version=key_version,
            message=_canonical_json(binding),
            mac=receipt_mac,
        ):
            raise ValueError("server export MAC is invalid")

    def _receipt_binding(
        self,
        *,
        owner_id: str,
        firebase_uid: str,
        idempotency_key: str,
        operation_id: str,
        client_export_receipt: FullExportReceipt,
        object_name: str,
        payload_sha256: str,
        bytes_written: int,
        expires_at: datetime,
        kms_key_version: str,
    ) -> dict[str, object]:
        return {
            "formatVersion": _FORMAT_VERSION,
            "macAlgorithm": _MAC_ALGORITHM,
            "kmsKeyVersion": kms_key_version,
            "operationId": operation_id,
            "ownerId": owner_id,
            "firebaseUid": firebase_uid,
            "idempotencyKey": idempotency_key,
            "clientExportReceipt": _client_receipt(client_export_receipt),
            "objectName": object_name,
            "payloadSha256": payload_sha256,
            "bytesWritten": bytes_written,
            "expiresAtUtc": _utc_text(expires_at),
        }

    def _now(self) -> datetime:
        value = self._now_utc()
        if value.tzinfo is None or value.utcoffset() != timedelta(0):
            raise ValueError("account deletion export clock must be UTC")
        return value


def build_trusted_kms_mac_authority(
    settings: Settings,
    *,
    authority_factory=None,  # type: ignore[no-untyped-def]
) -> TrustedKmsMacAuthority | None:
    authority = settings.account_deletion_server_export_authority
    if not authority:
        return None
    if authority != _PRODUCTION_AUTHORITY:
        raise ValueError("account deletion export authority is unsupported")
    authority_factory = (
        authority_factory or CloudKmsHmacSha256Authority.production
    )
    active_version = settings.account_deletion_export_kms_key_version
    active = authority_factory(active_version)
    trusted: dict[str, ReceiptMacAuthority] = {
        active_version: active,
    }
    for version in (
        settings.account_deletion_export_trusted_kms_key_versions.split(",")
    ):
        if version and version not in trusted:
            trusted[version] = authority_factory(version)
    return TrustedKmsMacAuthority(active=active, trusted=trusted)


def build_gcp_account_deletion_readiness_probe(
    settings: Settings,
    *,
    mac_authority: TrustedKmsMacAuthority | None,
    bucket_factory=None,  # type: ignore[no-untyped-def]
    kms_client_factory=None,  # type: ignore[no-untyped-def]
    firestore_client_factory=None,  # type: ignore[no-untyped-def]
    auth_get_user=None,  # type: ignore[no-untyped-def]
    auth_user_not_found_errors: tuple[type[BaseException], ...] = (
        firebase_auth.UserNotFoundError,
    ),
    monotonic: Callable[[], float] = time.monotonic,
) -> GcpAccountDeletionReadinessProbe | None:
    authority = settings.account_deletion_server_export_authority
    if not authority:
        return None
    if authority != _PRODUCTION_AUTHORITY or mac_authority is None:
        raise ValueError("account deletion readiness is not configured")
    expected_versions = {
        settings.account_deletion_export_kms_key_version,
        *(
            version
            for version in (
                settings.account_deletion_export_trusted_kms_key_versions.split(",")
            )
            if version
        ),
    }
    if mac_authority.trusted_key_versions != expected_versions:
        raise ValueError("account deletion KMS trust set is incomplete")

    bucket_factory = bucket_factory or firebase_storage.bucket
    if kms_client_factory is None:
        from google.cloud import kms_v1

        kms_client_factory = kms_v1.KeyManagementServiceClient
    firestore_client_factory = (
        firestore_client_factory or firebase_firestore.client
    )
    auth_get_user = auth_get_user or firebase_auth.get_user

    bucket = bucket_factory(settings.account_deletion_export_bucket)
    kms_client = kms_client_factory()
    firestore_client = firestore_client_factory()

    def bucket_attestation() -> bool:
        bucket.reload()
        iam = bucket.iam_configuration
        permissions = set(
            bucket.test_iam_permissions(sorted(_BUCKET_PERMISSIONS))
        )
        return bool(
            iam.public_access_prevention == "enforced"
            and iam.uniform_bucket_level_access_enabled is True
            and permissions == _BUCKET_PERMISSIONS
        )

    def kms_attestation() -> bool:
        from google.cloud import kms_v1

        for version, authority_for_version in (
            mac_authority.trusted_authorities.items()
        ):
            key = kms_client.get_crypto_key_version(
                request={"name": version}
            )
            if (
                key.state
                != kms_v1.CryptoKeyVersion.CryptoKeyVersionState.ENABLED
                or key.algorithm
                != kms_v1.CryptoKeyVersion.CryptoKeyVersionAlgorithm.HMAC_SHA256
            ):
                return False
            signature = authority_for_version.sign(_READINESS_MESSAGE)
            if (
                signature.key_version != version
                or not authority_for_version.verify(
                    key_version=version,
                    message=_READINESS_MESSAGE,
                    mac=signature.mac,
                )
            ):
                return False
        return True

    def firestore_iam_attestation() -> bool:
        readiness_ref = firestore_client.document(
            "account_deletion_operations/__readiness__"
        )
        readiness_ref.get()
        firestore_client.collection("categories").where(
            filter=FieldFilter(
                "uid", "==", "__lexiquest_account_deletion_readiness__"
            )
        ).limit(1).get()
        # This precondition can only succeed while the reserved document is
        # absent, so the IAM delete probe cannot remove real data.
        readiness_ref.delete(option=ExistsOption(False))
        return True

    def firebase_auth_iam_attestation() -> bool:
        readiness_uid = "__lexiquest_account_deletion_readiness__"
        try:
            auth_get_user(readiness_uid)
        except auth_user_not_found_errors:
            return True
        return False

    return GcpAccountDeletionReadinessProbe(
        bucket_attestation=bucket_attestation,
        kms_attestation=kms_attestation,
        firestore_iam_attestation=firestore_iam_attestation,
        firebase_auth_iam_attestation=firebase_auth_iam_attestation,
        monotonic=monotonic,
    )


def build_gcp_account_export_authority(
    settings: Settings,
    *,
    snapshot_reader_factory=None,  # type: ignore[no-untyped-def]
    object_store_factory=None,  # type: ignore[no-untyped-def]
    mac_authority_factory=None,  # type: ignore[no-untyped-def]
    mac_authority: ReceiptMacAuthority | None = None,
) -> KmsBackedServerCompleteAccountExportAuthority | None:
    authority = settings.account_deletion_server_export_authority
    if not authority:
        return None
    if authority != _PRODUCTION_AUTHORITY:
        raise ValueError("account deletion export authority is unsupported")

    if snapshot_reader_factory is None:
        from lexiquest_ai.firebase_account_deletion import (
            FirebaseOwnedAccountSnapshotReader,
        )

        snapshot_reader_factory = FirebaseOwnedAccountSnapshotReader.production
    object_store_factory = (
        object_store_factory or GcsImmutableExportObjectStore.production
    )
    snapshot_reader = snapshot_reader_factory(
        maximum_documents=settings.account_deletion_export_maximum_documents,
        maximum_bytes=settings.account_deletion_export_maximum_bytes,
    )
    object_store = object_store_factory(settings.account_deletion_export_bucket)
    if mac_authority is None:
        mac_authority = build_trusted_kms_mac_authority(
            settings, authority_factory=mac_authority_factory
        )
    if mac_authority is None:
        raise ValueError("account deletion KMS authority is unavailable")
    return KmsBackedServerCompleteAccountExportAuthority(
        snapshot_reader=snapshot_reader,
        object_store=object_store,
        mac_authority=mac_authority,
        retention=timedelta(
            seconds=settings.account_deletion_export_retention_seconds
        ),
        maximum_bytes=settings.account_deletion_export_maximum_bytes,
    )


def _client_receipt(receipt: FullExportReceipt) -> dict[str, object]:
    return {
        "ownerId": receipt.owner_id,
        "artifactId": receipt.artifact_id,
        "artifactSha256": receipt.artifact_sha256.lower(),
        "bytesWritten": receipt.bytes_written,
        "schemaVersion": receipt.schema_version,
        "coveredScopes": sorted(receipt.covered_scopes),
        "completedAtUtc": _utc_text(receipt.completed_at_utc),
    }


def _canonical_json(value: Mapping[str, object] | dict[str, object]) -> bytes:
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise ValueError("server export contains an unsupported value") from error


def _parse_utc(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None or parsed.utcoffset() != timedelta(0):
        raise ValueError("timestamp must be UTC")
    return parsed


def _utc_text(value: datetime) -> str:
    if value.tzinfo is None or value.utcoffset() != timedelta(0):
        raise ValueError("timestamp must be UTC")
    return value.isoformat().replace("+00:00", "Z")


def _require_identifier(value: str, label: str) -> str:
    normalized = value.strip()
    if (
        not normalized
        or value != normalized
        or "/" in normalized
        or len(normalized) > 128
        or any(
            character.isspace() or ord(character) < 0x20
            for character in value
        )
    ):
        raise ValueError(f"{label} is invalid")
    return normalized


def _object_name(value: str) -> str:
    prefix = f"{_OBJECT_PREFIX}/"
    if not value.startswith(prefix) or not value.endswith(".json"):
        raise ValueError("account deletion export object name is invalid")
    _require_identifier(value[len(prefix) : -len(".json")], "operation_id")
    return value


def _kms_key_version(value: str) -> str:
    normalized = value.strip()
    parts = normalized.split("/")
    if (
        len(parts) != 10
        or parts[0] != "projects"
        or parts[2] != "locations"
        or parts[4] != "keyRings"
        or parts[6] != "cryptoKeys"
        or parts[8] != "cryptoKeyVersions"
        or any(not part for part in parts[1::2])
    ):
        raise ValueError("Cloud KMS key version resource name is invalid")
    return normalized


def _crc32c(value: bytes) -> int:
    checksum = google_crc32c.Checksum()
    checksum.update(value)
    return int.from_bytes(checksum.digest(), "big")


def _recovery_key_message(idempotency_key: str) -> bytes:
    if _RECOVERY_KEY_PATTERN.fullmatch(idempotency_key) is None:
        raise ValueError("idempotency key is invalid")
    return _RECOVERY_PROOF_DOMAIN + idempotency_key.encode("utf-8")
