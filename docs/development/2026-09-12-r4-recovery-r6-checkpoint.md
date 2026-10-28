# R4 recovery and R6 reading/history preview checkpoint

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`.
Branch: `codex/pair-matching-pm0-pm8`.
HEAD: `788e90e62b1694c20945734787723c168b6a6ab2` with inherited uncommitted work
preserved. No commit, publish, real research upload or paid AI call was made.
User selected six readings and is unavailable for human audio/second-device
testing; live AI provider/model/budget are not ready.

## Transfer and installed versions

The old Windows binary-stdin path reproducibly wrote only 456 bytes from a
1 MiB block while returning exit zero; the first control-Z byte is at offset
456. `dd ... seek=... conv=notrunc` therefore left sparse zero-filled regions
when subsequent pieces were placed at their intended offsets. Merely reducing
piece size or trusting process exit was insufficient.

Replacement: `adb push -Z` using the sync protocol, explicit 4 MiB part names,
SHA-256 for every part on host/device, explicit ordered Android concatenation,
then full size and SHA-256 verification before `pm install -r -t`.
Never pipe APK bytes through Windows ADB stdin. Preserve mismatching pieces
for diagnosis; reconcile an existing install journal before retrying writes.

R4 manual v14 was installed and its actual installed APK matched
`db11b182dd63da6285061940b3b43603c57ea31535ae77d25e21f6209816c461`.
It opened without captured AndroidRuntime/flutter errors. Native history then
exposed the real bug below. R4 archives remain immutable.

R6 manual v15 subsequently updated the same package `com.lexiquest.app` on vivo
`9582188822004C6`. Host/staged/installed SHA-256 all equal
`8221a079e19614cac7e1d004521ab0638c6cdbe1dbe9037ebc8fbb0e9476caa7`.
Size 153,235,318 bytes, versionName 1.0.0; first-install time remains
2026-09-01 00:27:20, update time 2026-09-12 09:27:03 device local time.
Signer is unchanged:
`1f10bbeedb0b8f18bcbb789c31d862bcfe9a3d146920033fb93eb1d228b0c5b4`.

APK directory: `build/verification/motivation-ui-20260908/device/`:

- Installed synthetic manual: `lexiquest-learning-preview-manual-v15-thai-r6-debug.apk`.
- Ordinary candidate, built but not installed: `lexiquest-learning-preview-v20-thai-r6-debug.apk`,
  226,079,516 bytes, SHA-256
  `3fed92ecbdc98fd69ffbf86e047083ebaa51c0ba75d7910a0f558970ac36c2ac`.
- Each has `-identity.json`; manual also has `-build-record.json`.

Both are debug previews with cloud sync disabled, build ID
`reading-history-preview-thai-r6-20260912`. They are not final release APKs.
The earlier ordinary R5 v19 candidate is superseded and was never installed.
Builds and final manifest agree on whole-source fingerprint
`0d68b5d4cca2471cece26d47f11993dfcb8d83859b46abdbb9a387589a107476`;
manual fixture/driver hashes are additionally pinned in its build record.

## Data preservation and its limits

No uninstall or clear-data was used. Selected pre-existing files, preferences,
databases, no-backup data and synthetic QA stores were compared by hash before
and after updates. Android clears code_cache during installation; only missing
synthetic QA files were restored from verified backups, never old compiled code.

The old manual harness created a new temporary database on each launch.
R3 store `code_cache/lexiquest-manual-uat-YVAXVX` contains 18 vocabulary rows
and two sessions; it remains preserved separately. R4 live store
`code_cache/lexiquest-manual-uat-VTLJCU` contains the three activities from this
acceptance run. These independent stores have NOT been merged into one visible
history. File preservation must not be described as complete cross-store UI
continuity.

Before R6 installation, the complete R4 live fixture was copied and verified
at `files/lexiquest-manual-uat-v1`. The revised manual harness reopens that
dedicated synthetic store and seeds only when its seed category is absent.
The ordinary application's storage/bootstrap is unchanged. Old cache stores
and host tar backups remain available; do not delete them.

## Functional evidence and fixes

On unchanged R4, all A1–C2 readers opened through Learn, showed the provisional
level notice, completed and reopened; A2–C2 scrolled. Independent reading left
learning_sessions, answer_attempts, learning time and research evidence empty.
Vocabulary-linked A1 reading completed through its canonical activity route.

Matching 4 pairs: four independent, zero hints, 3/3 stars, 321 active seconds.
Matching 6 pairs: six independent, zero hints, 3/3 stars, 145 active seconds.
Focus Timer start/pause/resume/finish passed; pause remained at 1:36, finish
showed 2:05. Focus duration is separate from activity active time.
Today opened, but mixed history initially failed on R4.

The history reader required configuration mode to equal stored activity type.
Existing `LearningUseCases.startQuiz` stores `quiz` for CEFR and other configured
quiz modes. The fix recognizes only the explicit supported quiz-mode allowlist;
canonical configuration identity, owner and answer/event validation remain.
Ten supported-mode tests and four unrelated-mode rejection tests were added.
The actual synthetic vivo database reproduced the failure and now loads all
three entries. R6 native History shows the retained 6/4-pair results and CEFR
activity with its actual duration, without inventing a quiz correctness score.
Replay controls remain unavailable for these retained fixtures, and CEFR's
history content title is shown as unavailable; this run does not claim replay
acceptance for those entries.

The six-reading editorial review is in
`2026-09-12-six-reading-editorial-review.md`. B1/B2 wording and revision IDs
were improved; no new lessons or graded questions were added. Tests cover all
six on a narrow display at 1.2 text scale. All estimated levels remain explicitly
uncertified. The CEFR vocabulary route still checks only its first 100 candidate
words; tests prove inclusion at the boundary and omission beyond it. Empty
eligibility creates no durable attempt/session. This limitation was characterized,
not removed.

## Verification and changed files

Current combined run: 102 tests passed in `final-regression-corrected.log`, covering
reading adapters/catalog, library, reader, ChooseMode, history reader/replay/UI,
persistent manual storage and the actual vivo database reproduction. The initial
combined invocation named a nonexistent reader test; corrected to the discovered
`test/screens/cefr_article_reader_screen_test.dart` before the successful run.

Analysis of nine touched items found no code errors/warnings and one info:
the existing hyphenated `.superpowers/sdd/device-manual-uat.dart` filename.
It exits 1 under the default fatal-info policy; do not report a zero-issue pass.
Focused diff whitespace check passed with a Windows line-ending advisory.
Both source-gated builds passed. This was not a new full-repository regression
or final TalkBack/device-accessibility acceptance run.

Task edits:

- `lib/services/local_reading_catalog.dart`
- `lib/features/history/data/drift_learning_history_reader.dart`
- `.superpowers/sdd/device-manual-uat.dart`
- `integration_test/support/persistent_manual_qa_storage.dart`
- `test/services/ai_voice_reading_adapters_test.dart`
- `test/screens/choose_mode_screen_test.dart`
- `test/screens/local_reading_library_screen_test.dart`
- `test/features/history/learning_history_reader_test.dart`
- `test/support/persistent_manual_qa_storage_test.dart`
- `docs/superpowers/plans/2026-09-12-r4-reading-quality.md` and these review/checkpoint documents.

Raw evidence/scripts/backups are under ignored
`build/verification/r4-recovery-20260912/`; native screenshots/XML under
`build/verification/motivation-ui-20260908/device/manual-ui/`.
Key journals: `dd-probe.json`, `push-probe.json`, `transfer.json`, `install.json`,
`r6-device/transfer.json`, `r6-device/install.json`. The R6 transfer journal's
inherited `intent` label mentions the R4 intent; its APK hash/path and the separate
R6 install journal identify the actual R6 operation. The reusable wrapper label
was corrected after that transfer; no transfer was repeated merely for labeling.

## Remaining acceptance dependencies

- Human hearing and spoken STT success, incorrect/unclear speech, silence/retry,
  mic release and unavailable-service/network checks. Shadowing currently compares
  recognized TEXT (80% similarity threshold), not phonemes/pitch or direct
  pronunciation acoustics. No human success is claimed.
- Live AI provider/model/budget and key entered in-app, then the existing 12-case
  evaluation and real error paths. No key was requested in chat or paid request made.
- A second ready device/test account/backend for real sync, offline conflicts,
  duplicate retries, deletion and account isolation.
- Vivo pilot camera load/latency/memory and real scene/open-set comparisons;
  the main model stays unchanged. Earlier internet-image pilot results are not
  a substitute for device or out-of-class evidence.
- Full integration, Thai/TalkBack review, release signing and final source-pinned
  deliverable after remaining acceptance. Do not call these previews final.

## Final native reconciliation

R6 A1–C2 readers all opened, completed and returned to Learn. Revised B1 and
B2 phrases were verified in native word nodes; scroll and the estimated-level
notice remained available. The first helper assertion incorrectly expected a
whole sentence in one accessibility node. It was corrected to read the individual
word labels; this was a verification-helper error, not a product failure.
Evidence: `readings-r6.log` (A1/A2), B1 screenshots/word-node check,
`readings-r6-final-three.log` (B2/C1/C2, exit zero).

`r6-persistence.json` confirms identical row hashes before upgrade, after the
R6 independent readings, and after a force-stop/relaunch across ten core tables.
Retained counts: 18 vocabulary rows, three sessions, 11 answer attempts,
102 events and seven learning-time segments; no research-session proofs.
There were no new independent-reading attempts or duplicate seeds. Relaunch
error log is empty. Final screenshot `r6-relaunch-verified-20260912.png` shows
the ready synthetic launcher. No microphone or camera capture was started.

No task-owned build/test/transfer/install process remained in the final process
inventory. The app is left at its synthetic launcher. No new source edits
followed the successful source-pinned builds; this checkpoint is outside the
source manifest scope. The original plan checkboxes remain historical; this
checkpoint is the current result.

Next executable acceptance: when the holder is ready, open the app's native
Shadowing activity, play its sample, obtain an audible confirmation and spoken
recognition result, then run wrong/unclear/silent/retry cases. Before a final
release, also resolve whether historical R3 synthetic stores need an explicit
UI import/selection, complete unavailable replay/content-title acceptance as
applicable, and carry out the AI/sync/camera dependencies above. Do not reinstall
or rerun either one-shot install script without reconciling its existing journal.
