# Checkpoint 3 Finding 5 — immutable pinned-content boundary

Fix only the mutable pinned-content time-of-check/time-of-use gap at the application and Drift repository boundaries.

## Requirement

- `LearningUseCases.startCheckpointedQuiz()` must freeze the complete `PinnedQuizContent` vector synchronously before its first `await` (including owner resolution) and use only that frozen vector for selection, validation, initial-state creation, and the start call.
- `DriftLearningRepository.startExactPinnedSessionWithCheckpoint()` must likewise freeze the complete vector before entering asynchronous transaction work and use only that frozen vector for IDs and exact revision/checksum validation.
- A caller mutating the original list after invocation must not change the accepted content or checkpoint.

## TDD

1. Add a deterministic application-layer regression in `test/features/learning/learning_use_cases_test.dart`: hold owner resolution with a `Completer`, invoke start with mutable pins, mutate the source before owner resolution completes, then prove the original vector is the only one selected/started.
2. Observe expected RED.
3. Freeze synchronously at the application boundary; run focused and full file GREEN.
4. Add a deterministic repository regression in `test/features/learning/drift_learning_repository_test.dart`. Prefer a controlled list/iterator or transaction gate that changes the caller source after the synchronous validation pass but before asynchronous row validation, proving the repository does not re-read the caller list.
5. Observe expected RED.
6. Freeze synchronously at the repository boundary; run focused and full file GREEN.

Do not weaken exact owner/revision/checksum checks or convert mismatch into silent downgrade.

## Constraints

- Use `apply_patch` for edits.
- Do not edit or stage `lib/features/sync/domain/sync_entity.dart` or `lib/learning/storage/learning_database.g.dart`.
- Do not stage or commit.
- Do not run Codex Security.
- No unrelated refactor or Pair/research work.

Write `.superpowers/sdd/checkpoint-3-finding-5-report.md` with status, root cause, RED/GREEN commands and exact results, changed paths, and concerns. Return only a compact status summary.

