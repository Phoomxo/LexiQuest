# LexiQuest-LM HuggingFace Space

Serves the fine-tuned LexiQuest-LM model as a standalone OpenAI-compatible
chat API on HuggingFace Spaces. Hosting capacity and cost depend on the chosen
tier and workload. This endpoint does not implement Flutter's `/v1/content`
contract and is not a drop-in value for `LEXIQUEST_AI_API_URL`.

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
   - `POST /v1/chat/completions` — chat messages in, generated choices out.
     It does not expose a voice route or `/v1/content`.

## Calling the API

Set `FIREBASE_ID_TOKEN` to a real token obtained from the authenticated
Firebase client. Never commit or paste a real token into documentation.
Tokens expire and are checked for revocation; refresh them through the
authenticated client flow. A permanent bearer string is not supported.

```bash
curl -X POST "$SPACE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'
```

## Connection to the Flutter content flow

Flutter's `HttpContentProvider` calls `backend/ai_api` at `/v1/content` with
a refreshed Firebase ID token. That service validates the user and translates
the request to provider chat messages at `/v1/chat/completions`. Its provider
authorization currently uses the static server configuration
`LEXIQUEST_AI_LLM_API_KEY`; it does not forward or refresh the app's token.

The implemented local provider path is Flutter → AI content API → Ollama,
using `LEXIQUEST_AI_LLM_BASE_URL=http://127.0.0.1:11434/v1/`,
`LEXIQUEST_AI_LLM_MODEL=qwen2.5:3b`, and
`LEXIQUEST_AI_LLM_API_KEY=ollama`. The `ollama` value is a local placeholder,
not a Firebase credential. Disable unwanted fallback providers and configure
the AI API's Firebase verification as described in the repository's
`backend/lexiquest_lm/scripts/DEPLOY.md`.

Connecting the AI content API to this Space requires a refresh-capable
authenticated bridge with appropriate issuer/user and revocation handling.
That bridge is not currently implemented. Do not copy an expiring Firebase
client token into the static provider-key setting or claim that changing only
the base URL completes the integration. Direct Flutter-to-Space content
requests also have a different route and request/response contract.
