# Stage 0 final-review fixes

Worktree: `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-integrity-gate`
Branch: `codex/release-a-integrity-gate`
Current base: `04e2f8f2183e15bf01cf4d10e98b84e9d2d75f7c`

Resolve all release-blocking broad-review findings in one TDD task.

## 1. Remove remaining client score writers

- Remove `QuizService.savePointsToFirestore`.
- Remove `UserService.updateUserPoints`.
- Remove caller-controlled initial points from `UserService.saveUserData`; newly created profile data may only initialize the legacy field to zero.
- Do not change Firestore rules or the default-disabled purchase debit in `ShopPage`.
- Replace the narrow screen-only static test with a production-wide architectural contract that fails on client score/reward writers outside an explicit default-disabled `ShopPage` purchase-debit allowlist.

## 2. Validate every research export input

- `ResearchReportPdfExporterService` must reject every observation containing:
  - non-finite values;
  - pre/post scores outside 0–100;
  - pre/post latency that is not finite and strictly positive.
- Keep typed `InsufficientData` for too few observations; use a typed invalid-data error for malformed observations.
- Label N as paired observations, not participants.
- Calculate and explicitly label sample standard deviation (`N-1`), not unlabeled population SD.
- Replace `ResearchDataExporterService` map/fallback API with required typed rows. No default CEFR, latency, accuracy, SRS box, or current timestamp.
- Validate nonblank bounded word, CEFR A1–C2, finite positive latency, accuracy 0–100, bounded SRS box, and UTC timestamp. Add missing/invalid-value tests.

## 3. Restore safe exports, keep research outputs unavailable

- Restore production navigation from Choose Mode and Settings to the sanitized `ExportCenterScreen`.
- Keep Thesis Chart absent from production navigation.
- Keep Research CSV absent.
- Rename Export Center title/copy so it mentions only vocabulary/Anki/PDF glossary, not research data.
- Add widget/contract coverage proving Anki/PDF Export Center is reachable and Research CSV/Thesis are absent.

## 4. Truthful, non-blocking ScoreScreen lifecycle

- Make `sessionId` required. It is generated only by the quiz-session owner.
- Render the per-session result, app bar, and navigation immediately; persistence must not block the whole result screen.
- Model three distinct outcomes:
  - not saved (no repository or `recordSession` failed);
  - saved with aggregate snapshot;
  - session saved but aggregate snapshot unavailable.
- Display truthful Thai messages for each outcome. Never claim a failed write succeeded or a successful write failed.
- On success, show all four aggregate metrics and explicitly label them as device-local, non-spendable practice progress.
- Restore the established Thai result labels, gradient app bar, buttons, and card styling while keeping persistence outside `build()` and at-most-once.
- Test initial non-blocking rendering, write failure, read-after-write failure, success aggregates, and repeated rebuilds.

## 5. Fail-soft local repository bootstrap

- Add an injectable progress-repository loader/factory to `AppBootstrap`.
- Production loader wraps `SharedPreferences` in `LocalProgressRepository`.
- If loader/storage initialization throws, `AppBootstrap.initialize()` must still return with `progressRepository == null`; no exception/credential text may leak.
- Add focused bootstrap tests for success and failure.

## 6. Close misleading economy/ownership presentation

- When remote economy is disabled, `AchievementsScreen` must not show the fabricated/default 250-coin balance or reward/shop currency messaging.
- Device-global aggregate progress may remain only if every lifetime metric is explicitly labeled device-local practice progress and non-spendable; do not imply authenticated-user ownership.
- Add tests for the default-disabled messaging.

## Constraints and verification

- Strict RED → GREEN for each behavior; record the witnessed failures.
- Preserve default-disabled Shop behavior and local repository idempotency.
- Do not modify Firestore rules.
- Do not stage generated plugin files or `.superpowers` scratch files.
- Preserve current checkout/worktree line-ending noise as uncommitted.
- Run focused tests, full `flutter test`, `flutter analyze`, formatting, and `git diff --check`.
- Commit the complete fix with a conventional commit.
- Write RED/GREEN evidence and self-review to `.superpowers/sdd/final-review-fixes-report.md` but keep it uncommitted.
- Return only status, commit SHA, verification summary, and concerns.
