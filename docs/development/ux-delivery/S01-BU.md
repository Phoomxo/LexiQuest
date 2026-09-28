# S01-BU — frozen ordinary meaning admission

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`; branch `codex/ux-current-after-s01-bc`; HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1`.
Writer `01a0e574-5343-76d1-80c0-0819c996b2a0`; controller `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผลและขอบเขต

**BU initial admission engineering ผ่านใน HOST SYNTHETIC scope; BS-RESUME-01 ยังคง OPEN/RED.** ไม่ใช่ full resume, native/UAT หรือ release acceptance. ใช้ checkout เดิมเท่านั้น ไม่มี schema, scoring/SRS/reward authority หรือ feature-gate change.

- แยก pure `composeMeaningQuiz` จาก adapter เดิม; ordinary QuizScreen เรียก `startQuiz(ordinaryMeaning: true)` เพื่อ freeze ก่อน admission. ค่า default ของ shared `startQuiz` ยังเป็น generic เพื่อรักษากิจกรรม quiz-shaped อื่น; typed recall และ attached review ใช้พฤติกรรมเดิม.
- `OrdinaryMeaningPlan` version 1 เก็บ owner/session/configuration, ลำดับ prompt (word ID + label), direction, option IDs/labels, correct-answer ID, core revision/checksum ของคำถามและ distractors ที่ใช้จริง และ lexical artifact revision/checksum/evidence digest. Decode ตรวจ exact keys, unknown/version/type, duplicate IDs/options, label/answer/content binding, order และ 64 KiB UTF-8 budget; collections immutable.
- ใช้ `startExactPinnedSessionWithCheckpoint` transaction เดิม บันทึก session + checkpoint พร้อมตรวจ active owner/core pins และ lexical identity ซ้ำก่อน commit. Route expected checksums ถูกตรวจตั้งแต่ก่อน admission สำหรับ ordinary meaning; ตัวเลือกไม่พอไม่สร้าง session. ไม่มี migration.
- `PendingOrdinaryMeaningAdmission` ถือ command เดิม. เมื่อ acknowledgement หาย ต้องพบ exact accepted session ก่อน replay; ไม่มีการเลือกคำ/session ใหม่. Tests ตรวจ replay, conflict, rollback, content/metadata drift และ owner isolation.
- Initial QuizScreen/adapter ใช้ admitted questions โดยตรง ไม่โหลด distractors/lexical metadata มาเปลี่ยนโจทย์หลัง commit. Widget test อ่านลำดับปุ่มและข้อความจริงเทียบ durable checkpoint. Presentation ปฏิเสธแผนที่ผูกกับ owner/session อื่น.
- Real bootstrap เปิดเผย precision bug: clock มี microseconds แต่ durable time เป็น milliseconds. แก้ binding ให้เทียบ milliseconds และใช้ microsecond fixture ใน contract suite.

## หลักฐาน

ก่อนแก้ ตรวจ BT source closure 1,580 entries: mismatch 0; บันทึก Git-visible baseline ใน `evidence/S01-BU-runs/baseline.json`. รักษา immutable BD–BT evidence และ generated files; การแก้ BT/BS test sources เป็นการยกระดับ contract ให้ใช้ ordinary admission จริง ไม่แก้ historical evidence.

1. Reproduce BT เดิม: **9 PASS / 1 FAIL**, missing exact checkpoint; pre/post `799a128fe15fa3e3cb16fdd695779609bcc947bba39d99a1121f22ac363a3194`.
2. Final targeted **132 PASS**, exit 0: ordinary checkpoint contracts, QuizScreen, Learning use cases, contrastive feedback, session-configuration mode matrix. ครอบคลุม exact retry/ack loss, byte boundary, owner/content/artifact drift, immutable plan, actual rendered order, typed recall และ attached-review regressions.
3. Final analyzer: **No issues found**, exit 0, เฉพาะ 8 production + 3 touched test files. Input closure 1,582 entries ตรวจตรงทั้งก่อน/หลัง.
4. BS route ใช้ admission ใหม่ผ่าน actual AppBootstrap แล้ว: **0 PASS / 1 FAIL**, expected QuizScreen 1 / actual 0 หลัง Today resume. Checkpoint admission ผ่าน แต่ route/controller rehydration ยังไม่ทำ; ไม่ skip หรือเปลี่ยน expected result.
5. Final targeted, route RED และ analyzer ใช้ pre/post fingerprint เดียวกัน: `7005252282961944432e430ddcbbfa53ae5ff9d79bfcca4717095580e0fc9c03`. ผล Failed ไม่ถือเป็น PASS. ไม่มี reuse PASS ต่าง fingerprint.
6. Focused diff check ผ่านเมื่อระบุ `cr-at-eol` ตามไฟล์ CRLF เดิม; raw Git check รายงาน CR เป็น trailing whitespace. ไม่เปลี่ยน line endings หรือแก้ overlay อื่นเพื่อทำให้ check เงียบ.

รายละเอียด command/logs/pre-post อยู่ใน `evidence/S01-BU-runs/`; source/artifact pins และ preservation อยู่ใน `evidence/S01-BU-validation.json`. ตรวจ source diff ด้วยตนเองตามข้อห้าม subagents. ไม่รัน full release/build/native; ไม่มีผลทดสอบผู้ใช้จริง. การแก้ compile/fixture/style ระหว่างทางถูกตรวจสาเหตุและแก้ก่อน final gates.

## งานที่ยังเปิดและการปล่อย writer

BS-RESUME-01 ต้องเพิ่ม controller checkpoint state/restore สำหรับ draft, feedback, pending evidence/completion identity และ Today route ที่เปิด session เดิม; จากนั้นรัน end-to-end contract เดิมให้ผ่าน. BU เก็บ initial plan เท่านั้น ไม่อ้างว่า replay คำตอบหลัง process restart หรือ full exact resume สำเร็จ. ห้ามสร้าง fresh quiz แทน resume.

Field dailyContinuity คงเดิม, actual-user trials DEFERRED; no-login/no-AI baseline คงเดิม. ไม่มี native UI/adb/browser/helper, การติดต่อภายนอก, deploy, research activation, cleanup หรือข้อมูลจริง. Current-model deterministic fallback; Standard/default requested, effective tier unverified; ไม่ probe Jev/billing/quota หรือแก้ USD5 ledger.

Writer ปล่อยผ่าน immutable `evidence/S01-BU-checkpoint.json` พร้อม SHA256 และหยุดเขียนหลัง publication. Controller รับผลผ่าน final message/receipt; writer ไม่สร้าง successor.
