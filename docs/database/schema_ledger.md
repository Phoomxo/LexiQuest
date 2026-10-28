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
**v12** with 30 tables, matching `AppDatabase.schemaVersion`. The former
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
| v12 | Remaining-system integration | Owner-scoped immutable experiment assignments; one new table. | Implemented locally 2026-10-29 |
| v13 | Remaining-system integration | Cached signed participation permits with fresh authorization at use. | Reserved 2026-10-29 |
| v14+ | Future work | Exact purpose, owner, and migration coverage must be recorded before implementation. | Unreserved |

> **Rule:** Do not reuse v10, v11, v12 or the reserved v13. Reserve the next available version, starting at v14,
> through a separate approved entry before writing migration code.

### v12 — Authorized local experiment assignments

**Reserved:** 2026-10-29

**Branch:** codex/remaining-system-readiness

**Owner:** Root integration; assignment admission worker owns separate domain/repository tests.

**Status:** IMPLEMENTED LOCALLY. Current executable schema is v12/30 tables.
Populated migration, owner lifecycle and signed admission checks pass within a
655-test integration suite. Source `8504a202` passes full Flutter 2385, analysis
0, CLI 23 and the normal Android debug build. This entry does not authorize research
enrollment, collection, upload or deployment.

Add `experiment_assignments` with seven columns: `id`, `owner_id`,
`experiment_id`, `experiment_version`, `cohort`, `protocol_version`,
`assigned_at_utc_ms`. The primary ID is `experiment-assignment:` plus SHA-256 of
the UTF-8 JSON tuple `[ownerId, experimentId, experimentVersion]`. Require an
owner foreign key and uniqueness of `(owner_id, experiment_id, experiment_version)`.
The resulting schema has 30 tables; the approved feature catalog remains
8 domains and 44 capabilities.

Only the admission repository may create this local fact. It requires matching
current P256 participation authority, concrete Ed25519 collect authorization,
explicit protocol/instrument revision pins, trusted time, accepted versioned
consent and the persistent active-owner/deletion boundary. Caller-supplied
cohort, timestamps and boolean permission are not admission APIs. The timestamp
records the first successful local admission; it is not permit issuance or a
server assignment time. No assignment events or outbox mutations are added.

Acceptance covers populated-v11 migration with existing facts unchanged,
signature/revision/withdrawal/time rejection, current-authority unavailability,
idempotent concurrent admission, owner/deletion races, and populated export and
deletion isolation. Owner merge must validate canonical IDs, rekey with the
destination owner, deduplicate only exact cohort/protocol/time matches and
roll back the entire merge on conflict or collision. Signed participation
documents must not be silently rewritten.

Trusted time is checked at full precision after asynchronous authority checks
and after SQLite writer acquisition. Millisecond projection is used only where
the existing P256 contract and stored timestamp require it. Missing production
authority adapters deny admission; synthetic authority fixtures permit local
engineering checks. Cross-authority revocation is not claimed atomic with
SQLite commit. Downgrade requires a pre-upgrade backup or an explicitly tested
downgrade; no automatic rollback is claimed.

### v13 — Cached signed participation and fresh participant context

**Reserved:** 2026-10-29

**Branch:** codex/remaining-system-readiness

**Owner:** Root integration owns schema/generated source/inventory; separate
workers own the participation repository and signed-owner merge checks.

**Status:** RESERVED. Current executable schema remains v12/30 tables until
implementation and verification. Enrollment, upload and deployment stay disabled.

Add one `research_participation_permits` table using the approved signed model's
20 normalized fields: `id`, `owner_id`, `local_revision`, `cloud_revision`,
`is_deleted`, `participant_class`, `age_band_code`, `assignment_id`,
`assigned_treatment`, `consent_receipt_id`, `guardian_permission_receipt_ref`,
`learner_assent_receipt_ref`, `protocol_id`, `protocol_version`,
`issued_at_utc_ms`, `expires_at_utc_ms`, `revoked_at_utc_ms`, `issuer_key_id`,
`payload_sha256`, `signature`. Require owner and assignment foreign keys; delete
permits before assignments. The resulting schema will have 31 tables; this is
not a change to the 8-domain/44-capability catalog.

Persisted signed documents are cached facts, not proof of current issuer state.
Active import and participant reads reuse v12 admission with the same database,
trusted clock, consent and owner fence. A repository must not supply its own
stored row as `ResearchParticipationDocumentSource` authority. Rejected import
creates no permit, assignment, event or outbox row. A failed permit insert must
roll back any assignment first admitted in the same transaction.

Copy issuer-signed revisions verbatim. Same-revision payload changes, stale
updates, changed immutable pins and resurrection of signed revocation/deletion
are rejected. Authentic signed narrowing updates may amend an existing permit
after expiry or withdrawal; they must never enroll a new participant. Local
consent withdrawal denies use without inventing an issuer-signed revocation.

Owner-changing merges with source-owned signed permits must roll back rather
than rewrite their owner/assignment pins. Existing target-owned permits and
same-owner binding remain intact. Export, deletion and purge proof must cover
the populated table with owner isolation. Acceptance also covers populated-v12
migration, restart/replay, actual signature rejection, minor receipts, current
authority unavailability and expiry/owner/deletion races. Physical UAT and
production authority adapters remain separate. Downgrade requires a pre-upgrade
backup or an explicitly tested downgrade.

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
| 2026-10-29 | Reserved current-lineage v12 for one immutable assignment table with strict admission and populated migration/owner lifecycle checks. Runtime remains v11 until implementation; no research rollout permission added. | Root integration |
| 2026-10-29 | Reserved current-lineage v13 for one cached signed participation table; use must reauthorize against independent current authority and preserve signed owner pins. Runtime remains v12 until implementation. | Root integration |

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
