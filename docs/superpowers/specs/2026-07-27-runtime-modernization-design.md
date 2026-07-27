# LexiQuest Runtime Modernization Design

- **Date:** 2026-07-27
- **Branch:** `feature/production-vertical-slices`
- **Status:** Approved for implementation
- **Predecessors:** stabilization gate and production vertical-slice design
- **Authoring model:** Cointh/GLM proposes one narrow patch at maximum effort;
  Codex reviews, tests, and applies only validated output.

## Goal

Modernize the post-stabilization runtime safely: align the Voice API with
OmniVoice's supported runtime, repair the Supabase publishable-key contract,
remove unused Flutter dependencies, apply low-risk Python and GitHub Actions
updates, and define the gate for a future Built-in Kotlin migration.

## Non-goals

- Do not change the LexiQuest-LM training stack except the separately tested
  `tqdm` patch update. Its Torch/CUDA environment stays on
  `torch==2.13.0+cu132`.
- Do not start or resume GPU training. One bounded Voice API inference smoke
  test is allowed only after CPU and static gates pass.
- Do not present the simulated Object Scanner as production ML or implement its
  ML pipeline in this modernization.
- Do not force strict Built-in Kotlin while Flutter 3.44.7 fails inside its own
  Gradle plugin under that configuration.
- Do not patch the pub cache or embed production credentials.
- Do not use a `codex/` prefix in branch or pull-request names.

## Risks, highest first

1. **Critical - Voice runtime mismatch.** The current environment combines
   `torch 2.13.0+cu132`, `torchaudio 2.11.0+cpu`, and `omnivoice 0.2.1`.
   OmniVoice's supported pair is `torch==2.8.0+cu128` and
   `torchaudio==2.8.0+cu128`. Inference is therefore not reproducible.
2. **High - Supabase key contract drift.** Flutter names the configuration a
   publishable key but commits a legacy anon JWT as its default.
3. **High - unnecessary Flutter supply surface.** Nine direct dependencies
   have no source imports. Two also add obsolete Kotlin Gradle Plugin users.
4. **Medium - strict Built-in Kotlin is not yet viable.** Enabling it now
   breaks the Flutter toolchain; `flutter_tts` and `speech_to_text` remain
   upstream blockers.
5. **Medium - GitHub Actions major-version drift.** Current workflow actions
   are SHA-pinned but behind supported majors.
6. **Low - safe Python patch/minor updates.** FastAPI, SoundFile, and tqdm have
   approved update candidates, but each environment still needs isolation.

## Architecture boundaries

### Voice API

The Torch/Torchaudio change belongs only to `backend/voice_api`. Its GPU group
and lockfile must explicitly resolve `torch==2.8.0+cu128` and
`torchaudio==2.8.0+cu128` from the CUDA 12.8 index while retaining
`omnivoice==0.2.1`. `backend/lexiquest_lm` remains a separate environment.

The Voice API gains a fail-fast compatibility check. An incompatible or
partially installed GPU runtime must report model unavailability before
inference; it must not silently continue with a mixed CPU/CUDA pair.

### Supabase bootstrap

The Flutter bootstrap reads only
`LEXIQUEST_SUPABASE_PUBLISHABLE_KEY`, with no committed production default.
Missing or invalid configuration produces an explicit, user-readable
unavailable state rather than a crash or an insecure fallback. Dashboard key
rotation and remote verification remain a user-owned release gate.

### Flutter dependencies

Removal candidates are `cupertino_icons`, `firebase_storage`, `provider`,
`image_picker`, `fluttertoast`, `confetti`, `cached_network_image`,
`google_mlkit_image_labeling`, and `camera`. Search evidence must show zero
imports before removal. The resulting lockfile is accepted only after Flutter
analysis, tests, and an Android debug build.

### CI and Android

GitHub Actions stay immutable by full commit SHA. CI contract tests must be
changed before each action major update. Android keeps the current compatibility
flags until Flutter itself and the remaining plugins support strict Built-in
Kotlin; the package cache is never modified.

## Migration order

Each behavior change follows RED-GREEN-REFACTOR and is committed only after its
focused gate passes.

1. Align the Voice API runtime and add compatibility tests.
2. Remove the committed Supabase legacy key and test the unavailable state.
3. Remove unused Flutter dependencies while preserving the explicit simulated
   Object Scanner status.
4. Update Python dependencies one environment at a time with lockfile and test
   isolation.
5. Update GitHub Actions majors one action at a time under SHA-pin contract
   tests.
6. Record the Built-in Kotlin deferral and upstream owners.
7. Run the complete local, security, dependency, and pull-request gate.

## Failure handling and rollback

- A Voice runtime mismatch fails readiness closed. Practice mode may use the
  existing native-TTS policy; research evaluation records a technical failure.
  The Voice API patch can be reverted without touching the training stack.
- Missing Supabase configuration renders an unavailable state. Supplying the
  correct build define restores the integration without a code rollback.
- A dependency removal or version bump that breaks its focused gate is reverted
  before the next environment changes.
- Each GitHub Action is updated independently so a failed runner migration can
  be reverted in isolation.

## Security requirements

- No legacy anon JWT, service-role key, provider key, Firebase token, or model
  weight is committed.
- Voice readiness fails closed on an unsupported package combination.
- Supabase Storage RLS and Firestore rules contracts remain green.
- GitHub Actions remain SHA-pinned.
- The Object Scanner UI and tests must not claim a real ML implementation.
- Secret, dependency, and generated-file audits run against the final commit.

## Verification strategy

Focused tests cover Voice runtime compatibility and Supabase configuration
failure before their implementations. Every dependency environment runs its own
suite and lockfile check. The final gate includes:

- Flutter analysis and the complete Flutter test suite;
- Android debug APK build;
- Voice API, AI API, and LexiQuest-LM CPU test suites;
- a bounded real OmniVoice inference smoke test after the CPU gates;
- CI workflow contract tests;
- Firestore and Supabase security contracts;
- dependency, repository-security, secret, and generated-file audits;
- GitHub pull-request check rollup.

## Exit criteria

The same commit must satisfy all of the following:

1. Voice API resolves the supported Torch/Torchaudio pair, rejects mismatches,
   and passes a bounded real inference smoke test.
2. The training Torch/CUDA stack is unchanged.
3. Supabase has no committed legacy key and a missing publishable key is handled
   safely in UI and tests.
4. All proven-unused direct Flutter dependencies are removed and Flutter plus
   Android gates pass.
5. Approved Python updates have isolated, green lockfiles and suites.
6. Updated GitHub Actions use reviewed immutable SHAs and pass workflow tests.
7. Strict Built-in Kotlin remains deferred with remaining upstream blockers
   documented.
8. Full local verification, security audits, and PR checks are green.

Token use is reported from actual productive GLM work. It is never inflated
through filler, repeated output, or deliberate waste.
