# R15.10 local integration verification

## Source and disposition

R15.10 closes the approved local queue. No R15.11 or successor task was created.
Worktree: `C:/Users/Phet/.codex/worktrees/842c/LexiQuest`.
Branch: `feature/r15-integration-continuation`, based on exact accepted R15.9
`d076b48baf546ab5dc6840337207050b37e786f2`. Checkout started clean/detached;
no other branch, pending source or worktree was imported.

Local voice/sync changes and the debug preview are accepted within the evidence
below. This is not full release, emulator, live-service or research acceptance.
One observed learning-shell progress-label discrepancy remains outside this
package's permitted voice/sync expansion; see the explicit observation below.

## Changes and regression

- `lib/screens/shadowing_challenge_screen.dart`: a displayed speech failure now
  retires the screen attempt, clears pending state and cancels its scoped speech
  session. A late native final cannot write a learning answer after that failure.
  Retry remains available; shared speech engine semantics are unchanged.
- The assessment label is VOICE-01's recognized-text similarity wording.
  A failure with a readable reference and no persistence lock explains that the
  learner can continue reading the reference and retry the microphone later.
- `test/screens/shadowing_challenge_screen_test.dart`: six failure/retry/stale
  final cases and two real-font visual cases; existing score assertions updated
  for the specified label without weakening their expected outcomes.
- `test/features/media_practice/plugin_speech_recognition_gateway_test.dart`:
  native timeout/no-match mapping and unavailable recognizer fixtures.
- No new persistent storage, migrations, exports, sync policy, reward authority,
  research records, classifier or interface changes. Existing owner/session gate
  and canonical learning evidence remain responsible for persistence.

RED: all six new widget cases failed on the missing fallback (24.27s, exit1).
After the copy change, the combined run produced68pass/1failure (53.27s):
`SpeechFailureCode.engine` still allowed a late100% assessment. Investigation
found that shared speech policy treats engine errors as nonterminal while this
screen already presented a stopped/error state. The screen-specific cancellation
fix made all34voice cases pass (11.45s). No global speech policy was weakened.

The two edited pre-existing Dart files had CRLF/mixed line endings. The final
files use LF; tests/analyzer preceded this byte-only normalization. Review the
semantic diff with `git diff --ignore-space-at-eol`; no Dart tokens changed after
the passed gates. No global Git/settings changes were made.

## Actual commands and results

All paths below are relative to this worktree. Full logs stay under `build/`.
Flutter/test/build operations were serialized. No unchanged passed subsystem was
rerun merely because another subsystem or line endings changed.

```powershell
# RED
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Voice -TestTargets test/screens/shadowing_challenge_screen_test.dart -TestName 'R15.10'
# Combined discovery: 68pass/1engine failure
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Voice -TestTargets test/screens/shadowing_challenge_screen_test.dart,test/features/media_practice/speech_practice_use_cases_test.dart,test/scenarios/file_backed_sync_recovery_test.dart,test/features/sync/cloud_sync_policy_test.dart,test/features/account/local_data_deletion_test.dart,test/features/research/research_runtime_sync_integration_test.dart,test/features/sync/research_withdrawal_reopen_test.dart
# GREEN affected voice subsystem:34pass
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Voice -TestTargets test/screens/shadowing_challenge_screen_test.dart,test/features/media_practice/speech_practice_use_cases_test.dart
# Additional visual cases:2pass
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Voice -TestTargets test/screens/shadowing_challenge_screen_test.dart -TestName 'R15.10 visual'
# Native adapter mapping:3pass
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Voice -TestTargets test/features/media_practice/plugin_speech_recognition_gateway_test.dart
```

**74 distinct tests across8targets:**34voice +35 unaffected sync/research retained
from the combined run +2visual +3adapter. The failed combined run is not labeled
PASS. Its35 unaffected cases and source dependencies were unchanged by the
screen correction. The34voice results predate only visual-test additions and LF
normalization; these edits do not alter those test cases or runtime behavior.

Reports under `build/verification/d076b48baf546ab5dc6840337207050b37e786f2/`:

| Run | Report filename suffix after `targeted-voice-` | Seconds / result |
|---|---|---|
| RED | `a489fbbe6603f4ca9ae01bdc3a021eb5f7c4ccc105c792e416009a51ee0f1633.json` |24.27 /6fail|
| Combined | `1b8738f7eeacdaad8b10fb30a1c17d3f4482d3ccb708506d65971946be587424.json` |53.27 /68pass,1fail|
| Voice GREEN | `734b5f41ed762ad00c3e3dafd0063b0f98996f6b5b5a42e9227bc92779289e6a.json` |11.45 /34pass|
| Visual | `a550561821f859f743bbbb7e13f69244df1ee9f42867aa6a17ffdd21fbfd7ca7.json` |8.41 /2pass|
| Adapter | `071a717d5567948faea8fce89c3b70119f0794a9fdfdf5aa97700d8f0262d73d.json` |6.62 /3pass|

The reports retain full source fingerprints, timestamps and stdout/stderr paths.
Final pre-LF verify-scope fingerprint:
`59ffd93fed688c888d7fa7c86050a5195222d973889279ab85d2235c6accd113`.

`flutter analyze` on the screen, speech use cases/gateway and all8test targets:
11items, exit0, no issues, 8.39s wall time (`r15-integration/analyze.log`).
The command's explicit paths are the8targets above plus
`lib/screens/shadowing_challenge_screen.dart`,
`lib/features/media_practice/application/speech_practice_use_cases.dart` and
`lib/features/media_practice/data/plugin_speech_recognition_gateway.dart`.

## Frozen artifact and visual review

Build inputs:740files recorded in
`build/verification/r15-integration/source-freeze.json`, SHA256
`383b2381ea8450a12f5b4f4afdcb46036e79746ff6e135490b606bcd30478e16`.
All recorded files matched after build. No runtime/test source writers ran during
analysis/build. Final source hashes:

| File | SHA256 |
|---|---|
| Shadowing screen | `e4e0985fd622074848c021fbdc1057c51de21a685a8002b0f6b91a865b131893` |
| Shadowing tests | `638b2b8bd55baa40ab309993ea05301f19e17b13dd35c3ac84801f6152436249` |
| Native adapter tests | `9742e3c06a660a3e9fcb5b0fedf7d3793f6c7f54bcbc55523690a73744397e0d` |

```powershell
flutter build apk --debug --build-number=23 --dart-define=LEXIQUEST_VERSION=1.0.0+23 --dart-define=LEXIQUEST_BUILD_ID=r15.10-d076b48-383b2381ea84 --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=false --dart-define=LEXIQUEST_LEARNING_PREVIEW=true --dart-define=LEXIQUEST_VOICE_API_URL=http://127.0.0.1:8001 --dart-define=LEXIQUEST_AI_API_URL=http://127.0.0.1:8000
& ./tool/cli/verify-apk-model-runtime.ps1 -BuildMode Debug
```

Build exit0,155.33s; model-runtime gate exit0,0.55s.
Logs/results: `build/verification/r15-integration/{build.log,build-result.json,apk-model.log}`.
APK: `build/app/outputs/flutter-apk/app-debug.apk`, SHA256
`baa175c9b3f864663c90d37d4d7c89a50fc31264d566b3d527ec43acc3bec4cf`.
`aapt` verified `com.lexiquest.app`, versionCode23/versionName1.0.0,
minSDK26/targetSDK36, arm64-v8a/armeabi-v7a/x86_64.
`apksigner` passed and the signing certificate matches the previously installed
APK. All32bundled source assets matched byte-for-byte (`apk-assets.json`).
Research stays bootstrap-default-off; cloud sync explicitly false. No actual
AI/voice API requests were made. This is the production entry with the approved
learning-preview flag, not the prior synthetic manual harness.

Four real-font images were opened/reviewed from
`build/verification/r15-visual/after/`: `shadowing-{fallback,assessment}-{390-light,320-dark-200}.png`.
Viewports390x844@1x and320x844@2x text, reduced motion. The narrow assessment is a
scrolled view; its text and acoustic-score disclaimer remain reachable. These
are fixture visuals, not microphone/audio quality or TalkBack acceptance.

## Authorized physical subset

Only Vivo `9582188822004C6`, V2041/API33 was operated. No emulator was connected
in this task. Before installing, the prior APK was saved as
`build/verification/r15-integration/vivo-before.apk` for data-preserving rollback.
`adb -s 9582188822004C6 install -r build/app/outputs/flutter-apk/app-debug.apk`
succeeded; no uninstall, clear-data or identity/version changes.

- Fresh launch reached production login. Guest entry and **declining** research
  participation reached ordinary offline learning. No real enrollment occurred.
- Completed10synthetic starter-word answers; actual result screen showed10/10.
  After force-stop/relaunch, Dashboard still showed10/10 and3m47s learning time.
  Home, lesson, result, Dashboard and Review routes opened from the new artifact.
- SQLite integrity checks before/after restart both returned `ok`. All16selected
  table counts **and full-row hashes** matched, including1learning session,
  10answer attempts,1day log and1time segment. Private row values were not logged.
- Research permit/proof/measurement/response/assignment counts were0.
  The explicit decline is represented by1existing `research_consents` row in
  `withdrawn` state; it is not an enrollment/measurement.27outbox entries are
  ordinary attempts, achievements, time segments and reward transactions; every
  attempt counter is0. No research outbox type was present.
- The manual harness's separate database remains in place. Its first hash changed
  after the old harness was opened during preflight, so that first hash is **not**
  an unchanged-across-install proof. Its modification time02:29:59 predates the
  APK update02:35:50; its post-install/post-restart hashes match. Do not confuse
  this store with the production database used for the10/10 restart check.
- Device model bytes stayed at retained MobileNet SHA256
  `d3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b`.
  No model download, training, candidate export or physical accuracy evaluation.

Device evidence under `build/verification/r15-integration/`: `install.log`,
`device-result.png`, `device-dashboard.png` (both opened/reviewed), route XMLs,
`persistence-{before,after}-restart.json`, `device-research-policy.json`,
`device-db-*.txt`, `device-model-*.txt` and local SQLite snapshots (not tracked).

Bounded tooling recovery: the first UI dump had a null root during startup;
after verifying the app process existed, a ready-state dump succeeded. Vivo's
board-info warning did not prevent later dumps. The temporary quiz driver stopped
on an offscreen Next control, then on unmapped `door`; both were inspected and
resumed from the current question after specific corrections. No lesson restart
or duplicate answer was used as recovery. A one-line Python quoting error was
replaced with a file-based probe before any database snapshot was created.

## Acceptance ledger and retained evidence

| Case | Result and boundary |
|---|---|
| A-SYS-01 | Local fixtures pass: permission/no speech/native timeout/cancel/unavailable/restart; failure cannot yield stale assessment/evidence; reference remains readable. Physical microphone/audio quality not run. |
| A-SYS-02 | Existing file-backed lost-ACK/reopen/retry/owner isolation, transactional deletion, signed research recovery/conflict and local policy fixtures pass. No new live two-device or Firestore emulator run. |
| A-SYS-03 | Runtime research gating fixtures pass; declined-participation physical learning completed with0research measurement/proof/permit/assignment rows and no research outbox types. |
| A-SYS-04 | Frozen debug build/assets/native runtime/authorized Vivo restart-persistence subset verified. Literal emulator restart and full release acceptance remain not-run. |
| A-SYS-05 | Accepted local evidence and external/unresolved limits are explicitly separated here; no aggregate production/research PASS. |

Retained accepted package evidence is not rerun or relabeled as fresh:

| Acceptance family | Evidence in `docs/development/` |
|---|---|
| R15.0–1 / A-NAV, foundation | `2026-09-12-r15-execution-history.md` |
| A-PAIR | `2026-09-12-r15-pair-verification.md` |
| A-UI, A-NAV | `2026-09-12-r15-layout-verification.md` |
| A-LEARN | `2026-09-13-r15-learning-verification.md` |
| A-DATA | `2026-09-13-r15-dashboard-verification.md` |
| A-CAM | `2026-09-13-r15-camera-verification.md` |
| A-MODEL | `2026-09-13-r15-model-verification.md` — retained baseline |
| A-MOT | `2026-09-13-r15-motivation-verification.md` |
| A-AI | `2026-09-13-r15-ai-tutor-verification.md` — C-AI-Q live-not-run |

**Unresolved, outside permitted source expansion:** `quiz-07-question.xml` shows
the outer learning-shell semantics at0% while the native quiz reports question7
of10 (70). Durable answers, completion and Dashboard totals still verified.
This inherited/non-Shadowing route observation has not been fixed or assigned to
a newly invented package. It limits any claim that all combined UI is accepted.

External-not-run: human pronunciation/audio judgments, TalkBack operation,
physical camera accuracy, fresh qualifying model evaluation, two-device live
sync, live tutor quality, literal emulator restart and full release gates.
No paid service, enrollment/upload, push, merge, deployment or security worker.
Source review was solo per instruction; no subagent/independent review claimed.
Generated platform registrant EOL churn is excluded from the commit.
Actual model token/credit usage is unavailable; no savings are claimed.
