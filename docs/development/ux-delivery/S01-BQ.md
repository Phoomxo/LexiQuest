# S01-BQ — populated Profile host audit

Worktree: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest` · branch `codex/ux-current-after-s01-bc` · HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1`.
Writer: `01a0e0f5-20cf-7781-b9d3-4d80d71c6329`; controller: `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผลและขอบเขต

**HOST SYNTHETIC:** ปิดช่องว่าง BO/BP เฉพาะ Profile ที่มีข้อมูลการเรียน → รายละเอียด → ภาพรวม → Back. Host audit 1×/2× ผ่าน; ตรวจภาพจริงครบ 20 ภาพด้วย `view_image` ที่ 360×800, DPR1, NotoSansThai/MaterialIcons และเงาจริง ไม่พบ layout defect ในกรณีนี้ จึงไม่มี production source change.

เพิ่มเพียง `test/support/populated_profile_host_ui_audit_test.dart` โดยอ่าน profile/overview tests และ canonical readers ก่อนเลือก fixture ใช้ `composeHost` เดิม; ไม่เปลี่ยน runtime flags หรือคำนวณคะแนนอีกชุด.

| ตรวจ | หลักฐานและขอบเขต |
| --- | --- |
| Populated Profile | ไม่มี empty-profile message; mastery 0 มีหลักฐาน, SRS แสดง “ยังไม่มีหลักฐาน” |
| Details | 50% จากคำตอบแรก 2 ครั้ง, 1 คำที่ควรทบทวน, 0 XP/0 วัน; semantics value ตรงข้อความ |
| เวลา | 79 active seconds แสดง 1 นาที 19 วินาที แม้ช่วงเวลาครอบคลุม 10 นาที |
| Overview | canonical weekly summary 1/2; หกแกนแยกกัน, sample size 2, ข้อความไม่อ้าง proficiency หรือ before/after ที่ไม่มีข้อมูล |
| Navigation/focus | กดแท็บฉันจริง; Tab/Enter เปิด details, overview และ Back; กลับ Profile ได้ |
| Layout/accessibility | เลื่อนถึงท้าย overview; androidTapTargetGuideline/labeledTapTargetGuideline ผ่านทุก capture; ไม่มี layout exception |
| Isolation | seed เปลี่ยนเฉพาะ 3 ตาราง; UI/reader ไม่เปลี่ยนทั้ง 58 ตาราง; HTTP/gateway=0 |

## Fixture isolation

ฐาน SQLite แยกใต้ temp directory ชื่อ `bq-host-synthetic-*`, run `bm-bq-host`; ไม่เปิดฐานผู้ใช้จริง. Seed แบบ test-only ลง `learning_sessions` 2 แถว, `answer_attempts` 2 แถว (ถูก/ผิดอย่างละหนึ่ง), `learning_time_segments` 1 แถว. ใช้ EvidenceContext แบบ legacy compatibility ที่ production reader รองรับ เช่นเดียวกับ unit tests เดิม; `engagementAllowed=false`. ข้อมูลเหล่านี้เป็นอินพุตทดสอบเท่านั้น ไม่ใช่ผลจากผู้เรียนหรือการทำกิจกรรมจริง.

ไม่ seed SRS/rewards/points/research/consent/assessment หรือ outbox ของการเรียน. เปรียบเทียบทุกตารางก่อน/หลัง seed เพื่อยืนยันว่ามีเพียงสามตารางเปลี่ยน และทุกตารางก่อน/หลัง UI เท่ากัน. Ordinary vocabulary outbox ของ baseline fixture คงเดิม ไม่มีส่งออก. Read models เดิมเป็นผู้คำนวณ 50%, weakness และเวลา; test ไม่เขียนผลคำนวณลง projection.

## Verification และ recovery

- `verify-final.log`: 2 host tests PASS, source pre/post fingerprint `1364cf977f9e3d5ecc4ee5c49785248bf8811bf3e28640e51d3e271478a0a2d0`.
- Regression selections: canonical six-axis reader, overview six axes, Profile details/axes. ผลและ command logs ที่ตรวจแล้วเก็บใน validation/checkpoint.
- `analysis.log`: analyzer เฉพาะ harness ใหม่ — no issues.
- ภาพ: `01-profile`, `02-effort`, `03-accuracy`, `04-details`, `05-overview` ทั้งสองขนาด; `06-overview-0..2` ที่ 1× และ `06-overview-0..6` ที่ 2×. ทุกภาพ final ตรวจด้วย `view_image`.
- เก็บ initial 2× PASS ไว้; รอบ final เพิ่ม semantics assertion และเลื่อนตรวจจนสุด ไม่ใช้ initial แทน final.
- Regression invocation แรกส่ง regex ให้ TestName ซึ่งเป็น plain-name selector จึง “No tests ran”. แก้เป็นชื่อจริงและรันสาม selection ตามลำดับ; เก็บ failure log ไว้ ไม่คิดเป็น PASS. การอ่าน isolation ก่อนสร้างเสร็จเคยพบ missing path; รอผล test แล้วอ่านไฟล์จริง ไม่สร้างผลแทน.
- ได้รับ filesystem escalation สำหรับ worktree ที่อยู่นอก writable roots. ไม่ใช้ native UI, adb, browser, VM หรือ helper เพื่อข้ามข้อจำกัด.

## Checklist ที่เหลือแบบจำกัด

1. **Populated-learning Profile/details/overview host:** ปิดเฉพาะ representative synthetic fixture นี้; ไม่อ้างทุกชุดข้อมูลหรือทุกฟีเจอร์.
2. **Today routed success/resume:** NOT_RUN_GATED. Feature/composition gate คงปิด; BO component result คงความหมายเดิม. ไม่เป็นเหตุให้เปิด gate ใน BQ.
3. **Native IME/TalkBack/visual acceptance ของ snapshot ปัจจุบัน:** NOT_RUN; host key events/semantics ไม่ทดแทน. BM เป็นหลักฐาน snapshot เก่า.
4. **Actual-user participation/trials:** DEFERRED ตามผู้ใช้. S01 และ UX-D01–25 ยังเปิด.
5. **Instructional expansion, live provider, release:** ยังต้อง reviewed media/rights/rubrics, qualified trial results, device/provider/budget evidence หรือ frozen release SHA ตามแต่ละงาน.

จาก inventory BO/BP และ source ที่เกี่ยวข้อง ไม่พบข้อบกพร่องใหม่ซึ่งต้องสร้าง successor package. ไม่ขยาย owner/recovery matrices หรือสร้าง success variants ต่อเนื่องเพื่อให้มีงาน. Controller ใช้ checklist นี้ตัดสินงานถัดไป; ไม่มี successor dispatch จาก BQ.

## Handoff

Validation/checkpoint เก็บ hashes, current source closure, exact gates และสถานะ writer release. รักษา dirty BD–BP/generated7/หลักฐานเดิม. ไม่มี production edit, native/package change, cleanup, ZIP, worktree ใหม่, subagent, deployment หรือ research activation.

Current-model deterministic fallback; Standard/default requested, runtime tier unverified. ไม่มี Jev inference, billing/login/quota probe หรือ USD5 ledger change. Host engineering acceptance แยกจาก native/user/trial/release acceptance เสมอ.
