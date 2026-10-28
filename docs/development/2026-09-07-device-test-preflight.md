# Android test preflight — 2026-09-07

## ล่าสุด 14:19 UTC — ทดสอบเพิ่มเติมจบ พบ device/performance failures

อ่าน [รายงานผลทั้งหมดรอบนี้](2026-09-07-all-tests-device-results.md): Pair/shell บน vivo รันจบครบ 29 Pair files+2shellfixtures แต่มี 3 failure records; isolated host counterparts ผ่าน. Real LiteRT3, native TTSไทย/อังกฤษและcamera inventoryผ่าน; CPU backends206ผ่าน/1remoteE2Eskip; Supabaseผ่าน. Actual-view profileมี Map/List p95 31.946ms เกิน16.7ms. คืน original APK/hashverifiedแล้ว; ไม่มี test process ค้าง. ห้ามใช้ข้อความ core-only หรือ debugger blocker ในประวัติด้านล่างแทนสถานะล่าสุด

## ผลล่าสุด 13:11 UTC — Android core smoke PASS บน vivo V2041

ปัญหาการเชื่อมต่อแก้ได้แล้วโดยใช้ `dart:developer` `Service.getInfo()` ในตัวเชื่อมทดสอบชั่วคราว ซึ่งเก็บ authenticated endpoint ใน private `code_cache` ของ test app ให้ adb run-as อ่านไปใช้กับ `flutter drive --use-existing-app` โดยไม่พิมพ์ endpoint เป็นผลสรุป ไม่ปิด auth และไม่แก้ production source หรือ test assertions

**ผลยืนยัน:** core journey เดิม `guest completes the production learning loop and keeps evidence on restart` ผ่านบน V2041 Android13/API33; driver exit0 และ wrapper exit0, มีหลักฐาน phase-complete ทั้ง23 ช่วงและ46 transitions ถึง `23-sign-out`, cleanup=true, ไม่มี unhandled Flutter error รอบสุดท้าย Test reporter แสดง +2 เพราะรวม tearDownAll ไม่ใช่สอง business journeys เวลา test reporter ประมาณ30วินาที; รอบ install/run/restore รวม57.376วินาที

ครอบคลุม fixture setup/bootstrap, guest login, vocabulary create, quiz, associative reading stages, SRS due/review, progress/reward snapshot, mastery/achievements/profile/shop/quest, dispose/reopen database/UI, export และ sign-out การ reopen นี้เป็นการสร้าง dependencies/ฐานข้อมูลใหม่ภายใน fixture ไม่ใช่การ kill/restart process การใช้ fake cloud/Voice/camera เดิมทำให้ผลนี้ยังไม่ใช่ real backend/native Voice/camera certification, Pair UAT-039–050 หรือ physical accessibility/performance sign-off

หลักฐาน PASS: `build/verification/788e90e62b1694c20945734787723c168b6a6ab2/device-20260907/private-discovery-20260907T131025620Z/` โดย `result.json` ระบุ coreJourneyVerified=true และ completedPhases23; `core-fixture-test.log`, `drive.stdout.log`, `drive.stderr.log`, `response.json`, install/restore logs เก็บแยกครบ

ตัวเชื่อม version2 build ผ่าน **28.957วินาที** ตาม `device-20260907T130929098Z-core-private-discovery-build.metadata.json`; canonical104 inputs/HEAD/plan ตรงก่อนหลัง แฮช wrapper/APK อยู่ใน `core-private-discovery-v2-identity.json` ตัวเชื่อมแรก build96.56วินาทีแต่ไม่ใช่ accepted run ใช้ archived `core-private-discovery-v2-debug.apk` สำหรับผลที่ผ่าน

ประวัติ recovery รอบนี้เก็บไว้: รอบ private-discovery-20260907T130717920Z ใช้ path cache ไม่ตรงกับ Directory.systemTemp ซึ่งเครื่องนี้คือ code_cache; รอบ private-discovery-20260907T130827836Z driver exit0 แต่มี async-registration exception ทำให้เทสต์หลักไม่รัน จึงระบุ INVALID_TEST_EVIDENCE และไม่นับเป็น pass; version2 ลงทะเบียน core.main() แบบ synchronous ก่อน unawaited service discovery แก้จุดนี้ และรอบสุดท้ายยืนยัน phase traces ทุกช่วงแทนการเชื่อ exit0 เพียงอย่างเดียว

คืน original installed APK แล้วตรวจแฮชจากเครื่องตรง `632edb07f6882890c98e467871f98da02502c792df9dadbb854b9f40f17872a1`; scoped log tag คืนค่าว่าง, temporary connection file ถูกลบ, task forwarding ถูกถอด, ไม่มี uninstall/clear data และไม่มี Flutter/test process ค้าง Sessions38900/15249/40355/79940 จบแล้ว เอกสาร/ignored helpers เท่านั้นที่เพิ่ม; tracked implementation/test ไม่เปลี่ยน

สถานะถัดไป: core device smoke ผ่านผ่าน documented alternate runner ของ fixture เดิม แต่ literal `run-android-smoke.ps1` ยังไม่ได้ execute เพราะ default uninstall ต้องรักษาข้อมูลเดิมไว้ Pair internal rehearsal/UAT/accessibility/native Voice/performance/G4P ยังเป็นงานถัดไป ข้อความ blocker ในหัวข้อด้านล่างเป็นประวัติและไม่ใช่สถานะปัจจุบัน

## อัปเดต 12:56 UTC — อนุญาตเปิดแอปแล้ว แต่ discovery URL ถูกปกปิด

หลังผู้ใช้ระบุ “ดำเนินการได้” คำสั่งเปิด fixture ได้รับอนุญาตและ execute สำเร็จแล้ว ข้อจำกัด `blocked by policy` ด้านล่างเป็นประวัติ ไม่ใช่ blocker ปัจจุบัน ทดลอง startup รวม 3 รอบ (ครั้งแรกและ recovery 2 ครั้ง) โดยเพิ่ม process/log diagnostics และแก้ discovery log ตามหลักฐานใหม่

พบ `log.tag=E` บนเครื่องจึงมองไม่เห็น Flutter informational logs การเปิด `log.tag.flutter=I` ชั่วคราวทำให้เห็นข้อความ `The Dart VM service is listening on ************************************` ที่ 19:55:40 device time แสดงว่า VM service เริ่มแล้ว แต่ URL ถูกปกปิดใน log ที่ได้รับ จึงไม่มี endpoint/auth path ให้ driver ใช้ ยังไม่ทราบว่าชั้นใดปกปิด ไม่อ้างว่า VM service ไม่ทำงาน และไม่ได้พยายามถอดค่าที่ถูกปกปิดหรือปิดการป้องกัน debugger

ผลจริง: launcher สำเร็จ, driver ยังไม่เริ่ม, Android smoke/UAT ยัง NotRun; รอบเหล่านี้ไม่มี test assertions fail เพราะยัง attach ไม่สำเร็จ ทั้ง 3 รอบคืน original APK แล้วตรวจ hash จาก installed base.apk ตรง `632edb07f6882890c98e467871f98da02502c792df9dadbb854b9f40f17872a1` คืนค่า Flutter log tag เป็นค่าว่างเดิมและไม่แตะ global log.tag ไม่ uninstall/clear data

หลักฐานแต่ละรอบใต้ device evidence เดิม: `authorized-20260907T125226523Z`, `authorized-20260907T125422761Z`, `authorized-20260907T125525161Z` มี `result.json`, install/launch/restore logs; รอบท้ายมี `startup.log` และ `process-probe.jsonl` ไม่มี drive log/response เพราะยังไม่เริ่ม driver สคริปต์ ignored `.superpowers/sdd/device-authorized-smoke.ps1` เก็บ cleanup ใน finally; sessions 99306/62644/53787 จบแล้ว

ขั้นต่อไปคือวินิจฉัยแหล่งที่ปกปิด VM service URL หรือใช้เส้นทาง attach ที่เครื่องรองรับและรักษาการยืนยันตัวตนได้ ก่อนลอง startup ใหม่ ไม่ต้องขออนุญาตเปิดแอปจากผู้ใช้ซ้ำอีก และห้ามเปลี่ยนชื่อคำสั่งเพื่อรีเซ็ต recovery budget

เริ่มดำเนินการตามคำสั่งผู้ใช้แล้ว: ตรวจแผน/โค้ด, build fixture และทดลองติดตั้งแบบรักษาข้อมูล แต่ Android smoke ยังไม่ได้รัน เพราะระบบตรวจอนุมัติอัตโนมัติปฏิเสธคำสั่งเปิดแอปและเชื่อมต่อ debugger ก่อนเริ่ม process หลังจากนั้นคืน APK เดิมและตรวจแฮชจากเครื่องเรียบร้อย

## Source และแผน

- Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
- Branch: `codex/pair-matching-pm0-pm8`
- HEAD: `788e90e62b1694c20945734787723c168b6a6ab2`
- Implementation: `1875a61854490e0493cc084bffb705f5d3bd4b0b`
- Canonical fingerprint: `50ddab9318080e5dd7cd4b640cfb63dbbf52fb9613d7d61fa8064a59132d22fc`
- ใช้แผน `docs/superpowers/plans/2026-09-01-adventure-motivation-mode-implementation.md`, generated final test plan และ UAT script ตาม [handoff](2026-09-07-device-uat-test-handoff.md)
- หลักฐานใหม่: `build/verification/788e90e62b1694c20945734787723c168b6a6ab2/device-20260907/`

## ผลที่เกิดขึ้นจริง

| ขั้นตอน | ผล | หลักฐานในโฟลเดอร์ด้านบน |
| --- | --- | --- |
| Feature map preflight | PASS, exit 0, 4.511 s | `device-20260907T064000636Z-feature-map-preflight.metadata.json` |
| Final plan preflight | PASS, exit 0, 4.378 s | `device-20260907T064005223Z-final-plan-preflight.metadata.json` |
| Build core integration fixture APK | PASS, exit 0, 63.665 s | `device-20260907T064009653Z-core-fixture-apk-build.metadata.json` |
| ตรวจ signer และติดตั้ง fixture ด้วย `adb install -r -t` | PASS; signer ตรงกับแอปเดิม | `core-fixture-apk-identity.json`, `core-fixture-safe-install.metadata.json` |
| เปิดแอปและเชื่อมต่อ debugger | ไม่ได้ execute; automatic approval review rejected | `device-smoke-execution-status.json` |
| Android core smoke / Pair UAT | NotRun | ไม่มีผล test case ใหม่ |
| คืน APK เดิมด้วย `adb install -r -t` | PASS; ตรวจ installed SHA-256 ตรงกับก่อนทดสอบ | `restore-original-apk.metadata.json`, `restored-device-verification.json` |

ทั้งสาม local gates ตรวจ HEAD, plan bytes และ raw hashes ของ canonical inputs 104 รายการก่อน/หลังแล้วตรงกันทั้งหมด การ build ไม่ใช่ผล device smoke ผ่าน และผล full tests 4,852 สองรอบจาก PM8 เป็นหลักฐานเดิม ไม่ใช่การรันใหม่ครั้งนี้ ไม่มี source implementation/test case ที่ tracked เปลี่ยน

## Device และ artifact

เครื่อง V2041, Android 13/API 33, arm64-v8a, locale th-TH, 1080×2408, density 440, font scale 1.0; accessibility services ปิดขณะ preflight เก็บ device serial เฉพาะ local evidence เครื่องมี `com.lexiquest.app` 1.0.0/code 14 อยู่ก่อนแล้ว

Fixture ใช้ `integration_test/field_trial_core_journey_test.dart` เดิม: สร้าง temporary database/entry state/export, fake account/guest, ปิด real cloud initializers, AI และ Voice ใช้ unavailable/fake path จึงไม่ครอบคลุม native Voice หรือ camera จริง และไม่ใช่ learner UAT

- Test build command: `flutter build apk --debug --no-pub --target-platform android-arm64 --target integration_test/field_trial_core_journey_test.dart --dart-define=LEXIQUEST_VERSION=1.0.0+14 --dart-define=LEXIQUEST_BUILD_ID=device-core-788e90e62b1694c20945734787723c168b6a6ab2`
- Archived fixture: `core-fixture-788e90e6-arm64-debug.apk`, 223,955,799 bytes, SHA-256 `3c6e42d25816c91d7775c3374542570014ec3f0ada377587a87f88178ea9fac9`
- Original installed APK backup: `v2041-installed-before-testing.apk`, 219,956,515 bytes, SHA-256 `632edb07f6882890c98e467871f98da02502c792df9dadbb854b9f40f17872a1`
- Restored installed APK hash ตรงกับ backup; firstInstallTime ยังเป็น `2026-09-01 00:27:20`; ไม่มีคำสั่ง uninstall หรือ clear data ไม่ได้อ่าน/สำรองฐานข้อมูลผู้ใช้ จึงไม่อ้างว่าได้ตรวจเนื้อหาข้อมูลเดิม
- Original PM8 archive ใต้ evidence ของ implementation 1875a618 ยังคงเป็นคนละ artifact กับ test runner; path `build/app/outputs/flutter-apk/app-debug.apk` ปัจจุบันเป็น fixture build อย่าแจกเป็นแอปปกติ

## เหตุผลที่ปรับวิธีรันและจุดหยุด

Flutter SDK ที่ติดตั้งตั้ง `flutter test` integration option `uninstall` เป็น true และ `AndroidDevice.installApp` อาจถอนแอปเมื่อ install ครั้งแรกไม่สำเร็จ จึงยังไม่ได้เรียก `tool/cli/run-android-smoke.ps1` ตรง ๆ บนเครื่องที่มีแอปเดิม วิธีที่เตรียมไว้คือ build fixture เดิม, ตรวจ signer, ติดตั้งด้วย adb `-r -t` ที่ไม่มี uninstall fallback, แล้วใช้ `flutter drive --use-existing-app` เพื่อเชื่อมต่อ runner แยก ต้องบันทึกเป็นวิธีรันประกอบที่ต่างจาก literal generated gate เมื่อมีผลจริง

หลัง safe install สำเร็จ ระบบตรวจอนุมัติอัตโนมัติปฏิเสธคำสั่งที่รวม `adb shell am start` ใน debug/start-paused mode, อ่าน VM service และสร้าง task-owned adb forwarding ด้วยเหตุผลที่ส่งกลับเพียง **“blocked by policy”** ไม่มีรายละเอียดเพิ่มเติม คำสั่งถูกปฏิเสธก่อนสร้าง process; launch stdout ไม่เกิดขึ้น ไม่มีการเรียกคำสั่งนั้นใหม่ผ่านวิธีอื่น และยังไม่มี adb forwarding ที่สร้างโดยงานนี้

คืน APK เดิมสำเร็จแล้ว ไม่มี Flutter/test/build process ของงานค้าง; adb daemon และ Gradle daemons เดิมอาจยังอยู่ ไม่มีการ kill process ที่ไม่เกี่ยวข้อง สคริปต์เตรียมงานอยู่ใน ignored `.superpowers/sdd/device-run-gate.ps1`, `device-build-core.ps1`, `device-core-driver.dart`; driver ยังไม่ได้ execute สคริปต์ runner แยก checkout HEAD จาก implementation SHA และยังตรวจครบ 104 inputs

## ขั้นตอนถัดไป

ดำเนิน device launch/attach ต่อได้เมื่อมีหลักฐานใหม่ว่าข้อจำกัดการอนุมัติที่ปฏิเสธคำสั่งนี้เปลี่ยนแล้ว ก่อนรันต้องตรวจ device/installed artifact/source อีกครั้ง และใช้การติดตั้งที่รักษาข้อมูล ไม่มีการขอให้ bypass tool policy หรือเปิด production

หลังได้ core smoke จริง จึงตรวจ Pair Hidden/Internal configuration และดำเนิน device rehearsal/UAT-039–050 ตาม script; native accessibility/Voice/performance, comprehension 11/12 และ G4P ทั้งห้าบทบาทยังไม่มีผลรับรอง Research enrollment/upload คงไม่ได้รับอนุญาต; ไม่มี push/merge/deploy/publish ในรอบนี้
