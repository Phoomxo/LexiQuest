# UAT Script — Adventure Motivation Mode

**Document ID:** LQ-AMM-UAT-001
**Version:** 1.0
**Status:** Draft for Product Owner/UAT Lead Review
**Date:** 2026-09-01
**References:** `AMM-AUDIT-001`, TOR, SRS, SDS, WBS, UI/UX Spec และ Test Plan v1.0
**Baseline:** commit `99f7fb21`, Drift schema v22
**Release warning:** baseline ปัจจุบันมี 3,202 tests ผ่าน / 15 tests ไม่ผ่าน จึงใช้เอกสารนี้ทำ dry run ได้ แต่ห้าม sign-off Pilot/Production จน `G0B` และ `BG-01–BG-12` ผ่าน

## 1. วัตถุประสงค์

UAT ชุดนี้ใช้พิสูจน์กับผู้ใช้และเจ้าของระบบว่า Adventure Motivation Mode:

1. ช่วยกระตุ้นแรงจูงใจโดยไม่ทำให้การเรียนซับซ้อนขึ้น;
2. เป็นเพียงทางนำเสนอทางเลือก ไม่แทนที่ Standard และไม่เปลี่ยน 8/44;
3. ใช้คำศัพท์ บทเรียน SRS, Mastery, Quest, Streak, Achievement, XP และ Coins จาก authority เดิม;
4. ไม่ลงโทษ ไม่ทำให้อับอาย และไม่หักรางวัลเมื่อตอบผิด หยุดพัก หรือเกิด technical failure;
5. ทำงานต่อได้เมื่อ offline, asset เสีย, app ปิดกลางคัน หรือ feature ถูกปิดฉุกเฉิน;
6. แยก preference, feature availability, assignment และ consent ออกจากกัน;
7. ไม่สร้างข้อมูลวิจัยสำหรับ non-participant;
8. ใช้งานได้กับภาษาไทย screen reader, text 200%, high contrast และ reduced motion;
9. รักษาแบรนด์ `LexiQuest` และไม่มีข้อความ “เก่งศัพท์” กลับเข้ามา;
10. มีหลักฐานตรวจย้อนกลับถึง Requirement, WBS และ Test Case ได้

## 2. ขอบเขตและรอบ UAT

| รอบ | ผู้ใช้ | Build state | ใช้ทำอะไร | อนุญาตให้ sign-off อะไร |
|---|---|---|---|---|
| Dry run | Product/UX/QA ภายใน | Hidden/local fixture | ตรวจ script, copy, flow และ fixture | แก้เอกสาร/defect เท่านั้น |
| Internal UAT | Staff allowlist | Limited | UAT-001–024 และ 030–032 | MS-07/Internal acceptance |
| Consented Pilot UAT | ผู้เข้าร่วมที่ผ่าน protocol | Pilot | UAT-001–032 รวม research cases | MS-08/Pilot decision |
| Post-release smoke | eligible production sample | Enabled แบบควบคุม | critical path และ rollback | Increment continue/hold |

UAT ไม่แทน automated test, rules emulator, migration test, security/dependency gate หรือ accessibility certification

## 3. บทบาท

| Role | หน้าที่ |
|---|---|
| Product Owner | อนุมัติความหมายทางผลิตภัณฑ์และผลตรวจรับสุดท้าย |
| UAT Lead | ควบคุม build/fixture, มอบหมาย script, ตรวจ evidence และ defect |
| Learner representative | ทำงานโดยไม่รับคำใบ้จากผู้สังเกตและตอบ comprehension questions |
| Accessibility participant/reviewer | ตรวจ screen reader, keyboard, text scaling, contrast และ motion |
| QA recorder | บันทึก actual result, timestamp, screenshot/log แบบไม่ติดข้อมูลส่วนบุคคล |
| Tech Lead | แยก product defect ออกจาก fixture/environment defect และยืนยัน authority invariant |
| Research/Privacy Owner | อนุมัติเฉพาะ UAT-025–029 และตรวจ consent/assignment/zero-row evidence |
| Release Owner | ทำ emergency-off rehearsal และ rollout/rollback record |

ผู้พัฒนาเจ้าของ implementation ไม่ควรเป็นผู้ sign-off script ของตนเองเพียงคนเดียว

## 4. สภาพแวดล้อมและชุดข้อมูล

### 4.1 Build identity ที่ต้องบันทึก

- commit SHA, app version/build number และ platform;
- Flutter/Dart version;
- schema, feature-registry, catalog, policy และ content revisions;
- local/cloud rules revision;
- experiment/protocol/instrument/form versions เมื่อใช้ research;
- device model, OS, locale, text scale, theme, motion/audio/network state;
- owner fixture ID แบบ pseudonymous ห้ามใช้ชื่อจริงในหลักฐาน

### 4.2 Owner fixtures

| Fixture | สถานะ |
|---|---|
| U-A | owner ใหม่ ไม่มี due item ไม่มี accepted session |
| U-B | owner มี due review, new work และ saved item |
| U-C | owner มี accepted session ที่ resume ได้ |
| U-D | guest มี progress/preference สำหรับทดสอบ upgrade |
| U-E | owner มี equipped cosmetic และ canonical reward receipts |
| U-R1 | consented participant, assigned Adventure, active run |
| U-R2 | consented participant, assigned Standard, active run |
| U-NP | non-participant ไม่มี consent/run |
| U-X | owner อื่นสำหรับตรวจ isolation |

### 4.3 Content fixtures

- mission A: มีอย่างน้อย 8 items เพื่อพิสูจน์ repair spacing 3–5;
- mission B: มีเพียง 1–2 items หลังคำตอบผิด เพื่อพิสูจน์ no padding;
- mission C: local content/asset revision verified สำหรับ offline;
- bundle Q: checksum ผิดสำหรับ quarantine/repair;
- one assessment fixture ที่ต้องไม่สร้าง reward side effect;
- Thai/English locale parity fixture;
- canonical Standard/Adventure pair ที่ work IDs, modes, revisions และ policy เท่ากัน

## 5. Preconditions และ Stop Conditions

### 5.1 Preconditions ทุก script

1. UAT Lead ยืนยัน script ID, build และ fixture ก่อนเริ่ม;
2. reset เฉพาะ owner fixture ที่กำหนด ห้ามล้างข้อมูล owner อื่น;
3. เริ่ม screen recording/screenshot เมื่อได้รับอนุญาต;
4. เก็บ database/event evidence ผ่าน approved diagnostic view ไม่เปิด raw answer/research payload;
5. tester ต้องไม่เห็น expected result จนทำ action เสร็จ หากเป็น usability/comprehension test;
6. research scripts ต้องมี ethics/guardian/assent approval ที่ applicable ก่อนเสมอ

### 5.2 หยุดรอบทันทีเมื่อพบ

- learning evidence สูญหายหรือถูกบันทึกซ้ำ;
- XP, Coins, Quest, Streak, Achievement หรือ Reward ถูก grant โดย Adventure โดยตรง/ซ้ำ;
- mixed-owner data หรือ owner U-X เปลี่ยน;
- non-participant มี research row/event/outbox;
- Standard fallback เข้าไม่ได้;
- crash, retry loop, database corruption หรือ deletion กระทบ global content;
- ข้อความตำหนิ/ลงโทษผู้เรียนหรือ false mastery claim;
- consent withdrawal แล้วยังเกิด research enqueue ใหม่

## 6. แบบบันทึกผลต่อ Script

ในช่อง Trace ใช้ `FR/DATA/UI/NFR/BR` เป็นคำย่อของ `AMM-FR/AMM-DATA/AMM-UI/AMM-NFR/AMM-BR`; Test Case ใช้ ID เต็ม `TC-*`

| Field | ค่า |
|---|---|
| Script ID / attempt |  |
| Tester / observer |  |
| Build / commit / device |  |
| Owner/content fixture |  |
| Start–end time |  |
| Actual result |  |
| Requirement/Test IDs |  |
| Evidence links |  |
| Defect IDs/severity |  |
| Result | Pass / Fail / Blocked / Not Run |
| Retest result/date |  |
| Tester + UAT Lead signature |  |

`Blocked` ใช้เมื่อ environment/fixture ใช้ไม่ได้และไม่ถือเป็น Pass; ต้องมี blocker owner และวันนัดใหม่

## 7. UAT Scripts — Entry, Choice และ Fallback

### UAT-001 — Feature ปิดแล้ว Standard ไม่เปลี่ยน

**Trace:** FR-001–004, NFR-001, BR-018; WBS 0.19; TC-ENT-001/002, TC-LRN-015

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด build ที่ Adventure hidden/disabled ด้วย U-A | เข้าประสบการณ์ Standard เดิม ไม่มี Adventure entry |
| 2 | เปิด Vocabulary, Review/Mastery และ Profile ตามปกติ | route/action สำคัญทำงานเหมือน baseline |
| 3 | ลองเปิด stale/direct Adventure route จาก test harness | ถูกส่งไป Standard อย่างปลอดภัย มี bounded fallback reason |
| 4 | ตรวจ diagnostic/write summary กับ QA | ไม่มี Adventure row, learning write หรือ reward write |

**Pass:** ผู้ใช้ทำงาน Standard ต่อได้โดยไม่รู้สึกว่าฟีเจอร์ใหม่รบกวน

### UAT-002 — เลือก Adventure แบบ session-local และกลับ Standard

**Trace:** FR-006/010/017, BR-012; WBS 1.9/1.11; TC-ENT-004/005, TC-UX-001

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด Today ด้วย U-A ใน Internal build | เห็น choice ที่อธิบาย Adventure และ Standard ชัดเจน |
| 2 | เลือก Adventure โดยไม่เลือก “จำการตั้งค่า” | Adventure Home แสดง mission เด่นหนึ่งรายการ |
| 3 | สลับ Map → List → Map | node/order/selection/action ไม่เปลี่ยน |
| 4 | กด “ใช้แบบมาตรฐาน” ที่ไม่ต้อง scroll | กลับ Standard ใน Today destination เดิม ไม่ stack home ซ้ำ |
| 5 | ปิดและเปิดแอป | Phase 1 กลับค่าเริ่มต้นตาม session policy; assignment ไม่เปลี่ยน |

### UAT-003 — จำ preference โดยไม่เปลี่ยนสิทธิ์หรือ cohort

**Trace:** FR-005–008/076–077, DATA-002–006, BR-012–015; WBS 3.1–3.4; TC-DAT-004–008

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | UAT Lead ยืนยัน feature eligible และ assignment ของ U-B | บันทึกค่าเริ่มต้นไว้ใน evidence sheet |
| 2 | ผู้ใช้เลือก Adventure และ “จำการตั้งค่า” | save ผ่าน preference use case; ไม่มี feature/assignment mutation |
| 3 | restart | Adventure เป็น presentation ที่เลือกไว้เมื่อ feature/dependency ยังพร้อม |
| 4 | Release Owner ปิด feature แล้วเปิดแอป | Standard แสดง แม้ preference ยังเป็น Adventure |
| 5 | เปิด feature กลับหลัง review | preference ใช้ได้อีก; assignment เดิมไม่ถูก rewrite |

### UAT-004 — Missing/corrupt dependency ต้อง fallback ไม่วนซ้ำ

**Trace:** FR-014/024/033/089/096, NFR-006; WBS 1.10; TC-ENT-003/006, TC-JRN-010/011

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด fixture ที่ catalog/required dependency หาย | Standard แสดงทันทีหรือมี action กลับ Standard ที่ชัดเจน |
| 2 | กด retry หนึ่งครั้ง | retry เป็น bounded single-flight ไม่มี repeated dialog/spinner loop |
| 3 | เปิด diagnostics กับ QA | มี bounded reason code ไม่มี answer/direct identifier/raw story |
| 4 | เปิด Vocabulary/Review ใน Standard | canonical learning ยังใช้งานได้ |

## 8. UAT Scripts — Journey และ Learning

### UAT-005 — Primary mission, Resume และ Review priority

**Trace:** FR-013/026–035, BR-002/003; WBS 1.2–1.5; TC-JRN-003–005

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิดด้วย U-C | Resume เป็น primary mission ก่อน new mission |
| 2 | จบ/ปิด accepted session ตาม fixture แล้วเปิด U-B | due/review มาก่อน new work ตาม policy เดิม |
| 3 | เปิด mission sheet | แสดง reason, duration และ source freshness ที่เข้าใจได้ |
| 4 | สลับ List | node/action meaning เท่ากับ Map |
| 5 | refresh โดยข้อมูลไม่เปลี่ยน | node/order/state เหมือนเดิม; ไม่มี `adventure_progress` write |

### UAT-006 — Start mission เพียงครั้งเดียว

**Trace:** FR-015/039–045, NFR-005; WBS 1.4/1.5/2.2–2.5; TC-LRN-001–005

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด mission A และอ่าน reason/duration | primary CTA มีสถานะพร้อมและ semantic ชัดเจน |
| 2 | แตะ Start เร็วสองครั้ง | CTA disabled/loading; accepted session เพียงหนึ่ง |
| 3 | เริ่มเรียน | ใช้ Unified Lesson Shell เดิม ไม่เห็น shell ซ้อนหรือ duplicate route |
| 4 | QA เทียบ Standard fixture | work IDs/revisions/modes/policy และ canonical command เท่ากัน |
| 5 | ตรวจ write count | session/evidence ไม่มี duplicate และไม่มี Adventure field ใน EvidenceContext |

### UAT-007 — ตอบผิดแล้วซ่อมความจำหลัง 3–5 ข้อ

**Trace:** FR-060/063/066–071, BR-007/009/010; WBS 2.6/2.7; TC-LRN-009, TC-REC-001/003/004

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ใน mission A ตอบ item เป้าหมายผิด | incorrect evidence commit; feedback ให้กำลังใจ ไม่มีการหักคะแนน/หัวใจ |
| 2 | ทำข้อต่อไปและนับ intervening eligible items | item ไม่เด้งซ้ำทันที |
| 3 | หลัง 3–5 items | item กลับมา repair หนึ่งครั้งด้วย support level ที่เหมาะสม |
| 4 | ตอบ repair ผิดอีก | ไม่มีรอบซ่อมที่สองใน session; แจ้งว่าจะนำไปทบทวน |
| 5 | เปิด Result/Review | need แสดงแยกจาก prior completion และ Review/SRS เป็นเจ้าของนัดครั้งต่อไป |

### UAT-008 — เหลือข้อน้อยกว่า 3 ต้องไม่ยืด session

**Trace:** FR-067–070, BR-009; WBS 2.6/2.7; TC-REC-002/014

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ใน mission B ตอบ item เป้าหมายผิด | feedback ปกติและ incorrect evidence commit |
| 2 | ทำ items ที่เหลือ | ระบบไม่สร้าง filler/คำถามซ้ำเพื่อให้ครบระยะ 3 |
| 3 | จบ session | Result บอกว่ามีคำรอทบทวนโดยไม่กล่าวโทษ |
| 4 | กด action ทบทวน | ไป canonical Review/SRS ไม่ใช่ Adventure-owned queue |

### UAT-009 — Hint, Skip และ Technical Failure ต้องไม่ถูกนับเหมือนกัน

**Trace:** FR-053/060/072, BR-007/009/010; WBS 2.3/2.10; TC-LRN-008/010/011, TC-REC-006

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ใช้ hint แล้วตอบถูก | แสดง guided practice ไม่ claim independent mastery |
| 2 | กด Skip ในข้อถัดไป | แสดงสถานะ skip ไม่ปลอมเป็น incorrect หรือ technical failure |
| 3 | QA เปิด controlled evidence-write failure | completion/reward freeze และมี Retry ที่ไม่โทษผู้ใช้ |
| 4 | กด Retry | exact captured identity ถูกใช้และ commit ครั้งเดียว |
| 5 | ตรวจ Result | Learning/Effort/Engagement สอดคล้องกับ typed states |

### UAT-010 — ปิดแอปกลางคันและ resume โดยไม่ซ้ำ

**Trace:** FR-032/045/055/074, NFR-003/007; WBS 2.10/2.11; TC-LRN-013, TC-REC-009

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เริ่ม mission และตอบอย่างน้อย 2 ข้อ | accepted session/evidence receipt มีอยู่ |
| 2 | ปิดแอปหลัง submit ตาม breakpoint ที่ QA กำหนด | ไม่มี graceful completion ที่สร้างผลเพิ่ม |
| 3 | เปิดแอป | Resume เป็น primary action |
| 4 | ทำ session ต่อจนจบ | ข้อที่ commit แล้วไม่สร้าง answer/reward ซ้ำ |
| 5 | QA ตรวจ identity/ledger | duplicate learning/reward count = 0 |

## 9. UAT Scripts — Result, Motivation และ Companion

### UAT-011 — Result แยก Learning, Effort, Engagement

**Trace:** FR-064/065, UI-013, NFR-025, BR-016; WBS 2.8/2.9; TC-REC-012/013, TC-UX-012

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | จบ fixture ที่มี correct, incorrect, hint และ skip | Result มี 3 section ชื่อ/ความหมายแยกกัน |
| 2 | ให้ tester อธิบายแต่ละ section ด้วยคำตนเอง | แยก “เรียนรู้อะไร”, “ลงแรงเท่าไร”, “ทำอะไรในแอป” ได้ |
| 3 | ตรวจ reward area | อยู่แยกและมาจาก canonical receipt; ไม่มีคะแนนรวมใหม่ |
| 4 | ตรวจ wrong item copy | เป็น “ควรทบทวน/กำลังฝึก” ไม่ลด prior mastery |

### UAT-012 — Reward pending แล้ว refresh จาก authority เดิม

**Trace:** FR-016/049–056/073, BR-004–008/011; WBS 3.5–3.7; TC-REC-007–011

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | QA ชะลอ canonical side-effect reconciliation หลัง learning commit | Result แสดง Learning สำเร็จและ Reward pending |
| 2 | อยู่บน Result/refresh | Adventure ไม่เรียก grant และไม่สร้างตัวเลขคาดเดา |
| 3 | ปล่อย reconciler เดิมทำงาน | Quest/Streak/Achievement/Reward receipts แสดงถูกต้อง |
| 4 | refresh/restart ซ้ำ | ไม่มี XP/Coin/quest/unlock ซ้ำ |
| 5 | เปิด map/story แล้วออก | ledger ไม่เปลี่ยนจากการดู presentation |

### UAT-013 — Companion ใช้ scripted supportive reaction

**Trace:** FR-057–063, UI-010–012; WBS 3.8–3.11; TC-UX-008–011

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ใช้ U-E ที่มี equipped cosmetic | Companion แสดง cosmetic จาก ownership เดิม |
| 2 | ทำ correct/incorrect/hint/skip/return/completion | reaction เป็นข้อความจาก catalog ที่เหมาะกับ state |
| 3 | ปิดเสียง | มี text/caption equivalent ครบ |
| 4 | เปิด reduced motion | animation เปลี่ยนเป็น static/zero-duration โดยไม่เสียความหมาย |
| 5 | ตรวจ copy | ไม่มี AI free text, relationship score, punishment หรือ false mastery claim |

### UAT-014 — Brand และภาษา

**Trace:** UI-001/002/012/013, FR-018/021/024; WBS 0.17/3.11; TC-JRN-009, TC-UX-014/015

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เดินทุก required screen ภาษาไทย | ใช้ชื่อ LexiQuest และศัพท์ navigation glossary สม่ำเสมอ |
| 2 | ค้น/สังเกตทุก surface | ไม่มีข้อความ “เก่งศัพท์” |
| 3 | เปลี่ยน English locale | label/action สำคัญครบ ไม่มี key โผล่บน UI |
| 4 | เปิด technical failure | ข้อความบอก action ที่ทำได้และไม่กล่าวโทษผู้ใช้ |

## 10. UAT Scripts — Accessibility และ Responsive UX

### UAT-015 — Screen reader และ List parity

**Trace:** UI-004–007, NFR-015/016; WBS 1.8/1.12/5.4; TC-UX-002–004

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด screen reader ที่ Adventure Home | focus เริ่ม AppBar แล้ว primary mission ตามลำดับ |
| 2 | traverse Map | decoration ไม่ถูกอ่าน; node อ่าน label/state/action ไม่ซ้ำ |
| 3 | สลับ List และทำ action เดิม | node, order, state, reason และ action เท่ากับ Map |
| 4 | ไป Standard switch แล้วกลับ | เข้าถึงได้ ไม่ติด focus trap และ focus restore สมเหตุผล |

### UAT-016 — Text 200%, narrow phone และ touch target

**Trace:** UI-003/008/009, NFR-017; WBS 1.7–1.12; TC-UX-005

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ตั้ง text scale 200% บนอุปกรณ์แคบ | shell reflow/list-first โดยไม่ clip essential content |
| 2 | เปิด mission sheet | reason, duration, CTA และ Standard action อ่านครบ |
| 3 | เปิด Result/research prompt | section/Skip/consent link ไม่ซ้อนหรือตกขอบ |
| 4 | ตรวจ touch target ด้วย tooling | interactive target ≥48×48 logical pixels |

### UAT-017 — Dark, high contrast, motion และ no-audio

**Trace:** UI-001/004/010/011, NFR-017/018; WBS 5.4; TC-UX-006–009

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด dark theme | สี derive จาก M3Theme อ่านได้ทุก state |
| 2 | เปิด high contrast | locked/current/completed/error แยกด้วย icon/shape/text ไม่พึ่งสี |
| 3 | เปิด reduced motion แล้วเปลี่ยน screen/reaction | ไม่มี essential meaning สูญหายหรือ motion บังคับ |
| 4 | ปิด audio | caption/transcript/no-audio alternative ครบ |

## 11. UAT Scripts — Offline, Corruption และ Lifecycle

### UAT-018 — Offline mission ด้วย verified local content

**Trace:** FR-091, NFR-006/014; WBS 2.13/5.5; TC-OPS-005–007

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | verify mission C ขณะ online แล้วเปิด airplane mode | entry ใช้ได้เมื่อ required revisions อยู่ local ครบ |
| 2 | เริ่มและจบ mission | canonical learning commit local; network ไม่เป็น prerequisite |
| 3 | restart ยัง offline | accepted session/result recover ได้ |
| 4 | เปิด network | sync/reconciliation bounded; ไม่มี duplicate work/reward |

### UAT-019 — Corrupt bundle: quarantine, repair, remove

**Trace:** FR-022–024/092/093, NFR-006; WBS 0.18/5.5; TC-JRN-010–012, TC-OPS-008

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ติดตั้ง bundle Q แล้วเปิด Adventure | checksum mismatch ถูก quarantine; Standard พร้อมใช้ |
| 2 | เปิดซ้ำ 3 ครั้ง | ไม่มี crash/retry loop หรือ repeated destructive action |
| 3 | กด Repair ตาม test setup | bundle valid กลับมาใช้ได้เมื่อ verify ผ่าน |
| 4 | Remove asset bundle | learning evidence/progress เดิมยังอยู่; Adventure fallback Standard |

### UAT-020 — Guest upgrade, export และ owner isolation

**Trace:** DATA-008–012, NFR-005/023; WBS 3.4/4.11/4.12/5.6; TC-DAT-009–014

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ใช้ U-D ทำ progress และตั้ง preference | guest state เกิดตาม policy |
| 2 | upgrade ไป account ที่กำหนด | preference/progress ย้ายหรือ merge ครั้งเดียวตาม conflict policy |
| 3 | export owner ที่ upgrade | archive มี preference และ axes ที่มีสิทธิ์ครบ ไม่มี owner U-X |
| 4 | เปรียบ owner U-X ก่อน/หลัง | byte/value-equivalent สำหรับ scoped records |
| 5 | restart/sync replay | ไม่มี duplicate response/research identity |

### UAT-021 — Delete owner และ global content preservation

**Trace:** DATA-009/012, NFR-023; WBS 4.11/4.12; TC-DAT-010–012

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | QA บันทึก manifest count ของ test owner และ global content count | baseline evidence พร้อม |
| 2 | สั่ง delete test owner ผ่าน approved flow | owner-scoped rows ถูกลบตาม manifest/order |
| 3 | เปิด owner U-X | ข้อมูลไม่เปลี่ยน |
| 4 | ตรวจ packaged/global content | manifests/packs/items/download definitions ยังอยู่ |
| 5 | เปิดแอปด้วย owner ใหม่ | ทำงานได้ ไม่มี orphan/foreign state |

### UAT-022 — Emergency-off ก่อนและระหว่าง session

**Trace:** FR-009/075/094/095, NFR-004; WBS 2.12/5.7; TC-ENT-007–009, TC-OPS-011/012

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ปิด feature ก่อน Start | new Adventure start ถูกบล็อกและ Standard แสดง |
| 2 | เปิดใหม่ เริ่ม accepted session แล้ว emergency-off | accepted learning ไม่ถูกลบทิ้งหรือให้ penalty |
| 3 | ทำ action ตาม safe lifecycle | session close/retire ผ่าน lifecycle เดิม; ไม่มี duplicate evidence |
| 4 | กลับ Home | Standard เป็น presentation; new Adventure blocked |
| 5 | re-enable หลัง review | compatible preference/assignment คงเดิม ไม่มี down migration |

### UAT-023 — Owner switch ระหว่าง async work

**Trace:** FR-040, NFR-005; WBS 2.11/5.6; TC-ENT-012, TC-OPS-010

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เริ่ม load/compose ด้วย U-B แล้วค้าง controlled future | loading state ทำงาน |
| 2 | switch ไป U-X ก่อน future resolve | UI เปลี่ยน owner อย่างปลอดภัย |
| 3 | ปล่อย stale result ของ U-B | result ถูก discard ไม่แสดง/เขียนให้ U-X |
| 4 | ตรวจทั้งสอง owner | ไม่มี mixed-owner mutation |

### UAT-024 — Assessment isolation

**Trace:** FR-047/052, BR-006; WBS 3.5; TC-LRN-014

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด assessment fixture ผ่าน route ที่กำหนด | ไม่ถูก wrap เป็น reward-granting Adventure mission |
| 2 | ทำ assessment | scoring/evidence ใช้ assessment authority เดิม |
| 3 | เปิด Adventure Result/ledger diagnostic | ไม่มี XP/Coin/Quest/Streak/Achievement จาก assessment |
| 4 | กลับ Today | presentation ทำงานปกติ ไม่มี narrative claim ว่า mastery สำเร็จ |

## 12. UAT Scripts — Research, Consent และ Measurement

ส่วนนี้รันได้เฉพาะเมื่อ `MS-06`, ethics/guardian/assent ที่ applicable และ Research/Privacy Owner อนุมัติแล้ว

### UAT-025 — Non-participant ต้องเป็น zero-row

**Trace:** FR-048/078/084, NFR-020/021; WBS 4.5/4.8; TC-ENT-011, TC-RSH-001/005

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ยืนยัน U-NP ไม่มี consent/run | baseline research count = 0 |
| 2 | เปิด Adventure, เริ่มและจบ mission | product ใช้งานได้เต็มตาม feature |
| 3 | สลับ Standard แล้วกลับ Adventure | preference/presentation ทำงานโดยไม่สร้าง research |
| 4 | ตรวจ local rows, outbox และ server fixture | exposure/measurement/origin persisted row = 0 |

### UAT-026 — Consent/assignment/run gate และ stable assignment

**Trace:** FR-076–080, BR-012–015; WBS 4.4/4.5; TC-RSH-002–004/006

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ทดสอบ consent-only fixture | ไม่มี research row เพราะ assignment/run ไม่ครบ |
| 2 | ทดสอบ assignment-only fixture | ไม่มี research row เพราะ consent ไม่ครบ |
| 3 | เปิด U-R1 ที่ gate ครบและเริ่ม mission | event หนึ่งรายการมี version pins/aggregate/correlation ตาม contract |
| 4 | สลับ Standard | assignment ยัง Adventure; crossover เป็น secondary metadata เท่านั้น |
| 5 | restart/replay | assignment ไม่ถูก rewrite และ event identity ไม่ซ้ำ |

### UAT-027 — Research prompt, Skip และ bounded response

**Trace:** FR-079–083/088, UI-014; WBS 4.1/4.6/4.7; TC-RSH-010–013, TC-UX-013

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | พยายาม trigger prompt กลางคำถาม | prompt ไม่ขวาง/ถูก defer ไป natural breakpoint |
| 2 | เปิด prompt ที่ breakpoint | วัตถุประสงค์สั้น ชัด มี Skip และ consent details |
| 3 | กด Skip ใน run แรก | learning/reward/access ไม่เปลี่ยน; run status ตาม protocol |
| 4 | ใน run แยกเลือก bounded response | response code ที่อนุญาตบันทึกหนึ่งครั้ง ไม่มี free text |
| 5 | กด submit ซ้ำ | idempotent; response ไม่ซ้ำ |

### UAT-028 — Withdraw consent หยุด enqueue ทันที

**Trace:** FR-085, DATA-012, NFR-022; WBS 4.5/4.12; TC-RSH-008/009

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด prompt/event breakpoint ด้วย U-R1 | eligible state ยืนยันแล้ว |
| 2 | withdraw consent ผ่าน approved flow ก่อน submit/enqueue | effective gate เปลี่ยนก่อน operation ถัดไป |
| 3 | ลอง submit prompt/trigger exposure | rejected/suppressed โดย learning result ไม่เสีย |
| 4 | ตรวจ local/outbox/server หลัง cutoff | ไม่มี research record ใหม่หลัง withdrawal timestamp |

### UAT-029 — Export และความเข้าใจแกนผลลัพธ์วิจัย

**Trace:** FR-086/087, DATA-011/012; WBS 4.12/4.13; TC-RSH-014/015

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | export consented fixture ที่มี crossover | package แยก Outcome/Learning/Effort/Engagement/Motivation |
| 2 | ให้ Research Owner reconstruct assignment | intention-to-treat ใช้ assignment เดิม |
| 3 | ตรวจ adherence/crossover | อยู่ใน secondary metadata ไม่แก้ cohort |
| 4 | ตรวจ privacy/version | ไม่มี raw answer/free text; version pins ครบ |

## 13. UAT Scripts — Operations และ Release

### UAT-030 — Performance perception และ no forced timer

**Trace:** NFR-008–013/019; WBS 5.3; TC-OPS-001–004

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด Adventure จาก warm local state 5 รอบ | ผู้ใช้ไม่พบ freeze; QA เก็บ p95 ตาม certified method |
| 2 | สลับ Map/List ต่อเนื่อง | interaction ลื่น ไม่มี long task ที่มองเห็นได้ |
| 3 | Start เทียบ Standard fixture | ไม่มี waiting step เพิ่มที่ทำให้ flow สะดุด; budget ผ่าน |
| 4 | หยุดอ่านหน้าจอนานตามต้องการ | ไม่มี forced timeout/heart/life loss |

### UAT-031 — Diagnostic privacy และ unknown payload

**Trace:** FR-089/090/096, NFR-024/027/028; WBS 5.5/6.2; TC-OPS-013/014

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | trigger entry, asset และ projection failure fixtures | diagnostic มี bounded code/counter |
| 2 | Privacy Owner inspect payload | ไม่มี answer, raw response, story copy หรือ direct identifier ที่ไม่จำเป็น |
| 3 | replay unknown enum/schema/event fixture | fail closed; compatible state เดิมไม่ถูก overwrite |
| 4 | เปิด Standard | ทำงานต่อได้ |

### UAT-032 — Release smoke และ emergency decision

**Trace:** FR-094/095, NFR-032/033; WBS 5.7–5.13/6.1–6.6; TC-OPS-015

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | UAT Lead ตรวจ BG-01–BG-12 และ G0B | ทุก gate มี fresh evidence; ไม่มี historical result แทน current |
| 2 | ทำ smoke: entry → mission → answer → result → Standard | critical path ผ่านและ authority receipt ถูกต้อง |
| 3 | ทำ nonparticipant zero-row smoke | count = 0 |
| 4 | Release Owner ทำ emergency-off | new start blocked, accepted state safe, Standard restored |
| 5 | คณะตัดสิน Continue/Hold/Rollback | decision, threshold, owner และ next review ถูกบันทึก |

## 14. คำถามวัดความเข้าใจและแรงจูงใจ

ถามหลังผู้ใช้ทำงานเอง ห้ามชี้นำคำตอบ:

1. “หน้าจอนี้แนะนำให้คุณทำอะไรต่อ และเพราะอะไร?”
2. “ถ้าไม่อยากใช้โหมดผจญภัย คุณจะกลับแบบเดิมตรงไหน?”
3. “หลังตอบผิด คุณเข้าใจว่าจะเกิดอะไรต่อกับคำนั้น?”
4. “สามส่วนบนหน้าผลลัพธ์หมายถึงอะไร ต่างกันอย่างไร?”
5. “คุณคิดว่าการเปิดแผนที่หรือดูเรื่องราวได้ XP/Coins หรือไม่?”
6. “คุณรู้สึกว่าข้อความใดกดดัน ตำหนิ หรือทำให้ไม่อยากเรียนต่อหรือไม่?”
7. “คุณอยากเริ่ม mission ต่อหรือกลับมาภายหลัง เพราะอะไร?”
8. “เมื่อระบบมีปัญหา คุณรู้หรือไม่ว่าควร Retry หรือใช้ Standard?”
9. สำหรับ research prompt: “คุณเข้าใจหรือไม่ว่าข้อมูลนี้เก็บเพื่ออะไร และ Skip ได้หรือไม่?”

### เกณฑ์ comprehension

- อย่างน้อย 90% หา primary mission และ Standard switch ได้โดยไม่ช่วย;
- อย่างน้อย 90% อธิบาย wrong-answer recovery ว่า “ฝึก/ทบทวนอีก” ไม่ใช่ “ถูกลงโทษ”;
- อย่างน้อย 85% แยก Learning/Effort/Engagement ได้หลังอ่าน copy ครั้งเดียว;
- 100% ของ research participants ระบุได้ว่า Skip/withdraw ได้และไม่กระทบสิทธิ์เรียน;
- shame/coercion/false mastery finding ที่ยืนยันแล้วต้องเป็นศูนย์ก่อน Pilot

ค่าเหล่านี้เป็น acceptance threshold ของ UAT ไม่ใช่ผลวิจัยประสิทธิผล และห้ามตีความแทน protocol

## 15. Defect และ Decision Log

| Defect ID | UAT/Step | Severity | Actual/Expected | Evidence | Owner | Target | Retest | Disposition |
|---|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |  |

Severity:

- **S0 Stop:** data loss/duplication, owner leak, consent violation, direct reward grant, Standard unavailable, corruption/retry loop;
- **S1 Critical:** core mission unusable, wrong result meaning, critical accessibility blocker, emergency-off failure;
- **S2 Major:** recoverable main-flow defect or widespread confusing copy;
- **S3 Minor:** cosmetic/nonblocking issue

S0/S1 ต้องแก้และ rerun affected scripts + regression ก่อน sign-off; S2 ต้องมี owner/date/accepted risk; S3 เข้า backlog ได้เมื่อไม่กระทบ comprehension/accessibility

## 16. Exit Criteria และ Sign-off

### 16.1 Internal acceptance

- UAT-001–024 และ 030–032 ผ่านบน required device/accessibility matrix;
- ไม่มี S0/S1 เปิดค้าง;
- Standard fallback, restart, offline และ emergency-off ผ่าน;
- baseline `G0A` ผ่าน และไม่มี unclassified failure ใน touched foundation;
- Requirement/Test/UAT links ใน RTM ตรงกับ build

### 16.2 Pilot acceptance

- Internal acceptance ผ่าน;
- `G0B` และ `BG-01–BG-12` ผ่านด้วย fresh evidence;
- UAT-025–029 ผ่านภายใต้ approved protocol;
- nonparticipant zero-row และ withdrawal cutoff = 100%;
- comprehension thresholds ผ่าน;
- Research/Privacy, Accessibility, QA, Tech และ Product sign-off ครบ

### 16.3 Sign-off table

| Role | Decision | Name | Date | Build/evidence | Conditions |
|---|---|---|---|---|---|
| Learner representative | Accept / Reject |  |  |  |  |
| Accessibility reviewer | Accept / Reject |  |  |  |  |
| UAT Lead | Accept / Reject |  |  |  |  |
| QA Lead | Accept / Reject |  |  |  |  |
| Tech Lead | Accept / Reject |  |  |  |  |
| Research/Privacy Owner | Accept / N/A / Reject |  |  |  |  |
| Product Owner | Accept / Reject |  |  |  |  |
| Release Owner | Continue / Hold / Rollback |  |  |  |  |

การลงชื่อใน Draft หรือ build ที่ baseline gates ยังไม่ผ่านไม่ถือเป็น Pilot/Production approval
