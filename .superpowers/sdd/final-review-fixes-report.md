# Stage 0 final-review fixes report

## TDD evidence

- Client writer contract RED: `quiz_score_persistence_regression_test.dart`
  reported three prohibited writers in `QuizService` and `UserService`.
  GREEN: the production-wide Firestore contract passed with only zero-valued
  legacy profile initialization and the default-disabled Shop debit allowlisted.
- Research PDF RED: population SD was `5.0` instead of sample SD `7.071`,
  malformed values returned statistics, and the report still said
  `participants`. GREEN: 8 focused research export tests passed with typed
  invalid-data failures, bounded finite values, paired-observation N, and
  explicitly labeled sample SD (`N-1`).
- Typed CSV RED: the requested typed row/error API was absent, malformed rows
  exported fallback values, RFC-4180 quoting/CRLF checks failed, and formula
  prefixes were emitted verbatim. GREEN: required typed rows, complete
  validation, CRLF records, comma/quote/newline escaping, and `= + - @`
  neutralization all passed.
- Safe navigation RED: Choose Mode and Settings contained no Export Center
  route and the title still claimed research data. GREEN: both production
  sources route to the sanitized Anki/PDF screen; widget/contract tests prove
  Anki/PDF presence and Research CSV/Thesis absence.
- Score lifecycle RED: `sessionId` was optional, persistence blocked the whole
  screen, and failures were collapsed into one English message. GREEN: 8 widget
  tests passed for immediate Thai rendering, record failure, post-write read
  failure, aggregate success, no repository, and repeated rebuilds.
- Bootstrap RED: the injectable loader API did not exist. GREEN: injected
  repository identity is retained and loader exceptions return a null
  repository without leaking exception text.
- Disabled economy RED: Achievements displayed reward wording and caller coin
  balances under the default-disabled policy. GREEN: focused and navigation
  tests show only device-local, non-spendable practice wording.
- Full-suite integration RED: adding the Settings export action overflowed its
  fixed Column, and an older navigation test expected disabled reward wording.
  Root cause was confirmed with focused widget runs. GREEN: Settings is
  scrollable and the integration expectation matches the required truthful
  title.

## Verification

- `dart format --output=none --set-exit-if-changed ...`: 18 files, 0 changed.
- `flutter test`: 618 tests passed.
- `flutter analyze`: no issues found.
- `git diff --check`: exit 0; only the pre-existing Windows EOL conversion
  warnings for generated plugin files and a few touched Dart files were shown.

## Self-review

- Firestore rules and `ShopPage` purchase/debit behavior were not modified.
- The local repository's storage format and idempotency implementation were not
  modified.
- Research CSV and Thesis Chart remain absent from production navigation.
- Score outcomes distinguish not saved, saved with snapshot, and saved without
  snapshot; per-session UI/navigation do not wait for persistence.
- Every displayed lifetime metric is explicitly device-local and non-spendable.
- Production/test changes are limited to the final-review brief plus requested
  CSV hardening. Generated-plugin EOL noise and this report remain uncommitted.

