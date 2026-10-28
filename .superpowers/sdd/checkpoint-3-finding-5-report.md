# Checkpoint 3 Finding 5 Report

## Status

PASS — the application and Drift repository boundaries now synchronously freeze the complete caller-provided `PinnedQuizContent` vector and use only the frozen copy after asynchronous work begins. No files were staged or committed.

## Root cause

- `LearningUseCases.startCheckpointedQuiz()` awaited active-owner resolution before copying `pinnedContent`. A caller could replace list elements while owner resolution was pending, changing selection, initial checkpoint state, and the exact content passed to the start repository.
- `DriftLearningRepository.startExactPinnedSessionWithCheckpoint()` synchronously derived IDs from `content`, then re-iterated the caller-owned list inside its asynchronous transaction for revision/checksum checks. A post-invocation mutation could therefore change acceptance after the initial validation pass.

## RED/GREEN evidence

### Application boundary

1. RED command:

   `flutter test test/features/learning/learning_use_cases_test.dart --plain-name "checkpointed quiz freezes mutable pins before owner resolution"`

   Exact result: exit 1; 0 passed, 1 failed. The assertion expected `['word-3', 'word-1']` but received `['word-3', 'word-4']`, proving the pre-owner-resolution caller mutation changed selection.

2. Focused GREEN command:

   `flutter test test/features/learning/learning_use_cases_test.dart --plain-name "checkpointed quiz freezes mutable pins before owner resolution"`

   Exact result: exit 0; 1 test passed.

3. Full-file GREEN command:

   `flutter test test/features/learning/learning_use_cases_test.dart`

   Exact result: exit 0; 26 tests passed.

### Repository boundary

1. RED command:

   `flutter test test/features/learning/drift_learning_repository_test.dart --plain-name "exact pinned start freezes mutable content before transaction validation"`

   Exact result: exit 1; 0 passed, 1 failed with `Bad state: Pinned checkpoint content is no longer exact.` from the asynchronous row-validation loop. The transaction gate ensured the caller mutation occurred after synchronous validation.

2. Focused GREEN command:

   `flutter test test/features/learning/drift_learning_repository_test.dart --plain-name "exact pinned start freezes mutable content before transaction validation"`

   Exact result: exit 0; 1 test passed.

3. Full-file GREEN command:

   `flutter test test/features/learning/drift_learning_repository_test.dart`

   Exact result: exit 0; 30 tests passed.

### Final verification

- `dart format --output=none --set-exit-if-changed lib/features/learning/application/learning_use_cases.dart lib/features/learning/data/drift_learning_repository.dart test/features/learning/learning_use_cases_test.dart test/features/learning/drift_learning_repository_test.dart` — exit 0; 4 files checked, 0 changed.
- `git diff --check -- lib/features/learning/application/learning_use_cases.dart lib/features/learning/data/drift_learning_repository.dart test/features/learning/learning_use_cases_test.dart test/features/learning/drift_learning_repository_test.dart` — exit 0; no whitespace errors. Git emitted only LF-to-CRLF working-copy warnings.
- `flutter test test/features/learning/learning_use_cases_test.dart test/features/learning/drift_learning_repository_test.dart` — exit 0; 56 tests passed.
- `dart analyze lib/features/learning/application/learning_use_cases.dart` — exit 0; no issues found.
- `dart analyze lib/features/learning/data/drift_learning_repository.dart` — exit 0; no issues found.
- `dart analyze test/features/learning/learning_use_cases_test.dart` — exit 0; no issues found.
- `dart analyze test/features/learning/drift_learning_repository_test.dart` — exit 0; no issues found.

## Changed paths

- `lib/features/learning/application/learning_use_cases.dart`
- `lib/features/learning/data/drift_learning_repository.dart`
- `test/features/learning/learning_use_cases_test.dart`
- `test/features/learning/drift_learning_repository_test.dart`
- `.superpowers/sdd/checkpoint-3-finding-5-report.md`

## Concerns

- The worktree already contained many unstaged changes, including pre-existing modifications to the two protected files. This finding did not edit `lib/features/sync/domain/sync_entity.dart` or `lib/learning/storage/learning_database.g.dart`.
- Flutter dependency resolution reported 94 packages with newer versions incompatible with current constraints; this was informational and did not affect the test results.
- No staging, commit, security scan, unrelated refactor, pair work, or research work was performed.
