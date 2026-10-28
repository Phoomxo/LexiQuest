# PM3 read-only implementation preflight

Date: 2026-09-05. Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch verified `codex/pair-matching-pm0-pm8`.

Preparation only. PM2 is still the sole source/tooling writer while its P1 UTF-8 checkpoint liveness correction is reviewed. This preflight does not treat the observed PM2 engine/codec/coordinator as a stable accepted interface. No Flutter/Dart command, source edit, UI activation, schema change, web access, git mutation or new authority was performed. Only this document is written.

## Authority inspected

- `AGENTS.md`, `.superpowers/sdd/pm3-brief.md`, `pm3-integration-brief.md`, `progress.md`, PM2 report/review excerpts.
- Approved `docs/adventure-motivation-mode/00b-architecture-decision-records.md` ADR-011; `02-srs.md` FR-116–119; `03-sds.md` §§15.2–15.5; `06-test-plan-and-test-cases.md` PMT-017–024.
- Existing Pair reducer, coordinator classification and recovery sites; codec frozen hint validation; repository Pair checkpoint/answer validation sites. These observations must be refreshed after PM2 acceptance.
- Actual `DriftReviewCenterReader`, `ReviewCenterUseCases`, `ReviewQueueItem` provenance; real Drift Review integration fixtures and Pair evidence harness; canonical hint classification type.

## Bounded policy and reducer design

Create a pure `pair_repair_policy.dart` with immutable ticket/state decisions. A ticket binds canonical prompt word, original incorrect operation/attempt ordinal and committed source identity, due distinct-success ordinal, and waiting/available/completed/guided-required/deferred status. Keep one ticket per canonical word per Learning Session, including after a future round restart; PM4 must preserve this ledger. Stable order is due ordinal, original attempt ordinal, canonical word ID. The evidence ID remains supplied by the committed coordinator ledger, never fabricated by the policy.

Only acknowledged correct resolutions of distinct *other* canonical pairs advance spacing, once per pair. Compact delay is 2 and standard delay is 3. Wrong answers, target distractors, same-pair repetitions, pending evidence, same-side taps/deselect, support/audio/animation/time and technical replay do not advance it. Derive counts from the immutable committed ledger or validate stored counters against it; do not trust an arbitrary client counter. The first wrong creates the sole ticket; wrong scheduled repair transitions to explicit guided-required/deferred without another ticket. Waiting repair targets must be rejected by reducer selection until due, not merely visually hidden. A due ticket is available at exactly its interval, with deterministic presentation order; inspecting or retrying persistence must not consume it.

Tail feasibility uses the remaining distinct other resolvable pairs, not total tap/attempt capacity. If the interval cannot be met, expose explicit corrective mapping and a guided-completion opportunity, then defer future independent retry to Review. Do not silently manufacture a correct AnswerAttempt on a wrong answer, auto-increment matched progress merely for deferral, or insert filler/bridge pairs. Successful user guided completion is genuine guided evidence and increments matched progress once. Any implementation allowing repeated guided failures must still terminate through a bounded explicit guided completion action rather than rebuilding a queue; define and test that action before coding it. Policy outputs should make the waiting/due/guided-required transition visible to the later host without activating PM6 UI now.

Repair timing and evidence support are independent axes. Preserve `delayedRepair` role/ticket identity even after mapping; one shared pure support-at-attempt classifier uses canonical prompt ID and `supportAtRevision` strictly before the attempted operation revision. Mapping/semantic reveal changes subsequent attempts to `guidedPractice` with hint level 1; earlier attempts retain their historical class. Neutral visible pronunciation/narration does not create a support marker. Independent self-correction before reveal remains recognition while the first-opportunity wrong remains in history. A future round must not erase historical support/repair facts.

All classification paths must consume the same classifier: reducer ledger validation, coordinator dispatch/frozen validation/recovery comparison, strict codec frozen hint checks, and repository checkpoint/answer validation. Do not change frozen EvidenceContext or EventEnvelopeV2 contracts. Search all `guidedCompletion` comparisons after PM2 acceptance and again after implementation to catch duplicated assumptions. A role-only classifier would incorrectly grant recognition to supported delayed repair.

## Canonical Review handoff

Add a typed read-only handoff near Review application boundary. Input binds owner, session, canonical word/pin and committed incorrect answer ID from Pair evidence receipts. Validate actual committed source association, then call existing canonical Review composition without a limit that could exclude the requested item. Confirm the resulting word/revision has `ReviewReasonProvenance.incorrect(sourceId: actualAnswerId)` and return that existing item/need, or an explicit unavailable result when source/content authority is missing. Reject cross-owner/session/word substitutions and fabricated or pending IDs. A valid other incorrect answer in the same item is not sufficient to authenticate the requested source.

The actual reader already excludes assessment/recreational incorrect evidence, validates source events and lexical artifact revision, and merges sources by `(wordId, current revision)`. It does not own a new durable queue and does not implement per-handoff resolution state. Thus “one unresolved need” means one canonical content item with legitimate provenance retained; it does not mean deleting other real wrong attempts. Repeating a handoff or restoring its source must perform zero writes. Never insert synthetic wrong answers, write SRS directly, or mutate Review history to satisfy counts. Optional reader exposure can fail closed without blocking unrelated learning completion.

## Audio/support boundary

Use a pure capability decision for locally available pronunciation versus functional text/IPA fallback, with typed availability/privacy reason codes and no raw lexical text in diagnostics. PM3 introduces no remote TTS request path. A denied/private/offline/missing-audio decision must preserve all board commands and be neutral in the support classifier. Actual widget/native playback/TalkBack QA remains PM6; PM3 can verify the typed decision and evidence invariance. Reuse the established `HintEvidenceClassification` result shape rather than creating another learning authority.

## Proposed exclusive PM3 write set after root dispatch

New files (first confirm no equivalent):

- `lib/features/learning/pair_matching/domain/pair_repair_policy.dart`
- `lib/features/learning/pair_matching/domain/pair_support_policy.dart` (shared support classifier and neutral capability policy)
- `lib/features/review/application/pair_review_deferral.dart` (typed read-only handoff)
- `test/features/learning/pair_matching/pair_repair_policy_test.dart`
- `test/features/learning/pair_matching/pair_support_classification_test.dart`
- `test/features/learning/pair_matching/pair_review_deferral_test.dart`

Existing files, only after PM2 releases ownership:

- `lib/features/learning/pair_matching/domain/pair_matching_engine.dart`
- `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart`
- `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart`
- `lib/features/learning/pair_matching/domain/pair_matching_checkpoint_budget.dart`
- `lib/features/learning/data/drift_learning_repository.dart` (Pair-only classification/validation blocks; root PM8 owner-rehome work must remain read-only or transfer ownership explicitly)
- Existing Pair engine, checkpoint, evidence contract and idempotency tests as needed for regression adaptation, preserving assertions for PM2 invariants.

No change to Review reader is expected; if its public interface proves insufficient, report the exact minimal read-only adapter need before expanding shared files. Root owns status/RTM/acceptance documentation. No migrations, database generated code, feature catalog, routes, activation, rewards, SRS authority or frozen evidence contracts.

## RED/GREEN and acceptance evidence plan

1. Pure failing fixtures PMT-017/018: exact 2/3 distinct other acknowledged successes; unavailable at N-1, available at N; duplicates/pending/non-answer cannot advance. PMT-019: simultaneous due tickets sorted by all three keys, no loss/duplicates; input list order cannot affect results.
2. Reducer PMT-020/021: all-correct, early wrong, every pair wrong, concurrent tickets, final-pair wrong and repeated repair wrong reach a finite explicit guided tail without padding or recursive tickets. Check genuine guided progress exactly once, original wrong preserved, first-attempt flags stable, and waiting target rejected independent of tap order.
3. Actual coordinator/Drift evidence tests in both EN→TH and TH→EN and both tap orders: distractor receives no wrong evidence; normal unsupplied repair and self-correction remain recognition; mapping then delayed repair remains role=delayedRepair but emits guidedPractice; restore and frozen evidence use same classification. Neutral narration remains recognition. Tampering support revision/role/frozen hint is rejected.
4. Actual `DriftReviewCenterReader` integration through the new handoff after coordinator commits: repeated calls and lost-ack/restore produce one word item containing original actual answer ID. Two legitimate incorrect attempts preserve both provenance entries in that same item. Wrong owner/session/word/revision, deleted/unpublished content, forged event/ID and uncommitted source fail closed. Assert no new attempts/events/outbox rows from the handoff itself.
5. Seed due SRS and record table values before Pair wrong/guided completion and handoff. Assert matching does not close or reschedule due state. Run existing `test/features/review/review_center_reader_test.dart`, `test/features/learning/srs_policy_test.dart`, `test/services/srs_service_test.dart`, `test/services/weakness_clinic_service_test.dart`, owner and Pair evidence regressions. Check actual Weakness safety-floor behavior using committed evidence; do not invent zero changes where canonical incorrect recognition legitimately contributes.
6. PMT-024 pure fallback and payload inspection: missing/offline/private denial leaves board completeable, no remote adapter is invoked, and raw words/meanings/IPA are absent from diagnostics and frozen evidence payloads. Host/device behavior remains explicitly untested until PM6.
7. Extend accepted PM2 strict compact codec and budget with maximum tickets plus the largest permitted Unicode IDs, full pending frozen evidence, operation ledger, eventual mandatory guided answers and terminal reserve. Measure UTF-8, not string length. Keep <=64 KiB, no lost attempts and no raised ceilings; test pre-admission rejection, pending/acknowledged snapshots, lost acknowledgements and exact recovery. PM1 initial bytes and valid legacy 1–5 stay unchanged. PM4 combined timer reserve must be coordinated, not claimed accepted here.
8. After source is stable, serialized focused tests, touched-subsystem regressions, targeted analysis and final diff inspection. Record exact source/test outcomes in PM3 report. Root schedules repository-wide integration checks with all writers paused. No Flutter/Dart tooling during this preparation.

## Handoff state

Root approved guided-tail interpretation: enter revealed-pair completion state after tail/failed repair, with no automatic match on the wrong command. A separate learner confirmation binds exact shown canonical pair, support revision and normal owner/session/operation identity; it emits one correct guidedPractice answer. No further distractor guessing loop. First wrong and canonical Review need remain. PM6 will expose this as guided confirmation, not an independent success claim.

Changed file: only `.superpowers/sdd/pm3-preflight.md`. Read-only commands succeeded; no task-owned running process. No test execution or PM3 acceptance claimed. Next executable step: root accepts final PM2 correction/review, provides sole PM3 write/tooling ownership, then PM3 refreshes the accepted codec and repository interfaces and starts focused RED fixtures. Wait for that dispatch.
