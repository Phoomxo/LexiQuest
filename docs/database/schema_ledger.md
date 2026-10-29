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
**v17** with 34 tables, matching `AppDatabase.schemaVersion`. The former
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
| v13 | Remaining-system integration | Cached signed participation permits with fresh authorization at use. | Implemented locally 2026-10-29 |
| v14 | Remaining-system integration | Structured motivation measurement runs and coded responses; two local-only tables. | Implemented locally; integration 794 passed |
| v15 | Remaining-system integration | Local exposure opportunities and immutable first canonical-session linkage; one table. | Implemented locally; integration 1152 passed |
| v16 | Remaining-system integration | Immutable accepted meaning-quiz plan and durable presentation checkpoint; four columns on existing sessions. | Implemented locally; full Flutter 2728 passed |
| v17 | Remaining-system integration | Durable presentation-change intent, capped ordinal/suppression and immutable Started presentation; four columns on existing opportunities. | Implemented locally at853d4c13; full Flutter3054 passed |
| v18 | Remaining-system integration | One local Assessment run table with37 durable pins; canonical assessment-only sessions/answers remain in existing tables. | Reserved2026-10-30; executable schema remains17/34 |
| v19+ | Future work | Exact purpose, owner, and migration coverage must be recorded before implementation. | Unreserved |

> **Rule:** Do not reuse v10, v11, v12, v13, v14, v15, v16, v17 or v18. Reserve the next available version, starting at v19,
> through a separate approved entry before writing migration code.

### v12 — Authorized local experiment assignments

**Reserved:** 2026-10-29

**Branch:** codex/remaining-system-readiness

**Owner:** Root integration; assignment admission worker owns separate domain/repository tests.

**Status:** IMPLEMENTED LOCALLY in source `8504a202` at v12/30 tables.
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

**Status:** IMPLEMENTED LOCALLY in source `6a49e8e7` at v13/31 tables. Source
`6a49e8e7` has identical app inputs at `6f88bdc5`: integration 715, full Flutter
2445, analysis 0, CLI 23 and the normal debug APK pass after the late-operation
expiry correction. Enrollment, upload and deployment stay disabled.

Add one `research_participation_permits` table using the approved signed model's
20 normalized fields: `id`, `owner_id`, `local_revision`, `cloud_revision`,
`is_deleted`, `participant_class`, `age_band_code`, `assignment_id`,
`assigned_treatment`, `consent_receipt_id`, `guardian_permission_receipt_ref`,
`learner_assent_receipt_ref`, `protocol_id`, `protocol_version`,
`issued_at_utc_ms`, `expires_at_utc_ms`, `revoked_at_utc_ms`, `issuer_key_id`,
`payload_sha256`, `signature`. Require owner and assignment foreign keys; delete
permits before assignments. The resulting schema has 31 tables; this is
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

### v14 — Structured supplied-instrument motivation measurements

**Reserved:** 2026-10-29

**Branch:** codex/remaining-system-readiness

**Owner:** Root owns schema, generation, migration and owner inventory. A separate
worker owns the measurement domain/repository and
`test/support/motivation_measurement_harness.dart`. The identity worker owns the
distinct `test/support/motivation_measurement_fixture.dart` seed helper and its
seven assigned lifecycle test files; root integrates and verifies all changes.

**Status:** IMPLEMENTED LOCALLY in source `90a81306` at v14/33 tables. Populated
migration/database 38, repository 46, populated lifecycle 77 and combined
integration 794 pass; analysis reports no issues. Independent storage, lifecycle
and repository reviews accepted source `90a81306`, which also passes full Flutter
2507, CLI 23 and the normal Android debug build.
This adds two local-only tables. No new cloud collection, outbox type,
Research JSON export allowlist or runtime enrollment composition is authorized.

`motivation_measurement_runs` has 30 fields: `id`, `owner_id`, `local_revision`,
`permit_id`, `permit_payload_sha256`, `assignment_id`, `assignment_revision`,
`consent_version`, `consent_decided_at_utc_ms`, `protocol_id`, `protocol_version`,
`protocol_revision`, `treatment`, `instrument_id`, `instrument_version`,
`instrument_revision`, `instrument_checksum_sha256`, `form_id`, `form_version`,
`item_catalog_version`, `scoring_rule_version`, `app_version`, `build_id`,
`database_schema_version`, `content_revision`, `evidence_policy_version`,
`catalog_version`, `state`, `started_at_utc_ms`, `closed_at_utc_ms`.
Require owner, signed permit and assignment FKs, positive revisions and valid
state/timestamps. Canonical ID is `motivation:` plus SHA-256 of UTF-8 JSON
`[ownerId, permitId, protocolId, protocolVersion, instrumentChecksum]`.
Uniqueness of `(owner_id, assignment_id, protocol_id, protocol_version)` prevents
silently creating a second cycle with a replacement permit.

`motivation_responses` has nine fields: `id`, `owner_id`, `local_revision`,
`run_id`, `item_id`, `item_catalog_version`, `response_code`, `ordinal_value`,
`answered_at_utc_ms`. Require owner FK, run FK with cascade, bounded catalog
codes, ordinal 0..100 and nonnegative time. Canonical ID is `response:` plus
SHA-256 of UTF-8 JSON `[runId, itemId]`; unique `(owner_id, run_id, item_id)`.
No free text, caller score, caller ordinal or caller timestamp is accepted.

Use the supplied instrument's exact checksum and existing normalization formula,
pinned as `normalized-score-v1`. Partial form scores remain null. Exact response
replay keeps its original fact and time; changed-code replay conflicts. Terminal
replay cannot reopen a run or change completion time. Withdrawal commits canonical
consent denial first and then narrows existing run history without a collect grant.

Every collecting mutation runs under the existing concrete owner writer and fresh
R2 participant/actual Ed25519 receipt checks, including a final trusted-time check
after all asynchronous reads. Timing facts must distinguish unavailable from
conclusively no exposure. R3B must later supply committed visible exposure and
the first accepted canonical session; generic session timestamps are insufficient.
Do not compose collection UI before that linkage exists.

Acceptance includes a normal v13 DDL fixture, populated migration preserving all
31 tables and deletion intent, signature/consent/expiry/owner/fence races, no
research/event/outbox growth for denied participants, immutable replay/conflicts,
catalog and full-pin rejection, and populated export/purge/delete isolation.
Delete responses before runs before permits before assignments. Signed-source
owner merges remain rejected; target and same-owner signed facts remain intact.
Missing external authority fails research closed while learning continues.
Downgrade requires a pre-upgrade backup or an explicitly tested downgrade.

---

### v15 — Durable exposure and first canonical-session linkage

**Reserved:** 2026-10-29

**Branch:** codex/remaining-system-readiness

**Owner:** Root owns schema/generated source, migration, indexes, inventory and
populated export/deletion coverage. The research worker owns opportunity domain,
repository, raw timing reader, the archived research event identity helper, the
R3A active-run write boundary and distinctly named opportunity test/harness files.
The identity worker separately owns the learning data observer and canonical
repository hook with its focused tests. No repository writes overlap.

**Status:** IMPLEMENTED LOCALLY. Executable schema is v15/34 tables. Populated
migration/database 39, opportunity repository 43, populated lifecycle 99 and
combined integration 1152 pass; final analysis reports no issues. Independent
repository and storage/lifecycle reviews accepted source `1128b9e6`, which also
passes full Flutter 2594, CLI 23 and the normal Android debug build. One local-only
table is added; indexes do not change the table count.

`measurement_opportunities` has 15 fields: `id`, `owner_id`, `local_revision`,
`measurement_run_id`, `permit_id`, `entry_attempt_id`, `assigned_treatment`,
`effective_presentation`, `opened_at_utc_ms`, `presented_event_id`,
`presented_at_utc_ms`, `learning_session_id`,
`learning_session_started_at_utc_ms`, `is_index_session`, `closed_at_utc_ms`.
Require owner, run, permit, event and session FKs; the owned run FK cascades.
Enforce valid presentation values, UTC ordering, positive revisions, paired
nullable event/time and session/start fields, and a session for an index row.
Require unique owner/run/permit/entry and owner/nonnull-session attachment, plus
a partial unique index on `(owner_id, measurement_run_id)` for index rows.
Canonical opportunity ID is `opportunity:` plus SHA-256 of UTF-8 JSON
`[ownerId, measurementRunId, permitId, entryAttemptId]`; entry is UUID v4.

The Presented event retains its approved exact four-field payload and frozen
22-field envelope. Its deterministic UUID v7 encodes the exact occurrence
millisecond, which must agree with `presented_at_utc_ms` and the existing
EventsV2 epoch-seconds mapping. Do not change that global mapping, invent
Mission plan/mode fields, feed learning/reward projections or add an outbox type.

Bind only a newly inserted canonical learning session after exact persisted
tuple readback, through an optional same-database observer in a required-new
savepoint. Denied/unavailable research rolls back its sidecar while ordinary
learning commits. A start replay cannot backfill a previously denied first
session. Completion retries retain the canonical original end and rewards.
The first active or abandoned index cannot be replaced by later success.
Imported placeholders and ambiguous/unlinked/rehomed guest candidates must not
be treated as qualifying participant starts; unavailable evidence fails closed.

Append this table after its referenced owner tables in the inventory so reverse
purge removes it before events/sessions/runs/permits/assignments. Include source
research owner guards and populated export, purge proof and deletion isolation.
Acceptance covers populated-v14 migration retaining all 33 tables and deletion
intent, callback atomicity/replay, signatures, consent/expiry/owner/fence races,
event precision, gap/tie handling and zero research writes for denied participants.
Capture UI, both-treatment delivery, the other three neutral events, assessment,
upload and production authority remain separate work. Downgrade requires a
pre-upgrade backup or an explicitly tested downgrade.

---

### v16 — Accepted meaning-quiz plan and exact session recovery

**Reserved:** 2026-10-29
**Branch:** `codex/remaining-system-readiness`
**Owner:** Root owns schema/generated source, historical fixture, populated
migration, export/deletion and integration. Separate workers own bounded
domain, repository/use-case and caller/test files.
**Status:** IMPLEMENTED LOCALLY. Executable schema is v16/34. Database/migration
42, domain/repository/use-case 86, storage/lifecycle 47, UI integration 65,
other modes/bootstrap 191 and corrected owner fixtures 23 pass. Full Flutter
2728, analysis zero issues and CLI 23 pass. Independent storage/domain/core/UI
reviews accepted. Source `4a4cbdd8` also passes the normal Android debug build.

Add only four columns to existing `learning_sessions`: nullable TEXT
`accepted_plan_id`, nullable TEXT `accepted_plan_json`, INTEGER NOT NULL DEFAULT
0 `checkpoint_revision`, and nullable TEXT `checkpoint_json`. No new table,
cloud collection or outbox type. Legacy and synced-evidence rows retain
`(null, null, 0, null)` and cannot invent a resumable deck.

The versioned ownerless canonical plan hashes exact accepted question order,
content IDs/revisions/checksums, one-to-four actual options, correct option,
current supported configuration, builder and evidence/contract pins. Ownership
comes only from the canonical session. Save session, plan and first checkpoint
atomically before the accepted observer. Matching launch replay returns the
first saved plan; changed request/global identity conflicts reject.

Checkpoint variants retain the first hint receipt, exact pending answer and
original terminal time. Monotonic revision CAS prevents rewind or competing
overwrite. Canonical answer/finish and their checkpoint acknowledgement share
one transaction; no second score, reward or sync authority. Resume the exact
owner/session and reject corrupt, unsupported, drifted or remapped content.
Preserve ordinary owner rehome only when original pinned content still resolves;
never rewrite immutable plans or replay old-owner pending commands.

Migrate actual quiz, weaknessPractice and sourcePractice callers together. Use
the real same-database owner/deletion coordinator. Research denial cannot block
ordinary recovery, learning or rewards. Frozen EvidenceContext/EventEnvelopeV2
and attempt v1/v2 wire keysets stay unchanged; plan text is not uploaded.

Acceptance includes a genuine populated-v15 fixture retaining every prior
column/row in all 34 tables and pending deletion intent; fresh schema defaults;
exact replay, crash/ACK recovery, CAS races, assistance persistence, stale owner,
content drift, export/deletion and unchanged sync contracts. Re-run affected
historical migration assertions against their original column sets while
checking the new columns separately. Downgrade requires a pre-upgrade backup
or a separately tested downgrade. This reservation does not enable research.

---

### v17 — Durable presentation changes

**Reserved:** 2026-10-29

**Branch:** codex/remaining-system-readiness

**Owner:** Root owns schema/generated source, genuine historical fixture and
integration; separate workers own opportunity/timing logic and migration tests.

**Status:** IMPLEMENTED LOCALLY at `853d4c13`, executable schema v17/34.
Full Flutter3054, analysis0, CLI23/23 and normal debug APK pass. Populated
migration5 and actual pending export/purge2 pass; independent review accepted.
At reservation the executable schema was v16/34, source `61db267d`.
The verified initial-opening correction precedes this unit.

Add four columns on existing `measurement_opportunities`; no table, ordinary
sync entity, cloud collection or rollout permission is added:

```text
last_switch_ordinal                 INTEGER NOT NULL DEFAULT 0
suppressed_switch_count             INTEGER NOT NULL DEFAULT 0
started_effective_presentation      TEXT NULL
pending_presentation_change_json    TEXT NULL
```

Ordinal is0..10; suppression is nonnegative and only valid after ordinal10.
Started presentation is null or the existing standard/adventure code. Pending
intent is bounded canonical versioned JSON, parsed strictly at its boundary.
Current presentation derives from immutable first `effective_presentation`
and committed transition parity. The initial Presented fact remains unchanged.

Migration preserves every old column/row across all34 tables, accepted quiz
plan/checkpoint bytes and pending owner-deletion intent. Counters start at0 and
pending is null. Backfill Started presentation from `effective_presentation`
exactly where `learning_session_id IS NOT NULL`; unlinked stays null. This is
metadata only: missing/tampered Started events remain invalid and no event is
minted. A genuine pre-bump v16 snapshot was captured through normal database
open, checking34 tables, six explicit indexes,15 opportunity columns and the
four accepted-quiz fields. Its SHA-256 is
`52e331cff2584e21e634f9c3804861dfae006fcf5204f390f5093664d945c9ac`.

Prepare commits one exact receipt before a target frame. Capture after the
actual frame requires fresh authority, final visibility and CAS of the exact
prepared receipt/revision. Never hold SQLite across a frame. Unknown/restarted
pending exposure denies Research; no timeout, automatic abort, replacement
index or backfill. Retry requires the original in-process prepared handle.
Twelve actual committed transitions produce ten frozen Changed events plus
suppression2. Same choice, stale request and retries create no new transition.

Freeze the derived presentation once at canonical Started. Canonical completed
sessions deny prepare and commit even if completion sidecar/ACK is missing.
Pending intent denies ordinary Research timing/capture while canonical learning
and its single SRS/reward/sync authorities continue. Validate all original
Presented/Started/Completed and Changed envelopes, identity and pin contracts.

Acceptance includes fresh/default constraints, genuine populated-v16 migration,
linked/unlinked backfill, invalid Started rejection, reopen, prepare/render/ACK
crash windows, exact counters and event cardinality, owner/consent/authority
races, unchanged learning effects, personal export and purge. Downgrade needs a
pre-upgrade backup or a separately tested downgrade; none is implied here.

---

### v18 — Owner-scoped controlled Assessment runs

**Reserved:** 2026-10-30

**Branch:** codex/remaining-system-readiness

**Owner:** Root owns schema/generated source, inventory and migration/lifecycle
integration. Domain, authority, writer and application workers have disjoint
write sets in the [Assessment execution plan](../superpowers/plans/2026-10-30-assessment-writer-integration.md).

**Status:** RESERVED. Executable schema remains v17/34 at reservation. The
latest verified application source is `853d4c13`; attestation is `3810b265`.

Add one local-only `assessment_runs` table; total35. Its37 columns are:

```text
id owner_id learning_session_id study_cycle_id phase state
protocol_id protocol_version experiment_id experiment_version
assignment_id cohort consent_version consent_decided_at_utc_ms
instrument_id instrument_version form_id form_version
instrument_checksum_sha256 form_checksum_sha256 app_version build_id
database_schema_version content_revision evidence_policy_version
feature_contract_revision feature_contract_hash started_at_utc_ms
completed_at_utc_ms abandoned_at_utc_ms assignment_revision
protocol_revision instrument_revision form_content_revision
participation_permit_id participation_permit_revision
participation_permit_payload_sha256
```

Use actual FKs to owner, canonical Assessment session, assignment, signed
participation permit and the existing R3 cycle. Cycle/session/assignment/permit
references must not cascade away original evidence. Unique session and unique
owner/cycle/phase prevent replacement runs. Validate positive revisions,
canonical hashes, phase/state/cohort, consent-before-start and exclusive
terminal times. All original pins remain immutable across exact retries.

Assessment reuses existing answer/session tables through a dedicated SQL writer.
It must not reopen ordinary evidence admission or invoke ordinary SRS, XP,
reward, achievement, Quest, Streak, lifecycle or outbox hooks. The R3 cycle
anchors the exact first intervention, not an Assessment instrument or score.
Pre requires no opportunity; post requires the original completed first index.
Missing, pending, abandoned or inconsistent evidence denies Research.

Preserve all existing34-table rows, pending switch JSON, accepted quiz bytes,
ordinary projections and durable deletion intent. A genuine schema17 snapshot
was captured before the bump through normal open:34 tables, six indexes,
19 opportunity fields and four exact CHECK expressions. SHA-256:
`1829afc95e6c6d1217123d3eda4532a96bafa2df613a4a5da6c63167cf167a0c`.
The new table starts empty; no synthetic enrollment or row backfill occurs.

Add the table to owner inventory and signed-source rehome rejection. Reverse
purge removes it before its parents; personal export retains exact owner pins.
Acceptance includes populated-v17/reopen, real FK/uniqueness rejection, both
owners, signed-source merge denial, persistent deletion proof, zero Assessment
outbox and continued ordinary sync rejection/isolation. No new cloud collection,
upload type, rollout authority or efficacy claim is created. Downgrade requires
a pre-upgrade backup or a separately tested downgrade.

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
| 2026-10-29 | Attested v13 and reserved v14 for two local-only supplied-instrument measurement tables with immutable responses and fresh receipts; canonical session linkage remains a separate prerequisite for UI composition. | Root integration |
| 2026-10-29 | Attested v14 at source 90a81306 and reserved v15 for one local-only exposure/index linkage table with canonical learning savepoints and frozen event precision. Runtime remains v14 until implementation. | Root integration |
| 2026-10-29 | Reserved v16 for four columns on existing learning sessions, storing the exact accepted quiz and CAS checkpoint with canonical learning transactions. Runtime remains v15 until implementation; table count stays 34. | Root integration |
| 2026-10-29 | Reserved v17 after the verified initial-opening correction and genuine v16 schema capture for four existing-opportunity columns; original presentation/event proof and owner lifecycle stay intact. Executable schema remains v16 until implementation. | Root integration |
| 2026-10-30 | Attested current-lineage v17/34 at853d4c13 with full Flutter3054, analysis0, CLI23, backend CPU390 and normal debug APK; all620 Dart hashes unchanged. Assessment storage v18 remains unreserved. | Root integration |
| 2026-10-30 | Reserved v18 for one37-pin Assessment run table after genuine v17 capture; exact R3 intervention FK, dedicated writer and ordinary-projection isolation required. Executable schema remains17/34 until implementation. | Root integration |

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
