# UI/accessibility follow-up audit — 2026-09-12

ผู้ตรวจ editorial_two · worktree C:/Users/Phet/.codex/worktrees/02fa/LexiQuest · branch codex/pair-matching-pm0-pm8.
อ่าน AGENTS.md และ 2026-09-12-cefr-complete-r12-checkpoint.md ก่อนตรวจ ใช้ R12 เป็นหลักฐานภาพรุ่นเดิม ไม่อ้างว่าภาพนั้นพิสูจน์ทุกสถานะหรือ text scale อื่น

ช่วงแรกเป็น read-only audit; ต่อมา root อนุมัติแก้ VocabList, SRS, legacy Matching และเทสต์ที่เกี่ยวข้อง ผู้ตรวจไม่รัน ADB, Flutter, analyze หรือ build. Root เป็นผู้ถืออุปกรณ์และผู้รวมการแก้ไข

## ข้อเสนอซ่อมที่มีหลักฐาน

### P2 — ข้อความค้นหาไม่พบระบุว่าหมวดคำศัพท์ว่างผิดจากข้อมูล

ไฟล์: lib/screens/vocab_list_screen.dart:78–96 (การกรอง words และ words.isEmpty).

เมื่อหมวดมีคำอยู่ แต่พิมพ์คำค้นที่ไม่ตรงกับ spelling/meaning โค้ดกรองเหลือศูนย์ แล้วแสดง “ยังไม่มีคำศัพท์ในหมวดนี้” เหมือนหมวดว่างจริง ผู้เรียนจึงไม่ได้รับสถานะของการค้นหาที่ถูกต้อง เป็นผลที่ระบุได้จาก branch จริง ไม่ได้อ้างว่าจำลองการแตะบนเครื่องแล้ว

ซ่อมเฉพาะข้อความ: ถ้า snapshot มีคำแต่ผลค้นไม่มี ให้แสดง “ไม่พบคำศัพท์ที่ตรงกับคำค้น”; คงข้อความหมวดว่างเมื่อไม่มีข้อมูลจริง ไม่เปลี่ยน query/import/repository

เทสต์ที่มีความหมาย: เพิ่มใน test/screens/offline_vocabulary_journey_test.dart หรือ focused VocabList test: สร้างหมวดมี 2 คำ → ค้นไม่ตรง → พบข้อความ no-results และไม่พบ empty-category → ล้างค้นแล้ว 2 คำกลับมา; อีกกรณีหมวดว่างจริงยังแสดงข้อความเดิม

### P3 — ปุ่มลอยซ้อนพื้นที่ปุ่มรายการในคลังส่วนตัว

หลักฐานภาพ: build/verification/motivation-ui-20260908/device/manual-ui/r12-personal-words-20260912.png.
ไอคอนนำเข้าที่ลอยด้านขวาทับไอคอนลบของแถว station; ปุ่มเพิ่มขนาดใหญ่กินพื้นที่ด้านขวาของแถวล่าง ภาพเห็นการซ้อนจริง ไม่ได้พิสูจน์ว่าเลื่อนแล้วเข้าถึงปุ่มนั้นไม่ได้

ไฟล์: lib/screens/vocab_list_screen.dart:98 (bottom padding 96), 108–136 (trailing actions), 148–183 (FAB column).
ซ่อมแบบจำกัด: พิจารณาวาง action เพิ่ม/นำเข้าใน footer ที่ reserve layout space (SafeArea + Wrap) เพื่อให้ viewport ของรายการไม่อยู่ใต้ปุ่มเหล่านั้น; ไม่เพิ่มช่องทาง mutation หรือเปลี่ยนคำยืนยันลบ การเพิ่ม bottom padding อย่างเดียวช่วยแถวสุดท้ายแต่ไม่กำจัดการทับรายการที่เลื่อนผ่านพื้นที่ FAB

ผลตัดสินหลัง audit: root เลือกคง FAB และเพิ่ม scroll padding ให้พอสำหรับปุ่มสองชั้น จึงจะตรวจการเข้าถึง action แถวสุดท้ายที่เลื่อนพ้นปุ่ม ไม่ใช้เงื่อนไข rectangle ของทุกแถวห้ามทับ FAB เป็น acceptance ของแนวทางที่เลือก

เทสต์ที่มีความหมาย: viewport 360×800 และ 320×568, 200% text, มี importer และรายการหลายแถว; scroll ถึงท้ายแล้วปุ่ม example/delete ของแถวสุดท้าย hitTestable และแตะได้ถูก action; rectangle ของรายการที่อยู่ใน viewport ไม่ซ้อน footer; ปุ่มเพิ่ม/นำเข้ายังแตะได้ ไม่มี overflow. ถ้า root เลือกคง FAB ตามรูปแบบเดิม ให้บันทึกเป็น visual tradeoff ไม่อ้างแก้การทับแล้ว

### P3 — accessibility labels บางส่วนยังเป็นอังกฤษบน flow ภาษาไทย

ไฟล์:
- lib/screens/srs_flashcards_screen.dart:609–614: “Reveal answer for …” / “Answer for …”.
- lib/features/learning/presentation/legacy_matching_mode_screen.dart:297–303: “… of … pairs matched”.

คำสั่ง/ความคืบหน้าควรเป็นภาษาเดียวกับ UI ไทย โดยคง headword ภาษาอังกฤษตามบทเรียน เช่น “เปิดคำแปลของ …”, “คำแปลของ …”, “จับคู่แล้ว … จาก … คู่”. PairBoardView รุ่นใหม่มี PairMatchingCopy แยก locale อยู่แล้ว ไม่ต้องแก้ส่วนนี้เพิ่ม

เทสต์ที่เกี่ยวข้อง: test/screens/srs_flashcards_screen_test.dart:683 เป็นต้นไปยังคาด English label; test/screens/matching_mode_screen_test.dart:80 เป็นต้นไปยังคาด “0 of 3 pairs matched”. แก้ assertions ให้ตรง localized labels พร้อมคง enabled/onTap/selected และลำดับ prompt→response→feedback เดิม; อย่าเพิ่มการอ่านคำตอบก่อนพลิกหรือก่อนจับคู่

เป็นข้อพบจาก semantics source ไม่ใช่ผลฟัง TalkBack. การได้ยินคำออกเสียงจริงและการเลื่อน focus บนอุปกรณ์ยังต้องตรวจโดยผู้ถือเครื่อง

## ส่วนที่ตรวจแล้วแต่ไม่มีเหตุผลให้ redesign

ภาพที่เปิดอ่านจริงเพิ่มเติม:
- r12-catalog-20260912.png
- r12-detail-about-20260912.png
- r12-detail-about-bottom-20260912.png
- r12-about-alternatives-20260912.png
- r12-personal-about-example-20260912.png
- r12-personal-categories-20260912.png
- r12-library-bottom-20260912.png
- r12-reading-a1-contrast-20260912.png

CEFR detail/example มีการแบ่งความหมาย อังกฤษ ไทย และ disclaimer อ่านชัดในภาพ dark theme ที่ตรวจ หัวเรื่องบทอ่าน R12 ไม่ใช่สีน้ำเงินเข้มบนพื้นดำแล้ว ไม่เสนอเปลี่ยนสีซ้ำ ภาพเมื่อลากรายการไปใต้ AppBar ไม่ถือเป็น text truncation defect โดยตัวมันเอง

อ่านโค้ด/เทสต์ต่อไปนี้ในส่วน layout/semantics:
- CEFR catalog/detail และ test/screens/cefr_editorial_screen_test.dart (narrow/200% text)
- personal vocabulary และ offline_vocabulary_journey_test.dart
- Quiz: SafeArea + SingleChildScrollView, answer options มี minimum height ไม่ล็อกความสูง, feedback อยู่หลังตอบ
- SRS: outer scroll และ inner card scroll รองรับเนื้อหายาว, narrow/200% control test มีอยู่
- Today: TodayHubView ใช้รายการเลื่อน, heading semantics, flexible status rows
- FocusTimer: header เปลี่ยนเป็นแนวตั้งเมื่อแคบ/ตัวอักษรใหญ่, ปุ่ม Wrap; test ที่ 240px/200% แตะ start จริง
- legacy Matching: ปุ่มเต็มความกว้างและ scroll, narrow/200% semantics/order test
- PairBoardView: responsive/focused traversal, explicit labels และ ExcludeSemantics สำหรับ tile; ไม่พบข้อผิดเฉพาะใหม่จากส่วนที่อ่าน

ไม่มี R12 screenshots ของ Quiz/SRS/Today/FocusTimer/Matching ในชุดภาพที่พบ จึงไม่อ้าง physical visual acceptance ของหน้าเหล่านั้นจาก R12. ผลเทสต์ใน checkpoint เป็นหลักฐานที่ root บันทึกไว้ ไม่ใช่การรันใหม่ของผู้ตรวจนี้

## ส่งต่อ

Root อนุมัติ (1) คลังส่วนตัว no-results + เพิ่มพื้นที่เลื่อนท้ายรายการโดยคง FAB, (2) labels ของ SRS/legacy Matching แยก th/en, (3) device/large-text verification หลังรวมโดย root. ไม่เปลี่ยน canonical activity, admission, scoring, source identity หรือข้อมูลผู้ใช้เพื่อแก้ UI

## การดำเนินการหลังอนุมัติ

เพิ่มเทสต์ค้นหาไม่พบด้วยข้อมูลจริงสองคำ และตรวจว่าล้างการค้นหาแล้วคำเดิมกลับมา Root รันครั้งแรกพบ fixture timeout ก่อน assertion: การ seed Drift ใน fake async ไม่เดิน จึงแก้ fixture ครอบ tester.runAsync ไม่เพิ่ม timeout และรอรัน RED ใหม่ก่อนแก้ runtime

ปรับ existing SRS narrow/200% test ให้มี th/en และตรวจทั้งก่อน/หลังพลิก พร้อมย้าย textScaler เข้า MaterialApp builder เพื่อใช้ scale จริง; existing Matching semantic traversal test ใช้ Thai locale ส่วนอีก existing assertion ยังตรวจ English branch. Root เป็นผู้รันตามลำดับ; ยังไม่บันทึก PASS จนได้รับผล

Root ยืนยัน RED ที่ถูกเหตุหลังแก้ fixture: search แสดงหมวดว่างแทนไม่ตรงคำค้น; SRS หา Thai reveal label ไม่พบ; Matching หา Thai progress label ไม่พบ; English SRS ผ่าน. การเรียก regex ด้วย plain-name รอบหนึ่งไม่พบเทสต์ จึงใช้ --name แล้วได้ RED จริง ไม่ถือ no-tests เป็นหลักฐาน

ลงแก้ runtime เฉพาะสามไฟล์ที่อนุมัติแล้ว: VocabList ใช้ข้อมูลก่อนกรองแยก empty/no-results และ bottom padding 160 เมื่อมีปุ่มสองชั้น, 96 เมื่อมีเพิ่มอย่างเดียว, 16 สำหรับ read-only; SRS และ legacy Matching เลือก Thai labels เมื่อ locale เป็น th พร้อมคง English branch. ไม่มีการเปลี่ยน handler, enabled หรือกิจกรรมการเรียน

ขยาย existing offline reconstruction journey ด้วย 20 แถวเพิ่ม ที่ 320×568/dark/200% text แล้วเลื่อนท้าย ตรวจขอบแถวสุดท้ายอยู่เหนือปุ่มนำเข้าและแตะลบ word19 เปิดคำยืนยันถูกคำ จากนั้นยกเลิกและตรวจคำยังอยู่; เพิ่ม assertion หมวดว่างจริงในช่วงเดิม. เป็นการตรวจ reachability ตามแนวทาง FAB ไม่ใช่การกำจัดการซ้อนขณะเลื่อนทุกแถว

ตรวจ diff --check เฉพาะหกไฟล์ Dart ผ่าน (exit 0; มีคำเตือน LF/CRLF เดิม ไม่มี whitespace error) แล้วหยุด runtime/test writes ให้ root format และรันสามไฟล์เทสต์บน snapshot เดียวกัน. ผู้ตรวจไม่ได้รัน Flutter/analyzer/build/ADB. ผล GREEN และ device verification ยังรอ root

รันรวมรอบแรกโดย root: 28 PASS / 1 timeout ใน expanded offline journey; search และ Thai/English semantics ผ่าน. เพิ่ม temporary stage logging แล้ว root รันเฉพาะ journey: cleanup ผ่าน, category resolved แล้วค้างระหว่าง createWord transactions ของ fixture 20 แถว ไม่ใช่ assertion ของ layout. แก้ fixture ให้ unmount/pump ยกเลิก live watches ก่อน seed และใช้ direct DB synthetic rows สำหรับส่วนทดสอบ layout (ตามอนุมัติ root); ยังรักษาการสร้างคำผ่าน UI จริงในช่วงเดิมและทุก layout/delete/cancel assertion. ลบ diagnostic prints แล้ว ไม่มีการเพิ่ม timeout. ยังรอ focused rerun ยืนยัน ไม่อ้างว่าเจาะจงสาเหตุภายใน Drift ได้มากกว่าจุด await ที่หลักฐานระบุ

## ผลตรวจสุดท้ายและ freeze

Root รัน focused journey หลังแก้ fixture: **1 PASS ในประมาณ 3 วินาที** ตาม build/verification/system-followup-20260912/ui-journey-green.log. รวมหลักฐานเป็น 28 รายการผ่านจากรอบสามไฟล์ก่อนหน้า และ focused journey 1 รายการผ่านหลังแก้ fixture ไม่เรียกว่า suite 29 PASS บนการรันเดียวกัน. Root จะรัน full regression บนชุดไฟล์ freeze ต่อ

ขอบเขตสุดท้าย: สาม runtime files (vocab_list_screen, srs_flashcards_screen, legacy_matching_mode_screen), สาม screen test files (offline_vocabulary_journey, srs_flashcards_screen, matching_mode_screen) และรายงานนี้. matching_mode_screen wrapper ไม่ได้แก้. Runtime/test writes หยุดแล้ว; ตรวจ scoped diff --check สุดท้ายไม่มี whitespace errors. Freeze รายงานหลังบันทึกนี้

การตรวจครั้งนี้ยืนยัน widget behavior และ semantics tree ตามเทสต์เท่านั้น การฟังและเดิน focus ด้วย TalkBack โดยมนุษย์ยัง pending; ไม่อ้าง physical-device acceptance ของการแก้ใหม่จากภาพ R12 เดิม
