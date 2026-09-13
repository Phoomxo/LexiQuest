# Quiz header progress follow-up

## Scope and source

User explicitly authorized fixing the remaining0% header after the R15.10 report.
This is that bounded follow-up, not an invented R15.11 package or a new task.
Solo in `C:/Users/Phet/.codex/worktrees/842c/LexiQuest`, branch
`feature/r15-integration-continuation`, starting HEAD
`29b9b8dece78a89fb738b156f0a8f0a126073139`.

The previously observed outer native-quiz header defect is resolved. Native
meaning/typed-recall reviews persisted their answers correctly but did not
update the shared shell's ephemeral committed-response count. The shell therefore
stayed at0until completion even while the inner quiz advanced.

`QuizScreen` now reflects uniquely acknowledged question indices into the
existing `UnifiedLessonController` through its lifecycle scope. The controller
accepts only a monotonic count within the current session's item count while
active/paused. Wrong-session, disposed, terminal, duplicate, regressing and
out-of-range updates are ignored. This path never records an answer or reward.
The percentage represents **acknowledged answers**, not the current question
position: skipping a question does not fabricate a committed answer; completion
still uses the existing completed-state100% presentation.

Runtime changes: `lib/screens/quiz_screen.dart`,
`lib/features/learning/application/unified_lesson_controller.dart`,
`lib/features/learning/presentation/unified_lesson_shell.dart`.
Tests: `test/screens/quiz_screen_test.dart`.
No new storage, migrations, research records, persistent authority, model or
learning/reward writes. Frozen8/44 and EvidenceContext/EventEnvelopeV2 remain.

## Regression and scoped verification

The existing real-SQLite lost-ACK test was embedded in the real shell. RED
expected committed-response count1 after successful retry but observed0.
The failed assertion log remains under
`build/verification/29b9b8dece78a89fb738b156f0a8f0a126073139/a11a9fe74a95-be2dce3774ca/`.
After the fix, that test passed in8.55s: before ACK the header stays0, retry
advances it once, and the original frozen write identity still yields only1row.

Additional cases cover both meaning and actual typed-input routes. After skipping
one of4questions and acknowledging the next answer, the shell shows25%, not50%.
Thai progress semantics, exactly1durable answer, repeated/stale/regressing and
oversized progress reports are checked.

```powershell
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Learning -TestTargets test/screens/quiz_screen_test.dart -TestName 'commit then ack loss retries'
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Learning -TestTargets test/screens/quiz_screen_test.dart,test/features/learning/unified_lesson_controller_test.dart
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Learning -TestTargets test/screens/quiz_screen_test.dart -TestName 'native header counts'
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Learning -TestTargets test/screens/quiz_screen_test.dart
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Learning -TestTargets test/screens/quiz_screen_test.dart -TestName 'native header counts commits, not skips (typed=true)'
```

**153 distinct passing cases across2targets**, with retained evidence explicitly
separated from command status:

- The combined command completed128lifecycle cases before hanging in the first
  new Quiz fixture. That fixture initially awaited SQLite seeding in the widget
  fake-async zone. It was corrected to the existing `tester.runAsync` pattern.
  Only the verified task-owned tester PID10160 and its runner PID780 were stopped
  after inspecting exact command lines and parent/worktree identity. The combined
  command is recorded as failed/aborted (177.24s), not as aggregate PASS.
  Its128successful lifecycle cases had unchanged relevant inputs afterward.
- The corrected full Quiz run passed24cases in14.00s and failed1typed fixture
  because it tried to find a choice button on a typed-input question. After
  using the actual text input and pumping the enabled-submit frame, the remaining
  typed case passed in8.86s. The other24cases were retained unchanged.
- The intermediate focused fixture run also exposed an active semantics handle
  at test teardown; disposal now occurs in `finally` before end-of-test checks.
  No runtime assertion was weakened and no test was removed.

Reports under `build/verification/29b9b8dece78a89fb738b156f0a8f0a126073139/`:
`targeted-learning-7e9b288b1b601b39916fd4b2033eddcb30f3069569a533dc499f27135eb25ea6.json`
(lost-ACK GREEN),
`targeted-learning-9bd5bdca404e6de958d511ccea066fc12f47a5301eab14685ac0f68d927ca2dc.json`
(combined interrupted),
`targeted-learning-e12c8b895713898dcf6849384fea1d5df0f27bb92e5158629fc1cb49c6527149.json`
(24pass/1fixture failure),
`targeted-learning-533ff8324ff92dfa7434037ee690dc5b82792df6e013721f56d95431fde2b59f.json`
(final typed PASS). Reports contain exact commands, fingerprints and log paths;
earlier failed logs remain on disk even when a same-command report is replaced.
Final scoped fingerprint:
`f4a342ba0bbf585d0dd042b09a265a7f742db9563393c44026648cbfb49e09fb`.

`flutter analyze` on the3runtime files and2test targets passed:5items, no issues,
11.22s wall. After the final fixture frame change, only
`flutter analyze test/screens/quiz_screen_test.dart` was rerun: no issues,7.53s.
Logs: `build/verification/quiz-header/analyze.log`, `analyze-final-test.log`.
`git diff --check` passed. Source review was solo; no independent review claimed.

## Frozen debug artifact

`build/verification/quiz-header/source-freeze.json` records742build/test source
files. SHA256:
`0659310d93909dad8d98fa4c3e1ac5a21f8de4732ae48b8ef4cf440252ad740c`.
All recorded raw file hashes matched after build. No runtime/test source writers
ran during build/device checks. Git's existing CRLF/LF normalization is accounted
for when comparing committed text with the frozen build input.

```powershell
flutter build apk --debug --build-number=23 --dart-define=LEXIQUEST_VERSION=1.0.0+23 --dart-define=LEXIQUEST_BUILD_ID=quiz-header-29b9b8de-0659310d9390 --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=false --dart-define=LEXIQUEST_LEARNING_PREVIEW=true --dart-define=LEXIQUEST_VOICE_API_URL=http://127.0.0.1:8001 --dart-define=LEXIQUEST_AI_API_URL=http://127.0.0.1:8000
& ./tool/cli/verify-apk-model-runtime.ps1 -BuildMode Debug
```

Build passed in92.76s. APK native runtime and signature verification passed;
all32bundled assets matched source bytes. `aapt` confirmed
`com.lexiquest.app`, versionCode23/versionName1.0.0. Signing identity is unchanged.
APK: `build/app/outputs/flutter-apk/app-debug.apk`, SHA256
`2293fcdf6cad30729d20b6898dca05cc4ccfaaefb72f1123e259705e2bfda1ba`.
Logs/results under `build/verification/quiz-header/`: `build.log`,
`build-result.json`, `apk-model.log`, `apk-signature.txt`, `apk-assets.log`.
Prior installed APK is retained as `before.apk` for data-preserving rollback.

## Authorized Vivo verification

Only serial `9582188822004C6`, V2041/API33, was operated.
Installed with `adb -s 9582188822004C6 install -r ...`; no uninstall/data clearing.
Before-install and after-install snapshots had identical contents in all16checked
tables, including the original10answers and1completed session; SQLite integrity
was `ok`.

On the actual new artifact, completed another10synthetic starter-word answers.
After each acknowledged answer, the outer semantics reported10%,20%,...100%.
Images `header-10.png`, `header-70.png`, `header-100.png` were opened and reviewed:
the outer bar fills correctly, matching the acknowledged answers. The result was
10/10. All original historical answer/session rows remained byte-value identical.

After force-stop/relaunch, Dashboard showed20/20 (old10 + new10).
Before/after restart, all16checked table counts and full-row hashes matched;
SQLite integrity stayed `ok`. `dashboard.png` was opened/reviewed. Research
measurement/response/permit/proof/assignment counts remained0. Existing declined
consent was preserved. Cloud sync/research remain off; no enrollment/upload,
AI/voice call, model download or training occurred.

Evidence: `build/verification/quiz-header/device-journey.log`, question/answer
XMLs, the reviewed PNGs, `persistence-{before-install,after-install,before-restart,after-restart}.json`
and local synthetic SQLite snapshots. None of these generated artifacts is
tracked. Original R15.10 evidence remains historical and unchanged.

## Completion boundary

This resolves the concrete0% header observation in the R15.10 ledger. No task-owned
test/build/analyzer/device-driver process remains. No successor package created.
The previous external acceptance limits (human audio/TalkBack, camera accuracy,
live tutor/two-device sync, emulator/full release) are unchanged and not claimed
as passed here. Generated platform registrant EOL churn stays outside the commit.
No push/merge/deploy, paid service, security worker or destructive cleanup.
Actual model token/credit usage unavailable; no savings claimed.
