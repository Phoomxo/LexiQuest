# LexiQuest Voice API

Authenticated voice-design text-to-speech proof of concept for LexiQuest.
The service generates a locked teacher voice with OmniVoice. It does not
perform voice cloning.

## Architecture

The FastAPI HTTP layer depends on `SpeechEngine` and `TokenVerifier`
interfaces. Production uses OmniVoice and Firebase Admin; tests inject small
fakes, so the unit suite does not download a model or require a GPU.

Importing `lexiquest_voice.main` initializes Firebase, loads the pinned model,
and only then exports the ASGI application. A load failure prevents the
production process from serving traffic.

## Requirements

- Python 3.11
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
uv sync --project backend/voice_api --dev
uv pip install --python backend/voice_api/.venv/Scripts/python.exe -r backend/voice_api/requirements-omnivoice-cu128.txt
Copy-Item backend/voice_api/.env.example backend/voice_api/.env
$env:GOOGLE_APPLICATION_CREDENTIALS='C:\absolute\path\service-account.json'
```

Do not commit `.env`, service-account JSON, model weights, or generated audio.

Run the production application:

```powershell
uv run --project backend/voice_api uvicorn lexiquest_voice.main:app --host 127.0.0.1 --port 8000
```

## API

- `GET /health/live` reports that the HTTP process is live.
- `GET /health/ready` returns `200` only after the speech engine is loaded.
- `POST /v1/speech` verifies a Firebase ID token and returns WAV audio.

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
- The service accepts text only and returns generated WAV bytes; it does not
  store microphone recordings.
- There is no shared audio cache, deployment/autoscaling layer, or production
  cost control in this slice.
- Flutter `practice` fallback versus strict `researchEvaluation` behavior is
  separate work. Research evaluation must not silently fall back to native
  TTS.
- Existing Speech-to-Text exact matching is not pronunciation scoring.
