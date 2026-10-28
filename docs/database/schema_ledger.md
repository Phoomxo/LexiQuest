# Schema Reservation Ledger
**Phase:** Phase -1 Week 1-2 (D1.4)  
**Date Created:** 2026-08-04  
**Authority:** Architecture Team  
**Status:** ACTIVE — must be updated before any schema change is merged

---

> **Rule:** No developer may use a schema version not yet recorded here.  
> All schema version reservations require an entry in this ledger before  
> any migration code is written. PRs that bump `schemaVersion` without a  
> ledger entry are blocked.

---

## Historical Migrations (v1–v6)

| Version | Date | Author | Description | Status |
|---------|------|--------|-------------|--------|
| v1 | pre-2026 | Core team | Initial schema: LocalOwners, VocabularyCategories, VocabularyWords, VocabularyImports, VocabularyImportRows, LearningSessions, AnswerAttempts, SrsStates, ReadingProgressEntries, ReadingEvents, PointsLedgerEntries, AchievementUnlocks, RewardTransactions, OwnedRewardItems, EquippedRewardItems | ✅ Deployed |
| v2 | pre-2026 | Core team | Added sync columns to vocabulary tables | ✅ Deployed |
| v3 | pre-2026 | Core team | Added indexes for performance | ✅ Deployed |
| v4 | pre-2026 | Core team | Added `documentRevision` column to ReadingEvents | ✅ Deployed |
| v5 | pre-2026 | Core team | Added `failureCode` column to ModelDownloads | ✅ Deployed |
| v6 | 2026-03 | Core team | Created missing tables: OutboxOperations, SyncCheckpoints, SyncConflicts, RuntimeFlags, ModelDownloads | ✅ Deployed |

---

## Phase -1 Reservations (v7–v9)

### v7 — EventEnvelopeV2 Storage
**Reserved:** 2026-08-04  
**Deployed:** 2026-08-04 (Phase -1 Week 5-6 D3.2)  
**Branch:** feature/associative-reading-loop  
**Commit:** `748fb51`  
**Status:** ✅ DEPLOYED

**Actual tables added:**
```
events_v2  — append-only EventEnvelopeV2 log (22 columns)
             PK: event_id
             Unique: (owner_id, idempotency_key)
             Index:  ON events_v2(owner_id, occurred_at_utc)
```

**Migration safety:**
- Non-destructive (new table only)
- Rollback: downgrade to v6 safe (table was added, not modified)

---

### v8 — Quest Domain Persistence
**Reserved:** 2026-08-04  
**Deployed:** 2026-08-04 (Phase 0 Week 10-11 D6.1)  
**Branch:** feature/associative-reading-loop  
**Commit:** `1932d47`  
**Status:** ✅ DEPLOYED

**Actual tables added:**
```
quest_definitions        — catalog entries (no owner_id; shared content)
                           PK: quest_id
quest_instances          — per-learner state machine
                           PK: instance_id
                           Unique: (owner_id, quest_id)
                           FK: owner_id → local_owners(id)
                           FK: quest_id → quest_definitions(quest_id)
quest_objective_progress — per-objective counters
                           PK: id
                           Unique: (instance_id, objective_id)
                           FK: instance_id → quest_instances (CASCADE)
```

**ownerUpgradeInventory additions:** `quest_instances` (quest_objective_progress excluded — cascades from instance)

**Migration safety:**
- Non-destructive (new tables only)
- Rollback: downgrade to v7 safe

---

### v9 — Streak + Learning-Day Persistence
**Reserved:** 2026-08-04  
**Deployed:** 2026-08-04 (Phase 1 D7.2)  
**Branch:** feature/associative-reading-loop  
**Commit:** `77a62d8`  
**Status:** ✅ DEPLOYED

**Actual tables added:**
```
streak_states     — one row per owner; currentStreakDays, longestStreakDays,
                    freezeCount, lastLearnedAtUtcMs, updatedAtUtcMs
                    PK: owner_id (FK → local_owners)
learning_day_log  — immutable record per (owner, learning-day string)
                    PK: id ('day:{owner_id}:{YYYY-MM-DD}')
                    Unique: (owner_id, learning_day)
                    FK: owner_id → local_owners
```

**ownerUpgradeInventory additions:** `streak_states`, `learning_day_log`

**Migration safety:**
- Non-destructive (new tables only)
- Rollback: downgrade to v8 safe

---

### v10 — Associative Learning Persistence
**Reserved:** 2026-08-04  
**Deployed:** 2026-08-04 (Phase 2 D8.3)  
**Branch:** feature/associative-reading-loop  
**Commit:** `fbf2d91`  
**Status:** ✅ DEPLOYED

**Actual tables added:**
```
association_records       — keyword/story/image cues per (owner, wordKey, type)
                            PK: id
                            Unique: (owner_id, word_key, type) — upsert semantics
                            FK: owner_id → local_owners
associative_memory_states — AdaptiveAssociativeScheduler state per (owner, word)
                            PK: id
                            Unique: (owner_id, word_key)
                            FK: owner_id → local_owners
```

**ownerUpgradeInventory additions:** `association_records`, `associative_memory_states`

**Migration safety:**
- Non-destructive (new tables only)
- Rollback: downgrade to v9 safe

---

## Phase 0+ (v11+)

| Version | Phase | Purpose | Status |
|---------|-------|---------|--------|
| v10 | Phase 0 | First production V2 migration. Exact tables TBD after Phase -1 gate. | 🔮 Future |
| v11+ | Phase 0+ | TBD | 🔮 Future |

> **Rule:** v10 cannot be planned until Phase -1 completion report is signed (D5.1).

---

## Conflict Register

| Conflict | Description | Resolution |
|----------|-------------|-----------|
| None yet | — | — |

---

## Amendment Log

| Date | Change | Author |
|------|--------|--------|
| 2026-08-04 | Initial ledger created. v1–v6 history recorded. v7–v9 reserved for Phase -1. | Architecture Team |

---

## How to Add a Reservation

```markdown
### v[N] — [Short description]
**Reserved:** [YYYY-MM-DD]
**Planned Week:** [Week X-Y of which phase]
**Branch:** [branch name or TBD]
**PR:** [PR number or TBD]
**Status:** 🔒 RESERVED

**Planned tables/columns:** (list)
**Migration safety:** (describe rollback)
```

Then create the PR with:
1. This ledger updated with branch + PR number
2. Migration code in `app_database.dart` (`if (from < N)` block)
3. Migration test in `test/migrations/schema_v[N]_migration_test.dart`
4. All 3 must be in the same PR
