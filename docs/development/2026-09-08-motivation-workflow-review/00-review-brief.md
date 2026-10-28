# Motivation workflow impact review — briefing

วันที่ 8 กันยายน 2026 — งานนี้เป็นการวิเคราะห์และวางแผนตามคำขอผู้ใช้ ไม่ใช่การแก้โค้ดหรืออนุมัติ rollout

## ขอบเขตและหลักฐานตั้งต้น

- Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
- Branch: `codex/pair-matching-pm0-pm8`
- HEAD: `788e90e62b1694c20945734787723c168b6a6ab2` พร้อมงาน UI/contextual ที่ยังไม่ commit; ต้องอ่าน working tree ล่าสุด ไม่ใช้ HEAD อย่างเดียว
- ผลตรวจล่าสุด: `docs/development/2026-09-08-contextual-practice-results.md` มี 4,964 automated tests ผ่านและ debug APK; 4 native/platform exclusions, physical-device/UAT ยังไม่ตรวจรับสำหรับรุ่นล่าสุด ตัวเลขนี้เป็นหลักฐานเดิม ไม่ใช่ผลที่รันในรอบวิเคราะห์
- มุมผู้ใช้ด้านล่างเป็นการวิเคราะห์โดยเอเจนต์ ไม่ใช่บทสัมภาษณ์หรือ UAT ของบุคคลจริง

## ข้อเสนอที่ต้องท้าทาย

**User clarification during review:** โครงการสร้างเพื่อแก้ปัญหา ไม่ได้ตั้งต้นเพื่อทำเงิน BA ต้องเน้นรับฟังผู้ใช้และปัญหาที่เด็กไทยประสบ โดยใช้ข้อมูลอินเทอร์เน็ตที่น่าเชื่อถือประกอบได้ มุมธุรกิจเป็นการพิจารณาความยั่งยืนและโอกาสต่อยอดในอนาคต ไม่ใช่เป้ารายได้ที่มาบังคับการออกแบบปัจจุบัน ต้องแยกข้อมูลวิจัยระดับประชากร สมมติฐาน persona และเสียงของผู้ใช้จริงอย่างชัดเจน

**User design clarification during review:** UX/UI เป็นเกณฑ์หลักด้วย ต้องสวยงามและเสร็จเรียบร้อย ไม่ดูดิบ ใช้รูปแบบที่ผู้ใช้คุ้นเคยจาก Duolingo และ ALLTCAS เพื่อลดการปรับตัว อาจเรียบง่ายหรือมี animation เล็กน้อยตามหน้าที่ ต้องวิเคราะห์ layout/interaction/หลักการออกแบบร่วมกับผลกระทบระบบ ไม่คัดลอกแบรนด์หรือสรุปว่ารูปแบบยอดนิยมยืนยันความเหมาะสมกับเด็กไทยทุกกลุ่มโดยอัตโนมัติ Root จะจัดหลักฐานภาพปัจจุบัน/แหล่งอ้างอิงดีไซน์ก่อนรอบโต้แย้ง; S11 ต้องให้ข้อสรุปด้านหน้าจอและเกณฑ์ตรวจรับจริง ไม่ใช่แค่รายการฟีเจอร์

P1 เชื่อมเป้าหมายกับแผนรายสัปดาห์และหน้า วันนี้; P2 อธิบายพัฒนาการส่วนตัวจากหลักฐานจริง; P3 ภารกิจที่หลากหลายและเลือกได้; P4 กลับมาเรียนหลังเว้นช่วงและตารางเตือน; P5 แสดงภาพอวาตาร์ตามอุปกรณ์ที่ถือครอง; P6 เพื่อนร่วมฝึกแบบสมัครใจ

ทุกฝ่ายต้องแยกสิ่งที่มีแล้ว สิ่งที่ทำไม่ครบ และ capability ใหม่ ไม่ถือ `partial/newCapability` ใน feature map เป็นสถานะ runtime ปัจจุบัน ไม่อนุมานว่าฟีเจอร์ที่มีโค้ดถูกเปิดในทุก build

## ผู้ตรวจ 10 บทบาท

| ID | บทบาท | คำถามหลัก |
| --- | --- | --- |
| U1 | ผู้เริ่มต้น ไม่ถนัดแอป | เข้าใจว่าจะกดอะไรและเรียนเพื่ออะไรหรือไม่ |
| U2 | ผู้เตรียมสอบ มีเส้นตาย | งานใหม่แทรกการทบทวนและผลเรียนที่จำเป็นหรือไม่ |
| U3 | ผู้มีเวลาจำกัด กลับมาหลังหยุด | กลับมาได้ง่ายโดยไม่ถูกกดดันหรือไม่ |
| U4 | ผู้ใช้จอเล็ก การเข้าถึง และออฟไลน์ | ใช้งานได้เท่าเทียมโดยไม่เพิ่มภาระอุปกรณ์หรือไม่ |
| U5 | ผู้ชอบแต่งตัวละครและเรียนกับเพื่อน | ความสนุกและความเป็นตัวเองสัมพันธ์กับการเรียนอย่างไร |
| BA | Business Analyst | ปัญหาเด็กไทย/เสียงผู้ใช้ หลักฐาน ความต้องการ และเกณฑ์ตรวจรับเชื่อมกันอย่างไร; ความยั่งยืนและทางต่อยอดรองรับภารกิจอย่างไร |
| PM | Product Manager | ลำดับส่งมอบ คุณค่า ภาระ และสิ่งที่ควรเลื่อน |
| SA | System Analyst / Architect | ข้อมูล เจ้าของสถานะ กติกา และเส้นทางระบบกระทบที่ใด |
| DEV | Developer | จุดเชื่อมจริง ความเสี่ยงการเปลี่ยน การย้ายข้อมูล และ rollback |
| QA | Quality Assurance | regression, acceptance, device/UAT และหลักฐานที่ยังขาด |

เอเจนต์ S11 จะอ่านข้อสรุปและข้อโต้แย้งของทั้งสิบหลังจบการทบทวน แล้วสรุปจุดกึ่งกลางและแผนแก้ผลกระทบอย่างอิสระ

## กระบวนการ

1. วิเคราะห์อิสระโดยอ่าน code + historical decisions + latest evidence
2. ย้อนตรวจพัฒนาการ: V2/runtime convergence → 8/44 → Adventure → Research → Pair → Thai UI → contextual spelling/cloze/optional voice
3. แลกข้อโต้แย้งกับบทบาทอื่น และบันทึกว่าจะคง เปลี่ยน หรือปฏิเสธข้อเสนอใดพร้อมเหตุผล
4. S11 ตัดสินระหว่างทางเลือก ปรับของเดิม / ทำตามลำดับ / เพิ่มพร้อมกัน โดยไม่ใช้การลงคะแนนแทนหลักฐาน
5. จัดทำรายงานผลกระทบ แผนส่งมอบและตรวจรับ ตรวจเอกสารและยืนยันว่า source เดิมไม่เปลี่ยน

## ข้อจำกัดที่ต้องรักษา

- Standard learning และทางเข้าโหมดเดิมยังเรียนต่อได้; Adventure เป็นทางเลือก
- ไม่สร้าง authority ใหม่ซ้ำกับ Learning Evidence, SRS, Mastery, Quest, Streak, XP/Coins, Rewards, Today, History
- คง 8/44 catalog และ frozen EvidenceContext/EventEnvelopeV2; capability ใหม่ต้องมี scope/version decision ของตัวเอง
- การลองพูดเสริมล่าสุดเป็น optional ephemeral unscored; ห้ามเปลี่ยนเป็นหลักฐานรางวัล/ความชำนาญผ่าน UI
- ห้ามคะแนนหรือรางวัลซ้ำจาก retry, revisit, replay, double tap หรือ owner transition
- แยก learning, motivation, retention และ reward; ห้ามอ้าง efficacy จาก automated tests
- Research ยังคง default-off/consent/permit/owner boundaries; ผู้ไม่ร่วมวิจัยต้องเรียนได้โดยไม่มี research rows/events/uploads
- ข้อมูล owner-scoped ใหม่ต้องพิจารณา migration, deletion, export, sync/policy และ offline; อย่าจองหมายเลข migration โดยยังไม่ตรวจ ledger
- ไม่แก้ source/test/config/generated files, dependency, guardrails หรือสถานะ rollout ในรอบนี้ ไม่รัน Flutter/test/build ไม่แตะอุปกรณ์/production
- เขียนได้เฉพาะรายงานรายบทบาทที่ root มอบหมายด้วย apply_patch; ไม่มี commit

## แหล่งย้อนตรวจ

- `docs/superpowers/specs/2026-08-03-lexiquest-v2-evolution-framework-design.md`
- `docs/superpowers/specs/2026-08-08-lexiquest-complete-field-trial-convergence-design.md`
- `docs/superpowers/specs/2026-08-14-lexiquest-alltcas-idea-integration-feature-contract-design.md`
- `docs/superpowers/specs/2026-09-01-adventure-motivation-mode-design.md`
- `docs/development/2026-09-05-research-engineering-status.md`
- `docs/development/2026-09-07-pair-matching-pm8-local-verification.md`
- `docs/development/2026-09-08-approved-learner-ui-results.md`
- `docs/development/2026-09-08-contextual-practice-results.md`

## ข้อมูลต้นแบบที่ตรวจแล้วในบทสนทนาก่อนหน้า

ถือว่า RTKS หมายถึง ALLTCAS ตามบริบท ยังไม่ได้รับการยืนยันชื่อเพิ่มเติมจากผู้ใช้ ข้อเสนอเฉพาะของ LexiQuest ไม่ใช่การยืนยันว่าทุกต้นแบบมีฟีเจอร์เดียวกัน

- [ALLTCAS](https://alltcas.com/): ห้องโจทย์กับเพื่อน, weekly rankings, timer/statistics
- [Duolingo social](https://blog.duolingo.com/friends-social-features/): Friends Quests, Friend Streaks, congratulations
- [Duolingo learning metric](https://blog.duolingo.com/time-spent-learning-well/): quest progression และข้อจำกัดของ XP grinding
- [Duolingo avatar](https://blog.duolingo.com/avatar-creator/): visual customization

ข้อมูลเหล่านี้เป็น product references ไม่ใช่หลักฐานเชิงสาเหตุว่า LexiQuest จะเพิ่มแรงจูงใจได้เท่ากัน ไม่จำเป็นต้องค้นซ้ำทุกบทบาท
