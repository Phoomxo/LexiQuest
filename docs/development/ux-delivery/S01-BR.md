# S01-BR — actual preview composition and Today routes

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`; branch `codex/ux-current-after-s01-bc`; HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1`.
Writer `01a0e51a-4359-7893-b240-ba050ac5efe6`; controller `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผลและขอบเขต

**HOST SYNTHETIC — real AppBootstrap composition.** BO/BQ ไม่ได้พิสูจน์ว่า preview จริงขาด dependency: `composeHost` ของ BO เติม Today แต่ไม่มี reviewCenter/learningHistory และใช้ fieldDefaults ที่ซ่อน dailyContinuity. BR ใช้ `AppBootstrap.initialize` จริงกับ SQLite in-memory และ temporary support directory แยก ผ่าน dependency predicate เดิมทั้ง field และ preview โดยไม่แก้ production source หรือ gate.

`app_bootstrap.dart` ประกอบ Today, review และ history; review ใช้ activeOwnerIdentities instance เดียวกัน และ review/history ใช้ learning session authority เดียวกันตาม `AppDependencies.hasComposedDependencyFor`. `LearningPreviewFeatureRegistry` เปิดเฉพาะ dailyContinuity ที่ hidden เมื่อเลือก preview; RuntimeFeatureRegistry ยัง emergency-off ได้. ค่า fieldDefaults ไม่เปลี่ยน.

| การตรวจ | ผล / ความหมาย |
| --- | --- |
| Field bootstrap | composition ครบ แต่ feature hidden; Today unavailable → ฝึก ใช้ได้ |
| Preview Today tab → review → Back | route `home/today/review`; โหลด empty queue สำเร็จ |
| Preview Today tab → history → Back | route `home/today/history`; ไม่แสดง loading/error หลัง settle |
| Preview Today → ordinary quiz resume | ไปแท็บฝึก index 1 ตาม implementation ปัจจุบัน; session ID/owner/ข้อมูลเดิมคงอยู่ |
| Emergency-off | Today ปิดและ fallback ไปฝึกได้ โดยไม่แก้ build registry |
| Isolation | seed เปลี่ยนเฉพาะ learning_sessions; navigation ไม่เปลี่ยนทั้ง 58 ตาราง; HTTP operations 0; guest login ถูกปฏิเสธใน harness |

**Resume ไม่ใช่ quiz rehydration:** `_resumeFromToday` ตรวจ owner แล้วเรียก `_selectLearningFromToday` สำหรับกิจกรรมทั่วไป. BR พิสูจน์เส้นทางนี้เท่านั้น ไม่อ้างเปิดคำถาม/คำตอบเดิมหรือจบบทเรียน. Dialogue/mixed-review มีเส้นทางเฉพาะแต่ไม่อยู่ใน matrix นี้. ไม่พบ defect ที่จำเป็นต้องแก้ production จากขอบเขตที่รัน.

## Verification

เพิ่ม `test/support/today_preview_route_audit_test.dart` เพียงไฟล์เดียว. ใช้ AppBootstrap พร้อม `learningPreviewEnabled=false/true` เฉพาะ test, `cloudSyncEnabled=false`, Firebase/Supabase initializer แบบ no-op, mock preferences/path provider, HTTP client จำลองที่ปฏิเสธทุก operation และ no-login service. ไม่มีการเรียก production initializer/provider หรือฐานผู้ใช้จริง.

Seed active legacy-compatible quiz `synthetic-br-resume` ผ่านข้อมูลทดสอบลงฐานแยก; Today ใช้ canonical reader จริง ไม่ส่ง fake snapshot/delegate. ไม่สร้างคะแนน/SRS/rewards/research/outbox เพิ่ม. ตรวจทุกแถวทุกตารางก่อนและหลัง UI; bootstrap initialization rows อยู่ก่อน baseline comparison.

Final verification ใช้ `verify-scope.ps1 -Level Targeted -Area Runtime` เท่านั้น:

- BR actual bootstrap routes: 2 tests.
- `S01-AA owner drift during Today load rejects the late snapshot`: 1 test.
- `S01-AA legacy secondary index`: 3 tests (2, 3, 99).
- `Today is a named secondary route and resume closes only that route`: 1 test.
- Analyzer เฉพาะ harness ใหม่; focused diff/whitespace และ source/preservation hash checks.

Exact results, stdout/stderr, source closure 1,578 entries, artifact hashes และ gate pre/post อยู่ใน `evidence/S01-BR-validation.json` และ `evidence/S01-BR-runs/`. Final fingerprint: `e59d975a2148f83891cdb31ab0230b25c32c26d009895a38e4c13bca1c3c3abe`. ไม่ reuse ผลจาก BO/BQ หรือ fingerprint เก่า; ผลก่อนเพิ่ม loaded-state assertions เก็บแยก ไม่ใช่ final gate.

Recovery: initial harness รอ filesystem IO นอก runAsync จึงหยุดเฉพาะ process ที่เริ่มเองและย้าย IO เข้า runAsync. รอบต่อมา BaselineNoNetwork ปฏิเสธการสร้าง client ที่ bootstrap เตรียมไว้ (stack: AppBootstrap._compose → http.Client), ไม่ใช่ network request. เปลี่ยนเป็น inert client ที่สร้างได้แต่ปฏิเสธ/นับทุก operation; final operations=0. เก็บ initial interrupted stdout และ failed-run logs ไว้; ไม่จัดเป็น PASS. ไม่มี production fix และไม่ลด gate/owner assertions.

## ขอบเขตที่ยังไม่ผ่านการตรวจ

- Field Today routed success: NOT_RUN_FIELD_GATE ตามค่า production เดิม.
- เปิดบทเรียนเดิมแบบ exact quiz rehydration/answer continuation: NOT_RUN; ต้องระบุ acceptance ว่าต้องการพาไปฝึกหรือ restore session และมี bounded canonical-session test จึงจะอ้างได้.
- Review session start/answer/completion, history replay, dialogue/mixed-review และ route ทุกกิจกรรม: NOT_RUN ใน BR.
- Native visual/IME/TalkBack, screenshots และ end-to-end device acceptance: NOT_RUN. BR ไม่มี visual-render claim.
- Actual-user participation/trials: DEFERRED. S01/UX-D01–25 ยัง OPEN; ไม่มี release acceptance.

## Release / controller review

รักษา pre-existing 5,075 file pins ยกเว้น README/state/backlog ที่อัปเดตตามงานนี้; dirty BD–BQ/generated7 คงเดิม. ไม่ deploy, enroll/upload, install, cleanup, native UI/adb/browser/helper หรือ external contact. Current-model deterministic fallback; Standard/default requested, effective service tier unverified; ไม่มี Jev/billing/quota/login/ledger probe.

หยุดเขียน source หลัง verification; immutable writer-release receipt คือ `evidence/S01-BR-checkpoint.json` (ไม่ใช่ production-release approval). Controller ตรวจ receipt/source/gate แล้วตัดสินขอบเขตถัดไป; BR ไม่เลือกหรือสร้าง successor.
