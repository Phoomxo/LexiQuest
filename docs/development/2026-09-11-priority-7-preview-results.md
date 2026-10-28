# Priority 7 learning preview verification

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`.
Branch: `codex/pair-matching-pm0-pm8`. Preserve inherited changes.
User accepted priorities 1–6 as closed, including the 2:48:28 endurance run,
and requested priorities 7–12 sequentially. This document records priority 7;
it does not claim priorities 8–12 are complete.

## Implementation

`LEXIQUEST_LEARNING_PREVIEW=true` opts into the existing Pair Matching delivery,
ordinary Today and supported Focus Timer composition through AppBootstrap.
Default builds retain their existing behavior. Runtime emergency-off remains
authoritative; research and Adventure are not enabled by this preview.

The Learn entry now reaches the actual Pair setup and uses the packaged starter
content pins with canonical atomic start. Existing legacy checkpoint formats
retain their original renderer. Completed, presented Pair rounds can start a
fresh setup. The Pair coordinator pins completion time to database millisecond
precision before persisting the terminal checkpoint, fixing a real-clock failure
where a completed summary was rejected as changed.

## Evidence

Evidence directory: `build/verification/priority-7-20260911`.

- `regression-current.log`: 608 passed, exit 0. Bootstrap, production navigation,
  Pair, Today host and time-tracking suites. Follow-up changes after this run
  only add the deterministic clock test and braces to two equivalent conditions.
- `clock-regression.log`: 1 passed, exit 0. A clock containing microseconds
  completes, reloads the canonical summary, acknowledges presentation, reloads
  again, and retains one session.
- `preview-final.log`: 2 passed, exit 0, opt-in build. Real bootstrap to Learn
  entry, four-pair completion, stored result, return and fresh setup; capability
  composition and runtime emergency-off checks.
- `analysis-final.log`: zero errors/warnings, six inherited informational style
  findings in bootstrap/test code; analyzer exits 1 for these infos.
- Original red evidence: `activation-red-v2.log`, `route-red-v2.log`.
  `finish-diagnostic.log` captures the canonical timestamp mismatch. The first
  completion test also exposed a widget-test teardown timer, corrected by
  draining asynchronous disposal; no assertion was removed.

## Pending acceptance

APK build and physical vivo checks are still in progress. Component and widget
success do not substitute for those checks. No APK installation, microphone
quality result, external service quality result or production rollout is claimed
by the evidence above.

## Device findings and follow-up

The first opt-in manual APK (`e7d6cb2b4e6de8c35d7799481a09a51e9f86bd881d61e98c9511ea8b7184c873`)
was installed with verified provenance, without clearing existing app data.
On vivo V2041 it completed four pairs, displayed the result, returned to Learn
and reopened a fresh setup. Focus Timer started, paused at 17 seconds, resumed
and finished at 41 seconds. Today opened and its Review Center route worked.
Screenshots are under `build/verification/motivation-ui-20260908/device/manual-ui/priority7-*`.

This physical pass revealed two integration defects: MyApp had no Thai Flutter
localization, and bootstrap omitted History's existing Pair purpose reader.
The fixes configure Thai localization using the Flutter SDK delegates and inject
the authenticated reader. No session/purpose verification is weakened.

- `locale-red.log` then `locale-green.log`: actual MyApp defaults to Thai and
  the native Material back tooltip is Thai; the existing resume test still passes.
- `regression-thai.log`: 606 passed, three failed because Flutter's `pageBack`
  test helper searches for the English tooltip. Four calls were replaced by
  taps on the actual BackButton; `navigation-thai-green.log`: all 25 passed.
- `history-red.log` then `history-green.log`: actual bootstrap-to-four-pair
  route now loads exactly one authenticated history projection with four matches;
  the two opt-in tests pass.
- `history-bootstrap-regression.log`: 169 passed, exit 0, after the history fix.
- `analysis-history-final.log`: zero errors/warnings, six inherited style infos.

The first APK is superseded by the pending `*-thai-debug` artifacts. Physical
localization/history verification on those artifacts remains pending. No active
learning session is left in the first fixture: it is on the empty Review Center.

## Thai device pass and presentation follow-up

The Thai manual artifact (`717cbdad5588b4e7e9813a93e7c268fe1cd05fc21d52785175994c3f49fac9f3`)
completed six pairs on vivo, with Thai controls/Material tooltips and Thai result
copy. Today History displayed the same six independent matches, 3/3 stars and
91-second interactive duration (`priority7-thai-six-result` / `priority7-thai-history`).

Three display issues were then corrected: completed lesson progress is 100%,
terminal lessons do not expose a fresh Focus Timer start, and an authenticated
Pair result without a pack uses the label "Saved word set" rather than claiming
its content is unavailable. Pack-backed missing content keeps its unavailable
label. History replay without a composed replay callback remains unavailable.

- `regression-final.log`: 620 passed; the sole failure was the intentional
  completed-progress golden change. Reviewed master/test/diff images showed only
  the top progress strip changing. Both updated result goldens differ from their
  saved predecessors only within `(0, 0, 412, 4)`; no tolerance was relaxed.
- `golden-update.log`: one selected result/replay golden scenario passed.
- `app-shell-green.log`: all 24 passed, including normal golden comparison after
  generation. The additional MyApp navigation helper now taps BackButton; three
  equivalent integration core helper calls were adapted too (that native core
  journey was not rerun in this presentation pass).
- `history-presentation-green.log`: all 12 history screen tests passed. The
  initial new fixture incorrectly declared title-less pack content available;
  it was corrected to model the actual pack-less local-word session, preserving
  the domain validation.
- `preview-r2-final.log`: both opt-in bootstrap/route scenarios passed, including
  completed progress, no terminal timer widget and authenticated history result.
- `analysis-r2-final.log`: 14 touched items, zero errors/warnings, six inherited
  style infos. Analyzer exit 1 is due to these informational findings.

R2 artifacts built successfully with stable source evidence in
`ordinary-apk-v16-thai-r2/summary.json` and `manual-apk-v14-thai-r2/summary.json`.
Ordinary APK SHA256: `d7007317b8d6953067702ca2d8bb915f36805cac26c5427b4cb36df0bb232a40`.
Installed manual APK SHA256: `18dd1abb3d65dfba5e9f3e9a651c8db4827ebb652d8c96729710489585ccf13a`.
Both are archived under `build/verification/motivation-ui-20260908/device/`
as `lexiquest-learning-preview-v16-thai-r2-debug.apk` and
`lexiquest-learning-preview-manual-v14-thai-r2-debug.apk` respectively.

Final R2 physical check passed on vivo: four matches, 3/3 stars, 49 seconds,
100% completed progress, no terminal timer start, and Today History showing
the same result with `ชุดคำที่บันทึกไว้`. Evidence: manual-ui snapshots
`priority7-r2-result` and `priority7-r2-history`. Earlier checks cover six-pair
completion, fresh reopen, Today Review Center and timer start/pause/resume/finish.
Priority 7 is complete within the approved opt-in local preview scope. This is
not production rollout or history replay enablement. Proceed to priority 8.
No microphone capture or OEM log collection was started during priority 7.
