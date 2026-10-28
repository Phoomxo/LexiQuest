# R15.2 local verification

Timers change transient UI only. Final terminal persistence precedes animation;
summary receipt follows a rendered frame. Heading receives keyboard focus.

## Evidence
JSON records below are in build/verification/3e586dc24d34ca5103b4f3090a70bf26ad8e5916/.
Read each for its command/source log paths; counts overlap and must not be added.

- 88 selected host/feedback/board/accessibility/golden/theme checks passed before
  final heading change; 57s runner time.
  targeted-learning-5b446b9a24f3c195b341aa6cdd399eaa31db7cdd8454addd9833509250d7e7aa.json
  Source: 4aa4427127db9370d8709d88c7bdec537686267f94fa0638c035e5d042f25a0f.
- Affected host/result suite after heading change: 48 passed, one new overlap
  assertion failed because pumpAndSettle serialized the fixture's episodes; 55s.
  Includes the strengthened 449ms/600ms check.
  targeted-learning-0a88b3fee72c591e44dcff5db639186a69f96cfda58b1d3eae5c4b255e7313f2.json
- Corrected fixture waits only for enabled input. Both final scenarios passed,
  checking overlapping episodes, terminal durability, focus and reopen; 14s.
  targeted-learning-ac86ec1da4fb89f3a4f3427f4ae1f40912f6f7752090690f310aa3b75df61510.json
  Source: 659f2496b14d21a2945f3a73003e98a9a91dc84545945e75dbfbd9af703529dc.
  Command: verify-scope.ps1 Targeted/Learning with host TestTargets and
  -TestName 'R15 final pair'.
- Final bounded dart analyze: six changed production files plus host/feedback
  tests, no issues, exit0; build/verification/r15-pair-analysis.log.
- PowerShell runner contract passes target/filter selection, dependency coverage,
  missing target rejection and requiring explicit targets for name filters.

A-PAIR-01 timing/persist; 02 wrong repair; 03 assisted copy/role; 04 final
durability; 05 duplicate input/state; 06 dispose/owner cancellation; 07 reopen;
08 reduced motion/focus; 09 overlapping rapid pairs have automated coverage.
Session/round identity guards were also reviewed. Existing Review navigation and
authoritative active-clock tests remain intact.

## Visual and outstanding acceptance
Eight synthetic full-Scaffold captures: build/verification/r15-pair-visual/,
correct/wrong/support/final at 390px light/scale1 and 320px dark/scale2.
Thai fonts/icons, contrast >=4.5 and no overflow checked. Representative corrected
surfaces reviewed; long narrow content scrolls. These are widget captures.
Vivo, human TalkBack and release acceptance remain for combined source freeze.
No APK installed here; local completion does not claim these external results.

Reruns addressed changed code or demonstrated fixture errors; unchanged passed
cases were reused. Actual model tokens/credits per package are unavailable.
