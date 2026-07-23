# OmniVoice Backend Proof of Concept Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a tested Python API that authenticates Firebase users and returns OmniVoice-generated WAV audio behind a replaceable speech-engine interface.

**Architecture:** Add an isolated FastAPI service under `backend/voice_api`. The HTTP layer depends on a `TokenVerifier` and `SpeechEngine` protocol so automated tests run without Firebase credentials, model downloads, or a GPU. The production adapter lazily loads OmniVoice with ASR disabled because the first release uses voice design rather than voice cloning.

**Tech Stack:** Python 3.11, uv, FastAPI, Pydantic v2, firebase-admin, pytest, HTTPX, OmniVoice 0.2.1, PyTorch 2.8/CUDA 12.8

## Execution Record

The implementation review made these intentional adjustments to the original
task snippets:

- Work was isolated on `feature/omnivoice-backend-poc`, based on the approved
  design commits from `feature/omnivoice-integration`.
- The Hugging Face weights are pinned to revision
  `c5fdb5ccb189668d56333f77ba2629f4cd7535f4`; generation steps, guidance,
  temperatures, sample rate, language, and voice instruction are forwarded
  explicitly for research reproducibility.
- Generation is serialized because concurrent calls into one GPU model are
  not assumed to be safe.
- `generation_timeout_seconds` was not shipped. A Python thread timeout cannot
  cancel an in-flight CUDA kernel and would give a false availability
  guarantee. A cancellable worker-process/job boundary is required before the
  design's `GENERATION_TIMEOUT` response can be implemented safely.
- Firebase decoding is injectable in unit tests, avoiding credentials and
  network access while still exercising success and rejection behavior.
- A real CUDA smoke test on 2026-07-24 exposed an unsupported free-form voice
  instruction. The locked preset was corrected to supported OmniVoice 0.2.1
  tokens (`female, young adult, american accent, moderate pitch`), validated
  at configuration load, and then verified by generating a 24 kHz WAV on an
  NVIDIA GeForce RTX 3050.

## Global Constraints

- Work on `feature/omnivoice-backend-poc`, based on the approved integration
  design branch.
- Do not implement voice cloning.
- Do not accept filesystem paths, audio URLs, or model names from clients.
- Do not commit Firebase credentials, API keys, model weights, generated audio, or raw microphone recordings.
- The first backend slice has no shared Firebase Storage/Firestore cache.
- `practice` versus `researchEvaluation` fallback policy remains a Flutter responsibility and is not implemented in this backend PR.
- Pin the research-facing engine identifier and model version in server configuration.
- Do not claim Speech-to-Text exact match is pronunciation scoring.
- Use Python 3.11; Python 3.14 is not the service runtime.
- Run all backend tests without loading OmniVoice or requiring a GPU.

---

## File Structure

```text
backend/
  voice_api/
    .env.example
    README.md
    pyproject.toml
    requirements-omnivoice-cu128.txt
    src/
      lexiquest_voice/
        __init__.py
        app.py
        auth.py
        config.py
        errors.py
        models.py
        engines/
          __init__.py
          base.py
          omnivoice_engine.py
    tests/
      conftest.py
      test_app.py
      test_auth.py
      test_models.py
      test_omnivoice_engine.py
```

Responsibilities:

- `config.py`: environment-backed immutable service settings.
- `models.py`: validated request and engine result types.
- `auth.py`: bearer-token parsing and Firebase verification boundary.
- `engines/base.py`: speech-engine protocol used by API and tests.
- `engines/omnivoice_engine.py`: lazy production adapter; no HTTP concerns.
- `app.py`: FastAPI app factory, health endpoints, authentication, and WAV response.
- `errors.py`: stable machine-readable API error payloads.

### Task 1: Package skeleton and settings

**Files:**
- Create: `backend/voice_api/pyproject.toml`
- Create: `backend/voice_api/.env.example`
- Create: `backend/voice_api/src/lexiquest_voice/__init__.py`
- Create: `backend/voice_api/src/lexiquest_voice/config.py`
- Test: `backend/voice_api/tests/test_models.py`

**Interfaces:**
- Produces: `Settings(model_id, model_version, device, voice_instruction, max_text_length, generation_timeout_seconds)`.
- Consumes: environment variables prefixed with `LEXIQUEST_VOICE_`.

- [ ] **Step 1: Write the failing settings test**

```python
from lexiquest_voice.config import Settings


def test_settings_have_research_safe_defaults() -> None:
    settings = Settings()

    assert settings.model_id == "k2-fsa/OmniVoice"
    assert settings.model_version == "0.2.1"
    assert settings.device == "cuda:0"
    assert settings.max_text_length == 500
    assert settings.generation_timeout_seconds == 30
    assert settings.load_asr is False
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests/test_models.py -v
```

Expected: FAIL because `pyproject.toml` and `lexiquest_voice.config` do not exist.

- [ ] **Step 3: Create the package and minimal settings**

`backend/voice_api/pyproject.toml`:

```toml
[project]
name = "lexiquest-voice-api"
version = "0.1.0"
requires-python = ">=3.11,<3.13"
dependencies = [
  "fastapi==0.116.1",
  "firebase-admin==7.1.0",
  "pydantic-settings==2.10.1",
  "uvicorn[standard]==0.35.0",
]

[dependency-groups]
dev = [
  "httpx==0.28.1",
  "pytest==8.4.1",
  "pytest-cov==6.2.1",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/lexiquest_voice"]

[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
addopts = "-ra"
```

`backend/voice_api/src/lexiquest_voice/config.py`:

```python
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="LEXIQUEST_VOICE_",
        env_file=".env",
        extra="ignore",
        frozen=True,
    )

    model_id: str = "k2-fsa/OmniVoice"
    model_version: str = "0.2.1"
    device: str = "cuda:0"
    voice_instruction: str = "female, young adult, american accent, moderate pitch"
    max_text_length: int = Field(default=500, ge=1, le=2000)
    generation_timeout_seconds: int = Field(default=30, ge=1, le=120)
    load_asr: bool = False
```

`backend/voice_api/.env.example`:

```dotenv
LEXIQUEST_VOICE_MODEL_ID=k2-fsa/OmniVoice
LEXIQUEST_VOICE_MODEL_VERSION=0.2.1
LEXIQUEST_VOICE_DEVICE=cuda:0
LEXIQUEST_VOICE_VOICE_INSTRUCTION=female, young adult, american accent, moderate pitch
LEXIQUEST_VOICE_MAX_TEXT_LENGTH=500
LEXIQUEST_VOICE_GENERATION_TIMEOUT_SECONDS=30
LEXIQUEST_VOICE_LOAD_ASR=false
```

Create empty `backend/voice_api/src/lexiquest_voice/__init__.py`.

- [ ] **Step 4: Run the settings test**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests/test_models.py -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add backend/voice_api/pyproject.toml backend/voice_api/.env.example backend/voice_api/src/lexiquest_voice/__init__.py backend/voice_api/src/lexiquest_voice/config.py backend/voice_api/tests/test_models.py uv.lock
git commit -m "build: scaffold voice API service"
```

### Task 2: Validated speech contract

**Files:**
- Create: `backend/voice_api/src/lexiquest_voice/models.py`
- Create: `backend/voice_api/src/lexiquest_voice/engines/__init__.py`
- Create: `backend/voice_api/src/lexiquest_voice/engines/base.py`
- Modify: `backend/voice_api/tests/test_models.py`

**Interfaces:**
- Produces: `SpeechRequest`, `AudioResult`, and `SpeechEngine.synthesize(request)`.
- Consumes: settings from Task 1 only at the HTTP boundary, not inside request models.

- [ ] **Step 1: Add failing request-validation tests**

```python
import pytest
from pydantic import ValidationError

from lexiquest_voice.models import SpeechRequest


def test_speech_request_normalizes_text() -> None:
    request = SpeechRequest(
        text="  The   cat is sleeping.  ",
        language="en",
        voice="teacher_female",
        speed=0.9,
    )

    assert request.text == "The cat is sleeping."


@pytest.mark.parametrize("speed", [0.49, 1.51])
def test_speech_request_rejects_unsafe_speed(speed: float) -> None:
    with pytest.raises(ValidationError):
        SpeechRequest(
            text="Cat",
            language="en",
            voice="teacher_female",
            speed=speed,
        )


def test_speech_request_rejects_client_model_selection() -> None:
    with pytest.raises(ValidationError):
        SpeechRequest.model_validate(
            {
                "text": "Cat",
                "language": "en",
                "voice": "teacher_female",
                "speed": 1.0,
                "model": "untrusted/model",
            }
        )
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests/test_models.py -v
```

Expected: FAIL because `SpeechRequest` is missing.

- [ ] **Step 3: Implement the contract**

`backend/voice_api/src/lexiquest_voice/models.py`:

```python
from dataclasses import dataclass
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class SpeechRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    text: Annotated[str, Field(min_length=1, max_length=500)]
    language: Literal["en", "th"]
    voice: Literal["teacher_female"]
    speed: Annotated[float, Field(ge=0.5, le=1.5)] = 1.0
    format: Literal["wav"] = "wav"

    @field_validator("text")
    @classmethod
    def normalize_whitespace(cls, value: str) -> str:
        return " ".join(value.split())


@dataclass(frozen=True, slots=True)
class AudioResult:
    data: bytes
    media_type: str
    sample_rate: int
    engine: str
    model_version: str
```

`backend/voice_api/src/lexiquest_voice/engines/base.py`:

```python
from typing import Protocol

from lexiquest_voice.models import AudioResult, SpeechRequest


class SpeechEngine(Protocol):
    def synthesize(self, request: SpeechRequest) -> AudioResult: ...
```

Create empty `backend/voice_api/src/lexiquest_voice/engines/__init__.py`.

- [ ] **Step 4: Run model tests**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests/test_models.py -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add backend/voice_api/src/lexiquest_voice/models.py backend/voice_api/src/lexiquest_voice/engines backend/voice_api/tests/test_models.py
git commit -m "feat: define speech generation contract"
```

### Task 3: Firebase bearer-token boundary

**Files:**
- Create: `backend/voice_api/src/lexiquest_voice/auth.py`
- Test: `backend/voice_api/tests/test_auth.py`

**Interfaces:**
- Produces: `TokenVerifier.verify(token: str) -> AuthenticatedUser`.
- Produces: `FirebaseTokenVerifier`, which initializes Firebase Admin using Application Default Credentials.
- Does not expose token contents in exceptions or logs.

- [ ] **Step 1: Write failing authentication tests**

```python
import pytest
from fastapi import HTTPException

from lexiquest_voice.auth import extract_bearer_token


def test_extract_bearer_token() -> None:
    assert extract_bearer_token("Bearer valid-token") == "valid-token"


@pytest.mark.parametrize(
    "header",
    [None, "", "Basic abc", "Bearer", "Bearer  "],
)
def test_extract_bearer_token_rejects_invalid_header(header: str | None) -> None:
    with pytest.raises(HTTPException) as error:
        extract_bearer_token(header)

    assert error.value.status_code == 401
    assert error.value.detail["code"] == "UNAUTHENTICATED"
```

- [ ] **Step 2: Run the authentication tests**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests/test_auth.py -v
```

Expected: FAIL because `lexiquest_voice.auth` is missing.

- [ ] **Step 3: Implement the auth boundary**

```python
from dataclasses import dataclass
from typing import Protocol

import firebase_admin
from fastapi import HTTPException
from firebase_admin import auth


@dataclass(frozen=True, slots=True)
class AuthenticatedUser:
    uid: str


class TokenVerifier(Protocol):
    def verify(self, token: str) -> AuthenticatedUser: ...


def extract_bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise _unauthenticated()

    scheme, separator, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not separator or not token.strip():
        raise _unauthenticated()
    return token.strip()


def _unauthenticated() -> HTTPException:
    return HTTPException(
        status_code=401,
        detail={
            "code": "UNAUTHENTICATED",
            "message": "A valid Firebase ID token is required.",
        },
        headers={"WWW-Authenticate": "Bearer"},
    )


class FirebaseTokenVerifier:
    def __init__(self) -> None:
        if not firebase_admin._apps:
            firebase_admin.initialize_app()

    def verify(self, token: str) -> AuthenticatedUser:
        try:
            decoded = auth.verify_id_token(token, check_revoked=True)
        except Exception as error:
            raise _unauthenticated() from error

        uid = decoded.get("uid")
        if not isinstance(uid, str) or not uid:
            raise _unauthenticated()
        return AuthenticatedUser(uid=uid)
```

- [ ] **Step 4: Run authentication tests**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests/test_auth.py -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add backend/voice_api/src/lexiquest_voice/auth.py backend/voice_api/tests/test_auth.py
git commit -m "feat: verify Firebase bearer tokens"
```

### Task 4: FastAPI app factory and authenticated WAV endpoint

**Files:**
- Create: `backend/voice_api/src/lexiquest_voice/errors.py`
- Create: `backend/voice_api/src/lexiquest_voice/app.py`
- Create: `backend/voice_api/tests/conftest.py`
- Test: `backend/voice_api/tests/test_app.py`

**Interfaces:**
- Consumes: `SpeechEngine`, `TokenVerifier`, `Settings`.
- Produces: `create_app(engine, token_verifier, settings) -> FastAPI`.
- Produces: `GET /health/live`, `GET /health/ready`, and authenticated `POST /v1/speech`.

- [ ] **Step 1: Write failing endpoint tests**

```python
from fastapi.testclient import TestClient


def test_health_endpoints(client: TestClient) -> None:
    assert client.get("/health/live").json() == {"status": "live"}
    assert client.get("/health/ready").json() == {"status": "ready"}


def test_speech_rejects_missing_token(client: TestClient) -> None:
    response = client.post(
        "/v1/speech",
        json={
            "text": "Cat",
            "language": "en",
            "voice": "teacher_female",
            "speed": 1.0,
        },
    )

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "UNAUTHENTICATED"


def test_speech_returns_wav_with_provenance_headers(
    client: TestClient,
) -> None:
    response = client.post(
        "/v1/speech",
        headers={"Authorization": "Bearer valid-token"},
        json={
            "text": "Cat",
            "language": "en",
            "voice": "teacher_female",
            "speed": 1.0,
        },
    )

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/wav"
    assert response.headers["x-voice-engine"] == "fake-omnivoice"
    assert response.headers["x-model-version"] == "test"
    assert response.content == b"RIFF-test-wav"
```

`conftest.py` must provide fakes:

```python
import pytest
from fastapi.testclient import TestClient

from lexiquest_voice.app import create_app
from lexiquest_voice.auth import AuthenticatedUser
from lexiquest_voice.config import Settings
from lexiquest_voice.models import AudioResult, SpeechRequest


class FakeTokenVerifier:
    def verify(self, token: str) -> AuthenticatedUser:
        assert token == "valid-token"
        return AuthenticatedUser(uid="test-user")


class FakeSpeechEngine:
    def synthesize(self, request: SpeechRequest) -> AudioResult:
        return AudioResult(
            data=b"RIFF-test-wav",
            media_type="audio/wav",
            sample_rate=24_000,
            engine="fake-omnivoice",
            model_version="test",
        )


@pytest.fixture
def client() -> TestClient:
    app = create_app(
        engine=FakeSpeechEngine(),
        token_verifier=FakeTokenVerifier(),
        settings=Settings(),
    )
    return TestClient(app)
```

- [ ] **Step 2: Run the API tests**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests/test_app.py -v
```

Expected: FAIL because `create_app` is missing.

- [ ] **Step 3: Implement the app factory**

```python
from uuid import uuid4

from fastapi import FastAPI, Header
from fastapi.responses import Response

from lexiquest_voice.auth import (
    FirebaseTokenVerifier,
    TokenVerifier,
    extract_bearer_token,
)
from lexiquest_voice.config import Settings
from lexiquest_voice.engines.base import SpeechEngine
from lexiquest_voice.models import SpeechRequest


def create_app(
    *,
    engine: SpeechEngine,
    token_verifier: TokenVerifier,
    settings: Settings,
) -> FastAPI:
    app = FastAPI(title="LexiQuest Voice API", version="0.1.0")

    @app.get("/health/live")
    def live() -> dict[str, str]:
        return {"status": "live"}

    @app.get("/health/ready")
    def ready() -> dict[str, str]:
        return {"status": "ready"}

    @app.post("/v1/speech")
    def synthesize(
        request: SpeechRequest,
        authorization: str | None = Header(default=None),
    ) -> Response:
        token = extract_bearer_token(authorization)
        token_verifier.verify(token)
        audio = engine.synthesize(request)
        return Response(
            content=audio.data,
            media_type=audio.media_type,
            headers={
                "X-Request-ID": str(uuid4()),
                "X-Voice-Engine": audio.engine,
                "X-Model-Version": audio.model_version,
                "X-Audio-Sample-Rate": str(audio.sample_rate),
                "Cache-Control": "no-store",
            },
        )

    return app
```

Production assembly is deferred until Task 5 so importing `app.py` never loads the model.

- [ ] **Step 4: Run API and full backend tests**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add backend/voice_api/src/lexiquest_voice/app.py backend/voice_api/src/lexiquest_voice/errors.py backend/voice_api/tests/conftest.py backend/voice_api/tests/test_app.py
git commit -m "feat: add authenticated speech endpoint"
```

### Task 5: Lazy OmniVoice adapter

**Files:**
- Create: `backend/voice_api/src/lexiquest_voice/engines/omnivoice_engine.py`
- Create: `backend/voice_api/requirements-omnivoice-cu128.txt`
- Test: `backend/voice_api/tests/test_omnivoice_engine.py`

**Interfaces:**
- Consumes: `Settings`, `SpeechRequest`.
- Produces: `OmniVoiceEngine.synthesize(request) -> AudioResult`.
- Injects `model_loader` and `wav_writer` in tests so CI does not import Torch or download model weights.

- [ ] **Step 1: Write failing adapter tests**

```python
from io import BytesIO

import numpy as np

from lexiquest_voice.config import Settings
from lexiquest_voice.engines.omnivoice_engine import OmniVoiceEngine
from lexiquest_voice.models import SpeechRequest


class FakeModel:
    def __init__(self) -> None:
        self.calls: list[dict[str, object]] = []

    def generate(self, **kwargs: object) -> list[np.ndarray]:
        self.calls.append(kwargs)
        return [np.zeros(2400, dtype=np.float32)]


def test_engine_loads_model_once_and_forwards_locked_configuration() -> None:
    fake_model = FakeModel()
    load_count = 0

    def loader(settings: Settings) -> FakeModel:
        nonlocal load_count
        load_count += 1
        assert settings.load_asr is False
        return fake_model

    def writer(buffer: BytesIO, audio: np.ndarray, sample_rate: int) -> None:
        assert sample_rate == 24_000
        buffer.write(b"RIFF-test")

    engine = OmniVoiceEngine(
        settings=Settings(),
        model_loader=loader,
        wav_writer=writer,
    )
    request = SpeechRequest(
        text="Cat",
        language="en",
        voice="teacher_female",
        speed=0.9,
    )

    first = engine.synthesize(request)
    second = engine.synthesize(request)

    assert load_count == 1
    assert first.data == b"RIFF-test"
    assert second.engine == "omnivoice"
    assert fake_model.calls[0]["text"] == "Cat"
    assert fake_model.calls[0]["speed"] == 0.9
```

- [ ] **Step 2: Run the adapter tests**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests/test_omnivoice_engine.py -v
```

Expected: FAIL because `OmniVoiceEngine` is missing.

- [ ] **Step 3: Implement lazy loading**

```python
from collections.abc import Callable
from io import BytesIO
from threading import Lock
from typing import Any

from lexiquest_voice.config import Settings
from lexiquest_voice.models import AudioResult, SpeechRequest

ModelLoader = Callable[[Settings], Any]
WavWriter = Callable[[BytesIO, Any, int], None]


class OmniVoiceEngine:
    sample_rate = 24_000

    def __init__(
        self,
        *,
        settings: Settings,
        model_loader: ModelLoader | None = None,
        wav_writer: WavWriter | None = None,
    ) -> None:
        self._settings = settings
        self._model_loader = model_loader or _load_model
        self._wav_writer = wav_writer or _write_wav
        self._model: Any | None = None
        self._load_lock = Lock()

    def _get_model(self) -> Any:
        if self._model is None:
            with self._load_lock:
                if self._model is None:
                    self._model = self._model_loader(self._settings)
        return self._model

    def synthesize(self, request: SpeechRequest) -> AudioResult:
        model = self._get_model()
        generated = model.generate(
            text=request.text,
            instruct=self._settings.voice_instruction,
            speed=request.speed,
        )
        if not generated:
            raise RuntimeError("OmniVoice returned no audio.")

        buffer = BytesIO()
        self._wav_writer(buffer, generated[0], self.sample_rate)
        return AudioResult(
            data=buffer.getvalue(),
            media_type="audio/wav",
            sample_rate=self.sample_rate,
            engine="omnivoice",
            model_version=self._settings.model_version,
        )


def _load_model(settings: Settings) -> Any:
    import torch
    from omnivoice import OmniVoice

    return OmniVoice.from_pretrained(
        settings.model_id,
        device_map=settings.device,
        dtype=torch.float16,
        load_asr=settings.load_asr,
    )


def _write_wav(buffer: BytesIO, audio: Any, sample_rate: int) -> None:
    import soundfile as sf

    sf.write(buffer, audio, sample_rate, format="WAV")
```

`backend/voice_api/requirements-omnivoice-cu128.txt`:

```text
--extra-index-url https://download.pytorch.org/whl/cu128
torch==2.8.0+cu128
torchaudio==2.8.0+cu128
omnivoice==0.2.1
soundfile==0.13.1
```

- [ ] **Step 4: Run adapter and full tests without model dependencies**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests -v
```

Expected: PASS without importing Torch or OmniVoice.

- [ ] **Step 5: Commit**

```powershell
git add backend/voice_api/src/lexiquest_voice/engines/omnivoice_engine.py backend/voice_api/requirements-omnivoice-cu128.txt backend/voice_api/tests/test_omnivoice_engine.py
git commit -m "feat: add lazy OmniVoice engine adapter"
```

### Task 6: Production assembly and operator documentation

**Files:**
- Create: `backend/voice_api/src/lexiquest_voice/main.py`
- Create: `backend/voice_api/README.md`
- Modify: `.gitignore`
- Test: `backend/voice_api/tests/test_app.py`

**Interfaces:**
- Produces: ASGI export `lexiquest_voice.main:app`.
- Consumes: Application Default Credentials and locked `LEXIQUEST_VOICE_*` settings.

- [ ] **Step 1: Add a failing readiness test for an unavailable engine**

Extend the fake engine with:

```python
class UnavailableSpeechEngine:
    @property
    def is_ready(self) -> bool:
        return False

    def synthesize(self, request: SpeechRequest) -> AudioResult:
        raise RuntimeError("not ready")
```

Add:

```python
def test_ready_returns_503_when_engine_is_unavailable(
    token_verifier: FakeTokenVerifier,
) -> None:
    app = create_app(
        engine=UnavailableSpeechEngine(),
        token_verifier=token_verifier,
        settings=Settings(),
    )
    response = TestClient(app).get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "detail": {
            "code": "MODEL_UNAVAILABLE",
            "message": "The speech engine is not ready.",
        }
    }
```

- [ ] **Step 2: Run the failing readiness test**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests/test_app.py -v
```

Expected: FAIL because readiness always returns 200.

- [ ] **Step 3: Add readiness and production assembly**

Add `is_ready` to `SpeechEngine`, fake engine, and `OmniVoiceEngine`. The adapter reports ready only after the model is loaded; production startup explicitly calls `engine.load()` before serving traffic so `/health/ready` reflects deployment state.

`backend/voice_api/src/lexiquest_voice/main.py`:

```python
from lexiquest_voice.app import create_app
from lexiquest_voice.auth import FirebaseTokenVerifier
from lexiquest_voice.config import Settings
from lexiquest_voice.engines.omnivoice_engine import OmniVoiceEngine

settings = Settings()
engine = OmniVoiceEngine(settings=settings)
app = create_app(
    engine=engine,
    token_verifier=FirebaseTokenVerifier(),
    settings=settings,
)
```

Document exact commands:

```powershell
uv sync --project backend/voice_api --dev
uv pip install --python backend/voice_api/.venv/Scripts/python.exe -r backend/voice_api/requirements-omnivoice-cu128.txt
$env:GOOGLE_APPLICATION_CREDENTIALS='C:\absolute\path\service-account.json'
uv run --project backend/voice_api uvicorn lexiquest_voice.main:app --host 127.0.0.1 --port 8000
```

Add these ignore rules:

```gitignore
backend/voice_api/.venv/
backend/voice_api/.env
backend/voice_api/.pytest_cache/
backend/voice_api/.coverage
backend/voice_api/htmlcov/
backend/voice_api/generated/
*.wav
*.pt
*.safetensors
```

- [ ] **Step 4: Run all backend quality gates**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests -v
uv run --project backend/voice_api pytest backend/voice_api/tests --cov=lexiquest_voice --cov-report=term-missing
git diff --check
```

Expected: all tests PASS, coverage report generated, and `git diff --check` exits 0.

- [ ] **Step 5: Verify no secrets or model artifacts are staged**

Run:

```powershell
git status --short
git diff --cached --name-only
git grep -n -I -E "BEGIN PRIVATE KEY|service_account|COINTH_GLM_API_KEY|ANTHROPIC_AUTH_TOKEN"
```

Expected: no credentials, generated audio, `.pt`, or `.safetensors` files in the change set.

- [ ] **Step 6: Commit**

```powershell
git add .gitignore backend/voice_api/src/lexiquest_voice/main.py backend/voice_api/src/lexiquest_voice/app.py backend/voice_api/src/lexiquest_voice/engines backend/voice_api/tests backend/voice_api/README.md
git commit -m "docs: document voice API operation"
```

## Out of Scope for This Plan

The following require separate implementation plans and PR review:

- Flutter `VoiceService`, Native TTS provider, remote OmniVoice provider, and audio playback.
- `practice` fallback versus strict `researchEvaluation` policy.
- Firebase Storage/Firestore shared audio cache.
- Research assignment and telemetry.
- Deployment infrastructure, GPU autoscaling, and production cost controls.
- Pronunciation assessment beyond the existing Speech-to-Text exact match.
