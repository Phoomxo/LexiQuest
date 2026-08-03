# Phase 0: V2 Foundation Integration

**Status:** APPROVED — Phase -1 GO decision 2026-08-04  
**Duration:** 6 weeks (Week 10–16)  
**Branch strategy:** `feature/phase-0-*` branches off `main`  
**Dependencies:** Phase -1 complete ✅  

---

## Objective

Integrate V2 contracts into production, expand sync coverage, reconcile the two
learning layers, and prepare the codebase for Phase 1 feature development.

**Success Criteria:**
- Quest V2 persists and round-trips through schema v8
- SrsStates + AchievementUnlocks sync via Firestore
- `lib/learning/` fully proxied through `lib/features/learning/`
- SharedPreferences usage in feature code eliminated
- 931+ tests passing, fitness tests 15/15

---

## Week 10-11: Quest Domain Persistence

### Goal
Persist `QuestInstance` and `QuestDefinition` to local DB (schema v8); retire
the legacy `streak_and_daily_quest_service` behind the quarantine boundary.

### Tasks

**Schema v8 — Quest Tables**
- [ ] Add `quest_definitions` table (Drift) — mirrors `QuestDefinition` value object
- [ ] Add `quest_instances` table (Drift) — state machine rows keyed by `(owner_id, instance_id)`
- [ ] Add `quest_objective_progress` table (Drift) — per-objective counts
- [ ] Migration `if (from < 8)` — safe additive migration
- [ ] Regenerate `app_database.g.dart` via build_runner
- [ ] Add `quest_definitions`, `quest_instances`, `quest_objective_progress` to `ownerUpgradeInventory`

**Repository Layer**
- [ ] `QuestRepository` interface — `lib/features/quest/domain/quest_repository.dart`
- [ ] `DriftQuestRepository` implementation — `lib/features/quest/data/drift_quest_repository.dart`
- [ ] `QuestUseCases` — `lib/features/quest/application/quest_use_cases.dart`
  - `startQuest(QuestDefinition)` → inserts `QuestInstance(active)`
  - `advance(EventEnvelopeV2)` → `QuestInstance.advanceIfMatches()`
  - `completeQuest(instanceId)` → emits `QuestCompletedEvent` via event adapter

**Feature Flag**
- [ ] Add `Feature.questV2` to `FeatureRegistry`
- [ ] Gate `QuestUseCases` behind `features.isEnabled(Feature.questV2)`
- [ ] Default: `hidden` in `BuildFeatureRegistry.fieldDefaults()`; `enabled` in `.allEnabled()`

**Deprecation**
- [ ] Add `@Deprecated('Use QuestUseCases — Phase 0 Week 10-11')` to `streak_and_daily_quest_service.dart`
- [ ] Service Quarantine Registry: update entry with deprecation date and replacement

**Tests**
- [ ] `test/features/quest/drift_quest_repository_test.dart` — CRUD + state machine transitions
- [ ] `test/features/quest/quest_use_cases_test.dart` — advance + complete flow
- [ ] `test/database/migration_v7_to_v8_test.dart` — additive migration, no row loss
- [ ] Architecture fitness test T16: `lib/features/` does not import `streak_and_daily_quest_service`

**Gate 10-11:**
```
flutter test test/features/quest/
flutter test test/database/migration_v7_to_v8_test.dart
flutter test test/architecture/fitness_test.dart
# All passing; Feature.questV2 = hidden in production build
```

---

## Week 12-13: Sync Expansion

### Goal
Add `SrsState` and `AchievementUnlock` entities to the Firestore sync collection.
Verify on 10 beta devices. Confirm Golden Journey #2 (no duplicate rewards on sync).

### Tasks

**SyncCollection Expansion**
- [ ] Add `SrsStates` to `SyncCollection` enum and Firestore rules
- [ ] Add `AchievementUnlocks` to `SyncCollection` enum and Firestore rules
- [ ] Write `SrsStateFirestoreMapper` and `AchievementUnlockFirestoreMapper`
- [ ] Update `OutboxOperationProcessor` to handle new entity types
- [ ] Write Firestore security rules for `srs_states/{doc}` and `achievement_unlocks/{doc}`

**Conflict Resolution**
- [ ] Define `ConflictPolicy.lastWriteWins` for `SrsState` (server wins on tie)
- [ ] Define `ConflictPolicy.localIdempotent` for `AchievementUnlock` (immutable once granted)

**Beta Testing**
- [ ] Deploy to 10 internal beta devices (Android + iOS mix)
- [ ] Monitor sync success rate ≥99.5% over 48h
- [ ] Confirm no duplicate `AchievementUnlock` entries created by sync

**Tests**
- [ ] `test/features/sync/srs_state_sync_test.dart`
- [ ] `test/features/sync/achievement_unlock_sync_test.dart`
- [ ] Golden Journey #2 integration test — no duplicate rewards on cold-start + sync
- [ ] Firestore rules unit tests for new collections

**Gate 12-13:**
```
flutter test test/features/sync/
# Beta sync success rate ≥99.5%
# Golden Journey #2: PASS
```

---

## Week 14-15: Learning Layer Reconciliation

### Goal
Map all `lib/learning/` call sites through `lib/features/learning/` adapters.
Eliminate SharedPreferences usage within `lib/features/`. Unify SRS authority.

### Tasks

**Adapter Layer**
- [ ] Audit all files in `lib/learning/` — document public API surface
- [ ] Write `LearningLayerAdapter` — `lib/features/learning/application/learning_layer_adapter.dart`
  - proxies all `lib/learning/` public functions through `LearningUseCases`
- [ ] Replace all `lib/learning/` imports in `lib/screens/` and `lib/features/` with adapter
- [ ] Add deprecation notices to `lib/learning/` top-level exports

**SharedPreferences Elimination**
- [ ] Run `grep -r "SharedPreferences" lib/features/` — enumerate all sites
- [ ] For each site: migrate to Drift table or `AppDependencies` injected store
- [ ] Architecture fitness test T17: `lib/features/` does not import `SharedPreferences`

**SRS Authority Unification**
- [ ] `SrsService` (legacy) → `SrsUseCases` (V2) authority migration
- [ ] Update `ownerUpgradeInventory` if new SRS tables added
- [ ] Confirm `srs_states` table is single source of truth for scheduling

**Beta Feedback**
- [ ] Collect feedback from 100 beta users over 7 days
- [ ] Crash rate V2 path vs V1 path: target <0.1% difference

**Tests**
- [ ] `test/features/learning/learning_layer_adapter_test.dart`
- [ ] Fitness test T17: no SharedPreferences in `lib/features/`
- [ ] All existing 73 screen tests still passing

**Gate 14-15:**
```
flutter test test/features/learning/
flutter test test/architecture/fitness_test.dart
# Beta crash rate delta <0.1%
# grep -r "SharedPreferences" lib/features/ → 0 results
```

---

## Week 16: Phase 0 Gate

### Goal
Final validation before Phase 1 feature development begins.

### Checklist

**Code Quality**
- [ ] All fitness tests: 15/15 (+ T16, T17 new)
- [ ] Total test count ≥980 passing, 0 failing
- [ ] `flutter analyze` — zero errors, zero warnings
- [ ] No deprecated service imported outside its quarantine boundary

**Schema**
- [ ] Schema v8 deployed and tested on all supported Android/iOS versions
- [ ] Migration test coverage: v1→v8, v6→v8, v7→v8 all passing

**Shadow Mode**
- [ ] `Feature.questV2` parity ≥99% over 7-day shadow period (internal)
- [ ] `Feature.shadowRewardV2` parity still ≥99%

**Documentation**
- [ ] `docs/v2-implementation/authority_matrix.md` updated for Phase 0 changes
- [ ] `service_quarantine_registry.md` deprecation dates filled in
- [ ] `schema_ledger.md` amended with v8 entry

**Phase 1 Readiness**
- [ ] At least 2 Phase 1 feature briefs written and reviewed
- [ ] Phase 1 branch strategy agreed

**Gate 16 — Go/No-Go for Phase 1:**
```
✅ GO: All checklist items complete, metrics healthy
⚠️ GO WITH CONDITIONS: Proceed after addressing [specific items]
❌ NO-GO: Extend Phase 0 by 1-2 weeks
```

---

## Risks Carried from Phase -1

| Risk | Owner | Mitigation |
|---|---|---|
| R4: Sync Coverage Gap | Phase 0 Week 12-13 | Expand sync collection as planned |
| R6: Two Learning Layers | Phase 0 Week 14-15 | Adapter pattern + SharedPreferences elimination |

## New Phase 0 Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Schema v8 migration fails on older devices | Low | High | Test on Android 8 (API 26) emulator |
| Beta sync generates duplicate unlocks | Medium | High | Idempotency key on `AchievementUnlock` |
| LearningLayerAdapter breaks screen tests | Medium | Medium | Adapter is additive; run 73 screen tests after each change |

---

## Appendix: Feature Flag State at Phase 0 Start

| Feature | Phase -1 Exit | Phase 0 Target |
|---|---|---|
| `Feature.shadowRewardV2` | `limited` (internal shadow) | `enabled` (internal) → `pilot` |
| `Feature.questV2` | (not yet added) | `hidden` → `limited` (internal) |
| All other features | unchanged | unchanged |
