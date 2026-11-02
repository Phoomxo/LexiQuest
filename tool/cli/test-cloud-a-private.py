"""Check only the approved private, synthetic Cloud A service.

The caller supplies an existing IAM ID token through a named process environment
variable. This tool never mints tokens or changes cloud resources.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import ssl
import subprocess
from dataclasses import dataclass
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import HTTPSHandler, HTTPRedirectHandler, ProxyHandler, Request, build_opener


PROJECT = "vocab-learning-app-219ef"
REGION = "us-central1"
SERVICE = "lexiquest-ai-api"
RUNTIME_ACCOUNT = f"lexiquest-ai-runtime@{PROJECT}.iam.gserviceaccount.com"
IMAGE_PREFIX = f"{REGION}-docker.pkg.dev/{PROJECT}/lexiquest-runtime/ai-api@sha256:"
MAX_RESPONSE_BYTES = 65536
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
ERROR_CODES = frozenset({
    "INVALID_ARGUMENTS", "OUTPUT_UNAVAILABLE", "GCLOUD_FAILED", "INVALID_METADATA",
    "PROJECT_MISMATCH", "BILLING_NOT_ENABLED", "SERVICE_MISMATCH", "INVALID_ORIGIN",
    "RUNTIME_ACCOUNT_MISMATCH", "IMAGE_NOT_PINNED", "SAFE_OFF_DRIFT", "PUBLIC_SERVICE",
    "SERVICE_NOT_READY", "IAM_TOKEN_UNAVAILABLE", "HTTP_FAILED", "TOKEN_REFLECTION",
    "RESPONSE_TOO_LARGE", "PROBE_CONTRACT_FAILED", "INTERRUPTED", "INTERNAL_ERROR",
})


class SmokeFailure(Exception):
    pass


@dataclass(frozen=True)
class ProbeCase:
    name: str
    method: str
    path: str
    iam: bool
    statuses: tuple[int, ...]
    code: str | None = None
    payload: bytes | None = None


PROBES = (
    ProbeCase("anonymous-live-denied", "GET", "/health/live", False, (401, 403)),
    ProbeCase("iam-live", "GET", "/health/live", True, (200,)),
    ProbeCase("provider-safe-off", "GET", "/health/ready", True, (503,), "PROVIDER_UNAVAILABLE"),
    ProbeCase("production-docs-disabled", "GET", "/docs", True, (404,)),
    ProbeCase("firebase-auth-required", "POST", "/v1/content", True, (401,), "UNAUTHENTICATED",
              b'{"text":"Synthetic cat.","kind":"sentence","cefr":"a1","language":"en"}'),
)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def http_request(request):
    opener = build_opener(ProxyHandler({}), HTTPSHandler(context=ssl.create_default_context()), NoRedirect())
    try:
        response = opener.open(request, timeout=20)
    except HTTPError as error:
        response = error
    with response:
        return response.status, response.read(MAX_RESPONSE_BYTES + 1), response.headers


def run_command(arguments):
    executable = shutil.which("gcloud.cmd" if os.name == "nt" else "gcloud")
    if executable is None:
        raise SmokeFailure("GCLOUD_FAILED")
    try:
        result = subprocess.run(
            [executable, *arguments], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8", timeout=30,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0,
        )
    except Exception:
        raise SmokeFailure("GCLOUD_FAILED") from None
    if result.returncode != 0:
        raise SmokeFailure("GCLOUD_FAILED")
    return result.stdout


def unique_object(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise ValueError()
        result[name] = value
    return result


def cloud_json(command, arguments):
    try:
        raw = command([*arguments, f"--project={PROJECT}", "--quiet", "--format=json"])
    except Exception:
        raise SmokeFailure("GCLOUD_FAILED") from None
    try:
        value = json.loads(raw, object_pairs_hook=unique_object)
        if not isinstance(value, dict):
            raise ValueError()
        return value
    except (ValueError, TypeError):
        raise SmokeFailure("INVALID_METADATA") from None


def validate_service(service):
    try:
        metadata = service["metadata"]
        status = service["status"]
        runtime = service["spec"]["template"]["spec"]
        if metadata["name"] != SERVICE or metadata["labels"]["cloud.googleapis.com/location"] != REGION:
            raise SmokeFailure("SERVICE_MISMATCH")
        generation = metadata.get("generation")
        if (type(generation) is not int or generation < 1
                or type(status.get("observedGeneration")) is not int
                or status["observedGeneration"] != generation):
            raise SmokeFailure("SERVICE_NOT_READY")
        if metadata.get("annotations", {}).get("run.googleapis.com/invoker-iam-disabled", "false") != "false":
            raise SmokeFailure("PUBLIC_SERVICE")
        origin = status["url"]
        if not isinstance(origin, str) or re.fullmatch(r"https://[a-z0-9]+(?:[a-z0-9.-]*[a-z0-9])?\.run\.app", origin) is None:
            raise SmokeFailure("INVALID_ORIGIN")
        if runtime["serviceAccountName"] != RUNTIME_ACCOUNT:
            raise SmokeFailure("RUNTIME_ACCOUNT_MISMATCH")
        containers = runtime["containers"]
        if not isinstance(containers, list) or len(containers) != 1:
            raise SmokeFailure("INVALID_METADATA")
        container = containers[0]
        if re.fullmatch(re.escape(IMAGE_PREFIX) + r"[0-9a-f]{64}", container["image"]) is None:
            raise SmokeFailure("IMAGE_NOT_PINNED")
        values = {}
        for entry in container["env"]:
            name = entry["name"]
            if name in values:
                raise SmokeFailure("SAFE_OFF_DRIFT")
            values[name] = entry.get("value", "") if "valueFrom" not in entry else None
        if any(values.get(name) != expected for name, expected in SAFE_OFF.items()):
            raise SmokeFailure("SAFE_OFF_DRIFT")
        revision = status["latestReadyRevisionName"]
        if (not isinstance(revision, str) or not revision.startswith(SERVICE + "-")
                or revision != status["latestCreatedRevisionName"]
                or not any(condition.get("type") == "Ready" and condition.get("status") == "True"
                           for condition in status["conditions"])):
            raise SmokeFailure("SERVICE_NOT_READY")
        traffic = status.get("traffic")
        if (not isinstance(traffic, list) or len(traffic) != 1 or not isinstance(traffic[0], dict)
                or traffic[0].get("revisionName") != revision
                or type(traffic[0].get("percent")) is not int or traffic[0]["percent"] != 100
                or "tag" in traffic[0]):
            raise SmokeFailure("SERVICE_NOT_READY")
        return origin
    except (KeyError, TypeError, AttributeError):
        raise SmokeFailure("INVALID_METADATA") from None


def validate_private_policy(policy):
    try:
        bindings = policy.get("bindings", [])
        if not isinstance(bindings, list):
            raise ValueError()
        for binding in bindings:
            members = binding["members"]
            if not isinstance(members, list) or any(not isinstance(member, str) for member in members):
                raise ValueError()
            if any(member in ("allUsers", "allAuthenticatedUsers") for member in members):
                raise SmokeFailure("PUBLIC_SERVICE")
    except (KeyError, TypeError, ValueError):
        raise SmokeFailure("INVALID_METADATA") from None


def probe(case, origin, token, http, receipt):
    headers = {"X-Serverless-Authorization": "Bearer " + token} if case.iam else {}
    if case.payload is not None:
        headers["Content-Type"] = "application/json"
    request = Request(origin + case.path, data=case.payload, headers=headers, method=case.method)
    receipt["httpProbesAttempted"] += 1
    try:
        status, body, response_headers = http(request)
    except Exception:
        raise SmokeFailure("HTTP_FAILED") from None
    if (not isinstance(body, bytes) or not isinstance(status, int) or isinstance(status, bool)
            or not 100 <= status <= 599):
        raise SmokeFailure("HTTP_FAILED")
    if token is not None and (token.encode() in body or any(
            token in str(name) or token in str(value) for name, value in response_headers.items())):
        raise SmokeFailure("TOKEN_REFLECTION")
    if len(body) > MAX_RESPONSE_BYTES:
        raise SmokeFailure("RESPONSE_TOO_LARGE")
    code = None
    if case.code is not None:
        try:
            candidate = json.loads(body, object_pairs_hook=unique_object)["detail"]["code"]
            if candidate in ("PROVIDER_UNAVAILABLE", "UNAUTHENTICATED"):
                code = candidate
        except (ValueError, TypeError, KeyError):
            pass
    receipt["checks"].append({"probe": case.name, "status": status, "code": code})
    if status not in case.statuses or code != case.code:
        raise SmokeFailure("PROBE_CONTRACT_FAILED")


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise SmokeFailure("INVALID_ARGUMENTS")


def main(argv=None, *, command=run_command, http=http_request, environment=None):
    receipt = {
        "schemaVersion": 1, "project": PROJECT, "region": REGION, "service": SERVICE,
        "privateSyntheticOnly": True, "providerAcceptance": False, "livePaidAcceptance": False,
        "researchAcceptance": False, "connectedTrialAcceptance": False,
        "result": "not-ready", "httpProbesAttempted": 0, "checks": [],
    }
    output = None
    failure = None
    try:
        parser = Parser(description=__doc__)
        parser.add_argument("--output-directory", required=True, type=Path)
        parser.add_argument("--iam-token-environment-variable", required=True)
        args = parser.parse_args(argv)
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,127}", args.iam_token_environment_variable) is None:
            raise SmokeFailure("INVALID_ARGUMENTS")
        try:
            args.output_directory.mkdir(parents=True, exist_ok=False)
        except OSError:
            raise SmokeFailure("OUTPUT_UNAVAILABLE") from None
        output = args.output_directory / "receipt.json"
        billing = cloud_json(command, ["billing", "projects", "describe", PROJECT])
        if billing.get("projectId") != PROJECT:
            raise SmokeFailure("PROJECT_MISMATCH")
        if billing.get("billingEnabled") is not True:
            raise SmokeFailure("BILLING_NOT_ENABLED")
        service = cloud_json(command, ["run", "services", "describe", SERVICE, f"--region={REGION}"])
        origin = validate_service(service)
        policy = cloud_json(command, ["run", "services", "get-iam-policy", SERVICE, f"--region={REGION}"])
        validate_private_policy(policy)
        probe(PROBES[0], origin, None, http, receipt)
        token = (os.environ if environment is None else environment).get(args.iam_token_environment_variable)
        if (not isinstance(token, str) or not 16 <= len(token) <= 16384
                or re.fullmatch(r"[A-Za-z0-9._~+/-]+={0,2}", token) is None):
            raise SmokeFailure("IAM_TOKEN_UNAVAILABLE")
        for case in PROBES[1:]:
            probe(case, origin, token, http, receipt)
        receipt["result"] = "passed"
    except SmokeFailure as error:
        failure = error.args[0] if error.args and error.args[0] in ERROR_CODES else "INTERNAL_ERROR"
    except KeyboardInterrupt:
        failure = "INTERRUPTED"
    except Exception:
        failure = "INTERNAL_ERROR"
    if failure is not None:
        receipt["failureCode"] = failure
    if output is not None:
        try:
            with output.open("x", encoding="utf-8") as handle:
                json.dump(receipt, handle, indent=2)
                handle.write("\n")
        except OSError:
            print("OUTPUT_UNAVAILABLE")
            return 1
    print(failure if failure is not None else "PRIVATE_SYNTHETIC_SMOKE_PASSED")
    return 1 if failure is not None else 0


if __name__ == "__main__":
    raise SystemExit(main())
