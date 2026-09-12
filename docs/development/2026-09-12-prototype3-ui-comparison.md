# Prototype 3: ALLTCAS + Duolingo direction

## Intent and references

User direction: combine useful layouts and interaction patterns from ALLTCAS and Duolingo into LexiQuest, preserving working structures. Keep the design flexible; do not rebuild every screen or adopt a different template for each feature.

ALLTCAS reference: actual screenshots previously inspected in `C:/Users/Phet/Downloads/Aiitcas`, indexed in `docs/superpowers/specs/2026-09-12-unified-learner-ui-draft.md`. These are iPad captures, not evidence of Android layout or performance. No reference artwork is copied into shipped assets.

Duolingo primary reference: [Building character](https://blog.duolingo.com/building-character/) describes shared visual language and animation tied to correct answers. [Core tabs redesign](https://blog.duolingo.com/core-tabs-redesign/) informs consistency across destinations. Proposed LexiQuest timings below are design starting points, not timings measured from Duolingo.

## Combined design direction

| Surface | Pattern for LexiQuest | Status |
| --- | --- | --- |
| Learning activity selection | ALLTCAS-inspired clear groups, two-column cards, centered icon and short title, consistent spacing | Implemented first comparison |
| Narrow screen / large text | One column, natural card height, scroll to every available activity | Implemented and widget checked |
| Main menu | Compact heading, clear close action, preserve existing destinations | Implemented; full drawer visual comparison still needed |
| Shared visual style | Existing blue identity, Thai typeface, softer card outlines, left-aligned default page titles | Implemented in common theme; local overrides remain |
| Correct / incorrect feedback | Duolingo-inspired explicit result and small purposeful movement | Audited and specified below; not implemented |
| Rewards / progress | Reuse same heading, spacing, cards and buttons; celebrate earned outcomes only | Existing behavior checked; visual consolidation remains |
| Reading | Left-aligned paragraphs with readable line spacing; centered artwork only where useful | Audit remains; do not center long reading text |

Consistency means shared typography, spacing, colors and controls. It does not mean forcing a reading page, settings list and game board into an identical grid. Preserve existing mode availability and real progress; do not invent a linear learning path or synthetic rewards to imitate reference screenshots.

## Runtime comparison

Actual Flutter captures, same fixture and dimensions, rendered at 2x:

- Before: `build/verification/minimal-ui-20260912/prototype2-390-text100-light.png`
- After: `build/verification/minimal-ui-20260912/prototype3-final-390-text100-light.png`
- Before large text: `build/verification/minimal-ui-20260912/prototype2-320-text200-dark.png`
- After large text: `build/verification/minimal-ui-20260912/prototype3-final-320-text200-dark.png`

Opened and inspected before/after normal and after large-text images. The new normal layout exposes more choices with less introductory text, centers icons consistently, and removes SRS from navigation labels. Long Thai names still wrap; odd-sized groups leave a final empty column. Larger text remains readable but requires more scrolling. These are visible tradeoffs, not a human usability finding that Prototype 3 is better.

Fixture has no runtime dependencies, so it does not show the production starter panel, outer shell, or all gated activities. It is not a vivo capture. No new APK has been built or installed for this comparison.

## Matching findings and proposed sequence

`pair_board_view.dart` replaces matched tiles immediately with a placeholder. Its 100 ms selected-state animation does not animate that replacement. Hidden state also includes repair/support states; hiding is not always success. Existing incorrect-answer feedback already uses text, an icon and a live region.

| State | Proposed visual response | Behavior constraint |
| --- | --- | --- |
| Selected | Clear border / pressed state | Keep current selection rules |
| Accepted correct pair | Show check and “จับคู่ถูกแล้ว”, then fade the two tiles | Disable repeat taps immediately; preserve other tile positions |
| Incorrect | Keep readable feedback and retry/help action | Respect existing repair rules; do not silently reset the learning engine |
| Final accepted pair | Finish feedback before visually transitioning to results | Do not delay durable result recording or create another completion |
| Reduced motion | Immediate state transition with explicit text and icon | Keep the same meaning without relying on movement or color |

Starting motion proposal: roughly 180 ms fade for the current Pair board, after a perceptible confirmation hold to be tuned on device. Legacy Matching removes rows and reflows the list, so it may need fade plus size transition instead. Do not apply row collapse to the current Pair board. Keep animation out of the answer clock, evidence, rewards and persistence logic. Remove outgoing cards from pointer, keyboard focus and semantics immediately. Check owner changes so the transition never retains another account's content.

Next implementation checks: intermediate correct frame, wrong/support not styled as success, final-pair transition, no duplicate submissions, reduced motion, and existing focus/semantics coverage.

## Remaining consistency work

- Local centered headers and hard-coded colors in CEFR reader/selection and some activities override the common theme.
- SRS flashcard page still contains “ทบทวน SRS”; navigation wording is already changed, internal page wording still needs consolidation.
- Main shell runtime banner plus child app bar can still produce a double header.
- Rewards and the full drawer need actual screenshots under the same account/theme/text scale before claiming a unified system.
- Long activity names and odd-column groups need further visual refinement.

This checkpoint completes the first layout comparison, not the entire UI migration or Matching animation implementation.

## Verification and handoff

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch: `prototype-3-minimal-ui`, based on `ccf29d670f48c3536c630cfff8935ba9c2c6c08d`.

- Final focused suite: **146 passed**, exit 0. Command: `flutter test --no-pub --concurrency=1 --dart-define=UI_CAPTURE_PHASE=prototype3-final test/screens/minimal_ui_comparison_test.dart test/config/m3_theme_test.dart test/navigation/navigation_glossary_test.dart test/architecture/thai_navigation_glossary_boundary_test.dart test/screens/choose_mode_screen_test.dart test/screens/main_navigation_screen_test.dart test/screens/learning_pack_detail_screen_test.dart test/screens/profile_settings_screen_test.dart test/screens/production_shell_navigation_test.dart test/screens/achievements_screen_test.dart test/screens/mastery_dashboard_screen_test.dart --reporter expanded`.
- `flutter analyze --no-pub` on all 12 changed Dart files: **No issues found**, exit 0.
- Logs: `build/verification/minimal-ui-20260912/final-tests.log` and `analysis.log` (ignored local verification outputs).
- Earlier 3 failures were stale test assumptions: removed SRS whitelist entries and ListTile changed to InkWell. Corrected exact expectations without weakening retained-callback safety assertions; focused recovery passed 48 tests before the final 146-test run.
- `git -c core.whitespace=cr-at-eol diff --check` passes, allowing existing Windows line endings without rewriting unrelated files.
- No full repository suite, new APK, vivo install, human usability, or human TalkBack test in this checkpoint. Flutter test/analyze processes finished; no task-owned verification process remains running.

Changed production files: common theme, navigation glossary, Learn activity selector and main drawer. Associated tests, capture fixture, this report and the implementation plan accompany the change. No Matching production code changed in this checkpoint.

Next executable step: implement and test explicit accepted-pair confirmation and outgoing tile feedback in the existing Pair renderer, preserving placeholder position, focus, reduced motion, final-result lifecycle and recording boundaries; then consolidate internal page headers and capture full shell/menu/rewards for comparison.
