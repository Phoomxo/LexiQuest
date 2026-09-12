# งานระบบต่อเนื่อง 1–6 — R13

สถานะย้อนหลัง: R13 ถูกแทนด้วย R14 หลัง device scenario พบว่า Pair replay
ปฏิเสธ UTC timestamp ที่มี microseconds. หลักฐาน R13 ด้านล่างยังเก็บไว้ตามจริง;
ใช้ `2026-09-12-system-followup-r14-checkpoint.md` เป็น checkpoint ปัจจุบัน.

## Source และขอบเขต

- Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
- Branch: `codex/pair-matching-pm0-pm8`
- HEAD: `788e90e62b1694c20945734787723c168b6a6ab2`
- Runtime/test source fingerprint: `3f05006f1cffd3fc86b49264e1efb5d5e3911cdd8a7172bd21636e8ae7ce8235` (1,361 files)
- ต่างจาก R12 จำนวน 15 ไฟล์ตาม `build/verification/system-followup-20260912/source-delta.json`.
  Assets, dependency และ Android files ไม่เปลี่ยน; preserved inherited edits.
- ไม่ commit, deploy, เปิด cloud/research enrollment หรือเปลี่ยนโมเดลหลัก

## การแก้ที่ตรวจแล้ว

1. Today → History เปิด Pair practice replay ผ่าน route ที่เป็นเจ้าของกิจกรรมจริง;
   ใช้ PackagedStarter allowlist เดิมและ canonical source reread. ตรวจ owner,
   live Quiz gate และ operation identity; ไม่ให้ history สร้าง lexical authority.
2. CEFR history ที่ไม่มี pack แสดงชื่อกิจกรรมทั่วไปและระบุว่าไม่ได้เก็บชื่อบท/ระดับ
   ในรอบนั้น. ไม่อนุมานจาก catalog ปัจจุบันและไม่เปิด replay ที่ไม่มี content authority.
3. VocabList แยกค้นหาไม่พบจากหมวดว่าง และเพิ่มพื้นที่เลื่อนให้แถวสุดท้ายพ้นปุ่มลอย.
4. SRS/legacy Matching ใช้ semantics ตามภาษาไทย/อังกฤษ. ทดสอบหน้าจอแคบ,
   dark theme, text 200%, flip, scroll และเปิดยืนยันลบแล้ว cancel.
5. เพิ่ม benchmark helper เฉพาะ manual QA, ไม่อยู่ใน ordinary launcher และไม่แทน
   manifest หลัก. ตรวจ Android/model/input hashes และเขียนเฉพาะไฟล์ผล benchmark.

## Verification

- Current-source combined regression: **825 PASS**, exit 0, sourceStable true,
  257.82 seconds. Evidence:
  `build/verification/remediation-20260907/system-r13-test-20260912T101214441Z`.
  ครอบคลุม vocabulary/CEFR, history, Pair, Today, time tracking, Quiz/SRS,
  UI journeys, model runtime contracts และ architecture boundaries.
- TDD: history title, no-results และ Thai semantics มี expected RED แล้ว GREEN.
  Pair navigation ครบ normal, changed owner และ Quiz emergency-off; reward/points
  ไม่เพิ่มจาก replay test. Source history rows ไม่ถูกเขียนทับ.
- ขณะตรวจรวม พบ test fixture เพิ่ม 20 คำค้างใน async seed; เปลี่ยนเฉพาะ layout
  fixture เป็น direct synthetic DB rows หลังยกเลิก watch. การสร้างคำผ่าน UI เดิม
  ยังทดสอบจริง และ assertions ไม่ลดลง. Focused journey ผ่าน 3 seconds.
- Today review test เดิม tap ปุ่ม Next นอก viewport หลังเพิ่มตัวอย่างประโยค;
  เพิ่ม scroll/ensureVisible ก่อนกดสองจุด. Durable completion test ผ่านโดยไม่แก้ runtime.
- Manual helper analysis: exit 0 ด้วย no-fatal-infos; ไม่มี errors/warnings,
  มี file_names info 2 รายการตามชื่อ device-*.dart ของ QA tooling.
- Independent read-only review ไม่พบ actionable defect ในขอบเขตแก้.
- การเรียก analyze ที่ root ครั้งแรกกว้างเกินไป: พบ `.dart` 10,476 ไฟล์ใน
  build/verification ซึ่งรวมสำเนา baseline เก่า เทียบกับ source/tests 1,090 ไฟล์.
  หยุดเฉพาะ task-owned analyzer หลังตรวจ PID/parent/command, ไม่แก้หรือลบไฟล์.
  เก็บหลักฐานรอบที่หยุดไว้ แล้วเปลี่ยนเป็น explicit source scopes
  lib/test/integration_test/test_driver/tool/tools; manual QA วิเคราะห์แยกไว้แล้ว.
- Explicit-source analysis ผ่าน exit 0, sourceStable true, fingerprint เดียวกับ
  825 tests. ไม่มี errors/warnings; มี 94 informational style diagnostics
  ใน scope กว้างนี้ (รวม unused import ใน nav test ใหม่หนึ่งรายการ).
  Evidence `build/verification/remediation-20260907/system-r13-analyze-source-20260912T102259718Z`.

## กล้องและข้อจำกัด

รายงาน `2026-09-12-camera-followup.md` ตรวจ paired existing images 40 ภาพ:
object crops baseline 18/40, pilot 37/40; full frames 14/40 และ 35/40.
OOD เป็น UI golden 2 ภาพเท่านั้น pilot ทายผิดอย่างมั่นใจทั้งคู่;
softmax 4 classes มี max >= 0.25 จึงใช้ threshold 0.15 ปฏิเสธ unknown ไม่ได้.
ข้อสรุปปัจจุบันคือ **คง baseline**. Pilot ลด coverage เหลือ 4 กลุ่มและใหญ่กว่า.
ไม่มีการฝึกเพิ่ม ปรับ threshold ด้วย test set หรืออ้างว่าได้ตรวจ physical scenes.

Host timing/RSS และ Android timing/RSS ต้องรายงานแยกกัน. Android staging model
และ validation-book RGB bytes SHA ตรงทั้งหมดตาม camera/stage.json.
Device context V2041/API33/arm64, battery 100%, USB powered, power-save 0,
thermal status 0 ก่อนวัด. การวัดครั้งนี้เป็น debug/runtime และภาพ book เดียว;
ไม่รวม camera capture/preprocessing และไม่ใช่ model-only/continuous peak memory.

## ขั้นส่งมอบที่ยังต้องบันทึกผล

- vivo Pair4/6, Today/History replay, Focus Timer, Quiz/SRS, Back/reopen
- vivo model benchmarks fresh process และกลับเข้า scanner ที่ยังใช้ baseline
- Post-scenario persistence/restart, final manifest/hash และรายการข้อจำกัด

## Build และ update ที่ผ่านแล้ว

ทั้งสอง APK build exit 0, sourceStable true, whole source fingerprint เดียวกัน
`ffe1e451fc2c23d019057ea4d8afb97e331a9ee569ad106925680544951de768`.
Runtime gate fingerprint ตรงกับ 825 tests และ source analysis. ทั้งสองเป็น debug,
learning preview เปิด, cloud sync ปิด; ไม่มี production rollout.

| APK | Version code | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| manual-v22-thai-r13 (ติดตั้ง vivo) | 22 | 154614365 | `c3bbb62d6250f8eb9bc3c586e9af44e1837177363b8794c04d4103c2a7896131` |
| preview-v27-thai-r13 (ordinary, ยังไม่ติดตั้ง) | 27 | 227451071 | `0b2408d439b62d798ce0ab210d05b77aab5e8409014fb19bfa0fea01f8fc079c` |

ไฟล์อยู่ใน `build/verification/motivation-ui-20260908/device/` พร้อม identity และ
build records. Signer SHA-256 เดิม:
`1f10bbeedb0b8f18bcbb789c31d862bcfe9a3d146920033fb93eb1d228b0c5b4`.
Content audit ตรวจ 19 packaged assets ต่อ APK ว่าตรง source bytes ทั้งหมด.

ส่ง manual APK 37 ชิ้นด้วย adb push sync protocol, SHA ทุกชิ้นและ concatenated
APK บน vivo ตรง computer hash. ไม่ส่ง binary ผ่าน Windows stdin (สาเหตุเดิมที่
ทำข้อมูลเสียเมื่อ byte 0x1A ถูกจัดการแบบ text). `pm install -r -t` สำเร็จ;
installed base.apk hash ตรง. Update time 2026-09-12 17:26:23, first install time
ยังเป็น 2026-09-01 00:27:20. Cache fixtures ที่ Android ลบตามปกติ restored จาก
verified synthetic backup; primary files DB และทุก protected data file hash
ตรงก่อน/หลังตาม `device/install.json`.

`after-update.sqlite` integrity ok และ **ทุกตารางเท่ากับ before-update** ก่อน
เริ่มกิจกรรมใหม่: owners 2, categories 2, vocabulary 21, sessions 3, attempts 11,
events 102, time segments 7, research proofs 0. First launch PID 30183,
AndroidRuntime/flutter error log ว่าง. Ordinary APK มี asset/build evidence
และ automated tests; ไม่อ้างว่าได้ติดตั้งหรือทดสอบ physical launcher ของ ordinary.

## งานที่ต้องรอผู้ใช้หรือบริการจริง

ผู้ถือเครื่องช่วยฟังและพูด/รับเสียงจริง, เดิน TalkBack จริง, AI provider/model/budget/key,
เครื่องที่สองและ cloud test accounts, และ physical camera scenes หลายแสง/มุม/ระยะ.
ไม่มีการนับ automated/synthetic checks ว่าผ่านเงื่อนไขเหล่านี้.
