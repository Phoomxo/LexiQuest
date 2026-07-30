# LexiQuest Active Field-Readiness Execution Plan

**Status:** ACTIVE — single implementation plan

**Target:** A release-signed Android APK ready for a 30-participant,
geographically distributed field trial.

**Accepted baseline:** Gates P0-P7 are complete. Their immutable evidence is
recorded under `docs/development/`. This file supersedes every earlier
incremental implementation plan; the approved master design remains the
architecture contract. P8 automation is implemented and fail-closed; physical
device, release-signing, production-control, and owner evidence remain pending.

## 1. Operating rules

1. Work proceeds in dependency order: P4 model lifecycle, P5 camera and speech,
   P6 Gemini BYOK, P7 product completion, then P8 field certification.
2. Each package follows:
   `contract -> failing focused test -> implementation -> focused regression ->
   review -> bounded gate -> commit`.
3. A package does not trigger unrelated full-suite testing. The complete
   release suite runs only for a release candidate or after a release-blocking
   correction.
4. The same failed command is never repeated without a code, configuration, or
   environment change.
5. Participant-visible output must originate from stored evidence, a real
   device input, or a real provider response. Random values, canned success,
   fake confidence, sample cards, and fabricated scores are prohibited.
6. A temporarily unavailable field feature is controlled centrally by the
   production feature registry. It is never made to appear complete by hiding
   a failing assertion or swallowing an error.
7. Drift remains the runtime source of truth. Widgets do not import Firebase,
   HTTP clients, Drift tables, secure storage, or platform plugins directly.
8. Owner-generated platform registrants and unrelated worktree changes remain
   outside implementation commits.

## 2. Cost policy

- Use SQLite/Drift, Firebase emulators, local backend tests, and on-device CPU
  execution for development and automated acceptance.
- Use a redistributable model whose license and checksum are recorded. Do not
  introduce a paid model-hosting dependency.
- Keep GPU opt-in and device allowlisted; CPU/XNNPACK is the safe default.
- Gemini is BYOK. Automated tests use a local fake transport; live acceptance
  uses one bounded owner-provided request set and never a project-funded key.
- Firebase tests use demo projects and emulators. Production access remains
  disabled until rules, App Check policy, budget limits, and kill switches pass.
- Paid cloud/provider work requires an explicit field-acceptance reason,
  bounded request count, and a recorded expected cost.

## 3. Completed foundation — P0 to P3

### Accepted

- Versioned Drift schema, owner-scoped vocabulary/imports, immutable learning
  evidence, outbox, checkpoints, conflicts, ledger, achievements, and model
  download state.
- Offline CRUD/import, process-restart recovery, idempotent Firestore sync,
  Android scheduling contract, cloud kill switch, and guest-to-account
  ownership migration.
- Real local Quiz/SRS/reading evidence and evidence-derived mastery/weakness
  empty states.
- P3 gate: 88 focused Flutter tests, 23 Firestore emulator tests, static
  analysis, debug APK, and follow-up code review passed.

### Hardware evidence intentionally assigned to P8

- WorkManager after force-stop/reboot;
- real device model, camera, microphone, TTS, STT, GPU, and thermal behavior;
- release signing, installation upgrade, and 30-minute endurance.

### Accepted implementation packages P4 to P7

- P4 verified LiteRT lifecycle, resumable model delivery, CPU-safe inference,
  benchmark reporting, and tested GPU allowlisting.
- P5 real camera lifecycle, object inference, microphone/STT, pronunciation
  evidence, and platform-safe fallback states.
- P6 Android Keystore-backed Gemini BYOK, real REST transport, typed provider
  failures, redaction, and evidence-bounded tutor context.
- P7 evidence-derived progress/games, synchronized reward transactions,
  real exports, typed navigation, Material 3/accessibility, complete account
  flows, anonymous cloud namespace rehome, and cloud operations controls.
- Final P7 gate passed format, complete static analysis, bounded product and
  sync regressions, Auth emulator, 25 Firestore rules tests, debug APK,
  model-runtime integrity, diff checks, and independent blocker review.

## 4. P4 — On-device model lifecycle

### P4.1 Inventory and contract freeze

Inspect:

- `pubspec.yaml`
- `lib/services/device_capability_service.dart`
- every model/download/inference service under `lib/`
- related Android Gradle, manifest, ProGuard, and test files.

Create one model manifest domain contract containing model ID, version, source,
license, byte size, SHA-256, input tensor shape/type/normalization, output
labels, minimum app version, and supported delegates.

Exit:

- one selected model and license;
- no duplicate legacy inference path;
- tensor contract covered by a unit test.

### P4.2 Resumable verified download

Implement through the existing `model_downloads` table:

- HTTP range resume into a `.partial` file;
- atomic checkpoint updates;
- timeout, cancellation, bounded backoff, manual retry, and restart recovery;
- exact byte count and streaming SHA-256 verification;
- atomic promotion only after checksum and interpreter validation;
- rollback to the previous valid model when activation fails;
- cleanup restricted to known model-version files.

Tests:

- interruption/resume;
- server ignores range;
- checksum mismatch;
- insufficient storage/write failure;
- cancel/retry;
- invalid interpreter;
- previous-model rollback.

Exit:

- incomplete/corrupt bytes cannot become active;
- valid downloaded bytes are not downloaded again.

### P4.3 LiteRT adapter and benchmark

Implement:

- real LiteRT/TensorFlow Lite interpreter adapter;
- deterministic preprocessing and label decoding;
- CPU/XNNPACK execution and warm-up;
- bounded benchmark reporting median, p90, sample size, peak working set, model
  version, delegate, and device tier;
- GPU delegate behind an exact model/device/driver allowlist with CPU fallback;
- typed failures for unavailable model, invalid input, delegate failure,
  timeout, cancellation, and incompatible tensor contract.

Automated gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-device-model.ps1
```

The gate must run format, analysis, focused model tests, Android debug build,
dependency policy, and diff checks once. Real-device latency and thermal
acceptance remains a P8 matrix item.

## 5. P5 — Camera, scanner, and speech

### P5.1 Camera lifecycle

Replace scanner simulation with ports/use cases for permission, initialization,
preview, capture, pause/resume, rotation, background/foreground, cancellation,
and disposal. Object inference must use the P4 activated model. An accepted
result creates vocabulary through the standard local vocabulary use case.

Tests:

- denied/permanently denied permission;
- initialization and capture failure;
- lifecycle interruption and safe disposal;
- inference cancellation;
- accepted result persistence;
- no random confidence or placeholder label.

### P5.2 Microphone, STT, TTS, and pronunciation

Implement real microphone permission/capture and adapter-backed STT/TTS.
Pronunciation feedback may expose only measurements supported by the selected
engine. Every result carries engine/model, locale, timestamp, and method
provenance. Unsupported pitch/phoneme/acoustic scoring is shown as unavailable,
not estimated.

Tests:

- permission denial;
- silence/no match;
- cancel and lifecycle interruption;
- locale/engine unavailable;
- real transcript mapped into learning evidence;
- no raw audio retained by default;
- TTS start/stop/focus behavior.

Automated gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-camera-speech.ps1
```

P8 supplies real-device permission, camera orientation, STT/TTS, headset,
backgrounding, memory, and thermal evidence.

## 6. P6 — Gemini BYOK and AI Tutor

### P6.1 Secret lifecycle

Create a Gemini key port and Android Keystore-backed adapter supporting add,
validate, replace, and remove. The key must never enter Drift, Firestore,
analytics, crash messages, exported files, or logs. Non-Android field paths
must fail explicitly instead of using plaintext fallback storage.

### P6.2 Provider client and tutor

Implement a cancellable Gemini REST client with bounded timeout and typed
results for:

- invalid key;
- quota/rate limit;
- offline;
- timeout;
- provider outage;
- malformed response;
- safety refusal;
- cancellation.

AI Tutor context is constructed from consented, bounded local learning
summaries and contains no direct personal identifier. Remove canned successful
answers. Local study remains usable with no key or provider outage.

Tests use a local fake HTTP transport and redacted log sink. One bounded live
owner acceptance verifies key validity and response mapping without recording
the key or prompt.

Automated gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-gemini-byok.ps1
```

## 7. P7 — Product completion

P7 is executed in the following fixed order so infrastructure refactors do not
repeatedly invalidate product screens.

### P7.1 Evidence-derived progress and games

Replace remaining sample/default/random data in Mastery Dashboard, Weakness
Clinic, Ghost Shadow Duel, Weakness SRS, AI Tutor, and Shadowing Challenge.
Streak, mastery, weakness, recommendation, score, rank, and game progression
must declare source evidence count and algorithm version.

Exit:

- fresh account has sample size zero;
- projection rebuild is deterministic;
- no `Random`, hard-coded participant records, or fake success path remains in
  enabled field features.

### P7.2 Rewards, shop, equipment, and wallpaper

Implement append-only spend/award transactions, non-negative balance policy,
catalog-version price validation, idempotent purchases, durable ownership,
single equipped item per slot, restore, and guest upgrade. Enable shop surfaces
only after transaction, concurrency, replay, and owner-isolation tests pass.

### P7.3 Export and research integrity

Generate selected real records as CSV, PDF, Anki, and versioned research
dataset. Implement progress, cancellation, permission denial, insufficient
space, write failure, atomic finalization, and partial-file cleanup. Charts and
exports include sample size, time zone, schema/algorithm version, exclusions,
and an explicit no-data explanation.

Acceptance opens each artifact with an independent parser and reconciles counts
to immutable evidence IDs.

### P7.4 Typed navigation and architecture boundaries

Create one typed route graph and migrate every screen. Remove direct Firebase,
HTTP, SharedPreferences, Drift, and plugin imports from presentation. Delete
obsolete route and service paths after all callers migrate; do not leave two
runtime data spines.

Architecture tests scan all participant screens, not only the learning subset.

### P7.5 Material 3, Thai, accessibility, and dark mode

Consolidate one Material 3 theme, remove inconsistent legacy styling, reduce
decorative gradients/emoji, verify Thai text/encoding, 48dp touch targets,
system text scaling, contrast, focus order, semantic labels, keyboard insets,
and dark mode. Golden tests cover only stable critical screens; device
acceptance covers font rendering and touch behavior.

### P7.6 Account and cloud operations

Complete registration, login, email verification, forgot/reset password,
Android App Links, password change, logout, anonymous binding, and guest
upgrade. Run Auth/Firestore emulator journeys and rules tests. Implement App
Check enforcement rollout policy, cloud kill switch verification, privacy-safe
support logs, and documented Firebase budget alerts at 50%, 80%, and 100%.

Upgrade Android Gradle Plugin and Kotlin to supported Flutter versions in this
package, with clean debug/release builds and plugin compatibility tests.

Automated gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-product-completion.ps1
```

## 8. P8 — Field certification and release

### P8 implementation status

Implemented locally:

- versioned, owner-scoped research consent with explicit acceptance,
  withdrawal, and continued offline learning after decline/withdrawal;
- research export that fails closed without active consent while personal
  CSV/PDF/Anki export remains available;
- release packaging that requires owner-controlled signing material, verifies
  the APK certificate, and records APK/model hashes and build identity;
- physical-device evidence collection that rejects emulators, pseudonymizes
  device serials, installs the exact APK, and leaves unexecuted journeys
  `pending`;
- one evidence assembler and one strict final gate covering three device tiers,
  mandatory journeys, CPU/XNNPACK, honest GPU availability, 30-minute
  endurance, Cloud controls, participant documents, and owner approval;
- Thai installation, privacy/consent, data/export/delete, feedback/support,
  known-limitations, and release-operator documentation.

External acceptance remains open and cannot be synthesized by the repository:

- dedicated release keystore and `android/key.properties`;
- one low-, one mid-, and one high-tier physical Android device;
- production App Check, budget alerts, asset links, and kill-switch evidence;
- approved private research protocol and real feedback/support channels;
- completed real-device journeys, endurance records, and owner smoke approval.

Current evidence is recorded in
`docs/development/p8-field-certification-gate-2026-07-30.md`.

### P8.1 Automated participant journeys

Run one bounded release candidate suite covering:

- consent and guest startup;
- offline vocabulary CRUD/import;
- Quiz, SRS, reading, progress, rewards, and exports;
- offline -> force-stop -> restart -> online -> exactly-once sync;
- account registration/verification/reset/upgrade/logout;
- model download interruption/resume/checksum;
- camera scanner, STT, TTS, pronunciation, and Gemini errors;
- clean install, upgrade install, device reboot, foreground/background;
- cloud kill switch with uninterrupted local learning.

### P8.2 Three-tier Android matrix

Record device model, Android version, RAM, chipset/GPU, storage, app/build,
model checksum, delegate, and network. On low-, mid-, and high-tier devices run:

- cold/warm launch;
- CPU/XNNPACK benchmark;
- GPU correctness/stability only where allowlisted;
- camera rotation/background lifecycle;
- microphone, STT, TTS, and headset paths;
- Gemini live acceptance;
- 30-minute continuous learning for crash/ANR, RAM, battery, and temperature.

Any failed mandatory journey blocks release. A feature may be `limited` only
with a documented device/provider allowlist and an honest unavailable state.

### P8.3 Participant release package

Produce:

- release-signed APK and separately stored signing material;
- SHA-256, signature certificate, version code/name, build ID, and model hash;
- install/update guide;
- privacy notice and versioned consent;
- data/export/delete explanation;
- feedback and support channel;
- known limitations and recovery steps;
- owner smoke-test record and distribution approval.

Final command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-field-release.ps1
```

The final gate fails if any enabled feature contains sample/random/canned
participant output, any screen crosses an infrastructure boundary, any required
device result is missing, or the APK/signature/evidence manifest does not
reconcile.

## 9. Completion definition

Work is complete only when the P8 release gate passes, the owner smoke test is
approved, and the recorded APK can be installed by the 30 participants. Until
then, every incomplete item remains visible in this plan and in its current
gate record; no unresolved defect is relabeled as complete.
