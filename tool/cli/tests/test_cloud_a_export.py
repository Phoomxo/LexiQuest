from __future__ import annotations

import builtins
import hashlib
import hmac
import importlib.util
import json
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

import google_crc32c
import pytest
from google.api_core.exceptions import NotFound, PreconditionFailed
from google.cloud import kms_v1


SCRIPT = Path(__file__).parents[1] / "test-cloud-a-export.py"
ROOT = SCRIPT.parents[2]
sys.path.insert(0, str(ROOT / "backend" / "ai_api" / "src"))
from lexiquest_ai import gcp_account_export as exports
from lexiquest_ai.account_deletion import ACCOUNT_DELETION_SCOPES, FullExportReceipt
from lexiquest_ai.config import Settings

NOW = datetime(2026, 11, 2, 9, 0, tzinfo=UTC)
TOKEN = "synthetic-access-token.never-persist"


@pytest.fixture
def runner():
    spec = importlib.util.spec_from_file_location("cloud_a_export_acceptance", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def crc(value):
    return google_crc32c.value(value)


class Kms:
    def __init__(self, key_version):
        self.key_version = key_version
        self.calls = []
        self.state = kms_v1.CryptoKeyVersion.CryptoKeyVersionState.ENABLED
        self.algorithm = kms_v1.CryptoKeyVersion.CryptoKeyVersionAlgorithm.HMAC_SHA256

    def get_crypto_key_version(self, *, request):
        self.calls.append(("key", request))
        assert request == {"name": self.key_version}
        return SimpleNamespace(name=self.key_version, state=self.state, algorithm=self.algorithm)

    def mac_sign(self, *, request):
        self.calls.append(("sign", request))
        assert request["name"] == self.key_version
        assert request["data_crc32c"] == crc(request["data"])
        mac = hmac.new(b"synthetic-isolated-test-only", request["data"], hashlib.sha256).digest()
        return SimpleNamespace(name=self.key_version, mac=mac, verified_data_crc32c=True, mac_crc32c=crc(mac))

    def mac_verify(self, *, request):
        self.calls.append(("verify", request))
        assert request["name"] == self.key_version
        assert request["data_crc32c"] == crc(request["data"])
        assert request["mac_crc32c"] == crc(request["mac"])
        expected = hmac.new(b"synthetic-isolated-test-only", request["data"], hashlib.sha256).digest()
        return SimpleNamespace(name=self.key_version, success=hmac.compare_digest(expected, request["mac"]),
                               verified_data_crc32c=True, verified_mac_crc32c=True, verified_success_integrity=True)


class Blob:
    def __init__(self, bucket, name):
        self.bucket = bucket
        self.name = name
        self.metadata = None
        self.cache_control = None
        self.generation = None
        self.time_created = None
        self.retention_expiration_time = None

    def reload(self):
        self.bucket.reads.append(self.name)
        if self.name not in self.bucket.objects:
            raise NotFound("synthetic missing object")
        item = self.bucket.objects[self.name]
        self.generation = item["generation"]
        self.metadata = dict(item["metadata"])
        self.time_created = item["created"]
        self.retention_expiration_time = self.time_created + timedelta(days=7)

    def download_as_bytes(self, *, if_generation_match):
        assert if_generation_match == self.bucket.objects[self.name]["generation"]
        return self.bucket.objects[self.name]["contents"]

    def upload_from_string(self, contents, *, content_type, if_generation_match):
        assert if_generation_match == 0
        assert content_type == "application/json; charset=utf-8"
        assert self.cache_control == "no-store"
        assert self.name.startswith("account-deletion-exports/v1/synthetic-cloud-a-")
        assert self.bucket.before_write()
        self.bucket.upload_attempts += 1
        if self.name in self.bucket.objects:
            self.bucket.preconditions += 1
            raise PreconditionFailed("synthetic transport emulates actual GCS 412")
        self.bucket.objects[self.name] = {
            "contents": contents, "metadata": dict(self.metadata),
            "generation": self.bucket.upload_attempts, "created": NOW,
        }
        if self.bucket.uncertain:
            raise TimeoutError(TOKEN)


class Bucket:
    def __init__(self, runner):
        self.name = runner.BUCKET
        self.location = runner.REGION.upper()
        self.retention_period = runner.RETENTION_SECONDS
        self.iam_configuration = SimpleNamespace(public_access_prevention="enforced", uniform_bucket_level_access_enabled=True)
        self.default_event_based_hold = False
        self.versioning_enabled = False
        self.soft_delete_policy = SimpleNamespace(retention_duration_seconds=0)
        self.lifecycle_rules = [{"action": {"type": "Delete"}, "condition": {"age": 7, "matchesPrefix": [runner.PREFIX]}}]
        self.objects = {}
        self.reads = []
        self.upload_attempts = 0
        self.preconditions = 0
        self.before_write = lambda: False
        self.uncertain = False

    def reload(self):
        pass

    def test_iam_permissions(self, permissions):
        return permissions

    def blob(self, name):
        return Blob(self, name)


class Firestore:
    def __init__(self, before_write):
        self.before_write = before_write
        self.operations = []

    def document(self, path):
        assert path == "account_deletion_operations/__readiness__"
        self.operations.append(("document", path))
        return self

    def get(self):
        return []

    def collection(self, name):
        assert name == "categories"
        self.operations.append(("collection", name))
        return self

    def where(self, *, filter):
        assert filter.field_path == "uid"
        assert filter.value == "__lexiquest_account_deletion_readiness__"
        return self

    def limit(self, value):
        assert value == 1
        return self

    def delete(self, *, option):
        assert option._exists is False
        assert self.before_write()
        self.operations.append(("guarded-readiness-delete", False))


class Cloud:
    def __init__(self, runner, directory):
        self.runner = runner
        self.directory = directory
        self.calls = []
        self.runtime_calls = 0
        self.billing = {"projectId": runner.PROJECT, "billingEnabled": True,
                        "billingAccountName": "billingAccounts/ABC123-DEF456-789ABC"}
        self.key_version = runner.KMS_KEY + "/cryptoKeyVersions/7"
        self.bucket = Bucket(runner)
        self.bucket.before_write = lambda: (directory / "manifest.json").is_file()
        self.kms = Kms(self.key_version)
        self.firestore = Firestore(self.bucket.before_write)
        self.auth_calls = []
        self.observed_head = "7a1738e0a7ff00db6472ec7925cc76412c5d76d2"
        self.source_pins = {"runnerSha256": "a" * 64, "runtimeFiles": {"synthetic.py": "b" * 64}, "uvLockSha256": "c" * 64}

    def command(self, arguments):
        self.calls.append(arguments)
        if arguments == ["auth", "print-access-token"]:
            return TOKEN
        assert arguments == ["billing", "projects", "describe", self.runner.PROJECT, "--format=json"]
        return json.dumps(self.billing)

    def runtime(self, command, key_version):
        self.runtime_calls += 1
        assert key_version == self.key_version
        settings = Settings(
            account_deletion_server_export_authority="gcp-kms-hmac-sha256-v1",
            account_deletion_export_bucket=self.runner.BUCKET,
            account_deletion_export_kms_key_version=key_version,
            account_deletion_export_retention_seconds=604800,
            account_deletion_recovery_retention_seconds=604800,
        )
        class UserNotFound(Exception):
            pass
        def auth_get_user(uid):
            self.auth_calls.append(uid)
            assert uid == "__lexiquest_account_deletion_readiness__"
            raise UserNotFound()
        return SimpleNamespace(exports=exports, settings=settings, receipt_model=FullExportReceipt,
                               scopes=ACCOUNT_DELETION_SCOPES, bucket=self.bucket, kms=self.kms,
                               firestore=self.firestore, auth_get_user=auth_get_user,
                               auth_not_found=UserNotFound, precondition_failed=PreconditionFailed,
                               enabled_state=kms_v1.CryptoKeyVersion.CryptoKeyVersionState.ENABLED,
                               hmac_algorithm=kms_v1.CryptoKeyVersion.CryptoKeyVersionAlgorithm.HMAC_SHA256)

    def execute(self, *, resume=False, version=True):
        arguments = ["--resume-directory" if resume else "--output-directory", str(self.directory)]
        if version:
            arguments += ["--kms-key-version", self.key_version]
        return self.runner.main(arguments, command=self.command, runtime_factory=self.runtime,
                                source_factory=lambda: {"observedGitHead": self.observed_head, "immutable": self.source_pins},
                                now_utc=lambda: NOW)


@pytest.mark.parametrize("name", [
    "STORAGE_EMULATOR_HOST", "API_ENDPOINT_OVERRIDE", "FIRESTORE_EMULATOR_HOST",
    "FIREBASE_AUTH_EMULATOR_HOST", "API_VERSION_OVERRIDE", "GOOGLE_CLOUD_UNIVERSE_DOMAIN",
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_CLOUDBILLING", "CLOUDSDK_CORE_UNIVERSE_DOMAIN",
    "GOOGLE_SDK_PYTHON_LOGGING_SCOPE",
])
@pytest.mark.parametrize("value", ["", "http://synthetic.invalid:8080"])
def test_endpoint_overrides_stop_before_billing_credentials_and_writes(runner, tmp_path, monkeypatch, capsys, name, value):
    monkeypatch.setenv(name, value)
    cloud = Cloud(runner, tmp_path / "evidence")
    assert cloud.execute() == 1
    assert capsys.readouterr().out == "UNTRUSTED_ENDPOINT_CONFIGURATION\n"
    assert cloud.calls == []
    assert cloud.runtime_calls == 0
    assert not cloud.directory.exists()


def test_gcloud_uses_pinned_endpoint_and_universe_over_local_configuration(runner, monkeypatch):
    captured = {}
    monkeypatch.setattr(runner.shutil, "which", lambda name: "synthetic-gcloud")
    def command(*args, **kwargs):
        captured.update(kwargs)
        return SimpleNamespace(stdout="{}")
    monkeypatch.setattr(runner.subprocess, "run", command)
    assert runner.run_command(["billing", "projects", "describe", runner.PROJECT]) == "{}"
    assert captured["env"]["CLOUDSDK_API_ENDPOINT_OVERRIDES_CLOUDBILLING"] == "https://cloudbilling.googleapis.com/"
    assert captured["env"]["CLOUDSDK_CORE_UNIVERSE_DOMAIN"] == "googleapis.com"


def test_import_does_not_load_sdk_or_authenticate(monkeypatch):
    original = builtins.__import__
    calls = []
    def guarded(name, *args, **kwargs):
        assert not name.startswith(("google", "firebase", "lexiquest_ai"))
        calls.append(name)
        return original(name, *args, **kwargs)
    monkeypatch.setattr(builtins, "__import__", guarded)
    spec = importlib.util.spec_from_file_location("cloud_a_import_only", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert calls


@pytest.mark.parametrize("enabled", [False, "true", "false", 1, 0, None, [], {}])
def test_billing_nonliteral_true_stops_before_credentials_sdk_or_local_writes(runner, tmp_path, enabled, capsys):
    cloud = Cloud(runner, tmp_path / "must-not-exist")
    cloud.billing["billingEnabled"] = enabled
    assert cloud.execute(version=False) == 1
    assert capsys.readouterr().out == "BILLING_NOT_ENABLED\n"
    assert cloud.runtime_calls == 0
    assert not cloud.directory.exists()
    assert len(cloud.calls) == 1
    assert not cloud.bucket.objects
    assert not cloud.firestore.operations


@pytest.mark.parametrize("account", [None, "", "billingAccounts/fake", "ABC123-DEF456-789ABC", 123, True])
def test_billing_requires_actual_linked_account_before_credentials(runner, tmp_path, account, capsys):
    cloud = Cloud(runner, tmp_path / "no-output")
    cloud.billing["billingAccountName"] = account
    assert cloud.execute() == 1
    assert capsys.readouterr().out == "BILLING_ACCOUNT_UNAVAILABLE\n"
    assert cloud.runtime_calls == 0
    assert not cloud.directory.exists()


def test_missing_billing_account_and_wrong_project_stop_before_outputs(runner, tmp_path, capsys):
    cloud = Cloud(runner, tmp_path / "no-output")
    del cloud.billing["billingAccountName"]
    assert cloud.execute() == 1
    assert "BILLING_ACCOUNT_UNAVAILABLE" in capsys.readouterr().out
    cloud.billing["projectId"] = "other-project"
    assert cloud.execute() == 1
    assert "PROJECT_MISMATCH" in capsys.readouterr().out
    assert cloud.runtime_calls == 0
    assert not cloud.directory.exists()


@pytest.mark.parametrize("version", [None, "1", "latest", "/cryptoKeyVersions/1/extra", "/cryptoKeyVersions/0",
                                    "/cryptoKeyVersions/01", "/cryptoKeyVersions/-1", "/cryptoKeyVersions/1 "])
def test_key_version_is_canonical_fixed_resource_and_only_required_after_gate(runner, tmp_path, version, capsys):
    cloud = Cloud(runner, tmp_path / "no-output")
    arguments = ["--output-directory", str(cloud.directory)]
    if version is not None:
        arguments += ["--kms-key-version", runner.KMS_KEY + version if version.startswith("/") else version]
    assert runner.main(arguments, command=cloud.command, runtime_factory=cloud.runtime) == 1
    assert capsys.readouterr().out == "INVALID_KEY_VERSION\n"
    assert cloud.runtime_calls == 0
    assert not cloud.directory.exists()


@pytest.mark.parametrize("resource", ["project", "region", "key"])
def test_key_resource_cannot_escape_pins(runner, resource):
    version = runner.KMS_KEY + "/cryptoKeyVersions/7"
    version = version.replace({"project": runner.PROJECT, "region": runner.REGION, "key": "account-export-mac"}[resource], "other")
    with pytest.raises(runner.AcceptanceFailure, match="INVALID_KEY_VERSION"):
        runner.validate_key_version(version)


def test_real_export_factories_with_fake_transports_cover_cases_and_honest_evidence(runner, tmp_path, capsys):
    cloud = Cloud(runner, tmp_path / "evidence")
    assert cloud.execute() == 0
    assert capsys.readouterr().out == "SYNTHETIC_EXPORT_CASES_PASSED\n"
    manifest = json.loads((cloud.directory / "manifest.json").read_text())
    receipt = json.loads((cloud.directory / "receipt.json").read_text())
    assert receipt["directRuntimeReadiness"] is True
    assert len(cloud.bucket.objects) == 3
    assert cloud.bucket.upload_attempts == 4
    assert cloud.bucket.preconditions == 1
    assert len(receipt["retainedArtifacts"]) == 3
    assert cloud.auth_calls == ["__lexiquest_account_deletion_readiness__"]
    assert ("guarded-readiness-delete", False) in cloud.firestore.operations
    assert receipt["checks"][0]["simulatedExpiryRejected"] is True
    assert receipt["checks"][0]["actualObjectCorruption"] is False
    assert receipt["checks"][1]["lostAckInjectedAfterRealCreate"] is True
    assert receipt["checks"][2]["realPrecondition412AfterInjectedStaleRead"] is True
    assert all(item["generationAndContentsUnchanged"] for item in receipt["checks"])
    for key, value in receipt.items():
        if key.endswith("Acceptance"):
            assert value is False, key
    for name, value in cloud.bucket.objects.items():
        payload = json.loads(value["contents"])
        assert payload["serverSnapshot"]["syntheticOnly"] is True
        assert "firebaseAuth" not in payload["serverSnapshot"]
        assert "firestoreDocuments" not in payload["serverSnapshot"]
        assert payload["ownerId"].startswith("synthetic-cloud-a-")
        assert manifest["runId"].replace("-", "") in name
        assert "synthetic-recovery-" not in json.dumps(value["metadata"])
        assert "synthetic-recovery-" not in value["contents"].decode()
    evidence = "".join(path.read_text() for path in cloud.directory.iterdir())
    assert TOKEN not in evidence
    assert "synthetic-recovery-" not in evidence
    assert all(not value["deleted"] and value["retained"] for value in receipt["retainedArtifacts"])
    assert all(datetime.fromisoformat(value["earliestDeletionEligibilityUtc"].replace("Z", "+00:00")) == NOW + timedelta(days=7)
               for value in receipt["retainedArtifacts"])


def test_resume_reuses_operations_and_existing_exports(runner, tmp_path):
    cloud = Cloud(runner, tmp_path / "evidence")
    assert cloud.execute() == 0
    manifest_bytes = (cloud.directory / "manifest.json").read_bytes()
    original = dict(cloud.bucket.objects)
    cloud.observed_head = "d" * 40
    assert cloud.execute(resume=True) == 0
    assert (cloud.directory / "manifest.json").read_bytes() == manifest_bytes
    assert cloud.bucket.objects == original
    assert cloud.bucket.upload_attempts == 5
    receipt = json.loads((cloud.directory / "receipt.json").read_text())
    assert receipt["checks"][1]["lostAckInjectedAfterRealCreate"] is False
    assert receipt["artifactInventoryComplete"] is True
    assert receipt["observedGitHead"] == "d" * 40


def test_failed_resume_preserves_prior_immutable_acceptance_receipt(runner, tmp_path):
    cloud = Cloud(runner, tmp_path / "evidence")
    assert cloud.execute() == 0
    prior = (cloud.directory / "receipt.json").read_bytes()
    cloud.bucket.test_iam_permissions = lambda permissions: []
    assert cloud.execute(resume=True) == 1
    attempts = [path.read_bytes() for path in cloud.directory.glob("receipt-*.json")]
    assert prior in attempts
    assert len(attempts) == 2
    assert json.loads((cloud.directory / "receipt.json").read_text())["failureCode"] == "READINESS_NOT_READY"
    original = json.loads(prior)
    assert len(original["retainedArtifacts"]) == 3
    assert original["checks"][1]["lostAckInjectedAfterRealCreate"] is True


@pytest.mark.parametrize("pin", ["runtimeFiles", "runnerSha256", "uvLockSha256"])
def test_resume_rejects_runtime_runner_or_dependency_lock_drift(runner, tmp_path, pin):
    cloud = Cloud(runner, tmp_path / "evidence")
    assert cloud.execute() == 0
    cloud.source_pins[pin] = {"synthetic.py": "d" * 64} if pin == "runtimeFiles" else "d" * 64
    assert cloud.execute(resume=True) == 1
    assert cloud.runtime_calls == 1


def test_source_pins_follow_runtime_and_lock_without_pin_to_commit(runner, tmp_path, monkeypatch):
    runtime_root = tmp_path / "backend" / "ai_api"
    source_root = runtime_root / "src" / "lexiquest_ai"
    source_root.mkdir(parents=True)
    for index in range(23):
        (source_root / f"module_{index}.py").write_text("synthetic = True\n")
    (runtime_root / "uv.lock").write_text("synthetic isolated lock\n")
    monkeypatch.setattr(runner, "ROOT", tmp_path)
    head = ["a" * 40]
    monkeypatch.setattr(runner.subprocess, "run", lambda *a, **k: SimpleNamespace(stdout=head[0] + "\n"))
    before = runner.source_pins()
    head[0] = "b" * 40
    (tmp_path / "docs-only.txt").write_text("documentation commit")
    after = runner.source_pins()
    assert before["immutable"] == after["immutable"]
    assert before["observedGitHead"] != after["observedGitHead"]
    (source_root / "module_0.py").write_text("synthetic = False\n")
    assert runner.source_pins()["immutable"] != before["immutable"]
    (runtime_root / "uv.lock").write_text("changed synthetic lock\n")
    assert runner.source_pins()["immutable"]["uvLockSha256"] != before["immutable"]["uvLockSha256"]


@pytest.mark.parametrize("field", ["ownerId", "firebaseUid", "operationId", "artifactId"])
def test_resume_rejects_tampered_namespace_before_runtime(runner, tmp_path, field, capsys):
    cloud = Cloud(runner, tmp_path / "evidence")
    assert cloud.execute() == 0
    capsys.readouterr()
    path = cloud.directory / "manifest.json"
    manifest = json.loads(path.read_text())
    manifest["cases"]["binding"][field] = "real-user"
    path.write_text(json.dumps(manifest))
    assert cloud.execute(resume=True) == 1
    assert capsys.readouterr().out == "INVALID_MANIFEST\n"
    assert cloud.runtime_calls == 1
    assert cloud.bucket.upload_attempts == 4


@pytest.mark.parametrize("field,value", [("project", "other"), ("runtimePrincipal", "owner@example.invalid"),
                                        ("bucket", "other"), ("source", {}), ("retentionSeconds", 0),
                                        ("createdAtUtc", "2026-11-03T09:00:00Z"), ("runId", "invalid")])
def test_resume_rejects_manifest_resource_source_or_time_tampering(runner, tmp_path, field, value):
    cloud = Cloud(runner, tmp_path / "evidence")
    assert cloud.execute() == 0
    path = cloud.directory / "manifest.json"
    manifest = json.loads(path.read_text())
    manifest[field] = value
    path.write_text(json.dumps(manifest))
    assert cloud.execute(resume=True) == 1
    assert cloud.runtime_calls == 1


@pytest.mark.parametrize("attribute,value", [("retention_period", 0), ("retention_period", True),
                                            ("retention_period", 604801), ("location", "US"),
                                            ("default_event_based_hold", True), ("versioning_enabled", True),
                                            ("name", "another-bucket"), ("lifecycle_rules", [])])
def test_exact_bucket_policy_is_required_before_any_cloud_write(runner, tmp_path, attribute, value, capsys):
    cloud = Cloud(runner, tmp_path / "evidence")
    setattr(cloud.bucket, attribute, value)
    assert cloud.execute() == 1
    assert capsys.readouterr().out == "BUCKET_POLICY_MISMATCH\n"
    assert not cloud.bucket.objects
    assert not cloud.firestore.operations


@pytest.mark.parametrize("policy", ["public", "ubla", "soft-delete", "lifecycle-prefix", "lifecycle-age"])
def test_bucket_privacy_and_exact_lifecycle_cannot_drift(runner, tmp_path, policy):
    cloud = Cloud(runner, tmp_path / "evidence")
    if policy == "public":
        cloud.bucket.iam_configuration.public_access_prevention = "inherited"
    elif policy == "ubla":
        cloud.bucket.iam_configuration.uniform_bucket_level_access_enabled = False
    elif policy == "soft-delete":
        cloud.bucket.soft_delete_policy.retention_duration_seconds = 604800
    else:
        cloud.bucket.lifecycle_rules[0]["condition"]["matchesPrefix" if policy == "lifecycle-prefix" else "age"] = [""] if policy == "lifecycle-prefix" else 8
    assert cloud.execute() == 1
    assert not cloud.firestore.operations


@pytest.mark.parametrize("attribute,value", [("state", 2), ("algorithm", 1)])
def test_real_key_metadata_must_be_enabled_hmac_sha256(runner, tmp_path, attribute, value, capsys):
    cloud = Cloud(runner, tmp_path / "evidence")
    setattr(cloud.kms, attribute, value)
    assert cloud.execute() == 1
    assert capsys.readouterr().out == "KEY_NOT_ENABLED_HMAC_SHA256\n"
    assert not cloud.bucket.objects
    assert not cloud.firestore.operations


def test_uncertain_readback_keeps_manifest_then_resume_reconciles_same_object(runner, tmp_path, monkeypatch, capsys):
    cloud = Cloud(runner, tmp_path / "evidence")
    original = Blob.reload
    def unavailable_readback(blob):
        if blob.name in blob.bucket.objects:
            raise TimeoutError(TOKEN + " raw-exception-user-data")
        original(blob)
    monkeypatch.setattr(Blob, "reload", unavailable_readback)
    cloud.bucket.uncertain = True
    assert cloud.execute() == 1
    captured = capsys.readouterr().out
    assert captured == "CLOUD_OPERATION_UNCERTAIN\n"
    manifest_bytes = (cloud.directory / "manifest.json").read_bytes()
    assert len(cloud.bucket.objects) == 1
    receipt = json.loads((cloud.directory / "receipt.json").read_text())
    assert receipt["resumeRequired"] is True
    assert receipt["artifactInventoryComplete"] is False
    assert TOKEN not in json.dumps(receipt)
    assert "raw-exception-user-data" not in json.dumps(receipt)
    monkeypatch.setattr(Blob, "reload", original)
    cloud.bucket.uncertain = False
    assert cloud.execute(resume=True) == 0
    assert len(cloud.bucket.objects) == 3
    assert (cloud.directory / "manifest.json").read_bytes() == manifest_bytes


def test_existing_conflicting_object_is_rejected_without_replacement(runner, tmp_path, capsys):
    cloud = Cloud(runner, tmp_path / "evidence")
    assert cloud.execute() == 0
    capsys.readouterr()
    name = next(iter(cloud.bucket.objects))
    cloud.bucket.objects[name]["contents"] += b"synthetic conflicting contents"
    before = dict(cloud.bucket.objects[name])
    attempts = cloud.bucket.upload_attempts
    assert cloud.execute(resume=True) == 1
    assert capsys.readouterr().out == "CLOUD_OPERATION_UNCERTAIN\n"
    assert cloud.bucket.objects[name] == before
    assert cloud.bucket.upload_attempts == attempts


def test_runtime_impersonation_uses_fixed_principal_short_lifetime_no_adc(runner, monkeypatch):
    from google.auth import impersonated_credentials
    captured = {}
    def credentials(**kwargs):
        captured.update(kwargs)
        return "runtime-credential"
    monkeypatch.setattr(impersonated_credentials, "Credentials", credentials)
    monkeypatch.setattr("google.auth.default", lambda *a, **k: pytest.fail("ADC fallback forbidden"))
    assert runner.runtime_credentials(lambda arguments: TOKEN) == "runtime-credential"
    assert captured["source_credentials"].token == TOKEN
    assert captured["target_principal"] == runner.RUNTIME_ACCOUNT
    assert captured["lifetime"] == 900
    assert captured["target_scopes"] == ["https://www.googleapis.com/auth/cloud-platform"]


def test_production_clients_all_receive_explicit_runtime_credentials_and_project(runner, monkeypatch):
    import firebase_admin
    from firebase_admin import auth
    from google.cloud import firestore, storage
    credential = object()
    captured = {}
    def no_default():
        raise ValueError("no app")
    monkeypatch.setattr(firebase_admin, "get_app", no_default)
    monkeypatch.setattr(runner, "runtime_credentials", lambda command: credential)
    monkeypatch.setattr(firebase_admin, "initialize_app", lambda **kwargs: captured.setdefault("app", kwargs))
    monkeypatch.setattr(kms_v1, "KeyManagementServiceClient", lambda **kwargs: captured.setdefault("kms", kwargs))
    monkeypatch.setattr(firestore, "Client", lambda **kwargs: captured.setdefault("firestore", kwargs))
    def storage_client(**kwargs):
        captured["storage"] = kwargs
        return SimpleNamespace(bucket=lambda name: captured.setdefault("bucket", name))
    monkeypatch.setattr(storage, "Client", storage_client)
    monkeypatch.setattr(auth, "get_user", lambda uid, **kwargs: captured.setdefault("auth", (uid, kwargs)))
    runtime = runner.production_runtime(lambda arguments: pytest.fail("unexpected command"), runner.KMS_KEY + "/cryptoKeyVersions/7")
    runtime.auth_get_user("synthetic")
    assert captured["kms"] == {"credentials": credential}
    assert captured["firestore"] == captured["storage"] == {"project": runner.PROJECT, "credentials": credential}
    assert captured["app"] == {"credential": credential, "options": {"projectId": runner.PROJECT, "storageBucket": runner.BUCKET}}
    assert captured["bucket"] == runner.BUCKET
    assert captured["auth"][1]["app"] is captured["app"]


def test_preexisting_default_firebase_app_is_rejected(runner, monkeypatch):
    import firebase_admin
    monkeypatch.setattr(runner, "runtime_credentials", lambda command: pytest.fail("do not mint credentials for a preexisting app"))
    monkeypatch.setattr(firebase_admin, "get_app", lambda: object())
    monkeypatch.setattr(firebase_admin, "initialize_app", lambda **kwargs: pytest.fail("existing app must not be reused"))
    with pytest.raises(runner.AcceptanceFailure, match="DEFAULT_FIREBASE_APP_EXISTS"):
        runner.production_runtime(lambda args: pytest.fail("no cloud"), runner.KMS_KEY + "/cryptoKeyVersions/7")


def test_existing_output_directory_is_not_overwritten(runner, tmp_path):
    cloud = Cloud(runner, tmp_path / "evidence")
    cloud.directory.mkdir()
    (cloud.directory / "owner-file").write_text("preserve")
    assert cloud.execute() == 1
    assert cloud.runtime_calls == 0
    assert (cloud.directory / "owner-file").read_text() == "preserve"


def test_readiness_failure_never_claims_cloud_export_acceptance(runner, tmp_path):
    cloud = Cloud(runner, tmp_path / "evidence")
    cloud.bucket.test_iam_permissions = lambda permissions: []
    assert cloud.execute() == 1
    receipt = json.loads((cloud.directory / "receipt.json").read_text())
    assert receipt["failureCode"] == "READINESS_NOT_READY"
    assert receipt["directRuntimeReadiness"] is False
    assert not cloud.bucket.objects


def test_command_failure_never_prints_raw_errors(runner, tmp_path, capsys):
    def fail(arguments):
        raise TimeoutError(TOKEN)
    assert runner.main(["--output-directory", str(tmp_path / "unused")], command=fail) == 1
    assert capsys.readouterr().out == "INVALID_METADATA\n"
