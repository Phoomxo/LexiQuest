# Checkpoint 3 Finding 6 Report

## Status

DONE_WITH_CONCERNS — Adventure launch now requires an active-owner-aware
configuration authority and uses its atomic save operation. Drift validates
exactly one matching active local owner in the same transaction as the upsert.
Standard `SessionConfigurationStore.save/read/clear` behavior remains intact.
Nothing was staged or committed.

## Root cause

`_startAdventureMission()` validated the active owner immediately before and
after awaiting ordinary `SessionConfigurationStore.save()`. Ownership could
change while that save was pending, so the old owner's configuration could be
written before the post-save check stopped launch. Dependency composition also
accepted any plain `SessionConfigurationStore`, despite that interface having
no active-owner atomicity guarantee.

The fix adds the narrow `ActiveOwnerSessionConfigurationStore` interface and
implements it in `DriftSessionConfigurationStore`. `saveForActiveOwner()`
canonicalizes and verifies the signed configuration, then queries at most two
active local owners and performs the configuration upsert inside one Drift
transaction. It throws `SessionConfigurationResetRequired(ownerDrift)` before
the upsert unless there is exactly one active owner whose ID matches the
configuration owner. Adventure composition now requires this interface, and
Adventure launch calls `saveForActiveOwner()`; Standard launch paths continue
to use ordinary `save()`.

## RED/GREEN evidence

### Production atomic store

1. RED command:

   `flutter test test\features\learning\session_configuration_store_test.dart --reporter compact`

   Exact result: exit code `1`; test loading failed because
   `ActiveOwnerSessionConfigurationStore` was not a type and
   `saveForActiveOwner` was undefined on `DriftSessionConfigurationStore`.

2. GREEN command:

   `flutter test test\features\learning\session_configuration_store_test.dart --reporter compact`

   Exact result: exit code `0`; 7/7 tests passed. The real in-memory Drift
   cases prove success for one matching active owner, rejection of a stale
   inactive owner with zero rows written, and rejection of ambiguous active
   ownership with zero rows written. The existing ordinary save/read test also
   remained green.

### Adventure composition and navigation

1. RED command:

   `flutter test test\screens\main_navigation_screen_test.dart --reporter compact`

   Exact result: exit code `1`; 24 tests passed and 2 failed. The gated
   persistence race received ordinary `save()` and eventually threw the old
   post-save `StateError` instead of the expected typed owner-drift rejection.
   The plain-store composition case also expected `false` but received `true`
   for `atomicConfigurationStore`.

2. Focused plain-store RED confirmation:

   `flutter test test\screens\main_navigation_screen_test.dart --reporter expanded --plain-name "Adventure entry fails closed when a launch authority is absent"`

   Exact result: exit code `1`; 0 passed and 1 failed with `Expected: false`,
   `Actual: <true>`, reason `atomicConfigurationStore`.

3. GREEN command:

   `flutter test test\screens\main_navigation_screen_test.dart --reporter compact`

   Exact result: exit code `0`; 26/26 tests passed. The deterministic owner
   drift during persistence records one atomic call, zero ordinary save calls,
   zero stale writes, no Adventure screen, and zero learning sessions.

4. Production navigation fixture GREEN command:

   `flutter test test\scenarios\production_feature_navigation_test.dart --reporter compact`

   Exact result: exit code `0`; 24/24 tests passed. Its intentionally composed
   `_NavigationSessionConfigurationStore` now models the atomic authority,
   while the main-navigation plain-store fixture remains base-interface-only
   for fail-closed coverage.

### Final verification

- `dart format --output=none --set-exit-if-changed lib\features\learning\domain\session_configuration.dart lib\features\learning\data\drift_session_configuration_store.dart lib\runtime\app_dependencies.dart lib\screens\main_navigation_screen.dart test\features\learning\session_configuration_store_test.dart test\screens\main_navigation_screen_test.dart test\scenarios\production_feature_navigation_test.dart` — exit code `0`; 7 files checked, 0 changed.
- Scoped `dart analyze` over each of the seven Dart paths above — exit code `0`; all seven reported `No issues found!`.
- `flutter test test\features\learning\session_configuration_store_test.dart test\screens\main_navigation_screen_test.dart test\scenarios\production_feature_navigation_test.dart test\runtime\app_bootstrap_test.dart --reporter compact` — exit code `0`; 144/144 tests passed.
- `git diff --check` — exit code `0`; no whitespace errors. Git emitted only LF-to-CRLF working-copy advisories.

## Changed paths

- `lib/features/learning/domain/session_configuration.dart`
- `lib/features/learning/data/drift_session_configuration_store.dart`
- `lib/runtime/app_dependencies.dart`
- `lib/screens/main_navigation_screen.dart`
- `test/features/learning/session_configuration_store_test.dart`
- `test/screens/main_navigation_screen_test.dart`
- `test/scenarios/production_feature_navigation_test.dart`
- `.superpowers/sdd/checkpoint-3-finding-6-report.md`

## Concerns

- The worktree already contained many unstaged changes, including pre-existing
  modifications to both protected files. This finding did not edit or stage
  `lib/features/sync/domain/sync_entity.dart` or
  `lib/learning/storage/learning_database.g.dart`.
- Some existing widget/bootstrap fixtures emit Drift's multiple-database
  warning while still passing. This finding did not alter that fixture
  lifecycle behavior.
- Flutter dependency resolution reported 94 packages with newer versions
  incompatible with current constraints; this was informational and did not
  affect test results.
- No staging, commit, security scan, unrelated refactor, Pair work, or research
  work was performed.
