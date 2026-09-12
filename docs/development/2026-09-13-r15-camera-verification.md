# R15.6 scanner runtime verification

## Source and scope
Worktree:C:/Users/Phet/.codex/worktrees/fa58/LexiQuest
Branch:feature/r15-camera-continuation
Base:765237e2aee536fe7991f00916a57b8949768e01 (accepted R15.0–5).
Local R15.6 implementation accepted; this document accompanies its commit.
Only scanner screen/gateway, their tests and preprocessing fixtures changed.
ObjectScannerUseCases, raw RGB pipeline, model identity, primary-label policy,
canonical vocabulary duplicate behavior and frozen contracts remain intact.

## Acceptance mapping
- A-CAM-01: existing permanent-permission/model-missing checks retained; new
  permission retry, download cancellation and successful retry to ready tested.
  Capture stays disabled before ready. Old download error cannot replace a new
  scanner's state; releasing a lease cancels its download.
- A-CAM-02: existing low-confidence use-case test uses throwing vocabulary access;
  UI explains uncertainty and offers retake, without automatic accept/write.
- A-CAM-03: primary-Unknown/secondary-Apple test retains unsupported primary.
  Unsupported UI offers retake and existing vocabulary/create CategoriesPage
  route, retaining its dependency-unavailable handling and canonical editor flow.
- A-CAM-04: real in-memory vocabulary tests retain normalized duplicate word ID
  and model source. Widget regression prevents concurrent accept, shows saving,
  blocks capture while saving and ignores obsolete save completion.
- A-CAM-05: existing covered-route late success/failure/cancellation and shared
  controller lease tests pass. New displayed-result replacement clears old
  vocabulary/save state. Save callback checks current lease/foreground/epoch.
- A-CAM-06: deterministic raw224 RGB and invalid-image tests retained. New
  non-square center-crop fixture checks all triplets against [17,83,201].
  JPEG EXIF6 checks clockwise color positions with JPEG tolerance3.
  Five open/pause cycles dispose each session once. Generic native initialization
  failure now disposes the pending session, maps initializationFailed and can
  reopen. Existing in-flight pause/resume/dispose tests pass.

## Commands and evidence
Tests used tool/cli/verify-scope.ps1 -Level Targeted -Area Runtime with explicit
-TestTargets and optional plain-substring -TestName. Operations serialized.
Log root:build/verification/765237e2aee536fe7991f00916a57b8949768e01/
Directories contain Explicit-Flutter-tests.stdout.log and stderr.log.

| Gate | Result | Seconds | Log directory |
| --- | --- | --- | --- |
| Initial screen R15.6 regressions | 0 passed/3 failed | See raw log | d37a96e60741-d8f2afea6a01 |
| Permission fixture corrected to800x1200 | expected missing retry button | 7.57 | 6ddc0f6434ff-ae1eed13fd99 |
| Screen R15.6 incl. downloads | 4 passed/1 stale-download failure | 8.48 | d37a96e60741-23226cc53aa0 |
| Gateway R15.6 | 1 passed/1 generic-error failure | 6.73 | 09b51ab6f510-4fa20633eb04 |
| Screen+gateway+preprocessor R15.6 | 9 passed | 8.42 | 8c68db20f124-ec9bb0a4563b |
| Unsupported manual route | expected missing retake/route | 8.03 | 463ef60cde71-a44c54fb7c43 |
| Full4 A-CAM targets | 41 passed | 10.11 | 964232b18937-89b8cde2b3d8 |
| Extended cancellation→retry→ready | 1 passed | 7.89 | 43e77341d5b7-139f7d6f854b |

Full4 targets:test/screens/object_scanner_screen_test.dart,
test/features/media_practice/object_scanner_use_cases_test.dart,
test/features/media_practice/image_preprocessor_test.dart,
test/features/media_practice/plugin_camera_gateway_test.dart.
Broad fingerprint:89b8cde2b3d8d0939f5fcb03ceaf4534a18f2227fefe29e549d674fb7a9e9909.
Final fingerprint:139f7d6f854b2e353b032c5a8c3fe4d86e8e088895aba95be9478a591bf39cda.
After broad pass, production changes only added braces around two guards;
download test extended and rerun. No semantic production change invalidates
remaining broad evidence. Counts overlap; do not sum them.

flutter analyze --no-pub over the four production and four test paths:
initial2 brace style infos, then exit0/no issues,6.55s elapsed (analyzer4.0s).
Logs:build/verification/r15-camera-analysis.log and
build/verification/r15-camera-analysis-final.log.
Diff reviewed solo. CRLF already tracked for screen/test; diff --check with
command-local core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol
passes. No Git/global configuration changed.

## Visual evidence and limits
Actual Flutter390x844 at200% text reviewed:
build/verification/r15-visual/after/r15-camera-mapped-text200.png and
r15-camera-unsupported-text200.png. Text/actions fit; action row wraps.
Preview is synthetic, not evidence of physical accuracy. No physical/TalkBack/
human/live-service/release/research acceptance claimed. No APK build/install;
combined UI source-freeze device verification remains later. No new storage,
authority, research record, upload, paid service or model change.
Generated registrants have EOL-only status/no content diff and are excluded.
All task-owned verification processes completed. Logs/PNGs untracked here.
Actual token/credit usage unavailable; no savings claim.
