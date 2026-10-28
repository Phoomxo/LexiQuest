# PM4/PM8 checkpoint feasibility audit

Scope: read-only inspection of the approved PM4/PM8 plan, SDS 15.6/15.9, current Matching adapter, repository checkpoint boundary, and existing recovery tests in `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`. No Flutter/Dart command or production-source write was performed.

## Current canonical constraints

- `DriftLearningRepository.maxActivityRecoveryCheckpoints` is 64 and recovery fails closed at 65 rows. Each checkpoint revision is immutable, sequential, owner/session/activity scoped, and idempotent only when the same revision has exactly the same canonical state, timestamp, terminal identity, and acknowledgement (`drift_learning_repository.dart:42,596–729,889–1079`). A different payload cannot replace an acknowledged revision.
- One checkpoint state is JSON canonicalized and limited to 65,536 UTF-8 bytes (`drift_learning_repository.dart:560–593`). The repository separately caps recovered AnswerAttempts at 128.
- Current `MatchingModeAdapter` uses schema versions 1–5, a 64-checkpoint ceiling, 30-attempt ceiling, and a three-revision terminal reservation (`matching_mode_adapter.dart:443–447`). Each answer normally consumes two revisions: freeze pending evidence before the answer write, then clear pending after commit. Completion consumes pending close, terminal acknowledgement, and summary-presented revisions.
- Lost acknowledgement is already correctly modeled by `_pendingAppend`: while one append is unresolved, a different state is rejected and the exact same checkpoint object/revision is retried (`matching_mode_adapter.dart:329–369`). The repository validates the immutable stored envelope before acknowledging success.
- Current restore validates exact checkpoint schema keys, pair snapshots, answer ordering/content identity, pending evidence/event context, terminal identity, and owner/actor lineage. Legacy timeout schemas are interpreted and then `persistTimeoutContract()` automatically upgrades the active row stream to v5.

## Feasible bounded PM4 policy

Use a folded snapshot, not a log of UI/timer gestures, inside each v6 checkpoint. AnswerAttempts and their canonical events remain the immutable answer ledger. The checkpoint stores only the latest recoverable Pair reducer state: purpose/source pins, exact plan, committed-ledger references/counters needed for repair/stars, current round ordinal/seed, timer mode and remaining active milliseconds, pause reason set, extension entitlement/use, durable timeout decision, pending operation, terminal state, and codec/writer identity. Do not store frame ticks, raw monotonic samples, duplicate lifecycle callbacks, animation state, or an ever-growing list of pause/restart records. This keeps 4/6-pair state far below 64 KiB; tests must measure canonical UTF-8 size at worst-case IDs and terminal state.

Coalesce intents before persistence as follows:

1. Serialize answer, timeout, extension, restart, and terminal commands through the existing single admitted-operation/persistence lock. Freeze one operation ID and target snapshot before append. Disable conflicting UI actions until its exact acknowledgement or reconciliation.
2. Maintain lifecycle pause reasons as an in-memory set. Duplicate add/remove callbacks are no-ops. During an unresolved append, merge only equivalent lifecycle changes into the pending target; once the immutable write has been attempted, retry exactly that target and queue at most one folded successor snapshot. Never mutate the identity/payload of an uncertain write.
3. Timer ticks never persist. Persist on the first transition from active to inactive, timeout decision, extension, continue-untimed, restart, pending evidence, pending close, and lifecycle/background flush. Resume may remain conservatively represented as the last durable paused snapshot until a later boundary: after a crash it restores paused and requires explicit resume, preserving elapsed time rather than fabricating active time.
4. Persist `remainingActiveMs`, not wall-clock deadline, for v6. The injected monotonic clock exists only during one process lifetime. On pause/flush, fold elapsed monotonic duration into the remaining value and clear the live segment. Clock rollback/fault performs the same safe pause and leaves Continue untimed available.
5. Preserve a hard terminal reserve before admitting any nonterminal durable operation. The current three revisions are the minimum for pending close, completion acknowledgement, and summary-presented receipt. If v6 combines summary presentation with another acknowledged terminal snapshot, retain the larger proven reserve until PM8 recovery tests show the smaller sequence is safe.
6. At the reserve boundary, stop admitting operations that require another nonterminal checkpoint and surface a recoverable persistence-capacity state. Continue untimed must remain available: if the currently durable state is `timeoutDecision`, admission policy must reserve one revision specifically for `continueUntimed` in addition to the terminal reserve, or fold Continue untimed into the already pending timeout-decision operation before its acknowledgement. The UI must never remove Continue untimed or turn timeout into failure.

The final point prevents corruption and implements the plan's bounded “worst allowed” sequence. A mathematically unlimited sequence is discussed below only as a stress boundary; it is not an approved product requirement.

## Hypothetical mathematical limit (not a contract blocker)

If one hypothetically required all four conditions below, they could not all hold for an arbitrarily long session with the existing repository contract:

1. every restart/pause decision is durable before UI acknowledgement;
2. restart remains in the same Learning Session;
3. checkpoint revisions are immutable and capped at 64;
4. the number of sequential acknowledged restart/pause intents is mathematically unlimited.

Coalescing removes duplicate/concurrent intents and tick writes, but a user can still perform more than 60 sequential, acknowledged, state-changing restarts. Each needs a distinct durable snapshot because its round ordinal/seed changes. Reusing a revision is rejected as an identity collision, and appending revision 65 is rejected. The 64 KiB state bound is not the limiting factor; the immutable row-count bound is.

The approved PM4/PM8 plan does not require condition 4. It requires the worst allowed bounded sequence to remain below the repository ceilings with terminal reserve. Therefore this mathematical observation creates no contract contradiction, approval dependency, or unresolved PM8 acceptance item. A finite UI retry cap remains unnecessary, and Continue untimed must remain available.

Within the existing contract, capacity admission must calculate enough remaining revisions for the maximum remaining answer sequence plus any reachable Continue-untimed transition and terminal sequence before admitting a new nonterminal operation. It retains the last acknowledged checkpoint, permits exact retry/recovery/terminal close, never discards committed evidence, and never converts timeout into failure. PM8 proves the bounded worst-case arithmetic and runtime paths rather than an unlimited sequence.

## Reader-first v6 rollout without legacy overwrite

The current monolithic decode/upgrade path is not sufficient for SDS 15.9 because reading a v1–v4 active session can immediately append a v5 timeout upgrade. PM8 requires compatibility mode to be explicit:

- Extract/use `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart` with two independent concepts: `readVersions={1,2,3,4,5,6}` and `writeVersion` selected by a delivery/writer policy. Decoding must be pure and must retain the source version.
- Release A reads v1–v6 but writes legacy only for legacy sessions and does not append merely because decoding occurred. A v1–v5 session resumes with its exact legacy Standard behavior; missing repair/stars/replay/timer-active fields remain unavailable and are not inferred.
- Do not down-convert a v6 session to v5. In Release A, v6 is reader/recovery fixture support only unless the build is explicitly compatible with the v6 writer. If a v6 session exists, resume/retire through the v6 reader without writing a lossy legacy payload.
- Release B enables v6 writes only for newly accepted hidden-f10 Pair sessions after the compatibility matrix and minimum-compatible-build decision pass. Pin `checkpointWriteVersion=6` in revision 1 so a session never changes writer version midstream.
- Emergency-off blocks new v6 starts but still routes accepted v1–v6 sessions to their pinned reader/writer or safe retire path. Adventure-off uses the same checkpoint in Standard; renderer fallback does not transform it.
- Keep the repository EventEnvelopeV2 checkpoint envelope at its current event/payload version. “Pair checkpoint schema v6” belongs inside `payload.state.schemaVersion`; it is not a database schema or EventEnvelopeV2 change.

## Minimal existing seams

- `LearningActivityRecoveryRepository.appendActivityCheckpoint` and `loadExactActivityRecovery` remain the sole durable append/read boundaries. Do not add a timer table or overwrite EventsV2 rows.
- Replace `MatchingPreparedSession._appendState`’s direct revision arithmetic with a small Pair checkpoint coordinator/write policy that owns: retained operation identity, one folded successor, capacity calculation, terminal plus Continue-untimed reserve, and pinned writer version. It still delegates the actual immutable append to `LearningUseCases.appendActivityCheckpoint`.
- Move `_decodeCheckpointSession`, `_decodeTimeoutContract`, pending-evidence decoding, exact-key validation, and v1–v5 compatibility fixtures from the large adapter into the planned Pair checkpoint codec. Preserve all current fail-closed checks.
- Add a monotonic active-clock interface to the Pair domain/coordinator. Persist only folded `remainingActiveMs` and active/inactive reason state; wall time is presentation/legacy compatibility only.
- Extend the current operation admission seam (`_runAdmittedOperation`, `_runRecoveryOperation`, `_acceptsOperation`) so every answer/timeout/+30/restart/continue/close race is serialized before durable acknowledgement. Technical retries reuse the frozen operation/checkpoint identity; user restart creates a new operation ID and increments round exactly once.
- Keep `terminalCheckpointReservation` synchronized with the repository maximum through one shared Pair budget policy. Avoid two independent constants that can drift.

## Verification seams for PM4/PM8

Focused tests should cover:

- no writes for ticks, duplicate pause reasons, presentation, or renderer changes; one folded write for a burst of lifecycle callbacks;
- off/60/90/120, monotonic active-only timing, process death while active/paused, clock rollback -> paused + Continue untimed, and no incorrect/completion caused by timeout;
- exact lost acknowledgement before/after insert for pause, timeout decision, +30, continue untimed, restart, pending answer, close, acknowledgement, and summary receipt;
- +30 once per session; restart increments round/seed once and preserves exact content, committed attempts, repair/star inputs, and extensionUsed;
- races among answer/timeout/+30/restart/background with one accepted ordering and no overtaking of an uncertain append;
- budget proof for the plan's worst allowed sequence: admission preserves all remaining answer writes plus reachable Continue untimed and terminal writes, exact close remains possible at capacity, revision 65 is never needed by an admitted flow and is rejected without state loss, and capacity handling never abandons evidence or turns timeout into failure;
- canonical UTF-8 size below 65,536 bytes at worst-case valid identifiers, six pairs, maximum recoverable attempts/references, pending operation, repair state, timer decision, and terminal fields;
- v1–v5 byte fixtures read without writes or inferred v6 features; v6 fixture reads in Release A; legacy sessions keep legacy behavior; v6 is never down-converted; Release B writer only under hidden f10 state; feature/emergency/Adventure off still resume or retire accepted sessions;
- tampered version, extra/missing keys, nonsequential revision, owner/actor drift, altered operation ID, altered terminal identity, 65 rows, and >64 KiB all fail closed;
- PM8 evidence states the tested bounded sequence and reserve arithmetic explicitly; mathematical unlimited-transition support is outside the approved requirement and needs no acceptance disposition.

Conclusion: v6 is feasible as a reader-first, folded, immutable snapshot codec with exact lost-ack recovery, bounded capacity admission, remaining-answer/Continue-untimed/terminal reserve, and semantic coalescing. No material contract contradiction was found. The 64-revision ceiling only excludes a hypothetical mathematically unlimited sequence that the approved plan does not require.
