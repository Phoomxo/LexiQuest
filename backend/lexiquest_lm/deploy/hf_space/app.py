"""LexiQuest-LM HuggingFace Space serving app.

Exposes the fine-tuned LexiQuest-LM (Qwen2.5-0.5B + LoRA adapter) as an
OpenAI-compatible chat completions endpoint on HuggingFace Spaces' free CPU
tier. This is the public face of the thesis's custom model: the Flutter app
calls it just like it would call Gemini or Ollama, because the contract is
identical.

Cold start
----------
HuggingFace Spaces spin down after inactivity, so the first request after a
cold start pays a ~30-60s model-load penalty. To avoid the app holding the
request open that long, the model is loaded eagerly at import time; the
Space's own readiness probe handles the wait. Subsequent requests are fast
(CPU inference on a 0.5B model is ~1-3s per short completion).

Configuration
-------------
- ``MODEL_ID`` (secret): the HF repo of the merged/adapter model, e.g.
  ``your-user/lexiquest-lm``. Defaults to the base Qwen2.5-0.5B for
  first-time smoke tests before the adapter exists.
- ``MAX_INPUT_TOKENS``: per-request prompt cap (default 1024).
- ``MAX_NEW_TOKENS``: per-request generation cap (default 128).

Privacy
-------
Like the rest of LexiQuest, this service never logs request text, user
identity, or tokens. Only the request count and the exception type (on error)
are logged.
"""

from __future__ import annotations

import logging
import os
import time
from typing import Any

# Defer the heavy imports until the module body runs so the Space can at
# least report a clean error if torch/transformers are unavailable. We do
# NOT defer past this point because HF Spaces loads the model at import time
# to keep request latency low.
import torch
from fastapi import FastAPI, Header, HTTPException, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from transformers import AutoModelForCausalLM, AutoTokenizer

# Hugging Face copies this directory as a flat Space, so keep this template
# byte-identical to backend/lexiquest_lm/train/tokenise_dataset.py.
SYSTEM_PROMPT = "You are an English vocabulary teacher for Thai learners."

_PROMPT_TEMPLATE = (
    "<|im_start|>system\n{system}<|im_end|>\n"
    "<|im_start|>user\n{user}<|im_end|>\n"
    "<|im_start|>assistant\n"
)


def format_prompt(user_prompt: str) -> str:
    return _PROMPT_TEMPLATE.format(system=SYSTEM_PROMPT, user=user_prompt)
try:
    from .auth import (  # noqa: E402
        AuthenticationError,
        FirebaseTokenVerifier,
        extract_bearer_token,
    )
except ImportError:  # Hugging Face copies this directory as a flat Space.
    from auth import (  # type: ignore[no-redef]  # noqa: E402
        AuthenticationError,
        FirebaseTokenVerifier,
        extract_bearer_token,
    )

logger = logging.getLogger("lexiquest_lm_space")
logging.basicConfig(level=logging.INFO)

import threading

MODEL_ID = os.environ.get("MODEL_ID", "Qwen/Qwen2.5-0.5B")
MODEL_REVISION = os.environ.get("MODEL_REVISION", "main")
MAX_INPUT_TOKENS = max(1, int(os.environ.get("MAX_INPUT_TOKENS", "1024")))
MAX_NEW_TOKENS = max(1, int(os.environ.get("MAX_NEW_TOKENS", "128")))
FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID")
token_verifier = FirebaseTokenVerifier(FIREBASE_PROJECT_ID)

_GENERATION_LOCK = threading.Lock()


# ---------------------------------------------------------------------------
# Model load (eager, at import time)
# ---------------------------------------------------------------------------


def _load_model_and_tokenizer() -> tuple[Any, Any]:
    logger.info("Loading model %s (revision: %s)...", MODEL_ID, MODEL_REVISION)
    start = time.monotonic()
    tokenizer = AutoTokenizer.from_pretrained(
        MODEL_ID,
        revision=MODEL_REVISION,
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    # CPU + float32 on the free tier. A 0.5B model fits comfortably in the
    # 16GB RAM HF allocates to free CPU Spaces.
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_ID,
        revision=MODEL_REVISION,
        use_safetensors=True,
        dtype=torch.float32,
        device_map="cpu",
    )
    model.eval()
    logger.info("Model loaded in %.1fs", time.monotonic() - start)
    return model, tokenizer


model, tokenizer = _load_model_and_tokenizer()


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------


app = FastAPI(title="LexiQuest-LM", version="0.1.0")


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatCompletionRequest(BaseModel):
    """Subset of the OpenAI chat completions request the Flutter client sends.

    Extra fields (``temperature``, ``top_p``, ``stream``, etc.) are accepted
    and ignored so a client built for OpenAI does not get a 422.
    """

    model_config = {"extra": "ignore"}
    model: str = ""
    messages: list[ChatMessage] = Field(default_factory=list)
    max_tokens: int | None = None


def _build_prompt(messages: list[ChatMessage]) -> str:
    """Convert the OpenAI messages list to our ChatML training template.

    We always inject the same system prompt used during fine-tuning; any
    client-supplied system message is folded in AFTER it so the model still
    recognises its role frame.
    """

    user_parts: list[str] = []
    for msg in messages:
        if msg.role == "system":
            # Prepend any extra system instructions to the canonical one so
            # the model never loses its teaching identity.
            user_parts.append(f"(Additional guidance: {msg.content})")
        elif msg.role in ("user", "assistant"):
            user_parts.append(msg.content)
    user_text = "\n".join(p for p in user_parts if p) or "Hello."
    return format_prompt(user_text)


@app.get("/health/live")
def live() -> dict[str, str]:
    return {"status": "live"}


@app.get("/health/ready")
def ready() -> dict[str, str]:
    if model is None or not token_verifier.is_configured:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "detail": {
                    "code": "SERVICE_UNAVAILABLE",
                    "message": "Service is not ready.",
                }
            },
        )
    return {"status": "ready"}


@app.post("/v1/chat/completions")
def chat_completions(
    request: ChatCompletionRequest,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    try:
        token = extract_bearer_token(authorization)
        token_verifier.verify(token)
    except AuthenticationError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "UNAUTHENTICATED", "message": "Bearer token required."},
        ) from None

    if not request.messages or len(request.messages) > 10:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail={"code": "INVALID_REQUEST", "message": "messages must contain between 1 and 10 items"},
        )
    for msg in request.messages:
        if len(msg.content) > 2000:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail={"code": "INVALID_REQUEST", "message": "message content length exceeds limit"},
            )

    prompt = _build_prompt(request.messages)
    inputs = tokenizer(
        prompt,
        return_tensors="pt",
        truncation=True,
        max_length=MAX_INPUT_TOKENS,
    ).to(model.device)
    max_new = max(
        1,
        min(request.max_tokens or MAX_NEW_TOKENS, MAX_NEW_TOKENS),
    )

    stop_token_ids = {tokenizer.eos_token_id}
    im_end_id = tokenizer.convert_tokens_to_ids("<|im_end|>")
    if im_end_id is not None and im_end_id != tokenizer.unk_token_id:
        stop_token_ids.add(im_end_id)

    if not _GENERATION_LOCK.acquire(blocking=False):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "BUSY", "message": "Model generation busy"},
        )
    try:
        with torch.no_grad():
            out = model.generate(
                **inputs,
                max_new_tokens=max_new,
                do_sample=False,  # greedy for reproducibility
                pad_token_id=tokenizer.pad_token_id,
                eos_token_id=list(stop_token_ids),
            )
    finally:
        _GENERATION_LOCK.release()
    new_tokens = out[0][inputs["input_ids"].shape[1]:]
    text = tokenizer.decode(new_tokens, skip_special_tokens=True).strip()

    # OpenAI-compatible response shape so the Flutter client can parse it
    # with the same code it uses for Gemini/Ollama.
    return {
        "id": f"lexiquest-lm-{int(time.time())}",
        "object": "chat.completion",
        "model": MODEL_ID,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": text},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": int(inputs["input_ids"].shape[1]),
            "completion_tokens": int(new_tokens.shape[0]),
            "total_tokens": int(inputs["input_ids"].shape[1] + new_tokens.shape[0]),
        },
    }
