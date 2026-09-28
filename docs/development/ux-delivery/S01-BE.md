# S01-BE — อายุ callback เมื่อพักแอปหรือสลับหน้า

## ผลตรวจ

HOST_PASS74 รวมทดสอบใหม่ 8 กรณี. ยืนยัน RED บน source BD จำนวน 3 กรณี: callback ลบเดิมกลับมาทำงานหลังพัก/กลับ, หลัง route ถูกบัง/กลับ และทำงานขณะ inactive. รอบ RED มี fingerprint ก่อน/หลังตรงกัน; รอบแรกที่ test ใช้ await กับ API void เป็น compile error ไม่ใช่หลักฐาน RED และแก้ fixture ก่อนทดสอบใหม่.

หน้า offline เดิมติดตาม app lifecycle และ route visibility แล้ว retire load serial เมื่อเปลี่ยนช่วงการมองเห็น. กลับมาหน้าจะอ่าน catalog ใหม่; callback เก่าไม่กลับมามีสิทธิ์. คง manager generation และ busy/download/cancel state ของงานที่เริ่มแล้ว จึงยังยกเลิกผ่านปุ่มใหม่ได้. ไม่เปลี่ยน owner/scoring/SRS/reward/storage/schema/routes/deeplinks/gates หรือเปิด instructional Flutter.

ชุดตรวจครอบคลุม screen, Settings entry, offline manager; เพิ่ม remove/background/route return, download/repair, ongoing cancellation, retry failure และ pending catalog. ไม่อ้างว่าทดสอบครบทุกคู่ของ action/lifecycle หรือทุกพฤติกรรมบนอุปกรณ์.

## หลักฐานและข้อจำกัด

- [Validation](evidence/S01-BE-validation.json), [checkpoint](evidence/S01-BE-checkpoint.json), [claim](evidence/S01-BE-claim.json).
- verify-scope Targeted/Learning ผ่าน 74 tests; fingerprint `63f7435a2042ebf0338dcfdc8ea4914ba6d1ed3da81a257fa559502066a943ab` ก่อน/หลังตรงกัน; ตรวจ input closure 1563 paths แล้ว.
- Dart analysis ไม่มี error/warning; info เดิม 3 จุด use_build_context_synchronously ที่ 141/175/181. มี Drift warning เดิมใน test stdout.
- Diff ตรวจด้วย cr-at-eol เพราะ source ใช้ CRLF เดิม; default diff --check นับ CR เป็น trailing whitespace. ไม่เปลี่ยน line endings ของ BD หรือ generated files เพื่อให้ผ่าน.
- Source patch เป็น cumulative BD+BE เทียบ HEAD เดิม; BD patch และหลักฐานเดิมเก็บครบ ไม่ใช่ BE-only patch. ไม่มี commit/push/archive/cleanup/provider/browser/deployment.

Writer `01a0dec5-b093-7f20-b0c0-f5318ab6ccba` คืนสิทธิ์แล้ว. Controller เป็นผู้เปิด fresh chat ต่อ. งานพร้อมตรวจถัดไป: feedback ของ offline operation ที่เริ่มก่อนพัก/บัง route แต่เสร็จหลังกลับ; catch paths ยังตรวจ manager generation/current route โดยไม่มี visibility token. เป็นสมมติฐานจาก source ยังไม่ได้ reproduce จึงไม่อ้าง defect/RED.

S01 ยัง IN_PROGRESS; UX-D01–25 OPEN. Native/device/visual/keyboard/screen-reader/user/media-review/trial/release pending. ใช้ current-model deterministic fallback; ไม่อ้าง Jev selection หรือ runtime tier verification. เก็บ old worktrees และ backup เดิม ไม่รอ cleanup.
