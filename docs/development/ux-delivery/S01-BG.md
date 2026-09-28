# S01-BG — อ่านสถานะจริงหลังยกเลิกดาวน์โหลดจากงานภายนอกหน้าจอ

## ผลตรวจ

HOST_PASS94 รวมทดสอบใหม่ 8 กรณี. ยืนยัน RED บน source BF 3 กรณี: cancel คืน true/false/error แต่หน้าจอไม่แสดง repair/remove ตาม catalog จริง. Boundary controls 5 กรณีผ่านในรอบ RED: owner replacement, gate, app background, route cover และ dispose.

แก้เฉพาะ finally ของ _cancel: ล้าง cancelling แล้วโหลด catalog เมื่อ generation/owner/gate/visibility ยังอนุญาต. ไม่อนุมานสถานะจาก boolean หรือ error; canonical manager เป็นผู้กำหนดสถานะ. คง busy/download tracking และป้องกัน callback เก่าส่ง cancel ซ้ำ. หน้าที่ถูกบังโหลดใหม่เมื่อกลับมา. ไม่แก้ canonical semantics, scoring/SRS/rewards/schema/routes/deeplinks หรือ instructional Flutter.

## หลักฐาน

- [Validation](evidence/S01-BG-validation.json), [checkpoint](evidence/S01-BG-checkpoint.json), [claim](evidence/S01-BG-claim.json), [BG-only delta](evidence/S01-BG-source.patch).
- verify-scope Targeted/Learning: screen + Settings entry + manager ผ่าน 94 tests; fingerprint ก่อน/หลังตรงกัน และ input closure 1563 paths ตรงทั้งหมด.
- Analyzer exit 0: ไม่มี error/warning; info เดิม 3 จุด use_build_context_synchronously ที่ 145/182/188. Drift warning เดิมใน test output.
- ตรวจ diff ด้วย cr-at-eol ผ่าน; BG เพิ่ม 104 บรรทัดทดสอบและเปลี่ยน production 1 บรรทัดเป็น 8 บรรทัด. Baseline สองไฟล์เก็บก่อนแก้และ hash ตรง BF. รักษา BD+BE+BF และ generated files เดิม.
- Manual review ตามข้อกำหนดหนึ่ง writer; ไม่ใช้ subagents. Full release/native/device/user/trial ยังไม่รัน.
- สิทธิ์ปกติของ verifier ถูก sandbox ปฏิเสธการสร้าง log; รันด้วยสิทธิ์ escalated ที่ได้รับอนุมัติแล้วสำเร็จ. Analyzer ผ่าน path SDK จริงหลัง PATH/sandbox lookup ไม่สำเร็จ. ไม่หลบ approval หรือเปลี่ยน security settings.

## ส่งต่อ

คืน writer และพักตามคำสั่งผู้ใช้ล่าสุด: PAUSED_BY_USER. ไม่เริ่ม package ใหม่หรือสร้าง successor. เก็บ candidate ไว้เฉพาะเมื่อผู้ใช้สั่ง resume: ตรวจ recovery ของ catalog ที่เริ่มจาก cancel completion เมื่อ catalog ล้มเหลวหรือค้าง แล้ว owner เปลี่ยน; _load ใช้ generation/load serial และ retry เดิม แต่เส้นทางใหม่จาก _cancel ยังไม่มี dedicated fault-injection test. เป็น coverage candidate ไม่ใช่ defect/RED ที่ยืนยันแล้ว.

S01 ยัง IN_PROGRESS; UX-D01–25 OPEN. Native/device/visual/keyboard/screen-reader/user/reviewed-media/trial/release pending. Current-model deterministic fallback; Standard/default ตามคำขอ, runtime tier unverified, ไม่อ้าง Jev เลือก. ไม่มี provider/billing probe, deployment, research activation, cleanup, commit หรือ push.
