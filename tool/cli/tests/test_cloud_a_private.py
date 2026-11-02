import importlib.util
import io
import json
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError

import pytest


SCRIPT = Path(__file__).parents[1] / "test-cloud-a-private.py"
PROJECT = "vocab-learning-app-219ef"
TOKEN = "synthetic.iam-token.never-persist"
TOKEN_NAME = "SYNTHETIC_IAM_TOKEN"
ORIGIN = "https://lexiquest-ai-api-synthetic-uc.a.run.app"
IMAGE = f"us-central1-docker.pkg.dev/{PROJECT}/lexiquest-runtime/ai-api@sha256:" + "a" * 64
SAFE_OFF = {
    "LEXIQUEST_AI_ENVIRONMENT": "production",
    "LEXIQUEST_AI_ACCOUNT_DELETION_ENABLED": "false",
    "LEXIQUEST_AI_ACCOUNT_DELETION_SERVER_EXPORT_AUTHORITY": "",
    "LEXIQUEST_AI_BILLING_ENABLED": "false",
    "LEXIQUEST_AI_BILLING_MANAGED_CONTENT_REQUIRED": "false",
    "LEXIQUEST_AI_RESEARCH_ENABLED": "false",
    "LEXIQUEST_AI_CONTENT_REPORTS_ENABLED": "false",
    "LEXIQUEST_AI_LLM_MODEL": "",
    "LEXIQUEST_AI_FALLBACK_LLM_MODEL": "",
    "LEXIQUEST_AI_LLM_API_KEY": "",
    "LEXIQUEST_AI_FALLBACK_LLM_API_KEY": "",
    "LEXIQUEST_AI_GEMINI_KEYS": "",
}


def test_approved_private_cloud_smoke_tool_exists():
    assert SCRIPT.is_file(), "The approved private Cloud A smoke tool is missing"


@pytest.fixture
def smoke():
    assert SCRIPT.is_file(), "The approved private Cloud A smoke tool is missing"
    spec = importlib.util.spec_from_file_location("cloud_a_private_smoke", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class Environment(dict):
    def __init__(self, value=TOKEN):
        super().__init__({TOKEN_NAME: value})
        self.reads = []

    def get(self, key, default=None):
        self.reads.append(key)
        return super().get(key, default)


class Cloud:
    def __init__(self):
        self.calls = []
        self.billing = {"projectId": PROJECT, "billingEnabled": True}
        self.service = {
            "metadata": {"name": "lexiquest-ai-api", "generation": 1,
                         "labels": {"cloud.googleapis.com/location": "us-central1"}},
            "spec": {"template": {"spec": {
                "serviceAccountName": f"lexiquest-ai-runtime@{PROJECT}.iam.gserviceaccount.com",
                "containers": [{"image": IMAGE, "env": [{"name": k, "value": v} for k, v in SAFE_OFF.items()]}],
            }}},
            "status": {"url": ORIGIN, "observedGeneration": 1, "latestReadyRevisionName": "lexiquest-ai-api-00001-syn",
                       "latestCreatedRevisionName": "lexiquest-ai-api-00001-syn",
                       "conditions": [{"type": "Ready", "status": "True"}],
                       "traffic": [{"revisionName": "lexiquest-ai-api-00001-syn", "percent": 100}]},
        }
        self.policy = {"bindings": [{"role": "roles/run.invoker", "members": ["user:synthetic@example.invalid"]}]}

    def __call__(self, args):
        self.calls.append(tuple(args))
        if "billing" in args:
            return json.dumps(self.billing)
        if "get-iam-policy" in args:
            return json.dumps(self.policy)
        return json.dumps(self.service)


class Transport:
    def __init__(self):
        self.calls = []
        self.responses = [(403, b"private", {}), (200, b'{"status":"live"}', {}),
                          (503, b'{"detail":{"code":"PROVIDER_UNAVAILABLE"}}', {}),
                          (404, b'{"detail":"Not Found"}', {}),
                          (401, b'{"detail":{"code":"UNAUTHENTICATED"}}', {})]

    def __call__(self, request):
        self.calls.append(request)
        return self.responses[len(self.calls) - 1]


def invoke(smoke, tmp_path, *, cloud=None, http=None, environment=None):
    cloud = cloud if cloud is not None else Cloud()
    http = http if http is not None else Transport()
    environment = environment if environment is not None else Environment()
    output = tmp_path / "unique-receipt"
    exit_code = smoke.main(["--output-directory", str(output), "--iam-token-environment-variable", TOKEN_NAME],
                           command=cloud, http=http, environment=environment)
    receipt = json.loads((output / "receipt.json").read_text())
    return exit_code, receipt, cloud, http, environment


def test_fixed_private_probes_use_only_iam_header_and_sanitized_receipt(smoke, tmp_path, capsys):
    code, receipt, cloud, http, environment = invoke(smoke, tmp_path)
    assert code == 0
    assert receipt["result"] == "passed"
    assert receipt["privateSyntheticOnly"] is True
    assert all(receipt[key] is False for key in ("providerAcceptance", "livePaidAcceptance", "researchAcceptance", "connectedTrialAcceptance"))
    assert [check["status"] for check in receipt["checks"]] == [403, 200, 503, 404, 401]
    assert [check["code"] for check in receipt["checks"]] == [None, None, "PROVIDER_UNAVAILABLE", None, "UNAUTHENTICATED"]
    assert environment.reads == [TOKEN_NAME]
    assert len(cloud.calls) == 3
    assert all("--quiet" in args and "--format=json" in args and "--project=" + PROJECT in args for args in cloud.calls)
    assert [(req.method, req.full_url) for req in http.calls] == [
        ("GET", ORIGIN + "/health/live"), ("GET", ORIGIN + "/health/live"),
        ("GET", ORIGIN + "/health/ready"), ("GET", ORIGIN + "/docs"), ("POST", ORIGIN + "/v1/content")]
    assert not http.calls[0].headers
    for request in http.calls[1:]:
        headers = {key.lower(): value for key, value in request.header_items()}
        assert headers["x-serverless-authorization"] == "Bearer " + TOKEN
        assert "authorization" not in headers
    assert json.loads(http.calls[-1].data) == {"text": "Synthetic cat.", "kind": "sentence", "cefr": "a1", "language": "en"}
    persisted = (tmp_path / "unique-receipt" / "receipt.json").read_text() + capsys.readouterr().out
    assert TOKEN not in persisted
    assert ORIGIN not in persisted
    assert "headers" not in persisted and "body" not in persisted


def test_anonymous_denial_is_checked_before_reading_iam_token(smoke, tmp_path):
    http = Transport()

    class CheckedEnvironment(Environment):
        def get(self, key, default=None):
            assert len(http.calls) == 1
            return super().get(key, default)

    assert invoke(smoke, tmp_path, http=http, environment=CheckedEnvironment())[0] == 0


def test_effectively_public_service_stops_without_reading_iam_token(smoke, tmp_path):
    http = Transport()
    http.responses[0] = (200, b'{"status":"live"}', {})
    code, receipt, _, _, environment = invoke(smoke, tmp_path, http=http)
    assert code == 1 and receipt["failureCode"] == "PROBE_CONTRACT_FAILED"
    assert len(http.calls) == 1 and not environment.reads


@pytest.mark.parametrize("billing", [False, None, 1, "true", "false"])
def test_billing_requires_literal_true_before_service_token_or_http(smoke, tmp_path, billing):
    cloud = Cloud()
    cloud.billing["billingEnabled"] = billing
    code, receipt, cloud, http, environment = invoke(smoke, tmp_path, cloud=cloud)
    assert code == 1 and receipt["failureCode"] == "BILLING_NOT_ENABLED"
    assert len(cloud.calls) == 1
    assert not http.calls and not environment.reads
    assert receipt["checks"] == [] and receipt["httpProbesAttempted"] == 0


@pytest.mark.parametrize("mutation", ["project", "service", "region", "service_account", "image_tag", "image_project", "public", "public_authenticated", "iam_bypass", "ready_revision"])
def test_metadata_or_public_iam_drift_fails_before_reading_token(smoke, tmp_path, mutation):
    cloud = Cloud()
    container = cloud.service["spec"]["template"]["spec"]["containers"][0]
    if mutation == "project":
        cloud.billing["projectId"] = "other-project"
    elif mutation == "service":
        cloud.service["metadata"]["name"] = "other-service"
    elif mutation == "region":
        cloud.service["metadata"]["labels"]["cloud.googleapis.com/location"] = "asia-southeast1"
    elif mutation == "service_account":
        cloud.service["spec"]["template"]["spec"]["serviceAccountName"] = "other@example.invalid"
    elif mutation == "image_tag":
        container["image"] = IMAGE.split("@")[0] + ":latest"
    elif mutation == "image_project":
        container["image"] = IMAGE.replace(PROJECT, "other-project")
    elif mutation in ("public", "public_authenticated"):
        cloud.policy["bindings"][0]["members"].append("allUsers" if mutation == "public" else "allAuthenticatedUsers")
    elif mutation == "iam_bypass":
        cloud.service["metadata"]["annotations"] = {"run.googleapis.com/invoker-iam-disabled": "true"}
    else:
        cloud.service["status"]["latestCreatedRevisionName"] = "another-revision"
    code, receipt, _, http, environment = invoke(smoke, tmp_path, cloud=cloud)
    assert code == 1 and receipt["result"] == "not-ready"
    assert not http.calls and not environment.reads


@pytest.mark.parametrize("traffic", [None, [], [{"revisionName": "old-revision", "percent": 100}],
    [{"latestRevision": True, "percent": 100}],
    [{"revisionName": "lexiquest-ai-api-00001-syn", "percent": 50}, {"revisionName": "old-revision", "percent": 50}],
    [{"revisionName": "lexiquest-ai-api-00001-syn", "percent": 100, "tag": "old"}],
    [{"revisionName": "lexiquest-ai-api-00001-syn", "percent": "100"}]])
def test_only_the_checked_revision_can_receive_all_service_traffic(smoke, tmp_path, traffic):
    cloud = Cloud()
    cloud.service["status"]["traffic"] = traffic
    code, receipt, _, http, environment = invoke(smoke, tmp_path, cloud=cloud)
    assert code == 1 and receipt["failureCode"] == "SERVICE_NOT_READY"
    assert not http.calls and not environment.reads


@pytest.mark.parametrize("generation,observed", [(2, 1), (None, 1), (1, None), ("1", 1), (1, "1"), (True, True)])
def test_desired_safe_off_template_must_be_reconciled_before_any_http(smoke, tmp_path, generation, observed):
    cloud = Cloud()
    cloud.service["metadata"]["generation"] = generation
    cloud.service["status"]["observedGeneration"] = observed
    code, receipt, _, http, environment = invoke(smoke, tmp_path, cloud=cloud)
    assert code == 1 and receipt["failureCode"] == "SERVICE_NOT_READY"
    assert not http.calls and not environment.reads


@pytest.mark.parametrize("origin", ["http://x.run.app", "https://x.run.app.attacker.invalid", "https://user:password@x.run.app", "https://x.run.app:443", "https://x.run.app?token=x", "https://x.run.app#x", "https://x.run.app/path", "https://run.app", "https://x.run.app\n"])
def test_origin_is_exact_https_run_app_authority_before_token(smoke, tmp_path, origin):
    cloud = Cloud()
    cloud.service["status"]["url"] = origin
    code, _, _, http, environment = invoke(smoke, tmp_path, cloud=cloud)
    assert code == 1 and not http.calls and not environment.reads


@pytest.mark.parametrize("name", list(SAFE_OFF))
def test_safe_off_values_must_be_explicit_and_unchanged(smoke, tmp_path, name):
    cloud = Cloud()
    env = cloud.service["spec"]["template"]["spec"]["containers"][0]["env"]
    env[:] = [entry for entry in env if entry["name"] != name]
    code, _, _, http, environment = invoke(smoke, tmp_path, cloud=cloud)
    assert code == 1 and not http.calls and not environment.reads


@pytest.mark.parametrize("name,expected", list(SAFE_OFF.items()))
def test_present_name_only_env_uses_the_sdk_empty_default_only(smoke, tmp_path, name, expected):
    cloud = Cloud()
    env = cloud.service["spec"]["template"]["spec"]["containers"][0]["env"]
    next(entry for entry in env if entry["name"] == name).pop("value")
    code, _, _, http, environment = invoke(smoke, tmp_path, cloud=cloud)
    assert code == (0 if expected == "" else 1)
    if expected:
        assert not http.calls and not environment.reads


@pytest.mark.parametrize("mutation", ["true_flag", "model", "secret_reference", "duplicate"])
def test_changed_or_ambiguous_safe_off_values_fail_before_any_http(smoke, tmp_path, mutation):
    cloud = Cloud()
    env = cloud.service["spec"]["template"]["spec"]["containers"][0]["env"]
    entry = next(value for value in env if value["name"] == "LEXIQUEST_AI_RESEARCH_ENABLED")
    if mutation == "true_flag":
        entry["value"] = "true"
    elif mutation == "model":
        next(value for value in env if value["name"] == "LEXIQUEST_AI_LLM_MODEL")["value"] = "paid-model"
    elif mutation == "secret_reference":
        entry["valueFrom"] = {"secretKeyRef": {"name": "synthetic", "key": "latest"}}
    else:
        env.append(dict(entry))
    code, _, _, http, environment = invoke(smoke, tmp_path, cloud=cloud)
    assert code == 1 and not http.calls and not environment.reads


@pytest.mark.parametrize("token", [None, "", "short", TOKEN + "\r\nInjected: yes"])
def test_missing_or_unsafe_token_stops_after_anonymous_denial(smoke, tmp_path, token):
    code, receipt, _, http, environment = invoke(smoke, tmp_path, environment=Environment(token))
    assert code == 1 and receipt["failureCode"] == "IAM_TOKEN_UNAVAILABLE"
    assert len(http.calls) == 1 and environment.reads == [TOKEN_NAME]


@pytest.mark.parametrize("case", range(5))
def test_every_mandatory_probe_must_match(smoke, tmp_path, case):
    http = Transport()
    http.responses[case] = (202, b"unapproved response", {})
    code, receipt, _, _, _ = invoke(smoke, tmp_path, http=http)
    assert code == 1 and receipt["failureCode"] == "PROBE_CONTRACT_FAILED"
    assert len(http.calls) == case + 1


@pytest.mark.parametrize("where", ["body", "header", "error", "unknown_code"])
def test_token_reflection_or_exception_never_persists_secrets(smoke, tmp_path, capsys, where):
    http = Transport()
    if where == "error":
        def http(request):
            raise URLError(TOKEN)
    elif where == "body":
        http.responses[1] = (200, TOKEN.encode(), {})
    elif where == "header":
        http.responses[1] = (200, b"{}", {"Location": "https://example.invalid/" + TOKEN})
    else:
        http.responses[2] = (503, json.dumps({"detail": {"code": TOKEN}}).encode(), {})
    code, receipt, _, _, _ = invoke(smoke, tmp_path, http=http)
    assert code == 1
    assert receipt["failureCode"] in ("TOKEN_REFLECTION", "HTTP_FAILED")
    assert TOKEN not in (tmp_path / "unique-receipt" / "receipt.json").read_text() + capsys.readouterr().out


def test_gcloud_failure_is_opaque_and_does_not_read_token(smoke, tmp_path, capsys):
    def cloud(args):
        raise RuntimeError("secret-cloud-metadata-" + TOKEN)
    code, receipt, _, http, environment = invoke(smoke, tmp_path, cloud=cloud)
    assert code == 1 and receipt["failureCode"] == "GCLOUD_FAILED"
    assert not http.calls and not environment.reads
    assert "secret-cloud-metadata" not in (tmp_path / "unique-receipt" / "receipt.json").read_text() + capsys.readouterr().out


def test_output_directory_is_never_reused_or_overwritten(smoke, tmp_path):
    output = tmp_path / "unique-receipt"
    output.mkdir()
    sentinel = output / "receipt.json"
    sentinel.write_text("retain-existing-evidence")
    cloud, http, env = Cloud(), Transport(), Environment()
    assert smoke.main(["--output-directory", str(output), "--iam-token-environment-variable", TOKEN_NAME],
                      command=cloud, http=http, environment=env) == 1
    assert sentinel.read_text() == "retain-existing-evidence"
    assert not cloud.calls and not http.calls and not env.reads


def test_http_transport_rejects_redirects_and_bounds_tls_verified_reads(smoke, monkeypatch):
    observed = {}

    class Response(io.BytesIO):
        status = 302
        headers = {"Location": "https://attacker.invalid/"}

        def read(self, size):
            observed["limit"] = size
            return super().read(size)

    class Opener:
        def open(self, request, timeout):
            observed["timeout"] = timeout
            return Response(b"redirect")

    def build(*handlers):
        observed["handlers"] = handlers
        return Opener()

    monkeypatch.setattr(smoke, "build_opener", build)
    status, body, _ = smoke.http_request(smoke.Request(ORIGIN))
    assert status == 302 and body == b"redirect"
    assert 0 < observed["timeout"] <= 30 and observed["limit"] == 65537
    proxy = next(handler for handler in observed["handlers"] if isinstance(handler, smoke.ProxyHandler))
    assert proxy.proxies == {}
    tls = next(handler for handler in observed["handlers"] if isinstance(handler, smoke.HTTPSHandler))
    assert tls._context.check_hostname and tls._context.verify_mode == smoke.ssl.CERT_REQUIRED
    redirect = next(handler for handler in observed["handlers"] if isinstance(handler, smoke.NoRedirect))
    assert redirect.redirect_request(None, None, 302, "", {}, "https://attacker.invalid") is None


def test_http_error_body_is_checked_for_token_reflection(smoke, tmp_path, monkeypatch):
    class Opener:
        def open(self, request, timeout):
            body = TOKEN.encode() if request.has_header("X-serverless-authorization") else b"private"
            raise HTTPError(request.full_url, 403, "Denied", {}, io.BytesIO(body))
    monkeypatch.setattr(smoke, "build_opener", lambda *handlers: Opener())
    code, receipt, _, _, _ = invoke(smoke, tmp_path, http=smoke.http_request)
    assert code == 1 and receipt["failureCode"] == "TOKEN_REFLECTION"


def test_oversized_response_fails_without_persisting_body(smoke, tmp_path):
    http = Transport()
    http.responses[0] = (403, b"x" * 65537, {})
    code, receipt, _, _, _ = invoke(smoke, tmp_path, http=http)
    assert code == 1 and receipt["failureCode"] == "RESPONSE_TOO_LARGE"


def test_command_transport_discovers_windows_cmd_without_shell_or_secret_arguments(smoke, monkeypatch):
    observed = {}
    monkeypatch.setattr(smoke.os, "name", "nt")
    monkeypatch.setattr(smoke.shutil, "which", lambda name: observed.setdefault("discovery", name) and "C:/sdk/gcloud.cmd")

    def run(args, **kwargs):
        observed.update(args=args, kwargs=kwargs)
        return type("Result", (), {"returncode": 0, "stdout": "{}"})()

    monkeypatch.setattr(smoke.subprocess, "run", run)
    assert smoke.run_command(["billing", "projects", "describe", PROJECT, "--quiet"]) == "{}"
    assert observed["discovery"] == "gcloud.cmd"
    assert observed["args"][0] == "C:/sdk/gcloud.cmd"
    assert observed["kwargs"].get("shell", False) is False
    assert TOKEN not in repr(observed)
