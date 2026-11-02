# LexiQuest Voice API

Component-level backend proof of concept (POC) / spike for LexiQuest text to
speech. It targets a single locked "teacher" voice generated with OmniVoice and
does not perform voice cloning.

## Status

This is a research spike, not a completed backend. The only verified evidence
to date is:

- **`OmniVoiceEngine` CUDA synthesis on the former Torch 2.8 stack**,
  exercised directly against the engine on an NVIDIA GeForce RTX 3050 and
  producing a 24 kHz WAV with the locked research preset. This is historical
  evidence. The currently approved Torch 2.11.0+cu128 stack fails the security
  gate and cannot serve synthesis.
- **The FastAPI HTTP contract, exercised by fake-injected tests** that supply a
  `FakeTokenVerifier` and a `FakeSpeechEngine`.
- **Thai/English golden-set evaluation dataset & harness**, provided under `research/golden_texts.json` and `research/run_golden_set.py`.
- **Opt-in end-to-end integration test**, provided under `tests/integration/test_firebase_omnivoice_e2e.py`.

The metadata-only security gate requires Torch at least 2.13.0 and setuptools
at least 84.1.0 before the existing exact compatibility check. No
project-approved runtime currently satisfies both checks. Upstream candidates
exist, but changing package pins alone does not approve a new CUDA, driver and
OmniVoice combination. The [TorchAudio installation guide](https://docs.pytorch.org/audio/stable/installation.html)
and [PyTorch 2.13 release notes](https://pytorch.org/blog/pytorch-2-13-release-blog/)
describe the upstream ABI and CUDA changes to assess before a new GPU acceptance.

## Running Backend Tests & Research Evaluation

To run pytest backend tests:
```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests -q
```

To run the golden-set synthesis benchmark:
```powershell
uv run --project backend/voice_api python backend/voice_api/research/run_golden_set.py
```

## Architecture

The FastAPI HTTP layer depends on `SpeechEngine` and `TokenVerifier`
interfaces. The intended production wiring uses OmniVoice and Firebase Admin;
tests inject small fakes, so the test suite does not download a model or
require a GPU.

`lexiquest_voice.main` assembles the production ASGI application: it builds a
`Settings`, a `FirebaseTokenVerifier`, and an `OmniVoiceEngine`, loads the
engine, and exports the FastAPI app. A runtime-policy rejection leaves the
engine unready while HTTP liveness remains available. Readiness and authenticated
speech requests return `MODEL_UNAVAILABLE` with status503. Requests do not retry
the model load. Authentication and configured text limits are checked before
speech readiness. Unexpected startup failures still stop assembly.

CPU assembly tests use the real engine and metadata guard with synthetic
versions and heavy-import traps. They do not establish GPU synthesis, Firebase
service availability or physical-device audio acceptance.

## Requirements

- Python 3.11
- `uv`
- An accepted NVIDIA GPU, CUDA, driver and patched runtime combination before
  enabling synthesis
- Firebase service-account credentials or another supported Application
  Default Credentials source

The CUDA/GPU path was smoke-tested on this workstation on 2026-07-24 with
an NVIDIA GeForce RTX 3050 and the former Torch 2.8 stack. The pinned model
produced a 24 kHz WAV response through `OmniVoiceEngine` using the locked
research preset. That result is historical and does not verify the current
Torch/Torchaudio 2.11.0+cu128 pair.

## Setup

From the repository root:

```powershell
uv sync --project backend/voice_api --group dev
Copy-Item backend/voice_api/.env.example backend/voice_api/.env
$env:GOOGLE_APPLICATION_CREDENTIALS='C:\absolute\path\service-account.json'
```

This installs the CPU-safe service and test dependencies. The retained `gpu`
group describes the former approved CUDA 12.8 package set; its security rejection
must remain enabled. Do not deploy that group as a working synthesis runtime.
Approve a patched candidate only after actual model load, generated WAV,
driver/device and application acceptance checks. CPU tests cannot supply them.

Do not commit `.env`, service-account JSON, model weights, or generated audio.

Run the production application:

```powershell
uv run --project backend/voice_api uvicorn lexiquest_voice.main:app --host 127.0.0.1 --port 8000
```

## API

- `GET /health/live` reports that the HTTP process is live.
- `GET /health/ready` returns `200` only after the speech engine is loaded, or
  `503 MODEL_UNAVAILABLE` while runtime policy blocks loading.
- `POST /v1/speech` verifies a Firebase ID token and configured length first,
  then returns WAV audio when ready or `503 MODEL_UNAVAILABLE` without retrying
  an unavailable model.

Example request:

```http
POST /v1/speech HTTP/1.1
Authorization: Bearer <Firebase-ID-token>
Content-Type: application/json

{
  "text": "Cat",
  "language": "en",
  "voice": "teacher_female",
  "speed": 1.0
}
```

The response is `audio/wav` and includes `X-Request-ID`,
`X-Voice-Engine`, `X-Model-Version`, `X-Audio-Sample-Rate`, and
`Cache-Control: no-store`.

## Tests

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests -v
uv run --project backend/voice_api pytest backend/voice_api/tests --cov=lexiquest_voice --cov-report=term-missing
```

Tests inject `FakeTokenVerifier` and a `FakeSpeechEngine`, so they run without
Firebase credentials, a GPU, or the OmniVoice runtime.

## Locked research configuration

| Setting | Value |
| --- | --- |
| Model ID | `k2-fsa/OmniVoice` |
| OmniVoice package | `0.2.1` |
| Torch/Torchaudio | `2.11.0+cu128` |
| Hugging Face model revision | `c5fdb5ccb189668d56333f77ba2629f4cd7535f4` |
| Device | `cuda:0` |
| Sample rate | `24000` Hz |
| Voice instruction | `female, young adult, american accent, moderate pitch` |
| ASR loading | `false` |
| Generation steps | `32` |
| Guidance scale | `2.0` |
| Position/class temperature | `0.0` / `0.0` |

Environment variables use the `LEXIQUEST_VOICE_` prefix. Changing locked
values creates a different experimental condition and must be recorded in the
research protocol.

## POC boundaries

- Clients cannot choose model IDs or supply filesystem paths or audio URLs.
- The service accepts text only and returns generated WAV bytes; it does not
  store microphone recordings.
- There is no shared audio cache, deployment/autoscaling layer, or production
  cost control in this slice.
- Flutter `practice` fallback versus strict `researchEvaluation` behavior is
  separate work. Research evaluation must not silently fall back to native
  TTS.
- Existing Speech-to-Text exact matching is not pronunciation scoring.
