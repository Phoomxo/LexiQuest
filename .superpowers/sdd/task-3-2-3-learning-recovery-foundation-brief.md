# Task 3.2/3.3 — Learning Recovery Foundation

Work only in `C:\Users\Phet\Documents\LexiQuest\.worktrees\adventure-motivation-plan` at/after HEAD `b57f36402a0da292b6d04d2bf3b73596d874fcd2`.

This slice creates the Learning-owned durable foundation needed by Adventure repair/restart. It does **not** wire Adventure, bootstrap, navigation, or UI yet.

## Required behavior

1. Add exact-session recovery to `LearningActivityRecoveryRepository` and `LearningUseCases`. The lookup is keyed by canonical `ownerId`, `sessionId`, and `activityType`; mismatch/not-found returns `null`; corrupt matching durable data throws. Preserve the existing latest-by-activity API for current callers and share reconstruction logic rather than duplicating validation.
2. Add `pinnedWordIds` support to `LearningUseCases.startCheckpointedQuiz`, with the same ordered, exact, fail-closed semantics already used by `startQuiz`. No category may be combined with pinned IDs. A configured session still requires exactly `limit` items.
3. In `DriftLearningRepository.startSessionWithCheckpoint`, atomically reject a different active Learning session for the same owner before creating a new one. Use a typed Learning-domain conflict exception carrying enough identities for callers to resume the existing session. Retrying the exact same session ID and exact draft/checkpoint must remain idempotent. Sessions for another owner and non-active sessions do not block. Scope this invariant to the checkpointed start path only; do not change legacy `startSession` behavior and do not add a schema/index.
4. Generalize exact pending-evidence restart in `current_activity_evidence.dart`:
   - Add an immutable, strict, versioned (`schemaVersion: 1`) `FrozenPendingCurrentActivityEvidence` JSON representation.
   - `PendingCurrentActivityEvidence.freezeForRecovery()` must resolve/bind the owner and complete evidence/event contexts before any canonical write, then freeze the exact source evidence ID, timestamp, session/word/prompt, answer, response time, attempt number, provenance, historical actor, input/declaration/hint data, optional contrastive context, and resolved contexts. It must not write an answer.
   - Add generic `CurrentActivityEvidenceAdapter.restore(FrozenPendingCurrentActivityEvidence)` returning a pending occurrence in `retryRequired`; `record()` must reject until explicit `retry()`. Repeated retries preserve exact identity/payload and rely on canonical idempotency.
   - Preserve historical actor identity and resolved contexts across restart; do not re-read mutable research/owner context to redefine the evidence.
   - Keep `restoreMatching` source compatibility by delegating through the generic frozen/restore path, and update test-only repository wrappers for the new exact-recovery method.

## Tests (strict TDD)

Start with failing tests and record the RED failure in your final report. Add focused coverage in the existing test locations:

- `test/features/learning/learning_use_cases_test.dart`
- `test/features/learning/drift_learning_repository_test.dart`
- `test/features/learning/current_activity_evidence_test.dart`
- wrapper conformance where required in `test/features/learning/matching_mode_adapter_test.dart` and `test/screens/choose_mode_screen_test.dart`
- add `test/features/learning/learning_recovery_foundation_test.dart` for a real file-backed close/reopen scenario using fresh database/repository/adapter objects, exact session lookup, frozen decode/restore, and two explicit retries. Verify one durable answer attempt and one canonical source event after replay.

Cover at minimum: exact lookup, mismatches, corruption, active-session conflict, exact same-ID idempotency, owner/non-active exceptions, pinned order/fail-closed behavior, strict unknown/missing/wrong-type JSON rejection, deep immutability, no write during freeze, restored `retryRequired`, `record()` rejection, actor/context preservation, and duplicate count zero after restart/replay.

## Scope and safety

- Allowed production files: `lib/features/learning/domain/learning_repository.dart`, `lib/features/learning/application/learning_use_cases.dart`, `lib/features/learning/data/drift_learning_repository.dart`, `lib/features/learning/application/current_activity_evidence.dart`, plus narrowly necessary Learning-domain model files.
- Allowed tests: only the Learning tests and wrapper files listed above.
- Do not touch Adventure, Review, SRS policy, bootstrap, navigation, schema/migrations, generated files, or Standard UI behavior.
- Never edit/stage `lib/features/sync/domain/sync_entity.dart` or `lib/learning/storage/learning_database.g.dart`; they are pre-existing stat-only paths.
- Do not run repository-wide analysis/security. Run focused tests and focused analyzer only.
- Use `apply_patch` for edits, format touched Dart files, inspect `git diff --check`, stage only your exact paths, and commit with a focused message.
- Stop immediately if the same filesystem/tool error repeats or there is no measurable progress for 10 minutes. Return the commit SHA, changed paths, RED evidence, focused GREEN counts, analyzer result, and any remaining risks.
