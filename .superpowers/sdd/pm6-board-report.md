# PM6 pure Pair board handoff

Date: 2026-09-06

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`

Branch: `codex/pair-matching-pm0-pm8`

## Ownership and boundary

This dispatch implemented only the pure Standard Pair board renderer, local
Thai/English copy, and its focused tests. The renderer consumes immutable
`PairMatchingState` and `PairTimerState`, and emits typed lexical identities to
the host. It does not import a repository, coordinator, data adapter, evidence
writer, score policy, or research authority, and it does not decide
correctness, timer transitions, stars, evidence, or rewards.

Source ownership is released to `/root/pm6_implementation` after this report.
No further source edits are pending from this worker.

## Exact write set

Created:

- `lib/features/learning/pair_matching/presentation/pair_board_view.dart`
- `lib/features/learning/pair_matching/presentation/pair_matching_copy.dart`
- `test/features/learning/pair_matching/pair_board_view_test.dart`
- `test/features/learning/pair_matching/pair_board_accessibility_test.dart`
- `test/features/learning/pair_matching/pair_board_golden_test.dart`
- `.superpowers/sdd/pm6-board-report.md`

No existing or shared source file was edited. No golden image was generated.
The intended golden directory
`test/features/learning/pair_matching/goldens/pair_board/` does not exist yet;
generation and visual inspection remain with the parent.

## Stable API

- `PairBoardModel` requires `PairMatchingState state` and
  `PairTimerState timer`; optional fields are `busy`, `focusedTraversal`,
  `audioAvailable`, `statusMessage`, and `audioFallback`.
- `PairBoardView` requires `model`, `ValueChanged<PairTile> onSelectTile`,
  `ValueChanged<String> onRevealMapping`,
  `void Function(String, int) onConfirmGuidedMapping`, and
  `ValueChanged<PairTile> onPronounce`; `shellFeedback` is optional.
- `PairBoardView` implements `AccessibilityModeFeedbackSurface` and
  `withShellFeedback` preserves the model and every callback.
- Locale is read from `Localizations.localeOf(context)`.

## Implemented presentation behavior

- Both sides use `state.orderFor(side)` with stable side/word keys; matched,
  waiting, and guided tiles retain geometry as excluded-semantic placeholders.
- Regular layout uses balanced columns. Effective content width is centered and
  capped at 800 px. Standard-six tiles are at least 56 px and compact-four
  tiles are at least 64 px.
- Width below 360 px, text scale at least 200%, platform accessible navigation,
  or explicit `focusedTraversal` selects the linear source-to-target layout.
  One explicit activation emits one `PairTile`; the renderer never emits a
  prompt and target together. Returning to source selection emits only the
  already-selected tile so the canonical reducer can deselect it without an
  answer.
- Wrong, waiting repair, repair-ready, and guided states come only from the
  canonical attempt/support/repair projection. Guided confirmation is a
  separate button and forwards the exact `state.supportAtRevision[wordId]`.
- Timer display is read-only. Only exact 30-second and 10-second thresholds are
  live regions. Host status is a polite live region.
- Pronunciation is a neutral, user-initiated identity callback. Unavailable
  audio shows the supplied text/IPA fallback and never blocks completion or
  reveals an answer.
- Material 3 color roles, platform high contrast, reduced-motion durations,
  wrapping text, canonical semantic region order, keyboard activation, and
  48 px action conventions are preserved.
- FocusNodes are retained by side and word identity across resize, locale,
  layout, and unrelated state changes. After a match, focus moves to the first
  actionable unmatched prompt in canonical order. The explicit semantic node
  exports the same FocusNode's `focusable` and `focused` state; this fixed the
  earlier loss caused by excluding the button subtree semantics.

## TDD and verification evidence

The parent ran all Flutter commands serially; this worker ran no Flutter,
Dart, pub, format, generator, build, or golden command.

- `.superpowers/sdd/pm6-board-red.log`: expected RED from missing
  `PairBoardView`/`PairBoardModel`; it also exposed the initial missing
  semantics import.
- `.superpowers/sdd/pm6-board-green.log`: 6 passed / 4 failed. Root causes were
  the `dart:ui` semantics import, an off-screen guided button in the test, and
  `Chip` requiring unavailable Thai `MaterialLocalizations` in the test
  override.
- `.superpowers/sdd/pm6-board-green2.log`: 14 passed / 1 failed. It proved the
  explicit semantic node did not yet export FocusNode state.
- `.superpowers/sdd/pm6-board-green3.log`: 14 passed / 1 failed. Actual focus
  was `Tristate.isTrue`; the remaining failure was a test matcher comparing
  that enum to boolean `true`.
- `.superpowers/sdd/pm6-board-green4.log`: parent-run focused result is
  `+15: All tests passed!` for `pair_board_view_test.dart` and
  `pair_board_accessibility_test.dart`.

Final read-only checks found all five implementation/test files present, no
trailing spaces, and no `git diff --check` output. The files remain untracked
for parent integration. There is no task-owned running process.

## Remaining verification

- Compile and run `pair_board_golden_test.dart` with parent-owned golden update,
  then visually inspect all seven baselines: Thai standard-six, Thai
  compact-four, English reverse, long Thai at 200% narrow, wide bounded, dark
  high-contrast wrong/repair, and reduced-motion guided/no-audio.
- Exercise the board through the real PM6 host/coordinator and shell lifecycle;
  those files and checks are owned by the parent.
- Physical TalkBack, Switch Access, and device UAT remain Not Run. Automated
  semantics and keyboard coverage do not substitute for those external checks.
