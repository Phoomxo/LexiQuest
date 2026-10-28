# งานระบบต่อเนื่อง 1–6 — R14

สถานะล่าสุด: **ปิดงานอัตโนมัติตามแผน 1–6 แล้ว** หลังผู้ใช้สั่งให้ดำเนินต่อ
root ตรวจหน้าจอใหม่ ทำ Matching4/6 จบ เปิดบทอ่านครบ และตรวจ restart/persistence.
การพัก input ก่อนหน้าเป็นเหตุการณ์ย้อนหลัง ไม่ใช่ข้อบล็อกปัจจุบัน.
ไม่มีการแก้/ลบข้อมูลเพื่อจัดฉากผลทดสอบ. เงื่อนไขที่ต้องคน/บริการจริงแยกท้ายรายงาน.

## Worktree และ source

- `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
- Branch `codex/pair-matching-pm0-pm8`
- HEAD `788e90e62b1694c20945734787723c168b6a6ab2`
- Runtime/test fingerprint `5b3a8847d609d80f7df34d4e5377264dc00dc7174bcbffe47f22d8636d6f95b0` (1,361 files)
- Build whole-source fingerprint `653161a2ad5f553e54e817ff3aa32e5bd72978061bef0ffc523efbb96c5a1985`
- เก็บ inherited changes เดิม; ไม่มี commit, merge, production rollout,
  cloud/research enrollment หรือเปลี่ยน shipped model.

## สิ่งที่แก้แล้ว

1. Today → History เชื่อม Pair practice replay ผ่าน host และ curated allowlist
   เดิม ตรวจ active owner, live Quiz gate และ retry operation identity.
2. CEFR history ที่ไม่มีชื่อบทหรือระดับเดิม ใช้ชื่อกิจกรรมทั่วไป พร้อมบอกข้อมูล
   ที่ไม่ได้บันทึก ไม่อนุมานจากบทอ่านปัจจุบันหรือสร้าง pack authority เพิ่ม.
3. คลังส่วนตัวแยกค้นหาไม่พบจากหมวดว่าง และเลื่อนแถวสุดท้ายพ้นปุ่มลอยได้.
   SRS/Matching semantics ใช้ภาษา th/en ตามแอป; ตรวจหน้าจอแคบ/dark/text 200%.
4. R13 พบ defect บน vivo: นาฬิกาจริงส่ง UTC microseconds แต่ exact Pair plan
   รับเวลา precision milliseconds. R14 normalize UTC ใน replay builder ก่อน
   chronology/admission โดยยังปฏิเสธ non-UTC และเวลาก่อน source terminal.
   ไม่ลดความเข้มของ strict plan contract หรือเปลี่ยน retry/reward authority.
5. เพิ่ม manual-only camera benchmark helper และวัด existing models;
   ordinary launcher ไม่มีเมนู benchmark และยังใช้ baseline เดิม.

## Verification และ APK

- Combined regression **826 PASS**, exit 0, sourceStable true (234.4s):
  `build/verification/remediation-20260907/system-r14-test-20260912T104243600Z`.
  ครอบคลุม CEFR/vocabulary, History, Pair, Today, timer, Quiz/SRS,
  UI journeys และ model/runtime boundaries.
  เป็น integration checkpoint suite ที่เลือกสำหรับงานนี้ ไม่ใช่ full repository.
- UTC regression ผ่าน expected RED → GREEN; ตรวจ serialization, duplicate
  start, non-UTC และ chronology rejection พร้อมยืนยัน replay ไม่เพิ่ม rewards.
- Explicit-source analysis exit 0/sourceStable true (15.14s), 93 style infos,
  ไม่มี errors/warnings:
  `build/verification/remediation-20260907/system-r14-analyze-source-20260912T104815101Z`.
  Scope lib/test/integration_test/test_driver/tool/tools; manual helper วิเคราะห์
  แยกและมีเพียง file_names info 2 รายการ. ไม่อ้างว่า style infos เป็นศูนย์.
- Independent reviewer ไม่พบ actionable defect ใน timestamp delta.
- ทั้งสอง build exit 0, wholeSourceStable true และใช้ runtime fingerprint เดียว
  กับ tests/analysis. Packaged content 19 assets ต่อ APK ตรง source ทุก byte:
  `build/verification/system-followup-20260912/r14-apk-content-audit.json`.

| APK ใน build/verification/motivation-ui-20260908/device/ | Version code | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| lexiquest-learning-preview-manual-v23-thai-r14-debug.apk | 23 | 154615001 | `dc033748259db882aaf8a194ddbc7a1b4756e34b3cb23801dbe8d954cdabcd6e` |
| lexiquest-learning-preview-v28-thai-r14-debug.apk | 28 | 227451707 | `8248c928c1ee4ea579b0ac5b37ff1fa1de899ebbb91b64663db87da705ff278b` |

Manual v23 ติดตั้งบน vivo V2041/API33; ordinary v28 ยังไม่ได้ติดตั้ง/ตรวจ launcher
บนเครื่อง. ทั้งสอง debug, learning-preview=true, cloud-sync=false,
build ID `system-followup-thai-r14-20260912`.
Signer เดิม `1f10bbeedb0b8f18bcbb789c31d862bcfe9a3d146920033fb93eb1d228b0c5b4`.

## การอัปเดตและข้อมูลเดิม

ส่ง 37 ชิ้นด้วย adb push sync protocol แทน binary ผ่าน Windows stdin ที่เคย
เสียเมื่อพบ byte 0x1A. ตรวจ SHA ทุกชิ้นและไฟล์รวมบน vivo ก่อน `pm install -r -t`;
installed base.apk SHA ตรงกับ manual v23 ข้างต้น. LastUpdate 2026-09-12
17:52:57, firstInstall ยัง 2026-09-01 00:27:20. First-launch PID 10142,
PID-filtered AndroidRuntime/flutter error log ว่าง.

หลักฐาน `build/verification/system-followup-20260912/device-r14/transfer.json`,
`device-r14/install.json`, `r14-first-launch.json`, `before-r14.sqlite`,
`after-r14.sqlite` และ JSON ประกอบ. ทุกตารางเท่ากันก่อน/หลังอัปเดตและ integrity ok:
owners 2, categories 2, vocabulary 21, sessions 4, attempts 12,
reward transactions 1, points entries 1, achievement unlocks 4, SRS states 0.
รางวัลเหล่านี้มาจาก Quiz ที่ทำจริงก่อนอัปเดต ไม่ใช่ replay.
Primary files DB ไม่สูญหาย; คืนเฉพาะ synthetic code-cache fixtures ที่ Android
ลบระหว่าง update จาก backup ที่ตรวจ hash แล้ว.

## Device scenarios ที่มีหลักฐานจริง

- R13: Quiz 1 คำ cat → แมว ตอบถูกและหน้าผล 100%; session completed เพิ่มจริง
  1 รอบ/1 attempt. Focus Timer เริ่ม พักคงที่ 51s ทำต่อ และจบ 79s.
- R13: SRS เปิดได้และแจ้งไม่มีคำถึงกำหนด; Back ได้ ไม่มี SRS session/ผลฝึกปลอม.
  Flip/grading ผ่าน automated tests แต่ยังไม่ใช่ physical due-card result.
- R13: History แสดง CEFR generic title และระบุ missing original title/level.
  Replay รอบนั้นถูกปฏิเสธก่อนเขียน session; สาเหตุแก้ใน R14 แล้ว.
- R14 ช่วงแรก: เปิด Today → History แล้วกด replay source 6 คู่เก่า เปิด board ได้จริง
  (`manual-ui/r14-replay-inspect.png`). จึงยืนยัน actual-clock admission ผ่าน.
  ผลจบที่ทำต่อและตรวจหลัง restart อยู่ในหัวข้อปิดงานด้านล่าง.
- ระหว่างอ่านหน้าจอพบ attempts 6 รายการ (ถูก 4 ผิด 2) เวลา 17:59:41–18:00:07
  ก่อน visual-tap ของ root ที่ 18:00:23–25. ไม่มี task-owned Python/Dart/ADB
  client ค้าง (มีเฉพาะ ADB server). จึงพัก input เพื่อไม่ชนกับผู้ใช้/ตัวควบคุมอื่น.
  ไม่สรุปว่า engine ตอบเอง และไม่นับ interaction ที่ไม่ทราบผู้ทำเป็น scripted PASS.
- UIAutomator สร้าง hierarchy ไม่สำเร็จในหน้า Pair; screenshot ใช้ได้และแอป
  ยัง foreground. Host มี display tick 250ms แต่ยังไม่พิสูจน์ว่าเป็นสาเหตุของ
  idle timeout. เก็บภาพ fallback และหยุด retry dump เส้นทางเดิม.
- `replay-live-observation.sqlite` เป็น read-only copy ขณะ process ยังอยู่,
  integrity ok; ใช้วินิจฉัยเท่านั้น ไม่แทน final quiesced/restart acceptance.
  Original owner/vocabulary/completed sessions/attempts ยังครบ และ reward,
  points, achievements, SRS ไม่เพิ่มจาก replay ณภาพข้อมูลนี้. Event records
  เดิมยังอยู่; เปลี่ยนเฉพาะ projection cursors 4 ตัวตาม existing upsert contract
  (coins/quest/streak/reward) เพื่อเลื่อน frontier ไป attempt ที่ประมวลผลล่าสุด.
  ไม่ใช่รางวัลเพิ่มหรือการเขียนทับ learning evidence เดิม.

## กล้อง

รายงาน `2026-09-12-camera-followup.md` มี paired existing test images 40 ภาพ:
crop baseline 18/40 vs pilot 37/40; full-frame 14/40 vs 35/40.
OOD มีเพียง UI golden 2 ภาพ จึงไม่ใช่ natural unknown validation.
Pilot 4-class softmax ใช้ threshold 0.15 ปฏิเสธ unknown ไม่ได้ (max >= 0.25).

Vivo manual R13 วัด 12 fresh processes, 3/model/method, 5 warm + 50 measured
ต่อ process ใช้ book RGB input เดียวที่ pin SHA. Warm median ของ baseline/pilot:
default CPU 25.607/99.766ms; explicit XNNPACK 36.405/21.282ms.
Sampled RSS growth 9.03/39.19MiB และ 18.51/38.41MiB ตามลำดับ.
ไม่มี errors ใน process ที่วัด. Raw/aggregate อยู่ `system-followup-20260912/camera/`.
ไม่รวม capture/preprocessing; RSS ไม่ใช่ model-only/continuous peak และภาพเดิม
ที่รันซ้ำไม่นับเป็น independent accuracy sample. **คง baseline** เพราะ coverage,
unknown rejection และ memory ของ pilot ยังไม่เหมาะต่อการแทนโมเดลหลัก.
Benchmarks ทำบน R13; R14 ไม่มี camera runtime/model change ตาม source audit.
Runtime/whole R13→R14 delta มี 3 ไฟล์: replay builder, replay regression และ
nav test ที่ลบ unused import. Camera helper pin
`9341b58258dcec499ec5c0f924d633c2c142286c45da235acb9d684ef571dcdd`
ไม่เปลี่ยน; APK Flutter assets 43 entries เปลี่ยนเฉพาะ kernel_blob.bin.
ไม่มี .tflite embedded ใน APK; bytes ของโมเดลทดสอบมีหลักฐาน staging แยก.

ตรวจ source reconciliation หลังเขียน checkpoint ที่
`build/verification/system-followup-20260912/r14-checkpoint-reconciliation.json`.
Runtime files ต้องตรง gate เดิมทั้งหมด; whole-source อนุญาตเฉพาะ checklist
ในแผนที่อัปเดตสถานะหลัง build. ไม่ถือว่า docs-only เปลี่ยนเป็น runtime build ใหม่.

## ผลปิดงานบน vivo

1. ฝึกซ้ำ 6 คู่จบ: ทำเอง 4, ตัวช่วย 2, ดาว 1/3, interactive 1,381,955ms.
   ยืนยันตัวช่วย bottle/clock ผ่าน UI หลังเลื่อนถึงปุ่ม. รอบนี้รวมช่วงก่อนพัก input
   จึงไม่อ้างว่า root เป็นผู้ตอบทุก attempt หรือเวลาเป็น benchmark ความเร็วผู้เรียน.
2. ฝึกซ้ำ 4 คู่เปิดจากต้นทางเก่าและ root จับครบ 4 คู่: ไม่มีตัวช่วย, ดาว 3/3,
   interactive 94,117ms. ย้อนกลับ History/Today/Learn ได้. หลัง restart เปิด
   History ใหม่ เห็นทั้งสองผลพร้อมรอบต้นทางและข้อความไม่เพิ่มรางวัล.
3. เปิดบทอ่าน A1–C2 ทั้งหกจาก Learn และ Back ครบ; เปิด A1/C2 ซ้ำ,
   C2 เลื่อนอ่านและกดอ่านจบ. A1 พอดีหน้าจอ ไม่มี scroll container จึงไม่ฝืนเลื่อน.
   ทั้งหมดมี notice ระดับโดยประมาณ/ไม่ผ่านรับรอง CEFR. ภาพ R14 ใหม่อยู่
   `manual-ui/r14-reading-a1-20260912.png` ถึง `r14-reading-c2-20260912.png`
   พร้อม back/reopen/scroll captures; ไม่อาศัยภาพ R12 เป็นผล R14.
4. ทางเข้าฝึกจากคำศัพท์ที่มีระดับ → ตั้งค่า 1 ข้อ → C2 → อ่านจบ สำเร็จ.
   บันทึก 1 exposure session ตามกิจกรรมจริง (35s ใน History). Frozen adapter
   ใช้ isCorrect:false เป็น placeholder สำหรับ exposure; ไม่ใช่ผลสอบผิด และ
   History ไม่แสดงเป็น accuracy. การเปิดอ่านจาก library ไม่สร้าง session ปลอม.
5. Scanner เปิดพบโมเดลยังไม่อยู่ในพื้นที่ใช้งาน จึงดาวน์โหลดผ่าน verified flow
   ของแอปสำเร็จ. Back/reopen พร้อมถ่าย/benchmark, model state active, 4,287,874
   bytes และ SHA `d3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b`.
   `scanner-r14-installed.json` ยืนยัน private file bytes และ PID error log ว่าง.
   ไม่ถ่ายหรืออ้าง physical object accuracy จากขั้นนี้.
6. Force-stop/capture → relaunch → เปิดแอปจริง → Today/History → capture:
   `final-db-audit.json` และ `final-restart-audit.json` ผ่าน integrity/foreign keys/
   unchanged schema. ก่อน/หลัง update ทุกตารางเหมือนเดิม; หลัง restart 48/49
   ตารางเหมือนทุกแถว อีกตารางเปลี่ยนเฉพาะ timestamp การตรวจ offline cache.
   ทุก learning/history/vocabulary/reward/model row คงเดิมหลัง restart.

Final database: 7 completed sessions, 25 attempts, vocabulary 21, owners 2,
events 221, time segments 13, reward transactions 1, points entries 1,
achievements 4, SRS 0. เทียบ before-R14 เพิ่มเฉพาะ Pair replay2 + CEFR1,
13 attempts (Pair12 + exposure1); rewards/points/achievements เพิ่ม0,
SRS/quest/streak/research ไม่เปลี่ยน. Ordinary outbox เพิ่ม14รายการ pending/unsent,
ไม่มี cloud/research upload. Cursor4ตัวตรวจ source/receipt/projection lineage แล้ว.

Capture hashes:
- after-scenarios.sqlite `fadc3c8df44b9d0e099218c8667c192e128ab0596b695d031717098303689639`
- after-restart.sqlite `b3869cdb99701892ae2f1a0c6118fe53f02fafe27704c7b0a93bc6d6785974b6`

Simple capture assertions เดิมกว้างเกินไปสำหรับ mutable current configuration
และ cache: พบเฉพาะ CEFR config updated_at เปลี่ยน (identity/serialized bytes
เดิม), cursor upsert และ cache revalidation timestamp. เก็บ failed captures เดิม
ไม่ทับ/แก้ DB แล้วตรวจด้วย audit ที่จำกัด exact allowed columns/lineage แทน.
ไม่มีการลด assertion ของ product test หรือแก้ frozen evidence contract.

`r14-final-relaunch.json`: version23/SHAเดิม, new PID17253, startup errorsว่าง.
หลังเก็บหลักฐานเปิดแอปกลับให้ใช้งานต่อ. ไม่มี source runtime edit หลัง826 tests;
การเปลี่ยนหลัง build เป็น checklist/report และ scratch verification เท่านั้น.
Final source/artifact/report pins อยู่ `r14-delivery-reconciliation.json`
ใน `build/verification/system-followup-20260912/` (แทน checkpoint reconciliation
ก่อนหน้าซึ่งเก็บเป็นหลักฐานย้อนหลัง). ไม่มี build/test/agent/benchmark ค้าง;
ADB server คงไว้ตามปกติ.

เงื่อนไขนอกการทำอัตโนมัติยังเดิม: ฟัง/พูด Shadowing จริง, human TalkBack,
AI provider/model/budget/key, cloud สองเครื่องและ test accounts, physical camera
หลายแสง/มุม/ระยะ. ยังไม่อ้าง production readiness หรือผลรับรองระดับ CEFR.
