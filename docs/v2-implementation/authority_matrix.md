# Write Path Authority Matrix
**Phase:** Phase -1 Week 1-2 (D1.1)  
**Date:** 2026-08-04  
**Status:** ACTIVE — binding from this date forward  
**Auditor:** Architecture Team

---

## Critical Findings Summary

| Severity | Count | Description |
|----------|-------|-------------|
| 🔴 CRITICAL | 3 | Dual/no authority — blocks V2 migration |
| 🟠 HIGH | 4 | Legacy bypass or in-memory state |
| 🟡 MEDIUM | 6 | Acceptable multi-writer with sync role |
| 🟢 LOW | 8 | Single clear authority |

---

## Drift Table Write Authorities (21 tables)

| # | Table | Authority Owner | Secondary Writers | Risk | V2 Action |
|---|-------|----------------|-------------------|------|-----------|
| 1 | `LocalOwners` | `features/identity/data/drift_local_owner_repository.dart` | `drift_owner_upgrade_repository.dart` (upgrade flow only) | LOW | Keep — identity is stable |
| 2 | `ResearchConsents` | `features/consent/data/drift_research_consent_repository.dart` | None | LOW | Keep |
| 3 | `VocabularyCategories` | `features/vocabulary/data/drift_vocabulary_repository.dart` | Import: `drift_vocabulary_import_repository.dart`; Sync-in: `drift_sync_store.dart` | MEDIUM | Keep — 3 writers are intentional (local edit, import, remote sync) |
| 4 | `VocabularyWords` | `features/vocabulary/data/drift_vocabulary_repository.dart` | Import: `drift_vocabulary_import_repository.dart`; Sync-in: `drift_sync_store.dart` | MEDIUM | Keep — same pattern as categories |
| 5 | `VocabularyImports` | `features/vocabulary/data/drift_vocabulary_import_repository.dart` | None | LOW | Keep |
| 6 | `VocabularyImportRows` | `features/vocabulary/data/drift_vocabulary_import_repository.dart` | None | LOW | Keep |
| 7 | `LearningSessions` | `features/learning/data/drift_learning_repository.dart` | Sync-in: `drift_sync_store.dart`; Status-update: `drift_learning_projection_rebuilder.dart` | MEDIUM | Keep — sync writer is downstream |
| 8 | `AnswerAttempts` | `features/learning/data/drift_learning_repository.dart` | Sync-in: `drift_sync_store.dart` | MEDIUM | Keep — sync writer is downstream |
| 9 | `SrsStates` | `features/learning/data/drift_learning_projection_rebuilder.dart` | Migration cascade: `drift_owner_upgrade_repository.dart` | LOW | Keep — projection pattern is correct |
| 10 | `ReadingProgressEntries` | `features/learning/data/drift_learning_projection_rebuilder.dart` | None | LOW | Keep — sole writer |
| 11 | `ReadingEvents` | `features/learning/data/drift_learning_repository.dart` | Sync-in: `drift_sync_store.dart` | MEDIUM | Keep |
| 12 | `PointsLedgerEntries` | **⚠️ CONFLICT** | **BOTH** `drift_learning_projection_rebuilder.dart` AND `drift_reward_projection_rebuilder.dart` delete+insert | **CRITICAL** | **MUST RESOLVE before V2**: assign sole authority, decide whether this is XP or Coins ledger |
| 13 | `AchievementUnlocks` | `features/learning/data/drift_learning_repository.dart` | Rebuild: `drift_learning_projection_rebuilder.dart` | LOW | Keep — repository writes event-time, rebuilder is restore path |
| 14 | `RewardTransactions` | `features/rewards/data/drift_reward_repository.dart` | Sync-in: `drift_sync_store.dart` | MEDIUM | Keep — coins ledger. Freeze as spendable-coins authority |
| 15 | `OwnedRewardItems` | `features/rewards/data/drift_reward_projection_rebuilder.dart` | None | LOW | Keep — projection only |
| 16 | `EquippedRewardItems` | `features/rewards/data/drift_reward_projection_rebuilder.dart` | None | LOW | Keep — projection only |
| 17 | `OutboxOperations` | `features/sync/data/drift_sync_store.dart` (lifecycle mgmt) | Writers: learning, rewards, identity, vocabulary repositories (append-only) | MEDIUM | Keep — outbox pattern is intentional multi-writer; sync store owns lifecycle |
| 18 | `SyncCheckpoints` | `features/sync/data/drift_sync_store.dart` | None | LOW | Keep |
| 19 | `SyncConflicts` | `features/sync/data/drift_sync_store.dart` | None | LOW | Keep |
| 20 | `RuntimeFlags` | `features/sync/data/drift_cloud_policy_cache.dart` | Delete: `drift_sync_store.dart` (stale cleanup only) | LOW | Keep — policy cache has clear authority |
| 21 | `ModelDownloads` | `features/device_model/data/drift_model_download_repository.dart` | None | LOW | Keep |
| 22 | `EventsV2` | `features/events/` (via EventV1ToV2Adapter) | Sync-in: none (append-only) | LOW | Phase -1 D3.2 — frozen contract |
| 23 | `QuestDefinitions` | `features/quest/data/drift_quest_repository.dart` | None (catalog data) | LOW | Phase 0 D6.1 — no owner FK; catalog only |
| 24 | `QuestInstances` | `features/quest/data/drift_quest_repository.dart` | None | LOW | Phase 0 D6.1 — owner-scoped, state machine |
| 25 | `QuestObjectiveProgress` | `features/quest/data/drift_quest_repository.dart` | None | LOW | Phase 0 D6.1 — cascades from QuestInstances |
| 26 | `StreakStates` | `features/motivation/data/drift_streak_repository.dart` | None | LOW | Phase 1 D7.2 — one row per owner; owned by StreakUseCases |
| 27 | `LearningDayLog` | `features/motivation/data/drift_streak_repository.dart` | None | LOW | Phase 1 D7.2 — immutable append-only; insertOrIgnore |
| 28 | `AssociationRecords` | `features/learning/data/drift_associative_learning_adapter.dart` | None | LOW | Phase 2 D8.3 — insertOrReplace; one cue per (owner, word, type) |
| 29 | `AssociativeMemoryStates` | `features/learning/data/drift_associative_learning_adapter.dart` | None | LOW | Phase 2 D8.3 — insertOrReplace; one state per (owner, word) |

---

## SharedPreferences Write Authorities

| Key | Writer | Risk | V2 Action |
|-----|--------|------|-----------|
| `zpd_level` | `lib/services/local_user_progress_store.dart` | HIGH | QUARANTINE — must migrate to Drift RuntimeFlags or new ZPD table |
| `streak_count` | `lib/services/local_user_progress_store.dart` | HIGH | QUARANTINE — must migrate to new StreakStates Drift table (Week 5-6) |
| `mastered_words` | `lib/services/local_user_progress_store.dart` | HIGH | QUARANTINE — duplicate of SrsStates; will be derived from projection |
| `srs_progress` | `lib/services/local_user_progress_store.dart` | HIGH | QUARANTINE — shadowed by features/learning Drift SrsStates; remove |
| `srs_storage_key` | `lib/services/srs_service.dart` | HIGH | QUARANTINE — fully superseded by `features/learning/data/drift_learning_repository.dart` |
| `_kProgressKey` (JSON blob) | `lib/progress/local_progress_repository.dart` | HIGH | QUARANTINE — legacy progress blob; no new code may read/write |

---

## In-Memory State (Volatile — Resets on App Restart)

| State | Location | Values | Risk | V2 Action |
|-------|----------|--------|------|-----------|
| `_currentStreakDays` | `lib/services/streak_and_daily_quest_service.dart:26` | Hardcoded `= 1` | **CRITICAL** | QUARANTINE — streak state lost on restart; migrate to Drift |
| `_streakFreezeCount` | `lib/services/streak_and_daily_quest_service.dart:27` | Hardcoded `= 1` | **CRITICAL** | QUARANTINE — freeze count lost on restart |
| `_quests` list | `lib/services/streak_and_daily_quest_service.dart:28-53` | Hardcoded quest definitions | **CRITICAL** | QUARANTINE — quest progress lost on restart; new Quest domain needed |
| Incompatible `DailyQuest` model | `lib/services/adaptive_daily_quest_service.dart` | `{title, description, targetMode}` collides with `{id, title, targetCount, currentProgress}` | **CRITICAL** | QUARANTINE — model conflict with streak_and_daily_quest_service.dart |

---

## Direct Firestore Writes (Bypassing Outbox Pattern)

| Operation | Location | Risk | V2 Action |
|-----------|----------|------|-----------|
| `_wordsCollection.doc().delete()` | `lib/services/word_service.dart:102,112` | HIGH | QUARANTINE — bypasses outbox; offline-unsafe; no idempotency |
| `_wordsCollection.doc().update()` | `lib/services/word_service.dart:121` | HIGH | QUARANTINE — same issue; vocabulary writes must go through `drift_vocabulary_repository.dart` |
| `user.updatePassword()` | `lib/features/account/data/firebase_account_gateway.dart:153` | LOW | Keep — auth operation, not data mutation |

---

## Conflict Resolution Required Before Phase 0

### CONFLICT C1: PointsLedgerEntries — Dual Authority (CRITICAL)

**Problem:**  
Two separate rebuilders write to the same table with incompatible semantics:

```
drift_learning_projection_rebuilder.dart:44-46
  → inserts into pointsLedgerEntries with entryType = learning events (XP)
  
drift_reward_projection_rebuilder.dart:47-49  
  → inserts into pointsLedgerEntries with entryType = reward events (Coins?)
```

**Impact:** V2 Semantic Freeze defines XP ≠ Coins. A single ledger table cannot serve both without ambiguity.

**Resolution Required (Week 5-6):**
1. Designate `PointsLedgerEntries` as the **XP (non-spendable)** ledger only
2. `drift_reward_projection_rebuilder.dart` must be updated to use only `RewardTransactions` for coin balance
3. OR: rename `PointsLedgerEntries` to `XpLedgerEntries` in schema v7 migration
4. Decision must be documented in `semantic_contract.md` before either rebuilder is modified

**Gate:** No V2 code writes to `PointsLedgerEntries` without explicit `entryType = 'xp'` semantic

---

### CONFLICT C2: Quest Authority — No Persistent Owner (CRITICAL)

**Problem:**  
Two services claim quest authority with incompatible data models and no persistence:

```
streak_and_daily_quest_service.dart  →  DailyQuest{id, title, targetCount, currentProgress, coinReward, xpReward}
adaptive_daily_quest_service.dart    →  DailyQuest{title, description, targetMode}  ← DIFFERENT MODEL
```
Both services store quest state in RAM only. Progress is lost on app restart.

**Resolution:** Week 5-6 Quest Domain Contract (D3.5) establishes new Drift-backed authority.

---

### CONFLICT C3: SRS Dual Storage (HIGH)

**Problem:**
- `lib/services/srs_service.dart` stores SRS state in `SharedPreferences[srs_storage_key]`
- `features/learning/data/drift_learning_repository.dart` + `drift_learning_projection_rebuilder.dart` store SRS state in Drift `SrsStates` table
- Both active paths may serve different screens

**Resolution:** Quarantine `srs_service.dart`. All SRS reads/writes route to `features/learning` only.

---

## Authority Matrix Coverage

```
Total Drift tables:           21 / 21  ✅
SharedPreferences keys:        6 / 6   ✅
In-memory state locations:     4 / 4   ✅
Direct Firestore writes:       3 / 3   ✅
Conflicts documented:          3       ✅
```

**Gate 1.1 Status:** ✅ PASS — 100% coverage, all conflicts documented
