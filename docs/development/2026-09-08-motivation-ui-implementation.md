# Motivation UI — Implementation ledger

ผู้ใช้อนุมัติให้พัฒนาตามแผนเมื่อ 8 กันยายน 2026 งานปัจจุบันคือ D0 และ Phase A พร้อมการตรวจระบบหลังรวม UI; B/C เป็น decision packages ตามแผน ไม่ใช่การเพิ่มระบบสัปดาห์/ภารกิจ/สังคมทั้งหมดโดยอัตโนมัติ

- Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
- Branch: `codex/pair-matching-pm0-pm8`; baseline HEAD: `788e90e62b1694c20945734787723c168b6a6ab2`
- Approved plan: `docs/superpowers/plans/2026-09-08-motivation-workflow-evolution.md`
- Evidence: `build/verification/motivation-ui-20260908/`
- Baseline: 1,490 existing file hashes in `workspace-before.json`; 1,121 source/tool/test files copied under `baseline/` for incremental review. Preserve all existing dirty changes.
- Root owns all Flutter/Dart/test/build/dependency/codegen commands until explicitly handed off. Agents must not run concurrent toolchains.

## Tasks

| Task | Status | Owner / evidence |
| --- | --- | --- |
| Preflight / focused baseline | PASS 33 tests | Root; `logs/baseline-focused.log` |
| D0 interactive prototype and state review | Internally accepted A0–A4 | Actual browser interactions; `reports/D0-root-review.md`; synthetic prototype is not native UAT |
| A0 navigation / delegate integration | Implemented; pre-C1 review approved | `logs/A0-A1-A3-fixes-green.log` 100 PASS including integration; full queue / stale owner / gate checks retained |
| A1 Today planning / recovery / review preview | Implemented; pre-C1 review approved | Actual reader omitted-review fallback RED4 then `logs/A1-reviewed-green.log` 31 PASS; no fake empty goal state |
| A2 local date/time and one-time reminder | Implemented; pre-C1 final finding fixed | All A2 checks passed in combined254 PASS/one A3 failure later fixed. Denied-retry display bug reproduced and fixed; `remediation-20260907/motivation-a2-retry-green-20260908T062826566Z` 33 PASS, exit0 stable; R review finding closed |
| A3 truthful progress / companion language | Implemented; pre-C1 review approved | Owner replacement RED11/1; duplicate loader fixed; 100 PASS integration rerun includes Mastery. No silent same-dependencies owner-change observation claimed |
| A4 actual local avatar preview | Implemented; pre-C1 review approved | `logs/A4-green-5.log` 48 PASS; actual pixels, preview visibility, durable purchase/equip/ack/restart/fallback |
| C1 template / typography / centered summaries | Implemented; source/pixel findings closed; final Flutter regression PASS | Shared theme/summary/picker; narrow TimePicker, Mastery alignment and Pair companion locale corrected with observed failures and follow-up review. C1 incremental31 Dart files plus19 individually reviewed golden references. Focused53 PASS includes scroll/tap/navigation/locale changes; final F3 5,018 PASS includes the earlier F1 touched/accessibility cases |
| D1 real listening / D2 visual and flow QA | D1 not conducted; D2 current99 captures reviewed | `motivation-c1-visual-final-20260908T074726587Z`:12 PASS,99PNGs(base28/focused30/results27/context14). Comprehensive1421-input fingerprint ddd043c8… stable. All images opened in same-scale groups;4 changed after final fixes re-opened,95 hashes identical. Independent focused findings closed. Widget captures are not native/UAT |
| B/C decision packages | Written; engineering integration still pending | `docs/development/2026-09-08-motivation-next-decisions.md`; B/C future capabilities not implemented; D1 real listening not conducted |
| F final whole-system / APK | Prior C1 F0–F8 PASS; device-discovered UI corrections now require refreshed affected checks/build | Prior C1: F0 format/diff55 Dart files; F2 No issues; F3 5,018 PASS/0fail/skip/error/parseFailures; F4 core/controls/media3 flows PASS; F5 backend55+76+75=206 PASS, CLI25/25; F6 Firestore/Auth and local Supabase lint/rollback contract PASS; F7 current8/44 and test-plan checks PASS; F8 debug build92.93s PASS at1498 inputs/cdf39cff6bae1a280b2c4ae8ef6b3901fe65986e8e01d88f2ef53ef1c210cc29. Subsequent phone capture found shared header overlaps status bar and partial speech feedback/error conflict. Their local fixes are in progress; prior passing evidence must not be labeled current-source completion |
| F9–F11 native/device/TalkBack/UAT/three hours | Native six cases + sentinel PASS; core Android journey23 phases PASS; manual UAT pending | `native-execution-logged/journal.json`: driver0, all model/camera-inventory/TTS oracles PASS. User twice confirmed hearing sound, without separate language-quality ratings. `core-execution-export-observed`: driver0, all23 phases/46 transitions and teardown PASS, source/pins stable. Both restore original APK and temporary Flutter log tag, leaving global log tag unchanged. Failed phase06/22 runs preserved; bounded continuous drag and wait-for-export-before-lazy-status corrected the integration harness only. Core uses synthetic DB/external gateways,1280x900 logical test viewport and in-memory export recorder: not phone-layout UAT or proof of writing an external file. Actual camera capture, microphone recognition, TalkBack and180-minute journey remain unfinished |
| R review / rollback / handoff | A0–A4/C1 and core harness deltas reviewed; device/UAT closure pending | `reports/R-final-review.md`, `reports/C1-final-review.md`, four visual reports and `reports/core-android-scroll-diagnosis.md`; preserve schema v24, data, rewards, pending recovery, research gates |

## Operating decisions

- Brainstorming/design approval is satisfied by the completed eleven-agent decision and the latest implementation authorization. D0 is an internal prototype/interaction check, not an additional permission question.
- Use the existing linked worktree. No new worktree, reset, unrelated reformat, dependency update, commit, deployment, real enrollment or upload is part of this execution.
- Each application writer receives disjoint files and must pause before root runs tests that consume those inputs. Tests for behavior changes must be observed RED before implementation; purely visual adjustments use meaningful visual/interaction checks.
- Record intermediate failures and corrected evidence; only mark a task complete after its scope, code quality and current-source checks pass.

## Native follow-up and object-recognition proposal

User confirmed native speech transcription `station`. Actual device image07 showed shared header under the status bar; image08 showed a valid transcript together with an error. Root observed focused RED before fixes: SafeArea2 cases→GREEN2, speech4→GREEN32, camera lifecycle1→GREEN26, label mapping5→GREEN34. These run counts overlap and must not be added as a unique-test total. Independent reviews are `native-inset-review.md`, `native-speaking-review.md`, `native-camera-lifecycle-review.md`, and `native-label-mapping-review.md` under the evidence reports directory.

Camera retry after user instruction: real verified model download completed through the UI. Image22 initially showed dark preview and invalidImage; images23/24 later show live camera and classification joystick34%, with an object visually resembling a screwdriver. Camera capture/inference observed; classification accuracy not accepted. No evidence establishes the cause of the original dark preview. Camera inventory success alone was never capture proof. Human and assistant observations remain separately attributed in `device/human-observations.json`.

The pinned model includes screwdriver, but the old vocabulary substring fallback could map it to river/แม่น้ำ. Current source uses exact lookup plus one reviewed coffee cup→cup alias and rejects empty/unreviewed labels; all127 catalog entries are unchanged. This corrects a translation defect, not model accuracy. Unreviewed labels can now correctly lack a Thai mapping. Model weights/thresholds are unchanged and the installed e780 manual APK still predates these fixes until explicitly updated.

User asked how to achieve >90% and selected both classroom/home and tools with a limited list. `2026-09-08-object-recognition-accuracy-proposal.md` is a30-class pilot proposal: correct mapping, selected-object crop, diverse grouped data, fine-tuning, calibration, held-out tests, actual quantized-device evaluation. No training/replacement, collected user-photo dataset, accuracy90%, or rollout is claimed. Test-size/coverage protocol remains to be set before training.

Current-source delta report `reports/native-followup-source-delta.json` verifies exactly4lib+4test+2generated-plan changes from35ac4a80… to35365992…; backend/policy/dependency/platform/assets inputs unchanged. Analyzer initially found one speech collection-style lint; root corrected it without changing behavior and current7-root analyzer passes. Current full regression5,029PASS/0fail/skip/error/parseFailure, all3hostjourneys, contracts and ordinaryAPK PASS. Results `2026-09-08-native-ui-followup-results.md` supersede the old F summary for these gates. OrdinaryAPK b94b5fff… archived; manualfixture89a07a60… installed/launch/hash/source verified after reconciling a transient USB-disconnect acknowledgement. New manual visual UAT remains open because launcher navigation/UIA hierarchy could not yet be confirmed; all root toolchain/install processes finished. No model-training/accuracy90% claim.

## Prior verified APK and local-policy closure

`build/verification/motivation-ui-20260908/device/lexiquest-ui-consistent-debug.apk` is the ordinary debug build from final source: SHA256 `9efcf889d3bae180b1cad0c383c9db007375b9f2a9b4b6f961aa343b5427b707`,261,534,512bytes, Android package `com.lexiquest.app`,1.0.0/code14, verified single debug signer SHA256 `1f10bbeedb0b8f18bcbb789c31d862bcfe9a3d146920033fb93eb1d228b0c5b4`. Gate `motivation-f8-apk-20260908T084452944Z`; identity/arguments and complete signer/badging logs accompany the archive. Build uses no Dart defines: internal AppBuildInfo defaults remain1.0.0+1/development, distinct from Android package version14. Warnings about future Kotlin plugin migration and SDK XML-tool version remain maintenance notes; build exited0. This is not a release-signed artifact.

Supabase project/container/volume identity `lexiquest-local` was verified before the rollback-only SQL. Existing migration20260727000000 was already applied; no reset or migration write needed. Lint returned no findings, contract endedROLLBACK, task-started DB stopped with volume retained (same creation2026-09-07T13:23:35Z/labels). Evidence prefixes `motivation-f6-supabase-start/lint/contract/stop` and `logs/f6b-whole-before/after.json` retain actual results.

Installed-before backup `device/installed-before-motivation.apk` SHA256 `50a42c1ce50ae84038bddf36f4df02209fa0eb7cf1a4a12ca69e8a1b443c2559`,223,955,799bytes was read and hashed from vivo. Native helper failures are evidence-tool/device-connection findings; they do not invalidate the completed host UI gates, and they do not count as native test success. Never repeat an uncertain install before checking actual installed identity.
