# S01-BV — exact ordinary meaning recovery

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`; branch `codex/ux-current-after-s01-bc`; HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1`.
Writer `01a0e5ac-44de-7793-8a8a-278274d559f9`; controller `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผลและขอบเขต

PASS_HOST_SYNTHETIC_EXACT_RESUME: final targeted 283 PASS / 0 failed; analyzer ของ 13 touched source/test files ไม่พบปัญหา. ปิด BS-RESUME-01 เฉพาะ ordinary meaning exact recovery ใน host synthetic scope. S01/UX-D01–25, native/UAT/user/release acceptance ไม่ได้ปิดตาม.

- เพิ่ม ordinary progress envelope version 2 โดยรักษา frozen admission plan version 1, owner/session/configuration และ content/artifact pins เดิม. กู้ index, selected draft, pending/answered feedback และ close occurrence. Initial BU checkpoint รับได้เฉพาะ revision 1 ที่ยังไม่มี attempts; ไม่เดาหรือสร้าง quiz ใหม่จาก legacy/missing/corrupt state.
- บันทึก draft ก่อน resolve evidence context; บันทึก frozen pending command ก่อนส่ง canonical writer. กู้คำตอบผ่าน idempotent replay เดิม. Feedback อ้าง committed result; controller ใหม่ต้อง restore ก่อนรับคำตอบใหม่. เก็บ checkpoint ที่ acknowledgement หายไว้ retry ด้วย revision/time/state เดิม.
- Ordinary operation guard ตรวจ owner/session/checkpoint/content ภายใน transaction ที่ครอบ existing Learning writer. ไม่เพิ่ม scoring/SRS/reward authority, schema, table หรือ migration. EvidenceContext/EventEnvelopeV2 ไม่เปลี่ยน. Core/lexical drift และ callback ที่หมดอายุถูกปฏิเสธ.
- Close ใช้ occurrence ระดับ milliseconds ตรงกับ durable DB, บันทึก terminal intent ก่อน finish และ acknowledgement หลัง canonical result. Today มองเห็น ordinary close ที่ completed แต่ยังไม่ acknowledged; กู้ session เดิมแล้วไปผลเดิมได้. Acknowledged close ไม่ถูกเสนอซ้ำ.
- Closing checkpoint เก็บ selected answer และ frozen occurrence ของข้อสุดท้ายเพื่อคืน feedback ด้วย canonical replay. Skip ผ่าน controller โดยตรงต้องโหลด progress ก่อนบันทึก; ไม่แอบข้าม durable journal เมื่อ UI ยังไม่ได้ initialize.
- Today เปิด `learning/quiz/resume` ด้วย attached admitted session เดิม พร้อม dependency/feature/route-generation guards. Recreated QuizScreen อ่าน progress ก่อนเปิดให้ตอบ; late callbacks หลัง feature off, replacement dependencies หรือ route ถูกทับไม่เขียนข้อมูล.
- เพดาน ordinary checkpoints กำหนดใน shared limits เป็น 404 เพื่อรองรับ admission + draft/pending/feedback/advance ของ 100 ข้อและ close/ack. กิจกรรมอื่นยัง 64; 64 KiB ต่อ checkpoint และ 128 attempts ไม่เปลี่ยน. ใช้ bounded append-only journal เดิม; budget/authority failure ไม่สร้าง replacement quiz.
- ตรวจ semantics เดิมแล้ว: ปุ่มออกเป็น abandon ไม่ใช่ pause. คงพฤติกรรมนี้; process-like dispose/recreate ของ session ที่ยังไม่ยุติใช้ exact recovery. Typed recall และ attached review รักษาเส้นทางแยกเดิม.

## Verification และการรักษาหลักฐาน

เริ่มจาก BS contract เดิมโดยไม่แก้ assertion: RED, QuizScreen expected 1 / actual 0. จากนั้นเพิ่ม RED/GREEN ของ durable feedback, unresolved-context draft, pending acknowledgement, terminal precision/Today completed-close และ controller ที่ถูกสร้างใหม่โดยยังไม่ restore. Test สุดท้ายจับ duplicate score จากกรณีหลังได้ก่อนแก้ จึงไม่ใช้เพียงคำตอบว่ามี exception เป็น acceptance.

Actual-bootstrap contract ครอบคลุม initial, draft, feedback, next question, pending committed answer, committed close, feature off, replacement composition และ covered route; synthetic SQLite, isolated support directory, no-login/no-HTTP. ตรวจทุกตารางก่อน/หลัง resume และตรวจ projections หลัง replay/completion. ไม่มี native UI, screenshot/input, adb, browser/helper, real-user trial หรือ package operation.

การปรับ test เดิมมีเหตุผลตาม contract: ตรวจ NavigationBar ใต้ pushed quiz route ด้วย `skipOffstage: false` แต่คง required visible QuizScreen/session assertion; legacy summary ที่ไม่มี checkpoint ต้องอยู่ Today พร้อมข้อมูลเดิม. Fault injection สำหรับ lost acknowledgement ย้ายไปหลัง outer transaction commit จริง โดยคง assertion ว่ามี durable answer ก่อน retry.

สอง regression สุดท้ายมี RED จริงก่อนแก้: skipped progress expected true / actual false และ feedback หลัง committed close expected true / actual null; focused GREEN หลังแก้. คำสั่งคัด test ด้วย regex ครั้งแรกไม่รัน test เพราะ verifier ใช้ `--plain-name`; จึงแก้ selector เป็นชื่อย่อยและรันแยก ไม่ใช้ผล “No tests ran” เป็น RED ของผลิตภัณฑ์.

ระหว่าง regression พบ audit fixture เดิมเขียนผลกลับเข้า BR evidence. ตรวจ candidate bytes กับ SHA256 จาก pre-write baseline ก่อนคืนค่า แล้วเปลี่ยนปลายทางรันใหม่ไป mutable build output; BV เก็บสำเนาผลของตนเอง. Preservation ตรวจ baseline 5,130 ไฟล์: ไม่พบ mismatch นอก explicit write set; generated 7 และ BU artifact pins 20 ตรงเดิม รวม BR ที่คืนค่า byte-for-byte. ไม่แก้ historical acceptance หรือ receipt.

Final command: `tool/cli/verify-scope.ps1 -Level Targeted -Area Runtime -TestTargets` โดยเลือก 10 files ใน `gate-final-targeted.json`; 283 tests ผ่านใน Flutter runtime ประมาณ 4 นาที 25 วินาที. Runtime input closure และ gate pre/post fingerprint ตรงกัน: `e50a7b53676d26861762406642791a1efa8530b58cf472603d1da92bc704bcc7`. Analyzer มี pre/post SHA256 ของทั้ง 13 files; final closure ตรวจเทียบ source ปัจจุบันอีกครั้งก่อน release. Git diff whitespace check ผ่าน; ไม่รัน full suite/release verifier หรือ native build บน dirty checkout.

รายละเอียด final commands, counts, gate pre/post fingerprints, source closure, source/artifact hashes และ preservation อยู่ใน `evidence/S01-BV-validation.json` และ `evidence/S01-BV-runs/`. ไม่ reuse PASS ข้าม fingerprint; ไม่รัน full release บน dirty checkout.

## Release boundary

Field dailyContinuity ยัง hidden; preview scope เท่านั้น. Host synthetic ไม่ใช่ native/UAT/user acceptance หรือ production release. Actual-user trials DEFERRED; ไม่ deploy, activate research, ติดต่อภายนอก, ลบข้อมูลจริง หรือแตะ worktree อื่น. Current-model fallback; Standard/default requested, effective tier unverified; ไม่ probe Jev/billing/login/quota หรือแก้ USD5 ledger.

Writer release อ้าง immutable `evidence/S01-BV-checkpoint.json` พร้อม SHA256. Controller `01a0ce9e-23a6-7931-88e6-6390da748f39` ตรวจ receipt และเลือกงานถัดไปจาก scope ที่ยังเปิดอยู่; writer ไม่สร้าง successor และหยุดเขียนหลัง publication. ไม่มี test process ค้าง. ไม่มี release-only dependency ใดถูกใช้แทน engineering test ที่ยังไม่ผ่าน.
