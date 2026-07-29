# LexiQuest Vertical-Slice Production Integration Design

- **Date:** 2026-07-26
- **Primary platform:** Android
- **Secondary verification:** Windows and Web smoke tests
- **Compatibility targets:** iOS, macOS, and Linux source/build compatibility
- **Initial deployment:** Research/debug Android build using authenticated
  local workstation services over a trusted LAN; release builds continue to
  require HTTPS
- **AI authoring:** Cointh/GLM GLM-5.2 with maximum effort, supervised and
  verified locally

## 1. Goal

Transform the current collection of tested LexiQuest screens, services, and
backends into one coherent Android application whose production navigation,
authentication, data flow, voice path, AI path, device input, learning
telemetry, and exports work end to end.

The work proceeds in independently testable vertical slices. A slice is
complete only when a user can enter through the production app entry point,
perform the activity, observe an explicit success or fallback state, and
persist or export the resulting data as designed.

## 2. Constraints

1. Do not stop, reprioritize, attach to, or start another CUDA workload while
   the active LexiQuest-LM LoRA training process is running.
2. GPU-dependent Voice API and model-serving acceptance tests run only after
   training exits and GPU memory is released.
3. CPU-only Flutter, Python unit, static-analysis, formatting, and pure service
   tests may run while training continues.
4. Android is the production acceptance platform for this integration.
5. Windows and Web receive smoke verification. iOS and macOS retain permission
   and source compatibility. Linux must render a stable "Firebase unavailable"
   state instead of terminating; full Firebase support on Linux is not claimed.
6. No server credential, service-role key, private signing key, model-provider
   key, or bearer token is embedded in Flutter source, build artifacts,
   prompts, logs, telemetry, or Git. Firebase and Supabase publishable client
   identifiers are not secrets, but are centralized and documented separately
   from server credentials.
7. Feature branches and pull requests use research-appropriate names without
   a `codex` prefix.
8. Behavior changes use RED-GREEN-REFACTOR. Cointh/GLM proposes bounded
   test-only RED and production-only GREEN patches; the supervising agent
   reviews, applies, formats, and verifies every patch.

## 3. Delivery Strategy

The integration is split into five programs. Programs are ordered by runtime
dependency, but tasks within a program remain small enough for independent
review.

The implementation plan must execute the following dependency order:

1. GPU-training guard and CLI probes.
2. Centralized public-client configuration and server-secret boundaries.
3. Android debug-LAN connectivity, backend binding, and health diagnostics.
4. Application composition root, runtime status, and anonymous Firebase guest.
5. Canonical navigation with a legacy-feature drawer.
6. Learning event and vocabulary/progress repository boundaries.
7. Real device input: speech recognition, ML Kit labels, sound levels, and
   honestly labelled transcript/phoneme measurements.
8. Real Anki, CSV, PDF, and thesis exports.
9. AI serving provenance and authenticated local model proxy.
10. GPU-dependent OmniVoice and local LexiQuest-LM acceptance only after the
    LoRA training guard reports that training has exited.

### Program A: Production shell and runtime foundation

This program does not require GPU access and starts immediately.

- Replace the legacy `/home` destination with the canonical
  `MainNavigationScreen`.
- Preserve legacy category, vocabulary, shop, and settings functionality in a
  canonical navigation drawer. Keep the five destinations in
  `MainNavigationScreen` as the bottom navigation bar; do not exceed five
  bottom destinations.
- Remove the extra "enter learning center" navigation hop.
- Add a single application bootstrap/composition boundary for Firebase,
  Supabase Storage, app configuration, and runtime service health.
- Convert Guest Mode to Firebase anonymous authentication so secured AI and
  voice requests can acquire a real ID token. If anonymous authentication is
  disabled remotely, show a blocking, actionable guest-login message instead
  of silently creating an unauthenticated session.
- Add a runtime status model with explicit states: `live`, `nativeFallback`,
  `offline`, `misconfigured`, and `checking`.
- Add CLI launch commands for Android emulator and physical Android devices.
  Emulator defaults use `10.0.2.2`; physical-device commands require an
  explicit LAN host.
- Add a debug-only Android network security policy that permits cleartext
  traffic for research/LAN builds. `AppConfig` accepts loopback, emulator, and
  RFC1918 private addresses only in debug. Release builds accept HTTPS only.
- Start device-facing FastAPI services on `0.0.0.0` through the CLI while
  keeping the model-provider service bound to `127.0.0.1`; print the exact
  Windows Firewall/LAN exposure and never expose model-provider ports directly.
- Add an application version/build identifier to the settings/about surface so
  an old installed artifact is immediately distinguishable.

### Program B: Live AI and voice vertical slices

CPU-only contracts, configuration, and fake-server integration tests start
immediately. GPU inference acceptance waits for training to finish.

- Standard runtime route:
  `Flutter -> LexiQuest AI API /v1/content -> loopback-only
  OpenAI-compatible provider`.
- Local provider preference after training:
  `local LexiQuest-LM server on 127.0.0.1:8002 -> explicitly configured
  Ollama -> explicitly configured Gemini fallback`.
- The local LexiQuest-LM server is a new workstation runtime derived from the
  serving contract, not the existing Hugging Face Space. It binds to loopback,
  is reachable only through the Firebase-authenticated AI API, and does not
  start while LoRA training is active.
- The existing Hugging Face Space remains an optional later deployment target.
  Flutter never calls it directly. Before use, requests must pass through a
  Firebase-verifying proxy; the Space's current bearer-prefix soft gate is not
  production authentication.
- Standard voice route:
  `Flutter -> LexiQuest Voice API /v1/speech -> OmniVoice -> WAV player`.
- Practice voice falls back to native TTS on recoverable remote failure.
- Research evaluation never silently changes its assigned engine.
- Configure `FirestoreVoiceTelemetrySink` in production composition.
- Persist privacy-safe content-generation telemetry containing identifiers,
  kind, model version, cache status, latency, outcome, and fallback category;
  never persist prompt text, generated text, audio bytes, email, or tokens.
- AI Tutor visually labels live-model and offline fallback replies.
- AI responses include `servedProvider`, `servedModel`, `usedFallback`, and
  `cached`. These fields are produced by the provider that actually served the
  request, preserved through cache entries, returned by AI API, parsed by
  Flutter, rendered in AI Tutor, and included in privacy-safe telemetry.
- Health checks expose backend state before a user enters a dependent feature.
- The local CLI starts AI API and Voice API as separate processes, writes
  bounded logs, verifies `/health/live` and `/health/ready`, and stops only
  processes it started.
- While LoRA training is active the CLI may start only the CPU-safe AI API
  contract layer with a fake/unavailable provider for tests. It refuses to
  start Voice API, GPU Ollama, or the local LexiQuest-LM server. It never changes
  `LEXIQUEST_VOICE_DEVICE` to bypass the guard.

### Program C: Real Android device-input features

- Replace the AI Tutor's delayed canned microphone input with
  `speech_to_text` recognition and permission/error states.
- Replace Object Scanner's empty production implementation with actual
  `camera/image_picker -> InputImage -> Google ML Kit ImageLabeler` inference.
- Map detected labels into `ObjectVocabularyDatabase`; unknown labels remain
  visible but are not fabricated as known vocabulary.
- Replace randomized Shadowing waveform data with microphone sound-level
  samples.
- Capture recognized speech for transcript-based pronunciation comparison.
- Replace constant reference/user pitch data with values derived from captured
  audio when supported. On platforms without pitch extraction, hide the pitch
  comparison and show transcript/phoneme results rather than simulated data.
- Persist pronunciation outcome, score, engine, duration, and CEFR metadata
  without retaining raw audio by default.
- Android permissions are requested at point of use. iOS permission
  descriptions are added for source/build compatibility.

## 4. Learning, Gamification, and Research Data

### Program D: One learning event pipeline

Introduce a provider-neutral `LearningEvent` boundary. Screens emit events;
consumers calculate progress, research measures, and recommendations.

Allowed event fields include:

- anonymous/pseudonymous user identifier;
- event schema version and UTC timestamp;
- activity and content identifiers;
- CEFR level and skill dimension;
- correctness, bounded score, response time, attempt number;
- requested/actual engine and fallback category;
- app version and experiment assignment.

Events must not contain passwords, Firebase tokens, email addresses, complete
free-form conversations, raw microphone audio, or camera images.

The pipeline connects:

- SRS and interleaved scheduling;
- streak and daily quests;
- achievements and rank;
- weakness clinic;
- ZPD recommender and auto tuner;
- adaptive decay;
- cognitive attention metrics;
- rapid naming speed;
- lexical diversity;
- K-Means learner profile;
- Apriori error patterns;
- ghost model and ghost duel;
- Brahmawong E1/E2, Cohen's d, CRISP-DM, and dataset partitioning.

Services that cannot consume a real event or produce a user/research outcome
after this integration are removed from production exports rather than left as
unreachable claims.

The integration inventory is the 54 service files recorded by the repository
audit. A static architecture test maintains an explicit service registry with
one of `runtime`, `researchOffline`, or `retired`. Every `runtime` service must
have a production composition reference and behavior test. A service name may
claim an algorithm such as K-Means, Apriori, pronunciation scoring, or pitch
analysis only when its implementation and validation match that algorithm;
threshold bucketing and character edit distance must be labelled honestly.

Firestore becomes the cross-device source of truth for authenticated progress.
SharedPreferences remains a bounded offline cache and migration source.
Migration uses an explicit schema version, deterministic document identifiers,
per-record `updatedAtUtc`, last-write-wins for scalar settings, set union for
mastered content identifiers, and maximum-value merge for achievement/progress
milestones. Migration writes are idempotent, retain the local source until a
remote acknowledgement, and provide a rollback/export path. The existing
`vocabulary`, `categories/{id}/words`, and `global_words` structures receive
explicit repository adapters; screens no longer choose collections directly.

Voice telemetry writes to `voice_telemetry_events`. AI content telemetry uses a
parallel `ai_content_telemetry_events` sink and schema. Learning events use
`learning_events/{eventId}`. All three share pseudonymous identity, UTC time,
app version, experiment fields, retention documentation, and a strict content
denylist.

Supabase remains image storage for this phase. Its public project
configuration moves behind build-time configuration, while provider secrets
remain server-side.

## 5. Real Import and Export

### Program E: Research-ready files and platform completion

- Wordbook CSV/JSON import validates rows, reports rejected records, and saves
  accepted words through the vocabulary repository.
- Anki export writes a UTF-8 tab-separated file.
- Research export writes a UTF-8 CSV with a versioned header.
- Glossary and research reports create actual PDF files rather than text
  previews labelled as PDF.
- Android exports use an app-owned temporary/documents directory and the
  platform share sheet. Tests use injected filesystem and share boundaries.
- Thesis tables remain available as Markdown and LaTeX.
- Export screens use the signed-in user's real selected dataset, not built-in
  sample records.
- Every export includes schema/app version and generation timestamp.

## 6. Error Handling and Offline Behavior

1. Configuration failures are caught at a feature boundary and rendered as a
   stable status card; they must not crash widget initialization.
2. Network failures expose retry and fallback actions.
3. Guest authentication failure explains how to enable anonymous Firebase
   authentication or use a registered account.
4. Backend errors use stable machine codes and privacy-safe user messages.
5. Native TTS fallback is explicit in the UI and telemetry.
6. AI canned fallback is explicit and never presented as a live-model answer.
7. Features whose real sensor/provider is unavailable hide fabricated charts
   and show an unavailable state.
8. Export failures preserve the underlying data and allow retry.

## 7. CLI Runtime

PowerShell scripts under `tool/cli/` provide the supported local workflow:

- `doctor.ps1`: validates Flutter, Android tooling, Python 3.11 environments,
  Firebase configuration presence, required build defines, LAN address, ports,
  model/adapter presence, and whether GPU training is active.
- `start-backends.ps1`: starts CPU-safe services immediately; refuses to start
  CUDA voice/model processes while LoRA training is active unless the training
  process has exited.
- `run-android.ps1`: runs the app with explicit Voice and AI URLs for emulator
  or physical-device LAN mode.
- `verify.ps1`: runs format checks, analyzer, Flutter tests, backend tests,
  contract tests, and optional real E2E tests.
- `stop-backends.ps1`: stops only processes recorded by the CLI runtime state.

Scripts fail closed on missing configuration and print secrets only as
`SET/UNSET`, never values.

The GPU guard detects the active `lora_finetune.py --train` process and checks
VRAM use. It prohibits OmniVoice on `cuda:0`, local LexiQuest-LM serving, and
GPU-backed Ollama until that process exits. The guard is tested with injected
process/GPU probes so verification does not start CUDA work.

## 8. Testing and Acceptance

### Automated gates

- `flutter analyze` reports zero issues.
- All Flutter unit and widget tests pass.
- Voice API, AI API, and LexiQuest-LM tests pass without unexpected warnings.
- A production-shell widget/integration test proves
  `login/anonymous guest -> canonical home -> learning mode`.
- Contract tests prove Flutter paths match backend paths and response schemas.
- Provider-provenance tests prove primary, fallback, and cached responses retain
  the actual serving provider/model without exposing credentials.
- Fake-server integration tests cover AI success, voice success, auth refresh,
  cache state, timeout, fallback, and privacy-safe telemetry.
- Object Scanner tests exercise a real production adapter boundary with an
  injected labeler.
- Shadowing tests prove no randomized, self-compared, or constant simulated
  measurement is presented as captured user data. Transcript similarity is
  labelled `transcriptSimilarity`, not pronunciation accuracy. A
  `pronunciationScore` is shown only when a phoneme/acoustic scorer has valid
  captured input and a documented scoring method.
- Export tests inspect actual Anki, CSV, and PDF file bytes.

### Android acceptance

After LoRA training exits:

1. Start local backends through the CLI.
2. Verify device-facing health endpoints from the workstation and Android
   device; verify the provider port remains loopback-only.
3. Run the Android app against emulator or explicit LAN URLs.
4. Authenticate as a registered or anonymous Firebase user.
5. Complete vocabulary CRUD and a quiz.
6. Generate a live AI response and verify its model/fallback label.
7. Play remote OmniVoice audio, stop only the CLI-owned Voice API process, and
   verify one explicit native fallback before restarting it.
8. Capture real speech in AI Tutor and Shadowing.
9. Label a real camera/gallery image with ML Kit.
10. Verify learning events affect SRS, streak, achievement, weakness, and
    research views.
11. Export Anki, CSV, and PDF files and open/share them.
12. Install a newly versioned debug/release artifact and verify its build
    identifier.

### Secondary acceptance

- Windows and Web start and render the canonical shell.
- Unsupported sensor behavior is explicit and non-fabricated.
- iOS/macOS project files retain valid configuration and permission
  declarations. Linux renders a stable unsupported-Firebase state unless a
  Linux Firebase configuration is added later.

## 9. Git and Review

- Work occurs on `feature/wip-incomplete-system` until a research-appropriate
  integration branch is created by the implementation plan.
- Each vertical slice is committed independently after focused and regression
  verification.
- Generated models, checkpoints, credentials, runtime PID files, logs, and
  local endpoint configuration remain outside Git.
- A new pull request is opened only after Android acceptance or is clearly
  marked draft with an exact remaining E2E checklist.

## 10. Completion Definition

The integration is complete when the installed Android build opens the
canonical application shell; all user-visible production features use real
input or explicitly labelled fallback/unavailable states; AI and voice operate
through the supported local CLI deployment; learning outcomes flow into
persistent progress and research analytics; exports create real files; and the
full automated and Android acceptance gates pass without interrupting the LoRA
training workload.
