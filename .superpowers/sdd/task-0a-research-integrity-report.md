# Task 0A — Research Integrity Evidence

## Scope

Implemented the Release A research-integrity gate in
`codex/release-a-research-integrity` from base
`f66d0316daff57c83ed972a11f6425cb326f482a`.

## RED evidence

1. Added focused contracts before changing production code:
   - `test/services/research_report_pdf_exporter_service_test.dart`
     - Empty observations must throw typed `InsufficientData`.
     - Statistics and report fields must come from typed observations.
     - Report must not contain p-values, expected significance, or a t-test claim.
   - `test/screens/thesis_chart_screen_test.dart`
     - Caller-supplied score values must appear in chart labels.
     - Constructor parameters must be required and contain no fabricated defaults.
   - `test/screens/research_integrity_navigation_contract_test.dart`
     - Choose Mode and Settings must not expose Export Center/Thesis routes.
     - Export Center must not offer the sample Research CSV path.

2. Ran:

   ```text
   flutter test test/services/research_report_pdf_exporter_service_test.dart test/screens/thesis_chart_screen_test.dart test/screens/research_integrity_navigation_contract_test.dart
   ```

   Result: exit 1, as expected. The service test failed to compile because
   `ResearchObservation` and `InsufficientData` did not exist and the service
   still accepted `List<Map<String, dynamic>>`. The chart test failed because
   the rendered labels were `Pre-Test (52%)`/`Post-Test (88.5%)` and the
   constructor still had defaults. Navigation/export contracts failed because
   production sources still contained `ExportCenterScreen`, `ThesisChartScreen`,
   `Research CSV`, `_generateResearchCsv`, and `ResearchDataExporterService`.

## GREEN implementation

- Added typed `ResearchObservation` input and typed `InsufficientData` exception.
- Rejects fewer than two observations; no sample/fallback statistics remain.
- Derives every displayed report value from supplied observations: means,
  population standard deviations, score-point gain, average latencies, and latency change.
- Removed significance, p-value, and t-test claims from the report.
- Made all `ThesisChartScreen` data required and derived axis labels from its values.
- Removed Choose Mode and Settings navigation to research outputs.
- Removed Export Center's Research CSV segment, sample records, and research CSV service use.
- Preserved Anki and PDF glossary export behavior.

## Files changed

- `lib/services/research_report_pdf_exporter_service.dart`
- `lib/screens/thesis_chart_screen.dart`
- `lib/screens/choose_mode_screen.dart`
- `lib/screens/setting_screen.dart`
- `lib/screens/export_center_screen.dart`
- `test/services/research_report_pdf_exporter_service_test.dart`
- `test/screens/thesis_chart_screen_test.dart`
- `test/screens/research_integrity_navigation_contract_test.dart`
- `.superpowers/sdd/task-0a-research-integrity-report.md` (this scratch evidence file; intentionally not committed)

## Verification commands and outputs

```text
flutter test test/services/research_report_pdf_exporter_service_test.dart test/screens/thesis_chart_screen_test.dart test/screens/research_integrity_navigation_contract_test.dart
```

Result: exit 0; `+7: All tests passed!`

```text
dart format lib/services/research_report_pdf_exporter_service.dart lib/screens/thesis_chart_screen.dart lib/screens/export_center_screen.dart lib/screens/choose_mode_screen.dart lib/screens/setting_screen.dart test/services/research_report_pdf_exporter_service_test.dart test/screens/thesis_chart_screen_test.dart test/screens/research_integrity_navigation_contract_test.dart
```

Result: formatted the 8 touched Dart files.

```text
dart format --output=none --set-exit-if-changed lib/services/research_report_pdf_exporter_service.dart lib/screens/thesis_chart_screen.dart lib/screens/export_center_screen.dart lib/screens/choose_mode_screen.dart lib/screens/setting_screen.dart test/services/research_report_pdf_exporter_service_test.dart test/screens/thesis_chart_screen_test.dart test/screens/research_integrity_navigation_contract_test.dart
```

Result: exit 0; `Formatted 8 files (0 changed)`.

```text
flutter analyze
```

Result: exit 0; `No issues found! (ran in 7.3s)`.

```text
git diff --check
```

Result: exit 0; no whitespace errors.

## Self-review

- [x] No production navigation remains to Export Center or Thesis Chart from Choose Mode/Settings.
- [x] Research report data is typed and caller supplied; empty/insufficient data fails explicitly.
- [x] No fallback sample size, score, gain, latency, p-value, or expected-significance claim remains in the report service.
- [x] Thesis chart has no fabricated defaults and its score labels derive from supplied values.
- [x] Export Center no longer presents a sample Research CSV path; Anki/PDF exports remain.
- [x] Generated plugin files are untouched by this task and excluded from the commit.
- [x] The required evidence report remains uncommitted scratch content.

## Environment note

Flutter dependency resolution reported eight outdated/incompatible package updates, but both focused tests and analysis completed successfully. This task does not alter dependencies.

## Reviewer follow-up — zero latency and score-decline integrity

### RED evidence

Added two regression cases to
`test/services/research_report_pdf_exporter_service_test.dart` before changing
production code:

- `calculateAcademicStats rejects a zero pre-test latency baseline`
- `generateAcademicPdfReport formats a score decline with one sign`

Ran:

```text
flutter test test/services/research_report_pdf_exporter_service_test.dart
```

Result: exit 1, as expected. Exact failing assertions included:

```text
Expected: throws <Instance of 'InsufficientData'>
Actual: <Closure: () => ThesisAcademicStats>
Which: returned <Instance of 'ThesisAcademicStats'>
```

and:

```text
Expected: contains 'Mean Score Change: -10.0 percentage points'
Actual: '... - Mean Score Gain: +-10.0 percentage points ...'
```

### GREEN implementation

- A zero mean pre-test latency baseline now throws the typed `InsufficientData`
  exception with a precise message rather than emitting a fabricated `0%`
  latency change.
- The report field is now neutral (`Mean Score Change`) and uses a sign-aware
  formatter: positive values receive one `+`, negative values retain their
  one `-`, and zero is unprefixed.

### Follow-up verification

```text
dart format lib/services/research_report_pdf_exporter_service.dart test/services/research_report_pdf_exporter_service_test.dart
```

Result:

```text
Formatted 2 files (0 changed) in 0.01 seconds.
```

```text
dart format --output=none --set-exit-if-changed lib/services/research_report_pdf_exporter_service.dart test/services/research_report_pdf_exporter_service_test.dart
```

Result:

```text
Formatted 2 files (0 changed) in 0.01 seconds.
```

```text
flutter test test/services/research_report_pdf_exporter_service_test.dart test/screens/thesis_chart_screen_test.dart test/screens/research_integrity_navigation_contract_test.dart
```

Result: exit 0; `+9: All tests passed!`

```text
flutter analyze
```

Result: exit 0; `No issues found! (ran in 4.2s)`.

### Follow-up self-review

- [x] No numeric latency change is emitted when its zero baseline makes it undefined.
- [x] A score decline is described neutrally and has exactly one negative sign.
- [x] The two contracts were observed failing before the production fix and passing after it.
