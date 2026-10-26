from __future__ import annotations

import hashlib
import hmac
import json
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from types import SimpleNamespace

import pytest
import google_crc32c
from google.api_core.exceptions import NotFound

import lexiquest_ai.gcp_account_export as gcp_account_export
from lexiquest_ai.account_deletion import ACCOUNT_DELETION_SCOPES, FullExportReceipt
from lexiquest_ai.config import Settings
from lexiquest_ai.gcp_account_export import (
    CloudKmsHmacSha256Authority,
    GcpAccountDeletionReadinessProbe,
    GcsImmutableExportObjectStore,
    ImmutableExportObject,
    KmsBackedServerCompleteAccountExportAuthority,
    KmsRecoveryKeyAuthority,
    MacSignature,
    TrustedKmsMacAuthority,
    build_gcp_account_deletion_readiness_probe,
    build_gcp_account_export_authority,
    build_trusted_kms_mac_authority,
)


NOW = datetime(2026, 10, 26, 10, 0, tzinfo=UTC)
OWNER = "owner-a"
UID = "firebase-user"
KEY = "delete:00000000-0000-4000-8000-000000000001"
OPERATION = "operation-0001"


class _Reader:
    def __init__(self) -> None:
        self.calls = 0
        self.fail = False

    def read_complete_snapshot(self, firebase_uid: str) -> dict[str, object]:
        self.calls += 1
        if self.fail:
            raise AssertionError(
                "existing exports must be verified before rereading data"
            )
        assert firebase_uid == UID
        return {
            "firebaseAuth": {"uid": UID, "emailVerified": True},
            "firestoreDocuments": [
                {"path": f"users/{UID}", "data": {"level": 4}}
            ],
        }


class _Objects:
    def __init__(self) -> None:
        self.values: dict[str, ImmutableExportObject] = {}
        self.create_calls = 0
        self.fail_after_create = False

    def read(self, object_name: str) -> ImmutableExportObject | None:
        return self.values.get(object_name)

    def create(
        self,
        *,
        object_name: str,
        contents: bytes,
        metadata: dict[str, str],
    ) -> ImmutableExportObject:
        self.create_calls += 1
        if object_name in self.values:
            raise RuntimeError("object already exists")
        stored = ImmutableExportObject(
            object_name=object_name,
            contents=contents,
            metadata=dict(metadata),
        )
        self.values[object_name] = stored
        if self.fail_after_create:
            self.fail_after_create = False
            raise TimeoutError("synthetic lost upload acknowledgement")
        return stored


class _Mac:
    key_version = (
        "projects/test/locations/global/keyRings/delete/cryptoKeys/receipt/"
        "cryptoKeyVersions/1"
    )
    secret = b"synthetic-test-key"

    def sign(self, message: bytes) -> MacSignature:
        return MacSignature(
            key_version=self.key_version,
            mac=hmac.new(self.secret, message, hashlib.sha256).digest(),
        )

    def verify(self, *, key_version: str, message: bytes, mac: bytes) -> bool:
        return key_version == self.key_version and hmac.compare_digest(
            mac,
            hmac.new(self.secret, message, hashlib.sha256).digest(),
        )


class _NamedMac(_Mac):
    def __init__(self, key_version: str, secret: bytes) -> None:
        self.key_version = key_version
        self.secret = secret


def _settings(**overrides) -> Settings:  # type: ignore[no-untyped-def]
    values = {
        "account_deletion_server_export_authority": (
            "gcp-kms-hmac-sha256-v1"
        ),
        "account_deletion_export_bucket": "private-delete-exports",
        "account_deletion_export_kms_key_version": _Mac.key_version,
        "account_deletion_export_retention_seconds": 7 * 24 * 3600,
        "account_deletion_recovery_retention_seconds": 7 * 24 * 3600,
    }
    values.update(overrides)
    return Settings(**values)


def _receipt(*, artifact_sha256: str = "a" * 64) -> FullExportReceipt:
    return FullExportReceipt(
        ownerId=OWNER,
        artifactId="lexiquest-account.json",
        artifactSha256=artifact_sha256,
        bytesWritten=1024,
        schemaVersion=10,
        coveredScopes=ACCOUNT_DELETION_SCOPES,
        completedAtUtc=NOW - timedelta(minutes=1),
    )


def _authority(
    reader: _Reader,
    objects: _Objects,
    mac: _Mac | None = None,
) -> KmsBackedServerCompleteAccountExportAuthority:
    return KmsBackedServerCompleteAccountExportAuthority(
        snapshot_reader=reader,
        object_store=objects,
        mac_authority=mac or _Mac(),
        retention=timedelta(days=7),
        now_utc=lambda: NOW,
    )


def _ensure(
    authority: KmsBackedServerCompleteAccountExportAuthority,
    *,
    owner_id: str = OWNER,
    firebase_uid: str = UID,
    idempotency_key: str = KEY,
    operation_id: str = OPERATION,
    receipt: FullExportReceipt | None = None,
) -> None:
    authority.ensure_complete_export(
        owner_id=owner_id,
        firebase_uid=firebase_uid,
        idempotency_key=idempotency_key,
        operation_id=operation_id,
        client_export_receipt=receipt or _receipt(),
    )


def test_creates_kms_authenticated_server_export_without_secret_metadata() -> None:
    reader = _Reader()
    objects = _Objects()

    _ensure(_authority(reader, objects))

    assert reader.calls == 1
    assert objects.create_calls == 1
    stored = next(iter(objects.values.values()))
    assert stored.object_name == f"account-deletion-exports/v1/{OPERATION}.json"
    payload = json.loads(stored.contents)
    assert payload["operationId"] == OPERATION
    assert payload["ownerId"] == OWNER
    assert payload["firebaseUid"] == UID
    assert payload["serverSnapshot"]["firebaseAuth"]["uid"] == UID
    assert payload["clientExportReceipt"]["artifactSha256"] == "a" * 64
    assert stored.metadata["payloadSha256"] == hashlib.sha256(
        stored.contents
    ).hexdigest()
    assert stored.metadata["macAlgorithm"] == "HMAC-SHA256"
    public_locator = (
        f"{stored.object_name}\n{json.dumps(stored.metadata, sort_keys=True)}"
    )
    assert KEY not in public_locator
    assert UID not in public_locator
    assert OWNER not in public_locator


def test_same_operation_replays_verified_object_without_rereading_cloud_data() -> None:
    reader = _Reader()
    objects = _Objects()
    authority = _authority(reader, objects)
    _ensure(authority)
    reader.fail = True

    _ensure(authority)

    assert reader.calls == 1
    assert objects.create_calls == 1


def test_trusted_old_kms_version_replays_after_active_key_rotation() -> None:
    old = _NamedMac(f"{_Mac.key_version[:-1]}1", b"old-synthetic-key")
    new = _NamedMac(f"{_Mac.key_version[:-1]}2", b"new-synthetic-key")
    old_keyring = TrustedKmsMacAuthority(
        active=old,
        trusted={old.key_version: old},
    )
    reader = _Reader()
    objects = _Objects()
    _ensure(_authority(reader, objects, old_keyring))
    reader.fail = True

    rotated = TrustedKmsMacAuthority(
        active=new,
        trusted={old.key_version: old, new.key_version: new},
    )
    _ensure(_authority(reader, objects, rotated))

    assert reader.calls == 1
    assert objects.create_calls == 1


def test_recovery_key_authority_stores_only_keyed_proof_and_trusts_allowlist() -> None:
    old = _NamedMac(f"{_Mac.key_version[:-1]}1", b"old-synthetic-key")
    new = _NamedMac(f"{_Mac.key_version[:-1]}2", b"new-synthetic-key")
    old_proof = KmsRecoveryKeyAuthority(
        TrustedKmsMacAuthority(active=old, trusted={old.key_version: old})
    ).issue(KEY)
    rotated = KmsRecoveryKeyAuthority(
        TrustedKmsMacAuthority(
            active=new,
            trusted={old.key_version: old, new.key_version: new},
        )
    )

    assert KEY.encode("utf-8") not in old_proof.mac
    assert rotated.verify(KEY, old_proof)
    assert not rotated.verify(f"{KEY[:-1]}2", old_proof)
    assert not rotated.verify(
        KEY,
        type(old_proof)(
            algorithm=old_proof.algorithm,
            key_version="projects/attacker/locations/global/keyRings/x/"
            "cryptoKeys/y/cryptoKeyVersions/1",
            mac=old_proof.mac,
        ),
    )


def test_lost_upload_acknowledgement_reconciles_the_created_object() -> None:
    reader = _Reader()
    objects = _Objects()
    objects.fail_after_create = True

    _ensure(_authority(reader, objects))

    assert objects.create_calls == 1
    assert len(objects.values) == 1


def test_kms_verification_failure_leaves_the_export_unconfirmed() -> None:
    class _RejectingMac(_Mac):
        def verify(
            self, *, key_version: str, message: bytes, mac: bytes
        ) -> bool:
            return False

    reader = _Reader()
    objects = _Objects()

    with pytest.raises(ValueError, match="MAC"):
        _ensure(_authority(reader, objects, _RejectingMac()))

    assert objects.create_calls == 1
    assert len(objects.values) == 1


def test_export_size_limit_fails_before_object_creation() -> None:
    reader = _Reader()
    objects = _Objects()
    authority = KmsBackedServerCompleteAccountExportAuthority(
        snapshot_reader=reader,
        object_store=objects,
        mac_authority=_Mac(),
        retention=timedelta(days=7),
        maximum_bytes=32,
        now_utc=lambda: NOW,
    )

    with pytest.raises(ValueError, match="size limit"):
        _ensure(authority)

    assert objects.create_calls == 0


@pytest.mark.parametrize(
    ("mutation", "match"),
    [
        (lambda stored: stored.metadata.__setitem__("receiptMac", "AAAA"), "MAC"),
        (
            lambda stored: stored.metadata.__setitem__("payloadSha256", "0" * 64),
            "digest",
        ),
        (
            lambda stored: object.__setattr__(
                stored, "contents", stored.contents + b"tampered"
            ),
            "digest",
        ),
        (
            lambda stored: stored.metadata.__setitem__(
                "kmsKeyVersion", f"{_Mac.key_version[:-1]}2"
            ),
            "MAC",
        ),
        (
            lambda stored: stored.metadata.__setitem__(
                "email", "must-not-be-public@example.test"
            ),
            "binding",
        ),
    ],
)
def test_existing_object_mismatch_fails_closed(mutation, match: str) -> None:
    reader = _Reader()
    objects = _Objects()
    authority = _authority(reader, objects)
    _ensure(authority)
    stored = next(iter(objects.values.values()))
    mutation(stored)

    with pytest.raises(ValueError, match=match):
        _ensure(authority)

    assert objects.create_calls == 1


def test_existing_object_is_bound_to_the_original_owner_and_client_receipt() -> None:
    reader = _Reader()
    objects = _Objects()
    authority = _authority(reader, objects)
    _ensure(authority)

    with pytest.raises(ValueError, match="binding"):
        _ensure(authority, owner_id="owner-b")
    with pytest.raises(ValueError, match="binding"):
        _ensure(authority, receipt=_receipt(artifact_sha256="b" * 64))
    with pytest.raises(ValueError, match="MAC"):
        _ensure(authority, idempotency_key=f"{KEY}-different")
    with pytest.raises(ValueError, match="binding"):
        _ensure(authority, firebase_uid="another-firebase-user")

    assert reader.calls == 1


def test_rejects_an_expired_existing_export() -> None:
    reader = _Reader()
    objects = _Objects()
    authority = _authority(reader, objects)
    _ensure(authority)

    expired = KmsBackedServerCompleteAccountExportAuthority(
        snapshot_reader=reader,
        object_store=objects,
        mac_authority=_Mac(),
        retention=timedelta(days=7),
        now_utc=lambda: NOW + timedelta(days=8),
    )

    with pytest.raises(ValueError, match="expired"):
        _ensure(expired)


@pytest.mark.parametrize(
    "overrides",
    [
        {"owner_id": " owner-a"},
        {"firebase_uid": "firebase-user\n"},
        {"operation_id": " operation-0001"},
        {"idempotency_key": "invalid recovery secret"},
    ],
)
def test_rejects_noncanonical_identifiers_before_reading_cloud_data(
    overrides: dict[str, str],
) -> None:
    reader = _Reader()
    objects = _Objects()

    with pytest.raises(ValueError):
        _ensure(_authority(reader, objects), **overrides)

    assert reader.calls == 0
    assert objects.create_calls == 0


def test_gcs_store_uses_create_only_generation_and_generation_pinned_read() -> None:
    class _Blob:
        def __init__(self) -> None:
            self.metadata: dict[str, str] = {}
            self.cache_control = None
            self.generation = 7
            self.contents = b"existing"
            self.upload_kwargs: dict[str, object] | None = None
            self.download_kwargs: dict[str, object] | None = None

        def reload(self) -> None:
            pass

        def download_as_bytes(self, **kwargs):  # type: ignore[no-untyped-def]
            self.download_kwargs = kwargs
            return self.contents

        def upload_from_string(
            self, contents: bytes, **kwargs  # type: ignore[no-untyped-def]
        ) -> None:
            self.contents = contents
            self.upload_kwargs = kwargs

    blob = _Blob()
    bucket = SimpleNamespace(name="private-export-bucket", blob=lambda _: blob)
    store = GcsImmutableExportObjectStore(bucket)

    existing = store.read("account-deletion-exports/v1/operation-1.json")
    created = store.create(
        object_name="account-deletion-exports/v1/operation-2.json",
        contents=b"new",
        metadata={"payloadSha256": "abc"},
    )

    assert existing is not None and existing.contents == b"existing"
    assert blob.download_kwargs == {"if_generation_match": 7}
    assert blob.upload_kwargs == {
        "content_type": "application/json; charset=utf-8",
        "if_generation_match": 0,
    }
    assert blob.cache_control == "no-store"
    assert created.contents == b"new"


def test_gcs_store_returns_none_only_for_not_found() -> None:
    class _MissingBlob:
        metadata = None

        def reload(self) -> None:
            raise NotFound("synthetic missing object")

    store = GcsImmutableExportObjectStore(
        SimpleNamespace(blob=lambda _: _MissingBlob())
    )

    assert store.read("account-deletion-exports/v1/missing.json") is None


def test_cloud_kms_authority_signs_and_verifies_with_the_configured_version() -> None:
    key_version = _Mac.key_version

    class _KmsClient:
        def __init__(self) -> None:
            self.sign_request = None
            self.verify_request = None
            self.verify_name = key_version

        def mac_sign(self, *, request):  # type: ignore[no-untyped-def]
            self.sign_request = request
            return SimpleNamespace(
                name=key_version,
                mac=b"s" * 32,
                mac_crc32c=_crc32c(b"s" * 32),
                verified_data_crc32c=True,
            )

        def mac_verify(self, *, request):  # type: ignore[no-untyped-def]
            self.verify_request = request
            return SimpleNamespace(
                name=self.verify_name,
                success=True,
                verified_data_crc32c=True,
                verified_mac_crc32c=True,
                verified_success_integrity=True,
            )

    client = _KmsClient()
    authority = CloudKmsHmacSha256Authority(
        client=client, key_version=key_version
    )

    signature = authority.sign(b"binding")
    assert signature == MacSignature(key_version=key_version, mac=b"s" * 32)
    assert authority.verify(
        key_version=key_version, message=b"binding", mac=b"s" * 32
    )
    assert client.sign_request == {
        "name": key_version,
        "data": b"binding",
        "data_crc32c": _crc32c(b"binding"),
    }
    assert client.verify_request == {
        "name": key_version,
        "data": b"binding",
        "data_crc32c": _crc32c(b"binding"),
        "mac": b"s" * 32,
        "mac_crc32c": _crc32c(b"s" * 32),
    }

    assert not authority.verify(
        key_version=f"{key_version[:-1]}2",
        message=b"binding",
        mac=b"s" * 32,
    )
    client.verify_name = f"{key_version[:-1]}2"
    assert not authority.verify(
        key_version=key_version, message=b"binding", mac=b"s" * 32
    )


def test_production_authority_composes_only_from_complete_default_off_config() -> None:
    calls: list[tuple[str, object]] = []

    assert (
        build_gcp_account_export_authority(
            Settings(),
            snapshot_reader_factory=lambda **kwargs: calls.append(
                ("reader", kwargs)
            ),
            object_store_factory=lambda bucket: calls.append(("store", bucket)),
            mac_authority_factory=lambda key: calls.append(("kms", key)),
        )
        is None
    )
    assert calls == []

    reader = _Reader()
    objects = _Objects()
    mac = _Mac()
    settings = Settings(
        account_deletion_enabled=False,
        account_deletion_server_export_authority="gcp-kms-hmac-sha256-v1",
        account_deletion_export_bucket="private-delete-exports",
        account_deletion_export_kms_key_version=mac.key_version,
        account_deletion_export_retention_seconds=7 * 24 * 3600,
        account_deletion_recovery_retention_seconds=7 * 24 * 3600,
        account_deletion_export_maximum_documents=123,
        account_deletion_export_maximum_bytes=456_789,
    )

    authority = build_gcp_account_export_authority(
        settings,
        snapshot_reader_factory=lambda **kwargs: (
            calls.append(("reader", kwargs)),
            reader,
        )[1],
        object_store_factory=lambda bucket: (
            calls.append(("store", bucket)),
            objects,
        )[1],
        mac_authority_factory=lambda key: (
            calls.append(("kms", key)),
            mac,
        )[1],
    )

    assert isinstance(authority, KmsBackedServerCompleteAccountExportAuthority)
    assert calls == [
        (
            "reader",
            {"maximum_documents": 123, "maximum_bytes": 456_789},
        ),
        ("store", "private-delete-exports"),
        ("kms", mac.key_version),
    ]


def test_trusted_kms_keyring_uses_exact_configured_version_allowlist() -> None:
    old_version = f"{_Mac.key_version[:-1]}1"
    active_version = f"{_Mac.key_version[:-1]}2"
    settings = _settings(
        account_deletion_export_kms_key_version=active_version,
        account_deletion_export_trusted_kms_key_versions=old_version,
    )
    calls: list[str] = []

    keyring = build_trusted_kms_mac_authority(
        settings,
        authority_factory=lambda version: (
            calls.append(version),
            _NamedMac(version, version.encode("utf-8")),
        )[1],
    )

    assert keyring is not None
    assert keyring.key_version == active_version
    assert keyring.trusted_key_versions == frozenset(
        {old_version, active_version}
    )
    assert calls == [active_version, old_version]
    assert not keyring.verify(
        key_version=f"{_Mac.key_version[:-1]}99",
        message=b"binding",
        mac=b"x" * 32,
    )


def test_readiness_probe_caches_complete_attestation_and_fails_closed() -> None:
    now = [100.0]
    calls: list[str] = []

    def check(name: str, result: bool = True):
        def run() -> bool:
            calls.append(name)
            return result

        return run

    probe = GcpAccountDeletionReadinessProbe(
        bucket_attestation=check("bucket"),
        kms_attestation=check("kms"),
        firestore_iam_attestation=check("firestore"),
        firebase_auth_iam_attestation=check("auth"),
        cache_ttl=timedelta(seconds=30),
        monotonic=lambda: now[0],
    )

    assert probe.is_ready()
    assert probe.is_ready()
    assert calls == ["bucket", "kms", "firestore", "auth"]
    now[0] += 31
    assert probe.is_ready()
    assert calls == [
        "bucket",
        "kms",
        "firestore",
        "auth",
        "bucket",
        "kms",
        "firestore",
        "auth",
    ]

    unavailable = GcpAccountDeletionReadinessProbe(
        bucket_attestation=check("bucket-down", False),
        kms_attestation=check("kms-never"),
        firestore_iam_attestation=check("firestore-never"),
        firebase_auth_iam_attestation=check("auth-never"),
    )
    assert not unavailable.is_ready()
    assert calls[-1] == "bucket-down"


def test_production_readiness_builder_attests_without_deleting_auth_user(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    active = _NamedMac(_Mac.key_version, b"synthetic-active-key")
    keyring = TrustedKmsMacAuthority(
        active=active, trusted={active.key_version: active}
    )
    calls: list[object] = []

    class _Bucket:
        iam_configuration = SimpleNamespace(
            public_access_prevention="enforced",
            uniform_bucket_level_access_enabled=True,
        )

        def reload(self) -> None:
            calls.append("bucket-reload")

        def test_iam_permissions(self, permissions):  # type: ignore[no-untyped-def]
            calls.append(tuple(permissions))
            return list(permissions)

    class _KmsClient:
        def get_crypto_key_version(self, request):  # type: ignore[no-untyped-def]
            calls.append(("kms", request["name"]))
            return SimpleNamespace(state=1, algorithm=32)

    class _Firestore:
        class _Reference:
            def get(self):  # type: ignore[no-untyped-def]
                calls.append("firestore-get")
                return SimpleNamespace(exists=False)

            def delete(self, *, option):  # type: ignore[no-untyped-def]
                calls.append(("firestore-delete", type(option).__name__))

        class _Query:
            def where(self, *, filter):  # type: ignore[no-untyped-def]
                calls.append(("firestore-query", type(filter).__name__))
                return self

            def limit(self, count: int):
                assert count == 1
                return self

            def get(self):  # type: ignore[no-untyped-def]
                return []

        def document(self, path: str):  # type: ignore[no-untyped-def]
            calls.append(("firestore", path))
            return self._Reference()

        def collection(self, name: str):  # type: ignore[no-untyped-def]
            calls.append(("firestore-collection", name))
            return self._Query()

    class _MissingUser(Exception):
        pass

    def missing_user(uid: str) -> None:
        calls.append(("auth-get", uid))
        raise _MissingUser

    def missing_user_delete(uid: str) -> None:
        calls.append(("auth-delete", uid))
        raise _MissingUser

    monkeypatch.setattr(
        gcp_account_export.firebase_auth,
        "delete_user",
        missing_user_delete,
    )
    probe = build_gcp_account_deletion_readiness_probe(
        _settings(),
        mac_authority=keyring,
        bucket_factory=lambda name: (
            calls.append(("bucket", name)),
            _Bucket(),
        )[1],
        kms_client_factory=_KmsClient,
        firestore_client_factory=_Firestore,
        auth_get_user=missing_user,
        auth_user_not_found_errors=(_MissingUser,),
    )

    assert probe is not None and probe.is_ready()
    assert ("bucket", "private-delete-exports") in calls
    assert ("kms", active.key_version) in calls
    assert ("firestore", "account_deletion_operations/__readiness__") in calls
    assert ("auth-get", "__lexiquest_account_deletion_readiness__") in calls
    assert ("auth-delete", "__lexiquest_account_deletion_readiness__") not in calls
    assert ("firestore-delete", "ExistsOption") in calls


def test_readiness_builder_is_default_off_without_side_effects() -> None:
    calls: list[str] = []
    assert (
        build_gcp_account_deletion_readiness_probe(
            Settings(),
            mac_authority=None,
            bucket_factory=lambda _: calls.append("bucket"),
            kms_client_factory=lambda: calls.append("kms"),
            firestore_client_factory=lambda: calls.append("firestore"),
            auth_get_user=lambda _: calls.append("auth"),
        )
        is None
    )
    assert calls == []


def _crc32c(value: bytes) -> int:
    checksum = google_crc32c.Checksum()
    checksum.update(value)
    return int.from_bytes(checksum.digest(), "big")
