# R15 Implementation and Acceptance Contract

> **For agentic workers:** ใช้ executing-plans ทำทีละ package โดยผู้พัฒนาคนเดียว ไม่เรียก subagents ไม่แก้ทุก subsystem พร้อมกัน

**Goal:** แปลง [engineering spec](../specs/2026-09-12-r15-engineering-spec.md) เป็นงานที่เลือกไฟล์ เขียน regression ตรวจภาพ และปิดงานได้โดยไม่ต้องเดาความหมายจาก roadmap

**Architecture:** UI consumes existing authorities; เปลี่ยน internal implementation/เกมตาม spec ได้ รักษาความถูกต้องของ historical data และ compatibility. Read [source register](../specs/2026-09-12-r15-source-register.md) เพื่อแยก observed behavior กับ proposed design

**Tech stack:** existing Flutter/Dart/Drift/Python/loopback tooling; ไม่เพิ่ม dependency จากเอกสารนี้

**Baseline:** `8c160f87d77d8beb8ace2d8f2b7b0e92acb297ac`. ทุกกรณีด้านล่างเป็น acceptance ที่ต้องดำเนินการ ไม่ใช่ผล PASS แล้ว. รูปแบบ Given/When/Then เป็น executable test specification; production patch ต้องเขียนตาม source ณเริ่ม package ห้ามนำชื่อ proposed DTO ไปอ้างว่ามีจริงก่อนเพิ่ม

## 1. Working protocol และขอบเขตไฟล์

R15 เป็นหลาย subsystem จึงใช้ queue ใน roadmap แต่ละ package เป็นหน่วย implementation/review/commit ที่แยกได้ ขั้นตอนทุก package:

1. `git status --short`, อ่าน diff และ requirement IDs ของ package; pin HEAD และ working diff ถ้ามี ไม่ overwrite งานคนอื่น
2. เปิด existing test files ในตาราง ใช้ fixture factory/import ของไฟล์นั้นเพื่อไม่เพิ่ม authority จำลองที่มี semantics ต่างจาก production
3. เพิ่ม test case ตาม acceptance ID ให้ fail ที่ assertion ของ behavior ที่เปลี่ยน; รัน command กลุ่มที่กำหนดและเก็บ actual failure ห้ามนับ missing SDK/import error เป็น RED สำเร็จ
4. แก้ source ใน write set ให้ผ่าน spec; internal helper/private widget แบ่งได้เอง ถ้าขยาย write set ให้บันทึก dependency reason ก่อนแก้
5. รัน tests กลุ่มเดิมให้ผ่าน แล้วตรวจ named requirements/edge cases; test expectations เก่าที่ขัด spec ใหม่ปรับได้พร้อม rationale และ replacement coverage ห้ามลด assertion เพื่อกลบ defect
6. UI ต้องเก็บภาพจาก Flutter fixtures เดียวกัน before/after และเปิดดู; verify text overflow/focus/scroll ทั้ง state ที่เปลี่ยน ไม่รับเพียง golden update
7. ตรวจ diff, exact-source test evidence, source fingerprint/checkpoint แล้ว commit เฉพาะงานที่ตรวจแล้วเมื่อ execution authorization ครอบคลุม; ไม่ push/deploy จากคำสั่งวางแผน

ตาราง path อิง repo root; shorthand test path ใน acceptance rows หมายถึงไฟล์ที่ระบุใน write-set นี้ ไม่ใช่ไฟล์ใหม่ที่เดาขึ้น

| Package | Modify/read existing source | Existing tests ที่ต้องเริ่มจาก |
| --- | --- | --- |
| R15.0 | roadmap, R14 checkpoint, prototype3 comparison, Git diffs ของ worktrees ที่เกี่ยวข้อง | documentation consistency; ไม่รัน Flutter สำหรับ docs-only |
| R15.1 | `lib/screens/main_navigation_screen.dart`, `lib/screens/learning_history_screen.dart`, `lib/features/today_hub/application/today_hub_use_cases.dart`, `lib/features/progress/data/drift_personal_learning_profile_reader.dart` | `test/screens/main_navigation_screen_test.dart`, `test/screens/learning_history_screen_test.dart`, `test/scenarios/file_backed_sync_recovery_test.dart`, `test/features/account/local_data_deletion_test.dart` |
| R15.2 | `lib/features/learning/pair_matching/presentation/pair_board_view.dart`, `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`, `lib/config/m3_theme.dart` | `test/features/learning/pair_matching/pair_board_view_test.dart`, `test/features/learning/pair_matching/pair_matching_experience_host_test.dart`, `test/features/learning/pair_matching/pair_board_accessibility_test.dart`, `test/features/learning/pair_matching/pair_board_golden_test.dart` |
| R15.3 | `lib/screens/today_hub_view.dart`, `lib/screens/choose_mode_screen.dart`, `lib/screens/learning_pack_catalog_screen.dart`, `lib/config/m3_theme.dart` | `test/config/m3_theme_test.dart`, `test/screens/today_hub_screen_test.dart`, `test/screens/learning_pack_catalog_screen_test.dart` |
| R15.4 | `lib/features/learning/application/unified_lesson_controller.dart`, `lib/features/learning_packs/domain/content_quality_policy.dart`, `lib/screens/review_center_screen.dart`, `lib/screens/learning_history_screen.dart` | `test/features/learning/unified_lesson_controller_test.dart`, `test/features/learning_packs/content_quality_policy_test.dart`, `test/screens/review_center_screen_test.dart`, `test/screens/learning_history_screen_test.dart` |
| R15.5 | `lib/screens/mastery_dashboard_screen.dart`, `lib/features/progress/domain/personal_learning_profile.dart`, `lib/features/progress/data/drift_personal_learning_profile_reader.dart`, `lib/screens/learning_goals_screen.dart`, `lib/screens/study_reminder_settings_screen.dart` | `test/screens/mastery_dashboard_screen_test.dart`, `test/features/progress/personal_learning_profile_test.dart`, `test/features/reminders/study_reminder_use_cases_test.dart` |
| R15.6 | `lib/screens/object_scanner_screen.dart`, `lib/features/media_practice/application/object_scanner_use_cases.dart`, `lib/features/media_practice/application/image_preprocessor.dart`, `lib/features/media_practice/data/plugin_camera_gateway.dart` | `test/screens/object_scanner_screen_test.dart`, `test/features/media_practice/object_scanner_use_cases_test.dart`, `test/features/media_practice/image_preprocessor_test.dart`, `test/features/media_practice/plugin_camera_gateway_test.dart` |
| R15.7 | `tools/prepare_openimages_pilot.py`, `tools/train_camera_pilot.py`, `tools/export_camera_pilot.py`, `tools/camera_accuracy.py`; manifest/classifier อ่านเพื่อ compatibility ไม่เปลี่ยน shipped model | `tools/test_camera_accuracy.py`, `test/features/device_model/model_manifest_test.dart`, `test/features/device_model/litert_image_classifier_test.dart` |
| R15.8 | existing Today/result/goal/reward presentation ที่ route ใช้อยู่, `lib/config/m3_theme.dart`; source writer ของ Quest/Reward อ่านเพื่อ identity ไม่เพิ่ม writer | Pair host tests ข้างต้น, `test/screens/mastery_dashboard_screen_test.dart`, `test/features/sync/reward_transaction_sync_test.dart` |
| R15.9 | `lib/screens/ai_tutor_screen.dart`, `lib/features/ai_tutor/domain/ai_tutor_contracts.dart`, `lib/features/ai_tutor/application/ai_tutor_use_cases.dart`, `lib/features/ai_tutor/data/openai_responses_gateway.dart`, `lib/features/ai_tutor/data/openai_compatible_gateway.dart`, `lib/features/ai_tutor/data/anthropic_gateway.dart` | `test/screens/ai_tutor_screen_test.dart`, `test/features/ai_tutor/ai_tutor_use_cases_test.dart`, `test/features/ai_tutor/ai_gateway_adapters_test.dart`, `test/features/ai_tutor/ai_gateway_loopback_test.dart` |
| R15.10 | touched source only + existing verification tooling; expand only for reproduced voice/sync defect | `test/screens/shadowing_challenge_screen_test.dart`, `test/features/media_practice/speech_practice_use_cases_test.dart`, `test/scenarios/file_backed_sync_recovery_test.dart`, `test/features/sync/cloud_sync_policy_test.dart`, `test/features/account/local_data_deletion_test.dart` |

## 2. Acceptance cases

### A-UI — templates/tokens/accessibility (UI-01–08/UI-12)

| Case | Given / When | Required result |
| --- | --- | --- |
| A-UI-01 | T-01–07 ที่เปลี่ยน, widths320/390/840, textScale1/2, light/dark | ไม่มี overflow exception, Thai marks ไม่ถูกตัด, action สำคัญอ่านครบ; 320/text2 content-mode gridหนึ่งคอลัมน์ |
| A-UI-02 | keyboard เปิดใน search/composer แล้ว scroll ท้ายเนื้อหา | focused field และ CTA ที่เกี่ยวข้องไม่ถูก keyboard/footer ทับ แถวท้ายเลื่อนเห็นเต็ม |
| A-UI-03 | semantic tree พร้อม selected/correct/wrong/support | label ระบุสถานะได้โดยไม่อาศัยสี, hidden tile ไม่รับ focus, controls≥48×48logical pixels |
| A-UI-04 | platform disableAnimations=true, user reduceMotion=false | effective reduced motion ยัง true; animation0ms แต่ feedback/result information ยังอยู่ |
| A-UI-05 | foreground/background roles ที่ใช้จริงทุก theme | contrast ratio ไม่ปัดค่าก่อนเทียบ ≥4.5 สำหรับ text; snapshot สีไม่แทนการคำนวณ contrast |
| A-UI-06 | metadata ยาวจน gridอ่านยากและเลือกแทนด้วย listตามUI-07 | บันทึก before/after+source decision, listมีครบชื่อ/จำนวน/CTAและผ่านกรณี01–03 |

Visual evidence ใช้ fixture namespace synthetic-r15 และ capture filename `A-UI-01-T01-w320-s2-dark.png` แบบเดียวกันทุก template บันทึก viewport/textScale/theme/route/source pinใน report; images เป็นผลที่จะสร้างตอน implementation ไม่ใช่ไฟล์ที่มีแล้ว

### A-NAV — Today/library (UI-09/10, SYS-01)

| Case | Given / When | Required result |
| --- | --- | --- |
| A-NAV-01 | canonical snapshot มี resumable session และ due review / เปิด Today | primary actionจากcanonical order, เลือกฝึกเองยังอยู่, sessionเริ่มเมื่อกดเท่านั้น |
| A-NAV-02 | มี assigned assessment ที่ authority valid / เปิดToday | ไม่ถูกซ่อนหรือแทนด้วย recommendation ที่ widget คำนวณเอง |
| A-NAV-03 | recommendation stale/corrupt/unavailable แต่ reviewพร้อม | เฉพาะ dependencyนั้นบอกไม่พร้อม; review/เลือกฝึกยังใช้ได้ ไม่มี fake session |
| A-NAV-04 | categoryว่างเทียบ searchไม่ตรง / ค้นหาแล้วล้าง | copyและactionตรงแต่ละสถานะ; ล้างค้นหาแล้วแสดงเนื้อหาเดิม |
| A-NAV-05 | snapshot ownerA แล้วเปลี่ยนBก่อน action | ไม่เปิดเรียนของA; refreshด้วยB; ไม่มีrowsของAถูกส่งต่อ |

### A-PAIR — learning feedback (PAIR-01–03/UI-11/12)

| Case | Given / When | Required result |
| --- | --- | --- |
| A-PAIR-01 | unmatched valid pair / selectจนengineรับcorrect | feedback check+ถูกต้องทันที; durable attemptเกิดแล้วก่อน450ms; ที่449msยังเห็น, หลัง600ms slotsว่างเดิม |
| A-PAIR-02 | selectionสองคำผิด / acceptincorrect | ไม่มีsuccess; เห็นคำอธิบายตามrepair policyจนactionถัดไป; no forced reveal |
| A-PAIR-03 | guidedCompletion / confirm support | แสดงสำเร็จด้วยตัวช่วย; ไม่ใช้independent-correct label; authoritative attempt roleคงถูกต้อง |
| A-PAIR-04 | เหลือคู่สุดท้าย / ตอบถูกและadvancefakeclock | engineterminalและpersistก่อนanimationจบ, resultแสดงเมื่อ600ms, rewardจำนวนเดิม |
| A-PAIR-05 | doubletap/rebuild/repeatedstate ระหว่างepisode | operation identityไม่เปลี่ยนเพราะanimation, attempt/rewardไม่เพิ่มซ้ำ |
| A-PAIR-06 | route dispose หรือowner/sessionเปลี่ยนก่อน600ms | ไม่มีlatecallback setState/route/reward, episodeเก่าไม่ปรากฏหน้าใหม่ |
| A-PAIR-07 | restartแล้วhydrate terminal | resultทันที ไม่มี600ms replay และไม่มีsuccess animationทุกmatched pair |
| A-PAIR-08 | reducedmotion แล้วfinalpair | no forced delay, resultและsemantic summaryครบ ไม่พึ่งTTSเพื่อจบ |
| A-PAIR-09 | หลายคู่ถูกใกล้กัน / final acceptance | episodeแยกwordidentity, finalwaitไม่เกิน600msจากfinalacceptance ไม่ต่อคิวทุกคู่ |

ใช้ `tester.pump(Duration(...))` สำหรับขอบเวลาแต่ละสถานะ แทน `pumpAndSettle` เพื่อไม่กลบช่วงfeedback. Assert persistenceผ่าน canonical fake/store ที่ testsเดิมใช้ ไม่อ่านจำนวนwidgetมาแทนจำนวนattempt

### A-LEARN — content/review (LEARN-01/02, DATA-04)

| Case | Given / When | Required result |
| --- | --- | --- |
| A-LEARN-01 | firstattempt5/6 แล้วrepair1/1 | mainยัง5/6, repair1/1แยก มีป้ายฝึกซ้ำ; ไม่มีรางวัลเพิ่มโดยpresentation |
| A-LEARN-02 | flashcardจำได้หรือreading exposure / result/history | บอกชนิดกิจกรรม ไม่แสดงaccuracy100%จากself-report/exposure |
| A-LEARN-03 | original title/version unavailableแต่catalogปัจจุบันมีชื่อ | ใช้missing-metadata copy ไม่เติมย้อนหลังหรือเปิดreplayด้วยcontentผิดรุ่น |
| A-LEARN-04 | valid explanation / เปิดรายละเอียดและไปข้อถัดไป | สรุปและรายละเอียดตรงcontentversion; ข้อใหม่เริ่มprompt, เปิดรายละเอียดไม่กระชากscroll |
| A-LEARN-05 | explanationไม่พร้อมหรือversionmismatch | แสดงไม่พร้อม ไม่เรียกAIอัตโนมัติ ไม่มีเฉลยที่เดา |
| A-LEARN-06 | due reviewข้ามวันด้วยinjectedclock/timezone | queueตรงpolicy, restartไม่เลื่อนdueเอง; ไม่มีการแก้DBผู้ใช้จริงเพื่อให้มีคำทบทวน |

### A-DATA — dashboard/persistence (DATA-01–05)

| Case | Given / When | Required result |
| --- | --- | --- |
| A-DATA-01 | accuracyavailable, correctCount5,sampleSize6 | แสดง5/6กับเปอร์เซ็นต์ตามrounding policyเดียวในview; ห้ามแสดง5/5 |
| A-DATA-02 | noEvidenceหรือsampleSize0 | ไม่มีNaN/dividebyzero/0%proficiency; emptycopyตรงT-05 |
| A-DATA-03 | activeDuration79sแต่เปิดแอปนาน10min | effortแสดง79sตามformat ไม่แสดง10min |
| A-DATA-04 | XPเพิ่มแต่masteryไม่เปลี่ยน | XPsectionเปลี่ยน masteryไม่เพิ่มตามXP |
| A-DATA-05 | localweekboundary/UTCต่างวัน | calendarและdashboardใช้ช่วงเดียวกัน; overalldataไม่ติดป้ายweek |
| A-DATA-06 | sessioncommit→restart→read; replay retry/lostack | history/profileสอดคล้องledger, identityเดิมไม่writeซ้ำ |
| A-DATA-07 | owner switch/export/delete | cacheไม่ข้ามowner; export/deleteครอบคลุมข้อมูลที่เพิ่มจริง ไม่มีorphanownerrows |

### A-CAM — scanner runtime (CAM-01/02)

| Case | Given / When | Required result |
| --- | --- | --- |
| A-CAM-01 | permissiondenied/modelmissing/downloadcancel | copyและrecoveryตรงstate ไม่เปิดcaptureก่อนready |
| A-CAM-02 | classificationsทั้งหมดต่ำกว่าthreshold | notConfident, ไม่มีaccept/write; มีถ่ายใหม่ |
| A-CAM-03 | primarylabelไม่มีmappingแต่labelรองมี | unsupportedLabelตามpolicy, ไม่แอบแทนคำหลักด้วยคำที่แปลได้ |
| A-CAM-04 | mappedresult / acceptสองครั้ง | ได้wordเดิมตามnormalizedduplicatepolicyและmodelsource; ไม่สร้างสองคำ |
| A-CAM-05 | captureinflight→lease/ownerเปลี่ยน→late result | ไม่เปิดsaveของผลเก่า; release/pauseไม่ปิดpreviewใหม่ |
| A-CAM-06 | rotation/crop/RGBfixturesและopencloseซ้ำ | tensorinputตรงexpected, runtimecleanupครบ;ไม่อ้างphysicalaccuracy |

### A-MODEL — candidate evaluation (CAM-03)

- A-MODEL-01: duplicate source-group/hashข้ามsplit หรือ license/provenanceหาย → evaluatorปฏิเสธdatasetก่อนtrain/evaluate
- A-MODEL-02: validation/testต่ำกว่าminimumในspec → status insufficient-coverage ไม่มีfallbackลดminimumหลังเห็นคะแนน
- A-MODEL-03: softmax4classes/max≥0.25กับthreshold0.15 → รายงานunknown gateใช้ไม่ได้ ไม่claimunknownrejection
- A-MODEL-04: validation-selectedconfig/modelhashfreezeแล้วเปิดfreshtest → reportperclass,unknownfalseaccept,knowncorrectaccepted,counts,Wilsonintervals; ห้ามปรับthresholdจากtest
- A-MODEL-05: pairedbaseline/candidateใช้imageIDs/preprocessเดียวกัน → มีcasealignmentครบ ไม่เปรียบเทียบคะแนนคนละชุด
- A-MODEL-06: resourcegates/coverageไม่ผ่านหรือphysicalevidenceไม่พร้อม → retain-baseline; shippedmanifesthashไม่เปลี่ยน; packageอื่นเดินต่อ

Expected report fields: datasetVersion, splitGroupRule, licenseLedger, imageHashes, labelMap, modelHash, manifestHash, preprocessingVersion, thresholdSelectionSplit, frozenConfigHash, perClassCounts, knownCorrectAccepted, unknownFalseAccepted, intervals, coldWarmLatency, memoryMeasurementMethod, environment, failureReasons, decision. Missingfieldหรือnonfinite metricเป็นreportvalidationfailure ไม่เติมศูนย์แทน

### A-MOT — motivation (MOT-01)

- A-MOT-01: terminalrewardtransactionหนึ่งรายการ→rebuild/reopenresult → amountไม่เพิ่ม; animationไม่ออกwrite
- A-MOT-02: goalทำครบจากeffort→summary → ใช้คำเวลา/กิจกรรมไม่อ้างภาษาเก่งขึ้น; masterysectionอ่านauthorityของตน
- A-MOT-03: reducedmotion/noaudio→จบบท → ยังเห็นรางวัล/nextactionครบ ไม่มีmodalบังคับซ้ำหรือfriendlock

### A-AI — bounded tutor context (AI-01–06)

| Case | Given / When | Required result |
| --- | --- | --- |
| A-AI-01 | 4completedpairs / ส่งmessageใหม่ | ส่งได้ล่าสุดไม่เกิน3คู่และ3000codepoints, latestmessageแยก ไม่ซ้ำ |
| A-AI-02 | คู่ใหญ่เกินcap/มีThai+emoji | ตัดทั้งคู่เก่าตามpolicy ไม่ตัดsurrogateหรือhalfturn; ไม่มีsystemroleจากlearner |
| A-AI-03 | newchat/owner/provider/model/scenariochange | contextเก่าไม่ถูกส่ง; resultของcancelledoperationไม่ลงchatใหม่ |
| A-AI-04 | nullcontextcallerเดิม | ใช้A1/conversation/nohistoryที่ประกาศ ไม่crashหรือแอบใช้B1–B2 |
| A-AI-05 | conversation/explanation/practice | payloadcaps160/320/480หรือlowerconfiguredcapตรงทั้ง3adapters; usageunknownไม่เดาcost |
| A-AI-06 | completeThai/Markdownlike/plaintextreply | คำทุกคำอ่านได้; busy→completeไม่ทำquestionหาย; errorไม่สร้างassistantanswerปลอม |
| A-AI-07 | 401/402/429/malformed/timeout/cancelผ่านloopback | errorcategory/accounting/operationcountถูก, socketsปิด, credentialsไม่อยู่prompt/log |
| A-AI-08 | lackkey/network / เปิดAIแล้วกลับเรียน | มีทางตั้งค่าหรือกลับ ไม่มีการซื้อ/subscribeอัตโนมัติ; ordinarypracticeยังใช้ได้ |

Live rubric ใช้12cases G1–R2 จาก AI quality document; ไม่มีliveprovider/model/budgetให้ปิดเฉพาะsyntheticengineeringพร้อมสถานะlive-not-run ไม่อ้างscoreด้านความถูกต้องของการสอนจากmock

### A-SYS — voice/sync/integration (SYS-01/02/VOICE-01)

- A-SYS-01: no microphone/no speech/cancel/timeout → ไม่ออกacousticscore, text-basedpracticeยังเข้าถึงได้
- A-SYS-02: lostack/offline/reopenfile-backedstore/ownerchange → retryidentityเดิมและisolationตามexistingpolicy ไม่มีduplicateupload
- A-SYS-03: nonparticipantหรือwithdrawn → researchrows/events/outbox/uploadไม่ถูกสร้าง; ordinarylearningไม่หยุด
- A-SYS-04: finalsourcefreeze→targetedsuites+analysis+debugbuild→emulatorrestart → artifactตรงsourcepinและcontent/modelidentity, progresspreserved
- A-SYS-05: ทุกrequirementที่รับเข้าในรุ่นมีcaseผลจริง; caseที่ยังต้องhuman/physical/liveแยกสถานะexplicit ไม่ใส่PASSรวม

## 3. Commands และการบันทึกผล

รันเฉพาะ package ที่กำลังเปลี่ยน ทีละคำสั่ง Flutter ไม่ซ้อนกัน Test command ต่อไปนี้ใช้pathsที่ตรวจพบจริง

```powershell
# R15.1 / A-NAV,A-DATA recovery
flutter test test/screens/main_navigation_screen_test.dart test/screens/learning_history_screen_test.dart test/scenarios/file_backed_sync_recovery_test.dart test/features/account/local_data_deletion_test.dart
# R15.2 / A-PAIR
flutter test test/features/learning/pair_matching/pair_board_view_test.dart test/features/learning/pair_matching/pair_matching_experience_host_test.dart test/features/learning/pair_matching/pair_board_accessibility_test.dart test/features/learning/pair_matching/pair_board_golden_test.dart
# R15.3 / A-UI,A-NAV
flutter test test/config/m3_theme_test.dart test/screens/today_hub_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart
# R15.4 / A-LEARN
flutter test test/features/learning/unified_lesson_controller_test.dart test/features/learning_packs/content_quality_policy_test.dart test/screens/review_center_screen_test.dart test/screens/learning_history_screen_test.dart
# R15.5 / A-DATA
flutter test test/screens/mastery_dashboard_screen_test.dart test/features/progress/personal_learning_profile_test.dart test/features/reminders/study_reminder_use_cases_test.dart
# R15.6 / A-CAM
flutter test test/screens/object_scanner_screen_test.dart test/features/media_practice/object_scanner_use_cases_test.dart test/features/media_practice/image_preprocessor_test.dart test/features/media_practice/plugin_camera_gateway_test.dart
# R15.7 runtime compatibility (Python entry ใช้envเดิมตามcamera checkpoint)
flutter test test/features/device_model/model_manifest_test.dart test/features/device_model/litert_image_classifier_test.dart
# R15.8 / A-MOT
flutter test test/features/learning/pair_matching/pair_matching_experience_host_test.dart test/screens/mastery_dashboard_screen_test.dart test/features/sync/reward_transaction_sync_test.dart
# R15.9 / A-AI
flutter test test/screens/ai_tutor_screen_test.dart test/features/ai_tutor/ai_tutor_use_cases_test.dart test/features/ai_tutor/ai_gateway_adapters_test.dart test/features/ai_tutor/ai_gateway_loopback_test.dart
# R15.10 voice/sync focused
flutter test test/screens/shadowing_challenge_screen_test.dart test/features/media_practice/speech_practice_use_cases_test.dart test/scenarios/file_backed_sync_recovery_test.dart test/features/sync/cloud_sync_policy_test.dart test/features/account/local_data_deletion_test.dart
git diff --check
```

Expected GREEN: exit0และallselectedtestspass; reportต้องมีcommandจริง/count/duration/logpath/sourcepin. Existingcasesที่ผ่านก่อนแก้ไม่นับเป็นหลักฐานว่ากรณีใหม่ถูกทดสอบแล้ว และไม่รวมจำนวนซ้ำข้ามsuiteเป็นuniquechecks

ก่อนใช้ Python/train/verification/build ให้เปิด existing entry/config ของ `tools/test_camera_accuracy.py`, `tools/train_camera_pilot.py`, `tool/cli/verify-device-model.ps1`, `tool/cli/verify-camera-speech.ps1` เพื่อใช้ environment และparameterจริงตามcheckpoint ไม่ดาวน์โหลดโมเดลหรือฝึกโดยเรียก default ที่ยังไม่ตรวจ ส่วน release/build ต้องใช้ approved config ที่ยังปิดcloud/research; ไม่กำหนดapplicationId/versionCode/signingใหม่ในเอกสารออกแบบนี้

## 4. รูปแบบ checkpoint ที่ต้องส่งในแต่ละ package

ใช้ structured record ต่อไปนี้โดยเติม actual result ตอนทำงาน ไม่วางค่าตัวอย่างเป็นPASS:

- packageId / requirementIds / acceptanceCaseIds
- source HEAD + changed file hashes / branch / worktree
- old rule replaced + evidence IDs + chosen decision
- changed files / interfaces / migrations (noneเมื่อไม่มี)
- RED reproduction result / GREEN commands and actual outcomes
- visual evidence filenames + viewport/textScale/theme เมื่อมีUI
- diff review outcome / unresolved defects / external-not-run
- commit SHA เมื่อcommitจริง / running task-owned processes / next executable step

Definition of Done: ทุกMUSTของpackageมีacceptanceจริง; sourceหลังtestไม่เปลี่ยน; screenshotsอ่านและเปิดดูแล้ว; ไม่มีunknownduplicatewrite; logsไม่มีsecret; rollbackของsourceและdatachangeที่จำเป็นชัด. ถ้าปิดexperimentด้วยretain-baselineต้องแสดงเหตุผลไม่ผ่าน ไม่เปลี่ยนstatusเป็นmodelready

## 5. สิ่งที่พร้อมจากชุดเอกสารนี้และขอบเขตความครบ

ชุดนี้กำหนด design templates, token defaults, state transitions, data ownership, proposed AI interface/bounds, camera experiment gates, source mapping, file boundaries และ acceptance cases ครบตาม R15 ที่จัดคิวไว้ จึงใช้เริ่ม implementation ทีละpackageได้โดยไม่รอให้ผู้ใช้ช่วยตัดสินใจรูปลักษณ์ปกติ

ยังไม่มีproductionpatch, Fluttervisualprototypeใหม่, actualRED/GREENของcasesใหม่, liveAIqualityหรือphysicalcameraacceptance ไม่กล่าวว่าการมีspecแทนผลเหล่านั้น. ทุกข้อความ “ผ่าน” ในรายงานส่งงานต้องระบุว่าผ่านdocumentvalidationหรือผ่านruntimecasesใดให้ต่างกัน

## 6. Document validation — 2026-09-12

ตรวจชุด Markdown4ไฟล์: reference code paths156ตำแหน่งและlocal links17ตำแหน่งพบครบ; evidence manifest49entriesมีIDไม่ซ้ำและSHA-256ตรงoriginalfilesทุกภาพ; whitespace checkของเอกสารไม่มีerror (Gitแจ้งLF/CRLFconversion advisory). ตัวเลข156นับตำแหน่งอ้างซ้ำตามเอกสาร ไม่ใช่156ไฟล์unique

Self-review ตรวจ supersession ของข้อกำหนดเก่าตามคำชี้แจงล่าสุด, evidence-vs-decision labels, requirement→acceptance coverage และขอบเขตไม่เพิ่มbackend/modelrollout. Source HEADยังเป็นbaselineที่ระบุ; ไฟล์ใหม่มีเพียงเอกสาร4ไฟล์และmanifest1ไฟล์ ไม่มีapplicationedit/test/build/train/commit/push/processใหม่ที่ทำงานค้างจากงานเอกสารนี้
