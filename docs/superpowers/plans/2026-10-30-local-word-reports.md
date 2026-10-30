# Local owned-word reports — implementation plan

Baseline: cycle12 `codex/remaining-system-readiness`, verified application `597187e58049a57d3266191b1310f9d71a56693b`, SavedWords attestation `b06be6e8aa0855764e126a73a17f9cb47dd35202`, executable **v19/36**. Wave16 passed Flutter3922, analysis0, CLI23, backend390/one existing opt-in skip and normal debug APK. This reviewed card continues the user's authorized unfinished-system task; no production report transport or rollout is authorized.

## Outcome and actual design contract

Implement owned-word report → editable review → immutable local queue → restart/read receipt. Catalog f21/TOR `docs/design/lexiquest-revision-5-ui-tor-and-traceability.md:250` require issue/version/truthful result. `docs/design/2026-10-20-figma-r11-screen-by-screen-critique.md:146` explicitly names **F21B ตรวจรายงานก่อนส่ง**; `docs/design/2026-10-20-r11-implementation-map.md:129` says editable review. It does not require post-submit editing. Keep f21/f22 partial: AI generation, documents, chat, transport and moderation are separate targets/cards. Do not change 8/44, EvidenceContext or event contracts.

## One immutable record, ten columns

Proposed `WordReports` / `word_reports`, generated `WordReportRow`:

| Column | Constraint / meaning |
|---|---|
| id | opaque `word-report:<generated ID>`, global PK, nonblank <=256 UTF-8 bytes |
| owner_id | current owner, restrictive FK local_owners.id |
| word_id, category_id | immutable historical IDs; nonblank <=256 runes; deliberately no live parent FKs |
| word_revision | positive SQL local revision |
| snapshot_json | canonical ownerless JSON, <=8192 UTF-8 bytes |
| snapshot_sha256 | exact lowercase64-hex SHA256 of snapshot bytes |
| reason | incorrectMeaning / spelling / partOfSpeech / inappropriate / other |
| comment | nullable, normalized nonblank when present, <=500 runes /2048 UTF-8 bytes |
| queued_at_utc_ms | nonnegative integer, original UTC millisecond |

All columns except comment NOT NULL. Integer types/positive revision/nonnegative time, byte bounds, reason/hash shape and other→non-null comment receive SQL checks where expressible; parser validates exact JSON shape/canonical bytes/hash and duplicated pins. No status, local/cloud revision, lease, attempt counter, worker or second receipt table: every row means queued **locally**, with no transport claim. No natural-key dedup silently merges two explicit reports; stable ID deduplicates the same submission.

Snapshot has exactly nine ordered keys: version=`owned-word-report-v1`, wordId, categoryId, wordRevision, spelling, meaning, partOfSpeech, source, cefrLevel(nullable). Use current vocabulary limits; canonical encoder/parser are the sole report-content representation. SQL historical columns must equal the snapshot pins. Current owner is excluded from snapshot/hash. No copied whole file/chat, generated sentence or learning evidence metadata.

Historical target cannot FK to an overwritten live word/revision. Existing guest dedup physically deletes source words. Retain original ID/revision/content through edit, deletion, recreation and dedup, without substituting the survivor. This queue is evidence of a user's report, not a new content/learning authority.

## Exact DTO/API and transaction

New `domain/word_report.dart` owns ReportReason, immutable WordReportTarget.fromWord(VocabularyWord), WordReportCommand, StoredWordReport.fromStorage and SubmitResult(queued/replayed, report), plus WordReportRepository:
`submit(command) -> Future<SubmitResult>`;
`watchOwner(expectedOwnerId) -> Stream<List<StoredWordReport>>`.

WordReportUseCases.prepareSubmit(expectedOwnerId,target,reason,comment) validates/normalizes reviewed input and captures one ID/UTC-ms time **once on first confirmation**; submit/watch delegate without retries/notifiers. Errors distinguish staleTarget, collision and unavailable without private diagnostics. Merely opening/reviewing/cancelling creates zero rows. Target.fromWord is pure and preserves the displayed DTO's original revision/content; it does not reload a newer word silently.

Drift repository requires same-DB real coordinator and rejects ambient transactions. In its own owner-write transaction:
1. Verify current owner/deletion fence; look up report ID. Existing own row must match the entire immutable command payload and current owner. Exact match returns replay, different payload collides; foreign-owner ID denies without exposing its content.
2. A new ID requires active owned word AND category, exact historical IDs/revision and canonical current SQL snapshot/hash. Stale/missing target fails; no alias or fallback.
3. Insert once. Final nested owner/fence check, exact stored-row readback and **fresh target revalidation after actual INSERT** all precede commit/ACK.
4. Historical replay still performs final owner/fence/row verification, but **never requires a surviving live parent**. The immutable receipt remains valid after later changes. No network, sync notifier, outbox, learning/reward or Research hook.

Queue watch is owner-scoped, pure and parses every immutable record. Order by original queued-ms then ID; ordinary clock reversal changes no identity or authority.

## UI and restart caller

Keep visible save action; use row overflow for Report plus existing Delete rather than a third crowded icon. Preserve edit/delete guards. New `widgets/word_report_sheet.dart` has form→review/back-to-edit→submitting→queued/uncertain-retry. Before first submit, user may edit/cancel; after submission starts, freeze the exact command and disable edits/re-ID, including lost ACK. A late ACK never restores old-owner UI. Copy: “บันทึกรายงานในเครื่องแล้ว ยังไม่ได้ส่ง”. No sent/resolved label.

Reuse VocabList's existing owner/dependency/lifecycle generations and owned-overlay guard (`vocab_list_screen.dart:64,577`), extending it locally for the report modal. The sheet separately observes its actual current route/visibility: another overlay, owner/null/error/done/ABA, disposal, lifecycle or dependency replacement invalidates pending delivery. Do not invent a global UI framework or treat parent isActive as proof the sheet is visible.

Add VocabList header overflow entry to `screens/word_reports_screen.dart`: read-only queued list/details after restart, showing historical version/reason/comment/source. No post-submit editing, auto-resubmit or practice of unresolved historical IDs. This is a concrete reported-items caller, not complete f22 composition.

## Owner/storage write sets and acceptance

**Root storage:** after SavedWords attestation, capture genuine schema19 via current AppDatabase/NativeDatabase sqlite_master to `test/fixtures/schema_v19.sql`, then separately reserve next free version (currently20) before DDL. Edit vocabulary_tables.dart, AppDatabase and normal generated source; proposed total37, new table empty, all36 old tables/pins/fences untouched.

**Data:** NEW vocabulary/domain/word_report.dart, data/drift_word_report_repository.dart, application/word_report_use_cases.dart. **UI/composition:** NEW sheet/screen above; edit VocabList, app_dependencies.dart/app_bootstrap.dart. Keep one canonical vocabulary/learning authority.

**Lifecycle:** owner_upgrade.dart inventory plus repository strict report-row preflight/final decode using shared parser. Only owner_id moves on ordinary merge; all other nine columns remain byte-identical, even when original words are deleted. No word remap, revision rewrite, signed-Research guard or rehome-outbox specification. Same-owner bind/replay unchanged; logout retains reports; restrictive guest rollback cannot erase one. Export all10 fields; reverse purge/core residual proof covers reports and preserves other-owner data.

New test files: `test/features/vocabulary/{word_reports_domain_test,word_report_use_cases_test,word_report_repository_test}.dart`; `test/support/word_report_harness.dart`; `test/screens/{word_report_sheet_test,word_reports_screen_test,vocab_list_word_reports_test}.dart`; `test/data/local/word_reports_migration_test.dart`; `test/features/identity/word_reports_owner_lifecycle_test.dart`. Extend existing inventory/snapshot/purge/coordinator/bootstrap fixtures without fake word FKs or weakened assertions.

Minimum acceptance: exact retry/restart/concurrent same ID, altered-ID-payload collision, stale revision/hash, parent change after INSERT rollback, owner/fence/ABA/overlay late ACK suppression, historical replay after missing parent, original pins through duplicate-word hard-delete merge, queue restart, exact owner export/purge/residual rejection and Thai/English320px/200%. Compare all learning/SRS/reward/Research/outbox tables unchanged around reporting. Retain SavedWords, vocabulary recreation, sync contract/policy controls; root owns serial integration/full analysis/Flutter/APK and final disposition.

## Execution board

- Accepted boundary plan source SHA256 `fc9fb6b81e1bdc936d802a60bff21406b852252dd1ccfc5f6dfe752c6d4e0401`; independent review `f79e614ca5e976b651770d2309b521e594ba3b63cabec769d490a569d544df42`.
- Genuine current19/36 capture passed before any version bump: actual sqlite_master DDL/indexes SHA256 `ea30538113a7837ecf3c896513c71cfe96fd1e62ab2340d051414e6cf87dbd92`, stored at `test/fixtures/schema_v19.sql`. Assessment37/opportunity19/session15/SavedWords7 columns and FK checks pass.
- A second capture ran the real v19 runtime with synthetic facts in every36 old tables, including saved+tombstone rows, pending quiz, Assessment pin19, pending presentation and the actual deletion fence. Immutable rows at `test/fixtures/populated_schema_v19.json`, canonical LF SHA256 `c6e03a6f30ed047c31ace45d9aff368da46d1a3a7f104d006c84178a30cdf605`. Initial fixture assumed two existing words; actual fixture had one. Added an explicit second synthetic word without weakening the two-row assertion; final capture passes.
- Capture tools remain in the D evidence root `word-reports-storage-prep`: source SHA256 b0b8eae86a72fec91f8c3ea0132878d86be0fd33796c2566fb8fc5e5ae8e7696 /878868a700b7b374a06faf94b9bc79a2880d120dc640ccf19b840ada51e12549; logs `word-reports-capture-schema-v19.log` and `word-reports-capture-populated-v19-final.log` each1PASS.
- Frozen API: domain `1bc455dd64c36dc381d5683c54413c71542a73e9239c5d6b6ce6d8557ea5cb08`, use cases `be5d631520514c106a49e0030876981b60ff06d252f44f38a77aceb3064f82c7`. Root and independent owner/UI readers accepted exact10-column/9-key representation. Draft workers write only disjoint D mirrors; root alone promotes C and serializes Flutter/generation/build.
- v20 is reserved in this documentation/fixture-only commit before any migration code; executable remains19/36 and v21+ is unreserved. Data/UI/owner/storage implementations, focused RED/GREEN, integration/full regression/analysis/APK and final review remain pending.
