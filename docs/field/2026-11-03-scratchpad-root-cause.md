# Scratchpad root-cause investigation

Worktree `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`, branch
`codex/remaining-system-readiness`, baseline `d36f09be`.

## Intent and acceptance

Explain and reproduce the historical Typed Cloze Save hit-test failure, correct
the demonstrated cause, and verify the same mechanism repeatedly on Android.
Passing unrelated repeats alone does not close this task. Preserve typed-answer
ACK, frozen ink, owner/session scope, undo/clear and optional handwriting.
Cloud A/Billing, real payments/provider, physical Vivo, public rollout and real
Research enrollment/upload remain excluded. Use only task AVDs and synthetic data.

## Bug-fix workflow and cards

1. Reproduce it yourself on the matching surface via the control skill.
   Done. Root reproduced the late-keyboard Save failure on host and Android.
2. Binary-search the cause.
   Done. Controlled settled/late keyboard cases isolate the caret/layout race.
3. Plan the fix.
   Done: settle frames before the test helper taps Save. Production behavior
   is unchanged. The implementation agent owned only the Scratchpad test file.
4. Verify on the same surface.
   Done. Host regression and Android controlled probes fail before the fix;
   51 host tests and 66 Android executions pass after the fix.
5. Stage the commits so the failing repro lands before the fix in git history.
   Done: `3ba154fb` records the clean failing regression, followed by the
   verified helper correction in `ce1d0838`.
6. Run Opening a PR.
   Skip remote PR/publication for this local investigation and deliverable.
   The reviewed correction is committed locally. The report links local logs.

Throughput checkpoint: two read-only investigation slices run concurrently.
Root alone runs Flutter/build/ADB and writes this plan. No source writers until
the cause is supported. Before integrated checks, freeze implementation writers.
Preserve all pre-existing untracked critiques and failure artifacts.

## Evidence and decisions

- Apply Fix Root Causes. Recover the exact old failure and synthesize its trigger
  before proposing a production or harness fix. A hypothesis is not a diagnosis.
- Historical baseline: `synthetic-tests.log` failed the frozen-ink Save hit-test;
  later bounded repeats passed. No production Scratchpad fix was claimed.
- Evidence directory:
  `D:/LexiQuest-Storage/maintenance/2026-11-03/scratchpad-root-cause/`.
  The local append-only decision trail is `decisions.tsv` in that directory.
- Invalid 107dp geometry produced overflows, but Save was hit-testable. This does
  not reproduce or establish the cause of the historical Save failure.
  `native-original-480.log` is a failed environment experiment, not a release test.
- With physical 320x640 and density 160, the original frozen-ink test passed.
  The choice test failed because it read a meaning cue after scrolling it out
  of the lazy ListView. Revealing the cue and selected option fixes that test
  assumption. Both accepted Cloze cases pass in `native-causal-red.log`.
- `host-causal-probe-2.log` and `native-causal-red.log` each show a settled-keyboard
  control passing and two delayed-keyboard probes failing. The focused input's
  `showOnScreen` scroll moves the list back after `ensureVisible(Save)`.
  On Android, the following-frame trace moves offset 472 to 316 while the
  viewport shrinks to y=80..360. Save becomes unbuilt and not hit-testable.
- Temporary instrumentation is preserved in `causal-instrumentation.patch` and
  removed from source. The final regression retains the settled control and
  the first-frame metric case. The extra following-frame probe queued a callback
  without scheduling a frame, so it is not retained as a separate regression.
- `host-regression-red.log` confirms the clean test fails in `_reveal -> _tap`
  with `Found 0 widgets with key [<'cloze-save'>]`, offset 480 and inset 280.
  The settled control passes. No answer is dispatched before either probe.
- The historical one-off log has no metric trace. The new controlled runs prove
  a matching failure mechanism in the unchanged helper; they cannot recover
  the exact timing of that earlier event.

## Fix design

The test helper combines a lazy-list reveal and one layout frame, while Android
keyboard metrics and Flutter's caret reveal can still change the scroll offset.
Settle pending frames only before `_tap(_save)`, then use the existing reveal,
hit-test and actual pointer tap. Keep the five-second timeout explicit.

Do not settle every `_reveal` call: the frozen-ink test deliberately holds the
answer ACK while an indeterminate progress indicator runs. That test must still
reach the canvas and prove that retained Undo/Clear and pointer input cannot
change frozen ink. No production focus, persistence, scoring or ink code changes
are justified by the reproduced test-driver race.

Independent design review rejected a generic settling loop and a production
`unfocus` change. Comment review found no added comments or suppressions.

## Verification

- `host-green.log`: all 51 tests in `typed_cloze_scratchpad_test.dart`,
  `handwriting_scratchpad_test.dart` and `fill_in_the_blanks_screen_test.dart`
  pass after the fix. This includes the two controlled cases, frozen ACK,
  lost ACK retry, pointer limits, owner/session loss and Thai/English large text.
- `native-green-repeat.log`: all 66 executions pass on `LexiQuest_Synthetic_API35`, serial
  `emulator-5556`, physical 320x640, density 160. The controlled cases override
  their view to 360x640/DPR1/inset280 on both host and Android. Native input and
  synthetic typed-answer database operations remain active.
- The 66 executions are 22 distinct scenarios repeated three times: all 20
  Scratchpad screen cases plus the original accepted typed/choice Cloze cases.
  This is not 66 distinct features or whole-app acceptance. Each round includes
  frozen ACK, lost ACK, nine owner/session/lifecycle losses, fresh-attempt ink,
  optional ink, Undo/Clear, Thai/English large text and both causal controls.
- Independent GPT-6-astra review accepts the two-file code diff with no must-fix.
  Its follow-up confirms all 22 scenarios appear in each of the three passing
  Android rounds and that the two source hashes match the host snapshot.
  The decision trail's initial estimated timestamps are explicitly superseded;
  they are not evidence of exact event times.
- `analyze.log`: targeted analysis of both edited Dart files reports no issues.
  `dart format --output=none --set-exit-if-changed` reports two files, zero changes.
  Final `git diff --check` passes. No full-repository regression or new signed
  release is needed for this test-only correction; neither is claimed here.

Verified source is commit `ce1d0838`. File SHA-256 values:

- `test/screens/typed_cloze_scratchpad_test.dart`:
  `3FB5E18AC50A9D112BB11E34A621B18C771EE5952060972CC32D22736186AF21`
- `test/screens/fill_in_the_blanks_screen_test.dart`:
  `8773AC622B02B6980B6C586A758796ED12A599A642888D48B684933F85794100`

Reproduction and verification commands (run from the active worktree):

```powershell
flutter test test/screens/typed_cloze_scratchpad_test.dart --name 'already built button' -r expanded
flutter test test/screens/typed_cloze_scratchpad_test.dart test/widgets/handwriting_scratchpad_test.dart test/screens/fill_in_the_blanks_screen_test.dart -r expanded
flutter test integration_test/emulator_scratchpad_repeat_test.dart -d emulator-5556 --name 'accepted ClozeVariant\.(typed|choice) renders one masked gap|Typed Cloze|ink survives|Choice Cloze keeps' -r expanded
flutter analyze test/screens/typed_cloze_scratchpad_test.dart test/screens/fill_in_the_blanks_screen_test.dart
```

Before/after excerpts, without temporary trace output:

```text
host-regression-red.log:
Actual: _HitTestableWidgetFinder:<Found 0 widgets with key [<'cloze-save'>] (considering only
00:04 +1 -1: Some tests failed.

host-green.log:
00:33 +51: All tests passed!

native-green-repeat.log:
02:26 +66: All tests passed!
```

## Disposition

Complete for the reproduced Scratchpad test-driver failure. Fix Root Causes
required the paired runtime failure before a correction; Prove It Works required
the real Android pointer/ACK/database workflows on the final source. Production
Scratchpad behavior and the existing signed30 artifact remain unchanged.

The task emulator was stopped after verification, preserving its data and all
evidence. No task Flutter/test process remains running. Pre-existing untracked
critique and failure artifacts were preserved. No deployment, public access,
Cloud A/Billing, real payment, physical-device test, OCR claim or Research
enrollment/upload occurred. This is engineering closure of the bounded test
failure, not whole-app production certification.
