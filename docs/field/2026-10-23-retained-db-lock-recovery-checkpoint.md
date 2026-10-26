# Retained database lock recovery checkpoint — 2026-10-23

## Scope

- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- Write set: `lib/data/local/app_database.dart`,
  `test/data/local/app_database_lock_test.dart`, and this checkpoint.
- No changes to SyncEngine, SyncTrigger, owner repository, schema, or dependencies.

## Root cause

### Evidence

- The Vivo retained-data launch log failed with `SqliteException(5)` on
  `BEGIN IMMEDIATE` from `DriftLocalOwnerRepository._serialized`, reached by
  `SyncEngine.run` and `SyncTrigger`.
- Foreground startup and the Workmanager callback each construct a production
  bootstrap, giving them independent Drift/SQLite connections. The repository
  `_writeGate` and sync mutex are process-instance scoped and cannot serialize
  those two connections.
- Before this change, `AppDatabase.production()` supplied no native SQLite open
  policy. The new file-backed two-connection regression test reproduced the
  device failure: connection B immediately returned `SqliteException(5)` with
  the causing statement `BEGIN IMMEDIATE` while connection A held a write
  transaction.

### Inference

- A Workmanager/JobScheduler write overlapping foreground startup is the most
  likely lock owner. The device log does not identify the competing process at
  the exact failure instant, so that ownership remains an inference rather than
  direct proof.

## Smallest implemented recovery

- Production connections now run a top-level, capture-free
  `DriftNativeOptions.setup` callback. Its order is `foreign_keys = ON`, then a
  five-second SQLite busy timeout, then WAL journaling, so later open work has a
  contention policy before requesting the journal mode.
- The regression test opens production connection A on a real file, holds an
  explicit write transaction, and only then constructs and activates production
  connection B. It verifies B waits, releases A, and verifies B completes
  successfully. It also asserts `journal_mode = wal` and
  `busy_timeout = 5000`.

## Verification

- RED: `flutter test --no-pub test/data/local/app_database_lock_test.dart --reporter expanded`
  failed without hanging with `SqliteException(5)` and `BEGIN IMMEDIATE` on the
  no-policy baseline when connection B was first created and activated after A
  already held its write transaction.
- GREEN: the same focused test passed after the policy change.
- Related tests: `flutter test --no-pub test/data/local/app_database_lock_test.dart test/data/local/app_database_test.dart test/features/identity/drift_local_owner_repository_test.dart test/features/sync/background_sync_scheduler_test.dart test/runtime/app_bootstrap_test.dart --reporter compact`
  passed, 41 tests.
- Scoped analysis: `flutter analyze --no-pub lib/data/local/app_database.dart test/data/local/app_database_lock_test.dart`
  passed with no issues.
- No full suite, build, or physical-device rerun was performed in this card;
  integration owns those checks.

## Next executable step

Run the integration checkpoint on the current source snapshot, then repeat the
retained-data cold launch on Vivo while Workmanager is eligible to run. Confirm
that no `database is locked` / `BEGIN IMMEDIATE` error appears and archive the
device log with the release evidence.
