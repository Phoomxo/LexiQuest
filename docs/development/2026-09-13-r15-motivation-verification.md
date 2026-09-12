# R15.8 motivation — local acceptance

Base: `74099324671cafc5c1160c49e059dab8bf56c958` (accepted R15.0–7).
Worktree: `C:/Users/Phet/.codex/worktrees/f9b7/LexiQuest`.
Branch: `feature/r15-motivation-continuation`.
Scope: approved R15.8 roadmap, spec MOT-01/motion contract, A-MOT-01–03.
Solo implementation/review; no other package started.

## Result and authority

- Existing Adventure result explains that recorded time/activity is effort,
  independent of learning results/mastery. Goal completion requires committed,
  nonempty quest receipts; a processed receipt with no quest is not success.
- Static Material face reaction follows recorded mission completion/rest.
  Reuses bundled Material Icons; no downloaded art, audio, animation timer,
  preference, modal, forced step, animation callback or reward writer.
- Inline reward amount appears only with accepted receipt identity and a
  provided canonical amount. Runtime lifecycle currently supplies status/ID
  without amount; it keeps truthful status instead of inventing a number.
  The known-amount branch is tested with a synthetic stored transaction.
- Existing learning/reward/quest/streak authorities, clock, owner isolation and
  frozen evidence contracts unchanged. No storage/research operations added.

## Acceptance

| Case | Evidence |
| --- | --- |
| A-MOT-01 | In-memory Drift reward row, accepted result, rebuild/two openings: one identical transaction/amount. Stateless view has no writer. Existing lifecycle, read-only receipt reader and reward sync tests pass. |
| A-MOT-02 | Effort time/activity labels and completion/rest reactions; confirmed nonempty quest-goal feedback plus empty-receipt negative regression. Existing dashboard preserves independent mastery/SRS/effort authorities. |
| A-MOT-03 | Reduced motion/no audio, immediate next action, no dialog/persistent animation. Real-font 390px light and 320px dark/high-contrast/200% tests reach all sections without overflow. Pair host tests retain terminal/replay/clock protections. |

119 distinct tests passed across seven targets by retaining unchanged passing
results and rerunning only affected targets. This is composed local evidence,
not a new single-command all-green integration/release run.

Flutter commands used `tool/cli/verify-scope.ps1 -Level Targeted -Area Learning
-TestTargets ...`; focused regressions used `-TestName` plain substrings.
Exact commands/fingerprints/timestamps are recorded by wrapper JSON. Untracked
log root is this worktree's `build/verification/` with common prefix
`74099324671cafc5c1160c49e059dab8bf56c958/`.

| Run | Result / elapsed | Log suffix |
| --- | --- | --- |
| Result `R15.8` RED | exit1, 0/2; missing amount/reaction | `d0c2bd44e6b5-32327d5919b5` |
| Focused GREEN | exit0, 2/2; 8.04s | `d0c2bd44e6b5-861557bb0a42` |
| `R15.8 empty` RED | exit1, 0/1; false goal success; 7.93s | `0f458786df45-94abf7148026` |
| Result/lifecycle/motivation-reader/Pair-host/dashboard/reward-sync | exit1, 114 pass/3 fail; 57.90s | `b91aaf41c25d-42f1d9b9568b` |
| Result recovery | exit0, 9/9; 9.85s | `074f541171ea-18669f8792c8` |
| Stored-transaction refinement | exit0, 1/1; 9.95s | `74eb9070f4b4-2704d64e230f` |
| Final result + accessibility/PNGs | exit1; result9/9, accessibility0/2; 9.88s | `578f2688e471-d23208da0fef` |
| Accessibility recovery | exit0, 2/2; 8.49s | `a264ab15f3b8-cfb185206ff1` |

Each suffix contains `Explicit-Flutter-tests.stdout.log` and stderr log.
Six-target run:108 passing tests outside result; relevant source never changed
afterward. Final result9/9 plus accessibility2/2 cover the remaining11.
Result reruns followed relevant fixture/assertion changes, not unchanged gates.

Recovery1: longer page lets ListView evict offscreen reward after scrolling to
next action. Return to receipt before the same assertions; none removed.
Recovery2 (independent): zero scheduled callbacks was checked immediately after
Material button tap. Navigation already occurred; settle standard ink response
before asserting no persistent animation. One correction per cause, resolved.

Final scope fingerprint:
`cfb185206ff1e9e8631ad93c23360b4828c0332f35ae6918bdbf39261c8f9076`.
Production file SHA256:
`59a818bee4b276e8d52f7dae108d8ed64f9e2c9987319f6a52a434b69e06e6cf`.
Result test verified SHA256 before final indentation-only formatting:
`9d188b1c92c2a2b0b5f33056a500e5883a28fc4fb32de741a5eea69826d6336a`.
Final formatted result test SHA256:
`776ae0191d1ba8fbdbcea672eb6992c775303494953c4eef082869c3eaccc0ec`.
Formatter also normalizes this previously CRLF-tracked test; reviewed with
`git diff --ignore-space-at-eol`. No semantic change or gate rerun needed.
Accessibility test SHA256:
`45dc70fb89d4d27f601f65385abc94b0870e00ae0dd460e12c819a0bec259f7a`.

Targeted `dart analyze` these3files: exit0/no issues,2.89s;
`build/verification/r15-motivation/analyze.log`. Focused diff check passed.
PNG export: `LEXIQUEST_R15_VISUAL_QA=1` on accessibility target. Ten screenshots
under `build/verification/r15-motivation/large-{false,true}-*.png`. Reviewed
full light reward/summary and dark200% effort/motivation: readable Thai glyphs,
wrapping, truthful state copy and scroll access, no overflow.

## Closure and limits

Local R15.8 accepted. No unresolved debugging or task-owned test/build process.
Generated registrants EOL-only/no content diff excluded; do not import.
No physical operation/APK build; combined UI source freeze/device checks remain
later. No human/physical/live-service/research/release acceptance claimed.
Token/credit usage unavailable. Commit only package files, then immediately
create R15.9 from exact accepted SHA and carry one-task/one-package through
R15.10. No writer overlap/default-branch start/pending import/full-history fork.
