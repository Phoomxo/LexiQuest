# Minimal UI Comparison Implementation Plan

**Goal:** สำรอง Prototype 2 แล้วพัฒนา Prototype 3 minimal เพื่อเทียบภาพจาก Flutter จริงโดยไม่เปลี่ยนพฤติกรรมการเรียน

**Architecture:** คง routes, feature gates, data authorities และข้อมูลเดิม เปลี่ยน presentation ในธีมกลาง หน้าเลือกกิจกรรม เมนู และ glossary เท่านั้น ใช้สาขาแยกจาก snapshot เดียวกัน

**Tech Stack:** Flutter, widget tests, renderer captures, Git/GitHub

## สามสายงาน

| รุ่น | สาขา GitHub | จุดเริ่มต้น |
| --- | --- | --- |
| Prototype 1 ปี 2024 | baseline/2024-10 | 4837d8112169efc82f541a23649d4afc643436ab (2024-10-15) |
| Prototype 2 ก่อน minimal | prototype-2 | ccf29d670f48c3536c630cfff8935ba9c2c6c08d |
| Prototype 3 minimal | prototype-3-minimal-ui | เริ่มจาก ccf29d67 แล้วรับงาน UI รอบนี้ |

สำรองถาวร: branch `backup/2026-09-12-r14-pre-minimal-ui` และ annotated tag `backup-2026-09-12-r14-pre-minimal-ui` ชี้ ccf29d67 ห้ามใช้เป็นปลายทางงานต่อ ไม่ force-push หรือ merge ข้ามสามสายโดยอัตโนมัติ การอัปงานรอบนี้ใช้ explicit ref ของ Prototype 3 เท่านั้น Upstream ของ worktree นี้ตั้งเป็น Prototype 3 และ push.default=simple

ผู้ใช้ห้ามใช้คำนำหน้าชื่อสาขาว่า codex โดยเด็ดขาด ได้เปลี่ยนชื่อสาขาที่สร้างในรอบนี้ทั้ง local/remote และตรวจ SHA ตรงกันก่อนลบชื่อ remote เก่า เอกสารภายใน backup ที่ระบุชื่อเก่าเป็นประวัติก่อนการเปลี่ยนชื่อ ไม่แก้ commit backup ย้อนหลัง ตารางนี้เป็นชื่อที่ใช้งานจริงล่าสุด

สาขา Git แยกประวัติการพัฒนา ยังไม่ได้เปลี่ยน Android applicationId ให้ติดตั้งสามแอปพร้อมกัน ไม่มีการตั้ง GitHub branch protection ในรอบนี้ จึงเป็นกติกาการทำงาน ไม่ใช่การอ้างว่าฝั่งเซิร์ฟเวอร์ล็อกการเขียนแล้ว

## ลำดับงาน

- [x] สำรองงานเดิมรวม 591 ไฟล์ที่เปลี่ยนจาก HEAD, ตรวจ Gitleaks staged/history และยืนยัน remote SHA ของ backup
- [x] ตั้งสามสาขาและ upstream ของ Prototype 3 โดยเก็บ Prototype 1/2 และ backup เดิม
- [x] เก็บภาพก่อนแก้ด้วย fixture/ขนาดเดียวกัน (390 ปกติและ 320 text200)
- [x] ปรับ `lib/config/m3_theme.dart`: หัวหน้าชิดซ้ายร่วมกัน ลดน้ำหนักเส้นกรอบ คงปุ่ม/ช่องกรอกเดิม
- [x] ปรับ `lib/screens/choose_mode_screen.dart`: ลดหัวข้อซ้ำ ใช้กริดสองคอลัมน์ที่รูปและชื่ออยู่กลาง; จอแคบ/ข้อความใหญ่ใช้หนึ่งคอลัมน์และสูงตามเนื้อหา โดยคง callback/key/semantics เดิม
- [x] ปรับ `lib/screens/main_navigation_screen.dart`: ลดหัว drawer ขนาดใหญ่โดยคงทุกเมนูและสถานะระบบที่จำเป็น
- [x] ปรับ glossary และ snapshot expectations ของชื่อเมนูตามผู้ใช้ (ผู้ช่วยรับผิดชอบแยกไฟล์)
- [x] ตรวจ focused widget/navigation tests 146 ผ่าน, analysis 12 ไฟล์ไม่พบปัญหา แล้วถ่ายและเปิดภาพหลังแก้ที่เงื่อนไขเดียวกัน
- [ ] สรุปข้อดี/ข้อเสียจากภาพจริง แยกจาก human usability; commit/push เฉพาะ Prototype 3 และยืนยัน SHA รุ่น 1/2/backup ไม่เปลี่ยน

ไม่สร้างหลักสูตร/ข้อมูล progress สมมติในแอป ไม่เปลี่ยนโมเดลกล้อง/บริการ AI/ระบบ sync และไม่อ้างว่าการทดสอบภาพเป็นผลบน vivo หรือ human TalkBack

## แนวทางผสมและขอบเขตถัดไป

ผู้ใช้ยืนยันให้ผสม ALLTCAS กับ Duolingo อย่างยืดหยุ่น โดยรักษาโครงสร้างที่ดีไว้ ผลเปรียบเทียบและลำดับ feedback สำหรับ Matching อยู่ใน `docs/development/2026-09-12-prototype3-ui-comparison.md` รอบนี้ลงโค้ด layout/glossary ก่อน ส่วน Matching และหน้าภายในที่ override theme ยังไม่ถือว่าทำเสร็จ
