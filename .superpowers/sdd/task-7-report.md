# Task 7 Report: Record and verify the Firebase-only v0.1 APK baseline

## Status and commit

Complete.

```text
aa97664 docs: record the Firebase-only v0.1 baseline
```

## TDD evidence

### RED

After adding the requested README contract test, before changing the
documentation:

```powershell
flutter test test/config/flutter_dependency_surface_test.dart
```

Result: exit 1. The two existing dependency tests passed, and the new contract
failed for the intended reason:

```text
Expected: contains 'LEXIQUEST_VERSION=0.1.0+1'
Actual: README contained LEXIQUEST_VERSION=1.0.0+1
00:00 +2 -1: Some tests failed.
```

The Firebase-only assertion did not fail.

### GREEN

After the minimal README and historical-inventory edits:

```powershell
flutter test test/config/flutter_dependency_surface_test.dart
```

Result:

```text
00:00 +3: All tests passed!
```

The focused contract was rerun after formatting the edited Dart test and again
passed 3/3.

## Files changed

- `README.md`
  - Changed the debug APK version dart-define from `1.0.0+1` to `0.1.0+1`.
  - The command requires only build identity plus Voice and AI endpoint inputs;
    it contains no Supabase input.
- `docs/security/supabase-access-inventory.md`
  - Added the requested `v0.1 retirement status` notice at the top.
  - Explicitly marks the remaining Supabase content as historical audit
    evidence and records the Firebase-only runtime/artifact state.
- `test/config/flutter_dependency_surface_test.dart`
  - Added the requested README version and Firebase-only documentation
    contract.

## Verification

### Focused and standalone Flutter verification

```powershell
flutter test test/config/flutter_dependency_surface_test.dart
flutter analyze
flutter test --reporter compact
```

Results:

- Documentation contract: PASS, 3 tests.
- Flutter analysis: PASS, `No issues found!`.
- Complete Flutter suite: PASS, 700 tests.

### Complete approved CLI verification

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
```

Final result: exit 0, `LexiQuest verification: PASS`.

| Phase | Result |
|---|---|
| 01 Protected runtime probe tests | PASS, 49/49 |
| 02 Android command construction tests | PASS, 35/35 |
| 02.1 CI/CD contract tests | PASS (CI 88/88 plus all reported contract suites) |
| 03 Flutter dependency resolution | PASS |
| 04 Dart format check (tracked sources only) | PASS, 316 tracked Dart files unchanged |
| 05 Flutter static analysis | PASS |
| 06 Flutter unit and widget tests | PASS, 700 tests |
| 06.1 Trusted writer tests | PASS, 6 tests |
| 06.2 Trusted writer emulator tests | PASS, 5 tests |
| 07 Voice API CPU-only tests | PASS, 55 tests |
| 08 AI API CPU-only tests | PASS, 76 tests |
| 09 Local LM CPU-only tests | PASS, 75 tests |
| 10 Android debug APK build | PASS |
| 11 Read-only live GPU doctor | PASS |

Phase 10 completed without requesting or receiving
`LEXIQUEST_SUPABASE_PUBLISHABLE_KEY`:

```text
Running Gradle task 'assembleDebug'... 127.2s
Built build\app\outputs\flutter-apk\app-debug.apk
```

## APK evidence

```text
Path: C:\Users\Phet\Documents\LexiQuest\.worktrees\release-v0.1-complete-system\build\app\outputs\flutter-apk\app-debug.apk
Size: 166,358,815 bytes
SHA-256: 7D7F0A220D7DC4B8F70B735EAF8C96C4610F7257E546F7B52EA977B0B66386C7
Last write: 2026-07-30T00:40:56.9084298+07:00
```

## Systematic-debugging record

The first full-suite run stopped in phase 04 because
`lib/runtime/app_build_info.dart` had mixed working-copy line endings from the
earlier version-literal edit. Evidence:

```powershell
dart format --output=show --set-exit-if-changed lib/runtime/app_build_info.dart
git diff --exit-code -- lib/runtime/app_build_info.dart
```

The formatter returned 1 while Git reported no content diff. Formatting the
single file normalized its working-copy EOLs; `git add --renormalize` confirmed
there was no staged source change.

The next run identified the same Windows EOL condition in the newly patched
`test/config/flutter_dependency_surface_test.dart`. Formatting that one Dart
file and rerunning its focused test resolved the Task 7 regression. The
unchanged full suite then passed. Each failure had a distinct confirmed cause
and measurable progress; no retry loop occurred and no gate was weakened.

## Bounded diff and self-review

Commands:

```powershell
git diff --check
git status --short
rg -n "Supabase|supabase|LEXIQUEST_SUPABASE" lib pubspec.yaml tool/cli/verify.ps1 .github/workflows/ci.yml README.md
git diff -- README.md docs/security/supabase-access-inventory.md test/config/flutter_dependency_surface_test.dart
git diff --stat
git diff --check 26cb9a3..aa97664
git status --short
```

Results:

- No whitespace errors.
- The active-surface Supabase scan returned no matches.
- The commit contains exactly the three requested files: 17 insertions and
  1 deletion.
- The README command exactly uses version `0.1.0+1` and contains no Supabase
  input.
- The inventory notice matches the required historical-retirement wording.
- The test reads the real repository README and asserts both required
  properties without mocks.
- Post-commit worktree status is clean.

## Independent read-only review

An independent reviewer inspected `26cb9a3..aa97664` against the exact Task 7
brief and returned:

```text
Ready to merge. Task 7 complies exactly with the brief.
Critical: None.
Important: None.
Minor: None.
```

The reviewer confirmed the exact README command, verbatim retirement notice,
contract test, bounded three-file diff, version alignment, absent active
Supabase references, and clean worktree. The reviewer did not rerun the
repository-wide suites and relied on the fresh verification evidence recorded
above.

## Concerns

No blocker or Task 7 regression remains.

Non-blocking toolchain notices from the successful full suite:

- Flutter warns that future releases will require Android Gradle Plugin
  8.11.1+ and Kotlin 2.2.20+.
- npm warns that `global-ignore-file` will stop working in its next major
  version.
- The Android compiler reports existing dependency deprecation/unchecked
  operation notes.

These notices did not fail analysis, tests, or the APK build and were not
weakened or suppressed.
