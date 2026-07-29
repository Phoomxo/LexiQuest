# LexiQuest-LM HuggingFace Space

Serves the fine-tuned LexiQuest-LM model as an OpenAI-compatible chat API on
HuggingFace Spaces (free CPU tier). This is the production endpoint the
Flutter app calls — once deployed, the app needs no other LLM.

## Layout

```
hf_space/
  app.py            # FastAPI app loaded by HF Spaces
  auth.py           # Firebase ID-token verification
  Dockerfile        # standalone Docker SDK Space image
  requirements.txt  # pinned API, auth, and ML runtime dependencies
  README.md         # this file (HF reads it as the Space's README)
```

## Deploy

1. Train the model locally with `lora_finetune.py --train`.
2. Push the resulting `checkpoints/lora_adapter/` to a HuggingFace model repo
   (e.g. `your-user/lexiquest-lm`).
3. Create a new HF **Space** (SDK: Docker) and copy this directory into it.
4. Set the Space's required secrets:

   - `MODEL_ID`: the HuggingFace model repo from step 2.
   - `FIREBASE_PROJECT_ID`: the Firebase project that issues client ID tokens.
   - Optional `MAX_INPUT_TOKENS` and `MAX_NEW_TOKENS`: positive per-request
     limits (defaults: `1024` input and `128` generated tokens).

5. The service fails closed: `/health/ready` returns `503` until the model is
   loaded and Firebase authentication is configured. Chat requests without a
   cryptographically verified Firebase ID token return a uniform `401`.
6. The Space builds, downloads the adapter on cold start, and exposes:

   - `GET /health/live`, `GET /health/ready`
   - `POST /v1/chat/completions` — OpenAI-compatible (so the Flutter client
     can reuse the exact same `OmniVoiceProvider`-style HTTP shape).

## Calling the API

Set `FIREBASE_ID_TOKEN` to a real token obtained from the authenticated
Firebase client. Never commit or paste a real token into documentation.

```bash
curl -X POST "$SPACE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'
```

## Why OpenAI-compatible?

The Flutter `ai_api` backend already speaks OpenAI-compat. Serving
LexiQuest-LM with the same contract means the app has ONE client codepath
that works against Gemini, Ollama, **and** LexiQuest-LM — swapping is pure
configuration, never code.
