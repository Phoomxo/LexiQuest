# Adventure Motivation Mode — Document Set Index

**Document set version:** 1.0
**Status:** Draft for Owner Review
**Date:** 2026-09-01
**Product:** LexiQuest
**Baseline:** commit `99f7fb21`, database schema v22
**Planning branch:** `codex/adventure-motivation-plan`
**Scope:** planning and acceptance artifacts only; no production implementation is authorized by this document set

## 1. Purpose

ชุดเอกสารนี้แปลง [Adventure Motivation Mode System Design](../superpowers/specs/2026-09-01-adventure-motivation-mode-design.md) ให้เป็นข้อกำหนดที่ตรวจรับได้ ตั้งแต่ขอบเขตโครงการ ความต้องการ สถาปัตยกรรม งานพัฒนา ประสบการณ์ผู้ใช้ การทดสอบ จนถึง UAT โดยรักษา 8/44 baseline และ authority เดิมของ LexiQuest

## 2. Documents

| ลำดับ | เอกสาร | หน้าที่ | ผู้อนุมัติหลัก |
|---|---|---|---|
| 00 | Document Set Index | ควบคุมเวอร์ชัน ลำดับอำนาจ และสถานะเอกสาร | Product Owner |
| 00A | [Current System Audit](00a-current-system-audit.md) | หลักฐานระบบจริง gap/impact matrix ความเสี่ยง และ Go/No-Go gates | CTO + QA Lead + Product Owner |
| 01 | [TOR](01-tor.md) | เป้าหมาย ขอบเขต ผลส่งมอบ เงื่อนไขตรวจรับ | Sponsor/Product Owner |
| 02 | [SRS](02-srs.md) | Functional, data, integration และ non-functional requirements | Product Owner + CTO |
| 03 | [SDS](03-sds.md) | Component, interface, data, failure, security/privacy และ deployment design | CTO/Tech Lead |
| 04 | [Project Plan / WBS](04-project-plan-wbs.md) | ลำดับงาน dependency gate บทบาทและความเสี่ยง | Project Manager + CTO |
| 05 | [UI/UX Design Spec & Wireframes](05-ui-ux-design-spec-wireframes.md) | Information architecture, screen states, copy, accessibility และ wireframes | Product/UX Owner |
| 05A | [Wireframe Overview](05a-wireframe-overview.svg) | ภาพรวมหน้าจอหลักแบบ low fidelity | Product/UX Owner |
| 06 | [Test Plan & Test Cases](06-test-plan-and-test-cases.md) | กลยุทธ์ทดสอบ ชุดข้อมูล test case และ exit criteria | QA Lead + CTO |
| 07 | [UAT Script](07-uat-script.md) | ขั้นตอนตรวจรับโดยผู้ใช้ หลักฐาน และ sign-off | Product Owner/UAT Lead |
| 08 | [Requirements Traceability Matrix](08-requirements-traceability-matrix.md) | เชื่อม requirement → design → WBS → test → UAT | BA/QA Lead |
| PLAN | [Implementation Plan](../superpowers/plans/2026-09-01-adventure-motivation-mode-implementation.md) | งานระดับไฟล์และวงจร TDD สำหรับผู้พัฒนา | CTO/Tech Lead |

## 3. Precedence

เมื่อเอกสารขัดกัน ให้ใช้ลำดับต่อไปนี้:

1. Change Request ที่ Product Owner และ CTO อนุมัติแล้ว
2. Current System Audit สำหรับข้อเท็จจริงของ baseline และ gate ปัจจุบัน
3. TOR ที่อนุมัติแล้ว
4. SRS ที่อนุมัติแล้ว
5. SDS ที่อนุมัติแล้ว
6. UI/UX Design Spec ที่อนุมัติแล้ว
7. Requirements Traceability Matrix
8. Project Plan/WBS และ Implementation Plan
9. Test Plan และ UAT Script

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
| Pilot | การเปิดแบบจำกัดที่ผ่าน consent, protocol และ gate ทั้งหมด |
| Enabled | เปิดใช้งานแบบควบคุมหลังผ่าน Pilot ไม่ได้หมายถึงเปิดให้ทุกคนทันที |

## 5. Invariants Across All Documents

1. Standard Today Hub ต้องใช้งานได้เสมอและเป็น fallback
2. Adventure ไม่เป็นเจ้าของ Vocabulary, SRS, Mastery, Assessment, Quest, Streak, Achievement, XP, Coins, Reward, Recommendation, Today Hub หรือ History
3. ไม่มี `adventure_progress` table ในขอบเขตนี้
4. ทุกคำตอบผ่าน Unified Lesson Shell และ Evidence Gateway เดิม
5. Feature state, learner preference, experiment assignment และ consent เป็นคนละ state
6. ตอบผิดไม่ลด progress, streak, XP หรือสิทธิ์เรียน
7. ไม่มี hearts/lives, forced timer, public leaderboard, generative AI, camera quest, multiplayer หรือ social network ใน treatment แรก
8. งาน schema ใช้ migration ไปข้างหน้า: วางแผน v23 สำหรับ preference v2 และ v24 สำหรับ research measurement แต่ต้อง reserve จาก ledger จริง; หากเลขถูกใช้ก่อนเริ่มงานต้อง rebase ขึ้นโดยไม่ใช้ซ้ำ
9. `EventEnvelopeV2` ไม่ถูกแก้ฟิลด์หรือความหมายโดยปริยาย
10. Owner-scoped data ใหม่ต้องรองรับ guest upgrade, sync, export, withdrawal, deletion และ retention
11. Feature-off ต้อง behaviorally equivalent กับ baseline ยกเว้น schema ที่เพิ่มแบบ forward-compatible
12. ห้ามกล่าวว่าชุดทดสอบ baseline ผ่านทั้งหมดจนกว่า 15 failures ใน Current System Audit จะถูกปิดและมีผลรันใหม่

## 6. Review and Approval Workflow

| Gate | เอกสารที่ต้องผ่าน | ผลลัพธ์ |
|---|---|---|
| G0 Scope | TOR + SRS | ขอบเขตและ requirement ถูกยืนยัน |
| G1 Architecture | SDS + RTM | authority, interface, schema และ failure policy ถูกยืนยัน |
| G2 Experience | UI/UX Spec + wireframe accessibility review | flow และทุก screen state ถูกยืนยัน |
| G3 Build Ready | Project Plan/WBS + Implementation Plan + Test Plan | งานระดับไฟล์และ test-first sequence พร้อม |
| G4 Internal Ready | Test evidence ของ Phase 0–3 | feature ยัง hidden; ทีมทดลองได้ |
| G5 Pilot Ready | Research, privacy, accessibility, offline, UAT evidence | เปิด Pilot แบบ consented ได้ |
| G6 Enablement | Pilot report + rollback rehearsal | ขยายการเปิดแบบควบคุมได้ |

## 6.1 Controlled Coverage Totals

| Artifact | Controlled count | หมายเหตุ |
|---|---:|---|
| SRS requirements | 174 | FR 96 + DATA 13 + UI 14 + NFR 33 + BR 18 |
| Planned detailed test cases | 114 | ENT/JRN อย่างละ 12; LRN/REC/DAT/RSH/UX/OPS อย่างละ 15 |
| UAT scripts | 32 | nonresearch, accessibility, lifecycle, research และ release |
| Adventure modules | 11 | M01–M11; M07 เป็น read-only projection reader |
| Current Drift tables | 44 | schema v22 baseline; Phase 1 ต้องไม่เพิ่มตาราง |

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
- ห้าม Pilot หรือ production enablement จนกว่า baseline, consent/lifecycle, accessibility, security/dependency และ release gates จะมี fresh passing evidence;
- native-assets crash ที่บันทึกใน draft รุ่นก่อนหน้าไม่ใช่ข้อจำกัดปัจจุบันและห้ามนำมาใช้แทนผลตรวจล่าสุด
