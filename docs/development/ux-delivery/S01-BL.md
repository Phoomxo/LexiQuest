# S01-BL — Native readiness และชุดตรวจรับแบบจำกัด

## ผลตรวจจริง

ตรวจ 2026-09-27 บน `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`, branch `codex/ux-current-after-s01-bc`, HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1` รวม dirty BD–BK เดิม

- `adb devices -l` พบ V2041 พร้อมใช้งาน; `flutter devices --machine` ระบุ physical (`emulator: false`), Android 13/API33, android-arm64. เครื่องพร้อม ไม่ใช่ prerequisite ที่ยังขาด
- มี `com.lexiquest.app` versionCode23 และ `com.lexiquest.app.ariTest` versionCode14 ติดตั้งอยู่แล้ว ทั้งคู่มีพื้นที่ข้อมูลของตนเอง ไม่ได้อ่านข้อมูลผู้ใช้หรือถือว่า ariTest ลบทิ้งได้
- ตรวจ BK source/artifact pins และ input closure 1,563 รายการตรงทั้งหมด; ผล HOST_PASS236 เดิมยังใช้ได้เฉพาะ fingerprint เดิม ไม่ได้รัน host tests ซ้ำ
- **Native behavior / process restart: NOT_RUN** ไม่มีการติดตั้ง เปิดแอป force-stop ล้างข้อมูล ถอนแอป หรือเปลี่ยน network/device settings
- ไม่มี application source edits, build, release verifier, browser/native UI automation, provider/login/billing probe หรือ research activation

## Finding ที่ทำให้ยังไม่รัน smoke เดิม

| Source | สิ่งที่พบ | ผลต่อ scope |
| --- | --- | --- |
| `tool/cli/run-android-smoke.ps1` | เลือก Android จาก env แล้วรัน core journey ไฟล์เดียว ไม่มี package isolation/การตรวจ package เดิม | ไม่รันลงสองแพ็กเกจที่มีอยู่ |
| `android/app/build.gradle.kts` | default ID `com.lexiquest.app`; `ariLocalTest=true` เปลี่ยน debug เป็น `.ariTest`; ไม่มี identity ใหม่สำหรับ BL | การเปิด flag เดิมยังชนแพ็กเกจที่ติดตั้งแล้ว |
| `integration_test/field_trial_core_journey_test.dart` | single test 23 phases รวม vocabulary/quiz/rewards/export/logout และ research-consent withdraw บน fixture | `--plain-name` ไม่สามารถเลือกเฉพาะ baseline/navigation/persistence จาก test นี้ |
| core journey phases 18–21 | dispose dependencies แล้ว bootstrap/reopen DB และ pumpWidget ใน test/process เดิม | ใช้ยืนยัน OS process restart ไม่ได้ |
| core journey viewport | ปกติ override เป็น 1280×900; native viewport flag ยังเขียน authenticated VM endpoint ผ่าน service receipt | ไม่ใช้ค่า default อ้าง visual acceptance และไม่เก็บ endpoint/token ลง evidence |
| `tool/cli/verify-scope.ps1` | explicit Integration targets ใช้ `-d flutter-tester`; Targeted/Integration ปกติเป็น analyze; Subsystem เรียก smoke เดิม | ทั้งสอง targeted ทางไม่ใช่ native acceptance; ไม่ใช้ subsystem เพื่อข้ามขอบเขต |
| `integration_test/support/persistent_manual_qa_storage.dart` | helper มี persistent synthetic directory แต่ไม่ใช่ entrypoint หรือ runner แยกแพ็กเกจ | ใช้เป็นแนวทาง reuse ได้ ไม่ถือว่ามี runnable restart harness แล้ว |
| `tool/cli/tests/run-android-smoke.tests.ps1` | contract ใช้ stub Flutter และตรวจ command/device selection | เป็น host tooling evidence เท่านั้น |

ข้อจำกัดที่เหลือเป็นงาน engineering เรื่อง harness/isolation ไม่ใช่ external block ทั้งโครงการ Controller ยืนยันให้จบ BL ด้วย task card แล้วจัดงานถัดไปเอง

## Checklist ตรวจรับเมื่อ harness พร้อม

ทุกแถวเริ่ม NOT_RUN; ผู้รันต้องบันทึก actual result และ artifact ไม่มี automatic PASS จากการทำ checklist ครบ ใช้แพ็กเกจ debug ใหม่ที่พิสูจน์ว่าไม่เคยติดตั้ง ไม่แตะ production/ariTest

| ID | ขั้นรันและเกณฑ์รับ | หลักฐานขั้นต่ำ |
| --- | --- | --- |
| BL-N01 | เข้า baseline แบบ guest โดยไม่ login; เปิดครบสี่แท็บตาม navigation glossary แล้วกลับหน้าเริ่ม ไม่มี exception/ทางตัน | source/APK hash, native viewport, step results |
| BL-N02 | เข้า Settings → `settings/offline-content` ด้วย local catalog/asset fixture; กลับ Settings และเปิดใหม่ ไม่มีหน้า duplicate; read local content ได้เมื่อ external transports ถูกปิด | route observations, local fixture identity/hash, outbound-call counters = 0 |
| BL-N03 | เปลี่ยน display preference ที่รองรับผ่าน Settings; สร้างคำสังเคราะห์หนึ่งคำในคลังเดิม; บันทึก owner ID/row ID/preference ในข้อมูลทดสอบเท่านั้น | canonical DB + preference snapshot ก่อนปิด, ไม่มี learning/reward event ใหม่ |
| BL-N04 | ปิดเฉพาะ process ของ package ทดสอบหลัง flush; ยืนยัน PID เดิมหาย แล้วเปิด APK เดิมโดยไม่ติดตั้งหรือ seed ทับ; preference/owner/คำ/แคชจาก N03 อยู่ครบและไม่ซ้ำ | PID ก่อน–หยุด–หลัง, APK hash เดิม, read-only assertions หลัง restart |
| BL-N05 | ตรวจหน้า Settings/offline ที่จอจริงและขนาดตัวอักษรที่กำหนด; ตรวจ keyboard/TalkBack ด้วยช่องทางที่ได้รับอนุญาต | observation แยก visual/keyboard/screen-reader; ยัง pending หากเครื่องมือไม่รองรับ |

N01–04 เป็น engineering checks ไม่ใช่ qualified user trial หรือหลักฐานผลการเรียน N05 ไม่ปิด UX-D01–25 ทั้งชุด เก็บ reviewed media/qualified trial/release แยกตาม plan v5

## ขั้นถัดไปที่ลงมือได้

อ่าน [task card](S01-BL-next-harness.md) แล้วสร้าง isolated bounded harness พร้อมทดสอบ guard/fixture โดย sole writer ใน worktree เดิม ห้ามนำ smoke 23 phases มารันก่อนแก้ isolation ไม่ต้องรอ media/trial สำหรับงาน harness นี้

หลักฐาน: [validation](evidence/S01-BL-validation.json), [checkpoint](evidence/S01-BL-checkpoint.json), [claim](evidence/S01-BL-claim.json). Dirty BD–BK และ generated 7 ไฟล์คงเดิม; `ready-backlog.md` ของ controller คงเดิม

**S01 IN_PROGRESS; UX-D01–25 OPEN.** BL เสร็จเฉพาะ readiness/checklist; native, real-user, trial และ release ยังไม่รับรอง Writer RELEASED ให้ controller โดยไม่ dispatch successor
