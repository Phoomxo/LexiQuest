# PM2 implementation preflight

2026-09-05. Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`. Read-only source inspection; this report is the only write. No Flutter/Dart commands, production edits, branches, commits, or other worktrees. PM1 final review/report is still pending; implementation awaits root followup, without another product-design approval.

## Inspected contracts

Read AGENTS.md, PM2 brief/integration notes, PM4 checkpoint audit, current engineering status, SDS 15.4–15.7, TC-PMT-013–016, current Pair plan/launch/atomic-start, MatchingModeAdapter, CurrentActivityEvidenceAdapter, LearningUseCases, Drift repository and real-Drift atomic-start tests. Existing v1–v5 Matching behavior remains intact; v6 is a separate typed reader/writer. Database v24/48 tables and frozen EvidenceContext/EventEnvelopeV2 are unchanged. Practice Replay remains disabled.

PM1's initial checkpoint already carries full plan and serialized start operation but duplicates its shape in atomic-start. Start reconciliation may succeed after subsequent progress or terminal completion. Coordinator initialization must load latest authenticated exact recovery after start, never initialize blindly from `operation.initialCheckpoint`. Root is coordinating a PM1 regression for reconciliation after gate-off.

## Proposed interfaces

- `PairMatchingEngine.reduce(PairMatchingState state, PairMatchingCommand command) -> PairMatchingTransition`: pure domain code, immutable state/effects; no Flutter, repository, or clock imports. Command carries bounded operation ID, owner/session binding, expected round and operation revision; time/duration are supplied values. State contains pinned plan, round ordinal, selected typed tile (prompt/target + canonical word ID), matched IDs, operation revision, durable attempt/first-opportunity ledger, semantic-support history, and pending resolution. Reject same ID with changed payload; identical retry returns the same logical result. Same-side selection/deselection/reselection is neutral; cross-side resolution normalizes prompt identity independent of tap order and EN/TH direction.
- Typed effects: `PairAttemptRequested` holds prompt/target IDs, correctness, role, and operation identity; neutral taps emit no evidence. `PairAttemptRole` distinguishes first opportunity, later independent answer, delayed repair, and guided completion without claiming PM3 repair scheduling exists. First opportunity is session-wide, not reset by round lineage. `PairAttemptCommitted` acknowledges a reserved pending operation only for the exact round/revision; matched count grows once for correct commit and never changes on mismatch. Duplicate/no-op handling must precede stale-revision rejection for exact retried IDs.
- `PairMatchingSessionCoordinator.restore(startOperation, learning, evidence, ownerProvider, callbacks)` loads exact recovery and authenticates plan/start/session/attempt bindings. `dispatch(command)` serializes admitted commands; `retryPending()` reuses captured occurrence/checkpoint bytes; `flush()` persists a coalesced acknowledged snapshot. Retain an in-flight immutable append and one folded successor, never rewrite an attempted checkpoint. Fence owner/lifecycle epoch before and after async awaits. Expose immutable state; host/UI receives no repository write authority.
- Capture uses existing `captureMatching`, canonical `LexicalPromptArtifactResolver` content identity, and a shell-owned `HintEvidenceClassification`. Use `freezeForRecovery()` before pending checkpoint; persist its frozen identity/contexts; then canonical `record`/`retry`; then clear pending with committed reducer state. Recover via validated frozen occurrence/typed matching restore, not hand-built EvidenceContext. Existing `freezeForRecovery`/`FrozenPendingCurrentActivityEvidence.fromJson` already supply a reusable serializer.
- `PairMatchingCheckpointCodec.initialState(plan, startOperationBytes)`, `encode(snapshot)`, and `decode(state)` own one strict v6 shape. Codec remains pure with JSON payload fields rather than importing application adapters. Decode validates exact keys, plan fingerprint, all tile/ledger references, operation payload consistency, and bounded serialized size. Coordinator validates frozen evidence against codec pending operation and real recovered AnswerAttempts. Initial empty PM1 shape must have an explicit compatible decode path if evolved; atomic-start uses shared initial encoder.
- `PairMatchingCheckpointBudget` owns admission arithmetic for 64 revisions, 128 recovered attempts and 65,536 UTF-8 bytes; reserve three terminal revisions, reachable Continue-untimed revision, pending clear, and remaining allowed answer sequence. No per-tap/tick checkpoint. PM4 extends the same policy for timer/restart rather than introducing another limit.

## Exact planned write set

Create:

- `lib/features/learning/pair_matching/domain/pair_matching_engine.dart`
- `lib/features/learning/pair_matching/domain/pair_matching_checkpoint_budget.dart`
- `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart`
- `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart`
- `test/features/learning/pair_matching/pair_matching_engine_test.dart`
- `test/features/learning/pair_matching/pair_matching_idempotency_test.dart`
- `test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart`
- `test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart`
- `.superpowers/sdd/pm2-report.md`

Narrow modifications:

- `lib/features/learning/pair_matching/application/pair_matching_atomic_start.dart`: delegate initial state to shared codec, retain operation public API/serialization.
- `lib/features/learning/application/matching_mode_adapter.dart`: typed M12 Pair preparation seam only if necessary to admit the coordinator through existing lifecycle ownership; preserve legacy reader/writer/controller.
- `lib/features/learning/data/drift_learning_repository.dart`: add authenticated v6 pinned matching validation, including deleted lexical content; reuse recovery limits through shared policy where appropriate.
- `test/features/learning/pair_matching/pair_matching_atomic_start_test.dart`: shared-initial-codec regression.
- `test/features/learning/matching_mode_adapter_test.dart` and `test/features/learning/drift_learning_repository_test.dart`: only tests required by touched seams.

CurrentActivityEvidenceAdapter likely needs no production change: normal recognition/guided capture and frozen recovery already exist. If a missing typed authority check proves otherwise, notify root before expanding this write set. Generic configuration/history/Today files and status documents remain root-owned. No schema/code-generation work.

## TDD and real integration acceptance

1. RED engine transition table: no selection -> select; same tile -> deselect; same side different tile -> reselect; either cross-side tap order and both directions; invalid/matched tile rejected; correct commit increments once; mismatch unchanged; duplicate ID exact no-op versus payload collision; stale round/revision/owner fenced. Run focused engine file first after tool ownership is granted.
2. RED real in-memory Drift path: synthetic owner/category/4 and 6 pinned words -> atomic start -> coordinator -> canonical pending checkpoint/answer/event/clear. Assert actual AnswerAttempts and projection rows, not mocked effect counts. One mismatch writes one incorrect recognition for prompt canonical ID only; distractor has no incorrect attempt. No writes for selection, deselection, renderer rebuild, pronunciation, or visible-text narration. Mapping reveal makes subsequent answer guided and persists across restore. Check first-opportunity role stays consumed after wrong even if later correct.
3. Fault-injected real repository: failure before checkpoint commit, lost acknowledgement after checkpoint commit, answer rejection before commit, lost answer acknowledgement after commit, failure/lost acknowledgement clearing pending. Reconstruct coordinator from latest exact recovery at every boundary and compare sourceEvidenceId, occurrence time, actor/context bytes, attempts/events/projections and ledger exactly. Reject changed payload retries and corrupt/mismatched frozen contexts without new writes. Disk-backed reopen test covers actual process-style recovery, using only synthetic fixtures.
4. Owner switch during freeze/append/answer callbacks and disposed/rebuilt coordinator callbacks cannot advance state or write for another owner. Already acknowledged attempts remain recoverable. A repeated atomic start after progressed or closed session loads latest exact snapshot. Corrupt v6 plan/tile/support/ledger/attempt references fail closed.
5. Deleted pinned word with correct authenticated pending v6 answer remains recoverable; forged revision/checksum/prompt/target/evidence context rejects. Legacy deleted matching v1–v5 tests remain green. Boundary test verifies Practice Replay is still rejected.
6. Codec canonical round-trip and measured worst-case UTF-8 size; capacity test leaves remaining answer, Continue-untimed and terminal reservations reachable. Attempt/operation ledger must be bounded without silently accepting an old changed payload after eviction.
7. Serialized touched-suite checks: Pair tests, `matching_mode_adapter_test.dart`, `current_activity_evidence_test.dart`, `unified_lesson_controller_test.dart`, relevant Drift repository tests and discovered canonical evidence/gateway regression files. Follow with focused formatter/analyzer. Record exact commands, source state, RED/GREEN counts and any omissions in report. Full suite/build belong to root integration checkpoint.

## Concrete risks to resolve during implementation

- Existing Drift deleted-pinned matching validator accepts only state versions 1–5 and reads legacy `pairs`/`pendingEvidence`. Adding v6 must validate full pinned context, not simply widen its version switch. Live-word writes also need v6 operation/plan binding at the canonical boundary if currently only the coordinator checks it.
- Generic checkpoint append validates envelope/budget but is not a Pair semantic validator. Decode and repository admission need explicit tamper rejection; successful JSON round-trip is insufficient.
- v6 start operation is serialized in checkpoint beside the same plan, so bounded plan size plus duplicated content and pending contexts must be measured against 64 KiB, not only Dart string length.
- Serial two-checkpoint answer persistence consumes capacity quickly. Must reserve future required answers before optional durable state changes; PM3 role policy and PM4 transitions extend one budget rather than multiply constants.
- Capturing evidence again after uncertain failure would mint another identity. Preserve the pending object even if freeze fails, persist frozen contexts before write, and restore exactly from acknowledged checkpoint.
- Same-side operations cannot produce durable writes individually. Crash recovery promises apply at acknowledged coalesced boundaries; operation identities/ledger design must distinguish neutral transient gestures from evidence operations and document bounded dedup behavior.
- PM2 should expose support/repair roles without implementing fake repairs, timer UX, stars, replay, or presenting itself as end-to-end UI readiness. Actual shell integration and downstream authority checks must remain explicit for later phases.

Next step: root completes PM1 review, supplies final PM1 report and sole Flutter/Dart ownership, then PM2 begins focused RED tests. No task-owned process is running.
