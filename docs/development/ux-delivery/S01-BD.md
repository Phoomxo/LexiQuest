# S01-BD — อายุปุ่มตามสถานะเนื้อหาออฟไลน์

## ผลตรวจรับ

**HOST_PASS66** รวมทดสอบใหม่ 6 กรณี; 4 กรณี RED บนโค้ดเดิมยืนยันการเรียก remove/download/repair/cancel ซ้ำจากปุ่มเก่า. ปุ่มลบเก่าสามารถลบไฟล์ที่เพิ่งดาวน์โหลดกลับมาได้ เพราะตรวจเพียง manager generation แต่ไม่ตรวจรอบการอ่าน catalog.

แก้เฉพาะหน้า offline เดิมให้ปุ่มผูกกับ load serial และปฏิเสธคำสั่งระหว่างอ่านสถานะใหม่. ปุ่มใหม่ยังทำงาน รวมการยกเลิกงานเดิมหลังรายการอื่นเปลี่ยน และ explicit retry เมื่ออ่านสถานะล้มเหลว. ไม่เปลี่ยน authority ของ manager, owner, scoring, SRS, rewards, schema, routes, deeplinks หรือ gates.

## หลักฐาน

- [Validation และ SHA256](evidence/S01-BD-validation.json): exact command, 66 tests, pre/post fingerprint ตรงกัน, raw stdout/stderr และ source pins.
- [Delta ของ source/test](evidence/S01-BD-source.patch) บน HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1`.
- Dart analysis: exit 0, ไม่มี error/warning; มี info เดิม 3 จุด `use_build_context_synchronously`. Guard เดิมตรวจ mounted ผ่าน `_canAct` → `_current`; ไม่ suppress.
- Bounded suite มี Drift warning เดิม 1 รายการ. ไม่อ้างผลไม่มี warnings.
- รอบแรก InputDrift จาก dependency bootstrap; รอบ RED ที่ใช้ยืนยันมี fingerprint คงที่. Expanded test พบ fixture `_replace` ลืม identity ของไฟล์ที่สอง; แก้ fixture และเพิ่ม assertion รักษาทั้งสอง identity แล้วผ่าน focused และ final suite.
- Self-review เท่านั้น; ไม่มี subagent หรือ gate หนักคู่ขนาน. PASS เดิมของ BC เป็นประวัติ ไม่บวกกับ 66 หรืออ้างว่าเพิ่งรันใหม่.

## ขอบเขตและการส่งคืน

Worktree `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`, branch `codex/ux-current-after-s01-bc`, writer `01a0deb6-099b-7010-a49b-3ff84a2c62e1` จาก environment. Routing ใช้ current-model fallback; model/effort/tier จริงไม่เปิดเผย จึงไม่อ้าง Jev selection หรือ runtime tier verification.

เก็บเฉพาะ delta และหลักฐานใหม่; backup เดิมและ worktree เก่าไม่ถูกแตะ. Flutter generator ทำ platform files 7 ไฟล์ต่างเฉพาะ line ending โดย semantic diff ว่าง; เก็บสภาพไว้ ไม่ reset/clean. ไม่มี commit/push, ZIP หรือ successor ใหม่.

S01 ยัง IN_PROGRESS; UX-D01–25 OPEN. Native/device/visual/keyboard/screen-reader/user/trial/release ยัง pending. ไม่ทดสอบ browser/provider จริงหรือเปิด instructional Flutter. งานนี้เลือก UX12 แบบจำกัด ไม่ได้สรุปว่า backlog ทั้งหมดไม่มีงานพร้อม. Controller ตรวจ package ถัดไปจาก source ปัจจุบันได้โดยไม่รอ cleanup; [checkpoint](evidence/S01-BD-checkpoint.json) ระบุ writer release และขั้นถัดไป.
