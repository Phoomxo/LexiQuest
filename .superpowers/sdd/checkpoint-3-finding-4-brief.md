# Checkpoint 3 Finding 4 — cached terminal summary

Fix only the cached terminal-summary fail-closed gap.

## Requirement

`AdventureRecoveryUseCases._loadCompletedSummary()` must never return `_completedSummary` until the cached summary is validated against the current run and the supplied terminal checkpoint. A recovered completed session whose canonical summary `endedAtUtc` differs from the Adventure terminal checkpoint must fail closed when `loadCompletedSummary()` is called.

## TDD

1. Add the smallest regression in `test/features/adventure/application/adventure_recovery_use_cases_test.dart` that recovers a completed session with a mismatched cached/canonical terminal and demonstrates the current bad return.
2. Run that single test and record the expected RED failure.
3. Make the smallest production fix in `lib/features/adventure/application/adventure_recovery_use_cases.dart`; validate identity/lifecycle/terminal without deriving or rewriting Learning results.
4. Run the single test and full recovery-use-case test file GREEN.

## Constraints

- Use `apply_patch` for edits.
- Do not edit or stage `lib/features/sync/domain/sync_entity.dart` or `lib/learning/storage/learning_database.g.dart`.
- Do not stage or commit anything.
- Do not run Codex Security.
- Do not touch unrelated files or implement Pair/research work.

Write `.superpowers/sdd/checkpoint-3-finding-4-report.md` with status, root cause, RED/GREEN commands and exact results, changed paths, and concerns. Return only a compact status summary.
