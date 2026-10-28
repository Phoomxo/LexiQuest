# Checkpoint 3 review-fix brief

## Scope

Close the six verified correctness findings in the Adventure mixed-review/recovery implementation. Work test-first, one finding at a time: add the smallest regression test, run it and capture the expected failure, make the minimal production change, then rerun the focused test.

## Binding constraints

- Never edit or stage these pre-existing user files:
  - `lib/features/sync/domain/sync_entity.dart`
  - `lib/learning/storage/learning_database.g.dart`
- Do not run or recommend Codex Security workflows.
- Do not stage or commit. Leave changes in the current worktree for the controller to inspect and commit explicitly.
- Do not implement Matching Pair v1.2 or research-governance work.
- Preserve Standard/Adventure compatibility and fail-closed ownership/recovery behavior.
- Use `apply_patch` for edits.

## Finding 1: repair transition mismatch

`AdventureRepairPolicy._nextSupportiveTarget` can schedule `LessonMode.definitionQuiz` after `typedRecall` or `cloze`, while `AdventureRepairPolicySnapshot._isAuthorizedTransition` rejects those same transitions. Add regression coverage proving a policy snapshot containing each valid transition round-trips/restores, then make validator and scheduler authorization identical.

Covering test: `test/features/adventure/application/adventure_repair_policy_test.dart`.

## Finding 2: flashcard continuation reentrancy

`AdventureMixedReviewController.continueAfterFlashcard()` awaits persistence while still in `flashcardRevealed`, so a second tap can enter concurrently. Add a deterministic Completer-based regression test proving the first call enters a busy phase synchronously, a second call is rejected, only one checkpoint operation occurs, and a failed first operation restores a retryable revealed state. Then implement the minimal phase/failure handling.

Covering test: `test/features/adventure/application/adventure_mixed_review_controller_test.dart`.

## Finding 3: catalog snapshot mutability

`_AdventureLexicalArtifactSnapshot.fromJson()` currently keeps a cast view backed by the caller's mutable `examples` list. Add a regression test that decodes a snapshot, mutates the source JSON list, and proves the decoded snapshot/catalog remains unchanged. Freeze the complete list at the boundary.

Covering test: `test/features/adventure/application/adventure_mixed_review_prompt_catalog_test.dart`.

## Finding 4: cached terminal summary validation

`AdventureRecoveryUseCases._loadCompletedSummary()` returns `_completedSummary` before confirming its `endedAtUtc` matches the terminal checkpoint passed to the method. Add a recovery regression using a completed session whose cached summary terminal differs from the checkpoint; loading the completed summary must fail closed. Validate cached identity/terminal before returning it; do not derive or rewrite canonical Learning results.

Covering test: `test/features/adventure/application/adventure_recovery_use_cases_test.dart`.

## Finding 5: mutable pinned-content TOCTOU

`LearningUseCases.startCheckpointedQuiz()` snapshots `pinnedContent` only after awaiting owner resolution. `DriftLearningRepository.startExactPinnedSessionWithCheckpoint()` snapshots IDs but later iterates the original mutable list. Add deterministic regressions at both layers. Freeze the entire `PinnedQuizContent` vector before the first asynchronous boundary in each public method and use only that frozen vector thereafter.

Covering tests:
- `test/features/learning/learning_use_cases_test.dart`
- `test/features/learning/drift_learning_repository_test.dart`

## Finding 6: owner drift during configuration persistence

Adventure launch currently checks the owner before and after `SessionConfigurationStore.save`, leaving a stale old-owner write if the owner changes while the save is in flight. Make owner validation and persistence atomic against the production active-owner authority. A suitable design is a narrow active-owner-aware store interface implemented by `DriftSessionConfigurationStore`, with the active-owner check and configuration upsert in one Drift transaction; Adventure composition must require and use this authority. Standard save/read behavior must remain compatible.

Add tests proving the production store rejects a stale owner without writing and that Adventure dependency/navigation behavior fails closed when atomic authority is absent or ownership drifts. Do not add test-only production APIs.

Likely files/tests:
- `lib/features/learning/domain/session_configuration.dart`
- `lib/features/learning/data/drift_session_configuration_store.dart`
- `lib/runtime/app_dependencies.dart`
- `lib/screens/main_navigation_screen.dart`
- `test/features/learning/drift_session_configuration_store_test.dart`
- `test/runtime/app_dependencies_test.dart` or the existing dependency coverage file
- `test/screens/main_navigation_screen_test.dart`

## Required report

Write `.superpowers/sdd/checkpoint-3-review-fixes-report.md` with:

- status: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`;
- root cause and exact fix for each finding;
- RED command and expected failure observed for each regression;
- GREEN command and exact pass counts;
- all changed paths;
- self-review concerns, if any.

