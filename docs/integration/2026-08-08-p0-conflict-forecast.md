# P0.2 Conflict Forecast — Branch Convergence

**Date:** 2026-08-08
**Baseline:** `main` @ `7b8ac6c`
**Common ancestor (all branches):** `eb684f0`

## 1. Branch Inventory

| Branch | Commits ahead of main | Files changed | Schema | minSdk | Firebase appId |
|---|---|---|---|---|---|
| `main` | 0 (baseline) | — | n/a | flutter default | `2c4922` (old) |
| `release/v0.1-complete-system` | 52 | 135 | n/a (no app_database) | 29 | `2c4922` (old) |
| `feature/associative-reading-loop` | 84 | 532 | **v10** | **26** ✓ | `719eb3` (Production) ✓ |
| `feature/p8a-voice-architecture` | 149 | 633 | v8 | 24 | `2c4922` (old) |
| `feature/production-readiness-integration` | 170 | 701 | v9 | 24 | `2c4922` (old) |

**Key finding:** No branch is an ancestor of another. All diverge directly from `eb684f0`.

## 2. File Overlap Matrix

| Pair | Overlapping files |
|---|---|
| associative ∩ release/v0.1 | 67 |
| associative ∩ production-readiness | 419 |
| associative ∩ p8a-voice | 451 |
| release/v0.1 ∩ production-readiness | 66 |
| release/v0.1 ∩ p8a-voice | 67 |
| production-readiness ∩ p8a-voice | 589 |
| **All 4 branches** | **65** |

`production-readiness` and `p8a-voice` are highly overlapping (589 files) — they share a common lineage near the voice architecture work.

## 3. Conflict Groups

### Group A — Android / Firebase / Auth
**Affected files (in all 4 branches):**
- `android/app/build.gradle.kts` — minSdk conflict: associative=**26** ✓, release=29, p8a/prodrdy=24
- `android/app/google-services.json` — appId: associative=**Production** ✓, others=old dev
- `lib/services/auth_service.dart`
- `lib/screens/login_screen.dart`, `register_screen.dart`, `otp_screen.dart`
- `android/app/src/main/AndroidManifest.xml`, `MainActivity.kt`

**Source of truth:** `feature/associative-reading-loop` (field-verified minSdk 26 + Production appId + Play Integrity)

### Group B — Schema / Migration
- `lib/data/local/app_database.dart` — **schemaVersion conflict:**
  - associative = **v10** (has migration tests v6→v7, v7→v8, v8→v9, v9→v10)
  - production-readiness = v9
  - p8a-voice = v8
- `lib/data/local/tables/*` — associative has `associative_tables.dart`, `event_tables.dart`, `motivation_tables.dart`, `quest_tables.dart` (unique)
- production-readiness adds `associative_reading_tables.dart`, `speech_evidence_tables.dart`, `ai_usage_tables.dart`

**Source of truth:** `feature/associative-reading-loop` (highest schema, complete migration path). Voice/AI tables from p8a/prodrdy merged as v11 migration.

### Group C — Composition Root
- `lib/runtime/app_bootstrap.dart`
- `lib/runtime/app_dependencies.dart`
  - associative: `AppDependencies` with `quest`, `streak`, `associativeLearning`, `objectScanner`, `voice` (voice as `VoiceUseCases?`)
  - p8a/prodrdy: `AppDependencies` with `voice` as `VoiceProvider` (required), `objectScanner`, `associativeReading`, `associativeMemory`
- `lib/runtime/app_runtime_status.dart`

**Source of truth:** associative for Quest/Streak/Associative/Event wiring; p8a-voice architecture for Voice. Merge requires unifying `VoiceUseCases` + `VoiceProvider`.

### Group D — Navigation / UI
- `lib/screens/main_navigation_screen.dart`
- `lib/screens/setting_screen.dart`, `profile_settings_screen.dart`
- Feature-specific screens

**Source of truth:** associative (has V2 navigation tied to feature_registry).

### Group E — Backend / Voice
- `lib/voice/*` — p8a/prodrdy have 35+ voice files (unique); associative has only `voice/application/voice_use_cases.dart`
- `lib/features/ai_tutor/*` — p8a/prodrdy have full AI tutor stack
- `backend/*` — prod-readiness has backend hardening

**Source of truth:** p8a-voice for voice architecture; production-readiness for backend hardening + AI tutor.

### Group F — Tests / Verification
- `test/runtime/*`, `test/screens/*`, `test/services/*` — overlapping test files
- `tool/cli/verify.ps1` — modified in all 4 branches

**Source of truth:** associative (has latest field-verified test suite).

### Group G — Research / Analytics
- `firestore.rules` — modified in all branches; associative has srs_states + achievement_unlocks rules
- `supabase/migrations/*`

**Source of truth:** associative (field-verified rules with SRS + achievement sync).

### Group H — Feature Registry
- associative has BOTH `lib/runtime/field_feature_registry.dart` AND new `lib/runtime/registries/feature_registry.dart` (plus consent, entitlement, experiment registries)
- p8a/prodrdy only have `field_feature_registry.dart`

**Source of truth:** associative (most complete V2 registry architecture).

## 4. Merge Order Rationale

Per P0.4 the slices merge in this order:

1. **Device/Auth foundation** ← from associative (minSdk 26, Production appId, Play Integrity)
2. **Schema & migrations** ← from associative (v10 baseline, then add v11 for voice/AI tables)
3. **V2 core architecture** ← from associative (registries, event envelopes, composition root skeleton)
4. **Quest/Streak/Associative Reading** ← from associative (unique vertical slices)
5. **Field fixes** ← from associative (already integrated in current branch HEAD)
6. **Backend/Voice contracts** ← from p8a-voice (voice/) + prod-readiness (backend, ai_tutor)
7. **Production hardening** ← from prod-readiness (release hardening, cost control)

Each slice lands on an integration branch derived from `feature/associative-reading-loop`, not main, because associative already carries schema v10 and field fixes that main lacks.

## 5. Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Schema v8/v9 → v10 conflicts in app_database.dart | High | associative v10 is authoritative; p8a/prodrdy tables become v11 migration |
| VoiceProvider (required) vs VoiceUseCases (nullable) composition root conflict | High | Unify in slice 6 — wrap VoiceProvider in VoiceUseCases adapter |
| Firebase appId mismatch | Medium | Already resolved in associative |
| Test files for removed/renamed services | Medium | Re-run targeted tests per slice |
| pubspec.lock / dependency divergence | Medium | Resolve by taking highest-compatible versions |
