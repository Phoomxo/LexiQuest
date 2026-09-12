# R15.3 local implementation and verification

Starting source: 3a4c282f87ed72a53eaf0153cbe611a144088fa8.
Worktree: C:/Users/Phet/.codex/worktrees/1e15/LexiQuest.
Branch: feature/r15-continuation. This report accompanies the package commit.

## Implemented / reviewed

- A-NAV-01/02: primary styling follows the canonical section subsequence and
  usable dependencies; assigned assessment remains visible when authority is
  valid. Corrupt assessment dependency cannot offer launch.
- A-NAV-03: stale/corrupt/unavailable resume cannot launch; inconsistent
  recommendation is hidden; unusable review rows are not forwarded, while
  ordinary Review Center remains reachable. Preserve specific stale-reason copy.
- A-NAV-04 / UI-10: catalog search, actual level/topic filters, separate empty
  catalog / search miss / filter miss, clearing and toggling recover results.
  Existing pinned revision and live feature gate retained.
- A-NAV-05: existing owner replacement/captured-callback and production navigation
  coverage retained in the affected suites. No owner storage or new writers.
- UI-05/06/08: Today and Choose content max960, responsive outer16/24, SafeArea;
  mode grid1 below360 or scale>=1.5, otherwise2 below840 and3 at840+.
- T-01: existing primary card precedes the new manual-practice route. The route
  opens the existing Choose screen without creating a learning session.
- A-UI-01/02/03/05: viewport/theme/text matrices, keyboard/system insets, keyboard
  primary->manual focus, actual role contrast>=4.5 without rounding, catalog
  clear target>=48, final action reachability and navigation checked.

Catalog retains its existing metadata list (UI-07): level/topic/skill/goal/pinned
revision are comparative metadata. No invented word/progress count or path.
Before/after real Flutter images support this decision. Test-only write-set
extension: test/support/r15_visual_capture.dart supplies font loading and capture.
Today source was normalized from CRLF to LF during baseline capture restoration;
the whitespace-insensitive diff was reviewed. No business changes outside R15.3.

## Final command evidence

All logs below are under build/verification/3a4c282f87ed72a53eaf0153cbe611a144088fa8/.
Command JSON summaries may be replaced by later runs with the same selection;
these command/source log directories are immutable evidence.

1. verify-scope.ps1 -Level Targeted -Area Learning -TestTargets
   test/screens/learning_pack_catalog_screen_test.dart,
   test/screens/today_hub_screen_test.dart,test/screens/choose_mode_screen_test.dart,
   test/screens/main_navigation_screen_test.dart,
   test/screens/production_shell_navigation_test.dart
   PASS 180 checks; runner39.7s, Flutter35s; exit0.
   Log: 30e2fc269a1a-f37e85cf0f48/Explicit-Flutter-tests.stdout.log.
   Source fingerprint: f37e85cf0f48 (full value in selection JSON
   targeted-learning-1b35fdb6692c603455838aaad9d4cc45daa4deb19f03fd109d7655427c106d08.json).

2. Same runner, three changed screen test files, -TestName 'visual ':
   PASS26; runner10.8s, Flutter6s; exit0 after capture-helper-only correction.
   Log: 44cb8f4a6aad-fafe00f62f4d/Explicit-Flutter-tests.stdout.log.
   No runtime source changed after the 180-check run. Counts overlap; do not sum.

3. dart analyze the three changed runtime files, their three test files and
   test/support/r15_visual_capture.dart: exit0, no issues, about6.3s.
   Log: build/verification/r15-layout-analysis-final.log.
   Diff whitespace check passed with core.whitespace=cr-at-eol for existing CRLF.

## Regression and recovery evidence

- Search RED: missing TextField (23ecdd02300f-01ea68584767).
- Canonical-primary RED: ignored section subsequence
  (705585a5868a-37972bf8ebe0).
- Invalid dependency REDs: resume callback, recommendation launch, assessment
  launch persisted despite unusable dependencies. Final suites cover rejection.
- Mode840 RED: expected3 / actual2 (2e12b5393d54-4e50c4aebd4e).
- Wide/safe-area RED: expected<=960 / actual1200
  (371e5dcaee65-507c4fbea384); final checks pass.
- Filter mismatch RED: wrong search copy (23ecdd02300f-f4d8f6ebe592).
- Fixture corrections: valid canonical subsequence (model rejects reordering);
  scroll to actual end before keyboard-boundary assertion; measure clear button
  before it scrolls offscreen; manual route fixture has no starter adapter, so
  assert actual Choose route and quiz tile; scroll history before tapping.
- A combined TestName using regex ran no tests: runner uses a plain substring.
- One suite PNG omitted the resume layer although isolated capture rendered it.
  Capture helper now repaints retained child layers before toImage. Only the
  26 visual cases reran; final affected images were inspected, with card/button
  pixel presence additionally checked. No runtime workaround was added.

## Visual evidence / limitations

build/verification/r15-visual/{before,after}/ contains real Flutter PNGs from
synthetic fixtures using NotoSansThai and MaterialIcons:
T01 and T02-mode widths320/390/840 x scales1/2 x light/dark;
catalog T02 widths320/840, scale2/dark. Catalog keyboard matrix additionally covers
all12 width/scale/theme cases. Filenames encode template/viewport/scale/theme.
Before captures render committed baseline source; after captures render this
package source. Representative narrow200/dark, regular390/light and wide840
surfaces opened and reviewed. Wide1200/system34 checks are widget assertions.

Local R15.3 implementation is ready for the next package. Physical Vivo,
TalkBack, human usability and release acceptance are NOT established.
Combine UI packages before a frozen-source Android build/device run as approved.
R15.4–10 remain outstanding; do not rerun R15.2 or unchanged passed gates merely
for a new task/commit. Preserve approved8/44 and frozen evidence contracts.
No purchase, deployment, push/merge, enrollment or real upload occurred.
Actual model token/credit usage unavailable.
