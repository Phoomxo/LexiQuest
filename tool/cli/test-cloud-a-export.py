"""Run private Cloud A export cases with synthetic snapshots and runtime IAM.

This creates retained GCS exports. It never deletes exports or Firebase users,
inventories real account data, changes TTL, or enables a deployed feature.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID, uuid4


PROJECT = "vocab-learning-app-219ef"
REGION = "us-central1"
BUCKET = f"{PROJECT}-account-exports"
RUNTIME_ACCOUNT = f"lexiquest-ai-runtime@{PROJECT}.iam.gserviceaccount.com"
KMS_KEY = f"projects/{PROJECT}/locations/{REGION}/keyRings/lexiquest-accounts/cryptoKeys/account-export-mac"
PREFIX = "account-deletion-exports/v1/"
RETENTION_SECONDS = 604800
CASES = ("binding", "lost-ack", "precondition-race")
ROOT = Path(__file__).resolve().parents[2]
ERROR_CODES = frozenset({
    "INVALID_ARGUMENTS", "GCLOUD_FAILED", "INVALID_METADATA", "PROJECT_MISMATCH",
    "UNTRUSTED_ENDPOINT_CONFIGURATION",
    "BILLING_NOT_ENABLED", "BILLING_ACCOUNT_UNAVAILABLE", "INVALID_KEY_VERSION",
    "KEY_NOT_ENABLED_HMAC_SHA256", "DEFAULT_FIREBASE_APP_EXISTS", "SOURCE_MISMATCH",
    "OUTPUT_UNAVAILABLE", "INVALID_MANIFEST", "BUCKET_POLICY_MISMATCH",
    "READINESS_NOT_READY", "EXPORT_CASE_FAILED", "CLOUD_OPERATION_UNCERTAIN",
    "INTERRUPTED", "INTERNAL_ERROR",
})


class AcceptanceFailure(Exception):
    pass


def run_command(arguments):
    executable = shutil.which("gcloud.cmd" if os.name == "nt" else "gcloud")
    if executable is None:
        raise AcceptanceFailure("GCLOUD_FAILED")
    try:
        result = subprocess.run(
            [executable, *arguments, f"--project={PROJECT}", "--quiet"],
            capture_output=True, text=True, timeout=60, check=True,
            env={**os.environ,
                 "CLOUDSDK_API_ENDPOINT_OVERRIDES_CLOUDBILLING": "https://cloudbilling.googleapis.com/",
                 "CLOUDSDK_CORE_UNIVERSE_DOMAIN": "googleapis.com"},
        )
        return result.stdout
    except (OSError, subprocess.SubprocessError):
        raise AcceptanceFailure("GCLOUD_FAILED") from None


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate field")
        value[key] = item
    return value


def billing_gate(command):
    try:
        value = json.loads(command([
            "billing", "projects", "describe", PROJECT, "--format=json",
        ]), object_pairs_hook=unique_object)
    except AcceptanceFailure:
        raise
    except Exception:
        raise AcceptanceFailure("INVALID_METADATA") from None
    if not isinstance(value, dict):
        raise AcceptanceFailure("INVALID_METADATA")
    if value.get("projectId") != PROJECT:
        raise AcceptanceFailure("PROJECT_MISMATCH")
    if value.get("billingEnabled") is not True:
        raise AcceptanceFailure("BILLING_NOT_ENABLED")
    if not isinstance(value.get("billingAccountName"), str) or re.fullmatch(
        r"billingAccounts/[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}", value["billingAccountName"]
    ) is None:
        raise AcceptanceFailure("BILLING_ACCOUNT_UNAVAILABLE")


def validate_key_version(value):
    if not isinstance(value, str) or re.fullmatch(
        re.escape(KMS_KEY) + r"/cryptoKeyVersions/[1-9][0-9]*", value
    ) is None:
        raise AcceptanceFailure("INVALID_KEY_VERSION")
    return value


def runtime_credentials(command):
    from google.auth import impersonated_credentials
    from google.oauth2.credentials import Credentials

    token = command(["auth", "print-access-token"]).strip()
    if not token or len(token) > 16384 or re.fullmatch(r"[A-Za-z0-9._~+/-]+={0,2}", token) is None:
        raise AcceptanceFailure("GCLOUD_FAILED")
    return impersonated_credentials.Credentials(
        source_credentials=Credentials(token=token),
        target_principal=RUNTIME_ACCOUNT,
        target_scopes=["https://www.googleapis.com/auth/cloud-platform"],
        lifetime=900,
    )


def production_runtime(command, key_version):
    import firebase_admin
    from firebase_admin import auth
    from google.api_core.exceptions import PreconditionFailed
    from google.cloud import firestore, kms_v1, storage

    try:
        firebase_admin.get_app()
    except ValueError:
        pass
    else:
        raise AcceptanceFailure("DEFAULT_FIREBASE_APP_EXISTS")
    credentials = runtime_credentials(command)
    app = firebase_admin.initialize_app(
        credential=credentials, options={"projectId": PROJECT, "storageBucket": BUCKET},
    )
    sys.path.insert(0, str(ROOT / "backend" / "ai_api" / "src"))
    from lexiquest_ai import gcp_account_export as exports
    from lexiquest_ai.account_deletion import ACCOUNT_DELETION_SCOPES, FullExportReceipt
    from lexiquest_ai.config import Settings

    settings = Settings(
        _env_file=None,
        account_deletion_enabled=False,
        account_deletion_server_export_authority="gcp-kms-hmac-sha256-v1",
        account_deletion_export_bucket=BUCKET,
        account_deletion_export_kms_key_version=key_version,
        account_deletion_export_trusted_kms_key_versions="",
        account_deletion_export_retention_seconds=RETENTION_SECONDS,
        account_deletion_recovery_retention_seconds=RETENTION_SECONDS,
    )
    return SimpleNamespace(
        exports=exports, settings=settings, receipt_model=FullExportReceipt,
        scopes=ACCOUNT_DELETION_SCOPES,
        kms=kms_v1.KeyManagementServiceClient(credentials=credentials),
        bucket=storage.Client(project=PROJECT, credentials=credentials).bucket(BUCKET),
        firestore=firestore.Client(project=PROJECT, credentials=credentials),
        auth_get_user=lambda uid: auth.get_user(uid, app=app),
        auth_not_found=auth.UserNotFoundError, precondition_failed=PreconditionFailed,
        enabled_state=kms_v1.CryptoKeyVersion.CryptoKeyVersionState.ENABLED,
        hmac_algorithm=kms_v1.CryptoKeyVersion.CryptoKeyVersionAlgorithm.HMAC_SHA256,
    )


def validate_resources(runtime, key_version):
    key = runtime.kms.get_crypto_key_version(request={"name": key_version})
    if (key.name != key_version or key.state != runtime.enabled_state
            or key.algorithm != runtime.hmac_algorithm):
        raise AcceptanceFailure("KEY_NOT_ENABLED_HMAC_SHA256")
    bucket = runtime.bucket
    bucket.reload()
    expected_lifecycle = [{"action": {"type": "Delete"}, "condition": {
        "age": 7, "matchesPrefix": [PREFIX],
    }}]
    if (bucket.name != BUCKET or bucket.location != REGION.upper()
            or type(bucket.retention_period) is not int
            or bucket.retention_period != RETENTION_SECONDS
            or bucket.iam_configuration.public_access_prevention != "enforced"
            or bucket.iam_configuration.uniform_bucket_level_access_enabled is not True
            or bucket.default_event_based_hold is not False
            or bucket.versioning_enabled is not False
            or (bucket.soft_delete_policy.retention_duration_seconds is not None
                and (type(bucket.soft_delete_policy.retention_duration_seconds) is not int
                     or bucket.soft_delete_policy.retention_duration_seconds != 0))
            or list(bucket.lifecycle_rules) != expected_lifecycle):
        raise AcceptanceFailure("BUCKET_POLICY_MISMATCH")


def utc_text(value):
    return value.isoformat().replace("+00:00", "Z")


def source_pins():
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True,
        timeout=15, check=True,
    )
    head = result.stdout.strip()
    if re.fullmatch(r"[0-9a-f]{40}", head) is None:
        raise AcceptanceFailure("SOURCE_MISMATCH")
    backend = ROOT / "backend" / "ai_api"
    files = sorted((backend / "src" / "lexiquest_ai").rglob("*.py"))
    if len(files) != 23:
        raise AcceptanceFailure("SOURCE_MISMATCH")
    return {"observedGitHead": head, "immutable": {
        "runnerSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "runtimeFiles": {path.relative_to(backend).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in files},
        "uvLockSha256": hashlib.sha256((backend / "uv.lock").read_bytes()).hexdigest(),
    }}


def case_ids(run_id, case):
    namespace = f"synthetic-cloud-a-{UUID(run_id).hex}-{case}"
    return {"ownerId": namespace + "-owner", "firebaseUid": namespace + "-uid",
            "operationId": namespace + "-operation", "artifactId": namespace + "-receipt.json"}


def manifest_value(run_id, created, key_version, source):
    return {
        "schemaVersion": 1, "runId": run_id, "createdAtUtc": created,
        "syntheticOnly": True, "project": PROJECT, "region": REGION, "bucket": BUCKET,
        "kmsKeyVersion": key_version, "runtimePrincipal": RUNTIME_ACCOUNT,
        "retentionSeconds": RETENTION_SECONDS, "source": source,
        "cases": {case: case_ids(run_id, case) for case in CASES},
    }


def write_json(path, value, *, exclusive=False):
    temporary = path.with_name(path.name + ".pending-" + uuid4().hex)
    try:
        with temporary.open("x", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, allow_nan=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        if exclusive:
            os.link(temporary, path)
        else:
            os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def load_manifest(args, key_version, source, now):
    directory = args.resume_directory or args.output_directory
    try:
        if args.resume_directory is not None:
            if not directory.is_dir() or directory.is_symlink():
                raise AcceptanceFailure("INVALID_MANIFEST")
            path = directory / "manifest.json"
            if path.is_symlink() or path.stat().st_size > 32768:
                raise AcceptanceFailure("INVALID_MANIFEST")
            manifest = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
            run_id = manifest["runId"]
            if str(UUID(run_id)) != run_id or UUID(run_id).version != 4:
                raise ValueError("noncanonical UUID")
            created = datetime.fromisoformat(manifest["createdAtUtc"].replace("Z", "+00:00"))
            if (created.tzinfo is None or created.utcoffset() != timedelta(0)
                    or created > now or utc_text(created) != manifest["createdAtUtc"]):
                raise ValueError("invalid time")
            expected = manifest_value(run_id, utc_text(created), key_version, source)
            if json.dumps(manifest, sort_keys=True, allow_nan=False) != json.dumps(expected, sort_keys=True, allow_nan=False):
                raise AcceptanceFailure("INVALID_MANIFEST")
            return directory, manifest
        directory.mkdir(parents=True, exist_ok=False)
        manifest = manifest_value(str(uuid4()), utc_text(now), key_version, source)
        write_json(directory / "manifest.json", manifest, exclusive=True)
        return directory, manifest
    except AcceptanceFailure:
        raise
    except (KeyError, ValueError, TypeError):
        raise AcceptanceFailure("INVALID_MANIFEST") from None
    except OSError:
        raise AcceptanceFailure("OUTPUT_UNAVAILABLE") from None


class SyntheticSnapshot:
    def __init__(self, ids):
        self.ids = ids
        self.calls = 0

    def read_complete_snapshot(self, firebase_uid):
        if firebase_uid != self.ids["firebaseUid"]:
            raise AcceptanceFailure("EXPORT_CASE_FAILED")
        self.calls += 1
        return {"syntheticOnly": True, "inventorySource": "pure-in-memory-fixture",
                "fixtureId": self.ids["operationId"], "sample": {"word": "synthetic-cat"}}


class FaultView:
    def __init__(self, store, *, fault=None, precondition_failed=None, transform=None):
        self.store = store
        self.fault = fault
        self.precondition_failed = precondition_failed
        self.transform = transform
        self.injections = 0
        self.creates = 0

    def read(self, name):
        value = self.store.read(name)
        if self.fault == "stale-read" and self.injections == 0 and value is not None:
            self.injections += 1
            return None
        return self.transform(value) if self.transform and value is not None else value

    def create(self, **kwargs):
        self.creates += 1
        try:
            value = self.store.create(**kwargs)
        except Exception as error:
            if self.fault == "stale-read" and isinstance(error, self.precondition_failed):
                self.injections += 1
            raise
        if self.fault == "lost-ack":
            self.injections += 1
            raise TimeoutError("synthetic transport acknowledgement loss")
        return value


def export_authority(runtime, snapshot, store, mac):
    return runtime.exports.build_gcp_account_export_authority(
        runtime.settings, snapshot_reader_factory=lambda **kwargs: snapshot,
        object_store_factory=lambda name: store, mac_authority=mac,
    )


def fingerprint(runtime, store, object_name):
    value = store.read(object_name)
    if value is None:
        raise AcceptanceFailure("EXPORT_CASE_FAILED")
    blob = runtime.bucket.blob(object_name)
    blob.reload()
    created = blob.time_created
    if blob.generation is None or created is None or created.tzinfo is None:
        raise AcceptanceFailure("EXPORT_CASE_FAILED")
    earliest = created + timedelta(seconds=RETENTION_SECONDS)
    if blob.retention_expiration_time is not None:
        earliest = max(earliest, blob.retention_expiration_time)
    record = {"objectName": object_name, "generation": str(blob.generation),
              "payloadSha256": hashlib.sha256(value.contents).hexdigest(),
              "createdAtUtc": utc_text(created), "earliestDeletionEligibilityUtc": utc_text(earliest),
              "exportReceiptExpiresAtUtc": value.metadata["expiresAtUtc"],
              "retained": True, "deleted": False}
    return value, record


def require_rejection(authority, arguments):
    try:
        authority.ensure_complete_export(**arguments)
    except ValueError:
        return
    raise AcceptanceFailure("EXPORT_CASE_FAILED")


def run_export_cases(runtime, manifest, mac, receipt):
    store = runtime.exports.GcsImmutableExportObjectStore(runtime.bucket)
    for case in CASES:
        ids = manifest["cases"][case]
        recovery = "synthetic-recovery-" + hashlib.sha256(
            (manifest["runId"] + "/" + case).encode()
        ).hexdigest()
        client_receipt = runtime.receipt_model(
            ownerId=ids["ownerId"], artifactId=ids["artifactId"],
            artifactSha256=hashlib.sha256(ids["artifactId"].encode()).hexdigest(),
            bytesWritten=128, schemaVersion=1, coveredScopes=runtime.scopes,
            completedAtUtc=datetime.fromisoformat(manifest["createdAtUtc"].replace("Z", "+00:00")),
        )
        arguments = dict(owner_id=ids["ownerId"], firebase_uid=ids["firebaseUid"],
                         idempotency_key=recovery, operation_id=ids["operationId"],
                         client_export_receipt=client_receipt)
        snapshot = SyntheticSnapshot(ids)
        view = FaultView(store, fault="lost-ack" if case == "lost-ack" else None)
        authority = export_authority(runtime, snapshot, view, mac)
        authority.ensure_complete_export(**arguments)
        object_name = PREFIX + ids["operationId"] + ".json"
        before, retained = fingerprint(runtime, store, object_name)
        receipt["retainedArtifacts"].append(retained)
        calls = snapshot.calls
        creates = view.creates
        authority.ensure_complete_export(**arguments)
        if snapshot.calls != calls or view.creates != creates:
            raise AcceptanceFailure("EXPORT_CASE_FAILED")
        checks = {"case": case, "realGcsReadback": True, "replayWithoutSnapshot": True,
                  "lostAckInjectedAfterRealCreate": view.injections == 1,
                  "realPrecondition412AfterInjectedStaleRead": False,
                  "snapshotSource": "pure-in-memory-synthetic"}
        if case == "precondition-race":
            race = FaultView(store, fault="stale-read", precondition_failed=runtime.precondition_failed)
            export_authority(runtime, snapshot, race, mac).ensure_complete_export(**arguments)
            if race.injections != 2 or race.creates != 1:
                raise AcceptanceFailure("EXPORT_CASE_FAILED")
            checks["realPrecondition412AfterInjectedStaleRead"] = True
        if case == "binding":
            for field, value in (
                ("owner_id", ids["ownerId"] + "-mismatch"),
                ("firebase_uid", ids["firebaseUid"] + "-mismatch"),
                ("idempotency_key", recovery + "-mismatch"),
                ("client_export_receipt", client_receipt.model_copy(update={"artifact_sha256": "f" * 64})),
            ):
                changed = dict(arguments, **{field: value})
                if field == "owner_id":
                    changed["client_export_receipt"] = client_receipt.model_copy(update={"owner_id": value})
                require_rejection(authority, changed)
            corrupted = FaultView(store, transform=lambda value: replace(value, contents=value.contents + b"!"))
            require_rejection(export_authority(runtime, snapshot, corrupted, mac), arguments)
            def conflicting(value):
                contents = value.contents.replace(ids["firebaseUid"].encode(), (ids["firebaseUid"] + "-conflict").encode())
                metadata = dict(value.metadata, payloadSha256=hashlib.sha256(contents).hexdigest(), bytesWritten=str(len(contents)))
                return replace(value, contents=contents, metadata=metadata)
            conflict = FaultView(store, transform=conflicting)
            require_rejection(export_authority(runtime, snapshot, conflict, mac), arguments)
            expiry = datetime.fromisoformat(before.metadata["expiresAtUtc"].replace("Z", "+00:00"))
            expired = runtime.exports.KmsBackedServerCompleteAccountExportAuthority(
                snapshot_reader=snapshot, object_store=store, mac_authority=mac,
                retention=timedelta(seconds=RETENTION_SECONDS), now_utc=lambda: expiry + timedelta(seconds=1),
            )
            require_rejection(expired, arguments)
            if snapshot.calls != calls or view.creates != creates or corrupted.creates or conflict.creates:
                raise AcceptanceFailure("EXPORT_CASE_FAILED")
            checks.update(bindingMismatchRejected=True, corruptedReadViewRejected=True,
                          conflictingReadViewRejected=True, simulatedExpiryRejected=True,
                          actualObjectCorruption=False, actualLifecycleDeletion=False)
        after, after_record = fingerprint(runtime, store, object_name)
        if before != after or retained != after_record:
            raise AcceptanceFailure("EXPORT_CASE_FAILED")
        checks["generationAndContentsUnchanged"] = True
        receipt["checks"].append(checks)


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise AcceptanceFailure("INVALID_ARGUMENTS")


def main(argv=None, *, command=run_command, runtime_factory=production_runtime,
         source_factory=source_pins, now_utc=lambda: datetime.now(UTC)):
    receipt = {
        "schemaVersion": 1, "project": PROJECT, "region": REGION, "bucket": BUCKET,
        "attemptId": str(uuid4()),
        "runtimePrincipal": RUNTIME_ACCOUNT, "syntheticOnly": True,
        "result": "not-ready", "directRuntimeReadiness": False,
        "authDeletionAcceptance": False, "firestoreInventoryAcceptance": False,
        "ownerLostUpdateAcceptance": False, "leastPrivilegeAcceptance": False,
        "ttlAcceptance": False, "providerAcceptance": False, "paidAcceptance": False,
        "researchAcceptance": False, "actualLifecycleDeletionAcceptance": False,
        "checks": [], "retainedArtifacts": [],
        "retentionNotice": "No cleanup attempted. Eligibility after seven days does not prove lifecycle deletion.",
    }
    directory = None
    failure = None
    try:
        parser = Parser(description=__doc__)
        destination = parser.add_mutually_exclusive_group(required=True)
        destination.add_argument("--output-directory", type=Path)
        destination.add_argument("--resume-directory", type=Path)
        parser.add_argument("--kms-key-version")
        args = parser.parse_args(argv)
        if any(name in os.environ for name in (
            "STORAGE_EMULATOR_HOST", "API_ENDPOINT_OVERRIDE", "FIRESTORE_EMULATOR_HOST",
            "FIREBASE_AUTH_EMULATOR_HOST", "API_VERSION_OVERRIDE", "GOOGLE_CLOUD_UNIVERSE_DOMAIN",
            "CLOUDSDK_API_ENDPOINT_OVERRIDES_CLOUDBILLING", "CLOUDSDK_CORE_UNIVERSE_DOMAIN",
            "GOOGLE_SDK_PYTHON_LOGGING_SCOPE",
        )):
            raise AcceptanceFailure("UNTRUSTED_ENDPOINT_CONFIGURATION")
        billing_gate(command)
        key_version = validate_key_version(args.kms_key_version)
        source = source_factory()
        receipt["observedGitHead"] = source["observedGitHead"]
        directory, manifest = load_manifest(args, key_version, source["immutable"], now_utc())
        receipt.update(runId=manifest["runId"], manifest="manifest.json", kmsKeyVersion=key_version)
        runtime = runtime_factory(command, key_version)
        validate_resources(runtime, key_version)
        mac = runtime.exports.build_trusted_kms_mac_authority(
            runtime.settings, authority_factory=lambda version: runtime.exports.CloudKmsHmacSha256Authority(
                client=runtime.kms, key_version=version),
        )
        probe = runtime.exports.build_gcp_account_deletion_readiness_probe(
            runtime.settings, mac_authority=mac, bucket_factory=lambda name: runtime.bucket,
            kms_client_factory=lambda: runtime.kms, firestore_client_factory=lambda: runtime.firestore,
            auth_get_user=runtime.auth_get_user, auth_user_not_found_errors=(runtime.auth_not_found,),
        )
        if probe is None or probe.is_ready() is not True:
            raise AcceptanceFailure("READINESS_NOT_READY")
        receipt["directRuntimeReadiness"] = True
        run_export_cases(runtime, manifest, mac, receipt)
        receipt["result"] = "passed-synthetic-export-cases"
    except AcceptanceFailure as error:
        failure = error.args[0] if error.args and error.args[0] in ERROR_CODES else "INTERNAL_ERROR"
    except KeyboardInterrupt:
        failure = "INTERRUPTED"
    except Exception:
        failure = "CLOUD_OPERATION_UNCERTAIN" if directory is not None else "INTERNAL_ERROR"
    if failure is not None:
        receipt["failureCode"] = failure
        receipt["resumeRequired"] = directory is not None
        receipt["artifactInventoryComplete"] = False
    else:
        receipt["artifactInventoryComplete"] = True
    if directory is not None:
        try:
            write_json(directory / f"receipt-{receipt['attemptId']}.json", receipt, exclusive=True)
            write_json(directory / "receipt.json", receipt)
        except OSError:
            print("OUTPUT_UNAVAILABLE")
            return 1
    print(failure or "SYNTHETIC_EXPORT_CASES_PASSED")
    return 1 if failure is not None else 0


if __name__ == "__main__":
    raise SystemExit(main())
