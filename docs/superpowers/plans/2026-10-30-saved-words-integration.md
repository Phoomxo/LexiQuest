# Integrate local saved words

Grounded 2026-10-30 in `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`, `codex/remaining-system-readiness`, HEAD `d995ffc2040ba2019a09542be4db549ad92094eb`. Executable schema is **18 /35 tables**; ledger v19+ remains free. Predecessor: [verified Word Scramble checkpoint](../../field/2026-10-30-remaining-systems-wave15.md), Flutter3820/analysis0/CLI23/backend390/normal APK. This reviewed plan does not reserve a schema version or claim SavedWords implementation.

## Outcome and boundaries

Deliver the local **f20 Bookmark / Save** slice: save/unsave an owned word, survive restart, view saved words across categories, remove unavailable entries, and explicitly practice eligible saved words through the existing configured quiz. This contributes saved review to f22; it does not complete the whole Review Center.

Use VocabList's existing word rows and a Saved Words button beside its current import/source-practice controls. Add one small SavedWordsScreen with empty/loading/error/retry, saved/unavailable entries, removal and a practice button. Keep word editing/deletion intact. Read current vocabulary content, never copy spelling/meaning into bookmark storage. Deleting a word/category leaves its saved intent visible as unavailable; restoring the same ID restores availability. Explicitly unsaving while unavailable prevents that restoration from re-saving it.

Save/read/unsave create **zero** learning answers, SRS, reward/Quest/Streak/achievement, Research, outbox or network work. Do not attach the vocabulary sync notifier to this local-only writer. Starting/answering the existing source-practice quiz retains its existing canonical learning effects; add no reward rule or promise. No new SyncCollection, cloud path, wire field, Research flag or feature-catalog revision.

## State and exact command boundary

Candidate table `saved_words` / Drift `SavedWords`, seven columns:

| Column | Contract |
|---|---|
| owner_id | NOT NULL FK local_owners.id |
| word_id | NOT NULL FK vocabulary_words.id |
| is_saved | NOT NULL boolean |
| local_revision | NOT NULL positive integer, starts1 |
| first_saved_at_utc_ms | NOT NULL nonnegative integer, immutable after first save |
| updated_at_utc_ms | NOT NULL nonnegative integer |
| last_mutation_id | NOT NULL bounded, nonblank text |

Composite PK `(owner_id, word_id)`; both FKs NO ACTION/RESTRICT. No synthetic row ID, cloud fields, cascade, TTL, receipt table or extra index is needed. Default SQLite rowid remains available to the existing export sorter. Unsaved rows are retained tombstones, including export/purge. Absence is a typed virtual unsaved revision0; an unsave against absent revision0 is deliberately read-only: unchanged, no intent change, row or receipt. It cannot cancel a separately frozen concurrent expected0 save. Per-word UI pending serialization prevents presenting that no-op as cancellation; test this exact behavior rather than claiming all concurrent unsaves win.

New bounded types/port in `lib/features/vocabulary/domain/saved_words.dart`:

- Immutable stored/absent SavedWordState, owner-scoped SavedWordsSnapshot and current-content SavedWordItem (eligible or unavailable; no foreign-owner text).
- SavedWordMutation contains mutationId, expectedOwnerId, wordId, desiredIsSaved, expectedRevision and occurredAtUtc. SavedWordsUseCases.prepareSet captures one ID and UTC **millisecond** timestamp; pending UI retries reuse the same object.
- `watchOwner(expectedOwnerId)` is a pure joined read, creates no owner/bookmark, and tracks saved, vocabulary and category changes. LEFT JOIN word/category with owner equality in each ON predicate; retain unavailable saved rows without exposing any foreign-owner text. Do not place active-parent filters in WHERE and accidentally erase unavailable entries.
- `apply(command)` returns applied/replayed/unchanged/conflict with authoritative current state; typed unavailable/collision errors carry no private diagnostics.

DriftSavedWordsRepository requires the real same-database DriftOwnerWriteCoordinator; reject a foreign coordinator and ambient transaction. Use its top-level `writeForActiveOwner` before business writes. Validate the captured active owner/deletion fence, owned word and owned category. Saving requires both parents active; unsaving an existing own row remains allowed for soft-deleted parents. Validate IDs/revisions/timestamps at this boundary.

The coordinator currently checks owner/fence only before its callback (`drift_owner_write_coordinator.dart:45`); it does not supply a final check. After the actual awaited INSERT/UPDATE, and before returning any result from the same transaction, repeat a nested same-database `writeForActiveOwner` verification of owner/fence, owned parents and exact saved-row readback. Use the existing native writer's final-verification pattern (`drift_learning_repository.dart:_writeNativeExercise`), including replay/conflict/unchanged paths. Changed owner, new deletion fence, deleted/foreign parent on save, or mismatched row/revision/receipt must throw and roll back the entire mutation. No external IO/notifier occurs inside this transaction.

Inside the one transaction, read the current row, then:
1. Exact latest mutation ID + owner/word/desired state/expectedRevision+1/current update-ms match returns replay without another write. Same latest ID with altered payload is a collision.
2. Otherwise expectedRevision must equal current revision (0 for absence). A new valid command consumes exactly one revision, even when desired state matches; CAS UPDATE/INSERT and readback are atomic.
3. Stale/superseded commands return conflict without reissuing them against a fresh revision. A historical ID registry is unnecessary: each frozen old command retains its stale expected revision.

Keep first-save time through unsave/re-save. Ordinary local UTC is not a research clock: allow wall-clock reversal; do not require updatedAt >= firstSavedAt. UI disables a word's controls while its command is unresolved, labels pending/failure honestly, and never allocates a replacement identity just because ACK was lost.

## Owner lifecycle: required ordering

Current `DriftOwnerUpgradeRepository._mergeWords` physically deletes a duplicate guest word after remapping attempts/SRS/import references. Therefore generic owner movement alone is unsafe.

- Before mergedExisting business changes, validate all source/target saved rows' shape and owner→word→category relationships; deleted parents are valid unavailable intent. Keep existing deletion fences and signed-Research guards first.
- In each duplicate-word branch, merge the source bookmark into `(targetOwner, survivingTargetWord)` **before deleting the guest word**. If both states exist, use saved union; retain the minimum first-save timestamp; set revision to max(input revisions)+1 and a fresh internal `saved-merge:<generatedConflictId>` receipt. Remove the source row. This invalidates pending target CAS as well as source commands.
- After duplicate remapping, move remaining source saved rows with unchanged word IDs through one private saved-state helper, raising revision and replacing the receipt. Skip saved_words in `_moveOwnerRows`. Keep this inside the existing upgrade transaction; ordinary word-owner movement finishes before projection rebuilding/commit. Any malformed row/FK/CAS failure rolls back the entire merge, including vocabulary, rewards and outbox.
- Do not call the public active-owner setter from the merge helper. Preflight precedes category remapping; temporary cross-owner parent references created by that remap are internal transaction state, not foreign input to normalize or expose.
- No SavedWords entry in signed-source rejection or rehome-outbox specifications. Same-owner anonymous bind/alreadyBound preserves all seven fields exactly; replay of a completed merge changes nothing.
- Logout preserves prior-owner state. Guest rollback with any new saved row/tombstone must fail atomically through restrictive owner FK, preserving both owners and guest data; no cascade/delete workaround.

Insert `saved_words` into ownerUpgradeInventory **after vocabulary_words**. RequiredFullAccountExportScopes already spreads this inventory; snapshot SELECT * includes all seven fields. Reverse inventory purge removes saved rows before words/owners, and persistent deletion-core residual proof must reject even one leftover unsaved tombstone. Exercise both owners and preserve the other owner's bytes. Existing inventory fixtures assume various ID shapes: add an explicit composite-key seed, not a fake id column.

## Ordered write sets and verification

1. **Storage/lifecycle owner:** after ledger reservation and genuine current-v18 capture, edit `docs/database/schema_ledger.md`, `lib/data/local/tables/vocabulary_tables.dart`, `lib/data/local/app_database.dart` and normally generated `app_database.g.dart`. Candidate v19/36 is not reserved here. Register table, create it after owner/word in _createMissingTables, and cover from<19 using the existing missing-table convention. Use normal build_runner generation, never hand-edit generated Dart. Capture `test/fixtures/schema_v18.sql` from current AppDatabase+NativeDatabase sqlite_master **before bumping**, preserving historical fixtures. No backfill; new relation starts empty.
2. **Data/application owner:** NEW `lib/features/vocabulary/domain/saved_words.dart`, `data/drift_saved_words_repository.dart`, `application/saved_words_use_cases.dart`. NEW repository/use-case tests under `test/features/vocabulary/`.
3. **Shared owner writer:** edit `lib/features/identity/domain/owner_upgrade.dart` and `data/drift_owner_upgrade_repository.dart`; NEW `test/support/saved_word_fixture.dart` and `test/features/identity/saved_words_owner_lifecycle_test.dart`. Update populated inventory/export/purge/coordinator fixtures in existing owner/account-deletion tests without dropping assertions.
4. **Composition/UI owner:** edit `lib/runtime/app_dependencies.dart`, `app_bootstrap.dart`, `lib/screens/vocab_list_screen.dart`; NEW `lib/screens/saved_words_screen.dart`, `test/screens/saved_words_screen_test.dart`, `vocab_list_saved_words_test.dart`. Update bootstrap fixtures and offline_vocabulary_journey_test.dart. Keep SavedWords optional only when the local DB is unavailable; no fake production repository.
5. **Regression/attestation:** NEW `test/data/local/saved_words_migration_test.dart`; update latest-version/count assertions in current DB tests, preserving historical counts. One writer per shared file; serialize generator/Flutter checks and freeze source before final analysis/full suite/APK.

Practice caller must be exactly `QuizScreen(wordIds: capturedEligibleIds, selectionMode: QuizWordSelectionMode.sourcePractice, expectedOwnerId: capturedOwnerId, learning: canonicalLearning)`. Default supplied-ID mode is weakness, so it is not acceptable. Bind owner via existing ProgressUseCases.watchActiveOwnerId (null/error/done/ABA invalidates generation). Before dispatch and after each awaited read/mutation/navigation, verify mounted state, unchanged owner/generation and dependency/use-case identity, current visible route and resumed lifecycle. Discard stale delivery and stop further commands/navigation; never silently rebind an old screen to a new owner. Freeze eligible IDs before launch and pass the captured owner. QuizScreen owns accepted plan/launch retries and fresh word/category/content validation; do not add a learning writer or fallback deck. If no eligible IDs or content is unavailable, stay on the saved list with an honest message. A conflict requires an authoritative refresh and a new explicit user action, never an automatic CAS retry at the newer revision.

Acceptance: fresh schema/real FKs/constraints + populated genuine-v18→current/reopen preserve all35 old tables, quiz bytes, pending presentation and deletion intent; one-row retries/concurrency/stale save→unsave→save/clock reversal; changed/deleted/restored words; owner/fence/ABA and foreign joins; duplicate-word merge for saved/unsaved combinations before physical deletion, exact same-owner bind/replay, atomic rollback; exact export/two-owner purge/residual tombstone proof; actual offline save→restart→list→sourcePractice journey, Thai/English 320px/200%, accessible pending/retry/remove. Compare learning/reward/Research/outbox snapshots around bookmark-only commands.

Required boundary regressions intercept the real saved INSERT and UPDATE: change active owner, set persistent deletion intent, or change the owned parent immediately after SQL and before final verification; require whole-transaction rollback and unchanged saved/parent/owner snapshots. Separately prove absent revision0 unsave creates nothing and does not cancel a previously prepared expected0 save; duplicate latest-ID altered payload fails; stale/conflicting commands are never refreshed and resubmitted automatically. Delay read/save ACKs while switching owner/route/lifecycle/dependencies and prove no stale saved content, success UI or quiz launch is delivered.

Run new focused repository/use-case/migration/UI/lifecycle tests first, then existing vocabulary_recreate_test, source_practice_test, deleted_vocabulary_progress_test, weakness_clinic_screen_test, owner/export/delete suites, sync_contract_test and cloud_sync_policy_test. No new server rule is needed; prove the new relation never enters existing explicit sync collections. Final independent review + analysis/full Flutter/CLI/APK remains root-owned. Physical-device UAT stays separately unverified.

Independent boundary review accepted the seven-column/local-only/remap approach; its final-verification and absent-no-op refinements are incorporated here. Review source: `bookmark-boundary-review.md` (SHA256 `BFE956B57C0BDA4BC73786273DC42FFE299D8C9ADB880A0332D16B91912AF56E`). This is a reviewed plan, not executed verification evidence.

## Execution board

- Predecessor attested/pushed at0461d695; application source d995ffc2 remains the verified APK.
- Genuine v18 capture passed on the current AppDatabase before any version bump:35 tables, Assessment37/opportunity19/session15 columns. SQL SHA2569cff95c607a68bf6960ec451148280526bf902e3249d2767b7ebee2925c221c1; no SavedWords table exists yet.
- Ledger now reserves v19 for the seven-column relation, with mutation IDs bounded to256 UTF-8 bytes. Executable schema is still18/35; v20+ is unreserved. Migration implementation/generation and feature verification follow this reservation.
