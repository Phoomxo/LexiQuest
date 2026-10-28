# LexiQuest P8-B Hybrid Voice Implementation Plan

**Status:** COMPLETE — accepted gate PASS; see
`docs/development/p8b-hybrid-voice-gate-2026-07-31.md`

**Scope:** Standard VoxCPM2 target speech, downloadable standard audio packs,
dynamic standard speech, provider kill switch, Native TTS fallback, and a
bounded P8-B gate.

**Out of scope:** Participant voice enrollment, cloning, mirroring, embeddings,
or session cleanup. Those remain P8-C.

**Upstream:** P8-A commits through `7eaa7b2`.

**Reference:** [OpenBMB/VoxCPM](https://github.com/OpenBMB/VoxCPM). The current
upstream documents the `voxcpm` Python package, `openbmb/VoxCPM2`, 48 kHz
output, Python 3.10–3.12 support, and Apache-2.0 licensing.

## Delivery rules

- Use TDD: demonstrate RED, make the smallest production change, then run the
  focused test.
- Give GLM one bounded file task at a time. Codex reviews every change and runs
  the authoritative commands.
- Never bundle the multi-gigabyte VoxCPM model in the Android APK.
- Never log request text, authorization, participant identifiers, raw provider
  responses, or local file contents.
- Standard audio packs may contain only approved learning text and a standard
  synthetic voice.
- Keep Native TTS available when packs, network, provider, quota, or model are
  unavailable.
- Do not report GPU/model or physical-device acceptance without real evidence.
- Every retry count, timeout, input length, download size, and concurrency path
  must be bounded.

## Dependency order

1. Backend VoxCPM2 standard-speech adapter.
2. Backend runtime selection, health, and kill switch.
3. Flutter VoxCPM standard provider and registry wiring.
4. Trusted audio-pack manifest and pack builder.
5. Resumable verified pack installation and atomic activation.
6. Offline pack playback and deterministic fallback.
7. Dynamic quota and safe failure mapping.
8. Bounded P8-B gate and evidence.

## Task 1: Audit the P8-A seams and freeze the P8-B file map

**Read-only inputs:**

- `backend/voice_api/src/lexiquest_voice/engines/base.py`
- `backend/voice_api/src/lexiquest_voice/engines/omnivoice_engine.py`
- `backend/voice_api/src/lexiquest_voice/config.py`
- `backend/voice_api/src/lexiquest_voice/main.py`
- `lib/voice/voice_service_factory.dart`
- `lib/voice/voice_provider_registry.dart`
- `lib/voice/synthesized_voice_route_handler.dart`
- existing device-model download manager and its tests

**Output:** Update this plan only if an exact interface or path differs from the
tasks below. Do not write production code during the audit.

**Acceptance:** The file map is consistent with the committed P8-A branch and
P8-C behavior is absent.

## Task 2: Add the backend VoxCPM2 standard-speech engine

**Files, one at a time:**

- Create test: `backend/voice_api/tests/test_voxcpm_engine.py`
- Create production: `backend/voice_api/src/lexiquest_voice/engines/voxcpm_engine.py`
- Modify dependency declaration: `backend/voice_api/pyproject.toml`

**RED contract:**

- optional `voxcpm` import occurs only inside the default loader;
- loading is lazy and serialized;
- synthesis is serialized and calls `generate(text=...)` without reference or
  participant audio;
- empty/non-finite output fails closed;
- WAV output is 48 kHz;
- result provenance is `engine=voxcpm2` with configured model version;
- exceptions and logs contain no request text.

```powershell
Push-Location backend/voice_api
uv run --group dev pytest tests/test_voxcpm_engine.py -q
Pop-Location
```

Implement a `VoxCpmEngine` conforming to `SpeechEngine`, with injected loader
and WAV writer for plugin-free tests. Pin `voxcpm` and its runtime extras in a
separate optional dependency group so backend unit tests do not download model
weights or require CUDA. Keep `openbmb/VoxCPM2` configurable; do not place
weights in this repository.

**Commit:** `feat(voice-api): add VoxCPM2 standard speech engine`

## Task 3: Select and disable backend engines deterministically

**Files, one at a time:**

- Modify test: `backend/voice_api/tests/test_config.py`
- Create test: `backend/voice_api/tests/test_engine_factory.py`
- Modify production: `backend/voice_api/src/lexiquest_voice/config.py`
- Create production:
  `backend/voice_api/src/lexiquest_voice/engines/factory.py`
- Modify test: `backend/voice_api/tests/test_app.py`
- Modify production: `backend/voice_api/src/lexiquest_voice/app.py`
- Modify production: `backend/voice_api/src/lexiquest_voice/main.py`
- Modify documentation: `backend/voice_api/README.md`

Add validated settings for `engine_backend` (`voxcpm2` or `omnivoice`),
`provider_enabled`, model ID/version, device, sample rate, maximum input length,
generation steps, and bounded request concurrency. The factory is the sole
runtime selector. `provider_enabled=false` must keep liveness available while
readiness and synthesis fail with the existing safe typed provider-disabled
response. No request may enter an engine when disabled. `main.py` loads exactly
one selected engine.

```powershell
Push-Location backend/voice_api
uv run --group dev pytest tests/test_config.py tests/test_engine_factory.py tests/test_app.py -q
Pop-Location
```

**Commit:** `feat(voice-api): select and gate speech engines`

## Task 4: Register a provider-neutral VoxCPM standard client

**Files, one at a time:**

- Create test: `test/voice/vox_cpm_standard_provider_test.dart`
- Create production: `lib/voice/vox_cpm_standard_provider.dart`
- Modify test: `test/voice/voice_service_factory_test.dart`
- Modify production: `lib/voice/voice_service_factory.dart`
- Modify test: `test/voice/voice_policy_test.dart`
- Modify production only if RED requires it: `lib/voice/voice_policy.dart`

The Flutter adapter uses the existing authenticated `/v1/speech` boundary but
declares `VoiceEngine.voxCpmStandard`, supports only standard and dynamic target
speech, uses only `VoicePrivacyScope.standardContent`, accepts WAV only, applies
one forced token refresh after the first 401, enforces the existing 500
character ceiling, and maps provider-disabled, quota, timeout, model, network,
and synthesis failures to the P8-A taxonomy. It must not support
`sessionVoiceMirror`.

Factory wiring registers VoxCPM only when the endpoint and Cloud/provider
switch permit it. Policy prefers verified offline packs for standard content,
then VoxCPM standard speech when online, with Native TTS as deterministic
fallback. Existing OmniVoice remains selectable for rollback but is not
presentation-facing.

```powershell
flutter test test/voice/vox_cpm_standard_provider_test.dart `
  test/voice/voice_service_factory_test.dart `
  test/voice/voice_policy_test.dart --reporter compact
```

**Commit:** `feat(voice): register VoxCPM standard provider`

## Task 5: Define and build trusted standard audio packs

**Files, one at a time:**

- Create test: `test/voice/standard_voice_pack_manifest_test.dart`
- Create production: `lib/voice/standard_voice_pack_manifest.dart`
- Create fixture:
  `tool/voice_pack/fixtures/approved-standard-voice-content.json`
- Create test: `tool/cli/tests/build-standard-voice-pack.tests.ps1`
- Create production: `tool/cli/build-standard-voice-pack.ps1`

The manifest validates pack ID, semantic version, locale, standard voice ID,
engine/model version, Apache-2.0 license reference, minimum app version,
generation time, total bytes, and per-file content ID, normalized-text SHA-256,
byte size, audio SHA-256, and relative path. Paths must reject absolute paths,
traversal, collisions, and case-insensitive duplicates.

The builder reads only the approved content fixture, calls the authenticated
standard-speech endpoint or a test generator command, writes deterministic
file names, hashes actual bytes, and emits canonical JSON. It must be
cancellable and must delete an incomplete output directory on failure. Tests
use tiny WAV fixtures and no network/model.

```powershell
flutter test test/voice/standard_voice_pack_manifest_test.dart
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/tests/build-standard-voice-pack.tests.ps1
```

**Commit:** `feat(voice): define reproducible standard audio packs`

## Task 6: Download, verify, and atomically activate packs

**Files, one at a time:**

- Create test: `test/voice/standard_voice_pack_download_manager_test.dart`
- Create production: `lib/voice/standard_voice_pack_download_manager.dart`
- Create test: `test/voice/http_standard_voice_pack_source_test.dart`
- Create production: `lib/voice/http_standard_voice_pack_source.dart`
- Create test: `test/voice/file_standard_voice_pack_store_test.dart`
- Create production: `lib/voice/file_standard_voice_pack_store.dart`

Mirror the proven model-download lifecycle without sharing model-specific
types. Required behavior: HTTPS only; manifest maximum pack/file counts and
byte ceilings; free-space preflight; `.partial` resume through valid HTTP 206
and matching `Content-Range`; clean restart on HTTP 200; rejection of all other
responses; bounded retry count with deterministic backoff; cancellation;
streaming byte ceiling and SHA-256; per-file verification; staging directory;
atomic active-pointer replacement; recovery after restart; no partial or
corrupt pack can become active.

```powershell
flutter test test/voice/standard_voice_pack_download_manager_test.dart `
  test/voice/http_standard_voice_pack_source_test.dart `
  test/voice/file_standard_voice_pack_store_test.dart --reporter compact
```

**Commit:** `feat(voice): install verified resumable audio packs`

## Task 7: Serve offline packs and bound dynamic synthesis

**Files, one at a time:**

- Create test: `test/voice/installed_voice_pack_provider_test.dart`
- Create production: `lib/voice/installed_voice_pack_provider.dart`
- Modify test: `test/voice/voice_service_factory_test.dart`
- Modify production: `lib/voice/voice_service_factory.dart`
- Create test: `test/voice/voice_request_quota_test.dart`
- Create production: `lib/voice/voice_request_quota.dart`
- Modify test: `test/voice/vox_cpm_standard_provider_test.dart`
- Modify production: `lib/voice/vox_cpm_standard_provider.dart`

The installed-pack provider resolves only a manifest-approved `contentId` whose
normalized-text hash matches the request, returns the verified file, and never
falls back to an unverified path. Dynamic synthesis uses an in-memory bounded
concurrency and per-session request/character quota, fixed timeout, no automatic
retry inside the provider, and standard-content cache only. Quota exhaustion
maps to `rateLimited`, after which the orchestrator may use Native TTS. Add
factory ownership/disposal for pack resources without changing screen code.

```powershell
flutter test test/voice/installed_voice_pack_provider_test.dart `
  test/voice/voice_request_quota_test.dart `
  test/voice/vox_cpm_standard_provider_test.dart `
  test/voice/voice_service_factory_test.dart --reporter compact
```

**Commit:** `feat(voice): prefer verified packs and bound dynamic speech`

## Task 8: Close the bounded P8-B gate

**Files, one at a time:**

- Create contract test:
  `tool/cli/tests/verify-hybrid-voice.tests.ps1`
- Create gate: `tool/cli/verify-hybrid-voice.ps1`
- Create evidence:
  `docs/development/p8b-hybrid-voice-gate-2026-07-31.md`
- Modify design status only after PASS:
  `docs/superpowers/specs/2026-07-31-p8-hybrid-voice-field-release-design.md`

The gate runs each phase once and stops on first failure:

1. Dart format for changed voice/runtime files;
2. `flutter analyze`;
3. focused Flutter P8-A/P8-B tests;
4. all backend voice API unit tests without the optional model/GPU group;
5. pack-builder contract with deterministic fixture;
6. debug APK build;
7. `git diff --check`.

Evidence records exact source commit, Flutter/Dart/Python/uv versions, test
counts, fixture pack hash, APK bytes/hash, analyzer result, backend optional
runtime status, and warnings. It must say that real VoxCPM2 model loading/GPU
latency, physical-device audio quality, and all participant voice mirroring
remain uncertified.

**Commit:** `test(voice): close P8-B hybrid voice gate`

## P8-B completion boundary

P8-B is complete only after its accepted CLI gate passes and evidence records
the exact source commit, backend tests, Flutter tests, analyzer result, debug
APK hash, and pack fixture hash. This package does not certify a real VoxCPM2
GPU worker, a physical Android device, or participant voice mirroring.
