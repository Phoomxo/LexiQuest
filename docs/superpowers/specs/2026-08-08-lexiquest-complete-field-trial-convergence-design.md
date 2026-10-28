# LexiQuest Complete Field-Trial Convergence Design

**Date:** 2026-08-08  
**Scope:** Approved LexiQuest Complete Field-Trial Release, P0–P10

## Decision

The integration target is the clean linked worktree at
`C:/Users/Phet/Documents/LexiQuest/.worktrees/complete-field-trial-release`,
branch `codex/complete-field-trial-release`, starting at `7b8ac6c`. The normal
checkout at `C:/Users/Phet/Documents/LexiQuest` remains untouched because it
contains user-owned changes:

- Modified: `docs/field/2026-08-05-v12-verification-attempt.md`
- Untracked: `docs/field/2026-08-06-v12-gms-recovery-auth-verified.md`
- Untracked: `lexiquest_auth.png`

Codex is the only writer. Specialist analysis, when used, is read-only. No
divergent branch is merged wholesale; each selected commit group is reviewed,
cherry-picked as an incremental slice, tested, and given a rollback point.

## Design constraints

- Drift/local state remains authoritative for field learning and progress.
- Cloud services are additive and must not make offline learning unusable.
- Release evidence is valid only when tied to the exact APK hash and source
  commit that produced it.
- Real device, owner, private-channel, App Check, and API-key evidence cannot
  be fabricated or inferred from unit/widget tests.
- Monthly shared infrastructure cost remains zero-first with a working target
  of 0–100 THB/month; no Supabase Pro, Hugging Face PRO, GPU VPS, or baseline
  Cloud Run.
- Codex Security, Deep Scan, Security Scan, and their workers are forbidden.

## Branch conflict forecast

The forecast was calculated against `main` and confirmed with a read-only
three-way merge-tree inspection from common base `eb684f0f`.

| Branch | Changed files vs main | Merge-tree conflict notices | Role in convergence |
|---|---:|---:|---|
| `release/v0.1-complete-system` | 135 | 23 | Reference-only source for stable release/device contracts; no wholesale adoption |
| `feature/associative-reading-loop` | 443 | 41 | Local-first, Drift, sync, learning, field controls, and field evidence |
| `feature/production-readiness-integration` | 672 | 45 | Backend, cloud policy, release verification, and production hardening |
| `feature/p8a-voice-architecture` | 544 | 41 | Voice/AI provider-neutral runtime and signed RC evidence |

The largest touched-file overlaps are production-readiness versus P8-A (528
files), associative-reading versus P8-A (359 files), and
production-readiness versus associative-reading (358 files). The highest-risk
files are `lib/runtime/app_bootstrap.dart`, `lib/runtime/app_dependencies.dart`,
`lib/screens/main_navigation_screen.dart`, `firebase.json`, `firestore.rules`,
`pubspec.yaml`, `pubspec.lock`, `android/app/google-services.json`, and the
generated Drift database files.

## Source-of-truth ledger

| Subsystem | Authority | Selected source | Integration rule |
|---|---|---|---|
| Baseline build/toolchain and existing production shell | `main` at `7b8ac6c` | `codex/complete-field-trial-release` | Preserve unless a later slice has a test-backed replacement |
| Local-first runtime and feature flags | associative branch | `3ca9af9`, `d707dbf`, and their tests | Keep the field registry conservative; no feature is active only because a screen exists |
| Drift schema, identity, vocabulary, outbox | associative branch | `a06769f` through `14e4df3` selected by dependency | `app_database.dart` and generated output move together; migrations are mandatory |
| Sync contracts, leases, gateway, triggers | associative branch | `9f279a0` through `a0f7d72` selected by dependency | Sync is idempotent, bounded, mutex-protected, and non-blocking to local use |
| Learning evidence, SRS, associative reading | associative branch | `1700dbd` through `1fd71e9`, then V2 slices after gate review | Learning writes go through the learning authority; projections are rebuildable |
| Device model, camera, speech, Gemini BYOK | associative branch | `9bd7beb` through `a9dede8` and tests | Hardware/credential prerequisites stay explicit and fail typed, not silently |
| P8 voice contracts and routing | P8-A branch | `0d4913c` through `7eaa7b2`, then P8-B/C/D groups | Voice routes through the policy/orchestrator boundary and retains native fallback |
| Voice backend and ephemeral mirror | P8-A / production-readiness branches | P8-B/C commits and bounded backend tests | No raw audio, voiceprints, or private refs in source or committed evidence |
| AI Tutor providers and local usage ledger | P8-A branch after `de8fb31` | `60ba597` through `91f52aa` selected with tests | Provider/model selection is explicit; usage and failures are persisted locally |
| AI-analysis helper | production-readiness branch | `4de33c4` through `de8fb31` plus later boundary fixes | Launcher health first; one file per request; provider output is untrusted review data |
| Backend AI/LM and production gates | production-readiness branch | `38b2823` through `fb8228d` selected by subsystem | Keep CPU-safe bounded checks; optional GPU/LLM/train groups remain excluded |
| Firebase/Supabase rules and release policy | baseline plus production-readiness hardening | Exact tested rule/policy commits only | Rules are tested in emulators/snapshots; no credentials or billing changes here |
| Field evidence and final release | associative + production release tooling | Field gate scripts and genuine owner/device records | Evidence must match APK SHA-256, source commit, device tier, and journey result |

`release/v0.1-complete-system` is intentionally not the authority for any
subsystem above. Its device/prototype contracts are consulted only when a
selected slice needs a reference comparison.

## Incremental integration slices and gates

1. **P0 Baseline/Convergence:** preserve the dirty user checkout, prove the
   clean target, record branch topology, conflict forecast, and ledger. Gate:
   bounded Runtime, Integration, and Learning verification at `7b8ac6c`.
2. **P1 Platform/Data:** integrate local-first runtime, Drift schema, identity,
   vocabulary, database lifecycle, and migration tests. Gate: Runtime plus
   local database and vocabulary tests.
3. **P2 Sync/Learning:** integrate outbox leases, pull checkpoints, gateway,
   background triggers, learning evidence, SRS, and associative reading. Gate:
   Learning plus targeted sync tests and a migration test.
4. **P3 Device/Media:** integrate model lifecycle, camera preprocessing,
   speech contracts, and typed capability failures. Gate: device-model and
   media-practice tests; no physical-device claim yet.
5. **P4 AI/Voice:** integrate provider-neutral voice routing, hybrid standard
   packs, mirror consent, speech evidence, AI Tutor providers, and local usage
   ledger. Gate: Flutter Voice/AI and CPU-only backend tests.
6. **P5 Production Backend:** integrate bounded AI/voice/LM backend envelopes,
   release target parsing, cloud policy, and production verification controls.
   Gate: BackendAI, BackendVoice, BackendLM, Runtime, and rule/policy tests.
7. **P6 Internal APK checkpoint:** package a reproducible APK from the frozen
   integrated commit, record signing certificate and APK SHA-256, and run
   static/runtime gates tied to that manifest.
8. **P7 Device checkpoint:** collect low/mid/high tier evidence, offline/online
   recovery, model benchmark, permissions, and restart behavior. Pending owner
   or physical-device evidence stays pending.
9. **P8 Beta/field journeys:** exercise reachable navigation, persistence,
   SRS, speech, object scanner, AI Tutor, voice mirror consent, export, and
   support/consent flows against the checkpoint APK.
10. **P9 Release readiness:** reconcile App Check, Firebase/Supabase policy,
    billing guardrails, asset links, kill switch, feedback/support/research
    references, owner approval, and final regression.
11. **P10 Final acceptance:** run the release verifier only against the frozen
    release SHA, reconcile every gate and evidence hash, and hand off the
    exact branch/commit/APK artifacts. Any missing external evidence is a
    blocker, not a completion claim.

## Rollback and stop rules

Each slice records its pre-slice commit in the plan and creates a dedicated
commit after its targeted gate passes. If a cherry-pick conflicts, the
operation is aborted before any partial integration is retained. If an
integrated slice fails, the preferred rollback is a new revert commit for that
slice; a destructive reset is not used. Two identical failures stop the
current hypothesis and trigger root-cause analysis. Ten minutes without
measurable progress stops the run and reports the blocker.

## Acceptance definition

An item is complete only when its code is integrated into the target branch,
reachable from the production shell, persisted through the declared authority,
covered by an appropriate test, and—when it is a field/release claim—backed by
fresh APK/device/provider evidence. A file, route, widget, or unit test alone is
not acceptance evidence.
