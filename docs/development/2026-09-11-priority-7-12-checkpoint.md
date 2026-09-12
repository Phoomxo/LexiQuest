# Priority 7–12 checkpoint — 2026-09-11

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch
`codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2`.
Inherited changes preserved. No commit, deployment, real research upload,
participant enrollment, data clearing, or paid model request.

## Status

- 7: preview Matching, Today/history and Focus Timer implemented and exercised
  on vivo. See the companion priority-7-preview-results report.
- 8: microphone acquisition, timeout and release on Back verified. R3 reference
  loop and PC synthetic speech trials both returned noMatch. No successful human
  transcript or audible-output acceptance claimed. Exited Shadowing cleanly.
- 9: six original local reading starters A1–C2 with provisional-level notice;
  library works independently of classified vocabulary. Canonical practice
  filters up to 100 candidate words before starting. This is not full paged
  catalog coverage. R3 native failure fixed in R4; native R4 acceptance pending.
- 10: integration tests and twelve quality cases prepared; actual provider,
  model, spending ceiling and API key configured in app remain dependencies.
- 11: local sync and actual local Firestore emulator tests pass. Real cloud
  synchronization between two physical devices has not been tested.
- 12: internet-sourced pilot trained/exported and tested in real host app runtime.
  Candidate remains outside shipped assets; vivo/open-set acceptance pending.
- Scope confirmed by user: twelve items only; there is no item 13.

## Internet pilot

Official source: https://storage.googleapis.com/openimages/web/download_v7.html .
175 images with per-image attribution/license metadata retained: 100 train,
35 validation, 40 test; book, bottle, chair, coffee cup. Source IDs disjoint;
near-duplicate scene independence is not established. Validation selected model.
Object crops: candidate 37/40. Actual Dart full-frame preprocessing: 36/40.
Small four-known-class pilot only. Baseline full-frame exact mapped-word score
2/40 penalizes synonyms such as water bottle; it is NOT baseline vision accuracy.
Export parity: 35/35 validation top-1 matches. TFLite SHA256:
`eb39555e38ecb012c43a16b4300fbe323dfde84c939d22e4f80121fae473798a`.
Evidence: `build/verification/priority-12-training-20260911`.

Runtime corrections bound topK by class count, allow nullable background index,
and decode float32 output correctly. Legacy default background remains zero.
Permanent native regression uses a 1,612-byte synthetic fixture, not real images.

## Verification

Logs in `build/verification/priority-7-20260911`:

| Log | Result |
| --- | --- |
| priority9-integration-final.log | 292 passed |
| priority9-preview-final.log | 3 passed |
| priority10-ai-regression.log | 120 passed, no live requests |
| priority11-sync.log | 415 passed |
| priority11-firestore-rules.log | 175 passed, 0 failed/skipped; emulator shut down |
| priority12-runtime-green.log | 62 passed, includes real host pilot inference |
| priority12-full-frame.log | 1 passed, 40 held-out frames |
| priority12-float-regression.log | 1 passed, permanent fixture |
| priority9-12-analysis.log | exit 0, no errors/warnings, 4 inherited style infos |

Focused final diff check passed with line-ending advisories. Selected subsystem
checks are not a new full-repository run. No implementation edits after R4 builds.

## Artifacts and installation reconciliation

Both R4 builds passed with stable whole-source fingerprint
`85f7a0a79be5f571931c8c3d6be324b107a46b4722578d65d20135fa4e808c44`.
Under `build/verification/motivation-ui-20260908/device/`:

- Ordinary `lexiquest-learning-preview-v18-thai-r4-debug.apk`, SHA256
  `bd7c6c4bc8bdd32b789c8af8f82441097942843a832d7b4833910e3c8c075dd0`.
- Synthetic manual `lexiquest-learning-preview-manual-v14-thai-r4-debug.apk`, SHA256
  `db11b182dd63da6285061940b3b43603c57ea31535ae77d25e21f6209816c461`.

R4 streaming install lost USB. First corrected recovery used paced 1 MiB chunks,
but disconnected after 25,165,824 bytes. ADB subsequently returned at transport 6.
Read-only reconciliation verified staged size and installed R3 SHA256
`de633fe9eb2e2ec16b6225f92bbbe9bb48bcd3a2cbd83381b5b26c555303db47`.
Serial `9582188822004C6`, package `com.lexiquest.app`.
Partial `/data/local/tmp/lexiquest-r4-db11b182dd63.apk` preserved.
Evidence in `build/verification/motivation-ui-20260908/priority-9-12-thai-r4-preview-install/`:
`install.json`, `bounded-recovery.json`, logs. No blind retry or deletion.

No task-owned build/test/train/install processes remain; inventory only showed
the querying shell. The recovery script refuses existing staged files: do not
rerun unchanged. After a concrete USB stability correction, reconcile staged
prefix with local APK, then continue idempotently within recovery budget. Verify
full staged and installed hashes. Next native check: MyApp > Learn > CEFR > A1,
then library > vocabulary practice > Start, and clean Back. Human Shadowing
acceptance follows. Host/widget results do not establish these device results.

## Changed files and environment

### Subsequent R4 reconciliation

User requested continuation after confirming twelve-item scope. Device was
available on transport 6. A second recovery helper proposed 64 KiB writes with
100 ms pacing, but its prefix-integrity gate stopped before any device write.
The staged file is 25,165,824 bytes, yet SHA256 is
`0a1697e9fbd4731003db3eb4e253daf78978e3f3e2a5e607be825c9b83a4929e`;
the matching local APK prefix SHA256 is
`0479634c296786772b7ef5d3a0733b84949e05db2da5d2bebadd8f0c3752929a`.
An independent `adb exec-out cat` read reproduced the staged hash and size:
first differing byte offset 456, with 22,956,510 zero bytes in the staged data.
This proves corrupt/incomplete staged content, not its exact transport cause.
Do not resume from that prefix or install it. R3 was verified by SHA before
the failed gate; no installation or app-data mutation occurred this turn.
Evidence: `final-recovery.json`, `final-source-before.json` in the same install
directory; helper `build/verification/priority-7-20260911/resume-r4-final.py`.
The bounded recovery path is stopped; no task-owned process remains. Earlier
instruction to resume after prefix validation is superseded by this failure.
Next device step requires a corrected transfer path and a complete APK hash
match, followed by the native reading/Shadowing checks listed above. Live AI
still needs provider/model/budget and in-app credential configuration.

Reading: local_reading_catalog service, ai_reading_content_adapter,
local_content_fallback, local_reading_library_screen, cefr_article_reader_screen,
choose_mode_screen, synthetic device-manual-uat seed and reading/bootstrap tests.
Camera: model_manifest, litert_image_classifier, object_scanner_use_cases,
model/scanner tests and synthetic fixture. New tools: prepare_openimages_pilot,
train_camera_pilot, export_camera_pilot, camera_accuracy, test_camera_accuracy,
generate_float_classifier_fixture (all `.py` under `tools/`). Shadowing: two Thai
retry labels. Priority 7 files are documented in its companion report.
Plans: `docs/superpowers/plans/2026-09-11-priority-9-reading-starter.md` and
`2026-09-11-priority-12-camera-pilot.md`. Live AI cases:
`docs/development/2026-09-11-ai-tutor-quality-cases.md`.

Successful Python 3.12 ML environment: `C:/Users/Phet/.cache/lq12-20260911`;
dependency lock in priority-7 evidence. Initial long-path partial environment
preserved unused; no global Python or Windows setting changed.
