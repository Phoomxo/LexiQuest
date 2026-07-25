# LexiQuest-LM HuggingFace Space

Serves the fine-tuned LexiQuest-LM model as an OpenAI-compatible chat API on
HuggingFace Spaces (free CPU tier). This is the production endpoint the
Flutter app calls — once deployed, the app needs no other LLM.

## Layout

```
hf_space/
  app.py            # FastAPI app loaded by HF Spaces
  requirements.txt  # pinned deps (transformers, peft, fastapi, uvicorn)
  README.md         # this file (HF reads it as the Space's README)
```

## Deploy

1. Train the model locally with `lora_finetune.py --train`.
2. Push the resulting `checkpoints/lora_adapter/` to a HuggingFace model repo
   (e.g. `your-user/lexiquest-lm`).
3. Create a new HF **Space** (SDK: Docker) and copy this directory into it.
4. Set the Space's secret `MODEL_ID` to the model repo from step 2.
5. The Space builds, downloads the adapter on cold start, and exposes:

   - `GET /health/live`, `GET /health/ready`
   - `POST /v1/chat/completions` — OpenAI-compatible (so the Flutter client
     can reuse the exact same `OmniVoiceProvider`-style HTTP shape).

## Why OpenAI-compatible?

The Flutter `ai_api` backend already speaks OpenAI-compat. Serving
LexiQuest-LM with the same contract means the app has ONE client codepath
that works against Gemini, Ollama, **and** LexiQuest-LM — swapping is pure
configuration, never code.
