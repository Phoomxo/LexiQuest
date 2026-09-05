# UAT Script — Adventure Motivation Mode

**Document ID:** LQ-AMM-UAT-001
**Version:** 1.3
**Status:** Product engineering preflight ready; research/Pair prerequisites and external acceptance pending
**Date:** 2026-09-04; evidence update 2026-09-05
**References:** `AMM-AUDIT-001 v1.0`; SDS v1.3; TOR, SRS, WBS, UI/UX, ADR, MDS และ Test Plan v1.2
**Build baseline:** Adventure product source `f8a5f8bb` + hardening `703aabe4`; performance rehearsal source `85b17755`; local verification evidence `3c698cdd`; Drift schema v23; Pair Matching design source closure `f56e2eb`
**Release warning:** Android/shared local BG-01–BG-12 ผ่านโดยไม่มี unclassified failure และ source-gated Android host-GPU emulator performance rehearsal ผ่านทุก budget แต่ยังเป็น `not_certified`; ห้าม sign-off Pilot/Production จนกว่าจะมี physical-device accessibility/performance certification, participant UAT, approved research package และ signed MS-08A/MS-08B decision ตาม applicability

## 1. วัตถุประสงค์

UAT ชุดนี้ใช้พิสูจน์กับผู้ใช้และเจ้าของระบบว่า Adventure Motivation Mode:

1. ช่วยกระตุ้นแรงจูงใจโดยไม่ทำให้การเรียนซับซ้อนขึ้น;
2. เป็นเพียงทางนำเสนอทางเลือก ไม่แทนที่ Standard และไม่เปลี่ยน 8/44;
3. ใช้คำศัพท์ บทเรียน SRS, Mastery, Quest, Streak, Achievement, XP และ Coins จาก authority เดิม;
4. ไม่ลงโทษ ไม่ทำให้อับอาย และไม่หักรางวัลเมื่อตอบผิด หยุดพัก หรือเกิด technical failure;
5. ทำงานต่อได้เมื่อ offline, asset เสีย, app ปิดกลางคัน หรือ feature ถูกปิดฉุกเฉิน;
6. แยก preference, feature availability, assignment, raw consent/guardian/assent records และ participation permit ออกจากกัน;
7. ไม่สร้างข้อมูลวิจัยสำหรับ non-participant;
8. ใช้งานได้กับภาษาไทย screen reader, text 200%, high contrast และ reduced motion;
9. รักษาแบรนด์ `LexiQuest` และไม่มีข้อความ “เก่งศัพท์” กลับเข้ามา;
10. มีหลักฐานตรวจย้อนกลับถึง Requirement, WBS และ Test Case ได้;
11. แยก MS-08A Feasibility ออกจาก MS-08B Efficacy และ rollout adult/minor;
12. รับรอง Pair Matching Prototype ว่าใช้กิจกรรม f10 เดิม เป็นกิจกรรมย่อยใน Learn/Today Mission/Review/Adventure โดยไม่เพิ่มเมนูหลัก ไม่ให้รางวัลซ้ำ และไม่บิด SRS/Mastery

Controlled inventory รวม **50 UAT scripts (UAT-001–050)** โดยมี Android build
สำหรับ product engineering preflight ตามตารางด้านล่าง ส่วน research/permit,
MS-08B และ Pair scripts ยังติด prerequisite ของตนเอง จึงไม่ถือว่า UAT-001–038
พร้อมรันทั้งหมด ไม่มี script ใดถูกนับเป็น Pass จาก automated test แทนผู้ใช้จริง

### 1.1 Execution status snapshot

| Scope | Current status | Evidence/blocker |
|---|---|---|
| Android/shared engineering preflight | Ready | Product source `703aabe4`; BG-01–BG-12 local scope ผ่าน; 3,542 Flutter tests ผ่านทั้ง default/serial; source-gated host-GPU emulator rehearsal ที่ source `85b17755` ผ่าน 20/20 transitions ที่มีเฟรมจริง (p95 4.290 ms, max 7.031 ms) แต่ไม่ใช่ physical certification; APK SHA-256 `951F53BC5551E0DCDA631346F89015F31EDA52BAB01A48F9C9C2691BAFE7E64A`; ดู `docs/development/2026-09-04-adventure-motivation-checkpoint-6-local-verification.md` |
| Internal UAT UAT-001–024, 030–032 | Not Run | ต้องใช้ learner representatives ≥12, accessibility moderated sessions ≥4, certified profiles และผู้ sign-off ที่เป็นอิสระจากผู้พัฒนา |
| Research/permit UAT-025–037 | Blocked | ยังไม่มี approved protocol/instruments/response-code catalog/power plan/privacy-ethics package หรือ signed runtime permit fixtures; ระบบจงใจไม่มี research schema/capture |
| MS-08B UAT-038 | Blocked | ต้องรอ MS-08A, powered adult/minor samples, frozen windows และ approved ANCOVA/MI/tipping-point evidence |
| Pair UAT-039–050 | Engineering in progress; external UAT Not Run | ผู้ใช้อนุมัติแผน PM0–PM8 และ design B — Playful Quest แล้ว; PM0–PM3 ผ่าน local engineering checks และ PM4 กำลังพัฒนา ดู `docs/development/2026-09-05-pair-matching-engineering-status.md`; ยังไม่ถือว่า external UAT หรือ G4P sign-off ผ่าน |
| Defect/sign-off records | Empty by design | ยังไม่มี external attempt จึงไม่มี defect disposition หรือลายเซ็นที่สามารถบันทึกอย่างถูกต้อง |

APK ที่ตรวจ hash แล้วเก็บไว้ใน development worktree ที่
`build/deliverables/adventure-703aabe4-debug.apk` (ignored build artifact,
223,102,333 bytes) โดยยังใช้ feature configuration ที่ hidden/default-off
เช่นเดียวกับ source ที่ตรวจแล้ว รอบตรวจสถานะวันที่ 2026-09-05 ไม่พบอุปกรณ์
Android เชื่อมต่อจาก `adb devices -l`; ยังไม่มี physical-device session ใหม่

## 2. ขอบเขตและรอบ UAT

| รอบ | ผู้ใช้ | Build state | ใช้ทำอะไร | อนุญาตให้ sign-off อะไร |
|---|---|---|---|---|
| Dry run | Product/UX/QA ภายใน | Hidden/local fixture | ตรวจ script, copy, flow และ fixture | แก้เอกสาร/defect เท่านั้น |
| Internal UAT | Staff allowlist | Limited | UAT-001–024 และ 030–032 | MS-07/Internal acceptance |
| MS-08A Android Feasibility UAT | ผู้เข้าร่วม adult/minor ที่มี signed permit | Limited | UAT-001–037 ตาม applicability | MS-08A Limited/Revise/Stop |
| MS-08B decision rehearsal | คณะตัดสินและ frozen class evidence | Limited | UAT-038 | Expand/Remain Limited/Stop แยก class |
| Post-expansion Android smoke | class ที่ผ่าน MS-08B | Controlled | critical path, targeting and rollback | Increment continue/hold |
| Pair Matching Prototype UAT | learner/guardian/accessibility representatives | Prototype flag, no research treatment required | UAT-039–050 | Pair Matching Prototype Accept/Revise/Reject |

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
| Research/Privacy Owner | อนุมัติ UAT-025–038 ที่เกี่ยวข้องและตรวจ permit/consent/assent/opportunity/zero-row evidence |
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
| U-R1 | adult signed permit, assigned Adventure, active run |
| U-R2 | adult signed permit, assigned Standard, active run |
| U-M1 | minor permit with guardian permission + learner assent, assigned Adventure |
| U-M2 | minor permit missing/invalid guardian or assent evidence |
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

### 4.4 Android device/profile allocation

ไม่บังคับรันทุก script ซ้ำบนทุก profile แต่ทุก script ต้องผ่านอย่างน้อยหนึ่งครั้งบน mainstream Android และ critical subset ต้องผ่านตามตารางนี้:

| Profile | จำนวน session ขั้นต่ำ | Required UAT subset |
|---|---:|---|
| Mainstream Android phone | ครอบคลุม general learner ≥12 โดย minors ≥4 | UAT-001–038 ตาม applicability อย่างน้อยหนึ่ง pass ต่อ case |
| Small Android ≤360×640 + text 100%/200% | ≥1 | UAT-001/002/004/005/011/014/016/030/032–037 |
| Android tablet portrait/landscape | ≥1 | UAT-002/005/011/014/015/030/032 |
| TalkBack | ≥1 | UAT-002/004/005/007/011/015–017/019/032–037 |
| Android Switch Access/external keyboard | ≥1 | UAT-002/004/005/007/011/015–017/032–037 |
| Offline | ≥1 | UAT-004/005/010/018/022/032/033/035/037 |
| Corrupt asset | ≥1 | UAT-004/019/022/032 |

Accessibility participants รวมอย่างน้อย 4 moderated sessions ตาม MDS และหนึ่งคนอาจครอบคลุมหลาย profile ได้เมื่อบันทึก state/device แยกชัดเจน Research Prompt, guardian permission, learner assent, invalid permit และ withdrawal ต้องทำบน TalkBack, Switch Access/keyboard, text 200% และ offline profile ตาม UAT-037

## 5. Preconditions และ Stop Conditions

### 5.1 Preconditions ทุก script

1. UAT Lead ยืนยัน script ID, build และ fixture ก่อนเริ่ม;
2. reset เฉพาะ owner fixture ที่กำหนด ห้ามล้างข้อมูล owner อื่น;
3. เริ่ม screen recording/screenshot เมื่อได้รับอนุญาต;
4. เก็บ database/event evidence ผ่าน approved diagnostic view ไม่เปิด raw answer/research payload;
5. tester ต้องไม่เห็น expected result จนทำ action เสร็จ หากเป็น usability/comprehension test;
6. research scripts ต้องมี approved protocol และ signed permit fixture; minor ต้องมี guardian/assent runtime evidence ก่อนเสมอ

### 5.2 หยุดรอบทันทีเมื่อพบ

- learning evidence สูญหายหรือถูกบันทึกซ้ำ;
- XP, Coins, Quest, Streak, Achievement หรือ Reward ถูก grant โดย Adventure โดยตรง/ซ้ำ;
- mixed-owner data หรือ owner U-X เปลี่ยน;
- non-participant มี research row/event/outbox;
- Standard fallback เข้าไม่ได้;
- crash, retry loop, database corruption หรือ deletion กระทบ global content;
- ข้อความตำหนิ/ลงโทษผู้เรียนหรือ false mastery claim;
- permit/consent/assent withdrawal, expiry หรือ revocation แล้วยังเกิด treatment Host/start/research enqueue ใหม่

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
| 1 | เปิด build ที่ Adventure hidden ด้วย U-A และเข้า Learn | Learn layout/action set เหมือน baseline ไม่มี Today Experience card หรือ bottom tab ใหม่ |
| 2 | เปิด Vocabulary, Review/Mastery และ Profile ตามปกติ | route/action สำคัญทำงานเหมือน baseline |
| 3 | ลองเปิด hidden/stale/direct `home/learn/today-experience` จาก test harness | กลับ Learn พร้อม bounded reason; Host/snapshot/opportunity count = 0 |
| 4 | ตรวจ diagnostic/write summary กับ QA | ไม่มี Adventure row, learning write หรือ reward write |

**Pass:** ผู้ใช้ทำงาน Standard ต่อได้โดยไม่รู้สึกว่าฟีเจอร์ใหม่รบกวน

### UAT-002 — เลือก Adventure แบบ session-local และกลับ Standard

**Trace:** FR-006/010/017, BR-012; WBS 1.9/1.11; TC-ENT-004/005, TC-UX-001

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด Learn ด้วย U-A ใน Internal build | เห็น additive Today Experience card หนึ่งรายการ โดย bottom navigation เดิมไม่เปลี่ยน |
| 2 | เปิด card แล้วเลือก Adventure โดยไม่เลือก “จำการตั้งค่า” | Today Experience Host แสดง Adventure Home และ mission เด่นหนึ่งรายการ |
| 3 | สลับ Map → List → Map | node/order/selection/action ไม่เปลี่ยน |
| 4 | กด “ใช้แบบมาตรฐาน” ที่ไม่ต้อง scroll | กลับ Standard ใน Today Experience Host เดิม ไม่ stack home ซ้ำ; Back กลับ Learn |
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
| 1 | เปิด fixture สองแบบ: Adventure catalog หายแต่ Today พร้อม และ Today dependency หาย | แบบแรกแสดง Standard; แบบหลังไม่แสดง card/กลับ Learn พร้อม bounded reason |
| 2 | กด retry หนึ่งครั้ง | retry เป็น bounded single-flight ไม่มี repeated dialog/spinner loop |
| 3 | เปิด diagnostics กับ QA | มี bounded reason code ไม่มี answer/direct identifier/raw story |
| 4 | เมื่อ Today dependency หาย ตรวจการกลับ Learn; เมื่อเฉพาะ Adventure asset หายตรวจ Standard | fallback แยกตาม dependency และ canonical learning ยังใช้งานได้ |

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

ส่วนนี้รันได้เฉพาะเมื่อ `MS-06`, approved protocol/ethics และ signed runtime permit fixture ครบ; minor fixture ต้องมี guardian permission + learner assent refs และ Research/Privacy Owner อนุมัติแล้ว

### UAT-025 — Non-participant ต้องเป็น zero-row

**Trace:** FR-048/078/084, NFR-020/021; WBS 4.5/4.8; TC-ENT-011, TC-RSH-001/005

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ยืนยัน U-NP ไม่มี consent/run | baseline research count = 0 |
| 2 | เปิด Adventure, เริ่มและจบ mission | product ใช้งานได้เต็มตาม feature |
| 3 | สลับ Standard แล้วกลับ Adventure | preference/presentation ทำงานโดยไม่สร้าง research |
| 4 | ตรวจ local rows, outbox และ server fixture | exposure/measurement/origin persisted row = 0 |

### UAT-026 — Permit/assignment/run gate และ stable assignment

**Trace:** FR-076–080, BR-012–015; WBS 4.4/4.5; TC-RSH-002–004/006

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ทดสอบ consent-only fixture | ไม่มี active permit/treatment/research row เพราะ assignment/run ไม่ครบ |
| 2 | ทดสอบ assignment-only fixture | ไม่มี active permit/research row เพราะ consent ไม่ครบ |
| 3 | เปิด U-R1 ที่ signed permit/run ครบ | opportunity เปิดก่อน `TodayExperiencePresented`; Started ผูก accepted learningSessionId |
| 4 | สลับ Standard ทั้งก่อนและหลังมี plan | assignment ยัง Adventure; neutral change event pin assigned/effective presentation และ bounded ordinal |
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

### UAT-028 — Withdraw consent/permit หยุด treatment และ enqueue ทันที

**Trace:** FR-085, DATA-012, NFR-022; WBS 4.5/4.12; TC-RSH-008/009

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด prompt/event breakpoint ด้วย U-R1 | eligible state ยืนยันแล้ว |
| 2 | withdraw consent/permit ผ่าน approved flow ก่อน submit/enqueue | active projection invalid ก่อน operation ถัดไป |
| 3 | ลองเปิด treatment Host/start/submit prompt/trigger event | treatment/research operation rejected; product learning result ไม่เสีย |
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

Automated precondition only: source `85b17755` ผ่าน host-GPU emulator rehearsal
ครบทุก budget รวม Map/List frame p95 4.290 ms และ production-controller
untimed probe ที่ app-observed clock 601,000 ms โดย session ยัง active. ผลนี้ไม่
ทำให้ UAT-030 เป็น Pass; tester perception, physical profile และ sign-off ยัง
ต้องบันทึกจาก external session ตามตารางด้านบน.

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
| 1 | UAT Lead ตรวจ scoped BG-01–BG-12, G0B และ Android Pilot matrix | Android/shared gates มี fresh evidence; iOS/desktop/AI Voice/field-model แสดง excluded ไม่ใช่ pass |
| 2 | ทำ smoke: entry → mission → answer → result → Standard | critical path ผ่านและ authority receipt ถูกต้อง |
| 3 | ทำ nonparticipant zero-row smoke | count = 0 |
| 4 | Release Owner ทำ emergency-off | new start blocked, accepted state safe, Standard restored |
| 5 | คณะตัดสิน Continue/Hold/Rollback | decision, threshold, owner และ next review ถูกบันทึก |

## 14. UAT Scripts — Participation Permit, Accessibility and Release Gates

### UAT-033 — Guardian permit issuance and invalid permit

**Trace:** FR-097/103, DATA-014, UI-015/017, NFR-035, BR-021; WBS 4.15/4.17/5.14; TC-DAT-017/018, TC-RSH-017/018/020, TC-UX-016/018

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | Guardian เปิด flow ของ U-M1 และอ่าน purpose/data/expiry/withdraw/no-learning-impact | อธิบายได้โดยไม่รับคำใบ้; actions Allow/Not now เท่าเทียมและไม่ preselect |
| 2 | กด Allow ผ่าน approved enrollment | เกิด opaque guardian receipt ref; สถานะบอกว่ายังต้องมี learner assent ไม่ claim enrolled |
| 3 | ตรวจ app data/export diagnostic | มี age-band code; ไม่มี full DOB/guardian PII |
| 4 | เปิด U-M2 ที่ guardian ref หาย/signature ผิด/expired | active projection ไม่เกิด, zero opportunity/event; Continue learning ใช้ได้ |
| 5 | Guardian กด Not now | learner เข้าผลิตภัณฑ์ต่อได้และไม่มี protocol treatment/research row |

### UAT-034 — Learner assent and independent comprehension

**Trace:** FR-098/103, UI-016/017, BR-021; WBS 4.17/5.14; TC-RSH-017/019, TC-UX-017/018

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | U-M1 เปิด assent หลัง guardian permission | copy ตาม age band พูดกับ learner โดยตรง; Agree/Not now เท่าเทียม |
| 2 | Learner กด Not now | ไม่มี active permit/opportunity/event; กลับการเรียนและ focus ถูก restore |
| 3 | ใน fixture ใหม่ Learner กด Agree | active projection เกิดเมื่อหลักฐานทุกส่วน valid เท่านั้น |
| 4 | ถาม Skip/withdraw/no-learning-impact แยกจาก guardian | guardian และ learner ตอบผ่านเกณฑ์ของตนเอง; ห้ามใช้คำตอบแทนกัน |
| 5 | ถอน assent หลังออก permit | projection invalid ก่อน operation ถัดไป; product learning ยังใช้ได้ |

### UAT-035 — Expiry, revocation and withdrawal fallback

**Trace:** FR-098, DATA-014/015, UI-017, NFR-035, BR-019/020; WBS 4.15/4.16/5.7; TC-ENT-015, TC-DAT-018/021, TC-OPS-018

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด authorized Host ด้วย active permitและบันทึก snapshot fingerprint | Host/snapshot/opportunity เปิดครั้งเดียว |
| 2 | ทำ permit expire/revoke/withdraw ก่อน mission start | new treatment start/capture ถูก block; assignment ไม่เปลี่ยน |
| 3 | ตรวจ fallback ใน Host เดิม | session choice → preference → pure Standard view จาก snapshot เดิม |
| 4 | เปิด stale/direct routeใหม่หลัง invalidation | กลับ Learn; ไม่สร้าง Host/snapshot/opportunity |
| 5 | ทดสอบ offline invalid signature/known revocation revision | fail closed โดยไม่วน retry และยังเรียน product ได้ |

### UAT-036 — Symmetric Standard/Adventure opportunity and events

**Trace:** FR-099/100/101, DATA-015, NFR-034, BR-019/020; WBS 1.14/4.16/5.16; TC-ENT-014, TC-DAT-020/022, TC-RSH-021–024

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด U-R1 Adventure และ U-R2 Standard ด้วย authorized Host | แต่ละ opening มี UUID/opportunity หนึ่งและ neutral event allowlistเดียวกัน |
| 2 | เทียบ payload | ทั้งคู่ pin assignedTreatment/effectivePresentation; ไม่มี treatment-specific event name |
| 3 | rebuild/retry/switch 12 ครั้ง | loader =1 ต่อ Host; ordinals 1–10 ไม่ซ้ำ; 2 ครั้งเกินเพิ่ม suppressed counter |
| 4 | จำลอง Presented persistence failure | opportunity denominator ยังพบ; completeness reportชี้ missing event; replayไม่เพิ่ม denominator |
| 5 | ทำ flow เดียวกันด้วย U-NP | transient UUID ได้ แต่ research tables/outbox/server =0 |

### UAT-037 — Research-flow accessibility

**Trace:** UI-014–017, NFR-016–019/034/035; WBS 4.17/5.15; TC-UX-019/020, TC-DAT-021

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ใช้ TalkBack ทำ Prompt → Guardian → Assent → Invalid permit → Withdrawal | role/name/state/heading/action ถูก อ่านครั้งเดียว ไม่มี trap; Skip/Not now/Continue reachable |
| 2 | ใช้ Switch Access/keyboard ทำ flow เดิม | logical focus order, 48×48 target, ไม่มี gesture-only action |
| 3 | ใช้ text 200% บน narrow phone | essential copy/actionsไม่ clip; scrollได้; action hierarchyคงเดิม |
| 4 | ปิด dialog/sheet ทุกชนิด | focus กลับ invoking controlและไม่ trigger submitซ้ำ |
| 5 | ตัด networkระหว่าง validation/withdrawal | permit fail closed; ไม่มี enqueueหลัง cutoff; product learningยังใช้ได้ |

### UAT-038 — Feasibility versus efficacy release decision

**Trace:** FR-104, NFR-036/037, BR-022/023; WBS 5.13/5.17/6.4–6.10; TC-RSH-025–027, TC-OPS-016/017

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ป้อน fixture ที่ MS-08A ผ่านแต่ sample ยังไม่ powered | decision สูงสุด Limited; UI/config ปฏิเสธ Enabled/Controlled |
| 2 | ป้อน adult fixture ที่ powered/threshold ผ่าน และ minor incomplete | adult = eligible; minor = Remain Limited; targetingไม่รั่วข้าม class |
| 3 | ป้อน class fixture missing post >15% หรือ arm difference >5pp | class นั้นถูก block แม้ ANCOVA estimate ผ่าน |
| 4 | ตรวจ analysis package | baseline ≤24h, post หลัง first accepted completion ≤30m, ITT ANCOVA, MI และ tipping-point ครบ |
| 5 | ทำ Controlled Expansion + emergency rollback rehearsal | เฉพาะ class approvedเข้าได้; signed decision/monitoring/rollback evidenceครบ |

## 15. UAT Scripts — Pair Matching Prototype Standard

### UAT-039 — Existing entry points and source transparency

**Trace:** FR-105–110, DATA-016, UI-018, BR-024–026; WBS PM0/PM1; TC-PMT-001–005/007–009/012

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด Learn, Today Mission, Review และ Adventure ด้วย fixture ที่แต่ละ entry มีแผนจับคู่ | เข้ากิจกรรม Pair Matching เดิมได้จาก entry ที่เกี่ยวข้องโดยไม่เกิดเมนูหลักหรือ route ใหม่ |
| 2 | ตรวจข้อความก่อนเริ่ม | บอกเหตุผลแหล่งคำ เช่น “คำที่ถึงเวลาทบทวน” หรือ “คำจากภารกิจวันนี้” โดยไม่อ้าง mastery เกินจริง |
| 3 | เปิด entry ที่ canonical source ให้คำไม่ครบ 4 คู่ | กิจกรรมแสดง unavailable และทางกลับที่ปลอดภัย; ไม่เติมคำเงียบจาก source อื่น |
| 4 | สลับ Standard/Adventure แล้วเปิด plan เดียวกัน | pair IDs, direction, density และ source provenance ตรงกัน ต่างเฉพาะ presentation shell |

### UAT-040 — Density preference and guardian control

**Trace:** FR-112, DATA-019, UI-018, NFR-038/039, BR-026/027; WBS PM1/PM6; TC-PMT-006–008

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิดครั้งแรกโดยไม่มีค่า density | ถามเลือก 4 หรือ 6 คู่ครั้งเดียว; ถ้าปิดคำถาม fallback เป็น 4 คู่โดยไม่ใช้วันเกิดหรือ research permit |
| 2 | ผู้เรียนทั่วไปเลือก 6 คู่แล้วเริ่มรอบที่ source ครบ | แผนถูกตรึงเป็น 6 คู่และไม่เปลี่ยนกลางรอบ |
| 3 | ผู้ปกครองกำหนด 4 คู่ | profile ใช้ 4 คู่และ learner เปลี่ยนเกิน policy ไม่ได้ |
| 4 | source มีเพียง 4–5 คู่ขณะ preference เป็น 6 | ระบบขอยืนยันลดเป็น 4 คู่; ปฏิเสธได้และไม่มี silent downgrade |

### UAT-041 — English–Thai direction and pair identity

**Trace:** FR-107/110/111, DATA-016, NFR-038/039, BR-026; WBS PM1/PM2; TC-PMT-009–012/040

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เลือก English → Thai แล้วเริ่ม | ฝั่ง prompt เป็นอังกฤษและตัวเลือกเป็นคำแปลไทยตลอดรอบ |
| 2 | เลือก Thai → English แล้วเริ่มรอบใหม่ | ฝั่ง prompt เป็นไทยและตัวเลือกเป็นอังกฤษตลอดรอบ |
| 3 | ใช้ fixture ที่คำสะกดซ้ำแต่คนละความหมาย | ระบบใช้ curated sense/translation allowlist และป้ายกำกับที่มองเห็นได้; ไม่จับคู่ด้วย surface text อย่างเดียว |
| 4 | resume/rebuild | direction และ pair identity คงเดิม ไม่มีการสุ่มความหมายใหม่ |

### UAT-042 — Wrong answer, delayed repair and tail completion

**Trace:** FR-113–118, DATA-017, UI-022, BR-028/029; WBS PM2/PM3; TC-PMT-013–021

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | จับคู่ผิดหนึ่งคำหลังจับถูกแล้วหนึ่งคู่ | คู่ที่จับถูกยังอยู่; progress ไม่ลดและไม่เพิ่มจากคำตอบผิด |
| 2 | อ่านคำแนะนำสั้นแล้วทำคู่ถูกอื่นต่อ | คำที่ผิดกลับมาหลังคู่ถูกอื่นที่ไม่ซ้ำ 2 คู่ในรอบ 4 คู่ หรือ 3 คู่ในรอบ 6 คู่ |
| 3 | ทำผิดเมื่อท้ายรอบไม่มีระยะพอ | ระบบช่วยให้จบรอบอย่างสุภาพและส่ง independent retry ไป canonical Review; ไม่สร้าง filler pair |
| 4 | ตรวจผลและ history | แยก independent/guided evidence ได้ และไม่มีถ้อยคำลงโทษหรือหัก progress |

### UAT-043 — Pronunciation support versus revealing hint

**Trace:** FR-119, DATA-021, UI-021/026, NFR-043/044, BR-030; WBS PM3/PM6; TC-PMT-022–024/043

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | กดเสียงอ่านก่อนตอบ | เล่นเสียง/อ่านออกเสียงได้และยังนับเป็น independent attempt เพราะไม่ได้เปิดเฉลยความหมาย |
| 2 | ใช้ TalkBack ฟัง label ของคำและปุ่มเสียง | accessibility narration ไม่ถูกนับเป็น hint และไม่ลดดาว |
| 3 | กดคำใบ้ที่เปิดเผยความหมายหรือคู่ที่ถูก | attempt ถูกบันทึกเป็น guided และ UI แจ้งว่าระบบกำลังช่วย |
| 4 | จบรอบ | คำ guided ถูกส่งเข้า SRS/Weakness รอบที่เหมาะสม โดยไม่ claim mastery จากรอบนี้ |

### UAT-044 — Timer setup and active-interaction clock

**Trace:** FR-120/121/127, DATA-017, UI-018/024, NFR-041–043, BR-031; WBS PM4; TC-PMT-025–027/037

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เปิด setup ใหม่ | ค่าเริ่มต้นเป็น “ไม่จับเวลา”; ผู้ใช้เลือก 60/90/120 วินาทีได้ก่อนเริ่ม |
| 2 | เริ่มรอบจับเวลาแล้วเปิด system dialog/background app | clock หยุดระหว่าง non-active interval และ resume อย่างสม่ำเสมอ |
| 3 | ใช้ screen reader อ่านคำอธิบายยาว | narration interval ตาม policy ไม่ทำให้เสียเวลาเป้าหมาย |
| 4 | จบรอบ | ผลสรุปแสดง active time และตัวเลือก timer อย่างถูกต้องโดยไม่เปลี่ยน mastery/reward |

### UAT-045 — Timeout choices without forced failure

**Trace:** FR-122/124/127, DATA-017/018, UI-023/024, NFR-041/043, BR-031/033; WBS PM4; TC-PMT-027/028/030/031/037

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ปล่อยเวลาเป้าหมายหมด | เกมหยุด clock แต่ไม่ประกาศแพ้และไม่หัก progress |
| 2 | เลือก “เล่นต่อแบบไม่จับเวลา” ซึ่งเป็น primary action | เล่นต่อจากสถานะเดิมและผลสรุปบอก “ยังไม่ทันเป้าหมาย แต่ทำต่อได้” |
| 3 | ใน fixture ใหม่เลือก “เริ่มรอบใหม่” | ใช้ exact content set เดิม สับตำแหน่งใหม่ และยังอยู่ใน Learning Session เดิม |
| 4 | ตรวจ reward/mastery หลังทั้งสองทาง | เท่ากับโหมดไม่จับเวลาเมื่อ evidence การเรียนเท่ากัน |

### UAT-046 — One extension and restart persistence

**Trace:** FR-123/124, DATA-017/018, NFR-038/041, BR-031/033; WBS PM4; TC-PMT-029–031/040/041

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | เมื่อหมดเวลาเลือก “เพิ่ม 30 วินาที” | เพิ่มได้หนึ่งครั้งต่อ Learning Session และ clock เดินต่อจาก terminal state เดิม |
| 2 | ปล่อยหมดเวลาอีกครั้ง | ไม่มีสิทธิ์เพิ่มครั้งที่สอง; ยังเลือกเล่นต่อแบบไม่จับเวลาหรือเริ่มรอบใหม่ได้ |
| 3 | restart หลังเคยใช้ extension | extension entitlement ไม่ถูกรีเซ็ต และ evidence ก่อนหน้าไม่หาย |
| 4 | kill/relaunch ระหว่างสถานะ timeout | restore โดยไม่เพิ่มเวลา, reset attempt หรือสร้าง Learning Session ซ้ำ |

### UAT-047 — Stars and time as transparent result projections

**Trace:** FR-125–127, DATA-020, UI-024, BR-031/032; WBS PM5; TC-PMT-032–037

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | จบรอบแบบถูกครั้งแรกทุกคู่และไม่ใช้ revealing hint | ได้ 3 ดาว |
| 2 | จบรอบด้วย independent success อย่างน้อย 3/4 หรือ 5/6 รวม self-correction ก่อน reveal | ได้ 2 ดาว |
| 3 | จบรอบแบบ guided หรือ independent ต่ำกว่าเกณฑ์ | ได้ 1 ดาว; ถ้าออกก่อนจบแสดง incomplete ไม่แสดง 0 ดาว |
| 4 | เทียบ timer on/off, TalkBack on/off และ Standard/Adventure ด้วย ledger เดียวกัน | ดาวเท่ากัน; เวลาเป็นข้อมูลสรุป ไม่ใช่ currency, mastery หรือเงื่อนไข reward |

### UAT-048 — Practice Replay isolation

**Trace:** FR-128/129, DATA-018/020/021, UI-025, NFR-041, BR-032/033; WBS PM5; TC-PMT-038–041

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | จากผล/ประวัติเลือก Practice Replay | สร้าง Learning Session ใหม่ purpose=`practiceReplay` ด้วย exact content set และ shuffle ใหม่ |
| 2 | เล่นจบซ้ำหลายครั้ง | แสดงผลและเก็บ history แบบ grouped/labeled ได้ แต่ไม่เพิ่ม XP/reward/quest/streak/achievement |
| 3 | ตรวจ SRS/Mastery/Weakness/global accuracy/Today due | ค่า authority เหล่านี้ไม่เปลี่ยนและไม่ถูกเร่งจาก replay |
| 4 | กลับดู best result | normal best แยกจาก practice best/attempts อย่างชัดเจน |

### UAT-049 — Adaptive accessibility and localization

**Trace:** UI-019–027, NFR-042/043, BR-030–032; WBS PM6; TC-PMT-022–024/037/043

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | ใช้ TalkBack, Switch Access และ keyboard จบรอบ | ทุกคู่ ปุ่มเสียง คำใบ้ timeout และผลลัพธ์ reachable; focus order/restore ถูกต้อง |
| 2 | ใช้ text 200% และ narrow width | layout เปลี่ยนเป็น focused/list presentation โดยไม่ซ่อนคำหรือ action สำคัญ |
| 3 | ตรวจ target/contrast/motion | touch target ≥48×48, contrast ผ่าน, reduced motion ไม่เสีย state cue |
| 4 | ตรวจ copy ไทย/อังกฤษและตัวเลขเวลา | ไม่ clip/สลับภาษาโดยไม่ตั้งใจ; semantic order คงเดิม |

### UAT-050 — Standard/Adventure parity and safe fallback

**Trace:** FR-105/108/129/130, NFR-040/044–046, BR-024/034; WBS PM7/PM8; TC-PMT-038/040/042–044

| Step | Tester action | Expected result/evidence |
|---:|---|---|
| 1 | รัน immutable plan fixture เดียวกันใน Standard และ Adventure | engine transitions, timer, repair, attempt ledger, stars และ learning writes ตรงกัน |
| 2 | ทำ Adventure renderer fail กลางรอบ | กลับ Standard presentation จาก plan/checkpoint เดิมโดยไม่เสีย progress หรือเขียน reward ซ้ำ |
| 3 | เปิด feature flag Pair UI ใหม่เป็น off | f10/Standard เดิมยังใช้ได้และไม่มี orphan route |
| 4 | ตรวจ source and schema compatibility | reader รุ่นใหม่อ่าน checkpoint เดิมได้; writer ใหม่เริ่มหลัง compatibility gate เท่านั้น |

## 16. คำถามวัดความเข้าใจและแรงจูงใจ

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
10. “ดาวและเวลาหมายถึงอะไร และมีผลต่อ Mastery หรือรางวัลหรือไม่?”
11. “ถ้าหมดเวลา คุณยังทำอะไรต่อได้บ้าง?”
12. “Practice Replay มีผลกับคำที่ถึงเวลาทบทวนหรือรางวัลหรือไม่?”

### เกณฑ์ comprehension

- General learner representatives ขั้นต่ำ 12 คน;
- ใน 12 คนต้องมี minors อย่างน้อย 4 คน;
- อย่างน้อย 11/12 หา Learn card, primary mission และ Standard switch ได้โดยไม่ช่วย;
- อย่างน้อย 11/12 อธิบาย wrong-answer recovery ว่า “ฝึก/ทบทวนอีก” ไม่ใช่ “ถูกลงโทษ”;
- อย่างน้อย 11/12 แยก Learning/Effort/Engagement ได้หลังอ่าน copy ครั้งเดียว;
- accessibility sessions ขั้นต่ำ 4 และ required path ต้องผ่านทุก session;
- research comprehension participants ขั้นต่ำ 10 และ 10/10 ระบุได้ว่า Skip/withdraw ได้และไม่กระทบสิทธิ์เรียน;
- guardian–learner dyads ขั้นต่ำ 5 คู่ โดย guardian 5/5 และ learner 5/5 ต้องผ่าน Skip/withdraw/no-learning-impact แยกกัน;
- Pair Matching representatives ต้องครอบคลุม 4/6 คู่, ทั้งสองทิศทาง, timer off/60/90/120 และอย่างน้อยหนึ่ง assistive-technology path;
- อย่างน้อย 11/12 อธิบายได้ว่าดาว/เวลาเป็นผลแสดงการทำ ไม่ใช่เงินหรือ mastery และ Practice Replay ไม่ให้ reward ซ้ำ;
- shame/coercion/false mastery finding ที่ยืนยันแล้วต้องเป็นศูนย์ก่อน Pilot

ค่าเหล่านี้เป็น acceptance threshold ของ UAT ไม่ใช่ผลวิจัยประสิทธิผล และห้ามตีความแทน protocol

## 17. Defect และ Decision Log

| Defect ID | UAT/Step | Severity | Actual/Expected | Evidence | Owner | Target | Retest | Disposition |
|---|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |  |

Severity:

- **S0 Stop:** data loss/duplication, owner leak, permit/consent/assent violation, direct reward grant, Standard unavailable, cross-class rollout, corruption/retry loop;
- **S1 Critical:** core mission unusable, wrong result meaning, critical accessibility blocker, emergency-off failure;
- **S2 Major:** recoverable main-flow defect or widespread confusing copy;
- **S3 Minor:** cosmetic/nonblocking issue

S0/S1 ต้องแก้และ rerun affected scripts + regression ก่อน sign-off; S2 ต้องมี owner/date/accepted risk; S3 เข้า backlog ได้เมื่อไม่กระทบ comprehension/accessibility

## 18. Exit Criteria และ Sign-off

### 18.1 Internal acceptance

- UAT-001–024 และ 030–032 ผ่านอย่างน้อยหนึ่งครั้งบน mainstream Android และ critical subsets ผ่านบน profile ตามตาราง 4.4;
- general learner representatives ≥12 และ accessibility sessions ≥4 พร้อม numerator/denominator ตาม MDS;
- ไม่มี S0/S1 เปิดค้าง;
- Standard fallback, restart, offline และ emergency-off ผ่าน;
- baseline `G0A` ผ่าน และไม่มี unclassified failure ใน touched foundation;
- Requirement/Test/UAT links ใน RTM ตรงกับ build

### 18.2 Pair Matching Prototype acceptance

- UAT-039–050 และ TC-PMT-001–044 ผ่าน;
- no-new-main-menu, exact 4/6 plan, no silent filler/downgrade และ Standard/Adventure parity ผ่าน;
- timer pause/restore, one-extension entitlement, timeout continue/restart และ immutable evidence ผ่าน;
- stars projection ผ่านทุก boundary และไม่แตะ reward/mastery;
- Practice Replay write isolation = 100%;
- accessibility path และ comprehension threshold ผ่าน;
- ไม่มี S0/S1 เปิดค้าง และ S2 มี owner/date/accepted risk;
- Product, UX/Accessibility, QA และ Tech sign-off ครบ

### 18.3 MS-08A Feasibility acceptance

- Internal acceptance ผ่าน;
- `G0B` และ `BG-01–BG-12` ผ่านด้วย fresh evidence;
- UAT-025–037 ผ่านภายใต้ approved protocol ตาม applicability;
- general learners ≥12 โดย minors ≥4; accessibility moderated sessions ≥4;
- adult research comprehension ≥10 และผ่าน 10/10;
- guardian–learner dyads ≥5; guardian 5/5 และ learner 5/5 ผ่านแยกกัน;
- Android Pilot matrix ครบ; excluded platforms/capabilities ระบุชัด;
- nonparticipant zero-row และ withdrawal cutoff = 100%;
- comprehension thresholds ผ่าน;
- Research/Privacy, Accessibility, QA, Tech และ Product sign-off ครบ;
- decision ได้เพียง Limited/Revise/Stop; ห้าม Controlled Expansion/Enabled หรือ efficacy claim

### 18.4 MS-08B Efficacy acceptance

- UAT-038 ผ่านด้วย frozen evidence ของ participant class นั้น;
- powered sample, endpoint window, ANCOVA, MI/tipping-point และ learning/safety thresholds ผ่าน;
- missing post ≤15% และ arm difference ≤5 percentage points;
- rollout targeting แยก adult/minor และ cross-class negative smoke ผ่าน;
- class ที่ไม่ผ่านยังคง Limited;
- signed Expand/Remain Limited/Stop decision ครบ

### 18.5 Sign-off table

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

ผล automated/local preflight ไม่ใช่ UAT Pass และไม่แทนลายเซ็นของ learner,
Accessibility, UAT, QA, Research/Privacy, Product หรือ Release owner การลงชื่อ
ก่อนครบ external evidence และ gate ที่เกี่ยวข้องไม่ถือเป็น Pilot/Production
approval
