# LexiQuest-LM Deploy Guide

This guide packages a trained adapter for a standalone chat API and explains
the separate content API used by Flutter. The Space is not a drop-in value for
`LEXIQUEST_AI_API_URL`: the request contract and authentication differ.

## Prerequisites

- A trained adapter at `backend/lexiquest_lm/checkpoints/lora_adapter/`
  (produced by `lora_finetune.py --train`).
- A HuggingFace account and hosting capacity appropriate for the model.

---

## Step 1: Upload the adapter to HuggingFace

### 1a. Create a write token

1. Go to https://huggingface.co/settings/tokens
2. Click **New token**
3. Name: `lexiquest-upload`, Role: **Write**
4. Copy the token (starts with `hf_...`)

### 1b. Log in once (stores token locally)

```powershell
# Install the CLI (if not already)
uv pip install --project backend/lexiquest_lm huggingface_hub

# Log in — paste your token when prompted
huggingface-cli login
```

### 1c. Upload

```powershell
# Dry-run first to see what will upload:
uv run --project backend/lexiquest_lm python backend/lexiquest_lm/scripts/upload_to_huggingface.py --dry-run

# Real upload (auto-detects your username from the login):
uv run --project backend/lexiquest_lm python backend/lexiquest_lm/scripts/upload_to_huggingface.py
```

**Result**: Your model is now at `https://huggingface.co/<your-username>/lexiquest-lm`

Note the **full repo ID** (e.g. `phet1910/lexiquest-lm`) — you'll need it in Step 2.

---

## Step 2: Deploy the standalone HuggingFace Space

The Space serves your model as an OpenAI-compatible API. The app files are
already prepared at `backend/lexiquest_lm/deploy/hf_space/`.

### 2a. Create the Space

1. Go to https://huggingface.co/new-space
2. **Owner**: your username
3. **Space name**: `lexiquest-lm-api`
4. **License**: MIT (or your choice)
5. **SDK**: **Docker**
6. **Hardware**: choose a tier after checking the model's memory and latency needs.
7. Click **Create Space**

### 2b. Upload the Space files

The Space needs all files from `backend/lexiquest_lm/deploy/hf_space/`,
including `app.py`, `auth.py`, `Dockerfile`, `requirements.txt`, and
`README.md`.

Easiest method — clone the empty Space and copy files in:

```powershell
# Replace <your-username> with your HF username
git clone https://huggingface.co/spaces/<your-username>/lexiquest-lm-api
Copy-Item backend\lexiquest_lm\deploy\hf_space\* lexiquest-lm-api\ -Recurse
cd lexiquest-lm-api
git add .
git commit -m "Deploy LexiQuest-LM API"
git push
```

### 2c. Set the required secrets

The Space loads your model by repo ID and verifies Firebase ID tokens. Set both
values as repository secrets so they are not hard-coded:

1. Go to your Space: `https://huggingface.co/spaces/<your-username>/lexiquest-lm-api`
2. **Settings** → **Repository secrets** → **New secret**
3. Add `MODEL_ID` with value `<your-username>/lexiquest-lm`.
4. Add `FIREBASE_PROJECT_ID` with the Firebase project ID used by the app.
5. Save both secrets. The readiness endpoint intentionally returns `503` until
   the model is loaded and Firebase authentication is configured.

Optional Space variables `MAX_INPUT_TOKENS` and `MAX_NEW_TOKENS` control the
positive per-request resource limits. Their defaults are `1024` and `128`.

### 2d. Wait for build

The Space will build (installs torch + transformers from `requirements.txt`),
download your adapter on first start, then go **Running**.

Check the **Logs** tab if it stays in **Building** or errors.

### 2e. Test the endpoint

```powershell
# Replace <your-username> with your HF username
$SPACE_URL = "https://<your-username>-lexiquest-lm-api.hf.space"
# Export FIREBASE_ID_TOKEN from a signed-in client before running this command.
if (-not $env:FIREBASE_ID_TOKEN) { throw "FIREBASE_ID_TOKEN is required" }

$requestBody = @{
  messages = @(@{
    role = 'user'
    content = 'Write ONE example sentence using the word cat.'
  })
} | ConvertTo-Json -Depth 4
Invoke-RestMethod -Method Post -Uri "$SPACE_URL/v1/chat/completions" `
  -Headers @{ Authorization = "Bearer $env:FIREBASE_ID_TOKEN" } `
  -ContentType 'application/json' -Body $requestBody
```

You should get JSON with `choices[0].message.content` containing a sentence.

This checks the standalone chat endpoint. It does not verify the Flutter
content flow or establish a refresh-capable server connection to the Space.

---

## Step 3: Connect Flutter to the content API

The implemented local path is:

- Flutter `HttpContentProvider` sends content requests to the AI API's
  `POST /v1/content`, using the signed-in user's Firebase ID token and refresh flow.
- `backend/ai_api` validates that token, builds a teaching prompt, and calls
  the configured provider's `POST /v1/chat/completions` with a static server-side
  `LEXIQUEST_AI_LLM_API_KEY`.
- Local Ollama can serve that provider endpoint. The requested model must
  already be available in the running Ollama service.

For an isolated local provider configuration, use these existing Settings
names in `backend/ai_api/.env` (ensure process environment overrides do not
enable a different provider or fallback):

```dotenv
LEXIQUEST_AI_LLM_BASE_URL=http://127.0.0.1:11434/v1/
LEXIQUEST_AI_LLM_MODEL=qwen2.5:3b
LEXIQUEST_AI_LLM_API_KEY=ollama
LEXIQUEST_AI_FALLBACK_LLM_MODEL=
LEXIQUEST_AI_GEMINI_KEYS=
```

`ollama` is a local placeholder key, not a Firebase token. The AI API still
requires its existing Firebase Admin application-default credentials and
project configuration to verify app requests; local inference does not disable
authentication. Keep real credentials out of source files and APK defines.

From the repository root, using the already installed AI environment:

```powershell
& backend/ai_api/.venv/Scripts/python.exe -m uvicorn lexiquest_ai.main:app `
  --app-dir backend/ai_api/src --host 127.0.0.1 --port 8000
```

Build for an Android emulator with the AI API URL, and configure the Voice API
separately if needed:

```powershell
flutter build apk --debug `
  --dart-define=LEXIQUEST_AI_API_URL=http://10.0.2.2:8000
```

The emulator host address and physical-device LAN setup are documented in
[Android LAN Development](../../../docs/runbooks/android-lan-development.md).
The local backend and Ollama must remain available while using this path.
Release builds require an HTTPS AI API endpoint.

### Remote AI API to Space: missing authentication bridge

The Space accepts an expiring Firebase ID token and checks revocation. The AI
API's configured provider key is static and does not forward or refresh the
Flutter token. A base-URL change alone cannot create a working long-lived
AI API-to-Space connection. Do not store a copied client Firebase token as
`LEXIQUEST_AI_LLM_API_KEY`.

A refresh-capable authenticated bridge with the appropriate user/issuer and
revocation handling is still a deployment dependency. It is not implemented
by this guide. Pointing Flutter directly at the Space also fails the endpoint
contract: the Space does not expose `/v1/content`.

### Install on a phone

```powershell
flutter install
# or copy build/app/outputs/flutter-apk/app-debug.apk to the phone manually
```

---

## Capacity and cost

Hosting terms, runtime cost, memory requirements, cold-start duration, and
inference latency depend on the selected model and infrastructure. Check the
chosen service's current terms and measure the deployed workload; this guide
does not guarantee free operation or a fixed deployment/training duration.

## Troubleshooting

- **Space stays "Building" forever**: check Logs. Usually a typo in
  `requirements.txt` or an invalid `MODEL_ID` secret.
- **First request is slow**: inspect startup/model-load logs and measure the
  selected hardware before setting client timeouts or latency expectations.
- **Generation loops / repeats**: ensure the latest `app.py` is deployed
  (it passes `<|im_end|>` as the eos token to stop cleanly).
- **401 from the Space**: obtain a fresh Firebase ID token from a signed-in
  client and confirm `FIREBASE_PROJECT_ID` matches its issuer project. Tokens
  are cryptographically verified and arbitrary bearer strings are rejected.
