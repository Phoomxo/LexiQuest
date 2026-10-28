# Task 1 Report: Lock the v0.1 version contract

## Implementation summary

Locked the default LexiQuest build identity to `0.1.0+1` in both the Flutter package manifest and `AppBuildInfo.fromEnvironment()`. The default build ID remains `development`.

## Commands and test results

| Command | Result |
| --- | --- |
| `flutter test test/runtime/app_build_info_test.dart` (RED) | Failed as expected: expected `0.1.0+1`, actual `1.0.0+1`. |
| `flutter pub get` | Passed; dependency resolution completed. `pubspec.lock` did not change because the dependency graph was unchanged. |
| `flutter test test/runtime/app_build_info_test.dart` (GREEN) | Passed: 3 tests. |
| `flutter test` | Passed: 709 tests. |
| `git diff --check` | Passed with no whitespace errors. |

## TDD RED evidence with expected failure

Changed the existing `fromEnvironment defaults to pubspec version and a development id` test to expect `0.1.0+1` before changing production code. The focused test command failed specifically with:

```text
Expected: '0.1.0+1'
Actual: '1.0.0+1'
```

This proves the test exercised the old environment default rather than failing due to setup or a typo.

## TDD GREEN evidence

Updated `pubspec.yaml` and `AppBuildInfo.fromEnvironment()` to use `0.1.0+1`, then reran the focused test command. It completed successfully with `All tests passed!` and 3 passing tests. The complete Flutter suite subsequently completed successfully with 709 passing tests.

## Files changed

- `pubspec.yaml` — manifest version set to `0.1.0+1`.
- `lib/runtime/app_build_info.dart` — `LEXIQUEST_VERSION` default set to `0.1.0+1`.
- `test/runtime/app_build_info_test.dart` — default environment contract assertion set to `0.1.0+1`.
- `pubspec.lock` — resolved by `flutter pub get`; no content change was required.

## Self-review findings

- Confirmed the manifest version and runtime default are identical: `0.1.0+1`.
- Confirmed the default build ID remains `development` and is covered by the focused test.
- Confirmed no unrelated files were included in the commit.
- Confirmed `git diff --check` found no whitespace errors.

## Concerns

- `flutter pub get` and test commands report 15 packages with newer versions incompatible with current dependency constraints, including a retracted `jni 1.0.1`; this is pre-existing dependency maintenance information and outside Task 1's version-contract scope.

Commit: `423c01b build: set the v0.1 version contract`
