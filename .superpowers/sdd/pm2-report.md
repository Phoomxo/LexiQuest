# PM2 implementation handoff — 2026-09-05

## State and ownership

- Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`.
- PM1 accepted source base `cf94aecf`; current HEAD `e7ee85ad230fd0373b409fe7ed952eba33351256` contains root's subsequent documentation update. Root staged PM2 source/tests for review after final verification; this worker made no index/commit changes.
- PM2 implementation is ready for independent acceptance review. No navigation activation, deployment, package resolution, generation, full suite, build, migration, or other worktree changes.
- Flutter/Dart ownership RELEASED. All task-owned commands finished; no running process remains.
- Root-owned documentation and pre-existing generated registrant line-ending changes were preserved. This worker wrote only its preflight/report plus the source/test set below.

## Delivered

1. Pure immutable `PairMatchingEngine`: typed select/reveal commands, typed tiles/attempt roles, state + command -> state + optional attempt effect. No Flutter/repository/clock imports. Selection/deselection/reselection is neutral; either tap order and EN→TH/TH→EN resolve the prompt canonical word correctly. Correct acknowledgement increments matched set once; mismatch never changes progress. First-opportunity history is session evidence history, not presentation state.
2. Commands bind owner, learning session, round and expected operation revision. Operation IDs include their expected revision, preventing reuse at a newer revision. Exact last/evidence-operation duplicates return no transition; changed retained payloads reject; older neutral callbacks reject as stale. All retries therefore produce no second attempt. No unbounded neutral-operation log is stored.
3. Durable support acquisition revision per word preserves chronological classification: a reveal cannot retroactively downgrade previous recognition, and later guided attempts cannot be relabeled independent. Attempts preserve immutable roles and resolution fingerprints. Narration/visible text is modality, not a `PairRevealMapping` command.
4. Real `PairMatchingSessionCoordinator`: `restore`, `dispatch`, `retryPending`, `flush`, `dispose`; latest exact authenticated recovery after accepted start reconciliation. It uses `CurrentActivityEvidenceAdapter.captureMatching`, canonical lexical prompt artifact identity, `freezeForRecovery`, frozen restoration and canonical `LearningUseCases` writes. No arbitrary EvidenceContext construction and no parallel answer/reward authority.
5. Immutable pending checkpoint -> canonical answer -> committed-ledger clear boundary. Pending occurrence IDs/timestamps/actor/evidence/event contexts are frozen before the first durable write. Uncertain appends retain their exact revision/time/state; retry cannot replace them. Before/after acknowledgement-loss tests use real SQLite persistence. Clear failure retains the committed pending operation until recovery safely clears it.
6. Typed M12 `MatchingModeAdapter.preparePairSession` exposes existing generic admitted/recovery operation callbacks and operation acceptance. The coordinator checks owner/disposal before admission and acceptance inside the granted lease and around awaits; a revoked lease cannot produce an answer. Lease release after successful completion is not mistaken for an operation failure. Actual PM6 host/UI binding remains downstream.
7. Shared pure v6 codec. PM1 initial bytes stay **exactly unchanged**; initial state delegates to this codec. New snapshots use `schemaVersion:6, codecVersion:1`, full plan/start envelope, reducer state, ordered canonical evidence IDs and optional frozen occurrence. Strict decoding rejects shape/version/pins/ledger/pending/support corruption. Durable attempt lexical references use indexes into the immutable plan to avoid repeating maximum-length IDs; the reducer still exposes canonical IDs.
8. Neutral `LearningActivityRecoveryLimits` owns the existing 64 checkpoints, 128 attempts and 65,536 UTF-8 byte limits. Pair's separate admission policy consumes them and reserves three terminal receipts plus reachable Continue untimed and remaining answers. Correct resolutions reclaim one remaining pair in admission arithmetic, so reserved completion capacity stays usable. A real six-pair sequence of 23 mismatches followed by six correct pairs completes at revision 59 with exactly 29 AnswerAttempts.
9. Named repository v6 validation: `_validatePinnedPairCheckpoint`, `_validatePinnedPairAnswer`, `_pinnedPairOccurrence`, `_requireActivePairOwner`. Enforces exact initial empty state/app/build/start/session identity, immutable plan/pending/support/committed lineage, canonical attempt correspondence, and pinned recognition/guided provenance/context. Valid deleted pinned words remain answerable through their durable reservation. Owner checks before and after answer/checkpoint writes roll back SQL-trigger races.
10. Only the authorized Pair atomic path can create the first v6 checkpoint. Public generic start-with-checkpoint, exact-pinned start and generic session + first-v6 append cannot bypass capability. A private admission parameter is propagated only from the capability-validated Pair start; no public bypass flag. Already accepted exact starts still reconcile original immutable start events after progress/gate-off.

## Source/test write set

New production files:

- `lib/features/learning/domain/learning_activity_recovery_limits.dart` (root-authorized neutral policy extension)
- `lib/features/learning/pair_matching/domain/pair_matching_engine.dart`
- `lib/features/learning/pair_matching/domain/pair_matching_checkpoint_budget.dart`
- `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart`
- `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart`

Narrow production edits:

- `lib/features/learning/pair_matching/application/pair_matching_atomic_start.dart`
- `lib/features/learning/application/matching_mode_adapter.dart` (typed prepare/lifecycle seam; legacy implementation unchanged)
- `lib/features/learning/data/drift_learning_repository.dart`

Tests:

- New `test/features/learning/pair_matching/pair_matching_engine_test.dart`
- New `test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart`
- New `test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart`
- New `test/features/learning/pair_matching/pair_matching_idempotency_test.dart`
- Modified `test/features/learning/pair_matching/pair_matching_atomic_start_test.dart`: initial/capability rejection tests; the prior advanced-checkpoint retry fixture now advances through a valid reducer/codec snapshot instead of mutating the old minimal initial shape's operationRevision alone. Its reconciliation assertion remains intact.

No changes to CurrentActivityEvidenceAdapter, frozen evidence contracts, schema/tables, generic configuration, Today, History, identity upgrade or UI screens.

## RED / correction evidence

All Flutter commands used `--no-pub`; commands below ran in this exact worktree. Most initial focused commands used `--reporter compact`, later ones used `--reporter expanded`.

- `flutter test --no-pub test/features/learning/pair_matching/pair_matching_engine_test.dart`: compilation RED for planned missing reducer APIs, then 5 initial tests green. Added session-binding RED for missing command field; after adding field, historical wrong→reveal restore produced real `FormatException` RED. Added support acquisition chronology and negative relabel test, which initially accepted forged independent role; now rejects it without changing past evidence.
- `flutter test --no-pub test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart`: missing codec/budget API RED, then green. Maximum lexical strings + 29-attempt ledger later measured **65,546 bytes**, genuinely failing the 64 KiB assertion after adding resolution fingerprints. Compact plan-index references resolved the size failure; canonical round-trip and <65,536-byte assertion pass. No ceilings were raised.
- `flutter test --no-pub test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart test/features/learning/pair_matching/pair_matching_idempotency_test.dart`: missing coordinator API RED, then 11 real-Drift tests green. Added deleted-v6/owner-at-answer/downgrade tests: all three failed before narrow repository validation and passed after.
- `flutter test --no-pub test/features/learning/pair_matching/pair_matching_atomic_start_test.dart --plain-name 'Pair initial rejects' --reporter expanded`: RED because progressed codec revision 1 was admitted. Strict initial/app/build checks fixed it.
- `flutter test --no-pub test/features/learning/pair_matching/pair_matching_atomic_start_test.dart --plain-name 'generic learning start' --reporter expanded`: RED because generic start admitted Pair v6. Private authorized admission fixed all three generic paths. One exploratory shell call followed the test with a source read, so its shell exit was 0 even though test output was explicitly failing; no passing claim relied on that exit.
- `flutter test --no-pub test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart --plain-name 'capacity boundary' --reporter expanded`: RED at the correct completion after capacity reservation. Outcome-aware remaining-pair arithmetic fixed it; real 23 wrong + 6 correct sequence passes.
- `flutter test --no-pub test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart --plain-name 'owner mutation at checkpoint' --reporter expanded`: RED because an AFTER INSERT owner-change trigger left two checkpoint rows. Post-write owner check now rolls back the whole append and trigger mutation, leaving exactly the original checkpoint and active owner.
- Broad impacted run initially had 319 passing/1 failing: legacy `deleted word rejects a future matching checkpoint schema` expected repository `StateError`, but strict decoder surfaced `FormatException`. Added repository error translation and reran that exact legacy test green; assertion was not weakened.
- `flutter test --no-pub test/features/learning/pair_matching/pair_matching_idempotency_test.dart --plain-name 'host admission' --reporter expanded`: missing callback API RED, then a real lease-release RED (acceptance is true only while lease held). Final implementation checks acceptance inside the lease and owner/disposal after return; revoked callbacks and recovery pass.
- First focused analyzer identified new unbraced statements, one redundant non-null assertion and one initializing-formal lint; corrected them. A lint-patch preparation read was initially truncated and validation stopped before any write; a complete bounded read corrected that operation. Final analyzer has no issues.

## Final verification

1. Canonical impacted run **320 passed, exit 0** before the final lifecycle-callback-only addition:

```text
flutter test --no-pub test/features/learning/pair_matching test/features/learning/matching_mode_adapter_test.dart test/features/learning/current_activity_evidence_test.dart test/features/learning/unified_lesson_controller_test.dart test/features/learning/drift_learning_repository_test.dart test/features/learning/learning_use_cases_test.dart test/scenarios/current_activity_evidence_bootstrap_test.dart test/features/learning/assessment_evidence_isolation_test.dart test/architecture/pair_matching_f10_boundary_test.dart --reporter expanded
```

2. After final lifecycle seam/test edits, reran its affected subset: **245 passed, exit 0**. This includes all current Pair tests plus legacy Matching and Unified Lesson regressions:

```text
flutter test --no-pub test/features/learning/pair_matching test/features/learning/matching_mode_adapter_test.dart test/features/learning/unified_lesson_controller_test.dart --reporter expanded
```

3. Final focused static analysis: **no issues, exit 0**:

```text
dart analyze lib/features/learning/pair_matching lib/features/learning/domain/learning_activity_recovery_limits.dart lib/features/learning/application/matching_mode_adapter.dart lib/features/learning/data/drift_learning_repository.dart test/features/learning/pair_matching
```

4. Touched files formatted. Final narrow production diff and coordinator read inspected; `git diff --check` reports no whitespace errors. Existing LF/CRLF warnings on generated registrants and touched Windows checkout files are recorded, not described as pristine output.
5. Tests exercise actual AnswerAttempts/checkpoint/event rows, canonical classifications, disk database close/reopen with a generator that throws if asked to mint another evidence ID, exact pending/answer/clear faults before and after commit, duplicate payload/disposal, SQL owner races and reserved completion capacity. Pure model tests alone are not used as proof of persistence.

## Explicit remaining boundaries

- PM3 owns delayed repair scheduling/tickets, bounded repair opportunities and Review deferral. `delayedRepair` is a reserved typed role and not emitted/accepted as a completed PM2 feature. PM2 can represent first opportunity, independent retry and guided mapping completion; PM3 must extend the codec and reducer deliberately.
- PM4 owns active timer, restart/new-round semantics and exact terminal dispatch. Round 0 only is currently validated; no fake restart/history reset. Three terminal receipts and Continue untimed are reserved, not implemented or claimed tested as UI actions. PM4 must extend this same budget/codec for its full worst-allowed combined sequence.
- PM5 Practice Replay remains disabled; no recreational classification broadening or projection isolation claim.
- PM6 must connect the actual host/UI to `preparePairSession`, admitted/recovery leases and semantic mapping reveal commands. Narration must not dispatch reveal; all shell-owned answer-revealing hint use must dispatch/persist support before the subsequent answer. Current tests prove the real canonical coordinator and typed lease seam, not a routed playable screen.
- Process death before any pending checkpoint commits restores the last acknowledged snapshot; no canonical attempt existed yet. In-process pre-write failure retains exact capture for retry. Durable pending snapshots survive process reconstruction and reconcile exact answer identity.
- Neutral gestures coalesce in memory until an evidence/reveal/explicit flush boundary. Superseded neutral operation IDs reject as stale; they do not create an ever-growing checkpoint log. Conflicting operations during uncertain persistence reject until explicit retry.
- PM8 **real owner upgrade dependency remains unresolved**: `drift_owner_upgrade_repository.dart::_fenceMatchingSessionsForCollidingWord` (~822–899 at inspected source) reads legacy `state['pairs']`; v6 uses pinned plan/compact state. Noncollision rehome also changes canonical owner while the immutable Pair plan remains source-owner-bound. PM2 intentionally does not rewrite immutable plan/actor, auto-retire pending learning or claim guest/account merge compatibility. Root agreed PM8 should prefer authenticated rehome/source-actor lineage using existing event validation, preserve pending evidence exactly, and consider bounded close-before-transfer only if needed. Identity code was not changed here.
- v1–v5 writer/reader behavior stays intact; v6 admission is internal/default-off. Database remains v24/48 tables and catalog remains 8/44. No production research/enrollment/upload or efficacy claim.

Next executable step: root independent PM2 spec/quality review on this source snapshot, then approved PM3 work. Full integration/release suites, physical-device/UAT and deployment remain root/later-checkpoint work.

## Independent review correction followup (2026-09-05)

The first review found a real P1 byte-capacity defect and two minor issues. This section supersedes the earlier maximum-string claim: the previous 256-character evidence-ID fixture exceeded the canonical 197-rune source-ID bound and did not establish Unicode completion safety.

### Final changes

- Progressed v6 checkpoints now write codec version 2: one full immutable plan, a compact start envelope, and plan-index references for selected/matched/support identities as well as attempts. Decode reconstructs the exact original public startOperation serialization. PM1 initial checkpoint bytes remain unchanged; codec version 1 remains readable. Strict canonical compact-engine validation rejects ignored extra fields and noncanonical index aliases.
- `PairMatchingCheckpointCodec.requireCompletionCapacity` projects the existing full ledger plus every remaining mandatory correct answer, the maximum supported pending frozen occurrence, and 1024 bytes for future terminal metadata. No evidence is truncated. Admission applies before state publication or evidence-ID capture; optional mismatches can be denied earlier while correct completion remains reachable. Initial atomic start performs this preflight after exact prior-operation reconciliation/capability validation and before any session INSERT, with repository validation repeating it for the initial checkpoint.
- The pending occurrence bound covers ten research identifier occurrences (five in EvidenceContext and five in LearningEventContext), each at 256 runes and the largest six-byte JSON encoding; canonical source IDs reserve 197 runes. Pinned owner/actor/session and maximum word identity are measured exactly. Fixed schema keys, known declarations, hashes, timestamps, booleans and 64-bit numeric values reserve another 4096 bytes. CaptureMatching supplies no assessment/contrastive payload. The actual frozen envelope must fit this supported bound before admission; future schema expansion must update the bound explicitly. This is conservative, not a universal entitlement to 23 wrong attempts. PM3 repair and PM4 actual timer/terminal schema still must extend the same projection and verify their combined sequence.
- Synchronous capture exceptions leave the original neutral selection/revision unchanged. An asynchronous freeze failure retains the exact captured evidence object and candidate privately, exposes the original neutral state, and retries without a new evidence ID. An unsupported captured-only metadata envelope is rejected before persistence and cleared; already durable pending evidence is never discarded.
- Engine attempt ceiling now references the neutral LearningActivityRecoveryLimits policy.

Exact followup source write set: `drift_learning_repository.dart`, `pair_matching_session_coordinator.dart`, `pair_matching_checkpoint_codec.dart`, `pair_matching_engine.dart`; tests: `pair_matching_checkpoint_codec_test.dart`, `pair_matching_evidence_contract_test.dart`, `pair_matching_idempotency_test.dart`; this report. No index/commit mutation. Root's previously staged reviewbase is preserved; followup remains unstaged for root restaging. Generated registrant line-ending status was preserved.

### RED and GREEN evidence

- Real Drift permitted six-pair fixture with Thai 256-character word IDs, long English spelling/Thai meaning, all reasons except reported, maximum ASCII plan/start metadata and valid 197-character source IDs reproduced the original failure: pending append threw `Invalid Pair checkpoint`. Compact codec alone then permitted the original 29-attempt sequence. The final test adds conservative admission and proves an optional wrong answer is denied before state, evidence-ID count or checkpoint-write count changes, followed by all six correct completions. It reconstructs after an answer lost ACK and retries a clear-checkpoint lost ACK; every attempted pending/clear snapshot remains <=65536 bytes and canonical attempt count equals admitted wrong answers plus six.
- The pure original review fixture now verifies 29 retained attempts with Thai word IDs and valid 197-character source IDs fit the compact writer, and decoding recovers the exact original public start identity.
- A second permitted fixture uses escaped owner characters, long Thai metadata, English spelling and Thai meanings: its initial checkpoint fits 65536 bytes but mandatory reserve exceeds it. A real SQLite BEFORE INSERT trigger proves rejection occurs before session insertion, with no session/events written. Fixture development first hit the existing visible-language policy (Thai spelling), then corrected the synthetic spelling to valid English; the policy was preserved.
- Synchronous ID-provider failure initially exposed an engine pending operation despite no captured evidence (RED). Final test confirms neutral state and a successful new capture after provider recovery. Separate freeze-provider outage test proves exact retained ID and successful canonical retry. Its initial test compile used the candidate-only sourceEvidenceId getter on RecordAnswerCommand; corrected to canonical command.id, then passed.
- Final compact-decoder inspection added an extra selected-field negative test: RED returned a snapshot instead of rejecting. Canonical compact-engine equality now rejects it (GREEN).

Verification commands/results:

1. Full **impacted subsystem selection, 325 passed, exit 0**, after byte/capture/freeze/start fixes (before the final extra-field rejection only):

```text
flutter test --no-pub test/features/learning/pair_matching test/features/learning/matching_mode_adapter_test.dart test/features/learning/current_activity_evidence_test.dart test/features/learning/unified_lesson_controller_test.dart test/features/learning/drift_learning_repository_test.dart test/features/learning/learning_use_cases_test.dart test/scenarios/current_activity_evidence_bootstrap_test.dart test/features/learning/assessment_evidence_isolation_test.dart test/architecture/pair_matching_f10_boundary_test.dart --reporter expanded
```

2. Final decoder/repository/legacy affected selection, **155 passed, exit 0**, on the final source:

```text
flutter test --no-pub test/features/learning/pair_matching test/features/learning/matching_mode_adapter_test.dart test/features/learning/drift_learning_repository_test.dart --reporter expanded
```

3. Final focused analysis **No issues found, exit 0** using the same analyze command recorded above. Touched files formatted. `git diff --check` exit 0, no whitespace errors; LF/CRLF warnings remain recorded. No full repository suite/build/pub/generation/security scan/navigation activation was performed.

Tooling is released to root; no running Flutter/Dart process remains. Next executable step: root restage the seven changed source/test files and independently re-review this delta. PM3–PM8 deferred boundaries above remain unchanged; this followup does not claim actual host/UI, terminal flows or owner-upgrade integration completion.
