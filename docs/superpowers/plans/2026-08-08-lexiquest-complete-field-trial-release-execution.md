# LexiQuest Complete Field-Trial Release Execution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Converge the approved LexiQuest P0–P10 release program into a tested, reachable, persisted, evidence-backed field-trial release without merging divergent branches wholesale.

**Architecture:** Start from the clean `codex/complete-field-trial-release` main baseline. Import dependency-ordered commit slices from the associative-reading, P8-A, and production-readiness branches; keep Drift/local learning authoritative, make cloud/AI/voice additive, and gate every slice with bounded verification before advancing.

**Tech Stack:** Flutter/Dart, Drift/SQLite, Firebase Auth/Firestore/App Check, Supabase policy checks, Android Gradle/Kotlin, Python `uv` CPU-only backend tests, PowerShell 5.1 verification gates, Node emulator/rules tests, signed Android APKs.

## Global Constraints

- Single Writer: only this task edits files, runs tests, stages/commits, and decides integration.
- Preserve the user's dirty normal checkout; all work happens in the linked integration worktree.
- Do not invoke, install, resume, or recommend Codex Security, Security Scan, Deep Scan, or any Codex Security worker.
- Do not merge `release/v0.1-complete-system`, `feature/associative-reading-loop`, `feature/production-readiness-integration`, or `feature/p8a-voice-architecture` wholesale.
- Use test-first behavior for any new code authored during the run; imported commits must carry and pass their focused tests.
- Do not weaken gates, fabricate evidence, commit secrets, commit participant identifiers, or claim physical/provider/release readiness from local tests alone.
- Do not run full Flutter tests, full backend tests, Android builds, or GPU checks concurrently.
- Stop after the same failure occurs twice without a new hypothesis; stop after ten minutes without measurable progress.
- Keep local learning usable when cloud, backend, model, or voice services are unavailable.

## Task 1: P0 baseline and convergence record

**Files:**
- Create: `docs/superpowers/specs/2026-08-08-lexiquest-complete-field-trial-convergence-design.md`
- Create: `docs/superpowers/plans/2026-08-08-lexiquest-complete-field-trial-release-execution.md`
- Generated/ignored evidence: `build/verification/<sha>/targeted-*.json`

- [x] Preserve the normal checkout's modified and untracked user files.
- [x] Verify the linked worktree is clean and on `codex/complete-field-trial-release` at `7b8ac6c`.
- [x] Record branch topology, touched-file overlap, and read-only merge-tree conflict notices.
- [x] Run the fresh bounded baseline gates:

```powershell
$env:PATH = 'C:\Users\Phet\AppData\Local\Programs\flutter\bin;' + $env:PATH
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-scope.ps1 -Level Targeted -Area Runtime
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-scope.ps1 -Level Targeted -Area Integration
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-scope.ps1 -Level Targeted -Area Learning
```

- [x] Record that baseline commands passed at `7b8ac6c`; the first sandbox run failed only because nested PowerShell could not resolve `flutter`, then passed with the installed Flutter path.
- [ ] Commit the P0 design/plan documents as the first integration checkpoint.

## Task 2: P1 platform/data/local-first slice

**Files:**
- Import selectively from associative branch: `lib/runtime/`, `lib/data/local/`, `lib/features/identity/`, `lib/features/vocabulary/`, `lib/features/session/`, related tests, and required `pubspec`/Android configuration.
- Preserve main-only production shell and `functions/` unless a selected commit has a focused acceptance test.

- [ ] Review the exact diff and tests for `3ca9af9`, `a06769f`, `fd2338c`, `f96c76`, `7c932c3`, `ddfd09a`, `ca9421c`, `b9c05db`, and `14e4df3`.
- [ ] Import one dependency-ordered group at a time with `git cherry-pick`; abort immediately on an unresolved conflict.
- [ ] Run the relevant failing test first when authoring any manual adaptation, then the focused Runtime/database/vocabulary tests.
- [ ] Confirm generated Drift files and schema migrations move together and schema version remains monotonic.
- [ ] Commit the slice with a message identifying the subsystem and record its pre-slice SHA for revert.

## Task 3: P2 sync and learning slice

**Files:**
- Import selectively: `lib/features/sync/`, `lib/features/learning/`, `lib/learning/`, `lib/progress/`, Firestore rules, schema migrations, and focused tests.

- [ ] Review and import sync contracts/leases/checkpoints from `9f279a0`, `c1cb718`, `f4b30f3`, `a7efe19`, `57b9936`, `e4317f6`, `661e352`, `a926b82`, and `a0f7d72`.
- [ ] Review and import learning evidence/SRS/associative reading from `1700dbd`, `cb54614`, `59e8a26`, and `1fd71e9`.
- [ ] Run focused migration, sync contract, sync engine, learning use-case, scheduler, and associative journey tests.
- [ ] Verify local writes persist and cloud failure leaves Quiz, SRS, reading, progress, rewards, and export usable.
- [ ] Commit the slice only after targeted Learning and rule tests pass.

## Task 4: P3 device/model/media slice

**Files:**
- Import selectively: `lib/features/device_model/`, `lib/features/media_practice/`, model manifests/download/benchmark code, Android permissions, and tests.

- [ ] Review `9bd7beb`, `abd67ac`, and their focused tests before import.
- [ ] Verify checksum/pinning, resumable download behavior, camera/speech permission boundaries, and typed failure paths.
- [ ] Run Device Model and media-practice targeted gates; do not convert local tests into physical-device evidence.
- [ ] Commit the slice with an internal checkpoint note and rollback SHA.

## Task 5: P4 voice and AI slice

**Files:**
- Import selected P8-A/P8-B/P8-C/P8-D files under `lib/voice/`, `lib/features/media_practice/`, `backend/voice_api/`, `lib/features/ai_tutor/`, `lib/features/gemini/`, and matching tests.

- [ ] Import voice contracts/routing from `0d4913c`, `f9edeae`, `f7913e4`, `7ee1c1b`, and `60001c7`.
- [ ] Import standard packs and hybrid delivery from `823576b`, `e076238`, `a477bc9`, `110e5cc`, `06da4e3`, `eb7e36f`, then the P8-B gate test.
- [ ] Import mirror consent/ephemeral session code from `b5eedff`, `5432d77`, `fe77247`, `4bae4e4`, `3652758`, `baf9ca4`, `28241b5`, then the P8-C gate test.
- [ ] Import speech provenance/evidence from `cbf9dec`, `0961f9`, `8975b24`, `94f8dfb`, and the P8-D gate test.
- [ ] Import provider-neutral AI Tutor and local usage ledger from `46185b6`, `90ea997`, `c91fbee`, `23d4a53`, `00ff5e7`, `fc6fb32`, and later tested UI fixes from the P8-A branch.
- [ ] Run Flutter Voice/AI gates and CPU-only backend Voice/AI tests sequentially; no owner key or real mirror claim is made here.
- [ ] Commit only after navigation/reachability and local persistence tests pass.

## Task 6: P5 production backend and hardening slice

**Files:**
- Import selected production-readiness files under `backend/`, `tool/cli/`, `docs/runbooks/`, `firebase.json`, `firestore.rules`, `supabase/`, `.github/workflows/`, and provider/runtime boundary code.

- [ ] Import AI-analysis boundary/runtime commits only after launcher health is checked; one file per analysis request and no provider text execution.
- [ ] Import bounded backend envelope and policy commits from `38b2823` through `7a861bf` as individually reviewed subsystem groups.
- [ ] Import release target, cloud policy, Supabase, App Check, and artifact-verification commits from `d36cb52` through `fb8228d` only where their tests target the integrated files.
- [ ] Run BackendAI, BackendVoice, BackendLM, Runtime, Firestore emulator, Supabase policy, dependency, and focused diff checks sequentially.
- [ ] Keep optional GPU/LLM/train groups excluded from CPU baseline gates.
- [ ] Commit the hardening slice with all command outputs recorded.

## Task 7: P6 internal APK checkpoint

**Files:**
- Produce ignored artifacts under `build/field-release/` and evidence under `field/evidence/` only when genuine.
- Verify `android/`, `pubspec.yaml`, release config, signing configuration, and manifest.

- [ ] Freeze the integrated source SHA and verify the worktree status.
- [ ] Run the bounded Android/static gates and package a signed APK using the repository's release script when its prerequisites exist.
- [ ] Record `sourceCommit`, signing certificate digest, APK SHA-256, version, build ID, model manifest, and tool versions in the release manifest.
- [ ] Run APK/runtime verification against that exact manifest; do not reuse prior APK evidence after any byte changes.
- [ ] Commit only non-sensitive release metadata and keep keystores, keys, private refs, and participant data out of Git.

## Task 8: P7/P8 device and field journeys

**External evidence:** owner-provided release identity/API key/private refs, physical low/mid/high devices, App Check console state, real speech/voice results.

- [ ] Collect low-tier, mid-tier, and high-tier device evidence with hashed serials and exact APK hash.
- [ ] Exercise offline start, reconnect, sync recovery, restart, model download/checksum/inference, camera, microphone, SRS, export, AI Tutor, voice mirror consent, and native fallback.
- [ ] Keep `pending` when a real journey or owner approval has not occurred; never turn a placeholder into `pass`.
- [ ] Record only evidence that is tied to the checkpoint APK and approved research/consent scope.

## Task 9: P9 release readiness

- [ ] Confirm App Check valid traffic before enforcement and run the enforced journey after the exact APK is installed.
- [ ] Reconcile Firebase/Supabase policy snapshots, asset links, kill switch, billing/budget controls, support/feedback/research references, consent, export/deletion, and owner approval.
- [ ] Run the release verifier only on the frozen release SHA; report every failed gate with its evidence path.
- [ ] If a gate fails, use systematic debugging and a fresh hypothesis; do not weaken the verifier.

## Task 10: P10 final acceptance and handoff

- [ ] Run final targeted regression for every changed subsystem and the release gate once on the frozen SHA.
- [ ] Verify source/diff, tests, APK/hash, device evidence, provider evidence, and field evidence are mutually consistent.
- [ ] Provide a final status table that separates passed local gates, passed external gates, pending owner/device inputs, and proven blockers.
- [ ] Use `verification-before-completion` before any completion claim and use `finishing-a-development-branch` only after all required work is genuinely complete.
