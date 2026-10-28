# Task 2A-R: Fail closed on empty research CSV exports

## Goal

Make every research report exporter return the same typed `InsufficientData`
failure when it lacks enough real observations. An empty CSV request must not
return a successful header-only export.

## Files

- Create: `lib/services/research_export_errors.dart`
- Modify: `lib/services/research_data_exporter_service.dart`
- Modify: `lib/services/research_report_pdf_exporter_service.dart`
- Modify: `test/services/research_data_exporter_service_test.dart`
- Modify only if import compatibility requires it:
  `test/services/research_report_pdf_exporter_service_test.dart`

## Binding requirements

- Use TDD and record RED and GREEN output.
- Public exception name remains exactly `InsufficientData`.
- Shared type definition:

```dart
class InsufficientData implements Exception {
  const InsufficientData([
    this.message = 'Insufficient real observations for this report.',
  ]);

  final String message;

  @override
  String toString() => 'InsufficientData: $message';
}
```

- Both exporter libraries import and re-export
  `research_export_errors.dart`, preserving callers/tests that import either
  exporter library.
- `ResearchDataExporterService.generateCsvReport(const [])` throws
  `const InsufficientData()` before allocating or writing the CSV header.
- Existing row validation, CSV escaping/formula-injection protection, PDF
  two-observation threshold, and all existing non-empty output remain
  unchanged.
- Do not add sample rows, fabricated observations, fallback values, or a
  successful empty report.
- Do not touch Firestore rules, navigation, economy code, or unrelated docs.

## TDD steps

1. Add this behavior test to
   `test/services/research_data_exporter_service_test.dart`:

```dart
expect(
  () => service.generateCsvReport(const []),
  throwsA(isA<InsufficientData>()),
);
```

2. Run:

```powershell
flutter test test/services/research_data_exporter_service_test.dart test/services/research_report_pdf_exporter_service_test.dart
```

The new CSV test must fail before implementation.

3. Implement the shared error type and empty-list guard.

4. Run the same focused command and require all tests to pass.

5. Run:

```powershell
dart format --output=none --set-exit-if-changed `
  lib/services/research_export_errors.dart `
  lib/services/research_data_exporter_service.dart `
  lib/services/research_report_pdf_exporter_service.dart `
  test/services/research_data_exporter_service_test.dart `
  test/services/research_report_pdf_exporter_service_test.dart
flutter analyze
git diff --check
```

6. Commit only the listed research-export files:

```text
fix(research): reject empty CSV exports
```

## Report

Write the full implementation/TDD/self-review report to:

`C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-economy-lockdown\.superpowers\sdd\task-2a-research-report.md`
