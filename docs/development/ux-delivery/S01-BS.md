# S01-BS — ordinary meaning quiz exact resume

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`; branch `codex/ux-current-after-s01-bc`; HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1`.
Writer `01a0e53a-bd22-7723-96db-1b02bb81640b`; controller `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผลตามจริง

**BS-RESUME-01 OPEN / acceptance RED — ยังไม่ได้แก้ exact resume.** ตรวจและจำลองปัญหาตามเงื่อนไขที่อนุญาตให้บันทึก concrete next contract เมื่อ API ปัจจุบันคืนงานเดิมไม่ได้อย่างปลอดภัย. ไม่มี production source change และไม่อ้าง engineering completion ของ resume หรือ release acceptance.

BR receipt เป็น RELEASED; ตรวจ predecessor source/artifact/closure 1,631 pins mismatch 0 ก่อนเขียน. Snapshot ก่อนงานนี้ 5,096 files อยู่ใน `evidence/S01-BS-runs/baseline.json`. BR 4 gates เป็นหลักฐานเฉพาะ snapshot เดิม; ไม่ reuse PASS เป็น acceptance ของ BS.

## ขอบเขตและ reproduction

`test/support/today_quiz_resume_contract_test.dart` ใช้ AppBootstrap จริง, `learningPreviewEnabled=true`, SQLite in-memory และ temporary support directory แยก, no-login และ HTTP operation rejection. สร้างศัพท์ synthetic สองคำใน owner จริงของฐานทดสอบ แล้วเรียก canonical `learning.startQuiz(categoryId, limit: 2)`; ไม่ใช้ fake session summary หรือ seed learning session โดยตรง.

ก่อน assertion ที่ RED ตรวจได้ว่า owner/session ตรง, Today อ่าน session เดิม, resume เลือก Learning index 1, ทุกแถวของฐานก่อน/หลัง navigation เท่ากัน และ HTTP calls 0. จากนั้น required assertion หา `QuizScreen` ไม่พบ (expected 1, actual 0). ไม่มีคำตอบหรือคะแนนถูกส่งในการทดลองนี้ จึงไม่อ้าง no-duplicate-score หลัง resume/completion.

รอบแรกเรียก `loadExactActivityRecovery(ownerId, sessionId, activityType: quiz)` ก่อน route แล้วได้ `StateError: exact activity checkpoint is missing or corrupt`. เก็บ gate/log เป็น checkpoint-red. รอบสุดท้ายย้ายการอ่าน recovery หลัง required route assertion เพื่อจำลอง route โดยตรง; ไม่เปลี่ยน assertion ให้ยอมรับ Learning tab และไม่ skip RED. Final route test เป็น 0 passed / 1 failed ตาม defect จริง. Analyzer เฉพาะไฟล์ใหม่ exit 0, No issues found. คำสั่งทั้งสองผ่าน `tool/cli/verify-scope.ps1 -Level Targeted -Area Runtime -TestTargets test/support/today_quiz_resume_contract_test.dart`; gate pre/post และ closure อยู่ใน validation/immutable receipt. ไม่มี full release verifier หรือ heavy gates ขนาน.

## ต้นเหตุและเหตุผลที่ยังไม่ต่อ route

- `main_navigation_screen.dart::_resumeFromToday` ตรวจ owner/isCurrent แล้ว ordinary activity ลงท้ายที่ `_selectLearningFromToday`; ไม่มีการ load/attach session.
- `LearningUseCases.startQuiz` เรียก `repository.startSession` ด้วย summary/configuration; คืน questions เฉพาะใน `QuizSession` ที่อยู่ในหน่วยความจำ. `DriftLearningRepository._insertLearningSession` ไม่บันทึก ordered question/content snapshot หรือ checkpoint สำหรับ ordinary quiz.
- `loadExactActivityRecovery` มีอยู่ แต่ repository ปฏิเสธ exact session ที่ checkpoint หาย. `reconstructPinnedQuizSession` ต้องได้รับ ordered identities/revisions/checksums จาก authority ที่บันทึกไว้; summary ไม่มีข้อมูลเหล่านี้ครบ จึงสร้างกลับโดยเลือกศัพท์ปัจจุบันแทนไม่ได้.
- `QuizScreen.attachedSession` ส่ง session เข้า `_prepareSession` และสร้าง meaning review ใหม่. `MeaningQuizReviewController` เริ่ม index 0, awaitingAnswer, selectedOption null, pending operation null; ไม่มี restore input สำหรับ draft/feedback/pending evidence identity. ต่อ route อย่างเดียวเสี่ยงย้อนข้อและสร้าง operation ใหม่ ไม่ใช่ exact resume.
- Today มี view/route/feature guard ใน `_buildTodayHub`; dependencies ถูก resolve จาก scope. การเพิ่ม async reconstruction ต้อง revalidate owner, authority identity, route generation, feature และ composition หลัง await ทุกช่วง ไม่ถือ guard ก่อนอ่านเป็นหลักฐานตลอดอายุ callback.

## Concrete next contract — prerequisite ของการแก้

ใช้ Learning authority/repository และ checkpoint storage เดิม; ไม่เพิ่ม schema หรือ score/SRS/reward writer. ต้องเพิ่ม versioned ordinary-meaning-quiz checkpoint codec และ controller restore contract ที่ครอบคลุม:

1. Atomic ordinary start พร้อม session ID/owner/configuration และ ordered content IDs, revisions, checksums, prompt direction/options identity. ตรวจว่า generic checkpoint APIs เดิมรองรับ transaction/validation ทั้งหมดก่อนนำมาใช้.
2. Durable current index, answer/feedback phase, draft/selected option และ frozen pending/committed operation identity. บันทึกก่อน pause และกู้หลัง restart โดยไม่สร้าง evidence identity ใหม่สำหรับคำตอบเดิม; reconcile acknowledgement loss ผ่าน canonical replay.
3. Restore จาก exact accepted session/checkpoint เท่านั้น; owner check ก่อน/หลัง await, route/feature/dependency generation guard และ late-callback rejection. ห้าม startQuiz เพื่อเลียนแบบ resume. Missing/corrupt/legacy checkpoint หรือ content drift ต้องแสดง recovery unavailable พร้อมรักษาข้อมูล ไม่เดาลำดับเดิม.
4. ส่ง restored state เข้า QuizScreen/controller/lifecycle ด้วย authority เดิม; draft และข้อที่ตอบแล้วต้องไม่กลับเป็นข้อใหม่. ความหมาย pause/abandon ของ shell ต้องตรวจร่วมกันก่อน wiring.
5. Acceptance บนฐาน synthetic: กลับข้อเดิมหลังตอบอย่างน้อยหนึ่งข้อ/มี draft, process-like dispose/recreate, content revision drift, owner switch ทุก async boundary, stale route/feature/dependency/late callback, pending-write replay และ complete ซ้ำต้องไม่เพิ่ม score/SRS/reward. รักษา RED ปัจจุบันแล้วเพิ่ม acceptance เหล่านี้ก่อนอ้าง GREEN.

ข้อขาดนี้เป็น engineering contract ไม่ใช่การรอผู้ใช้จริงหรือ permission ใหม่. Controller ต้องรับ findings และกำหนดงาน canonical checkpoint/restore นี้ก่อนปิด BS-RESUME-01; งานปัจจุบันไม่สร้าง successor และไม่ย้าย RED ไปอ้างว่าปิดแล้ว.

## ขอบเขตที่คงไว้และ release

Actual-user trials DEFERRED; native/visual/device และ draft/replay/completion acceptance NOT_RUN. Field gate, no-login/no-AI baseline, routes/deeplinks, owner/scoring/SRS/rewards/schema ไม่เปลี่ยน. ไม่ deploy/research activation, nativeUI/adb/browser/helper, installed-package changes หรือ external contact. Current-model deterministic fallback; Standard/default requested, runtime tier unverified; ไม่ probe billing/login/quota หรือแก้ USD5 ledger.

หยุด source writes และปล่อย writer ด้วย `evidence/S01-BS-checkpoint.json` พร้อม checksum; เป็น handoff ของ OPEN/RED ไม่ใช่ production release. Final validation ระบุ preservation, source/artifact hashes, gate pre/post และ running process state. Controller รับงานจาก receipt นี้; ไม่มี successor.
