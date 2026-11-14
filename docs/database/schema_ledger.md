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

### v11 — Local calendar evidence and recurring Quest claims
**Reserved:** 2026-11-14
**Branch:** codex/figcraft-flutter-prototype
**PR:** [16](https://github.com/Phoomxo/LexiQuest/pull/16)
**Owner:** Root integration; disjoint table/test writers under S6-C
**Status:** 🔒 RESERVED — locally implemented/verified in S6-C (Flutter1946, AI107, analysis/reviews); no rollout

**Planned tables/columns:**
- Nullable `answer_attempts.calendar_evidence` and `quest_intent`, preserving old rows.
- New `owner_calendar_epochs`, `quest_definition_revisions` (shared),
  `quest_claim_receipts`, `streak_baselines`, `streak_token_adjustments`.
- Quest instance origin/period/calendar/segments/digest/alias/kind fields,
  exact revision FK and canonical period uniqueness replacing lifetime uniqueness.
- Owner/time/ID query index; existing indexes and original EventEnvelopeV2 schema unchanged.

**Migration safety and coverage:**
Frozen actual v10 SQL fixture and focused RED precede migration code. Stage and
restore parent/objective data with FK enforcement inside one write transaction;
compare original data/IDs/JSON and publish version last. Preserve legacy balances,
freeze assets and unverifiable history; generate no claims or research events.
Four new owner scopes require migration, merge, full local export and deletion;
shared definitions remain public/retained. Calendar/claim authority stays local,
with local-only sync metadata handling and schema-aware export/backend contracts.
Real-file reopen/rollback/current-create parity and historical upgrades are required.
Same-database downgrade to old clients is unsupported; never reset live data.

The concrete write set and checks are in
`docs/development/figcraft-v1/s6-persistence-plan.md`. Existing approved S1–S7
implementation authority covers this local card; release and real-data authority
remain separate. AppDatabase is still v10 at reservation time.

---

### v12 — Local practice recovery and study records
**Reserved:** 2026-11-14
**Branch:** codex/figcraft-flutter-prototype
**PR:** [16](https://github.com/Phoomxo/LexiQuest/pull/16)
**Owner:** Root integration; disjoint schema/test/backend writers
**Status:** Implemented locally, verification in progress. No rollout.

**Tables and columns:**
- Nullable local-only session `question_plan_json` and `continuation_json`;
  nullable attempt `answer_evidence_json` (slot plus selected/reveal evidence).
- Default-false local `vocabulary_words.is_bookmarked`, preserving public sync.
- Three owner scopes: `local_content_reports`, `focus_sessions`,
  `learning_preferences`. Focus is independent of learning sessions/rewards.
  Actual generated table count must be37, not the44-feature catalogue count.

**Migration safety and coverage:**
The actual fresh-v11 schema was captured before migration and checked against
the real frozen-v10→v11 upgrade for columns/FKs/indexes. Its synthetic fixture
contains no learner rows. Focused RED precedes migration code. Add nullable/default
columns without fabricated history, duration, preferences or research facts.
Test populated v11 file upgrade/reopen, fresh/upgraded parity, failure rollback,
re-entry, FK/check constraints and all historical upgrade paths. Preserve IDs,
raw data, existing indexes and frozen research/event contracts.

Every new owner scope requires merge, export and deletion. Bookmark follows the
existing word, with explicit duplicate OR and inbound-local-field preservation.
Preference singleton/closed-goal and two-open-timer merges need deterministic
rules. Local exports and backend schema-version scope validation extend together;
old versions and fixed cloud deletion scopes remain unchanged. New fields/tables
must not enter cloud/research payloads. Same-database downgrade is unsupported;
never reset live data. The executable order and acceptance are recorded in
`docs/development/figcraft-v1/execution.md` under the S7 persistence plan.

Existing S1–S7 authorization covers local implementation/synthetic tests. Real
enrollment/upload, deployment, live deletion and merge permission stay separate.
AppDatabase remains v11 at reservation; f31 source34e628a7 passed2176 locally.

---

## Phase 0+ (v13+)

Current local implementation is **v12**, matching `AppDatabase.schemaVersion`.
Integration verification is in progress. The last deployed
entry remains **v10** Associative Learning Persistence. The former future-v10
placeholder was superseded by that recorded migration and must not be reused.
Versions **v11** and **v12** are reserved above. The next reservable version is **v13**.

| Version | Phase | Purpose | Status |
|---------|-------|---------|--------|
| v13+ | Future work | Exact purpose, owner, and migration coverage must be recorded before implementation. | Unreserved |

> **Rule:** Do not reuse v10, v11 or v12. Reserve the next available version, starting at v13,
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
| 2026-11-14 | Reserved v11 for S6-C after actual v10 fixture and focused RED; new local calendar/Quest/streak data requires lifecycle and policy coverage before acceptance. No rollout. | Root integration |
| 2026-11-14 | Reserved v12 for local practice recovery, bookmark and three study owner scopes after actual v11 capture/parity; coordinated lifecycle/export/delete and local-only sync checks required. No rollout. | Root integration |

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
