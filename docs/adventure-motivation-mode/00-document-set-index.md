# Adventure Motivation Mode — Document Set Index

**Document set version:** 1.2
**Status:** Draft for Owner Review
**Date:** 2026-09-04
**Product:** LexiQuest
**Baseline:** Adventure planning commit `99f7fb21`; 8/44 Matching source-closure commit `f56e2eb`; database schema v22
**Planning branch:** `feature/adventure-motivation-plan`
**Scope:** planning and acceptance artifacts only; no production implementation is authorized by this document set

## 1. Purpose

ชุดเอกสารนี้แปลง [Adventure Motivation Mode System Design](../superpowers/specs/2026-09-01-adventure-motivation-mode-design.md) ให้เป็นข้อกำหนดที่ตรวจรับได้ ตั้งแต่ขอบเขตโครงการ ความต้องการ สถาปัตยกรรม งานพัฒนา ประสบการณ์ผู้ใช้ การทดสอบ จนถึง UAT โดยรักษา 8/44 baseline และ authority เดิมของ LexiQuest

## 2. Documents

| ลำดับ | เอกสาร | หน้าที่ | ผู้อนุมัติหลัก |
|---|---|---|---|
| 00 | Document Set Index | ควบคุมเวอร์ชัน ลำดับอำนาจ และสถานะเอกสาร | Product Owner |
| 00A | [Current System Audit](00a-current-system-audit.md) | หลักฐานระบบจริง gap/impact matrix ความเสี่ยง และ Go/No-Go gates | CTO + QA Lead + Product Owner |
| 00B | [Architecture Decision Records](00b-architecture-decision-records.md) | ปิด route authorization, permit boundary, neutral events/opportunity, snapshot, minor participation และ rollout gates | Product Owner + CTO |
| 01 | [TOR](01-tor.md) | เป้าหมาย ขอบเขต ผลส่งมอบ เงื่อนไขตรวจรับ | Sponsor/Product Owner |
| 02 | [SRS](02-srs.md) | Functional, data, integration และ non-functional requirements | Product Owner + CTO |
| 03 | [SDS](03-sds.md) | Component, interface, data, failure, security/privacy และ deployment design | CTO/Tech Lead |
| 04 | [Project Plan / WBS](04-project-plan-wbs.md) | ลำดับงาน dependency gate บทบาทและความเสี่ยง | Project Manager + CTO |
| 05 | [UI/UX Design Spec & Wireframes](05-ui-ux-design-spec-wireframes.md) | Information architecture, screen states, copy, accessibility และ wireframes | Product/UX Owner |
| 05A | [Wireframe Overview](05a-wireframe-overview.svg) | ภาพรวมหน้าจอหลักแบบ low fidelity | Product/UX Owner |
| 05B | [Research Participation Wireframes](05b-research-participation-wireframes.svg) | Guardian permission, learner assent, prompt, invalid permit และ withdrawal continuation | Product/UX/Privacy Owner |
| 05C | [Pair Matching Prototype Wireframes](05c-pair-matching-prototype-wireframes.svg) | Setup, board, repair, timeout, result, adaptive accessibility และ Practice Replay | Product/UX/Accessibility Owner |
| 06 | [Test Plan & Test Cases](06-test-plan-and-test-cases.md) | กลยุทธ์ทดสอบ ชุดข้อมูล test case และ exit criteria | QA Lead + CTO |
| 07 | [UAT Script](07-uat-script.md) | ขั้นตอนตรวจรับโดยผู้ใช้ หลักฐาน และ sign-off | Product Owner/UAT Lead |
| 08 | [Requirements Traceability Matrix](08-requirements-traceability-matrix.md) | เชื่อม requirement → design → WBS → test → UAT | BA/QA Lead |
| 09 | [Measurement Decision Spec](09-measurement-decision-spec.md) | นิยาม Motivation/Engagement/Learning, threshold, sample rule และ Android Pilot matrix | Research + Product + Privacy |
| PLAN | [Implementation Plan](../superpowers/plans/2026-09-01-adventure-motivation-mode-implementation.md) | งานระดับไฟล์และวงจร TDD สำหรับผู้พัฒนา | CTO/Tech Lead |

## 3. Precedence

เมื่อเอกสารขัดกัน ให้ใช้ลำดับต่อไปนี้:

1. Change Request ที่ Product Owner และ CTO อนุมัติแล้ว
2. Current System Audit สำหรับข้อเท็จจริงของ baseline และ gate ปัจจุบัน
3. TOR ที่อนุมัติแล้ว
4. SRS ที่อนุมัติแล้ว
5. Architecture Decision Records ที่อนุมัติแล้วสำหรับ decision ที่ TOR/SRS มอบหมาย
6. Measurement Decision Spec ที่อนุมัติแล้วสำหรับ metric/sample/decision rules
7. SDS ที่อนุมัติแล้ว
8. UI/UX Design Spec ที่อนุมัติแล้ว
9. Requirements Traceability Matrix
10. Project Plan/WBS และ Implementation Plan
11. Test Plan และ UAT Script

ข้อกำหนดด้าน data integrity, consent, accessibility, owner isolation และการคง Standard Today Hub เป็น fallback ลดทอนไม่ได้ด้วยแผนงานระดับล่าง

## 4. Controlled Vocabulary

| คำ | ความหมายในเอกสารชุดนี้ |
|---|---|
| 8/44 baseline | ระบบ 8 หมวด 44 ความสามารถที่เสร็จแล้วบน commit `99f7fb21` |
| Standard | Today Hub และเส้นทางเรียนเดิมโดยไม่มี Adventure presentation |
| Adventure | Presentation ทางเลือกที่ใช้ learning core และ authority เดิม |
| Authority | ส่วนเดียวที่มีสิทธิ์เป็นเจ้าของและเปลี่ยนข้อเท็จจริงนั้น |
| Evidence | คำตอบหรือกิจกรรมการเรียนที่ commit ผ่าน Evidence Gateway เดิม |
| Journey Projection | Read model ของแผนที่ซึ่งสร้างใหม่ได้จากข้อมูล canonical |
| Treatment | รูปแบบประสบการณ์ที่ protocol กำหนดให้ participant |
| Preference | ตัวเลือก Standard/Adventure ของผู้ใช้; ไม่ใช่ assignment |
| Crossover | ผู้เข้าร่วมเปลี่ยนไปใช้ Standard ระหว่าง treatment; assignment เดิมไม่ถูกเขียนทับ |
| Internal | เปิดเฉพาะทีมเพื่อทดสอบ ไม่ใช่ production rollout |
| Active Presentation Permit | Minimal projection ที่ Product Entry ใช้เลือก protocol treatment โดยไม่เห็น raw receipts |
| Measurement Opportunity | Participant-only denominator ต่อ authorized Host opening |
| Limited | สถานะสูงสุดหลัง MS-08A Feasibility; ยังห้าม claim efficacy/ขยายทั่วไป |
| Controlled Expansion | เปิดเฉพาะ participant class ที่ผ่าน MS-08B |
| Enabled | เปิดใช้งานหลัง class-specific efficacy และ controlled rollout ผ่าน |
| Pair Matching Experience | Major semantic revision ของ `f10 Matching Mode`; ไม่ใช่ `f45` และไม่ใช่ authority ใหม่ |
| Pair Matching Plan | Immutable learning plan ที่ pin exact lexical identity/revision/checksum, direction, pair count, source reasons, timing และ policy versions |
| Practice Replay | Learning Session ใหม่เพื่อฝึกซ้ำ; บันทึกประวัติได้แต่ไม่เปลี่ยน SRS/Mastery/Weakness ranking/reward/quest/streak/research primary outcome |
| Timeout Restart | Round ใหม่ภายใน Learning Session เดิม; คำและ revision เดิม, deterministic reshuffle, evidence และ extension entitlement เดิมไม่ถูกลบ |

## 5. Invariants Across All Documents

1. Standard Today Hub เดิมยังอยู่; Standard fallback ผ่าน Adventure route ใช้ได้เฉพาะ Host ที่ authorized แล้ว ส่วน hidden/disabled/unknown/stale route กลับ Learn
2. Adventure ไม่เป็นเจ้าของ Vocabulary, SRS, Mastery, Assessment, Quest, Streak, Achievement, XP, Coins, Reward, Recommendation, Today Hub หรือ History
3. ไม่มี `adventure_progress` table ในขอบเขตนี้
4. ทุกคำตอบผ่าน Unified Lesson Shell และ Evidence Gateway เดิม
5. Feature state, learner preference, experiment assignment, consent/guardian/assent receipts และ participation permit เป็นคนละ state
6. ตอบผิดไม่ลด progress, streak, XP หรือสิทธิ์เรียน
7. ไม่มี hearts/lives, forced timer, public leaderboard, generative AI, camera quest, multiplayer หรือ social network ใน treatment แรก
8. งาน schema ใช้ migration ไปข้างหน้า: วางแผน v23 สำหรับ preference v2 และ v24 สำหรับ research measurement แต่ต้อง reserve จาก ledger จริง; หากเลขถูกใช้ก่อนเริ่มงานต้อง rebase ขึ้นโดยไม่ใช้ซ้ำ
9. `EventEnvelopeV2` ไม่ถูกแก้ฟิลด์หรือความหมายโดยปริยาย
10. Owner-scoped data ใหม่ต้องรองรับ guest upgrade, sync, export, withdrawal, deletion และ retention
11. Feature-off ต้อง behaviorally equivalent กับ baseline ยกเว้น schema ที่เพิ่มแบบ forward-compatible
12. ห้ามกล่าวว่าชุดทดสอบ baseline ผ่านทั้งหมดจนกว่า 15 failures ใน Current System Audit จะถูกปิด; Android Pilot ใช้เฉพาะ fresh passing evidence ของ logical/shared + touched scope และต้องประกาศ capability exclusions ตาม ADR-005
13. Product Entry ไม่อ่าน raw consent/guardian/assent; รับเฉพาะ active permit projection และเมื่อ projection invalid ใช้ session choice → preference → Standard
14. Production v1 ไม่เพิ่ม bottom tab; entry เป็น additive card `home/learn/today-experience` ใน Learn surface
15. Standard/Adventure ใช้ neutral event policy และ participant opportunity เดียวกัน; `entryAttemptId` เป็น UUID v4 หนึ่งค่าต่อ authorized Host opening
16. MS-04 เป็นจุด Accept/Stop/Continue ของ Product Core MVP ที่หยุดได้โดยไม่มี schema migration
17. Pilot v1 เป็น Android-only; excluded platform/capability ไม่ถือว่าผ่าน
18. Today Experience Host load snapshot ครั้งเดียวและส่ง object เดียวให้ pure `TodayHubView(snapshot)`/`AdventureHubScreen(snapshot)`
19. Minor treatment/research ต้องมี guardian-led signed permit ที่อ้าง guardian permission + learner assent; ไม่เก็บ full DOB/guardian PII
20. MS-08A ให้ได้สูงสุด Limited; MS-08B ตัดสิน adult/minor แยกกัน
21. Pair Matching เป็น major revision ของ `f10`; ห้ามสร้าง `f45`, route หลัก, learning authority, star currency หรือ pair-specific reward authority
22. Pair Matching ใช้ exact 4/6 คู่ตาม product preference; timer default OFF และตัวเลือก 60/90/120 ไม่มีผลต่อดาว, evidence eligibility, reward หรือ mastery
23. Standard/Adventure Pair ใช้ plan, engine, repair, timer, evidence และ outcome policy เดียวกัน; presentation metadata ห้ามเข้า learning fingerprint
24. Wrong answer ไม่ลดและไม่เพิ่ม matched progress; normal repair เว้น distinct correct pairs 2/3 และ tail ใช้ guided completion พร้อม canonical Review deferral โดยไม่ padding
25. Practice Replay และ Timeout Restart เป็นคนละ contract; technical evidence retry ต้อง reuse identity เดิมและไม่ถือเป็นทั้งสองอย่าง

## 6. Review and Approval Workflow

| Gate | เอกสารที่ต้องผ่าน | ผลลัพธ์ |
|---|---|---|
| G0 Scope | TOR + SRS | ขอบเขตและ requirement ถูกยืนยัน |
| G1 Architecture | SDS + RTM | authority, interface, schema และ failure policy ถูกยืนยัน |
| G2 Experience | UI/UX Spec + wireframe accessibility review | flow และทุก screen state ถูกยืนยัน |
| G3 Build Ready | Project Plan/WBS + Implementation Plan + Test Plan | งานระดับไฟล์และ test-first sequence พร้อม |
| G4 Internal Ready | Test evidence ของ Phase 0–3 | feature ยัง hidden; ทีมทดลองได้ |
| G5 / MS-08A Feasibility | Permit, data quality, privacy, accessibility, offline, comprehension/UAT | เปิด Limited study ต่อได้; no efficacy claim |
| G6 / MS-08B Efficacy | Powered class analysis, missingness, learning/safety, UAT-038 | ขยายเฉพาะ adult/minor class ที่ผ่าน |

## 6.1 Controlled Coverage Totals

| Artifact | Controlled count | หมายเหตุ |
|---|---:|---|
| SRS requirements | 258 | FR 130 + DATA 21 + UI 27 + NFR 46 + BR 34 |
| Planned detailed test cases | 188 | เดิม 144 + Pair Matching Prototype `PMT-001–044` |
| UAT scripts | 50 | เดิม 38 + Pair Matching Prototype `UAT-039–050` |
| Logical planning modules | 12 | M01–M11 เดิม + M12 Pair Matching Prototype Integration; M12 ยังคงเป็น `f10` |
| Current Drift tables | 44 | schema v22 baseline; Phase 1 ต้องไม่เพิ่มตาราง |
| Architecture decisions | 13 | ADR-001–008 เดิม + ADR-009–013 สำหรับ Pair Matching Prototype |
| Measurement axes | 5 + reliability/safety | Motivation primary; Engagement/Effort/Learning แยกกัน |

ตัวเลขนี้เป็น coverage inventory ไม่ใช่ผลผ่านการทดสอบ

## 7. Change Control

การเปลี่ยน requirement ต้องมี Change Request ระบุอย่างน้อย:

- เหตุผลและผู้ร้องขอ;
- requirement IDs ที่เปลี่ยน;
- ผลกระทบต่อ authority, schema, event contract, privacy และ accessibility;
- WBS/test/UAT ที่ต้องแก้;
- migration/rollback consequence;
- ผู้อนุมัติและวันที่มีผล

ห้ามแก้เฉพาะ UI หรือ implementation แล้วปล่อย RTM, test case หรือ UAT ไม่ตรงกัน

## 8. Current Verification Constraint

การตรวจใหม่เมื่อ 2026-09-01 แก้ปัญหา package resolution ของ worktree ด้วย `flutter pub get --offline` และสามารถรัน full Flutter suite ได้จริงทั้งแบบ default concurrency และ `--concurrency=1` ผลที่ทำซ้ำได้คือ **3,202 ผ่าน / 15 ล้มเหลว** รายละเอียดและ root-cause classification อยู่ใน [Current System Audit](00a-current-system-audit.md)

ดังนั้นสถานะปัจจุบันคือ:

- อนุญาตให้ทำเอกสาร wireframe และ prototype ที่ไม่เขียนข้อมูล;
- implementation แบบ hidden/default-off ต้องผ่าน gate “before implementation” ใน Audit;
- ห้าม MS-08A จน baseline, permit/lifecycle, accessibility, security/dependency และ release gates มี fresh passing evidence; ห้าม Controlled Expansion/Enabled จน class นั้นผ่าน MS-08B;
- native-assets crash ที่บันทึกใน draft รุ่นก่อนหน้าไม่ใช่ข้อจำกัดปัจจุบันและห้ามนำมาใช้แทนผลตรวจล่าสุด
