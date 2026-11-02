# Run the AI API container

Build from `backend/ai_api` so the deny-all `.dockerignore` admits only the
dependency manifests and Python application source. The image uses Python 3.11,
the existing lockfile, and a source import through `PYTHONPATH=/app/src`.
It excludes the development and optional `llm` dependency groups. The content
adapter uses Python's standard HTTP client, so the optional client is unnecessary.

From the repository root, build a local image on an already running Linux Docker
engine. This command downloads the pinned public base images and locked packages.

```powershell
docker build --pull=false --tag lexiquest-ai-api:local backend/ai_api
```

The Dockerfile pins both official multi-platform image indexes. Registry
manifest inspection on 2026-11-02 returned these digests.

- `python:3.11-slim-bookworm@sha256:94a8fee35252d06ab75856f15f12c7bae67b10e8a6da93c7fded82b2610926cd`
- `ghcr.io/astral-sh/uv:0.11.8@sha256:3b7b60a81d3c57ef471703e5c83fd4aaa33abcd403596fb22ab07db85ae91347`

Refresh a digest only with a reviewed dependency change and new artifact checks.
The runtime starts one Uvicorn worker on `0.0.0.0`, uses `PORT` with default
`8080`, and runs as UID and GID `65532:65532`. More workers multiply the in-memory
cache and provider limiters. Scaling needs an explicit shared quota policy.

## Check a prebuilt local image without credentials

Create an evidence directory, then run the smoke script with that image.

```powershell
New-Item -ItemType Directory -Path D:/LexiQuest-Storage/maintenance/2026-11-02/commercial-readiness/ai-container -Force
./tool/cli/test-ai-api-container.ps1 -Image lexiquest-ai-api:local -EvidencePath D:/LexiQuest-Storage/maintenance/2026-11-02/commercial-readiness/ai-container/smoke.json
```

Use a new evidence path for each run. The script refuses remote Docker endpoints,
non-Linux engines, mismatched CPU architectures, root images, and image-declared
volumes. It never starts an engine, builds an image, or pulls an absent image.

The task container uses a unique ownership label, no network, no published ports,
a read-only filesystem, and writable `/tmp` only. It mounts no host files or
Application Default Credentials. Synthetic project settings disable billing,
research, reports, account deletion, and both LLM models. The script sends these
requests through `docker exec` to the container's loopback interface.

- `GET /health/live` returns `200` and `{"status":"live"}`.
- `GET /health/ready` returns `503` with `PROVIDER_UNAVAILABLE`.
- `GET /docs` returns `404` with production documentation disabled.
- `POST /v1/content` without a bearer token returns `401` with `UNAUTHENTICATED`.

The evidence records the immutable image ID, runtime user, package versions,
application import paths, absent test/GPU packages, and HTTP results. Cleanup
verifies the task label, container name, and image ID before removing only that
container. It preserves images and volumes. Failed checks return an error.

To check the script's context and cleanup guards without Docker, run this command.

```powershell
./tool/cli/test-ai-api-container.ps1 -SelfTest
```

## Keep deployment acceptance separate

This smoke check proves local container assembly and unavailable-provider behavior.
It does not prove provider reachability, Firebase credentials, managed quota,
Play purchase verification, or production readiness. `/health/ready` evaluates
provider configuration rather than making a paid generation request. In production,
the configured deletion readiness check can perform cloud infrastructure
attestation with write preconditions. Do not point this smoke script at a deployed
service or use a production readiness probe as an assumed read-only test.

Deployment requires reviewed runtime configuration, workload identity, provider
acceptance, billing/store acceptance, and separate rollout authorization. Keep
research enrollment and uploads disabled until their existing authority gates
are satisfied. Never put `.env`, service-account files, signing material, model
files, or user data in the build context or image.
