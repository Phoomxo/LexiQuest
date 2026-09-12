# คลังคำศัพท์ชุดหลัก 5,000 + C2 เสริม 500 — R8

2026-09-12: ผู้ใช้อนุมัติขยายชุดหลักเป็น 5,000 คำและเพิ่มชุดเสริม C2
ดำเนินการต่อใน worktree เดิมโดยไม่ต้องใช้คนถือเครื่องหรือบริการ AI ที่เสียเงิน

## ผลส่งมอบ

เพิ่ม 2,000 คำในชุดหลัก และ C2 แยกอีก 500 คำ รวม 5,500 headword ไม่ซ้ำ
คง asset ของ 3,000 คำเดิมแบบ byte-for-byte รวมรหัส ความหมาย ลำดับความหมาย
และ namespace สำหรับนำเข้าคลังส่วนตัว จึงไม่สร้างคำซ้ำเมื่ออัปเดตจาก R7

| ชุด | ระดับ | จำนวน |
| --- | --- | ---: |
| หลัก | A1 | 933 |
| หลัก | A2 | 1,101 |
| หลัก | B1 | 1,233 |
| หลัก | B2 | 1,233 |
| หลัก | C1 | 500 |
| เสริม | C2 | 500 |

ทางเข้า: เรียน → เปิดอ่านตามระดับภาษา CEFR → คลังคำศัพท์ 5,000 คำ + ชุดเสริม C2
ค่าเริ่มต้นค้นชุดหลัก A1–C1 จำนวน 5,000 คำ เลือก “ชุดเสริม C2” เพื่อค้นอีก 500 คำ
เลือกหนึ่งความหมายเข้าหมวดส่วนตัวผ่าน VocabularyUseCases เดิม จำกัด 50 คำต่อหมวด
ไม่ยัดคำทุกคำเข้าฐานข้อมูลอัตโนมัติ ไม่เพิ่ม schema/learning/reward authority

## แหล่งข้อมูลและคุณภาพ

ระดับ A1–B2 จาก CEFR-J 1.5 ระดับ C1/C2 จาก Octanove 1.0 ผ่าน
[Open Language Profiles](https://github.com/openlanguageprofiles/olp-en-cefrj)
คำแปลไทยจาก LEXiTRON 2.0 โดย NECTEC ตามเครดิต/ใบอนุญาตเดิมของ R7

Octanove ต้นทาง 2,136 แถว จับคู่คำแปลแบบ exact spelling/POS และตัดคำที่ซ้ำ
กับรายการ CEFR-J ทั้งชุดแล้ว เหลือใช้ได้ C1 695/C2 612 คำ เลือกอย่างละ 500
เพิ่ม B1/B2 อย่างละ 750 คำจากแหล่งเดิม กระจายตามตัวอักษร ไม่จัดอันดับความถี่
คำแปลทั้งหมด 10,793 รายการเป็นหลายความหมายภายใต้ 5,500 headword

Octanove source CSV ที่แจกมากับแอปคงต้นฉบับ แยก advanced-profile.json ซึ่งเป็น
ดัชนีระดับดัดแปลงภายใต้ [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
ออกจาก advanced-translations.json ซึ่งเป็น lookup คำแปล NECTEC ที่คงใบอนุญาต
LEXiTRON ของตนเอง ไม่เปลี่ยนสิทธิ์คำแปลเป็น CC ใส่เครดิต ลิงก์ใบอนุญาต และรายการ
สิ่งที่ดัดแปลงใน NOTICE และ asset ดัชนี ข้อมูลแสดงร่วมกันผ่าน join ในแอป

ข้อจำกัดยังคงเดิม: ไม่ใช่หลักสูตรรับรองหรือชุด C2 ครบทุกคำ ระดับเป็น annotation
ที่ headword/POS ไม่รับรองทุกความหมาย คำแปลยังไม่ได้ตรวจความเหมาะสมรายความหมาย
หรือเรียงความหมายพื้นฐานก่อนทั้งหมด ยังไม่มีประโยคตัวอย่างตรวจครบทุกคำ
ไม่ใช้การเพิ่มจำนวนคำเป็นหลักฐานว่าผู้เรียนจะถึง C1/C2

## การตรวจ

หลักฐานใน `build/verification/cefr-expanded-20260912/`

- `generator-green.log`: Python 6 ผ่าน รวม generator เดิม/ใหม่
- `regression-verified.log`: Flutter 97 ผ่าน บนซอร์สสุดท้ายก่อน build
  ครอบคลุม vocabulary, expanded catalog, UI, reading, mode routing, adapters, Thai encoding
- `analysis-verified.log`: 8 ไฟล์ ไม่พบปัญหา
- `data-audit.json`: สร้างซ้ำ byte-for-byte, 3,000 เดิมไม่เปลี่ยน, 5,500 headword
  ไม่ซ้ำ, ทุกความหมายและ source tag อยู่ในขีดจำกัดของ importer
- tests ตรวจแยกจำนวน 5,000/500, ค้น C2 เกิน 100 รายการ, ปฏิเสธ asset hash ผิด,
  การนำคำเก่าที่ผู้ใช้แก้แล้วเข้าซ้ำหลังขยาย, owner/category/capacity gates,
  นำคำ C2 เข้าซ้ำแล้วได้ ID เดิม, ไม่สร้าง session/attempt จากการนำคำเข้า
- มี widget coverage หน้าจอแคบ text scale 2 และหน้ารายละเอียด/ข้อความผิดพลาด
- แก้ style info เรื่องวงเล็บ if หนึ่งจุดแล้ววิเคราะห์/ทดสอบซ้ำผ่าน
- ทั้งสอง APK ตรวจ asset 9 ไฟล์ตรงกับซอร์ส (`manual-asset-audit.json`,
  `ordinary-asset-audit.json`) ไม่ได้รัน full-repository regression ใหม่

### vivo V2041 / Android 13

ติดตั้งแบบอัปเดต `-r -t` versionCode 16 → 17 ใช้ signer เดิม
ส่ง 37 ส่วนด้วย adb push -Z ตรวจ SHA ต่อส่วนและไฟล์รวม ก่อนตรวจ APK ที่ติดตั้งจริง
firstInstallTime ยังเป็น 2026-09-01 00:27:20 แฮชข้อมูล protected files ก่อน/หลังตรงกัน
คืนเฉพาะ synthetic code_cache เก่าที่ Package Manager ล้างจาก backup ที่ตรวจแฮชแล้ว
ไม่มี uninstall/clear-data และไม่ได้เปลี่ยนข้อมูลส่วนบุคคลเป็น fixture

- เปิดผ่าน Learn เห็นชุดหลัก 5000/5000, C1 500/5000 และชุดเสริม C2 500/500
- เปิด aberration C2 เห็นคำแปลและที่มาระดับ Octanove 1.0 พร้อมคำชี้แจงคุณภาพ
- เลือก “การเบี่ยงเบนจากปกติ” เข้าหมวดคำตัวอย่างสำหรับทดสอบสำเร็จ
- กลับชุดหลัก ค้น April แล้วเพิ่ม “เดือนเมษายน” ซ้ำ ไม่สร้างรายการใหม่
- เปรียบเทียบ synthetic DB R7 → R8: 19 คำเดิมอยู่ครบทุกแถว เพิ่ม aberration เพียง
  1 แถวเป็น 20 คำ source `cefr-expanded-r1/aberration/0`, April มีเพียง 1 แถว
- owners 2, categories 2, sessions 3, configurations 2, attempts 11,
  reading_events 0, events_v2 102, time_segments 7, research_session_proofs 0
  ทุกแถวตรงกับก่อนอัปเดต ไม่มีประวัติเรียนเพิ่มจากการเปิดคลัง/เพิ่มคำ
- ปิด/เปิดแอปแล้วข้อมูลตรงกันอีกครั้ง ไม่พบ flutter:E/AndroidRuntime:E ของ PID ใหม่
  ดู `persistence.json`, `persistence.log`, `r8-relaunch-errors.log`
- ภาพ/XML/JSON: `build/verification/motivation-ui-20260908/device/manual-ui/r8-*`
  ตรวจภาพหน้าชุด C2 แล้ว ภาษาไทยและรายการแสดงได้ ไม่พบส่วนล้นจากภาพที่ตรวจ
- จบที่หน้า launcher รุ่นทดสอบ ไม่มีงานไมค์/เสียง/กล้องเปิดค้าง

## รุ่นและแฮช

APK ใน `build/verification/motivation-ui-20260908/device/`

| APK | SHA-256 | สถานะ |
| --- | --- | --- |
| lexiquest-learning-preview-manual-v17-thai-r8-debug.apk | `60a9f5546809345644e85d261a37a57c60893f0c3ad12d75f573c821949faa0d` | ติดตั้งและตรวจบน vivo |
| lexiquest-learning-preview-v22-thai-r8-debug.apk | `3502a36aacb0c23933d64b74bda0fa3dd768b90416a231a3a6ee041816375758` | สร้าง ordinary preview ไม่ติดตั้ง |

Build ทั้งสองผ่าน source-stability gate:
whole-source `a19d8ed4d63a25ff71c1ae96f6a85bbdae84a8a7a22266759ac76c8579b12a42`
runtime gate `291aa049e5c1ea43106e80727cfa4a96b32fbfd5c44226ecc05a6b16fe4980f0`
หลัง build อัปเดตเฉพาะ checklist แผนและเพิ่มรายงานนี้ ไม่แก้ runtime/assets/tests
ยังเป็น debug preview ปิด cloud sync ไม่ใช่ production/research rollout

Source/asset pins:

- Octanove CSV: `18c33a407f2f89f7b8de9671c6d45fe3ea0bce45e7d2d7dcaab48d73e0f7b380`
- legacy catalog: `b1af6f5c444650d39d6873bf7db7632585b2220b69bce323327693c021641140`
- core extension: `da83baf5ecfb8b64a486da6e784c7ca3d5ae373e18e7fccc02d09179cf7bf6bf`
- advanced profile: `694a96a5cd413aa41c8547691d54eabed8f8746ca08dcf970e3dd288fc7ebe05`
- advanced translations: `3e25d52af96d5524ca786c07cc840772ee6862cb381e7b2cda96c16a1d116130`
- CEFR-J/LEXiTRON source pins ตามรายงาน R7 และ generator ที่ตรวจ SHA ก่อนใช้

## สถานะ workspace และงานต่อ

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
branch `codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2`
รักษาไฟล์แก้เดิมทั้งหมด ไม่มี commit/reset หรือแก้ guardrails

เพิ่ม `tools/build_expanded_cefr_catalog.py`, `tools/test_build_expanded_cefr_catalog.py`,
`assets/content/cefr_expanded/` 5 ไฟล์, `test/features/vocabulary/expanded_cefr_catalog_test.dart`
และแผน/รายงาน แก้ generator เดิมให้รับระดับ/ID prefix โดย default เดิมไม่เปลี่ยน,
catalog loader, importer namespace, หน้าคลัง/ทางเข้า, pubspec assets และ tests ที่เกี่ยวข้อง

ไม่มี build/test/transfer ค้าง งานถัดไปที่ทำได้คือคัด/เรียงความหมายพื้นฐาน A1/A2
และตรวจคำแปล/ประโยคตัวอย่างรายรายการ ส่วน query กิจกรรม CEFR เดิมที่ดู 100 คำแรก
ยังไม่แก้ในงานนี้ บทอ่านคง 6 บท และงานเสียงคนจริง/AI จริง/ซิงก์สองเครื่อง/กล้องจริง
ยังมีข้อพึ่งพาตาม checkpoint ก่อนหน้า ไม่เปลี่ยนเป็นสถานะผ่านจากงานขยายคลังนี้
