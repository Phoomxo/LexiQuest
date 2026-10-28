# Checkpoint 3 Finding 4 Report

## Status

GREEN. The cached completed summary is now validated against the current
Adventure run and terminal checkpoint before it can be returned. Nothing was
staged or committed.

## Root cause

`recoverExact()` cached `recovery.session` for a completed run. Although
`_loadCompletedSummary()` checked the supplied terminal against the run state,
it returned a non-null `_completedSummary` immediately. Identity, completed
lifecycle, and `endedAtUtc` validation therefore ran only on the uncached
canonical-load path.

The fix selects the cached or freshly loaded Learning summary, then validates
its session ID, owner ID, activity type, completed state, and exact terminal
before caching or returning that same Learning-owned result. It does not derive
or rewrite Learning results.

## RED

Command:

```text
flutter test test/features/adventure/application/adventure_recovery_use_cases_test.dart --plain-name "recovered completed summary rejects a mismatched terminal"
```

Exact result: exit code `1`; `00:00 +0 -1`; the test expected a
`StateError`, but the future emitted a `LearningSessionSummary`; final output
was `Some tests failed.`

## GREEN

Single regression command:

```text
flutter test test/features/adventure/application/adventure_recovery_use_cases_test.dart --plain-name "recovered completed summary rejects a mismatched terminal"
```

Exact result: exit code `0`; `00:00 +1: All tests passed!`

Full recovery-use-case command:

```text
flutter test test/features/adventure/application/adventure_recovery_use_cases_test.dart
```

Exact result: exit code `0`; `00:01 +26: All tests passed!`

Additional bounded checks:

- `dart format --output=none --set-exit-if-changed lib/features/adventure/application/adventure_recovery_use_cases.dart test/features/adventure/application/adventure_recovery_use_cases_test.dart` — exit code `0`, `Formatted 2 files (0 changed)`.
- `dart analyze lib/features/adventure/application/adventure_recovery_use_cases.dart` — exit code `0`, `No issues found!`
- `dart analyze test/features/adventure/application/adventure_recovery_use_cases_test.dart` — exit code `0`, `No issues found!`
- Scoped `git diff --check` — exit code `0`; Git emitted only the existing LF-to-CRLF working-copy advisory.

## Changed paths

- `lib/features/adventure/application/adventure_recovery_use_cases.dart`
- `test/features/adventure/application/adventure_recovery_use_cases_test.dart`
- `.superpowers/sdd/checkpoint-3-finding-4-report.md`

## Concerns

- The worktree was already dirty before this finding, including pre-existing
  modifications to both protected files. This work did not edit or stage
  `lib/features/sync/domain/sync_entity.dart` or
  `lib/learning/storage/learning_database.g.dart`.
- Flutter dependency resolution reported 94 newer versions incompatible with
  current constraints; this was informational and did not affect the tests.
