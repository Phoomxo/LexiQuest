# Learning flow remediation

Status: Complete for the four critique findings; local engineering integration.
Worktree: `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`.
Branch: `codex/remaining-system-readiness`.
Baseline: `3651cde3`.
Intent: implement the four findings in the 2026-11-03 comparison critique.
Authority: the user's request to continue development authorizes these local
changes and synthetic verification. Cloud A/Billing, public deployment, payments,
real Research and physical-device settings remain excluded.

## Feature playbook

1. `how` over the affected subsystem.
2. `architect` for parallel design exploration.
3. Write the throughput checkpoint as four todo items.
4. Delegate code-writing to a subagent using your configured feature model.
5. Verify on the matching surface.
6. Rebase into small, ordered commits. Stack follow-ups.
7. If the design is contested, `interrogate` before shipping.
8. Run **Opening a PR**.

Step 6 uses the existing task branch with one integrated local commit after
verification. No other branch needs a rebase. Step 7 applies only if a material
design disagreement remains. Step 8 is omitted for this local app task; no PR,
remote publication or deployment is required to deliver the requested behavior.

## Throughput checkpoint

- Blocking first steps: inspect the four findings, source callers, owner leases
  and existing tests. Complete the baseline before implementation writers start.
- Independent workstreams: starter/recommendation UI, shared resume opening, and
  score continuation have separate owners. The hub is edited by one owner.
- Shared mutable state: root alone runs Flutter, builds and emulator tests.
  Changes to hub callbacks are integrated by the hub owner after shared API
  signatures are fixed. No parallel dependency resolution or generated output.
- Smallest safe decomposition: reuse the existing pack preview, recall stage,
  LearningHistoryEntry and session authority. No schema, reward authority,
  additional feature or navigation framework is introduced.

## Grounding and alternatives

The hub composes RecallLadderPanel and TodayResumePanel. Recall uses an existing
word and stage. Matching requires multiple distinct pairs. Some stages open
selectors instead of accepting a single target word. Labels must describe the
actual next action. Catalog owns preview and installation under PackOwnerScope.

History owns guarded session reopening. Today's history reader only lists
candidate sessions; accepted-checkpoint flags do not prove a session can still
open. Reopening must retain fresh owner and activity checks. History order is
start time, not last interaction time.

ScoreScreen has callers with different return destinations. Do not rename every
Back action to Home. Preserve mistake repair and ensure an all-correct result
offers a clear finish action without generating new sessions or rewards.

Design alternatives are reviewed by independent GPT-6.1 Terra and GPT-6 Astra
agents. The configured Claude/Grok families are unavailable in this harness;
these are the available equivalents, not a claim of cross-family review.
Candidate sketches are returned in messages without duplicate draft files.
The independent cross-judge accepts the callback/shared-opener design. Both
implementers and root reject an auto-opening hidden history route and a new
launch coordinator. Grafted constraints are fresh validation of the displayed
session ID, separate launch and active-child validity, and caller-owned result
labels. A covered hub must not invalidate its own child activity's owner lease.

ScoreScreen accepts an optional backLabel. QuizScreen, MatchingQuizScreen and
NativeExerciseResumeScreen accept resultBackLabel and preserve their existing
callbacks and pop counts. Known callers supply their actual return destination.
Fallback Done remains available for unknown callers without guessing Home.
Successful completion text requires answers > 0 and wrongAnswers == 0.

## Task cards

| Card | Outcome | Write ownership | Acceptance | State |
|---|---|---|---|---|
| U1 | Start from an empty library and understand recommendation destinations | Hub, recall panel, pack catalog and their tests | Empty state reaches starter preview, explicit installation, truthful stage action, owner loss rejected | Done |
| U2 | Resume the newest eligible started session directly | History, TodayResumePanel, shared presentation opener, resume tests | Same session opens without history detour; missing/stale/changed-owner sessions fail safely; history still works | Done |
| U3 | Finish results with a clear action | ScoreScreen, result producers and their known caller labels, focused result tests | All-correct, mistakes, empty result and Thai/English large text remain accurate; callbacks execute once | Done |
| V1 | Review and verify integrated source | Root owns integration test entry and this checkpoint | Targeted regression, static checks, Android synthetic flows and visual inspection | Done |

## Review rubric

Compare candidates on preservation of owner/session checks, visible outcome,
reuse of existing authorities, accurate navigation and size of API/diff. Reject
a duplicated resume resolver, hidden history route, single-word MatchingPlan,
automatic starter installation and a global Home label.

## Evidence

Baseline and later logs use
`D:/LexiQuest-Storage/maintenance/2026-11-03/learning-flow`.
Preserve the pre-existing untracked critiques and screen failure artifacts.
No test or app process from the preceding Scratchpad task is still running.
The existing signed30 release artifact is not proof of this new source.

Baseline command passes 32 tests before implementation.

```powershell
flutter test test/screens/recall_ladder_entry_flow_test.dart test/screens/today_resume_panel_test.dart test/screens/bundled_starter_pack_flow_test.dart -r expanded
```

The root started only LexiQuest_Synthetic_API35 on emulator-5556 without wiping
data. The attached Vivo is excluded from commands. Native evidence is synthetic.

## Review and bounded recovery

- First focused pass: 72 tests passed. Full analysis found two new unused
  parameter underscore lints in a test callback; these were corrected.
- Independent lifecycle review found a retained Today button could borrow a
  newer history read epoch. A SQLite regression opened the old QuizScreen
  before the fix. The button now captures its rendered history and read epoch,
  while the active child retains a separate owner/dependency predicate. The
  same regression passes after the fix.
- Independent navigation review found a Thai result return label on English
  History results. The label now follows the existing language setting. A
  Matching flow checks both the English label and actual return to History.
- Today keeps an outlined resume action so it does not compete with the hub's
  filled recall recommendation. Comment review found no added comments or
  suppressions requiring changes. A fresh final source review accepts the
  lifecycle correction, subject to runtime verification.
- The score golden changed only for the intended completion label. Root
  inspected the generated image before updating the baseline. Pre-existing
  failure images were backed up separately for restoration.
- The first 31-file subsystem run passed 392 tests before its remaining native
  worker was stopped after a confirmed stall. Six earlier failures concerned
  a lazy-list test helper and the new Today fixture's non-replaying owner
  stream. This interrupted run is not a passing regression result.
- Pack readiness now reveals the actual import action when it is outside the
  lazy viewport, then retains the enabled-action assertion. Search taps also
  reveal the field. Today native fixtures use the production progress owner
  watcher rather than a broadcast event emitted before the panel exists.
- Isolated hook-retry tracing confirmed all commits/reads finished and no
  repository operations remained, but teardown waited at database.close.
  Reusing motivationPresentationIo lets Flutter process pending work while the
  database closes and adds the existing bounded deadline. The isolated case
  then passes. Temporary trace prints were removed. No production database or
  answer logic was changed for this test-driver problem.

The two stopped processes were task-owned flutter_tester workers. Their command
lines identified this worktree's unit_test_assets. Only synthetic fixtures were
in use. No unrelated process or emulator data was removed.

The corrected native-resume and pack-action suites pass all 51 tests. A first
rerun exposed seven fixture assertions: five checked Score disappearance before
its exit animation settled, and two looked for import before catalog loading
finished. The final assertions wait for both Home and Score absence, or catalog
readiness followed by the real enabled action. No assertion was removed.

Final independent review accepts these fixture changes and the Android wrapper.
The reviewer checked bounded teardown, exact temporary-path containment,
retained session/answer assertions and real surface screenshot capture. Review
did not execute the toolchain and is not Android test evidence.

Formatting passes for all 34 changed/new Dart files without changes.
`flutter analyze --no-pub` passes with no issues in `analyze-final.log`.

The final affected-subsystem regression passes all 423 tests across 31 files in
8m30s (`subsystem-green.log`). The exact file list is
`subsystem-test-files.txt` in the evidence directory. It includes starter packs,
recall recommendations, Today/History resume, all five native resume modes,
Matching, result continuation, Source Practice, Ask Lexi, review/weakness flows,
navigation and large-text/golden checks. This is affected-scope regression,
not a rerun or certification of all 44 app features.

All 16 pre-existing failure images have been restored and SHA256-compared with
their backups. The reviewed image from this task is retained outside the repo
as `score-golden-reviewed.png`.

## Android findings and corrections

The first Android run (`native.log`) finished with 41 passed and 49 failed. It
exposed a real Score owner-lifetime bug: after A -> B -> A, the result route
checked only the current owner ID and revived the old result. The source now
also requires the exact retained `_finished` result and dependency binding.
Owner invalidation clears that result permanently. The same predicate guards
retained mistake-repair callbacks; ordinary route cleanup is unchanged.
A focused host regression emits B and A before a frame and invokes the retained
repair callback. It checks that the invalidation remains visible, no extra Quiz
opens and all session/answer rows remain unchanged. Independent review accepts
this reuse of existing state. No extra owner authority or schema is introduced.

Other initial Android failures were test-driver defects: pumping while paused
left a pending frame and caused subsequent binding failures; using expect in a
concurrently pumping database-close helper caused guarded-call conflicts. Tests
now await background DB work without pumping and use an equivalent throwing
path-containment check before fixture deletion. The pause callback is still
invoked while paused and asserted unable to open a Quiz.

The second Android run (`native-recovery.log`) finished with 86 passed and four
failed. Score owner ABA passed. Remaining failures identified a missed next tap
during keyboard layout changes, a retry control that was not hit-testable, and
a frame deadline during Study fixture setup before UI creation. The following
Matching binding failure was fallout from that pending frame. No Study
exclusion assertion or committed-answer integrity assertion was weakened.

Typed input still uses IME Done, now after an enabled-field and exact-text
check. Next/retry actions settle keyboard layout and retain hit-test assertions.
Study setup awaits DB/signature work through runAsync and closes the fixture
if setup fails. These changes do not disable or fake cryptographic checks.
Host rechecks pass 99 tests including the Score regression, then 71 tests after
the final fixture corrections (`android-recovery-host.log`,
`android-fixtures-host.log`). The earlier 423-test pass predates the Score fix;
final integrated regression is required again before completion.

The third Android run (`native-final.log`) passed 89/90. Its remaining typed
case caught an empty controller immediately after injecting the second answer.
SDK inspection traced this to WidgetTester.focusedEditable caching the same
EditableTextState across questions while IntegrationTest's real IME had closed
the connection after Done. The helper now taps the visible field to request
the keyboard again, verifies actual focus and exact text, and then sends Done.
No input-channel mock, production workaround or assertion removal was added.
The isolated native two-question typed flow passes (`native-typed-focus.log`).
The independent reviewer accepts the final diff, including the retained
coalesced-event test comment and fixture cleanup. Final verification freezes
the changed source/test/golden hashes in `verified-source.json`.

## Final integrated checks

| Check | Current-source result | Evidence |
|---|---|---|
| Android API 35, emulator-5556, 320 logical pixels | 90 passed, 0 failed, 3m19s after build/install | `native-green.log` |
| Affected host regression, 31 files | 424 passed, 0 failed, 8m31s | `subsystem-final.log`, `subsystem-test-files.txt` |
| Flutter analysis | No issues, 23.3s | `analyze-integrated.log` |
| Source review | Accepted, no remaining must-fix | Independent review of result retirement, callbacks and final fixtures |
| Source identity | 35 changed source/test/golden files unchanged during checks | `verified-source.json` |

These counts overlap across platforms and do not mean 514 distinct features.
The Android run includes two large-text visual cases and four surface captures.
Flutter's default integration cleanup uninstalled the package before the first
image pull. Only the two visual cases are rerun with `--no-uninstall` to retain
their PNGs for inspection; no source change is involved.

The visual rerun passes both cases (`native-visual.log`). All four PNGs were
pulled successfully, validated as 320x640 PNGs and visually inspected:

- `score-top-2x.png`: 100%, all-correct text and all three counts are legible.
- `score-action-2x.png`: the named Home action is fully visible and its callback
  was tapped and verified by the integration test.
- `catalog-starter.png`: the bundled pack precedes file import; title, offline
  availability and search/filter controls wrap within the narrow viewport.
- `starter-preview.png`: installation remains an explicit primary action,
  offline caching is secondary, and sample words remain scrollable.

The images and their hashes are in the evidence directory with
`screenshots-sha256.json`. These are synthetic Android test surfaces, not a
physical-device acceptance claim. Final formatting checks all 34 changed/new
Dart files with zero changes; git diff whitespace checks and the 35-file source
hash comparison pass. No source edits followed these checks.

## Integration and limits

All four findings are implemented, and the additional Score owner-ABA defect
found on Android is fixed. Review disposition is accepted. The task is integrated
as one local commit on the existing branch; no PR, push, publication or deployment
is part of this work. No schema, dependency or feature-catalog change was needed.

The test package was removed from the verified LexiQuest_Synthetic_API35 device
and emulator-5556 was stopped. All test/analyze commands completed. No task-owned
test or emulator process remains running. The attached Vivo was not targeted.
The pre-existing critiques and failure images remain outside this commit.

No signed normal-app release was built from this source; the debug APK exercised
the integration entry point. A future distribution must build the normal app
entry point and complete its release checks. This work does not recertify all
44 features, real provider/Play services, physical audio/TalkBack or Research
authority. Cloud A/Billing, public traffic, real charging, enrollment and uploads
remain outside scope. The successful build still emits a non-blocking warning
about Kotlin plugin compatibility with future Flutter versions.

The reusable lesson is to validate owner lifetime independently of current owner
equality, and to drive Android tests through visible, focused controls. Await
fixture-only work without asking a paused/live UI for a frame; keep source
identity and failed-run evidence when correcting the test driver.
