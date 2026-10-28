# คลังคำศัพท์ออฟไลน์ 3,000 คำ — R7

วันที่ 2026-09-12 · งานเพิ่มคำระหว่างผู้ใช้ไม่ว่าง

## สถานะและขอบเขต

เพิ่มคลังอ้างอิงออฟไลน์ในซอร์ส สร้าง preview APK สองแบบ และอัปเดตรุ่นทดสอบ
บน vivo สำเร็จ เป็นการส่งมอบด้านวิศวกรรม ยังไม่ใช่การรับรองคุณภาพรายความหมาย
หรือหลักสูตร CEFR ครบ A1–C2

ทางเข้า: เรียน → เปิดอ่านตามระดับภาษา CEFR → คลังคำศัพท์ CEFR 3,000 คำ
ค้นหาอังกฤษ/ไทย กรองระดับ เปิดความหมาย และเลือกเพิ่มทีละความหมายเข้าหมวดส่วนตัว
ผ่าน VocabularyUseCases เดิม ไม่เพิ่ม 3,000 แถวอัตโนมัติ ไม่เปลี่ยนตารางฐานข้อมูล
ไม่สร้างประวัติการเรียนจากการเปิดคลัง หมวดส่วนตัวยังคงจำกัด 50 คำต่อหมวด
ไม่มีหมวดให้เลือกจะแนะนำให้สร้างในแท็บคลังคำศัพท์ก่อน

| ระดับอ้างอิง | จำนวน headword |
| --- | ---: |
| A1 | 933 |
| A2 | 1,101 |
| B1 | 483 |
| B2 | 483 |
| รวม | 3,000 |

มีข้อความแปลให้เลือก 6,676 รายการ รวมอยู่ใต้ headword เดิม ไม่ใช่ 6,676 คำไม่ซ้ำ
เก็บตัวพิมพ์ตามต้นทาง เช่น April/I และรวม headword โดยไม่แยกตัวพิมพ์เล็กใหญ่
เลือก POS/ระดับที่พบก่อนในระดับต่ำสุดเมื่อ headword ซ้ำ จึงไม่ได้เก็บทุก POS
เลือกทุก A1/A2 ที่จับคู่ข้อมูลได้ จากนั้นแบ่ง B1/B2 และกระจายตามตัวอักษร
ไม่ใช่อันดับความถี่ ไม่อ้างว่าครบทุกคำของระดับนั้น

## แหล่งข้อมูลและข้อจำกัดคุณภาพ

- ระดับคำ/ชนิดคำ: [CEFR-J 1.5 ผ่าน Open Language Profiles](https://github.com/openlanguageprofiles/olp-en-cefrj)
  CSV SHA-256 `b0dd3c635f1c9a4fdf1490c7e5b7c48e8bbe55b652ad0c9860a95f98e10ae498`
- ความหมายไทย: [LEXiTRON 2.0 จาก NECTEC/NSTDA](https://opend.nstda.or.th/en/dataset/lexitron-2-0)
  ZIP SHA-256 `604fa2d1cccacfca01f919764ed5a99c78730afe55ddcd1863b42a8d56194840`
- สงวนเครดิตต้นทาง มี NOTICE และใบอนุญาตอังกฤษ/ไทยฉบับเต็มใน asset และหน้าแอป
  ไม่ใช้รายการ Google frequency ที่ดาวน์โหลดเพื่อสำรวจ เพราะสิทธิ์ที่พบไม่ชัดเจน
- Catalog SHA-256 `b1af6f5c444650d39d6873bf7db7632585b2220b69bce323327693c021641140`
- จับคู่ตัวสะกดแบบ case-sensitive และ POS เท่านั้น ไม่แต่งระดับหรือคำแปลเติม
  ตัวอย่างคำหลายความหมาย เช่น address/above อาจแสดงความหมายแรกที่ไม่เหมาะเป็น
  ความหมายเริ่มต้นสำหรับ A1 แม้ระดับของ headword มาจากต้นทาง
  ต้องคัด/เรียงความหมายและตรวจประโยคตัวอย่างรายคำก่อนยกระดับเป็นชุดบทเรียนรับรองคุณภาพ
- ระบุในแอปว่ายังไม่ได้ตรวจทุกความหมายรายคำ ไม่ได้วิเคราะห์/รับรองระดับของผู้เรียน
  ยังไม่มีประโยคตัวอย่างที่ตรวจครบ 3,000 คำ และไม่มี C1/C2 ในคลังชุดนี้
- รายการที่เพิ่มใช้ระบบคำศัพท์ส่วนตัวปกติ สถานะไม่ได้กลายเป็นเนื้อหา rich-content
  ที่ผ่านการตรวจอัตโนมัติ จึงไม่อ้างว่าทุกโหมดที่ต้องใช้ประโยค/คำใบ้พร้อมทุกคำ
- การค้นหาคลังใหม่นี้ดูครบ 3,000 คำ ข้อจำกัด 100 รายการของทางเข้ากิจกรรม CEFR
  เดิมเป็นอีก query และยังไม่ได้แก้ในงานนี้ บทอ่านยังคง 6 บทตามที่ผู้ใช้เลือก

## หลักฐานทดสอบ

โฟลเดอร์หลัก: `build/verification/cefr-catalog-20260912/`

- `generator-verified.log`: Python unittest 4 ผ่าน ตรวจ join/POS/ตัวพิมพ์/ข้อมูลเสีย/การเลือก
- `regression-verified.log`: Flutter 94 ผ่าน ครอบคลุม vocabulary, catalog UI,
  local reading library, article reader, choose mode, adapters และ Thai encoding
- `analysis-verified.log`: วิเคราะห์ 7 ไฟล์ที่เกี่ยวข้อง ไม่พบปัญหา
- `data-audit.json`: สร้างซ้ำได้ byte-for-byte, 3,000 headword ไม่ซ้ำ,
  ทุกความหมายอยู่ในขีดจำกัด importer, catalog/notice/licenses ภายใน APK ตรงซอร์ส
- ทดสอบ importer ด้วยฐานข้อมูลจริงในหน่วยความจำ: เพิ่มซ้ำ, คำที่ผู้ใช้แก้แล้ว,
  หมวดครบ 50 คำ, owner เปลี่ยน, หมวดหาย, index ผิด และไม่สร้าง session/attempt
- Widget tests: หน้าจอ 390×844 text scale 2, ค้นหาคำท้ายคลังเกิน 100,
  ทางเข้า Learn และข้อความกรณีโหลดล้มเหลว
- RED ระหว่างพัฒนาได้รับการแก้ทั้งหมด รวม source ยาวเกิน 60 ตัว และการนำคำที่แก้แล้ว
  เข้าซ้ำ ส่วน assertion ที่คาด May ในชุด final เปลี่ยนเป็น April เพราะ canonical
  headword may ถูกเลือกเป็น modal จากแถวก่อนหน้า ไม่ได้แก้แหล่งข้อมูลเพื่อให้ test ผ่าน
- ไม่ได้รัน full-repository regression ใหม่ในงานนี้ ไม่ใช่ release sign-off ทั้งระบบ

### vivo V2041 / Android 13

ใช้ synthetic QA fixture เดิม `files/lexiquest-manual-uat-v1` แยกจากฐานข้อมูลผู้ใช้
ส่ง 37 ส่วนด้วย adb push -Z ตรวจ SHA ทุกส่วนและรวมบน Android แล้วตรวจทั้งไฟล์
ติดตั้ง `pm install -r -t` สำเร็จ versionCode 15 → 16 และแฮช APK ที่ติดตั้งจริงตรงกัน
firstInstallTime ยังคง 2026-09-01 00:27:20 ไม่มี uninstall/clear-data
Package Manager ล้าง code_cache fixture เก่า 5 ไฟล์ จึงคืนเฉพาะรายการที่หายจาก backup
ตรวจแฮชไฟล์ข้อมูลที่ป้องกันไว้ทุกไฟล์ก่อน/หลังอัปเดตตรงกัน

- เรียน → บทอ่าน → คลัง 3,000 เปิดได้ เห็นจำนวนเต็ม
- ค้น April เปิดความหมาย/ข้อความสถานะภาษา และเลือกเดือนเมษายนเข้าหมวดทดสอบได้
- เพิ่ม April ซ้ำผ่าน UI สองครั้ง ได้แถวใหม่เพียงหนึ่งแถว: คำเดิม 18 → 19
- ตัวเลือก A1/A2/B1/B2 ปรากฏ เลือก B2 ขณะค้น April แสดงไม่พบ 0/3000
- เปิดสิทธิ์ใช้งานได้ ไทยไม่เสีย ย้อนกลับ เปิดคลังซ้ำ และเลื่อนรายการได้
- เปรียบเทียบฐานข้อมูล: คำเดิมทั้ง 18 แถวไม่เปลี่ยน, owners 2, categories 2,
  sessions 3, configurations 2, attempts 11, reading_events 0, events 102,
  time_segments 7, research_session_proofs 0 คงเดิมทุกแถว
- ปิด/เปิดแอปซ้ำแล้วเปรียบเทียบอีกครั้งข้อมูลตรงกัน ไม่พบ flutter:E/AndroidRuntime:E
  ของ PID ที่เปิดใหม่ (`persistence.json`, `r7-relaunch-errors.log`)
- ภาพ/ลำดับ UI: `build/verification/motivation-ui-20260908/device/manual-ui/r7-*.{png,json,xml}`
- หลังตรวจปล่อยแอปไว้หน้า launcher ของรุ่นทดสอบ ไม่เปิดไมค์/เล่นเสียง

## APK และ source provenance

APK อยู่ใน `build/verification/motivation-ui-20260908/device/`

| Artifact | SHA-256 | สถานะ |
| --- | --- | --- |
| `lexiquest-learning-preview-manual-v16-thai-r7-debug.apk` | `1444e5895d0e47d4bd69a7d4ff976a3f1f54a446c5c95738b56c4fab5e894604` | ติดตั้งและตรวจบน vivo |
| `lexiquest-learning-preview-v21-thai-r7-debug.apk` | `62a8d7849369df4dfe2195fc600d1b1a40c6ab5cda198677d1bf5901563f61f6` | สร้าง ordinary preview ไม่ติดตั้ง |

ทั้งสอง build ผ่าน current-source gate และซอร์สไม่เปลี่ยนระหว่าง build
whole-source fingerprint ณ build:
`5051bb0d5b7fd1a0a00118b5ad2a5e4908c13419cd742d94089804922beb5100`
runtime gate fingerprint: `fece6fcce881f0e24d3b59333ab923b2c815b7a82eec3622dd538cde3900b894`
หลัง build เปลี่ยนเฉพาะ checklist ของแผนและเพิ่ม checkpoint นี้ ไม่เปลี่ยนโค้ด/assets/tests
ทั้งสองเป็น debug preview ปิด cloud sync ไม่ใช่ APK production หรืออนุญาตเปิด research

## ไฟล์งานและขั้นต่อไป

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
branch `codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2`
เก็บงานเดิมที่ modified/untracked ไว้ทั้งหมด ไม่มี commit/reset

เพิ่ม `tools/build_cefr_catalog.py`, `tools/test_build_cefr_catalog.py`,
`assets/content/cefr_starter/{catalog.json,NOTICE.txt,LICENSE.txt,LICENSE-th.txt}`,
`lib/features/vocabulary/data/cefr_vocabulary_catalog.dart`,
`lib/features/vocabulary/application/cefr_catalog_import.dart`,
`lib/screens/cefr_vocabulary_catalog_screen.dart`,
`test/features/vocabulary/{cefr_vocabulary_catalog_test.dart,cefr_catalog_import_test.dart}`,
`test/screens/cefr_vocabulary_catalog_screen_test.dart` และแผน/รายงาน
แก้ `pubspec.yaml` เพิ่ม 4 assets และ `lib/screens/local_reading_library_screen.dart` เพิ่มทางเข้า

ไม่มี process ทดสอบ/build/transfer ค้าง งานถัดไปที่ทำได้โดยไม่ใช้คนคือคัดความหมายพื้นฐาน
และตรวจคำแปล A1/A2 เป็นชุด พร้อมประโยคตัวอย่างและหลักฐานรายรายการ
งานเสียงคนจริง, AI provider/model/budget, sync สองเครื่อง และกล้องในสภาพจริงยังรอ
ความพร้อมตาม checkpoint ก่อนหน้า งานนี้ไม่เปลี่ยนสถานะผ่านของงานเหล่านั้น
