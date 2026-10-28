# Serve LexiQuest-LM on Hugging Face Spaces

The standalone Space serves Firebase-authenticated content requests from the
Flutter app and retains an OpenAI-compatible chat endpoint.

## Prepare the model artifact

1. Train and evaluate the LoRA adapter using the existing training workflow.
2. Merge the adapter into its base causal language model. Use the same base
   model and immutable base revision recorded for training. Load the base
   model in float32 for this CPU serving artifact.
3. Save the merged model with safetensors and save its tokenizer in the same
   folder. The artifact needs `config.json`, tokenizer files and
   `model*.safetensors` weights.
4. Upload that merged folder to a Hugging Face model repository. Record its
   40-character Git commit SHA for `MODEL_REVISION`.

The merged repository must not contain `adapter_config.json`. An adapter-only
repository is not a serving artifact. The existing
`deploy/upload_adapter.py` script uploads adapter training artifacts and does
not merge them. The Space fails readiness for an adapter-only or incomplete
snapshot instead of downloading an unpinned base model.

## Configure the Space

Create a Docker SDK Space and copy `app.py`, `auth.py`, `Dockerfile`,
`requirements.txt` and this README into it.

Set these required Space variables:

| Variable | Value |
| --- | --- |
| `MODEL_ID` | Repository containing the complete merged model. |
| `MODEL_REVISION` | Immutable 40-character commit SHA. Branches such as `main` are rejected. |
| `FIREBASE_PROJECT_ID` | Firebase project that issues the app's ID tokens. |

For a private model repository, configure `HF_TOKEN` as a Space secret. Never
put tokens in source or API payloads. Optional `MAX_INPUT_TOKENS` and
`MAX_NEW_TOKENS` must be positive integers. Their defaults are 1024 and 128.

Importing the API does not import Torch, Transformers or the Firebase SDK.
With valid configuration, startup downloads only the pinned model snapshot.
Tokenizer and model loading then use local files, safetensors and
`trust_remote_code=False`. Failed loads keep the process alive but unready.

The Docker image runs one server worker. Each app process permits one
generation at a time. A simultaneous content request receives `429` with code
`RATE_LIMITED`. The chat route preserves `503 BUSY`. No request text, identity
or bearer token is logged.

## Connect the Flutter app

Set the app's `LEXIQUEST_AI_API_URL` to the Space's HTTPS origin. The app
calls `POST /v1/content` with its Firebase ID token. The Space accepts
`sentence`, `story` and `explanation` content kinds, CEFR levels
`a1` through `c2` or `unknown`, and language `en` or `th`.

Set `FIREBASE_ID_TOKEN` to a token obtained from the authenticated Firebase
client, then send a content request:

```bash
curl -X POST "$SPACE_URL/v1/content" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"cat","kind":"sentence","cefr":"a1","language":"en"}'
```

The response has `text`, `kind`, `cefr`, `language`,
`model_version` and `cached`. `model_version` identifies the model repository
and pinned revision. This service does not cache generated answers.

`POST /v1/chat/completions` remains available for authenticated chat clients.
A fixed operator API key is not a Firebase ID token, so an arbitrary
OpenAI-style proxy cannot authenticate to this Space without the required
Firebase identity.

Both routes cap actual request bodies at 100,000 bytes, including chunked
requests. Oversized bodies receive `413` and malformed Content-Length
receives `400`. Each content field is limited to 2,000 characters. Chat accepts
one to ten messages and clamps generation to the configured token limit.

## Check availability

- `GET /health/live` returns `200` while the process runs.
- `GET /health/ready` returns `503` until a valid pinned artifact loads and
  Firebase authentication is configured.
- Missing, invalid or revoked Firebase ID tokens receive a uniform `401`.

Readiness does not validate model quality, a particular Firebase account or
research efficacy. Validate those separately before a production rollout.

## Run CPU contract tests

From `backend/lexiquest_lm`, run:

```powershell
uv sync --frozen --group dev --no-group train
uv run --frozen --group dev --no-group train pytest tests/test_hf_space_http.py tests/test_hf_space_deployment.py tests/test_hf_space_auth.py -q
```

These tests inject synthetic model and Firebase boundaries. They make no
model downloads, GPU calls or live Firebase requests.
