# CEFR quality and practice — R12 verified checkpoint

วันที่ 2026-09-12 · worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
branch `codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2`.
งานคุณภาพเนื้อหาและการนำไปฝึกตามขอบเขตนี้เสร็จแล้ว เป็นรุ่น debug preview
ไม่ใช่ production rollout หรือการรับรองระดับภาษา/ผลการเรียนโดยมนุษย์
รักษาการแก้ไขเดิมทั้งหมดใน worktree ไม่มี commit, merge หรือเผยแพร่บริการจริง

## เนื้อหาและพฤติกรรมที่ส่งมอบ

- ชุดหลัก A1–C1 5,000 คำ และชุดเสริม C2 500 คำ มีความหมายหลัก ประโยคอังกฤษ
  ที่เขียนขึ้น และคำแปลไทยครบทุกคำ สามผู้เขียนอ่านทวนและผู้ตรวจอีกคนตรวจข้ามชุด
  การแก้จากผู้ตรวจทุกจุดมีการอ่านทวนฉบับสุดท้าย ไม่ใช้จำนวนแถวแทนการตรวจภาษา
- ตรวจความหมายต้นฉบับครบ 10,793 รายการ: รับ 8,654 และไม่เสนอให้เลือก 2,139
  พร้อมเหตุผล เก็บต้นฉบับไว้ครบ ไม่เปลี่ยน index หรือเขียนทับคำที่ผู้ใช้บันทึกไว้
  ความหมายที่เกลาคำสะกดแต่ยังเป็น sense เดิมรักษา import identity เดิม
  cooker ที่เปลี่ยนเป็นความหมายเครื่องหุงต้มแบบอังกฤษแยก identity อย่างชัดเจน
- ตัวอย่างใหม่ 3,466 รายการรวมกับเดิม 2,034; แก้ตัวอย่างเดิม 33 รายการตามผลตรวจ
  source-linked primaries 4,927 / independent senses 573; explicit POS overrides
  มีเพียง its และ wizard. Validator ไม่มี warnings. มีประโยคซ้ำสี่คู่คนละ headword
  ซึ่งตรวจแล้วใช้ประกอบทั้งสองคำได้ ไม่ใช่คำศัพท์ซ้ำ
- คลังเปิดออฟไลน์ได้ ค้นคำ/คำแปล เลือกระดับ แยก C2 ดูความหมายที่คัดและตัวอย่าง
  พร้อมป้าย AI และระดับอ้างอิง/ไม่ใช่การรับรอง CEFR ความหมายอื่นแสดงเฉพาะที่รับไว้
  คำเหยียดรุนแรง gook มีคำเตือนสำหรับการรู้จำและไม่เสนอเพิ่มเข้าชุดฝึก
- ค้นผู้สมัครกิจกรรมต่อจาก 100 แถวแรกด้วย keyset paging รักษา owner/deleted
  filtering และ canonical admission เดิม กรณีไม่มีคำเข้าเงื่อนไขแจ้งตรงเหตุผล
- ดูตัวอย่างจากคลังส่วนตัวได้ Quiz แสดงหลังตอบ และ Flashcards หลังพลิกเท่านั้น
  จับคู่ด้วย spelling/meaning/POS/level; ไม่แนบตัวอย่างผิดความหมายเมื่อผู้ใช้แก้คำ
  ไม่เพิ่มผู้เขียนคะแนนหรือหลักฐานกิจกรรมใหม่ การดูตัวอย่างไม่สร้างผลตอบ
- คงบทอ่านหกบท A1–C2 ตรวจภาษา/คำถามโดยสองผู้ตรวจ AI เป็นบทอ่านสั้นระดับประมาณ
  คำถามฝึกคิดไม่มีการตรวจคะแนนอัตโนมัติ ไม่ใช่หลักสูตร CEFR ที่ผ่านการรับรอง
- จัดแยกส่วนความหมาย ตัวอย่าง และคำแปลพร้อมระยะห่างในหน้าคำศัพท์ ส่วนแก้ท้าย
  R12 ทำให้หัวเรื่องบทอ่านใช้สีข้อความตามธีม แทนสีน้ำเงินเข้มบนพื้นมืด

## ผลตรวจบนซอร์สสุดท้าย

- `tools/validate_cefr_editorial.py --complete --write-manifest --report ...`
  PASS ครบ 5,500 primary และ partition 10,793 original senses; ตรึง hash เก้า JSON
  ใน `lib/features/vocabulary/data/cefr_editorial_manifest.dart`.
  รายงาน `build/verification/cefr-complete-20260912/final-editorial-validation.json`.
  immutable base catalog ทั้งสี่ไฟล์ผ่าน SHA เดิมและ license/attribution คงอยู่
- Python validator unit tests 3 PASS; focused reader/theme follow-up 10 PASS
- Final integration **204 PASS**: vocabulary subsystem, Drift learning repository,
  ChooseMode, Quiz, SRS, personal vocabulary, CEFR catalog/detail/example,
  selection/reader/library, six readings, Thai encoding/navigation boundaries
  รวม coverage 5,500/10,793, corrupt overlay fallback, excluded import,
  unchanged saved edits, candidate after100 และไม่รั่วตัวอย่างก่อนตอบ
- Current-source gate exit0/stable, runtime fingerprint
  `ceac723c48cef5b1937e7694c006558e14ddd312309988135446601813d3a36a`, 1,360 files.
  หลักฐาน `build/verification/remediation-20260907/cefr-r12-regression-20260912T093446938Z`.
  Earlier R11 204 PASS ถูกทดสอบซ้ำหลังแก้สี ไม่ใช้ผลเก่าอ้างแทนซอร์สสุดท้าย
- Analysis 15 runtime files: ไม่มี error/warning แต่มี **6 pre-existing infos**
  เรื่อง braces ใน Drift repository lines1147,1216,1221,1324,2570,2580 (exit1).
  Reader ที่แก้เพิ่ม: No issues/exit0. ไม่อ้างว่า analysis ทั้งชุดสะอาด
- Scoped independent code reviews โดย editorial_one และ editorial_two
  ไม่พบ actionable issue ใน examples/hosts, paging, overlay และ import preservation
  Final focused diff whitespace check exit0; Git มีเพียงคำเตือน CRLF เดิม
- Build ทั้งสองแบบสำเร็จ/source stable; มีคำเตือน KGP compatibility สำหรับ Flutter
  รุ่นอนาคตใน firebase_app_check/flutter_tts/speech_to_text/workmanager_android
  ไม่มี build failure; ไม่ปรับ dependency นอกขอบเขตนี้

## APK ที่ตรวจแล้ว

ทั้งสองไฟล์อยู่ใน `build/verification/motivation-ui-20260908/device/`:

| APK | bytes | SHA-256 |
| --- | ---: | --- |
| `lexiquest-learning-preview-manual-v21-thai-r12-debug.apk` | 154603785 | `6ba34338dcc412d11bd14591b966f538595a3f7021dba34edbef756c88ce57c6` |
| `lexiquest-learning-preview-v26-thai-r12-debug.apk` | 227448767 | `f538ff4df55ac39cea1c03787b5dd7a9bfb9860eb6f0cfef43872e7932192ad0` |

manual21 ใช้ persistent synthetic fixture และติดตั้งบน vivo แล้ว; ordinary26
ใช้ lib/main.dart สร้างและตรวจแพ็กเกจแล้วแต่ไม่ได้ติดตั้งแทน fixture
ทั้งคู่ debug-only, learning preview enabled, cloud sync disabled.
Signer `1f10bbeedb0b8f18bcbb789c31d862bcfe9a3d146920033fb93eb1d228b0c5b4`.
Whole-source fingerprint ตอน build และหลังทดสอบเครื่องก่อนเขียนรายงานนี้ตรงกัน:
`76978cc308c1cef3372976ad9add2346f50058932190cdef9f4a6d554bf2f518` (1,611 files).
Package audit ของทั้งสอง APK ยืนยันไฟล์เนื้อหา 19 ไฟล์ตรงกับซอร์สทุก byte
ใน `build/verification/cefr-complete-r12-20260912/apk-content-audit.json`.

## vivo และการรักษาข้อมูล

- vivo V2041/API33 serial9582188822004C6, package com.lexiquest.app
  R10 manual19 → R11 manual20 → **R12 manual21** โดย `pm install -r -t`
- ส่ง binary ผ่าน adb push sync protocol 37 parts ขนาดไม่เกิน4MiB ตรวจ SHA
  ทุก part แล้วประกอบภายใน Android ตรวจทั้งขนาด154603785และ SHA เต็มตรงคอม
  วิธีนี้เลี่ยงปัญหา Windows stdin ทำ binary เสียตรง byte0x1A ที่พบในงานก่อนหน้า
- SHA ของ APK ที่ติดตั้งจริงตรง manual21 ข้างต้น versionCode21/versionName1.0.0
  lastUpdate2026-09-12 16:38:44; firstInstall2026-09-01 00:27:20 ไม่เปลี่ยน
- Hash ไฟล์ app-data ก่อน/หลัง update ตรงกัน Android ล้าง code_cache QA ตามปกติ
  helper คืนเฉพาะ synthetic QA จาก backup ที่ตรวจ hash แล้ว ไม่ย้ายฐานหลักออกจาก files
- R11 physical UI: Learn→library, A1–C2 ทั้ง6บท, scroll A2–C2, back/reopen A1,
  estimated-level notice; A1 สั้นพอดีจอจึงไม่มี scroll container ไม่ใช่แอปค้าง
  คลังแสดง5,500/5,500; ชุดหลัก5,000/C2 500, C2 abhor example และแผงระดับภาษา
- R12 physical UI: launch→Learn→library→A1 ตรวจภาพหัวเรื่องใหม่ชัดเจน;
  catalog5,500/5,500, about example/translation, accepted alternative panel,
  เพิ่ม curated about ซ้ำลงหมวดเดิม แล้วเปิดตัวอย่าง about จากคลังส่วนตัวได้
  เนื้อหาทั้ง19ไฟล์เหมือนชุด R11 ที่ตรวจ; R12ต่างที่สีหัวเรื่องและbuild identity
- หลัง browse/reimport และ restart เทียบ **ทุกแถว** ใน10ตารางกับ R10 baseline:
  owners2, categories2, words21, sessions3, configs2, attempts11, reading_events0,
  events_v2 102, time_segments7, research_proofs0 ตรงทั้งหมด ไม่มี duplicate
  หรือหลักฐานกิจกรรมจากการอ่าน/เปิดตัวอย่าง PIDหลังเปิดใหม่26112, error logว่าง
  เป็นหลักฐานต่อ fixture ที่ตรวจ ไม่ใช่การอ้างข้อมูล production ที่ไม่ได้เข้าถึง
- หลักฐาน transfer/install/persistence ใน `build/verification/cefr-complete-r12-20260912/`.
  UI PNG/XML/JSON ใน `build/verification/motivation-ui-20260908/device/manual-ui/r11-*`
  และ `r12-*`; ไม่อ้างว่าเปิดดูตัวอย่างทีละ5,500คำบนโทรศัพท์

## ใช้ต่อและขอบเขตที่ยังต้องมีคน/บริการจริง

คู่มือ `docs/development/2026-09-12-cefr-learner-guide.md`.
รายงาน editorial/cross-review ทั้งสามชุดและ root adjudication อยู่ใน docs/development
ชื่อวันที่2026-09-12-cefr-*. การตรวจภาษาเป็น AI assisted ไม่ใช่ human certification

ยังไม่อ้างผ่าน: การได้ยินเสียง/รับคำพูดจริง/Shadowing/TalkBackที่ต้องมีผู้ถือเครื่อง,
AI Tutor บริการจริงซึ่งรอ provider/model/budget/key, sync จริงสองเครื่องและบัญชีทดสอบ,
การวัดโมเดลกล้องกับวัตถุจริงและตัดสินโมเดลส่งมอบ งานเหล่านี้ไม่ถูกแทนด้วยผลจำลอง
ไม่มีการใช้งบ API, real research enrollment/upload หรือ production deployment.

ไม่มี task-owned build/test process ค้าง ผู้ช่วยทั้งสามหยุดเขียนแล้ว
ขั้นถัดไปเมื่อผู้ใช้พร้อม: ใช้ R12 บน vivo ทำการฟัง/พูดและตรวจ accessibility ร่วมกัน
หรือดำเนินเงื่อนไขบริการภายนอกตามสิทธิ์และงบที่ผู้ใช้กำหนด
