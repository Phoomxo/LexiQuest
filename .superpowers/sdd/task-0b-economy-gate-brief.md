# Task 0B — Release A remote-economy safety gate

Worktree: `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-economy-gate`
Branch: `codex/release-a-economy-gate`
Base: `f66d0316daff57c83ed972a11f6425cb326f482a`

Implement the Stage 0 economy/progress safety slice with strict TDD.

## Required behavior

1. Add a fail-closed `RemoteEconomyPolicy` in `lib/config/remote_economy_policy.dart`.
   - `shopAndPurchasesEnabled` defaults to `false`.
   - `leaderboardEnabled` defaults to `false`.
   - It must not become enabled merely because Firebase is configured/ready or through a public client Dart define.
   - Expose it through `AppDependencies` with a safe default.
2. Thread the policy through production composition/navigation:
   - Default production drawer has no Shop entry.
   - `ShopPage` must also fail closed when directly constructed/navigated while disabled: show a truthful unavailable message, do not load Firestore data, seed products, or expose purchase buttons.
   - Hide the Settings wallpaper selector while the remote economy is disabled because it depends on purchased items/remote selected wallpaper state.
   - Remove/hide the Achievements copy/CTA that states the shop is active.
   - There is no current leaderboard implementation; keep its policy default false without inventing one.
3. Eliminate remote score mutation from the quiz completion path:
   - Remove the client Firestore aggregate write in `QuizScreen`.
   - `ScoreScreen.build()` must have no persistence/network side effect.
   - Record completion once from lifecycle initialization through the existing `ProgressRepository`/`LocalProgressRepository`.
   - Create one collision-resistant stable session ID at quiz-session initialization, retain it for the route lifetime, and pass it with correct/wrong counts to `ScoreScreen`.
   - Rebuilds or duplicate lifecycle calls must not double count; repository replay with the same session ID is idempotent.
   - Keep local result display, correct/wrong totals, games played, and navigation functional.
   - Do not call local counters server-authoritative or spendable.
4. Do not tighten deployed Firestore rules in this slice. The server-side client-write denial belongs to the later trusted-writer migration; remote economy UI remains closed meanwhile.

## Test-first acceptance

- Update `test/screens/production_shell_navigation_test.dart` so the default drawer omits Shop.
- Add focused `ShopPage` disabled-state coverage proving no product load and no Buy/purchase control.
- Add `test/screens/score_screen_test.dart` using an injected repository:
  - multiple pumps/rebuilds invoke `recordSession` once;
  - session ID and counts are passed correctly;
  - replaying the same session ID leaves totals unchanged.
- Add focused Settings/Achievements coverage proving remote economy controls/active-shop copy are absent by default.
- Preserve and run `test/progress/local_progress_repository_test.dart`.
- Add a focused static or widget regression proving `ScoreScreen.build()` and quiz completion no longer perform Firestore counter mutation.

## Global constraints

- Preserve unrelated local game mechanics, learning UI, and legacy constructor compatibility where reasonable.
- Do not edit generated plugin files.
- Do not modify or rebase `feature/associative-reading-loop`.
- No production code before witnessed failing tests.
- Run focused tests, format touched Dart files with `dart format`, run `flutter analyze`, and commit with a conventional message.
- Write full RED/GREEN evidence, files changed, commands/outputs, and self-review to `.superpowers/sdd/task-0b-economy-gate-report.md`.
- Return only status (`DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`), commit SHA, one-line test summary, and concerns.
