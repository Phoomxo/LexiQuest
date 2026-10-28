# LexiQuest-LM Deploy Guide

End-to-end guide to take the trained model from your workstation to a public
API that the Flutter app calls. Total time: ~20 minutes.

## Prerequisites

- A trained adapter at `backend/lexiquest_lm/checkpoints/lora_adapter/`
  (produced by `lora_finetune.py --train`).
- A free HuggingFace account: https://huggingface.co/join

---

## Step 1: Upload the adapter to HuggingFace (~5 min)

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

## Step 2: Deploy the HuggingFace Space (~10 min)

The Space serves your model as an OpenAI-compatible API. The app files are
already prepared at `backend/lexiquest_lm/deploy/hf_space/`.

### 2a. Create the Space

1. Go to https://huggingface.co/new-space
2. **Owner**: your username
3. **Space name**: `lexiquest-lm-api`
4. **License**: MIT (or your choice)
5. **SDK**: **Docker**
6. **Hardware**: **CPU basic** (free, 16GB RAM — plenty for a 0.5B model)
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

### 2d. Wait for build (~3-5 min)

The Space will build (installs torch + transformers from `requirements.txt`),
download your adapter on first start, then go **Running**.

Check the **Logs** tab if it stays in **Building** or errors.

### 2e. Test the endpoint

```powershell
# Replace <your-username> with your HF username
$SPACE_URL = "https://<your-username>-lexiquest-lm-api.hf.space"
# Export FIREBASE_ID_TOKEN from a signed-in client before running this command.
if (-not $env:FIREBASE_ID_TOKEN) { throw "FIREBASE_ID_TOKEN is required" }

curl -X POST "$SPACE_URL/v1/chat/completions" `
  -H "Authorization: Bearer $env:FIREBASE_ID_TOKEN" `
  -H "Content-Type: application/json" `
  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Write ONE example sentence using the word cat.\"}]}'
```

You should get JSON with `choices[0].message.content` containing a sentence.

**Note the full Space URL** — you'll need it in Step 3.

---

## Step 3: Build the APK pointing at your Space (~5 min)

```powershell
# Replace <your-username> with your HF username
flutter build apk --debug `
  --dart-define=LEXIQUEST_VOICE_API_URL=https://your-voice-api.example.com `
  --dart-define=LEXIQUEST_AI_API_URL=https://<your-username>-lexiquest-lm-api.hf.space
```

The APK installs on any Android phone. When a learner taps a word in the AI
Tutor or fill-in-the-blanks screen, the app calls your Space, which runs
LexiQuest-LM, which returns a teaching sentence. No third-party API key, no
per-request cost, no dependency on your workstation being online.

### Install on a phone

```powershell
flutter install
# or copy build/app/outputs/flutter-apk/app-debug.apk to the phone manually
```

---

## Cost summary

| Component | Cost |
|---|---|
| HuggingFace model repo (public) | Free |
| HuggingFace Space (CPU basic) | Free |
| Per-request inference | Free (CPU) |
| Training (already done) | 50 min of your RTX 3050 |
| **Total ongoing** | **$0/month forever** |

## Troubleshooting

- **Space stays "Building" forever**: check Logs. Usually a typo in
  `requirements.txt` or an invalid `MODEL_ID` secret.
- **First request is slow (~30-60s)**: Spaces sleep when idle; the first
  request after sleep pays a cold-start model-load. Subsequent requests are
  fast (~1-3s).
- **Generation loops / repeats**: ensure the latest `app.py` is deployed
  (it passes `<|im_end|>` as the eos token to stop cleanly).
- **401 from the Space**: obtain a fresh Firebase ID token from a signed-in
  client and confirm `FIREBASE_PROJECT_ID` matches its issuer project. Tokens
  are cryptographically verified and arbitrary bearer strings are rejected.
