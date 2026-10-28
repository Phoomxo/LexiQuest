# LexiQuest Voice API

Provider-neutral backend boundary for LexiQuest standard target speech. It can
select VoxCPM2 or the retained OmniVoice rollback engine. An independently
disabled P8-C path can perform temporary VoxCPM2 voice mirroring for an
authenticated, separately consented session.

## Status

This is a research spike, not a completed backend. The only verified evidence
to date is:

- **`OmniVoiceEngine` CUDA synthesis**, exercised directly against the engine
  on an NVIDIA GeForce RTX 3050, producing a 24 kHz WAV with the locked
  research preset.
- **The FastAPI HTTP contract, exercised by fake-injected tests** that supply a
  `FakeTokenVerifier` and a `FakeSpeechEngine`.
- **The VoxCPM2 adapter contract, exercised with injected fakes** without
  downloading weights or claiming real GPU/model acceptance.
- **The temporary mirror lease/adapter contract, exercised with injected
  fakes** without retaining participant audio outside volatile worker memory.
- **Thai/English golden-set evaluation dataset & harness**, provided under `research/golden_texts.json` and `research/run_golden_set.py`.
- **Opt-in end-to-end integration test**, provided under `tests/integration/test_firebase_omnivoice_e2e.py`.

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
interfaces. Runtime wiring selects VoxCPM2 (default) or OmniVoice (explicit
rollback) and uses Firebase Admin. Tests inject small fakes, so the test suite
does not download a model or require a GPU.

`lexiquest_voice.main` assembles the production ASGI application: it builds a
`Settings`, a `FirebaseTokenVerifier`, and exactly one selected engine. When
`LEXIQUEST_VOICE_PROVIDER_ENABLED=false`, the process remains live but
readiness and synthesis fail closed with `PROVIDER_DISABLED`, and model weights
are not loaded. This assembly has not yet received real VoxCPM2 GPU acceptance.

## Requirements

- Python 3.10 through 3.12 (the repository lock uses Python 3.11)
- `uv`
- NVIDIA GPU and a driver compatible with the CUDA 12.8 PyTorch build
- Firebase service-account credentials or another supported Application
  Default Credentials source

The CUDA/GPU path was smoke-tested on this workstation on 2026-07-24 with
an NVIDIA GeForce RTX 3050. The pinned model produced a 24 kHz WAV response
through `OmniVoiceEngine` using the locked research preset.

## Setup

From the repository root:

```powershell
uv sync --project backend/voice_api --group voxcpm
Copy-Item backend/voice_api/.env.example backend/voice_api/.env
$env:GOOGLE_APPLICATION_CREDENTIALS='C:\absolute\path\service-account.json'
```

The `voxcpm` group pins `voxcpm==2.0.3` for
`openbmb/VoxCPM2`. Use `--group gpu` only for the retained OmniVoice CUDA
rollback. Do not use `--all-groups` in production.

Do not commit `.env`, service-account JSON, model weights, or generated audio.

Run the production application:

```powershell
uv run --project backend/voice_api uvicorn lexiquest_voice.main:app --host 127.0.0.1 --port 8000
```

## API

- `GET /health/live` reports that the HTTP process is live.
- `GET /health/ready` returns `200` only after the speech engine is loaded.
- `POST /v1/speech` verifies a Firebase ID token and returns WAV audio.
- `POST /v1/voice-mirror/sessions` enrolls bounded WAV bytes after separate
  versioned consent.
- `POST /v1/voice-mirror/sessions/{id}/heartbeat` renews the five-minute lease.
- `POST /v1/voice-mirror/sessions/{id}/speech` returns uncached mirror audio.
- `DELETE /v1/voice-mirror/sessions/{id}` withdraws and zeroes the session.

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
Firebase credentials, a GPU, VoxCPM2 weights, or the OmniVoice runtime.

## Runtime selection

| Environment variable | Default | Meaning |
| --- | --- | --- |
| `LEXIQUEST_VOICE_ENGINE_BACKEND` | `voxcpm2` | `voxcpm2` or `omnivoice` |
| `LEXIQUEST_VOICE_PROVIDER_ENABLED` | `true` | Provider kill switch |
| `LEXIQUEST_VOICE_VOXCPM_MODEL_ID` | `openbmb/VoxCPM2` | Server-owned model ID |
| `LEXIQUEST_VOICE_VOXCPM_MODEL_VERSION` | `2.0.3` | Response provenance |
| `LEXIQUEST_VOICE_MAX_CONCURRENT_REQUESTS` | `1` | Bounded server work |
| `LEXIQUEST_VOICE_MIRROR_ENABLED` | `false` | Independent mirror kill switch |
| `LEXIQUEST_VOICE_MIRROR_LEASE_SECONDS` | `300` | Renewable server lease |
| `LEXIQUEST_VOICE_MIRROR_ABSOLUTE_LIFETIME_SECONDS` | `1200` | Hard session lifetime |
| `LEXIQUEST_VOICE_MIRROR_MAX_REFERENCE_BYTES` | `2097152` | Enrollment byte ceiling |
| `LEXIQUEST_VOICE_MIRROR_MAX_REQUESTS` | `20` | Per-session request ceiling |
| `LEXIQUEST_VOICE_MIRROR_MAX_CHARACTERS` | `4000` | Per-session text ceiling |

## Locked research configuration

| Setting | Value |
| --- | --- |
| Model ID | `k2-fsa/OmniVoice` |
| OmniVoice package | `0.2.1` |
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
- Standard speech accepts text only. The optional mirror endpoint accepts one
  bounded WAV reference, keeps it in volatile session memory, writes a private
  randomized work file only during a model call, and removes/zeroes temporary
  state on expiry or deletion.
- Mirror sessions are owner-bound, uncached, non-exportable, non-restorable,
  leased for at most five minutes without heartbeat, and capped at twenty
  minutes absolutely.
- The worker does not persist mirror state to Firebase, Drift, analytics,
  backups, or a permanent voice profile.
- There is no shared audio cache, deployment/autoscaling layer, or production
  cost control in this slice.
- Flutter `practice` fallback versus strict `researchEvaluation` behavior is
  separate work. Research evaluation must not silently fall back to native
  TTS.
- Existing Speech-to-Text exact matching is not pronunciation scoring.
