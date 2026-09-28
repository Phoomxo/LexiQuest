# S01-BT — canonical ordinary quiz checkpoint boundary

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`; branch `codex/ux-current-after-s01-bc`; base HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1`.
Writer `01a0e558-a428-7a23-9df2-25d0026374a3`; controller `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผลและขอบเขต

**S01-BT OPEN/RED; BS-RESUME-01 ยังคง OPEN/RED. ไม่มี production implementation.** ใช้เงื่อนไข fallback ที่มอบหมาย: existing API รองรับ atomic storage ของ opaque checkpoint แต่ยังไม่รองรับ exact ordinary meaning prompt/options contract อย่างปลอดภัยแบบใช้ตรง ๆ. ไม่อ้างว่าข้อจำกัดนี้แก้ไม่ได้; ต้องเพิ่ม contract การ compose/admit โจทย์จริงก่อน จึงจะบันทึก checkpoint ที่มีความหมายครบถ้วนได้. ไม่รอผู้ใช้จริงและไม่ขอ permission ใหม่.

ก่อนเขียน ตรวจ BS validation pins + artifact receipt pins + final gate inputClosure รวม **1,598 entries, mismatch 0** (นับตามสามชุดที่อ่านจริง รวมรายการซ้ำ; ไม่ใช่จำนวนไฟล์ unique หรือเลข 1,597 ที่ controller เคยรายงาน). Snapshot tracked/untracked ที่ Git มองเห็นอยู่ใน `evidence/S01-BT-runs/baseline.json`. ตรวจ writer BS RELEASED/state144 และ HEAD/branch จริงแล้ว. ไม่แก้ immutable BS evidence.

## API ที่ตรวจและหลักฐานที่ได้

- `DriftLearningRepository.startSessionWithCheckpoint` canonicalize JSON, จำกัด 65,536 bytes และ transaction session+checkpoint; identity/revision replay แบบเดิมไม่เพิ่ม event. `startExactPinnedSessionWithCheckpoint` เพิ่ม uniquely active owner และ revision/checksum validation ภายใน transaction.
- `LearningActivityRecoveryLimits`: 64 checkpoints, 128 attempts, 64 KiB ต่อ checkpoint. codec version ของ ordinary meaning ยังไม่มี; generic API ไม่ทำ semantic validation ให้กิจกรรมนี้.
- Exact read ตรวจ owner/session/activity และปฏิเสธ legacy missing checkpoint; `reconstructPinnedQuizSession` ปฏิเสธ content drift จาก pins ที่ผู้เรียกส่ง. การอ่าน generic checkpoint สำเร็จไม่ใช่หลักฐานว่าข้อมูลใน `state` ถูกต้องตาม ordinary meaning contract.
- ไม่มี schema, score/SRS/reward writer ใหม่. การทดสอบ generic replay เปรียบเทียบทุก user table ก่อน/หลัง ยกเว้น `learning_sessions`/`events_v2` ที่ admission ตั้งใจเขียน และเปรียบเทียบ event rows ก่อน/หลัง replay. นี่พิสูจน์เฉพาะ **generic admission replay** ไม่ใช่ ordinary answer/completion replay.

## Concrete gap ที่ทำให้ direct reuse ไม่ปลอดภัย

1. **เวลาที่กำหนด prompt/options อยู่หลัง commit:** `LearningUseCases.startQuiz` สร้าง `QuizSession` จาก `canonicalQuizQuestions` ซึ่งเป็น meaning labels; แต่ `MeaningQuizModeAdapter.pinQuestions` สร้าง forward/reverse/mixed prompt และ ordered options อีกชุด. `QuizScreen._prepareSession` อ่าน distractors เมื่อชุดเดิมไม่พอ (หรือ attachedSession) และโหลด lexical metadata หลัง await start. คำศัพท์ใน extra options จึงไม่อยู่ใน ordered session questions เสมอ และ metadata ที่กำหนด evidence/contrastive identity ยังไม่ถูกผูกกับ atomic admission.
2. **ทดสอบได้ว่า session เดียวกำหนดตัวเลือกจริงไม่ได้:** ordinary start limit1 ได้ตัวเลือกหนึ่งรายการ; เรียก adapter เดิมพร้อม distractor จริงจากฐาน synthetic ได้สองรายการและ optionIdentities ต่างกัน โดย session ID/content เดิมทั้งหมด. การบันทึกเฉพาะ `_questions(words)` จึงให้ checkpoint ที่ดูครบแต่ไม่ใช่โจทย์จริง. ทดสอบนี้ไม่ใช่ UI acceptance.
3. **ไม่มี ordinary semantic admission validator:** exact-pinned API รับ state ที่ `kind=ordinaryMeaningQuiz`, owner/session ผิดและ questions ว่าง แล้ว exact read คืน state นั้นได้ ทั้งที่ transaction ตรวจ external content pins ถูกต้อง. นี่เป็น characterization ของ generic opaque storage ไม่ใช่ regression ของ API ที่สัญญาว่าจะ validate ordinary codec อยู่แล้ว.

ดังนั้นไม่เพิ่ม checkpoint ที่เดาทิศทาง/options หรืออ้างว่า checkpoint ภายใน generic envelope คือ exact meaning snapshot. ไม่แก้ Today/controller restore และไม่สร้าง fresh quiz เป็น resume.

## Prerequisite ที่เป็นขั้นตอนถัดไปได้จริง

เพิ่ม **canonical ordinary meaning admission contract** ที่ freeze actual ordered questions, direction, prompt/option IDs+labels, answer identity, content revision/checksum ของคำถามและ distractors รวม verified lexical artifact identity ที่ adapter ใช้ **ก่อน** transaction. ใช้ pure shared composition เดียวกับ meaning adapter; ต้องมีวิธีให้ initial presentation ใช้ plan ที่ admit แล้ว ไม่โหลด extra distractors/metadata มาเปลี่ยนโจทย์หลัง commit. ต้องแยก typed-recall/attached review callers ที่ใช้ startQuiz/QuizSession ร่วมกันโดยไม่เปลี่ยนความหมายเงียบ ๆ.

เพิ่ม strict versioned codec ที่ตรวจ session/owner/configuration และรายการ content ทั้งหมดตรงกับ transaction pins, duplicate/unknown/version/budget rejection; ใช้ existing exact transaction เป็นฐานโดยไม่เพิ่ม schema. จับ frozen admission command ก่อนเขียนและใช้ identity เดิมสำหรับ lost-ack retry; ไม่ retry ด้วยการเลือกชุดคำใหม่. Test ที่ต้องเพิ่มคือ post-selection content/owner drift, mismatched prompt/options pins, exact retry/conflict และ byte boundary. หลัง initial admission ผ่านแล้ว controller draft/feedback/pending identity/restore และ route end-to-end ยังเป็นงานที่ต้องทำก่อนปิด BS-RESUME-01.

## Verification

เพิ่ม `test/features/learning/ordinary_quiz_checkpoint_contract_test.dart` ใช้ SQLite in-memory และคำศัพท์ synthetic เท่านั้น. First targeted run: **9 passed / 1 failed**, RED ที่ `exact activity checkpoint is missing or corrupt` หลัง canonical ordinary start. Characterizations ผ่าน: atomic rollback + retry, same-command replay/conflict, content drift ก่อน admission/หลัง admission, foreign-owner read/inactive-owner admission, byte budget, legacy fail-closed, opaque-state gap และ post-start options gap.

BS route targeted: **0 passed / 1 failed**, `QuizScreen` expected1/actual0 เช่นเดิม. ไม่มีการแก้/skip assertion. Analyzer รอบแรกพบ style info หนึ่งจุดใน test ใหม่ แก้ braces เท่านั้น แล้วตรวจ final snapshot ใหม่: **final combined Targeted 9 passed / 2 failed, exit1**; analyzer **No issues found, exit0**. Final gate pre/post ตรงกัน `8eb0325a6c31343491d25cd94fdd75716e0bda2d677174eff159b469bfe444cc`; gate ที่ Failed ไม่ถือเป็น PASS. ไม่ rerun full release/build/heavy parallel; ไม่มี physical/native/visual acceptance. Ordinary answer/score/completion replay และ full exact resume **NOT_RUN / NOT_IMPLEMENTED**.

Repository-wide `git diff --check` พบ trailing whitespace ใน pre-existing dirty overlay; ไม่แก้ churn นอกขอบเขต. Final preservation ตรวจเทียบ bytes ของ baseline ทุกไฟล์ยกเว้น README/state/backlog ที่อัปเดตตามงาน; ข้อเท็จจริงและ hashes อยู่ใน validation/receipt.

## Release

Actual-user trials DEFERRED; dailyContinuity production gate, schema, Phonics/story, scoring/SRS/rewards, owner/routes/deeplinks, no-login/no-AI คงเดิม. ไม่แตะข้อมูลจริง/package/nativeUI/adb/browser/VM/helper, ไม่ deploy/research activation/external contact. Current-model deterministic fallback; Standard/default requested, effective runtime tier unverified; ไม่ probe Jev/billing/login/quota หรือแก้ USD5 ledger.

Writer หยุด source writes และปล่อยด้วย immutable `evidence/S01-BT-checkpoint.json` + SHA256. เป็น **OPEN/RED handoff ตาม allowed fallback**, ไม่ใช่ engineering completion หรือ release acceptance. Controller ตรวจ receipt และ prerequisite ข้างต้นก่อนกำหนดขอบเขตถัดไป; writer ไม่สร้าง successor.
