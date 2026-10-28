# Task 2 Report: Remove Supabase from application bootstrap and runtime health

## Implementation summary

- Replaced the three-boundary runtime status with Firebase and cloud-enhancement (`backends`) availability only.
- Added `isCoreLearningAvailable`, which is always true so local learning is accurately represented as offline-capable.
- Removed the Supabase initializer, production configuration, constructor dependency, and runtime status contribution from `AppBootstrap`.
- Deleted the obsolete Supabase configuration helper and its unit test.
- Updated runtime and shell fixtures, removed Supabase-specific bootstrap tests, and changed the drawer summary to call out local offline learning while listing only account sync and AI/online voice availability.

## Commands and results

| Command | Result |
| --- | --- |
| `flutter test test/runtime/app_runtime_status_test.dart` | RED: exit 1 as expected; `AppRuntimeStatus` still required the `supabase` named parameter. |
| `dart format lib/runtime/app_runtime_status.dart lib/runtime/app_bootstrap.dart lib/screens/main_navigation_screen.dart test/runtime/app_runtime_status_test.dart test/runtime/app_bootstrap_test.dart test/runtime/learning_dependencies_test.dart test/runtime/app_build_info_test.dart test/screens/production_shell_navigation_test.dart` | Completed; affected Dart files formatted. |
| `flutter test test/runtime/app_runtime_status_test.dart test/runtime/app_bootstrap_test.dart test/runtime/learning_dependencies_test.dart test/runtime/app_build_info_test.dart test/screens/production_shell_navigation_test.dart` | GREEN: exit 0; 25 tests passed. |
| `flutter test` | exit 0; 693 tests passed. |
| `git diff --check` | exit 0; no whitespace errors. |
| `rg -n -i 'supabase' lib/runtime` | No matches. |

## RED evidence and why expected

The new runtime-status surface test initially failed to compile because the existing constructor still required `supabase`. This was the expected pre-change API mismatch and demonstrated that the test exercised the intended Supabase-boundary removal.

## GREEN evidence

The focused runtime and shell command passed all 25 tests after the minimum implementation and fixture changes. The new test verifies that fully-ready depends on Firebase plus configured cloud enhancements, while core learning remains available when both are unavailable.

## Full-suite result

`flutter test` completed successfully with 693 passing tests. The anticipated historical build-key blocker did not occur in this run.

## Files changed

- Modified: `lib/runtime/app_runtime_status.dart`
- Modified: `lib/runtime/app_bootstrap.dart`
- Deleted: `lib/runtime/supabase_client_config.dart`
- Modified: `lib/screens/main_navigation_screen.dart`
- Added: `test/runtime/app_runtime_status_test.dart`
- Modified: `test/runtime/app_bootstrap_test.dart`
- Modified: `test/runtime/learning_dependencies_test.dart`
- Modified: `test/runtime/app_build_info_test.dart`
- Modified: `test/screens/production_shell_navigation_test.dart`
- Deleted: `test/runtime/supabase_publishable_key_test.dart`

## Self-review

- Confirmed `AppBootstrap` exposes no Supabase initializer and production bootstrap makes no Supabase call.
- Confirmed runtime status has only Firebase and backend availability, with a constant offline-learning availability signal.
- Confirmed `lib/runtime` has no Supabase source references.
- Confirmed Supabase remains in dependencies and wallpaper code, as intentionally deferred to Tasks 3 and 4.
- Reviewed the focused diff and checked it for whitespace errors.

## Concerns

None for this task. Supabase package and wallpaper references intentionally remain outside this task's runtime/bootstrap scope.

## Follow-up review fix

Added behavior-level widget coverage in `test/screens/production_shell_navigation_test.dart` for the runtime drawer summary.

| Command | Result |
| --- | --- |
| `flutter test test/screens/production_shell_navigation_test.dart` | GREEN: exit 0; 7 tests passed. |

### RED/GREEN record

The assertions were added before any production change. A RED run was not applicable: the existing committed production summary already rendered the exact ready text (`ระบบพร้อมใช้งาน รวมบริการออนไลน์`) and the required degraded-state text for offline learning, account sync, and AI/online voice. The first focused run was GREEN with all seven tests passing, so no production correction was made.
