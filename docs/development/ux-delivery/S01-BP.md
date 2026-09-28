# S01-BP — quest child and vocabulary forms host audit

Worktree: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest` · branch `codex/ux-current-after-s01-bc` · HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1`.
Writer: `01a0e0be-f3e1-7ab0-9d33-f3d7c6ddc7ae`; controller: `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผล

**HOST SYNTHETIC PASS:** 5 tests บน source fingerprint เดียวกัน; ตรวจภาพด้วย `view_image` ครบ 24 ภาพที่ 360×800, DPR1, ภาษาไทย 1×/2× พร้อม NotoSansThai, MaterialIcons และเงาจริง แก้ production หนึ่งบรรทัดใน `lib/screens/add_vocab_screen.dart`: ให้ label CEFR ลอยเหนือช่องตลอด เพื่ออ่านคำว่า “ไม่บังคับ” ครบก่อนเลือกค่า

**BP-A11Y-01 FIXED (host):** ภาพก่อนแก้ `initial-renders/02-add-empty-2.0x.png` แสดง label ถูกตัด เพิ่ม assertion `RenderParagraph.didExceedMaxLines == false` แล้วได้ RED จริง: expected false / actual true จากนั้นตั้ง `FloatingLabelBehavior.always` และได้ GREEN พร้อม flow บันทึกเดิม ไม่เปลี่ยน validation, authority หรือ semantics label

อ่าน source และ coverage ใน `quest_status_screen_test.dart`, `word_form_recovery_test.dart`, `vocab_list_screen_test.dart` ก่อนเพิ่ม `test/support/forms_host_ui_audit_test.dart`. ไม่ทำ owner/recovery/offline matrix ซ้ำ ใช้ `NativeBaselineFixture`, `baselineDependencies`, `baselineAwait`, canonical vocabulary/quest authorities และ disposable SQLite เท่านั้น

## Coverage

| Surface / action | ผล | หลักฐานและขอบเขต |
| --- | --- | --- |
| Drawer → Quest empty → Back | PASS | route จริง; Back ผ่าน Tab/Enter |
| Quest active/details/collapse | PASS | seed daily quest เดิมด้วย canonical refresh ใน fixture; แสดง 0/5; กดขยายและยุบผ่านคีย์บอร์ด; ไม่ตอบคำถามหรือรับรางวัล |
| Quest expired ที่จอแคบ | PASS | canonical expiry เฉพาะ fixture; ข้อความสถานะที่ยาวที่สุดไม่ overflow ที่ 360/2×; เทสต์ lifecycle เดิมใช้ 800px |
| Vocabulary → category → Add | PASS | กดปุ่มจริง, empty validation, Back ยกเลิก draft แล้วฐานข้อมูลไม่เปลี่ยน |
| Form keyboard/semantics | PASS | Tab จากคำศัพท์ → ความหมาย → ชนิดคำ; focused text-field/setText semantics; save/Back เข้าถึงและใช้ Enter ได้ |
| CEFR popup/save | PASS | เปิด popup จริง เลือก A1; คำว่าไม่บังคับอ่านครบก่อนเลือก; บันทึกกลับ list |
| Edit/cancel/save | PASS | เปิดจากแถวจริงและ preload; cancel ไม่เปลี่ยน revision; save เปลี่ยนคำเดิม revision 1→2; คง A1 และคำ fixture เดิม |
| Tap labels/targets | PASS | androidTapTargetGuideline และ labeledTapTargetGuideline ทุก final capture; ไม่มี layout exception |
| Data isolation | PASS | 56 ตารางนอก vocabulary_words/outbox_operations เท่ากันก่อน/หลัง UI; setup เปลี่ยนเฉพาะ quest tables; learning/research/reward ยังว่าง; outbox 4 รายการเป็น category/word pending, attempt=0; HTTP/gateway counters=0 |
| Native screenshots, actual IME/keyboard/TalkBack | NOT_RUN | host key events/TestTextInput ไม่ใช่ผลบนอุปกรณ์; ไม่มี native UI/adb/browser/VM |
| Actual-user participation/trials | DEFERRED | ตามคำสั่งผู้ใช้ 27 September; ไม่อ้าง usability หรือ efficacy |
| Today fully routed success, populated-learning Profile, full release | NOT_RUN | ข้อจำกัด BO ยังคงเดิม; ไม่เปิด Today gate หรือสร้าง learning evidence |

## Verification

Final `verify-scope Targeted/Runtime` ทั้ง 5 selections มี pre/post fingerprint ตรงกัน:
`a82659db25fe587c358c9b1092e6008af4bb019d7040c08e4cf3c1b06be365b1`.

- `verify-quest-phone.log`: host 2× รวม quest empty/active/details/expired และ form actions — 1 PASS
- `verify-host-1x.log`: flow เดียวกันที่ 1× — 1 PASS
- `verify-form-regression.log`: `AY owned CEFR chooser remains usable and saves selected level` — 1 PASS
- `verify-quest-regression.log`: `renders all lifecycle states without internal identifiers` — 1 PASS
- `verify-vocab-regression.log`: `personal vocabulary keeps its mutation actions` — 1 PASS
- `analysis-final.log`: `dart analyze test/support/forms_host_ui_audit_test.dart lib/screens/add_vocab_screen.dart` — no issues. ไม่ใช่ repository-wide analyzer; ข้อจำกัด BN/BO ยังคงอยู่
- source closure 1,576 pins ตรงกับ source ปัจจุบัน; preservation 198/198 ตรงเดิม (201 initial pins ยกเว้น README/state/ready-backlog ที่อัปเดตตามงานนี้)
- focused diff และ `git -c core.whitespace=cr-at-eol diff --check` ผ่าน; คง line endings และ generated7 เดิม

เก็บ initial gate/ภาพก่อนแก้และ RED log ไว้ ไม่อ้าง initial PASS ว่าครอบคลุม clipping เพราะตอนนั้นยังไม่มี assertion. ปรับ harness ให้รอ frame ก่อน capture หลังกรอกข้อความ เพื่อให้ภาพตรงกับค่าปัจจุบัน. การอ่าน SDK source ถูก filesystem ปฏิเสธ จึงไม่ได้อ่านต่อ; ใช้ source แอป ภาพ และ RenderParagraph assertion แทน ไม่มี bypass. Patch เอกสารครั้งแรกถูก parser ปฏิเสธเพราะซ้ำ target; ตรวจว่าไม่มี write แล้วใช้ Update File ที่ถูกต้อง

## ภาพที่ตรวจ

ทุก prefix ใน `evidence/S01-BP-runs/host-renders/` มีทั้ง `1.0x`/`2.0x`:

| Prefix | สิ่งที่ตรวจ |
| --- | --- |
| 01-quest-empty | หน้าไม่มีภารกิจและ Back |
| 02-add-empty / 03-add-validation | label ไม่บังคับครบ; validation ไทยตัดบรรทัดอ่านได้ |
| 04-add-focused / 05-cefr-chooser / 06-add-ready | focus, popup A1–C2, save; ช่องบรรทัดเดียวเลื่อนแนวนอนเมื่อข้อความยาว |
| 07-list-added / 08-edit-loaded / 09-list-edited | ค่าที่เพิ่มและแก้; แถว list ขยายตามข้อความ 2× |
| 10-quest-active / 11-quest-details / 12-quest-expired | progress 0/5, รายละเอียดเลื่อนอ่านได้, รางวัลระบุว่าเป็นเงื่อนไข |

## Handoff และข้อจำกัดที่เหลือ

[Validation](evidence/S01-BP-validation.json) เก็บ source/artifact pins และคำสั่งจริง; [checkpoint](evidence/S01-BP-checkpoint.json) เก็บ hash/state/writer release. รักษา dirty BD–BO/generated7/หลักฐานเดิม ไม่มี host test/build process จาก BP ค้าง ไม่สังเกตหรือแก้ native process/package

ขอบเขตที่มอบหมายปิดแล้ว; ไม่เลือกแพ็กเกจขยายโดยอัตโนมัติ ช่องว่างจริง: Today success route ยังถูก feature/composition gate ปิด; BO ตรวจ Profile เฉพาะ loaded-empty; native IME/TalkBack และ actual-user acceptance ยังไม่มีหลักฐานของ snapshot นี้; instructional expansion ยังต้อง reviewed media/qualified trials. Controller ตรวจ checkpoint แล้วเลือกจากช่องว่างจริง ไม่ dispatch จาก BP

Writer **RELEASED** หลัง checkpoint; S01 ยัง IN_PROGRESS และ UX-D01–25 OPEN. ไม่อ้าง full-baseline/native/release readiness. Current-model deterministic fallback; Standard/default requested, runtime tier unverified; ไม่มี Jev/billing/login/quota probe, ledger USD5 ไม่เปลี่ยน ไม่มี deployment, research activation, external contact, cleanup หรือ worktree ใหม่
