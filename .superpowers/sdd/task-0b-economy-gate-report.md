# Task 0B — Economy Gate Report

## Scope

Implemented the Release A remote-economy safety slice in the assigned
`codex/release-a-economy-gate` worktree. Generated plugin registrants and
Firestore rules were not edited.

## RED evidence

1. Added the focused drawer, disabled-Shop, Settings, Achievements, Score,
   and static Firestore-mutation regression tests before changing production
   sources.
2. Ran:

   ```text
   flutter test test/screens/shop_page_test.dart test/screens/score_screen_test.dart test/screens/setting_screen_test.dart test/screens/quiz_score_persistence_regression_test.dart test/screens/production_shell_navigation_test.dart test/screens/achievements_screen_test.dart
   ```

3. The command exited `1` as expected. Failures identified the absent
   `ShopPage.onLoadData`, `ScoreScreen.sessionId` and `repository`, and
   `SettingScreen.profileData` seams; the new assertions also failed against
   the pre-change Shop CTA, drawer Shop entry, and Firestore mutation code.

## GREEN evidence

Implemented the smallest behavior needed to pass the tests:

- Added a constant, fail-closed `RemoteEconomyPolicy` and exposed it from
  `AppDependencies`; no Dart define or runtime-readiness condition enables it.
- Suppressed the production drawer Shop entry, made direct disabled Shop
  construction render an unavailable message before any product work, hid the
  Settings wallpaper selector, and removed the default Achievements Shop CTA.
- Wired `LocalProgressRepository` into production bootstrap. `ScoreScreen`
  records a supplied stable session once from lifecycle setup and renders the
  resulting local snapshot without Firestore work in `build`.
- Created the collision-resistant session ID in `QuizScreen.initState`, passed
  it and answer totals to `ScoreScreen`, and removed quiz completion writes.

Focused verification:

```text
flutter test test/screens/shop_page_test.dart test/screens/score_screen_test.dart test/screens/setting_screen_test.dart test/screens/quiz_score_persistence_regression_test.dart test/screens/production_shell_navigation_test.dart test/screens/achievements_screen_test.dart test/progress/local_progress_repository_test.dart
```

Result: exit `0`, `23` tests passed.

During full-suite verification, seven `AppBootstrap` tests initially failed
because the newly used SharedPreferences API requires a Flutter test binding.
The root cause was confirmed by the `ServicesBinding` stack trace at
`SharedPreferences.getInstance`. The test setup now initializes the binding
and in-memory preferences; the targeted bootstrap suite then passed `7/7`.

Final verification:

```text
flutter test
```

Result: exit `0`, `598` tests passed.

```text
flutter analyze
```

Result: exit `0`, `No issues found!`.

## Second reviewer follow-up: aggregate answer totals

### RED evidence

Added a successful-persistence widget test that seeds `10` correct and `6`
wrong answers, records a `4`/`2` session, and requires aggregate Correct
answers `14` and Wrong answers `8`. Updated all unavailable-path expectations
to the neutral `Local progress totals are unavailable.` copy.

Ran:

```text
flutter test test/screens/score_screen_test.dart
```

Result: exit `1`. The new test could not find `Correct answers`, and the
updated unavailable-message assertions could not find the prior wording.

### GREEN evidence

Successful persistence again renders the repository-provided total points,
games played, correct answers, and wrong answers. Unavailable persistence
continues to show only per-session results with the neutral totals-unavailable
message; its one lifecycle future and record-at-most-once guard are unchanged.

Ran:

```text
flutter test test/screens/score_screen_test.dart test/progress/local_progress_repository_test.dart test/screens/quiz_score_persistence_regression_test.dart
```

Result: exit `0`, `18` tests passed.

Final second-follow-up verification:

```text
flutter test
```

Result: exit `0`, `602` tests passed.

```text
flutter analyze
```

Result: exit `0`, `No issues found!`.

```text
git diff --check
```

Result: exit `0`, no whitespace errors.

## Files changed

- `lib/config/remote_economy_policy.dart`
- `lib/runtime/app_dependencies.dart`
- `lib/runtime/app_bootstrap.dart`
- `lib/screens/main_navigation_screen.dart`
- `lib/screens/shop_page.dart`
- `lib/screens/setting_screen.dart`
- `lib/screens/achievements_screen.dart`
- `lib/screens/quiz_screen.dart`
- `lib/screens/score_screen.dart`
- `test/runtime/app_bootstrap_test.dart`
- `test/screens/production_shell_navigation_test.dart`
- `test/screens/achievements_screen_test.dart`
- `test/screens/shop_page_test.dart`
- `test/screens/setting_screen_test.dart`
- `test/screens/score_screen_test.dart`
- `test/screens/quiz_score_persistence_regression_test.dart`

## Self-review

- `RemoteEconomyPolicy` has explicit false defaults for Shop/purchases and
  leaderboard, and no enablement source was added.
- Disabled Shop does not enter its loader; therefore it cannot read products,
  seed products, or render purchasing controls.
- The score screen contains no Firebase imports or counter writes, and quiz
  completion contains no Firestore increment operation.
- One ID is initialized for each quiz state instance and repository replay
  remains idempotent through the existing `LocalProgressRepository` contract.
- No code labels local counters as server-authoritative or spendable.
- Firestore rules and generated plugin files remain outside this change.

## Reviewer follow-up: persistence-unavailable state

### RED evidence

Added three focused `ScoreScreen` tests before changing production code:

- a repository whose `recordSession` throws;
- a repository whose `readSnapshot` throws after recording; and
- a screen with no injected or scoped repository, rebuilt after settling.

Ran:

```text
flutter test test/screens/score_screen_test.dart
```

Result: exit `1`. The three tests failed because the prior screen supplied an
invented per-session `ProgressSnapshot`, rendering `Total points` and `Games
played` without a truthful unavailable message.

### GREEN evidence

`ScoreScreen` now creates one lifecycle-owned persistence future, catches
record/read failures, and renders only the explicit per-session correct/wrong
result plus `Progress could not be saved locally.` when persistence is absent
or fails. It creates no future in `build`, shows no invented totals in that
state, and retains record-at-most-once behavior.

Ran:

```text
flutter test test/screens/score_screen_test.dart test/progress/local_progress_repository_test.dart test/screens/quiz_score_persistence_regression_test.dart
```

Result: exit `0`, `17` tests passed.

Final follow-up verification:

```text
flutter test
```

Result: exit `0`, `601` tests passed.

```text
flutter analyze
```

Result: exit `0`, `No issues found!`.
