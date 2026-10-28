"""Authenticated content and chat endpoints for a pinned LexiQuest-LM model."""

from __future__ import annotations

from collections.abc import Callable
from contextlib import asynccontextmanager
from dataclasses import dataclass
import logging
import os
from pathlib import Path
import re
import threading
import time
from typing import Any, Literal, Protocol

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, field_validator
from starlette.concurrency import run_in_threadpool
from starlette.types import ASGIApp, Message, Receive, Scope, Send

try:
    from .auth import AuthenticationError, FirebaseTokenVerifier, extract_bearer_token
except ImportError:  # Hugging Face copies this directory as a flat Space.
    from auth import AuthenticationError, FirebaseTokenVerifier, extract_bearer_token


logger = logging.getLogger("lexiquest_lm_space")
SYSTEM_PROMPT = "You are an English vocabulary teacher for Thai learners."
_PROMPT_TEMPLATE = (
    "<|im_start|>system\n{system}<|im_end|>\n"
    "<|im_start|>user\n{user}<|im_end|>\n"
    "<|im_start|>assistant\n"
)
MAX_INPUT_TOKENS = 1024
MAX_NEW_TOKENS = 128


def format_prompt(user_prompt: str) -> str:
    return _PROMPT_TEMPLATE.format(system=SYSTEM_PROMPT, user=user_prompt)


def _environment_limit(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError:
        return 0


@dataclass(frozen=True, slots=True)
class ServingSettings:
    model_id: str = ""
    model_revision: str = ""
    max_input_tokens: int = MAX_INPUT_TOKENS
    max_new_tokens: int = MAX_NEW_TOKENS

    @classmethod
    def from_environment(cls) -> ServingSettings:
        return cls(
            model_id=os.environ.get("MODEL_ID", "").strip(),
            model_revision=os.environ.get("MODEL_REVISION", "").strip(),
            max_input_tokens=_environment_limit("MAX_INPUT_TOKENS", MAX_INPUT_TOKENS),
            max_new_tokens=_environment_limit("MAX_NEW_TOKENS", MAX_NEW_TOKENS),
        )

    @property
    def is_configured(self) -> bool:
        return bool(
            re.fullmatch(r"[\w][\w.-]{0,95}/[\w][\w.-]{0,95}", self.model_id, re.ASCII)
            and ".." not in self.model_id
            and re.fullmatch(r"[0-9a-fA-F]{40}", self.model_revision)
            and self.max_input_tokens > 0
            and self.max_new_tokens > 0
        )

    @property
    def model_version(self) -> str:
        return f"{self.model_id}@{self.model_revision}"


@dataclass(frozen=True, slots=True)
class GenerationResult:
    text: str
    prompt_tokens: int
    completion_tokens: int


class Generator(Protocol):
    def generate(self, prompt: str, max_new_tokens: int) -> GenerationResult: ...


class _TransformersGenerator:
    def __init__(self, model: Any, tokenizer: Any, torch: Any, settings: ServingSettings):
        self.model = model
        self.tokenizer = tokenizer
        self.torch = torch
        self.settings = settings

    def generate(self, prompt: str, max_new_tokens: int) -> GenerationResult:
        inputs = self.tokenizer(
            prompt, return_tensors="pt", truncation=True,
            max_length=self.settings.max_input_tokens,
        ).to(self.model.device)
        stop_token_ids = {self.tokenizer.eos_token_id}
        im_end_id = self.tokenizer.convert_tokens_to_ids("<|im_end|>")
        if im_end_id is not None and im_end_id != self.tokenizer.unk_token_id:
            stop_token_ids.add(im_end_id)
        with self.torch.no_grad():
            output = self.model.generate(
                **inputs, max_new_tokens=max_new_tokens, do_sample=False,
                pad_token_id=self.tokenizer.pad_token_id,
                eos_token_id=list(stop_token_ids),
            )
        prompt_tokens = int(inputs["input_ids"].shape[1])
        new_tokens = output[0][prompt_tokens:]
        return GenerationResult(
            self.tokenizer.decode(new_tokens, skip_special_tokens=True).strip(),
            prompt_tokens, int(new_tokens.shape[0]),
        )


def _load_generator(settings: ServingSettings) -> Generator:
    import torch
    from huggingface_hub import snapshot_download
    from transformers import AutoModelForCausalLM, AutoTokenizer

    start = time.monotonic()
    snapshot = Path(snapshot_download(
        repo_id=settings.model_id, revision=settings.model_revision,
        allow_patterns=[
            "config.json", "generation_config.json", "tokenizer.json",
            "tokenizer_config.json", "tokenizer.model", "special_tokens_map.json",
            "added_tokens.json", "vocab.json", "merges.txt", "model*.safetensors",
            "model.safetensors.index.json",
        ],
    ))
    if (
        (snapshot / "adapter_config.json").exists()
        or not (snapshot / "config.json").is_file()
        or not any(snapshot.glob("model*.safetensors"))
    ):
        raise ValueError("A merged safetensors model snapshot is required")
    tokenizer = AutoTokenizer.from_pretrained(
        snapshot, local_files_only=True, trust_remote_code=False,
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    model = AutoModelForCausalLM.from_pretrained(
        snapshot, local_files_only=True, use_safetensors=True,
        trust_remote_code=False, dtype=torch.float32, device_map="cpu",
    )
    model.eval()
    logger.info("Model loaded in %.1fs", time.monotonic() - start)
    return _TransformersGenerator(model, tokenizer, torch, settings)


class RequestBodyLimitMiddleware:
    maximum_bytes = 100_000

    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] not in ("POST", "PUT", "PATCH"):
            await self.app(scope, receive, send)
            return

        async def reject(status_code: int) -> None:
            response = JSONResponse(status_code=status_code, content={"detail": {
                "code": "PAYLOAD_TOO_LARGE" if status_code == 413 else "INVALID_CONTENT_LENGTH",
                "message": "Request body exceeds 100KB." if status_code == 413 else "Content-Length is invalid.",
            }})
            await response(scope, receive, send)

        lengths = [value.strip() for name, value in scope["headers"] if name.lower() == b"content-length"]
        if len(lengths) > 1 or (lengths and (not lengths[0].isdigit() or len(lengths[0]) > 20)):
            await reject(400)
            return
        if lengths and int(lengths[0]) > self.maximum_bytes:
            await reject(413)
            return
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            if len(body) + len(chunk) > self.maximum_bytes:
                await reject(413)
                return
            body.extend(chunk)
            if not message.get("more_body", False):
                break
        delivered = False
        async def replay() -> Message:
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()
        await self.app(scope, replay, send)


class ContentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    text: str = Field(min_length=1, max_length=2000)
    kind: Literal["sentence", "story", "explanation"]
    cefr: Literal["a1", "a2", "b1", "b2", "c1", "c2", "unknown"] = "unknown"
    language: Literal["en", "th"] = "en"

    @field_validator("text")
    @classmethod
    def normalize_whitespace(cls, value: str) -> str:
        return re.sub(r"\s+", " ", value)


class ChatMessage(BaseModel):
    role: str
    content: str = Field(max_length=2000)


class ChatCompletionRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")
    model: str = ""
    messages: list[ChatMessage] = Field(min_length=1, max_length=10)
    max_tokens: int | None = None


def _build_prompt(messages: list[ChatMessage]) -> str:
    user_parts = [
        f"(Additional guidance: {message.content})" if message.role == "system" else message.content
        for message in messages if message.role in ("system", "user", "assistant")
    ]
    return format_prompt("\n".join(part for part in user_parts if part) or "Hello.")


def _content_prompt(request: ContentRequest) -> str:
    instruction = {
        "sentence": "Write one short example sentence using",
        "story": "Write a short story of 3 to 5 sentences using",
        "explanation": "Explain the meaning and usage of",
    }[request.kind]
    level = "" if request.cefr == "unknown" else f" Use CEFR {request.cefr} vocabulary."
    language = "Thai" if request.language == "th" else "English"
    return format_prompt(f"{instruction}: {request.text}.{level} Respond in {language}.")


def _failure(status_code: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status_code, detail={"code": code, "message": message})


def create_app(
    *, settings: ServingSettings | None = None,
    token_verifier: FirebaseTokenVerifier | None = None,
    generator: Generator | None = None,
    model_loader: Callable[[ServingSettings], Generator] | None = None,
) -> FastAPI:
    config = settings if settings is not None else ServingSettings.from_environment()
    verifier = token_verifier if token_verifier is not None else FirebaseTokenVerifier(os.environ.get("FIREBASE_PROJECT_ID"))
    lock = threading.Lock()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if app.state.generator is None and config.is_configured and verifier.is_configured:
            try:
                app.state.generator = await run_in_threadpool(model_loader or _load_generator, config)
            except Exception as error:
                logger.error("Model load failed: %s", type(error).__name__)
        yield
        app.state.generator = None

    app = FastAPI(title="LexiQuest-LM", version="0.1.0", lifespan=lifespan)
    app.state.generator = generator
    app.add_middleware(RequestBodyLimitMiddleware)

    def authenticate(authorization: str | None) -> None:
        try:
            verifier.verify(extract_bearer_token(authorization))
        except AuthenticationError:
            raise _failure(401, "UNAUTHENTICATED", "Bearer token required.") from None

    def generate(
        prompt: str, maximum: int | None = None, *, content_contract: bool = False,
    ) -> GenerationResult:
        backend = app.state.generator
        if not config.is_configured or backend is None:
            raise _failure(
                503, "PROVIDER_UNAVAILABLE" if content_contract else "SERVICE_UNAVAILABLE",
                "Service is not ready.",
            )
        if not lock.acquire(blocking=False):
            raise _failure(
                429 if content_contract else 503,
                "RATE_LIMITED" if content_contract else "BUSY", "Model generation busy.",
            )
        try:
            maximum = max(1, min(config.max_new_tokens if maximum is None else maximum, config.max_new_tokens))
            result = backend.generate(prompt, maximum)
            if not result.text.strip():
                raise ValueError("empty model response")
            return result
        except Exception as error:
            logger.error("Generation failed: %s", type(error).__name__)
            raise _failure(
                503, "CONTENT_GENERATION_FAILED" if content_contract else "GENERATION_FAILED",
                "Model generation failed.",
            ) from None
        finally:
            lock.release()

    @app.get("/health/live")
    def live() -> dict[str, str]:
        return {"status": "live"}

    @app.get("/health/ready")
    def ready() -> dict[str, str]:
        if not config.is_configured or app.state.generator is None or not verifier.is_configured:
            raise _failure(503, "SERVICE_UNAVAILABLE", "Service is not ready.")
        return {"status": "ready"}

    @app.post("/v1/content")
    def content(request: ContentRequest, authorization: str | None = Header(default=None)) -> dict[str, Any]:
        authenticate(authorization)
        result = generate(_content_prompt(request), content_contract=True)
        return {"text": result.text.strip(), "kind": request.kind, "language": request.language,
                "cefr": request.cefr, "model_version": config.model_version, "cached": False}

    @app.post("/v1/chat/completions")
    def chat_completions(request: ChatCompletionRequest, authorization: str | None = Header(default=None)) -> dict[str, Any]:
        authenticate(authorization)
        result = generate(_build_prompt(request.messages), request.max_tokens)
        return {
            "id": f"lexiquest-lm-{time.time_ns()}", "object": "chat.completion",
            "model": config.model_id,
            "choices": [{"index": 0, "message": {"role": "assistant", "content": result.text.strip()}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": result.prompt_tokens, "completion_tokens": result.completion_tokens,
                      "total_tokens": result.prompt_tokens + result.completion_tokens},
        }

    return app


app = create_app()
