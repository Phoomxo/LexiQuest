# LexiQuest Runtime Modernization Implementation Plan

> Execute one narrow patch at a time. Cointh/GLM works at maximum effort;
> Codex reviews every proposal and advances only after fresh evidence is green.

**Design:** `docs/superpowers/specs/2026-07-27-runtime-modernization-design.md`

**Branch:** `feature/production-vertical-slices`

**Constraints:** Never start GPU training, never change LexiQuest-LM's
Torch/CUDA pins, never patch the pub cache, and never use a `codex/` branch or
PR prefix.

## Task 1: Voice runtime compatibility guard

**Files**

- Create: `backend/voice_api/tests/test_runtime_compat.py`
- Create: `backend/voice_api/src/lexiquest_voice/runtime_compat.py`
- Modify: `backend/voice_api/src/lexiquest_voice/engines/omnivoice_engine.py`

1. RED: test exact acceptance of Torch `2.8.0+cu128`, Torchaudio
   `2.8.0+cu128`, and OmniVoice `0.2.1`; test missing, CPU, CUDA, and release
   mismatches; test that model loading stops before download.
2. Run the focused tests and retain the expected module/import failure.
3. GREEN: implement a small pure compatibility evaluator plus a fail-fast
   runtime requirement using package metadata. Call it before model download.
4. Run focused tests and the full Voice API CPU suite.
5. Commit: `feat(voice-api): guard OmniVoice runtime compatibility`.

## Task 2: Voice GPU dependency alignment

**Files**

- Create: `backend/voice_api/tests/test_dependency_pins.py`
- Modify: `backend/voice_api/pyproject.toml`
- Regenerate: `backend/voice_api/uv.lock`

1. RED: parse `pyproject.toml` with `tomllib` and require explicit pins for
   `torch==2.8.0+cu128`, `torchaudio==2.8.0+cu128`, and
   `omnivoice==0.2.1`, all Torch packages bound to an explicit CUDA 12.8 index.
2. GREEN: align the GPU group and uv source bindings, then run `uv lock`.
3. Verify the Voice CPU suite with `--no-group gpu`; verify the lockfile and
   prove `backend/lexiquest_lm` Torch/CUDA pins are unchanged.
4. Commit: `fix(voice-api): align OmniVoice CUDA runtime`.

## Task 3: Bounded real inference gate

**Files**

- Modify: `backend/voice_api/tests/integration/test_firebase_omnivoice_e2e.py`
- Create if needed: `tool/cli/voice-smoke.ps1`
- Add focused contract test under `backend/voice_api/tests/`

1. RED: require the opt-in integration test to generate only one short phrase,
   validate a RIFF/WAV payload and positive duration, and remain excluded from
   CPU CI.
2. GREEN: strengthen the existing E2E smoke and, if needed, add a bounded CLI
   entry point that refuses to run unless explicitly enabled.
3. Run the contract and verify the integration test skips when its enable/token
   variables are absent.
4. After all CPU gates pass and no training process is active, run one real
   local inference. Record its actual outcome; never substitute a mocked pass.
5. Commit: `test(voice-api): harden bounded OmniVoice smoke gate`.

## Task 4: Supabase publishable-key contract

**Files**

- Create or modify a focused test under `test/runtime/`
- Modify: `lib/runtime/app_bootstrap.dart`
- Update relevant security documentation and secret allowlist if required

1. RED: prove there is no legacy JWT default, missing/empty configuration maps
   to `RuntimeAvailability.unavailable`, malformed input is rejected, and a
   value using the current `sb_publishable_` format is accepted.
2. GREEN: remove the committed legacy anon JWT and validate the explicit
   `LEXIQUEST_SUPABASE_PUBLISHABLE_KEY` before initialization. Reuse the
   existing bootstrap availability wrapper so the application remains usable.
3. Run focused runtime/widget tests, Flutter analysis, and secret checks.
4. Document Dashboard key rotation and deployed-project parity as user-owned
   release gates.
5. Commit: `fix(bootstrap): require Supabase publishable key`.

## Task 5: Remove unused Flutter dependencies

**Files**

- Modify: `pubspec.yaml`
- Regenerate: `pubspec.lock`
- Verify unchanged simulation contract in:
  `lib/services/ml_image_labeling_service.dart` and its tests

1. Re-run source/import evidence for `cupertino_icons`, `firebase_storage`,
   `provider`, `image_picker`, `fluttertoast`, `confetti`,
   `cached_network_image`, `google_mlkit_image_labeling`, and `camera`.
2. Remove only dependencies with zero executable references and run
   `flutter pub get`.
3. Verify the Object Scanner remains explicitly simulated and makes no
   production-ML claim.
4. Run Flutter analysis, the complete Flutter test suite, and Android debug
   build.
5. Commit: `chore(flutter): remove unused direct dependencies`.

## Task 6: Safe Python dependency updates

Perform three independent patches; never combine their lockfiles.

### 6A - AI API

- RED pin test for `fastapi==0.140.0`.
- Update `backend/ai_api/pyproject.toml` and its `uv.lock`.
- Run the AI API suite with deprecations promoted to errors.
- Commit: `chore(ai-api): update FastAPI to 0.140.0`.

### 6B - Voice API

- Extend its pin test for `fastapi==0.140.0` and `soundfile==0.14.0`.
- Update `backend/voice_api/pyproject.toml` and its `uv.lock`.
- Run the Voice CPU suite and re-check the approved CUDA pair.
- Commit: `chore(voice-api): update API and audio dependencies`.

### 6C - LexiQuest-LM

- RED pin test for `tqdm==4.69.1` and a defensive assertion that
  `torch==2.13.0+cu132` is unchanged.
- Update only tqdm in `backend/lexiquest_lm/pyproject.toml` and its lockfile.
- Run the CPU suite with `--no-group train`.
- Commit: `chore(lm): update tqdm to 4.69.1`.

## Task 7: GitHub Actions major updates

For each action, first change `tool/cli/tests/ci-workflow.tests.ps1` so the
current workflow is RED. Then replace only that action with the official,
reviewed, full 40-character SHA and run the contract test.

1. `actions/checkout`: v4 to v7.
2. `actions/setup-java`: v4 to v6; preserve Temurin Java 21.
3. `actions/setup-node`: v4 to v7; preserve Node 24 and npm cache inputs.
4. Run CI workflow, Dependabot, and action-pin contract tests after each patch.
5. Commit each action independently.

Official release notes and tags must be rechecked at execution time because
action versions are time-sensitive.

## Task 8: Built-in Kotlin compatibility record

**Files**

- Create: `docs/superpowers/notes/2026-07-27-built-in-kotlin-deferral.md`
- Verify: `android/gradle.properties`, Gradle files, Android build output

Record the verified Flutter 3.44.7 / AGP 9.0.1 / Gradle 9.1 strict-mode
failure, preserve `android.builtInKotlin=false` and `android.newDsl=false`, and
identify `flutter_tts` and `speech_to_text` as the remaining upstream plugin
owners. Never patch cached packages. Re-run the Android debug build.

Commit: `docs(android): record Built-in Kotlin compatibility gate`.

## Task 9: Final stabilization and security gate

1. Run `tool/cli/verify.ps1` from a clean working tree.
2. Run Flutter analysis/tests, Android debug build, and all three Python suites
   with their frozen lockfiles.
3. Run CI contracts, Firestore rules tests, Supabase reset/lint/advisors/storage
   contract, dependency audit, Gitleaks, and repository security scan.
4. Review `main...HEAD` for secrets, generated files, model artifacts, and
   unrelated changes.
5. Push `feature/production-vertical-slices` and observe the GitHub PR check
   rollup. Remote Supabase key rotation/parity remains user-owned.
6. Do not declare completion until the same commit is green across all
   applicable local and remote gates.

Actual productive GLM token usage is recorded from gateway telemetry. Deliberate
token waste, padding, or repeated output is prohibited.
