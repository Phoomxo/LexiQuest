# ADLC cycle 12 — Vivo post-fix, current gates, and release evidence

Date: 2026-10-26 (Asia/Bangkok)
Branch: `feature/associative-reading-loop`
HEAD: `f43aa0ff`
State: dirty working snapshot; engineering evidence only, production actions disabled

## Outcome

Cycle 12 reached **engineering-complete for the current local source**. A physical Vivo V2041 run exposed one must-fix camera lifecycle defect; the shared scanner use case was repaired with a readiness postcondition, covered by RED/GREEN tests, rerun on the device, and followed by fresh full/product gates and new signed APK/AAB artifacts.

This checkpoint does **not** claim release-ready, production deployment, Play acceptance, real-participant research authority, or complete physical-device coverage.

## Physical Vivo evidence

Device: `9582188822004C6`, Vivo V2041, Android 13/API 33, 1080×2408, density 440.

| Journey | Result | Evidence |
| --- | --- | --- |
| Preserve-data reinstall | PASS | `package-before-install.txt`, `package-after-install.txt`, `postfix-install.txt` |
| Cold/warm lifecycle | PASS | `cold-after-17s.png`, `warm-resume.txt`; no app crash/ANR pattern |
| Build identity/drawer | PASS | `drawer-bottom-build-info.png` |
| Password-reset App Link, cold | PASS | `app-link-reset-cold.png` |
| Verify-email invalid App Link, warm | PASS | `app-link-verify-warm.png`; safe Thai invalid/used state |
| 200% text portrait/landscape | PASS for tested shell | `font-200-portrait.png`, `font-200-landscape-confirmed.png`; content remains scrollable |
| Category blank save | PASS | `category-blank-error.png`; dialog remains open with inline error |
| Offline cold launch | PASS | `offline-cold-launch.png`; local shell loads without crash |
| Scanner permission/model/recovery | PASS after fix | `postfix-camera-result.png`, `model-download-actual.png`, `model-benchmark.png` |

Device settings were restored after capture: airplane mode off, font scale 1.0, autorotate on, user rotation 0, camera/microphone permissions denied. The pinned model remains in app-private data as test setup.

## Scanner defect and smallest complete fix

Observed defect: after Android permission lifecycle transitions, camera adapter initialization/resume could complete while `camera.isInitialized == false`. The UI could then show no preview, a disabled action, and no recovery message.

Root fix:

- `ObjectScannerUseCases.initialize()` now rejects a false-success camera initialization as `CameraFailureCode.initializationFailed`.
- `ObjectScannerUseCases.resume()` enforces the same postcondition.
- Two regression tests cover initialize and resume completing without readiness.

Focused scanner/screen tests: **17/17 PASS**. The physical post-fix run reached the explicit missing-model state, downloaded the verified pinned model (4,287,874 bytes), opened live preview, and completed:

- CPU/standard: 20 runs, median 27.8 ms, p90 31.8 ms, peak 626.5 MB.
- XNNPACK/speed: 20 runs, median 37.5 ms, p90 39.1 ms, peak 631.4 MB.

## Current-source verification

| Gate | Result |
| --- | --- |
| `flutter test --no-pub` | **1754/1754 PASS** |
| `flutter analyze --no-pub` | PASS, no issues |
| Product completion contract/format/analyze | PASS |
| Product completion Flutter tests | **727/727 PASS** |
| Firebase Auth emulator | **3/3 PASS** |
| Firestore rules emulator | **33/33 PASS** |
| Debug APK + model runtime integrity | PASS |
| Release APK model runtime integrity | PASS |
| `git diff --check` inside product gate | PASS |

The product test log contains an expected Drift multiple-database warning in a controlled test fixture; the gate completed with 727/727 passes.

## Signed engineering artifacts

The official field packager intentionally refuses a dirty worktree. These artifacts were therefore built and verified directly from this bounded snapshot and are labeled **engineering artifacts**, not field-release packages.

| Artifact | SHA-256 | Verification |
| --- | --- | --- |
| `lexiquest-adlc-cycle12-signed-postfix-20261026.apk` | `55262D798C4B2647CD3E550813C4722F16AFE82A4F35973FE81B1BDF515C6442` | APK v2 signature PASS; release model runtime PASS |
| `lexiquest-adlc-cycle12-signed-postfix-20261026.aab` | `FC84D53A518AF162A0F63EBC77BF1EF2F163737675D71E8271C7063AF1BFD069` | `jar verified` |

Signing certificate SHA-256: `E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`, matching the repository Firebase release-SHA evidence. The AAB uses a self-signed certificate without a timestamp; Play acceptance of this exact hash remains external evidence.

## LDPlayer current-snapshot matrix

The first current debug APK contained all ABIs (221 MB) and timed out during LDPlayer tablet installation. The corrected x86_64 artifact is 109,755,499 bytes, SHA-256 `35E3572A649CF4BF909454F1E5571DA4CE125788C389BE331842A9FD418AE6D3`; installation changed to bounded `adb push` + `pm install`.

| Profile | Result |
| --- | --- |
| 393×876 phone | PASS |
| 360×800 compact | PASS |
| 412×915 compact | PASS |
| 600×960 small tablet | PASS |
| 800×1280 tablet upper bound | PASS after adding a boot-readiness gate requiring `sys.boot_completed=1`, `dev.bootcomplete=1`, and the expected model for three consecutive probes |
| 1024×1366 medium tablet | PASS |
| 1280×800 landscape tablet | PASS |
| 800×479 height boundary | PASS |
| 800×480 height boundary | PASS |

All nine profiles rendered Login/Home, exposed clickable accessibility nodes, resumed `MainActivity`, and had zero fatal/Unhandled/RenderFlex/database-lock matches. All task-owned instances were stopped. LDPlayer does not prove hinge/posture hardware.

## `/critique` disposition

Target: Android core shell and object-scanner post-fix on Vivo V2041. Result: **40/40, P0=0, P1=0 after immediate repair**. Scope is deliberately limited to tested surfaces and must not be read as universal physical-device certification. Snapshot: `.impeccable/critique/2026-10-25T20-13-24Z__and-object-scanner-post-fix-on-vivo-v2041-5c4abdbd.md`.

## ADLC 1–12 disposition

| # | Workstream | Disposition |
| --- | --- | --- |
| 1 | Consolidate/checkpoint R11 | DONE by this checkpoint and manifest; no commit because the worktree contains broad pre-existing user work |
| 2 | Android responsive matrix | EMULATOR-COMPLETE: Vivo physical plus LDPlayer 9/9; physical low/high/fold/tablet and manual TalkBack remain external evidence |
| 3 | Sync R11 to Figma Cloud | SERVICE-BLOCKED: authenticated owner is `petch954100@gmail.com`; Cloud R11 `81:2` remains final8-era and Starter MCP quota was reached during current audit |
| 4 | Authentication/account lifecycle | ENGINEERING-COMPLETE; live Google chooser and production deletion adapters/authority remain external |
| 5 | Vocabulary/import | ENGINEERING-COMPLETE; optional OEM file-picker UAT remains |
| 6 | Activity catalog/exercises | ENGINEERING-COMPLETE for implemented 8/44 catalog; editorial/content UAT remains |
| 7 | Progress/mastery | ENGINEERING-COMPLETE; longitudinal efficacy is separate research evidence |
| 8 | Theme marketplace | ENGINEERING-COMPLETE baseline; catalog economics/content approval remains publication work |
| 9 | AI Tutor | ENGINEERING-COMPLETE BYOK/bounded; live provider key/cost/policy acceptance remains external |
| 10 | Voice/camera | ENGINEERING-COMPLETE locally and on tested Vivo scanner path; physical device-class quality remains |
| 11 | Settings | ENGINEERING-COMPLETE; manual TalkBack reading order remains |
| 12 | Offline/sync | ENGINEERING-COMPLETE local/emulator; production App Check/Firestore rollout remains external |

## Remaining release-only dependencies

- Figma Cloud final9/post-fix delta after the Starter MCP quota resets or the plan changes.
- Physical low/high/fold devices, hinge/posture behavior, manual TalkBack spoken order, and stakeholder UAT.
- Live Google account chooser completion, Play Console acceptance of the exact AAB, App Check valid traffic/enforcement, and production Firestore/rollout approval.
- Production research stays fail-closed/default-off until ethics/protocol/instrument approval plus trusted issuer/time authority exist.

## Evidence locations

- Vivo, signed artifacts, signatures, and manifest: `output/adlc-cycle12-vivo-2026-10-26/`
- LDPlayer current x86_64 matrix: `output/adlc-cycle12-ldplayer-x64-push-2026-10-26/`
- Full regression log: `tmp/adlc-cycle12-postfix-full-flutter.log`
- Product gate log: `tmp/adlc-cycle12-postfix-product-completion.log`
