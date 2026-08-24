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

### v11 — AI Usage and Speech Evidence
**Implemented:** 2026-08-08
**Status:** IMPLEMENTED; release evidence pending

Added `ai_usage_events` and owner-scoped `speech_evidence`. The original AI
usage table was device-global and is superseded by v12.

### v12 — Owner-scoped AI Usage
**Reserved:** 2026-08-09
**Implemented:** 2026-08-09
**Branch:** `integration/p0-baseline`
**Status:** IMPLEMENTED; release evidence pending

Added `owner_id` to `ai_usage_events`, changed its primary key to
`(owner_id, event_id)`, and added `idx_ai_usage_owner_occurred`.

**Migration safety:** legacy v11 AI usage is dropped because no owner can be
proven. All other tables and owner data are preserved. This migration is
forward-only; reopening the database with a v11 APK is unsupported.

### v13 — Answer Evidence Metadata
**Reserved:** 2026-08-14
**Implemented:** 2026-08-14
**Branch:** `feature/alltcas-8-44-integration`
**Status:** IMPLEMENTED; release evidence pending

Added `evidence_class` and `evidence_context_json` to the existing canonical
`answer_attempts` table. Historical attempts receive the frozen schema-v1
legacy context with explicit nullable keys and `engagementAllowed: true`.
No table or competing evidence authority was added.

**Migration safety:** non-destructive column additions preserve attempt IDs,
SRS, points, achievements, events, and outbox rows. This migration is
forward-only; rollback disables new invocation and continues reading v13.

---

### v14 — Immutable Experiment Assignment
**Reserved:** 2026-08-14
**Implemented:** 2026-08-23
**Branch:** `feature/alltcas-8-44-integration`
**Status:** IMPLEMENTED; release evidence pending

Added the owner-scoped `experiment_assignments` table as the single immutable
experiment-assignment authority. The table stores the canonical owner-bound
assignment ID, experiment ID and positive version, cohort, protocol version,
and UTC assignment timestamp, with a unique constraint on
`(owner_id, experiment_id, experiment_version)`.

Owner upgrade preserves byte-equivalent assignments, rejects conflicting
immutable payloads atomically, and rebinds only the deterministic owner-bound
ID. Participant archive and explicit owner deletion share the lifecycle
manifest; consent withdrawal retains the assignment audit row.

**Migration safety:** v13→v14 adds only `experiment_assignments`; all 31 v13
tables and their data remain intact. Rollback is forward-only: disabling
research activation does not erase assignments, and older binaries must not
open a v14 database.

---

### v15 — Immutable Assessment Run
**Reserved:** 2026-08-14
**Implemented:** 2026-08-23
**Branch:** `feature/alltcas-8-44-integration`
**Status:** IMPLEMENTED; release evidence pending

Added the owner-scoped `assessment_runs` table as the immutable assessment-run
audit authority. It pins the existing LearningSession and ExperimentAssignment
identities, study cycle and phase, protocol/experiment/cohort/consent metadata,
instrument and form versions plus SHA-256 checksums, build/schema/content and
evidence-policy/feature-contract identities, and the Active, Completed, or
Abandoned lifecycle timestamps. Unique constraints bind one run to each
`learning_session_id` and one phase to each
`(owner_id, study_cycle_id, phase)`. Its foreign keys are `owner_id` →
`local_owners(id)`, `learning_session_id` → `learning_sessions(id)`, and
`assignment_id` → `experiment_assignments(id)`. Controlled responses remain
canonical AnswerAttempts; v15 adds no assessment-attempt, response, or score
table.

Owner upgrade coalesces only byte-equivalent runs and assessment evidence,
participant archive retains the audit after consent withdrawal, and explicit
owner deletion removes runs before their LearningSession, ExperimentAssignment,
and LocalOwner parents.

**Migration safety:** v14→v15 adds only `assessment_runs`; all 32 v14 tables and
their data remain intact, producing the named 33-table v15 inventory. Rollback
is forward-only: disabling assessment invocation or sync does not erase runs or
evidence, no downgrade migration is provided, and older binaries must not open
a v15 database.

---

### v16 — Versioned Content Manifest and Learning Pack Authority
**Reserved:** 2026-08-14
**Implemented:** 2026-08-24
**Branch:** `feature/alltcas-8-44-integration`
**Status:** IMPLEMENTED; release evidence pending

Added four non-owner content tables: `content_manifests` is the immutable
revision, SHA-256, byte-length, provenance, review, and publication authority;
`learning_packs` pins one manifest and one pack revision;
`learning_pack_items` stores only ordered references to canonical
`vocabulary_words.id` values; and `content_download_states` stores
device-local cache state without owning content identity. Manifest-backed pack
reads fail closed on unknown references, noncanonical item order, checksum or
byte-length mismatch, invalid provenance, unapproved review state, unpublished
state, or conflicting metadata for an existing immutable revision. SQLite
insert-conflict/update/delete triggers enforce manifest-revision immutability
at persistence; pack bytes pin each lexical reference's canonical ID,
revision, and checksum.

The canonical `vocabulary_words` table gained `content_revision`,
`content_checksum_sha256`, `content_provenance`, `content_review_state`, and
`content_publication_state`. New learner-authored words receive explicit
`userAuthored` / `unreviewed` / `private` metadata and deterministic SHA-256;
legacy rows retain readable v1 defaults. Cloud vocabulary reads accept v1 and
v2, while v2 writes remain gated on the exact separately deployed Firestore
rules revision. During that rollout, migrated rows without a checksum continue
to write v1; a newer legacy pull cannot erase an already-versioned identity.
The current rules intentionally reject v2.

The four new tables raise the named inventory from 33 to 37. Pack and manifest
rows are packaged non-owner content preserved across owner deletion; download
state is device-local; learner vocabulary remains owner-synced and participates
in owner upgrade and archive handling.

**Migration safety:** v15→v16 adds four tables and five columns with defaults;
all 33 v15 tables, rows, foreign keys, and assessment/evidence identities are
preserved. Rollback is forward-only: disabling content consumers does not erase
manifest identity, and older binaries must not open a v16 database.

---

### v17 — Saved Learning Intent and Content Report Lifecycle Reservation
**Reserved:** 2026-08-24
**Implemented:** 2026-08-24
**Branch:** `feature/alltcas-8-44-integration`
**Status:** IMPLEMENTED; release evidence pending

Added `saved_learning_items` as owner-scoped, revisioned learner intent keyed
uniquely by owner plus immutable content type, content ID, and content revision.
Save replay is idempotent; unsave is retained as a syncable tombstone. Saved
intent does not write SRS, weakness, score, quest, streak, or effort evidence.
Cloud payload v1 remains disabled until the exact Firestore rules revision is
separately deployed. Writers derive one deterministic cloud document ID from
the immutable content-identity tuple. Each immutable cloud operation receipt
uses a fixed-length digest that also binds the exact local operation and wire
mutation envelope, preventing distinct device intents from sharing a receipt.
Pull coalesces any legacy device-local ID by the same natural key before
applying a revision.

Added `content_quality_reports` only as the f21 lifecycle/schema reservation so
owner upgrade, export, withdrawal, and deletion cannot omit it. No report
repository, use case, sync writer, or UI is introduced by v17/f20.

The two owner-scoped tables raise the named inventory from 37 to 39.

**Migration safety:** v16→v17 only creates two empty tables; all 37 v16 tables
and rows remain intact. Rollback is forward-only: disabling bookmark actions or
saved-item sync does not erase local intent, and older binaries must not open a
v17 database.

---

### v18 — Trustworthy Active Learning-Time Segments
**Reserved:** 2026-08-24
**Implemented:** 2026-08-24
**Branch:** `feature/alltcas-8-44-integration`
**Status:** IMPLEMENTED; release evidence pending

Added `learning_time_segments` as the single owner-scoped durable authority for
active learning effort. Each immutable segment is pinned to a canonical
`learning_sessions` row and stores UTC start/end occurrence context, IANA
timezone ID and offset, cumulative active offset, and duration derived from a
process-monotonic clock. Wall-clock subtraction is never used as effort.
Session offsets are unique and overlap is rejected by both the repository and
SQLite guard. Automatic capture closes on pause, background, idle, completion,
and abandonment; an interrupted open interval is discarded rather than
reconstructed from untrusted wall time, while the next process resumes from
the durable monotonic offset.

The owner-scoped table participates in guest upgrade, exact lifecycle export
and delete, and immutable local-first outbox synchronization. Cloud claims are
disabled until the exact v1 Firestore rules revision is separately deployed.
The table raises the named inventory from 39 to 40.

**Migration safety:** v17→v18 creates one empty table and preserves all 39 v17
tables and rows. Rollback is forward-only: disabling automatic capture or
cloud delivery retains closed segments for export/delete, and older binaries
must not open a v18 database.

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
| 2026-08-09 | Recorded implemented v11 and owner-scoped AI usage migration v12; deployment evidence remains pending. | LexiQuest integration |
| 2026-08-14 | Reserved and implemented v13 evidence metadata on canonical answer attempts. | LexiQuest integration |
| 2026-08-23 | Reserved and implemented v14 immutable experiment assignment with lifecycle coverage. | LexiQuest integration |
| 2026-08-23 | Reserved and implemented v15 immutable assessment runs with lifecycle, export, and revisioned-sync coverage. | LexiQuest integration |
| 2026-08-24 | Implemented v16 versioned content manifests, learning packs, device-local download state, and versioned learner vocabulary metadata. | LexiQuest integration |
| 2026-08-24 | Reserved and implemented v17 saved learning intent plus the f21 content-report lifecycle table. | LexiQuest integration |
| 2026-08-24 | Reserved and implemented v18 trustworthy active learning-time segments with monotonic duration. | LexiQuest integration |

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
