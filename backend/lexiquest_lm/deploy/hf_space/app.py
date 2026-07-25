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

# Re-use the exact prompt template from training so the served model sees the
# same instruction frame it learned on. This is a reproducibility invariant.
import sys
from pathlib import Path

# Make the train package importable when this file runs inside the Space.
_TRAIN_DIR = Path(__file__).resolve().parents[2] / "train"
if str(_TRAIN_DIR) not in sys.path:
    sys.path.insert(0, str(_TRAIN_DIR))
from tokenise_dataset import SYSTEM_PROMPT, format_prompt  # noqa: E402

logger = logging.getLogger("lexiquest_lm_space")
logging.basicConfig(level=logging.INFO)

MODEL_ID = os.environ.get("MODEL_ID", "Qwen/Qwen2.5-0.5B")
MAX_NEW_TOKENS = int(os.environ.get("MAX_NEW_TOKENS", "128"))


# ---------------------------------------------------------------------------
# Model load (eager, at import time)
# ---------------------------------------------------------------------------


def _load_model_and_tokenizer() -> tuple[Any, Any]:
    logger.info("Loading model %s ...", MODEL_ID)
    start = time.monotonic()
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    # CPU + float32 on the free tier. A 0.5B model fits comfortably in the
    # 16GB RAM HF allocates to free CPU Spaces.
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_ID,
        torch_dtype=torch.float32,
        device_map="cpu",
        trust_remote_code=True,
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
    if model is None:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"detail": {"code": "MODEL_UNAVAILABLE", "message": "Model not loaded."}},
        )
    return {"status": "ready"}


@app.post("/v1/chat/completions")
def chat_completions(
    request: ChatCompletionRequest,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    # NOTE: HuggingFace Spaces do not enforce auth themselves; this header
    # check is a soft gate so the endpoint is not a fully open proxy. The
    # Flutter app sends the Firebase ID token here, mirroring the ai_api
    # contract. A production deployment should put a real auth layer in
    # front (HF Inference Endpoints, a Cloud Run proxy, etc.).
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "UNAUTHENTICATED", "message": "Bearer token required."},
        )

    if not request.messages:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"code": "INVALID_REQUEST", "message": "messages must not be empty"},
        )

    prompt = _build_prompt(request.messages)
    inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
    max_new = min(request.max_tokens or MAX_NEW_TOKENS, MAX_NEW_TOKENS)

    # Stop generation at the ChatML assistant turn terminator so the model
    # does not ramble past the first response (a known issue with greedy
    # decoding on small fine-tuned models). eos_token_id covers <|im_end|>
    # directly; we pass both the bare eos and any additional stop ids to be
    # safe across tokenizer revisions.
    stop_token_ids = {tokenizer.eos_token_id}
    im_end_id = tokenizer.convert_tokens_to_ids("<|im_end|>")
    if im_end_id is not None and im_end_id != tokenizer.unk_token_id:
        stop_token_ids.add(im_end_id)

    with torch.no_grad():
        out = model.generate(
            **inputs,
            max_new_tokens=max_new,
            do_sample=False,  # greedy for reproducibility
            pad_token_id=tokenizer.pad_token_id,
            eos_token_id=list(stop_token_ids),
        )
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
