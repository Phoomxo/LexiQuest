# ส่งต่องาน: เริ่มทดสอบตามแผนเดิมในแชตใหม่

**ล่าสุด 14:19 UTC:** การทดสอบเพิ่มเติมบน vivo/backend จบแล้ว อ่าน [รายงานรอบนี้](2026-09-07-all-tests-device-results.md). Nativeโมเดล/เสียงผ่าน, backend206ผ่าน/1skip, Supabaseผ่าน; Pair/shellมี3failure records และ actual-view profile p95 31.946ms เกิน16.7ms. APKเดิมคืน/hashverified; task-owned Supabaseหยุดแบบเก็บvolume; ไม่ต้องเริ่ม42นาทีของPair suiteซ้ำโดยไม่มีการแก้ไข/สมมติฐานใหม่. Next: device-only failures/performance และ human/external UAT ที่ยังไม่มี หัวข้อด้านล่างเป็นประวัติ

บันทึกวันที่ 2026-09-07; ตรวจ APK ล่าสุดเมื่อ 06:10:43 UTC

**ล่าสุด 13:11 UTC: Android core smoke ผ่านบน vivoV2041 แล้ว** ใช้ authenticated private discovery + fixtureเดิม ครบ23phase/driverexit0/no unhandled errors คืนAPKเดิมและค่าlog/cleanupครบ ดูหัวข้อบนสุดของรายงาน preflight ก่อนทำงานต่อ ปัญหา debugger ด้านล่างเป็นประวัติ; งานถัดไปคือ Pair internal rehearsal/UAT/accessibility/native Voice/performance/G4P

**สถานะล่าสุด 12:56 UTC:** ผู้ใช้อนุญาตเปิดแอปซ้ำแล้วและ launch execute สำเร็จ; blocker ปัจจุบันคือ Dart VM service discovery URL ถูกแสดงเป็นดอกจันใน log ไม่ใช่การปฏิเสธคำสั่ง ทั้งสาม startup attempts คืน APK เดิมและคืนค่า log แล้ว ดูอัปเดตบนสุดในรายงาน preflight ก่อนอ่านประวัติด้านล่าง ไม่ต้องขอ user authorization เปิดแอปซ้ำ

**อัปเดตหลังผู้ใช้สั่งดำเนินการ:** อ่าน [ผล device preflight](2026-09-07-device-test-preflight.md) ก่อนเริ่มต่อ สอง generator checks และ build fixture ผ่านแล้ว; safe install ผ่าน แต่ขั้นเปิดแอป/debugger ถูก automatic approval review ปฏิเสธด้วย “blocked by policy” ก่อน execute จึงยังไม่มี Android smoke/UAT และคืน APK เดิมพร้อมตรวจ installed hash แล้ว ห้ามรันคำสั่งที่ถูกปฏิเสธซ้ำผ่านวิธีอื่น; ข้อมูลด้านล่างเป็น handoff ก่อนรอบนี้

## คำสั่งจากผู้ใช้และขอบเขต

ผู้ใช้สั่ง “สร้างchatใหม่แล้วเริ่มต้นทดสอบตามแผนที่ได้เขียนไว้ตอนต้น” ให้เริ่มจาก preflight ของแผนเดิม เทียบหลักฐานที่มี แล้วดำเนินงานทดสอบที่ยังขาดต่อเนื่อง ไม่ใช่เริ่มพัฒนา PM0–PM8 ใหม่ อ่าน AGENTS.md ของ worktree นี้ก่อนทำงาน และรักษาการเปลี่ยนแปลงเดิมทั้งหมด

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`

Branch: `codex/pair-matching-pm0-pm8`

HEAD: `788e90e62b1694c20945734787723c168b6a6ab2`

Implementation source: `1875a61854490e0493cc084bffb705f5d3bd4b0b`

Source fingerprint: `50ddab9318080e5dd7cd4b640cfb63dbbf52fb9613d7d61fa8064a59132d22fc` (104 canonical inputs)

## เอกสารที่ต้องอ่านและใช้ตามลำดับ

1. `.superpowers/sdd/progress.md` เฉพาะ checkpoint บนสุดที่ระบุ COMPLETE; รายการด้านล่างเป็นประวัติ
2. `docs/superpowers/plans/2026-09-01-adventure-motivation-mode-implementation.md` โดยเฉพาะ Checkpoint 6 และ Task PM8 ของ Checkpoint 7
3. `docs/generated/alltcas-8-44-final-test-plan.md` และ `.json` สำหรับ 42 ordered gates และรูปแบบหลักฐาน
4. `docs/development/2026-09-07-pair-matching-pm8-local-verification.md` สำหรับผลปัจจุบัน ข้อยกเว้น และ identity ของ artifact
5. `docs/adventure-motivation-mode/06-test-plan-and-test-cases.md`, `07-uat-script.md`, `08-requirements-traceability-matrix.md`, `09-measurement-decision-spec.md`
6. `docs/development/2026-09-05-research-engineering-status.md` สำหรับขอบเขต Research ที่เสร็จและ authority ที่ยังขาด

ให้ใช้แผนเดิมทั้งหมดเป็นรายการอ้างอิงและเริ่ม preflight จากต้นแผน งานที่ผ่านแล้วใช้หลักฐานเดิมได้เมื่อยืนยัน source/config ตรงกัน งานที่ยังไม่รันต้องระบุแยกชัดเจน หากพบ relevant source/config เปลี่ยน ให้รัน focused regression ก่อนขยายตาม integration checkpoint

## หลักฐานที่เสร็จแล้ว

- Local PM0–PM8 engineering เสร็จและ commit แล้ว ไม่มี actionable implementation finding ค้างตาม final review
- Full default และ serial ผ่านรายการเดียวกัน 4,852 named tests ต่อรอบ; failed/skipped/error = 0 ภายในขอบเขตที่รัน โดยมี 4 explicit release-excluded cases ไม่ได้รัน
- Analyzer, host-fake journeys 3 ชุด, focused authority/privacy/runtime, demo Auth/Firestore policies, bounded Gitleaks, OSV ตามข้อยกเว้นเดิม, debug APK และ native integrity ผ่านแล้ว
- TC-PMT-001–044 mapped ครบ; RTM 258 rows; UAT inventory 50 scripts ไม่ใช่ผล UAT ผ่านแล้ว
- หลักฐานอยู่ที่ `build/verification/1875a61854490e0493cc084bffb705f5d3bd4b0b/`; อ่าน `pm8-local-release-evidence.json`, `pm8-post-commit-checks.json`, `pm8-unexecuted-gates.json` และ `reviews/pm8-final-evidence-audit.md`

## Preflight ที่ตรวจใหม่ก่อนส่งต่อ

- `git rev-parse HEAD` ยังตรงกับ HEAD ด้านบน
- `adb devices -l` พบอุปกรณ์สถานะ `device` หนึ่งเครื่อง รุ่น V2041/product 2041T; ต้องตรวจซ้ำก่อนเลือก target เพราะอาจถอดสายหรือเปลี่ยนเครื่องแล้ว
- ยังไม่ได้ตั้ง `LEXIQUEST_ANDROID_DEVICE_ID`; discover serial จาก adb อย่าเดาค่า
- คำสั่ง adb เริ่ม local daemon ที่ port 5037 สำเร็จ; ไม่มีการติดตั้ง ลบ หรือ clear data บนอุปกรณ์ในรอบส่งต่อนี้
- Archive APK มี 223,956,089 bytes และ SHA-256 ยังตรง:
  `4a7ac0ff4e7e5da0189962e7f91628e5654fe21f16585a0e8f20a6d9b06bd4e3`
- Archive: `build/verification/1875a61854490e0493cc084bffb705f5d3bd4b0b/LexiQuest-Pair-PM8-1875a618-debug.apk`
- APK package `com.lexiquest.app`, versionName `1.0.0`, versionCode `14`, build ID `pair-1875a61854490e0493cc084bffb705f5d3bd4b0b`
- รอบส่งต่อนี้ยังไม่ได้เริ่ม Flutter tests, device smoke หรือ UAT และยังไม่มีผลใหม่ที่นำไปอ้างเป็น pass ได้

## งานที่ต้องเริ่มในแชตใหม่

1. ยืนยัน cwd/branch/HEAD/diff และตรวจ source/config/evidence ตามแผน ไม่ reset หรือล้าง generated files ที่มีสถานะเดิม 7 รายการ ตรวจว่าไม่มี Flutter/build writer อื่นก่อนเริ่มคำสั่ง
2. ตรวจ Android ที่ต่ออยู่ด้วย adb และ Flutter; บันทึก model, OS/API, locale, display/text scale, accessibility, audio/network และ package/build ที่ติดตั้งอยู่ ตรวจผลกระทบต่อข้อมูลเดิมก่อน install test build ห้าม uninstall/clear data เพื่อให้ทดสอบผ่าน หากมีหลาย target ให้ขอผู้ใช้เลือก
3. ตรวจ `tool/cli/run-android-smoke.ps1`, `integration_test/field_trial_core_journey_test.dart` และ external fakes ก่อนรัน ยืนยัน synthetic/temp fixtures และปิด real Research/upload ใช้ environment variable เฉพาะ process สำหรับ target ที่ยืนยันแล้ว
4. รัน generated gate `android-bounded-core-smoke` และเก็บ command, source fingerprint, config, device, UTC time, exit code, stdout/stderr และผลจริงใน evidence directory ใหม่ของ HEAD ปัจจุบัน:
   `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/run-android-smoke.ps1`
5. แยก artifact ของ `flutter test -d ...` ออกจาก archived debug APK เพราะเป็นการ build/install integration test runner; ผล core smoke บนเครื่องไม่ใช่ผล Pair UAT หรือ physical Voice/accessibility ผ่านทั้งหมด
6. ตรวจวิธีเปิด Pair แบบ Hidden/Internal และ reader-first compatibility จาก actual code/fixtures ก่อนทดสอบ prototype APK เดิมไม่ใช่หลักฐานว่า new Pair writer เปิดอยู่ ห้ามเปลี่ยน production rollout หากต้องสร้าง internal harness ให้ระบุ delta ต่อแผนและตรวจขอบเขตก่อนแก้ไข
7. ดำเนิน engineering device rehearsal และบันทึกผลเกม/recovery/native Voice/TalkBack/Switch Access/keyboard/text 200%/performance ที่ตรวจได้จริง จากนั้น UAT-039–050 ตามแต่ละ script กับผู้ทดสอบจริงเมื่อพร้อม แยก technical rehearsal จาก learner UAT และอย่าสร้าง numerator/denominator ของเป้าหมาย 11/12 ขึ้นเอง
8. เตรียม G4P evidence ให้ Product, Learning/Data, UX/Accessibility, QA และ Tech บันทึก Accept/Revise/Reject พร้อมชื่อ/วันจริง เมื่อหลักฐานครบ; agent ไม่ลงนามแทน

## งานที่ยังไม่รันและข้อจำกัดที่ต้องรักษา

- Android smoke, Pair UAT-039–050, physical accessibility/Voice/performance และ G4P roles ยังไม่มีผล acceptance
- Supabase policy เดิมไม่มี Docker daemon ที่พร้อม; CPU backends 3 ตัวไม่มี local venv ตาม checkpoint ก่อนหน้า ให้ตรวจใหม่ก่อนกล่าวว่ายังขาด ห้าม reset containers ที่ไม่ใช่ของงาน
- 3 real LiteRT cases ยังไม่ได้รัน; iOS notification case ถูก exclude ตาม owner scope อย่าเปลี่ยนเป็นผ่าน
- OSV exceptions เดิม 8 รายการ optional Voice/Torch หมดอายุ 2026-09-11 และ uuid 1 รายการ 2026-10-26; ไม่ต่ออายุหรือเปิด capability โดยอัตโนมัติ
- ห้าม Codex Security/Security Scan/Deep Scan; ใช้ local tests/policy/audits ตาม AGENTS.md
- Research enrollment/collection/upload คง default-off จนมี trusted authority, approved protocol/instrument, consent และ rollout authorization จริง; local tests ไม่ใช่ efficacy evidence
- ไม่มีอนุญาต push/merge/deploy/publish/production enablement หรือ destructive cleanup ในงานนี้
- ห้ามใช้ `.superpowers/sdd/pm8-run-gate.ps1` หรือ `pm8-release-phase.ps1` กับ HEAD ปัจจุบันโดยตรง: helper เก่าบังคับ HEAD เท่ากับ implementation commit 1875a618; อย่า reset HEAD เพื่อใช้ helper
- Serialize Flutter/Dart/pub/build/generation ใน worktree เดียว หากแก้ source ให้ทดสอบ affected scope และบันทึก source identity ใหม่

## สถานะเมื่อส่งต่อ

ไม่มี test/build session ค้างจากรอบส่งต่อนี้; local adb daemon อาจยังทำงานอยู่ ไฟล์ handoff นี้เป็นเอกสารใหม่ยังไม่ commit และ generated status เดิม 7 รายการต้องคงไว้ งานถัดไปที่ทำได้ทันทีคือยืนยัน target V2041 และตรวจ device/package/fixture ก่อนเริ่ม Android smoke ตามข้อ 1–4
