# Task 2A-R implementation report

## Scope

- Base worktree: `release-a-economy-lockdown` at requested base `4906e2ddc017577a8492c1f3c1997be7c7915cb2`.
- Implemented the required failure-closed behavior only in the authorized research-export source and test files.
- No Firestore, navigation, economy, GitHub, cloud, or unrelated documentation changes were made.

## TDD evidence

### RED

1. Added the specified empty-list behavior expectation to `test/services/research_data_exporter_service_test.dart`.
2. Ran:

   ```powershell
   flutter test test/services/research_data_exporter_service_test.dart test/services/research_report_pdf_exporter_service_test.dart
   ```

3. Result: failed as expected (exit code 1). The new test expected `InsufficientData`, but `generateCsvReport(const [])` returned the header-only string:

   ```text
   word,cefr_level,latency_ms,accuracy_percent,srs_box,reviewed_at\r\n
   ```

   The other 13 focused tests passed.

### GREEN

1. Added `lib/services/research_export_errors.dart` with the required exact `InsufficientData` implementation and default message.
2. Both exporter libraries now import and re-export that shared type.
3. Added the empty-list guard at the start of `generateCsvReport`, before `StringBuffer` allocation and CSV-header writing.
4. Re-ran the focused test command above: passed, **14 tests passed**.

## Verification

All required validation commands passed:

```powershell
dart format --output=none --set-exit-if-changed ...
# Formatted 5 files (0 changed)

flutter analyze
# No issues found

git diff --check
# Passed
```

`flutter test` and `flutter analyze` reported only pre-existing package-update notices; neither reported test, analyzer, or formatting failures.

## Self-review

- Empty CSV input now throws `const InsufficientData()` and cannot return a successful header-only report.
- The guard precedes allocation/writing, satisfying fail-closed behavior.
- CSV row validation, RFC 4180 escaping, formula-injection protection, and non-empty CSV output remain unchanged.
- The PDF two-observation guard remains unchanged in behavior and now uses the same shared `InsufficientData` type and required message.
- Data-export tests import `InsufficientData` through the CSV exporter; PDF tests import it through the PDF exporter, exercising both re-exports.
- `git diff --check` was clean; the working-tree changes are limited to the specified research-export files plus this uncommitted report.

## Commit

Created `0008cfb` with message `fix(research): reject empty CSV exports`.

The commit includes only:

- `lib/services/research_export_errors.dart`
- `lib/services/research_data_exporter_service.dart`
- `lib/services/research_report_pdf_exporter_service.dart`
- `test/services/research_data_exporter_service_test.dart`
