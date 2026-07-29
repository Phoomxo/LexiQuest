# Flutter Hybrid Voice Integration Implementation Plan

> **Execution rule:** Implement one checkbox group at a time. Every behavior change follows RED → GREEN → REFACTOR, and every GLM-produced patch is reviewed before it is applied.

**Goal:** Connect the existing authenticated OmniVoice WAV API to LexiQuest through a testable Flutter `VoiceService`, while preserving `flutter_tts` as the practice-mode fallback and as the research baseline.

**Architecture:** UI code submits a provider-neutral `VoiceRequest` to `HybridVoiceService`. In practice mode the service tries an in-memory audio cache, requests WAV bytes from `OmniVoiceProvider`, plays them through an injected player, and falls back to `NativeTtsProvider` on an operational failure. In research-evaluation mode the assigned engine is strict: no silent cross-over is allowed because that would contaminate the experiment. Authentication, HTTP, playback, cache, and telemetry are separate injectable boundaries.

**Current API adjustment:** The approved design showed a future JSON response containing `audioUrl`. The implemented Phase 2 API intentionally returns authenticated `audio/wav` bytes with provenance headers. This plan consumes that current binary contract and leaves Firebase Storage/Firestore shared-cache URLs for Phase 4.

**Supported runtime:** Flutter 3.44.7 / Dart 3.12.2. Use `audioplayers ^6.8.1` for cross-platform `BytesSource` playback. The existing `http ^1.6.0` and `flutter_tts ^4.2.5` remain.

---

## Task 0: Repository hygiene before feature changes

**Files:**
- Modify: `.gitignore`
- Move out of repository: `.firecrawl/`
- Untrack but preserve locally: `node_modules/`

- [ ] **Step 1: Preserve the source-search audit**

Resolve both paths first, then move `.firecrawl/` to:

```text
E:\เล่มโปรเจค\LexiQuest_Research_Sources\04_Citation_Audit\firecrawl-search-logs
```

Expected: the search audit remains recoverable outside the application repository.

- [ ] **Step 2: Ignore generated dependency directories**

Add:

```gitignore
node_modules/
.firecrawl/
```

- [ ] **Step 3: Remove only the tracked index entries**

Run:

```powershell
git rm -r --cached -- node_modules
```

Expected: local files remain on disk; Git records their removal from source control.

- [ ] **Step 4: Verify exact scope**

Run:

```powershell
Test-Path -LiteralPath node_modules
git status --short
git diff --check
```

Expected: `node_modules` still exists locally, only index removals and `.gitignore` are reported, and the whitespace check passes.

---

## Task 1: Define provider-neutral voice contracts

**Files:**
- Create: `lib/voice/voice_models.dart`
- Create: `lib/voice/voice_provider.dart`
- Test: `test/voice/voice_models_test.dart`

**Interfaces:**
- `VoiceEngine`: `nativeTts`, `omniVoice`
- `VoiceMode`: `practice`, `researchEvaluation`
- `VoiceRequest`: normalized text, language, voice, speed, content identifiers, mode, assigned engine
- `VoicePlaybackResult`: requested engine, actual engine, fallback/cache flags, request/model provenance
- `VoiceFailure`: typed category safe for UI/telemetry
- `VoiceProvider`: `speak`, `stop`

- [ ] **Step 1: Ask GLM for test-only RED patch**

The prompt must describe validation rules:

- text must be nonblank and at most 500 Unicode code units;
- language is currently `en` or `th`;
- speed is 0.5 through 1.5;
- research mode requires an assigned engine;
- practice mode may omit assignment.

- [ ] **Step 2: Review and apply tests only**

Reject production types or unrelated edits in the RED patch.

- [ ] **Step 3: Run the focused test**

```powershell
flutter test test/voice/voice_models_test.dart
```

Expected: FAIL because the contracts do not exist.

- [ ] **Step 4: Ask GLM for the minimum GREEN implementation**

Provide the actual compiler/test failure. Do not add HTTP, plugins, Firebase, caching, or UI.

- [ ] **Step 5: Review, apply, format, and retest**

```powershell
dart format lib/voice/voice_models.dart lib/voice/voice_provider.dart test/voice/voice_models_test.dart
flutter test test/voice/voice_models_test.dart
```

Expected: PASS.

---

## Task 2: Wrap the existing native TTS provider

**Files:**
- Create: `lib/voice/native_tts_provider.dart`
- Test: `test/voice/native_tts_provider_test.dart`

**Interfaces:**
- Inject a small `NativeTtsAdapter` instead of constructing `FlutterTts` in test code.
- Map `en` to `en-US` and `th` to `th-TH`.
- Preserve the current default speech rate behavior through an explicit mapping.
- A plugin error becomes a typed `VoiceFailure`.
- `stop()` delegates to the adapter.

- [ ] **Step 1: GLM writes behavior tests only**

Cover language, speed, volume, pitch, speech text, stop, and plugin failure.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/voice/native_tts_provider_test.dart
```

Expected: FAIL because `NativeTtsProvider` is missing.

- [ ] **Step 3: GLM writes minimum provider implementation**

The production adapter may import `flutter_tts`; the provider test must use a fake adapter.

- [ ] **Step 4: Run GREEN and the complete Flutter suite**

```powershell
flutter test test/voice/native_tts_provider_test.dart
flutter test
```

Expected: PASS.

---

## Task 3: Acquire Firebase ID tokens behind a boundary

**Files:**
- Create: `lib/voice/voice_auth_token_provider.dart`
- Test: `test/voice/voice_auth_token_provider_test.dart`

**Interfaces:**
- `VoiceAuthTokenProvider.getIdToken({bool forceRefresh = false})`
- Production implementation reads `FirebaseAuth.instance.currentUser`.
- Missing user or missing/empty token is an authentication `VoiceFailure`.
- Tokens must never appear in exception messages, logs, results, or telemetry.

- [ ] **Step 1: GLM writes RED tests with an injected user/token reader**
- [ ] **Step 2: Confirm focused failure**

```powershell
flutter test test/voice/voice_auth_token_provider_test.dart
```

- [ ] **Step 3: GLM writes minimum GREEN implementation**
- [ ] **Step 4: Inspect for token leakage and rerun**

```powershell
rg -n "print|debugPrint|token:" lib/voice/voice_auth_token_provider.dart
flutter test test/voice/voice_auth_token_provider_test.dart
```

Expected: no token logging and tests PASS.

---

## Task 4: Consume the authenticated binary WAV contract

**Files:**
- Create: `lib/voice/omni_voice_provider.dart`
- Test: `test/voice/omni_voice_provider_test.dart`

**Interfaces:**
- Inject `http.Client`, `VoiceAuthTokenProvider`, base `Uri`, and timeout duration.
- POST `/v1/speech` with the Firebase bearer token.
- JSON request fields match the backend: `text`, `language`, `voice`, `speed`, `format`.
- Accept only successful `audio/wav` responses with non-empty bytes.
- Parse `X-Request-ID`, `X-Voice-Engine`, `X-Model-Version`, and `X-Audio-Sample-Rate`.
- Convert 400/401/422/429/503, timeout, network, malformed media, and empty audio into typed failures.
- Retry authentication once with a forced token refresh only after a 401.
- Never retry synthesis automatically for other responses.

- [ ] **Step 1: GLM writes HTTP contract tests only**

Use `package:http/testing.dart` or an injected fake client. Include a test proving the bearer token is not included in exposed errors.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/voice/omni_voice_provider_test.dart
```

- [ ] **Step 3: GLM writes minimum GREEN provider**
- [ ] **Step 4: Run focused and backend contract suites**

```powershell
flutter test test/voice/omni_voice_provider_test.dart
uv run --project backend/voice_api pytest backend/voice_api/tests -q
```

Expected: Flutter and Python contracts both PASS.

---

## Task 5: Play WAV bytes through an injected player

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/voice/voice_audio_player.dart`
- Test: `test/voice/voice_audio_player_test.dart`

**Interfaces:**
- `VoiceAudioPlayer.play(Uint8List bytes)`, `stop()`, and `dispose()`
- Production implementation wraps `audioplayers.AudioPlayer` and `BytesSource`.
- Empty input is rejected before crossing the plugin boundary.
- A playback plugin error becomes a playback `VoiceFailure`.

- [ ] **Step 1: Add the reviewed dependency**

```powershell
flutter pub add audioplayers:^6.8.1
```

- [ ] **Step 2: GLM writes player-boundary RED tests**
- [ ] **Step 3: Run RED**

```powershell
flutter test test/voice/voice_audio_player_test.dart
```

- [ ] **Step 4: GLM writes minimum adapter**
- [ ] **Step 5: Run GREEN**

```powershell
flutter test test/voice/voice_audio_player_test.dart
```

Expected: PASS without invoking a real platform channel.

---

## Task 6: Add bounded in-memory audio caching

**Files:**
- Create: `lib/voice/voice_audio_cache.dart`
- Test: `test/voice/voice_audio_cache_test.dart`

**Interfaces:**
- Deterministic key includes normalized text, language, voice, speed, and model version.
- LRU eviction is bounded by total byte count and entry count.
- Values are copied at the boundary so callers cannot mutate cached bytes.
- No raw spoken text, ID token, UID, or audio is logged.
- Persistent disk and Firebase shared cache remain Phase 4.

- [ ] **Step 1: GLM writes RED tests for hit, miss, stable key, copy safety, and eviction**
- [ ] **Step 2: Run RED**

```powershell
flutter test test/voice/voice_audio_cache_test.dart
```

- [ ] **Step 3: GLM writes minimum GREEN cache**
- [ ] **Step 4: Run GREEN and inspect memory bounds**

```powershell
flutter test test/voice/voice_audio_cache_test.dart
```

Expected: PASS.

---

## Task 7: Orchestrate practice fallback and strict research assignment

**Files:**
- Create: `lib/voice/voice_telemetry.dart`
- Create: `lib/voice/hybrid_voice_service.dart`
- Test: `test/voice/hybrid_voice_service_test.dart`

**Behavior:**
- Practice: cache hit → play OmniVoice bytes; otherwise remote → cache → play; operational remote/playback failure → native TTS.
- Practice authentication failure may fall back but must be tagged distinctly.
- Research/native assignment: native only.
- Research/OmniVoice assignment: OmniVoice only; surface failure and never cross over silently.
- Record engine requested/used, fallback reason category, cache status, latency, content ID/type, request ID, and model version.
- Do not record spoken text, token, email, or other direct personal identifiers.
- New requests stop current remote playback/native speech before starting.
- `stop()` stops both provider paths.

- [ ] **Step 1: GLM writes an orchestration decision matrix as RED tests**

At minimum cover:

1. practice remote success;
2. practice cache hit;
3. practice remote failure → native fallback;
4. research native assignment;
5. research OmniVoice success;
6. research OmniVoice failure without fallback;
7. telemetry privacy fields;
8. superseding request stops previous output.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/voice/hybrid_voice_service_test.dart
```

- [ ] **Step 3: GLM writes minimum GREEN orchestration**
- [ ] **Step 4: Run GREEN**

```powershell
flutter test test/voice/hybrid_voice_service_test.dart
```

Expected: PASS.

---

## Task 8: Compose production dependencies without hard-coded secrets

**Files:**
- Create: `lib/voice/voice_service_factory.dart`
- Create: `lib/config/app_config.dart`
- Test: `test/config/app_config_test.dart`

**Configuration:**
- Read the voice API URL from `--dart-define=LEXIQUEST_VOICE_API_URL=https://...`.
- Reject missing or non-HTTPS production URLs.
- Permit `http://127.0.0.1` and `http://10.0.2.2` only in debug/local development.
- No API key is shipped in Flutter; authentication uses the current Firebase ID token.

- [ ] **Step 1: GLM writes configuration RED tests**
- [ ] **Step 2: Run RED**

```powershell
flutter test test/config/app_config_test.dart
```

- [ ] **Step 3: GLM writes minimum GREEN composition**
- [ ] **Step 4: Secret and endpoint review**

```powershell
rg -n -i "cointh|anthropic_auth_token|api[_-]?key|bearer [a-z0-9]" lib test
flutter test test/config/app_config_test.dart
```

Expected: no gateway/user secret in app source and tests PASS.

---

## Task 9: Migrate the first vertical slice

**Files:**
- Modify: `lib/screens/speak_to_text_screen.dart`
- Test: `test/screens/speak_to_text_screen_voice_test.dart`

**Behavior:**
- Accept an optional injected `VoiceProvider`/service for tests; use the factory by default.
- Keep automatic pronunciation after the first frame.
- Tapping the vocabulary word speaks it again.
- Do not block speech-to-text controls while remote audio is loading.
- Show a small progress indicator and accessible retry/error feedback.
- Dispose/stop owned voice dependencies safely.
- Preserve navigation and scoring behavior.

- [ ] **Step 1: GLM writes widget RED tests**

Cover automatic request, tap replay, request fields, safe error UI, and stop on dispose.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/screens/speak_to_text_screen_voice_test.dart
```

- [ ] **Step 3: GLM writes the minimum screen migration**
- [ ] **Step 4: Run focused and complete tests**

```powershell
flutter test test/screens/speak_to_text_screen_voice_test.dart
flutter test
```

Expected: PASS.

---

## Task 10: Add research-ready telemetry persistence

**Files:**
- Create: `lib/voice/firestore_voice_telemetry.dart`
- Create: `docs/research/voice-telemetry-dictionary.md`
- Test: `test/voice/firestore_voice_telemetry_test.dart`

**Behavior:**
- Write append-only events to a versioned Firestore collection.
- Use pseudonymous Firebase UID only if required for longitudinal linkage.
- Store no text/audio/token/email.
- Include consent/status field, schema version, engine assignment/actual engine, latency, fallback category, cache state, content ID/type, and timestamp.
- A telemetry write failure never blocks learning or audio playback.

- [ ] **Step 1: GLM writes serializer/privacy RED tests**
- [ ] **Step 2: Run RED**

```powershell
flutter test test/voice/firestore_voice_telemetry_test.dart
```

- [ ] **Step 3: GLM writes minimum GREEN serializer/sink**
- [ ] **Step 4: Review data dictionary and run GREEN**

```powershell
flutter test test/voice/firestore_voice_telemetry_test.dart
```

Expected: PASS and every persisted field is documented.

---

## Task 11: Add backend opt-in end-to-end and bilingual golden-set harness

**Files:**
- Create: `backend/voice_api/research/golden_texts.json`
- Create: `backend/voice_api/research/run_golden_set.py`
- Create: `backend/voice_api/tests/integration/test_firebase_omnivoice_e2e.py`
- Create: `backend/voice_api/tests/test_golden_texts.py`
- Modify: `backend/voice_api/README.md`

**Behavior:**
- Golden set contains reproducible Thai and English vocabulary/sentence cases, stable IDs, language, and expected validation metadata.
- Runner writes measurements/review forms outside tracked generated-audio paths.
- Real E2E test is opt-in and skips unless Firebase credentials, test ID token, and GPU/model settings are explicitly supplied.
- No credential, ID token, raw microphone data, or generated WAV is committed.

- [ ] **Step 1: GLM writes schema/coverage RED tests**
- [ ] **Step 2: Run RED**

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests/test_golden_texts.py -q
```

- [ ] **Step 3: GLM writes the minimum dataset and runner**
- [ ] **Step 4: Run backend suite and inspect opt-in skip reason**

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests -q
```

Expected: unit/contract tests PASS; real external E2E is either explicitly PASS or clearly SKIPPED with the missing prerequisite.

---

## Task 12: Final verification, documentation, and PR update

**Files:**
- Modify: `README.md`
- Modify: `backend/voice_api/README.md`
- Modify: relevant architecture/research docs

- [ ] **Step 1: Format and static analysis**

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
```

- [ ] **Step 2: Complete automated suites**

```powershell
flutter test
uv run --project backend/voice_api pytest backend/voice_api/tests -q
git diff --check
```

- [ ] **Step 3: Platform build smoke tests**

Run at least the active thesis demonstration target. Prefer:

```powershell
flutter build apk --debug --dart-define=LEXIQUEST_VOICE_API_URL=https://example.invalid
flutter build windows --debug --dart-define=LEXIQUEST_VOICE_API_URL=https://example.invalid
```

Document any unavailable SDK/toolchain as a verified limitation rather than claiming success.

- [ ] **Step 4: Review privacy, secrets, and artifacts**

```powershell
git status --short
git diff --stat
git diff --name-only
git grep -n -I -E "BEGIN PRIVATE KEY|COINTH_GLM_API_KEY|ANTHROPIC_AUTH_TOKEN|Bearer [A-Za-z0-9_-]{20,}"
```

Expected: no credential, generated audio, model weight, or unrelated user file is staged.

- [ ] **Step 5: Commit in reviewable units**

Use descriptive messages without a `codex` branch prefix, for example:

```text
chore: stop tracking generated dependencies
feat: add hybrid voice service
feat: connect OmniVoice to pronunciation practice
test: add bilingual voice evaluation harness
docs: document voice research telemetry
```

- [ ] **Step 6: Push and update the existing PR**

Push `feature/omnivoice-integration` and update PR #2 only after all applicable gates pass. Summarize external E2E status and research limitations explicitly in the PR body.

---

## Phase 4 follow-up (separate reviewed plan)

- Firebase Storage/Firestore shared audio cache with server-side ownership.
- Persistent on-device cache and eviction policy across app restarts.
- Server job queue, rate limiting, cost quotas, GPU deployment, and autoscaling.
- Consent flow and study-group assignment administration.
- Controlled listening experiment and learning-outcome analysis.
- Pronunciation assessment beyond the existing exact speech-to-text match.
