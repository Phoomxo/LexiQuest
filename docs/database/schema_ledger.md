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

## Recorded Reservations and Migrations (v7–v10)

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

The recorded deployed lineage ends at **v10**. The current branch implements
**v11** with 29 tables, matching `AppDatabase.schemaVersion`. The former
future-v10 placeholder was superseded by the recorded Associative Learning
migration and must not be reused.
The 2026-10-21 reconciliation left v11 unreserved. The following reservation
starts the current branch's migration lineage after deployed v10.

### v11 — Immutable answer evidence metadata

**Reserved:** 2026-10-28

**Branch:** codex/remaining-system-readiness

**Owner:** Root integration; capture and sync workers have disjoint write sets

**Status:** IMPLEMENTED LOCALLY; populated-v10 migration and full Flutter suite
pass. Production deployment is not authorized by this entry.

**Columns added:**

```text
answer_attempts.evidence_class         — frozen EvidenceClass wire name
answer_attempts.evidence_context_json  — frozen EvidenceContext schema-v1 JSON
```

No table is added. The database remains at 29 tables. Existing rows receive the
exact legacy-inferred sentinel from the approved archived evidence contract
(historically called the v13 sentinel). This reservation uses v11 in the current
lineage and does not import the archived v11–v24 migration sequence.

The migration adds columns without deleting or rewriting answer facts. Capture
stores the content revision shown to the learner. Replay compares metadata as
part of immutable evidence. Ordinary attempts use an explicit versioned sync
contract; v1 legacy payloads retain the sentinel. Collection/upload authority is
not enabled, and research-bearing metadata fails closed.

Acceptance covers populated-v10 upgrade, unchanged legacy facts and learning
projections, metadata replay conflicts, owner isolation, sync payload/rules,
full-account export, merge and deletion. Eligibility enforcement for scores,
SRS and rewards is a separate implementation unit. Local rules are not deployed
by this reservation. Downgrading an upgraded database requires restoring its
pre-upgrade backup or an explicit tested downgrade; no automatic rollback is
claimed.

| Version | Phase | Purpose | Status |
|---------|-------|---------|--------|
| v11 | Remaining-system integration | Immutable answer evidence metadata; two columns, no new tables. | Implemented locally 2026-10-28 |
| v12+ | Future work | Exact purpose, owner, and migration coverage must be recorded before implementation. | Unreserved |

> **Rule:** Do not reuse v10 or v11. Reserve the next available version, starting at v12,
> through a separate approved entry before writing migration code.

---

## Conflict Register

| Conflict | Description | Resolution |
|----------|-------------|-----------|
| Duplicate future v10 | A legacy future placeholder conflicted with the recorded deployed v10 Associative Learning migration. | Resolved 2026-10-21: retained current/deployed v10; removed the obsolete future row; v11+ remains unreserved. |

---

## Amendment Log

| Date | Change | Author |
|------|--------|--------|
| 2026-08-04 | Initial ledger created. v1–v6 history recorded. v7–v9 reserved for Phase -1. | Architecture Team |
| 2026-10-21 | Reconciled duplicate future v10 against current schemaVersion 10; next reservations begin at v11. Documentation only; no version reserved or migration changed. | LQ-00 / delegated integration |
| 2026-10-28 | Reserved current-lineage v11 for two answer evidence metadata columns with populated-v10 and owner/sync lifecycle coverage. No research tables or rollout permission added. | Root integration |

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
