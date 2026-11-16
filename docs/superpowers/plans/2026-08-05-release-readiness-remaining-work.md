# Release-Readiness Remaining Work Plan

> **For agentic workers:** This plan tracks the work that remains *after* the
> 2026-08-05 systematic fix batch (Track A retry reduction + App Check testable
> seam, Track B `release-blockers-resolution.md` runbook, Track C verification).
> Steps use checkbox (`- [ ]`) syntax for tracking. Each step names the single
> owner who must drive it: **OWNER**, **ENGINEER**, or **BOTH**.

**Goal:** Close every remaining issue on the LexiQuest release-readiness list so
that a single `verify-field-release.ps1` run can pass against a new signed APK,
the 30-person field trial can begin, and the P9 backend proxy work can start
from a clean release baseline.

**Architecture:** No new architecture is introduced by this plan. It executes
the existing tooling (`tool/cli/*`, `tool/cli/*.cjs`), wires already-built
screens (SRS Flashcards, Speak-to-Text, AI Tutor) through their final hardware
and credential prerequisites, and records evidence against the existing field
schema (`docs/field/release-evidence-template.json`). The P9 backend proxy is
the only net-new code and is scoped to its own deferred phase per
[`2026-08-04-p9-backend-proxy-design.md`](../specs/2026-08-04-p9-backend-proxy-design.md).

**Tech Stack:** Flutter 3.44.7 / Dart 3.12.2, Firebase (Auth, Firestore, App
Check), Supabase Storage, Gemini BYOK, LiteRT on-device model, PowerShell 5.1
CLI gates, Node `firebase-tools` config scripts.

## Global Constraints

- Drift remains the runtime source of truth; cloud is additive and never gates
  local learning. Any cloud outage path must keep Quiz, SRS, reading, progress,
  rewards, and export usable.
- Do not enable Firebase paid products for the 30-person trial without an
  explicit owner acceptance record (see `docs/runbooks/firebase-field-operations.md`).
- No participant identifiers, voiceprints, raw audio, or private channel refs
  are committed. Private refs flow only through
  `tool/cli/new-field-release-evidence.ps1` parameters.
- `verify-field-release.ps1` must remain failing until every required item is
  genuine; do not weaken a gate to force a pass.
- Any journey affected by a new APK must be rerun and tied to the new APK
  SHA-256 before re-certifying.
- Stop on retry loops, repeated filesystem errors, or ten minutes without
  measurable progress (per `AGENTS.md`).
- Do not invoke Codex Security tooling; use bounded local verification only
  (per `AGENTS.md`).
- Preserve the historical P0–P7 evidence and the exact prior APK hashes as
  immutable records; this plan produces a new APK hash only after its gate
  passes.

## Workstream Map

The remaining work is organized into five workstreams. W1–W2 are on the
critical path (both blockers); W3–W4 are gated behind W1–W2; W5 is the only
deferred engineering work.

### Status as of 2026-08-05 (W1 execution)

W1 was executed and uncovered the **true root cause** of Blocker 1. The SHA
certificate was *already registered* with Firebase on both Android apps — the
real defect was an **appId mismatch**:

- The codebase (`lib/firebase_options.dart`) hardcoded the Android appId
  `1:145034183638:android:719eb38067864496be5a77`, which belongs to the
  placeholder Firebase app `vocab_learning_app` (package
  `com.example.vocab_learning_app`).
- The real app is **LexiQuest Production**, appId
  `1:145034183638:android:2c492244dd68e77dbe5a77`, package `com.lexiquest.app`.
- The release SHA-256 (`E1B0...`) is registered against **both** apps, so the
  SHA itself was never the blocker — every release build was authenticating
  against the wrong Firebase app whose package does not match
  `applicationId = "com.lexiquest.app"`, which is why Play Integrity and
  Anonymous Auth failed.

**Fix applied (this session):** `lib/firebase_options.dart` Android appId
corrected to `2c492244dd68e77dbe5a77`; `android/app/google-services.json`
refreshed for the LexiQuest Production app. SHA registration (`created: false`)
confirmed against the correct app. iOS/macOS/web configs left untouched per
owner decision (app is Android-only; no iOS/Web apps exist in Firebase).

**W2 status:** App Check Firestore enforcement is `UNENFORCED` (correct
pre-release state per the runbook; enforce only after the new APK observes
valid traffic).

**What remains for W1:** rebuild a release APK with the corrected appId and
confirm Anonymous Auth + Firestore succeed on a physical device (W1.6). This
requires the owner to run `package-field-release.ps1` and a device smoke test.

### W4 journey results (2026-08-05, vivo V2041 mid-tier, APK 1.0.0+10)

Executed after the W1 + Firestore-rules fixes. Anonymous Auth succeeded
(uid `uxdB3O...`); no Firestore PERMISSION_DENIED. See
`build/field-release/w4-journey/JOURNEY_EVIDENCE.md` (gitignored, local).

- **W4.1 SRS Flashcards:** screen opens, empty state correct. Flip / mark
  known-unknown **not testable in a single session** — the FSRS scheduler
  (`srs_policy.dart`) sets `dueAtUtc = now + interval` so every freshly-answered
  word is due in the future. Re-test after ≥ 1 day or with a lapse-inducing
  quiz.
- **W4.2 Shadowing/Speech:** ✅ mic permission granted, speech engine listens,
  correctly reports "didn't hear clear speech" with no real audio. (The drawer
  item opens `ShadowingChallengeScreen`; `SpeakToTextScreen` is unreachable in
  production by design.)
- **W4.5 Object Scanner:** ✅ camera permission granted; model downloaded +
  checksum verified (~15 s); end-to-end inference worked — detected
  `matchstick` at 15.6% confidence with model `mobilenet-v1-imagenet
  1.0.224-quantized-metadata1`; "no verified translation" path rendered
  correctly.
- **W4.3 (AI Tutor):** still requires an owner Gemini API key — not exercised.

| WS | Name | Owner | Critical path? | Depends on |
|----|------|-------|----------------|------------|
| W1 | Release certificate + SHA registration | OWNER | Yes (Blocker 1) | — |
| W2 | App Check enforcement rollout | OWNER | Yes (Blocker 2) | W1 |
| W3 | Hardware verification across device tiers | OWNER + ENGINEER | Yes (after W1–W2) | W1, W2 |
| W4 | Feature journeys on real hardware | OWNER + ENGINEER | Yes (after W1–W2) | W1, W2, W3 |
| W5 | P9 backend proxy implementation | ENGINEER | No (deferred) | W1–W2 stable |

---

## W1 — Release certificate + SHA registration (Blocker 1)

**Owner:** OWNER (with ENGINEER available to run tooling)
**Reference:** [`docs/runbooks/release-blockers-resolution.md`](../../runbooks/release-blockers-resolution.md) Section 1
**Why now:** `android/app/google-services.json` currently has no `sha*_cert_hashes`,
so Play Integrity rejects every release-build token and cascades
`PERMISSION_DENIED` into Anonymous Auth, Firestore, and App Check.

### Files

- Verify/replace: `android/key.properties` (gitignored, must exist)
- Produce: `build/field-release/lexiquest-1.0.0+1.apk`
- Produce: `build/field-release/release-manifest.json`
- Replace: `android/app/google-services.json` (after Firebase re-download)
- Produce: `field/evidence/cloud/firebase-release-sha.json`

### Steps

- [ ] **W1.1 (OWNER/ENGINEER): Confirm or generate the release signing identity**

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tool/cli/initialize-release-signing.ps1
  ```

  Refuses to overwrite an existing identity. If `android/key.properties`
  already exists and points at a real keystore, skip generation and verify
  `key.properties` is loadable.

- [ ] **W1.2 (ENGINEER): Package the signed release APK**

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tool/cli/package-field-release.ps1 -Version 1.0.0+1
  ```

  Requires clean Android-relevant sources. Produces `release-manifest.json`
  with `signingCertificateSha256`, `apkSha256`, `buildId`, `sourceCommit`.
  Rejects debug/fake keys.

- [ ] **W1.3 (OWNER): Authenticate `firebase-tools` against the project**

  ```bash
  firebase login
  firebase use vocab-learning-app-219ef
  ```

  One-time owner credential step. The `*.cjs` config scripts require a global
  default account.

- [ ] **W1.4 (OWNER/ENGINEER): Register the release SHA-256 with Firebase**

  ```bash
  node tool/cli/configure-firebase-release-sha.cjs
  ```

  Reads `signingCertificateSha256` from `release-manifest.json` and registers
  it if absent. Writes `field/evidence/cloud/firebase-release-sha.json`.

  Manual fallback (if the script cannot run): paste the owner-supplied SHA-1
  `7A:B8:6E:48:96:1A:9F:B5:67:49:13:9D:4F:FE:97:8F:D3:B4:36:5B` into
  Firebase Console → Project Settings → Your apps → Android → Add fingerprint.
  Both SHA-1 and SHA-256 derive from the same keystore certificate.

- [ ] **W1.5 (OWNER): Re-download and replace `google-services.json`**

  Firebase Console → Project Settings → Your apps → Android → Download
  `google-services.json` → replace `android/app/google-services.json`. The new
  file must contain a `sha1_cert_hashes` and/or `sha256_cert_hashes` entry.

- [ ] **W1.6 (ENGINEER): Rebuild and verify the blocker cleared**

  Rebuild a release APK *without* `LEXIQUEST_APP_CHECK_DEBUG=true`, install on
  a physical device, and confirm Anonymous Auth + a Firestore read succeed
  (no `PERMISSION_DENIED`). This is the W1 exit criterion.

### W1 Exit Criteria

- `field/evidence/cloud/firebase-release-sha.json` exists with `created: true`
  or a matching pre-existing entry.
- `android/app/google-services.json` contains a `sha*_cert_hashes` entry.
- A release build (no debug App Check override) authenticates anonymously and
  reads Firestore on a physical device.

---

## W2 — App Check enforcement rollout (Blocker 2)

**Owner:** OWNER
**Reference:** [`docs/runbooks/release-blockers-resolution.md`](../../runbooks/release-blockers-resolution.md) Section 2; [`docs/runbooks/firebase-field-operations.md`](../../runbooks/firebase-field-operations.md) § App Check rollout
**Depends on:** W1 (SHA must be registered before valid traffic is possible)

### Files

- Produce: `field/evidence/cloud/firebase-app-check-enforcement-*.json` (one per mode change)

### Steps

- [ ] **W2.1 (OWNER/ENGINEER): Confirm current enforcement state**

  ```bash
  node tool/cli/set-firebase-app-check-enforcement.cjs status
  ```

  Expected: `UNENFORCED` (rolled back per the P8 gate App Check status note).

- [ ] **W2.2 (ENGINEER): Build with the debug provider only if W1 is incomplete**

  ```bash
  flutter build apk --release \
    --dart-define=LEXIQUEST_APP_CHECK_DEBUG=true \
    --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true \
    --dart-define=LEXIQUEST_VERSION=1.0.0+1 \
    --dart-define=LEXIQUEST_BUILD_ID="$(git rev-parse --short HEAD)"
  ```

  Skip this step entirely once W1 is complete — a release build with no
  debug override is the target.

- [ ] **W2.3 (OWNER): Observe valid/invalid traffic with enforcement OFF**

  With `UNENFORCED`, run the release-signed APK (post-W1) and confirm the
  Firebase Console App Check logs show **valid** traffic. Do not proceed to
  W2.4 until valid traffic is observed.

- [ ] **W2.4 (OWNER): Enforce Firestore**

  ```bash
  node tool/cli/set-firebase-app-check-enforcement.cjs enable
  ```

  Per `firebase-field-operations.md` step 5: only enforce after the
  release-signed APK completes the full offline/online journey. Auth is
  protected by its own provider controls, not App Check.

- [ ] **W2.5 (OWNER): Second bounded acceptance pass**

  Re-run the mandatory journeys under `ENFORCED`. If rejection or cost
  anomalies occur, roll back:

  ```bash
  node tool/cli/set-firebase-app-check-enforcement.cjs disable
  ```

  and, if cloud access must stop completely, distribute a build with
  `--dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=false`.

### W2 Exit Criteria

- Firebase Console shows valid App Check traffic from the release build.
- Firestore enforcement is `ENFORCED` and the mandatory journeys still pass.
- At least one `firebase-app-check-enforcement-enable-*.json` evidence file
  exists under `field/evidence/cloud/`.

---

## W3 — Hardware verification across device tiers

**Owner:** OWNER (device procurement) + ENGINEER (evidence collection)
**Reference:** [`docs/development/p8-field-certification-gate-2026-07-30.md`](../development/p8-field-certification-gate-2026-07-30.md) § External requirements remain
**Depends on:** W1, W2 (a stable signed APK with working cloud is required)

### Status as of 2026-08-05

| Tier | Device | Android | RAM | XNNPACK | GPU | Status |
|------|--------|---------|-----|---------|-----|--------|
| Mid | vivo V2041 | 13 | ~7.5 GB | — (P8 certified) | Not allowlisted | ✅ Certified (P8) |
| High | HONOR DNP-NX9 | **16** (SDK 36) | **11 GB** | **18 ms** (12.8× CPU) | Adreno 750, not allowlisted | ✅ Evidence collected |
| Low | — | 11–12 | ≤ 4 GB | — | — | ⏳ Device needed |

High-tier evidence: `field/evidence/devices/high-20260805T040232Z.json`
(gitignored; pseudonymous device id `6D16563A...`; APK sha256 `A90BB0...`)
All journeys remain pending owner run.

### Files

- Produce: `field/evidence/devices/<device-id>.json` per device (via `collect-android-field-evidence.ps1`)

### Steps

- [ ] **W3.1 (OWNER): Procure the low-tier device**

  Target: ≤ 4 GB RAM, Android 11–12. This tier is currently unverified.

- [x] **W3.2 (ENGINEER): Install + collect evidence on high-tier device**

  HONOR DNP-NX9 (Android 16, SDK 36, 11 GB RAM, Snapdragon SM8650 / Adreno 750).
  APK 1.0.0+10 installed. `verify-device-model.ps1` PASS (11/11).
  XNNPACK median 18 ms vs CPU 232 ms (12.8× speedup). GPU not allowlisted
  (same policy as mid-tier — requires certification pass).

- [ ] **W3.3 (OWNER): Procure/confirm a GPU-allowlist-qualifying device**

  Needed to exercise the GPU inference path that is currently disabled
  (not allowlisted) on both the mid-tier vivo V2041 and high-tier HONOR.

- [ ] **W3.4 (ENGINEER): Collect evidence on low-tier device (when procured)**

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tool/cli/collect-android-field-evidence.ps1 -Tier low -NetworkProfile wifi
  ```

  One physical device per run; no emulators. Hashed serial only; no
  participant identifiers committed.

- [ ] **W3.5 (ENGINEER): Run the model runtime + GPU allowlist probes on low-tier**

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tool/cli/verify-apk-model-runtime.ps1
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tool/cli/verify-device-model.ps1
  ```

### W3 Exit Criteria

- Evidence exists for one low-tier, one mid-tier (existing vivo V2041), and
  one high-tier device.
- GPU allowlist decision is recorded per device (preferred / disabled with
  reason).
- `verify-field-release.ps1` device-tier reconciliation passes.

---

## W4 — Feature journeys on real hardware

**Owner:** OWNER (credentials + smoke test) + ENGINEER (test scaffolding)
**Reference:** P8 gate § Evidence still required; the original issue list (SRS Flashcards, Speak-to-Text, AI Tutor)
**Depends on:** W1, W2, W3

### Files

- Produce: journey evidence referenced from `field/evidence/devices/<device-id>.json`
- Verify: `lib/features/learning/*` (SRS), `lib/features/media_practice/*` (speech), `lib/features/gemini/*` (AI Tutor)

### Steps

- [ ] **W4.1 (ENGINEER): SRS Flashcards — flip card + mark known/unknown**

  Open the SRS screen on each device tier, exercise flip and both mark
  actions, and confirm the schedule + Drift persistence update. No code
  change expected; this is a journey verification.

- [ ] **W4.2 (ENGINEER): Speak-to-Text — real microphone on release APK**

  Grant microphone permission on a physical device, run a pronunciation /
  speech capture, and confirm transcription returns. Verify the release APK
  does not silently fail the permission flow.

- [ ] **W4.3 (OWNER): Provide the owner Gemini API key**

  Create a Gemini API key and load it via the AI Tutor settings screen. See
  [`docs/development/p6-gemini-byok-gate-2026-07-30.md`](../development/p6-gemini-byok-gate-2026-07-30.md).
  Missing keys already surface as a typed `GeminiException` and never crash.

- [ ] **W4.4 (OWNER + ENGINEER): AI Tutor end-to-end**

  With the key loaded, send a real prompt and confirm a streamed response.
  Exercise `verify-gemini-byok.ps1`:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File tool/cli/verify-gemini-byok.ps1
  ```

- [ ] **W4.5 (ENGINEER): Object Scanner model download + checksum + inference**

  Exercise the on-device model download path, verify the checksum matches
  the pinned `modelSha256` in `release-manifest.json`, and run a real
  inference. Use `verify-apk-model-runtime.ps1`.

- [ ] **W4.6 (ENGINEER): Voice mirror session-consent flow**

  Exercise enrollment + mirror audio on a physical device once the hybrid
  voice path is live. This was flagged as untested in the original issue
  list.

- [ ] **W4.7 (OWNER): Supply the private channel refs**

  Provide `feedbackChannelRef`, `supportChannelRef`, `researchProtocolRef`
  to `new-field-release-evidence.ps1` (see `docs/field/README.md`). These are
  never committed; they populate the private evidence bundle only.

- [ ] **W4.8 (OWNER): Owner smoke test + approval**

  Install the final signed APK on a physical device, run the mandatory
  journeys, and record approval against the exact `apkSha256` from
  `release-manifest.json`. `verify-field-release.ps1` refuses to pass until
  `ownerApproval.approved` is true and the hash matches.

### W4 Exit Criteria

- All eight P8 "Evidence still required" journeys are recorded against the
  final APK hash.
- AI Tutor returns a real streamed response with a valid owner key.
- `ownerApproval.approved == true` with a matching `apkSha256`.

---

## W5 — P9 backend proxy implementation (deferred)

**Owner:** ENGINEER
**Reference:** [`docs/superpowers/specs/2026-08-04-p9-backend-proxy-design.md`](../specs/2026-08-04-p9-backend-proxy-design.md)
**Depends on:** W1 + W2 stable (so the proxy can be validated against a known-good release baseline). May also benefit from W4.3 (owner key) for end-to-end validation.

> **Sequencing note:** W5 is intentionally deferred until after the
> release-readiness gate passes. Starting it earlier risks conflating proxy
> defects with release-blocker regressions. It should be planned as its own
> full plan doc once the design spec is reviewed and approved.

### Steps (high-level — to be expanded into a dedicated plan)

- [ ] **W5.1 (ENGINEER): Review and ratify the P9 design spec**

  Confirm scope, threat model, cost boundary, and the BYOK-vs-proxy
  data-flow decision against the stable release baseline.

- [ ] **W5.2 (ENGINEER): Split the P9 spec into a task-by-task plan doc**

  Follow the convention in
  [`docs/superpowers/plans/2026-07-31-p8a-voice-architecture-implementation.md`](./2026-07-31-p8a-voice-architecture-implementation.md):
  Goal, Architecture, Tech Stack, Global Constraints, File Structure,
  checkbox Tasks, Completion Check.

- [ ] **W5.3 (ENGINEER): Implement, test, and gate P9**

  Execute the dedicated P9 plan. The P9 gate must not weaken any W1–W4
  release-readiness gate.

---

## Already completed (2026-08-05 systematic fix batch)

These items are done and are listed here only so the remaining-work plan stays
reconciled with the issue list it was derived from.

- [x] **A1** Reduced `OwnerBindingGuestSessionService` cloud-binding retry
  default 8 → 5 (× 15 s = 75 s). `lib/services/guest_session_service.dart`.
- [x] **A2** Extracted App Check provider selection into a testable seam
  `resolveAndroidAppCheckProvider()`. `lib/runtime/app_bootstrap.dart`.
- [x] **A3** Added three unit tests for the provider seam.
  `test/runtime/app_bootstrap_test.dart`.
- [x] **A4** Added a regression test pinning the new retry default (5) and its
  four 15 s backoffs. `test/services/guest_session_service_test.dart`.
- [x] **B1** Created [`docs/runbooks/release-blockers-resolution.md`](../../runbooks/release-blockers-resolution.md).
- [x] **B2** Updated the P8 gate App Check status note + cross-reference.
- [x] **C1** Verified: `flutter analyze` clean, 1015/1015 tests pass, the four
  changed files pass `dart format`. (`verify.ps1` step 04 fails only on
  pre-existing formatting debt from commit `fbf2d91`, unrelated to this work.)

---

## Release-Readiness Completion Check

The single command that must pass before the 30-person trial begins:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/cli/verify-field-release.ps1
```

This remains failing by design until **every** required item above is genuine.
Do not weaken any gate to force a pass. When it passes, record the final APK
SHA-256, the owner approval evidence, and the device-tier evidence, then open
the P9 (W5) plan.
