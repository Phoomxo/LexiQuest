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
**Planned Week:** Week 5-6 (D3.2)  
**Branch:** TBD (will be created in Week 5)  
**PR:** TBD  
**Status:** 🔒 RESERVED

**Planned tables:**
```
EventEnvelopeV2Store          — append-only event log (22 fields)
EventEnvelopeV2Inbox          — received events pending processing
V1ToV2EventAdapterLog         — adapter run log for parity tracking
```

**Planned column additions:**
```
PointsLedgerEntries.semanticType  — 'xp' | 'legacy_points'
  (if board approves rename: migrate to XpLedgerEntries instead)
```

**Migration safety:** 
- Non-destructive (new tables + one nullable column)
- Rollback: drop new tables, revert column (no data loss on downgrade)

---

### v8 — Quest, Streak, and Mastery Foundation
**Reserved:** 2026-08-04  
**Planned Week:** Week 5-6 (D3.5) + Week 7-8  
**Branch:** TBD  
**PR:** TBD  
**Status:** 🔒 RESERVED

**Planned tables:**
```
QuestInstances                — persistent quest state (replaces in-memory DailyQuest)
QuestCompletionEvents         — immutable completion log with idempotencyKey
StreakStates                  — per-owner streak + freeze count (replaces in-memory)
LearningDayLog                — one row per learning day per owner (for streak calc)
```

**Migration safety:**
- Non-destructive (new tables only)
- Rollback: drop all 4 tables

---

### v9 — Identity Consolidation + V2 Projection Tables
**Reserved:** 2026-08-04  
**Planned Week:** Week 7-8 (Shadow Mode)  
**Branch:** TBD  
**PR:** TBD  
**Status:** 🔒 RESERVED

**Planned tables:**
```
IdentityMappings              — guestOwnerId ↔ cloudUid ↔ canonicalOwnerId
V2ProjectionCheckpoints       — shadow mode projection run tracking
ParityTestResults             — shadow vs V1 match records (≥99% required)
```

**Migration safety:**
- Non-destructive (new tables only)
- Rollback: drop all 3 tables

---

## Phase 0+ (v10+)

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
