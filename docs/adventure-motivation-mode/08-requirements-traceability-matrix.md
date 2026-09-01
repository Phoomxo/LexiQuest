# Requirements Traceability Matrix — Adventure Motivation Mode

**Document ID:** LQ-AMM-RTM-001
**Version:** 1.0
**Status:** Draft for BA/QA/Tech Review
**Date:** 2026-09-01
**Requirements source:** `02-srs.md` v1.0
**Design source:** `03-sds.md` v1.0
**Delivery source:** `04-project-plan-wbs.md` v1.0
**Verification sources:** `06-test-plan-and-test-cases.md` และ `07-uat-script.md` v1.0

## 1. วิธีใช้ Matrix

RTM นี้ทำให้ requirement ทุกข้อมี design owner, work package และ verification evidence ที่วางแผนไว้ โดยยังไม่แสดงสถานะ “ผ่าน” เพราะ Adventure ยังไม่ได้ implement

| Code | ความหมาย |
|---|---|
| `P` | Planned — มี design/work/test ครบ แต่ยังไม่มี execution evidence |
| `B` | Baseline evidence — ตรวจระบบปัจจุบันแล้ว ไม่ใช่ผล Adventure |
| `I` | Implemented — ใช้หลัง code review เท่านั้น |
| `V` | Verified — ต้องมี fresh command/device/UAT evidence |
| `A` | Accepted — Product/UAT sign-off แล้ว |
| `GOV` | Governance/manual evidence เป็นหลัก |

กติกา:

1. ห้ามเปลี่ยนเป็น `V` จากเอกสารหรือผลทดสอบเก่า;
2. requirement ที่มีทั้ง automated และ UAT ต้องผ่านทั้งสองชนิด;
3. เมื่อ Requirement, interface, WBS หรือ test เปลี่ยน ต้องแก้ทั้งแถวใน PR เดียวกัน;
4. `N/A` ต้องมีผู้อนุมัติ เหตุผล และ decision log; ช่องว่างไม่ถือเป็น coverage;
5. เพื่อให้ตารางอ่านง่าย คอลัมน์ Verification ย่อ `TC-ENT-001` เป็น `ENT-001` และคอลัมน์ UAT ย่อ `UAT-001` เป็น `001`; ทุก reference ต้องขยายกลับไปหา ID เต็มในเอกสารต้นทางได้

## 2. Functional Requirements — Entry และ Experience Shell

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-FR-001 | เพิ่ม broad feature แบบ additive ไม่เป็น f45 | M01 / §10 | 0.12–0.13 | ENT-001, OPS-015 | 001 | P |
| AMM-FR-002 | default state = hidden | M01 / §10 | 0.12–0.13 | ENT-001 | 001 | P |
| AMM-FR-003 | entry ต้องผ่าน feature/dependency gate | M01 / §3 | 0.14,1.11 | ENT-002–004 | 001–004 | P |
| AMM-FR-004 | config ผิดต้อง Standard | M01 / §6 | 0.14,1.10 | ENT-006 | 001,004 | P |
| AMM-FR-005 | feature state ไม่แก้ assignment | M01/M10 | 0.13,4.5 | ENT-010 | 003,026 | P |
| AMM-FR-006 | Phase 1 session choice; Phase 3 preference | M01 | 1.9,3.3 | ENT-004/005, DAT-005 | 002,003 | P |
| AMM-FR-007 | switch ไม่ rewrite stable assignment | M01/M10 | 4.5,4.8 | ENT-010, RSH-006 | 003,026 | P |
| AMM-FR-008 | entry decision มี pins/reason ครบ | M01 | 0.14,0.16 | ENT-002–006 | 002–004 | P |
| AMM-FR-009 | emergency-off บล็อก start ไม่ทำลาย session | M01/M09 | 2.12,5.7 | ENT-007–009, OPS-011 | 022,032 | P |
| AMM-FR-010 | Standard escape ไม่ต้อง scroll | M01/M02 | 1.9,1.12 | UX-001/003/005 | 002,015,016 | P |
| AMM-FR-011 | shell อ่าน snapshot ไม่เขียน repo | M02 | 1.6–1.11 | JRN-005, LRN-015 | 001,005 | P |
| AMM-FR-012 | Map/List action parity | M02 | 1.7–1.8 | UX-002 | 002,005,015 | P |
| AMM-FR-013 | primary mission เด่นเพียงหนึ่ง | M02 | 1.9 | UX-001 | 002,005 | P |
| AMM-FR-014 | state matrix ครบ | M02 | 1.6,1.10 | ENT-003/006, JRN-006/010/011 | 004,019 | P |
| AMM-FR-015 | async single-flight/recoverable | M02 | 1.6,1.9 | LRN-003, OPS-007 | 006 | P |
| AMM-FR-016 | ไม่ claim ก่อน receipt | M02/M07/M09 | 2.8–2.9,3.6 | REC-007/008 | 012 | P |
| AMM-FR-017 | Map/List switch ไม่ mutate state | M02 | 1.7–1.8 | UX-002 | 002,005,015 | P |

## 3. Functional Requirements — World, Journey และ Session Composer

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-FR-018 | versioned/QA catalog identity | M03 | 0.16–0.18 | JRN-007–009 | 014,019 | P |
| AMM-FR-019 | world/node/story IDs stable unique | M03 | 0.16–0.18 | JRN-007 | 019 | P |
| AMM-FR-020 | prerequisite graph valid/acyclic | M03 | 0.18 | JRN-008 | 019 | P |
| AMM-FR-021 | visual metadata + accessible label | M03 | 0.17–0.18 | JRN-009, UX-003 | 014,015 | P |
| AMM-FR-022 | asset manifest checksum/size/type/revision | M03 | 0.17–0.18 | JRN-010, OPS-005 | 019 | P |
| AMM-FR-023 | catalog ห้าม execute remote code | M03 / §8 | 0.18,5.5 | architecture review, OPS-008 | 019 | P |
| AMM-FR-024 | locale/checksum ผิด quarantine + Standard | M03 | 0.18,1.10 | JRN-009–011 | 004,014,019 | P |
| AMM-FR-025 | ไม่ reuse legacy LearningWorldMapScreen | M03 / §10 | 0.10,0.15 | architecture boundary | 001 | P |
| AMM-FR-026 | projection อ่าน authorities เดิม | M04 | 1.2–1.3 | JRN-001–005 | 005 | P |
| AMM-FR-027 | deterministic snapshot | M04 | 1.1–1.3 | JRN-001/002 | 005 | P |
| AMM-FR-028 | snapshot มี freshness/dependency state | M04 | 1.1–1.3 | JRN-006 | 004,005 | P |
| AMM-FR-029 | node state เป็น closed enum | M04 | 1.1 | JRN-001/005 | 005 | P |
| AMM-FR-030 | ไม่มี adventure_progress | M04 / §4 | 1.3,1.13 | JRN-005, DAT-001 | 005 | P |
| AMM-FR-031 | wrong word กลับผ่าน Review identity เดิม | M04/M09 | 1.3,2.7 | REC-002/014 | 007,008 | P |
| AMM-FR-032 | resume มาก่อน mission ใหม่ | M04/M09 | 1.3,2.11 | JRN-003 | 005,010 | P |
| AMM-FR-033 | partial dependency ลดเฉพาะ node ที่เกี่ยว | M04 | 1.2,1.10 | ENT-003, JRN-006/011 | 004 | P |
| AMM-FR-034 | composer ใช้ canonical Today work | M05 | 1.5 | LRN-001 | 005,006 | P |
| AMM-FR-035 | due/review priority ตาม policy เดิม | M05 | 1.5 | JRN-004 | 005 | P |
| AMM-FR-036 | reason/override ไม่สูญหาย | M05 | 1.4–1.5 | LRN-001 | 005,006 | P |
| AMM-FR-037 | saved intent ไม่แปลง weakness | M05 | 1.5 | JRN-001/004 | 005 | P |
| AMM-FR-038 | duration ใช้ policy เดิม | M05 | 1.4–1.5 | LRN-001 | 006 | P |
| AMM-FR-039 | plan pins identities/versions | M05 | 1.4–1.5 | LRN-001/005 | 006 | P |
| AMM-FR-040 | reject mixed-owner/stale/unresolved | M05 | 1.4–1.5 | LRN-004/005, OPS-010 | 006,023 | P |
| AMM-FR-041 | compose idempotent/no duplicate mission | M05 | 1.5 | JRN-001/002, LRN-003 | 005,006 | P |

## 4. Functional Requirements — Learning Bridge และ Motivation Projection

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-FR-042 | เริ่มผ่าน Unified Lesson เดิม | M06 | 2.2–2.5 | LRN-001/002 | 006 | P |
| AMM-FR-043 | origin transient; EvidenceContext unchanged | M06 / §4 | 2.4 | LRN-006 | 006 | P |
| AMM-FR-044 | answer/evidence/mastery เท่า Standard | M06 | 2.1–2.4 | LRN-001/006–010/015 | 006,009 | P |
| AMM-FR-045 | submission identity เดียวข้าม retry | M06/M09 | 2.10–2.11 | LRN-011–013 | 006,009,010 | P |
| AMM-FR-046 | Adventure UI ไม่ import/write Drift learning | M06 / §8 | 2.2–2.5 | architecture test, DAT-001 | 006 | P |
| AMM-FR-047 | assessment ไม่เป็น reward mission | M06/M10 | 3.5 | LRN-014 | 024 | P |
| AMM-FR-048 | consented exposure correlation แยกจาก evidence | M06/M10 | 4.7–4.8 | LRN-006, RSH-004/005 | 025,026 | P |
| AMM-FR-049 | motivation อ่านหลัง evidence/side effect commit | M07 | 3.5–3.7 | REC-007/008 | 012 | P |
| AMM-FR-050 | อ่าน receipts เดิม ห้าม grant/mutate | M07 | 3.5–3.7 | REC-007–010 | 012 | P |
| AMM-FR-051 | เปิด map/story ไม่ได้ reward | M07 | 3.5–3.6 | REC-010 | 012 | P |
| AMM-FR-052 | assessment ไม่มี motivation side effect | M07 | 3.5 | LRN-014 | 024 | P |
| AMM-FR-053 | hint คง guided practice | M06/M07 | 2.3,3.5 | LRN-008 | 009 | P |
| AMM-FR-054 | receipt ผูก source evidence/idempotency เดิม | M07 | 3.5–3.7 | REC-008/009 | 012 | P |
| AMM-FR-055 | replay ไม่ให้ reward/unlock ซ้ำ | M07/M09 | 2.10,3.6 | LRN-013, REC-009 | 010,012 | P |
| AMM-FR-056 | equip/purchase ไม่ลด lifetime XP | M07/M08 | 3.6,3.10 | REC-011 | 013 | P |

## 5. Functional Requirements — Companion, Result และ Recovery

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-FR-057 | reaction จาก versioned scripted catalog | M08 | 3.8–3.9 | UX-008–010 | 013 | P |
| AMM-FR-058 | ไม่มี AI free text | M08 | 3.8–3.9 | architecture/content review | 013 | P |
| AMM-FR-059 | avatar/cosmetic อ่าน ownership เดิม | M08 | 3.10 | REC-011 | 013 | P |
| AMM-FR-060 | supportive reaction ครบ typed outcomes | M08 | 3.8–3.11 | REC-013, UX-010/011 | 007,009,013 | P |
| AMM-FR-061 | ไม่มี relationship/punishment state | M08 / §4 | 3.8–3.10 | schema/architecture review | 013 | P |
| AMM-FR-062 | reduced-motion/no-audio equivalents | M08 | 3.10–3.11 | UX-008/009 | 013,017 | P |
| AMM-FR-063 | copy ไม่ shame | M08 / §8 | 3.11 | UX-010/011 | 007,013,014 | P |
| AMM-FR-064 | Result แยกสามแกน | M09 | 2.8–2.9 | REC-012, UX-012 | 009,011 | P |
| AMM-FR-065 | ไม่รวมเป็นคะแนนเดียว | M09 | 2.8–2.9 | REC-012 | 011 | P |
| AMM-FR-066 | incorrect commit ก่อน feedback/repair | M09 | 2.6–2.7 | LRN-009, REC-001 | 007 | P |
| AMM-FR-067 | repair หลัง 3–5 items | M09 | 2.6–2.7 | REC-001/002 | 007,008 | P |
| AMM-FR-068 | repair สูงสุดหนึ่งรอบ/item/session | M09 | 2.6–2.7 | REC-003–005 | 007 | P |
| AMM-FR-069 | เหลือน้อยไม่ padding; ส่ง Review | M09 | 2.6–2.7 | REC-002/014 | 008 | P |
| AMM-FR-070 | repair ผิดให้ SRS นัดต่อ | M09 | 2.7 | REC-004/014 | 007,008 | P |
| AMM-FR-071 | support ladder ตาม active recall | M09 | 2.6–2.7 | REC-001–004 | 007 | P |
| AMM-FR-072 | evidence failure freeze + exact retry | M09 | 2.10 | LRN-011/012 | 009 | P |
| AMM-FR-073 | reward failure ไม่ลบ learning | M09/M07 | 3.7 | REC-007/008 | 012 | P |
| AMM-FR-074 | termination ใช้ recovery เดิมไม่ซ้ำ | M09 | 2.10–2.11 | LRN-013, REC-009 | 010 | P |
| AMM-FR-075 | kill switch safe close + Standard | M09/M01 | 2.12 | ENT-009, OPS-011 | 022 | P |

## 6. Functional Requirements — Research และ Operations

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-FR-076 | stable assignment จาก ExperimentRegistry | M10 | 4.4–4.5 | RSH-002–007 | 026 | P |
| AMM-FR-077 | preference/feature/crossover ไม่ rewrite assignment | M10 | 4.5/4.8 | ENT-010, RSH-006/007 | 003,026 | P |
| AMM-FR-078 | collect เมื่อ consent+assignment+run ครบ | M10 | 4.4–4.5/4.8 | RSH-001–004 | 025,026 | P |
| AMM-FR-079 | prompt ที่ breakpoint, Skip ได้ | M10 | 4.6 | RSH-010/011, UX-013 | 027 | P |
| AMM-FR-080 | measurement run pins versions | M10 / §4 | 4.1–4.5 | RSH-004/014/015 | 026,029 | P |
| AMM-FR-081 | bounded response ไม่มี free text | M10 | 4.1/4.5 | RSH-012/013 | 027 | P |
| AMM-FR-082 | exact four exposure events v1 | M10 | 4.7–4.8 | RSH-004/006/007 | 026 | P |
| AMM-FR-083 | ใช้ EventEnvelopeV2 เดิม | M10 | 4.7–4.8 | RSH-004, OPS-014 | 026,031 | P |
| AMM-FR-084 | nonparticipant zero-row | M10 | 4.5/4.8 | ENT-011, RSH-001/005 | 025 | P |
| AMM-FR-085 | withdrawal หยุด create/enqueue/upload | M10 | 4.5/4.12 | RSH-008/009 | 028 | P |
| AMM-FR-086 | export แยกห้า axes | M10 | 4.12 | RSH-014 | 029 | P |
| AMM-FR-087 | ITT primary; crossover secondary | M10 | 4.13 | RSH-015 | 026,029 | P |
| AMM-FR-088 | ethics/guardian/assent ก่อน collection | M10 / §8 | 5.9 | governance checklist | 025–029 precondition | P/GOV |
| AMM-FR-089 | bounded operational diagnostics | M11 | 5.5–5.7/6.2 | OPS-007/008/011/013 | 004,019,022,031 | P |
| AMM-FR-090 | diagnostics ไม่เก็บ sensitive payload | M11 / §8 | 6.2 | OPS-013 | 031 | P |
| AMM-FR-091 | offline entry เฉพาะ verified revisions | M11/M03 | 2.13/5.5 | JRN-011, OPS-006 | 018 | P |
| AMM-FR-092 | asset removal ไม่ลบ learning/progress | M11 | 5.5 | JRN-010–012 | 019 | P |
| AMM-FR-093 | corrupt bundle repair/remove path | M11 | 5.5 | JRN-010–012, OPS-008 | 019 | P |
| AMM-FR-094 | rollout Hidden→Internal→Pilot→Enabled | M11 / §13 | 5.1/5.10/6.1–6.5 | OPS-015 | 032 | P/GOV |
| AMM-FR-095 | emergency-off rehearsal ก่อน rollout | M11 | 5.7/6.6 | OPS-011/015 | 022,032 | P |
| AMM-FR-096 | unknown payload fail closed | M11 / §6 | 5.5/6.2 | OPS-014 | 031 | P |

## 7. Data Requirements

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-DATA-001 | Phase 1 schema v22 unchanged | M01–M06 / §4 | 1.13 | DAT-001 | 001,005 | P |
| AMM-DATA-002 | preference v2 เพิ่ม home_experience บนเลขที่ reserve จริง | M01 / §4 | 0.11,3.1–3.2 | DAT-002–004 | 003 | P |
| AMM-DATA-003 | codec มี standard/adventure เท่านั้น | M01 | 3.1–3.2 | DAT-005–007 | 003 | P |
| AMM-DATA-004 | migration รักษา v1 fields ทุกค่า | M01 | 3.1–3.2 | DAT-004 | 003 | P |
| AMM-DATA-005 | unknown experience → effective Standard | M01 | 3.2–3.3 | DAT-006/007 | 003,004 | P |
| AMM-DATA-006 | mutation ผ่าน use case/owner gate | M01 | 3.3 | DAT-005/010 | 003,023 | P |
| AMM-DATA-007 | research migration เพิ่มเพียง runs/responses บนเลข reserve จริง | M10 / §4 | 0.11,4.2–4.3 | DAT-003/011 | 025–029 | P |
| AMM-DATA-008 | research identity idempotent/owner-scoped | M10 | 4.3–4.5 | DAT-014, RSH-013 | 020,027 | P |
| AMM-DATA-009 | research rows ครบ owner lifecycle manifest | M10 | 4.11 | DAT-011/012 | 020,021 | P |
| AMM-DATA-010 | guest upgrade รักษา identity ตาม policy | M10/M01 | 3.4,4.11 | DAT-009 | 020 | P |
| AMM-DATA-011 | sync payload versioned/bounded/reject replay | M10 | 3.4,4.9–4.10 | DAT-007/008/014 | 020,026–029 | P |
| AMM-DATA-012 | lifecycle ครอบคลุม preference/research | M10/M11 | 3.4,4.11–4.12 | DAT-009–013 | 020,021,028,029 | P |
| AMM-DATA-013 | schema ledger ห้าม reuse/released edit | §4/§13 | 0.11,3.1,4.2 | DAT-002/003 | pre-build review | P/GOV |

## 8. UI/UX Requirements

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-UI-001 | Material 3/M3Theme | M02/M08/M09 / §7 | 1.7–1.10,3.10 | UX-006/007 | 014,017 | P |
| AMM-UI-002 | Thai glossary + English keys | M03/M08 | 0.17,3.11 | JRN-009, UX-014/015 | 014 | P |
| AMM-UI-003 | CTA loading/disabled/single-flight | M02 | 1.6/1.9 | LRN-003, UX-001 | 006,016 | P |
| AMM-UI-004 | state ไม่พึ่งสี | M02 / §7 | 1.7–1.8 | UX-007 | 015,017 | P |
| AMM-UI-005 | semantics label/role/state/action | M02 / §7 | 1.7–1.12 | UX-003 | 015 | P |
| AMM-UI-006 | focus order ตาม intent | M02 / §7 | 1.12 | UX-003/004 | 015 | P |
| AMM-UI-007 | keyboard ไม่มี trap | M02 / §7 | 1.12 | UX-004 | 015 | P |
| AMM-UI-008 | text 200% ไม่ clip | M02/M09 | 1.12,5.4 | UX-005 | 016 | P |
| AMM-UI-009 | target ≥48×48 | M02 / §7 | 1.12 | UX-005 | 016 | P |
| AMM-UI-010 | reduced motion = zero/static equivalent | M02/M08 | 1.12,3.10 | UX-008 | 013,017 | P |
| AMM-UI-011 | audio มี caption/no-audio | M03/M08 | 3.10–3.11 | UX-009 | 013,017 | P |
| AMM-UI-012 | failure copy actionable/no blame | M02/M08/M11 | 1.10,3.11 | UX-011 | 004,014 | P |
| AMM-UI-013 | Result copy แยกสามแกน | M09 | 2.8–2.9 | REC-012, UX-012 | 011 | P |
| AMM-UI-014 | prompt purpose/Skip/consent details | M10 | 4.6 | RSH-010/011, UX-013 | 027 | P |

## 9. Non-Functional Requirements

| Requirement | Short intent | SDS section | WBS/Gate | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-NFR-001 | feature-off equivalent baseline | §10/§13 | 0.19, BG-12 | ENT-001, LRN-015 | 001 | P |
| AMM-NFR-002 | deterministic/rebuildable journey | §3 M04 | 1.1–1.3 | JRN-001/002/005 | 005 | P |
| AMM-NFR-003 | duplicate reward = 0 | §6 | 2.10/3.6 | LRN-013, REC-009 | 010,012 | P |
| AMM-NFR-004 | evidence ไม่หายเมื่อ projection fail | §6 | 3.7 | REC-007/008 | 012,022 | P |
| AMM-NFR-005 | reject mixed owner before write | §4/§6 | 1.4/2.11 | LRN-004, OPS-010 | 006,023 | P |
| AMM-NFR-006 | missing dependency fallback/no crash | §6 | 1.10/5.5 | ENT-003/006, OPS-008 | 004,019 | P |
| AMM-NFR-007 | restart recovery ตาม lifecycle เดิม | §5/§6 | 2.10–2.11 | LRN-013 | 010,018 | P |
| AMM-NFR-008 | entry local p95 ≤50ms | §9 | 5.3 | OPS-001 | 030 | P |
| AMM-NFR-009 | 3-node projection p95 ≤100ms | §9 | 5.3 | OPS-001 | 030 | P |
| AMM-NFR-010 | meaningful render p95 ≤1.5s | §9 | 5.3 | OPS-002 | 030 | P |
| AMM-NFR-011 | frame/long-task budget | §9 | 5.3 | OPS-004 | 030 | P |
| AMM-NFR-012 | start overhead p95 ≤150ms | §9 | 5.3 | OPS-003 | 030 | P |
| AMM-NFR-013 | measurement commit p95 ≤100ms/nonblocking | §9 | 4.4/5.3 | OPS-001/003 | 027,030 | P |
| AMM-NFR-014 | visual assets ≤5MB/audio separate | §9 | 0.17/5.3 | OPS-005 | 018,019 | P |
| AMM-NFR-015 | Map/List parity 100% | §7 | 1.8/1.12 | UX-002 | 002,005,015 | P |
| AMM-NFR-016 | automated + manual screen reader | §7 | 1.12/5.4 | UX-003/004 | 015 | P |
| AMM-NFR-017 | 200%/dark/contrast/motion coverage | §7 | 5.4 | UX-005–008 | 016,017 | P |
| AMM-NFR-018 | WCAG 2.2 AA contrast | §7 | 5.4 | UX-006/007 | 017 | P |
| AMM-NFR-019 | ไม่มี forced timeout | §7 | 3.11/5.4 | content/widget review | 030 | P |
| AMM-NFR-020 | nonparticipant zero research rows | §8 | 4.5/4.8 | ENT-011, RSH-001/005 | 025 | P |
| AMM-NFR-021 | no free text/answer duplication | §4/§8 | 4.1/4.7 | RSH-012/014 | 027,029 | P |
| AMM-NFR-022 | withdrawal before next enqueue | §5/§8 | 4.5/4.12 | RSH-008/009 | 028 | P |
| AMM-NFR-023 | export/delete owner isolation + manifest | §4/§8 | 4.11–4.12 | DAT-010–013 | 020,021 | P |
| AMM-NFR-024 | diagnostics redact sensitive data | §8 | 6.2 | OPS-013 | 031 | P |
| AMM-NFR-025 | no shame/coercion/false mastery | §7/§8 | 3.11/5.4 | UX-010/011 | 007,011,013,014 | P |
| AMM-NFR-026 | presentation ไม่ import Drift rows | §3/§8 | 1.6–1.11 | architecture test | 001,005 | P |
| AMM-NFR-027 | persisted enum explicit/fail closed | §4/§6 | 0.16/3.2/4.3 | DAT-006/007, OPS-014 | 003,031 | P |
| AMM-NFR-028 | independent payload versions | §4 | 0.16/4.1/4.7 | DAT-007, RSH-014 | 026,029,031 | P |
| AMM-NFR-029 | Drift code generated only | §11 | 3.2/4.3 | generated diff/toolchain gate | pre-build review | P/GOV |
| AMM-NFR-030 | unit tests/doc comments | §12 | all build WPs | code review + family tests | N/A | P |
| AMM-NFR-031 | feature-off ไม่ down-migrate | §13 | 3.2/4.3/6.1 | DAT-015 | 003,022 | P |
| AMM-NFR-032 | 15 baseline findings closed before Pilot | §12/§13 | 0.3–0.9, BG-01–10 | fresh baseline suite | 032 | B→P |
| AMM-NFR-033 | scans/platform/model gates ไม่แย่ลง | §8/§12 | 0.6–0.9, BG-07–11 | Gitleaks/OSV/platform/model/diff | 032 | B→P |

## 10. Business Rules

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-BR-001 | learning authority ชนะ narrative | M04/M06/M09 | 1.3/2.3/2.8 | LRN-001/015, REC-013 | 005,011 | P |
| AMM-BR-002 | resume ก่อน mission ใหม่ | M04/M09 | 1.3/2.11 | JRN-003 | 005,010 | P |
| AMM-BR-003 | review/due ก่อน new work | M04/M05 | 1.3/1.5 | JRN-004 | 005 | P |
| AMM-BR-004 | reward หลัง eligible evidence commit | M07 | 3.5–3.7 | REC-007/008 | 012 | P |
| AMM-BR-005 | presentation action ไม่ให้ reward | M07 | 3.5–3.6 | REC-010 | 012 | P |
| AMM-BR-006 | assessment ไม่ update motivation ledger | M06/M07 | 3.5 | LRN-014 | 024 | P |
| AMM-BR-007 | hint = guided practice | M06 | 2.3 | LRN-008 | 009 | P |
| AMM-BR-008 | evidence หนึ่งให้ side effect อย่างละไม่เกินหนึ่ง | M07 | 3.5–3.7 | LRN-013, REC-009 | 010,012 | P |
| AMM-BR-009 | incorrect/skip/timeout/technical แยก state | M06/M09 | 2.3/2.6 | LRN-009–011, REC-006 | 007–009 | P |
| AMM-BR-010 | technical failure ไม่ลงโทษ | M09 | 2.10/3.11 | REC-006, UX-011 | 009,014 | P |
| AMM-BR-011 | XP/Coins ใช้ ledger semantics เดิม | M07 | 3.6 | REC-008–011 | 012,013 | P |
| AMM-BR-012 | preference ไม่ grant feature | M01 | 3.3 | ENT-002/005, DAT-005 | 003 | P |
| AMM-BR-013 | feature ไม่ assign cohort | M01/M10 | 0.13/4.5 | ENT-010, RSH-002 | 003,026 | P |
| AMM-BR-014 | consent ไม่ imply assignment | M10 | 4.5 | RSH-002/003 | 026 | P |
| AMM-BR-015 | crossover ไม่ rewrite assignment | M10 | 4.8/4.13 | RSH-006/007/015 | 026,029 | P |
| AMM-BR-016 | result axes ไม่รวมคะแนนเดียว | M09 | 2.8–2.9 | REC-012 | 011 | P |
| AMM-BR-017 | world v1 ไม่มี durable branching choice | M03 | 0.16–0.18 | catalog validator/review | 019 | P |
| AMM-BR-018 | catalog เอา Standard fallback ออกไม่ได้ | M01/M03 | 0.18/1.10 | JRN-008–011 | 001,004,019 | P |

## 11. Coverage Summary

| Requirement family | Count | Design mapped | WBS mapped | Verification mapped | Current verified |
|---|---:|---:|---:|---:|---:|
| Functional | 96 | 96 | 96 | 96 | 0 — implementation not started |
| Data | 13 | 13 | 13 | 13 | 0 — planned migrations not created |
| UI/UX | 14 | 14 | 14 | 14 | 0 — wireframe/spec only |
| Non-functional | 33 | 33 | 33 | 33 | 0 Adventure; baseline evidence recorded separately |
| Business rules | 18 | 18 | 18 | 18 | 0 Adventure; authority behavior characterized in Audit |
| **Total** | **174** | **174** | **174** | **174** | **0 Adventure verified** |

## 12. Gate Traceability

| Gate | Requirements chiefly protected | Required evidence |
|---|---|---|
| G0A Implementation-ready | FR-001–010, NFR-001/005/006/026/030 | BL-05/06/07 + worktree bootstrap + touched-foundation green |
| G0B Pilot-ready | NFR-032/033 และทุก safety invariant | ปิด 15 baseline findings + BG-01–BG-12 |
| MS-02 Hidden contract | FR-001–010, NFR-001 | feature-off equivalence |
| MS-03 Read-only preview | FR-011–041, DATA-001 | deterministic/zero-write/schema v22 |
| MS-04 Learning equivalence | FR-042–048/066–075 | exact command/evidence/restart equivalence |
| MS-05 Core motivation | FR-049–065, DATA-002–006 | read-only receipt projection + preference lifecycle |
| MS-06 Research ready | FR-076–090, DATA-007–013 | consent/assignment/rules/sync/export/delete/zero-row |
| MS-07 Internal accepted | UI-001–014, NFR-008–031 | accessibility/offline/performance/UAT |
| MS-08 Pilot accepted | FR-088/094/095, NFR-020–025/032/033 | protocol approvals, Pilot UAT, guardrails |

## 13. RTM Change Control Checklist

- [ ] SRS requirement count/IDs ยังเป็น FR 96, DATA 13, UI 14, NFR 33, BR 18
- [ ] ไม่มี requirement ถูกลบหรือเปลี่ยนความหมายโดยไม่มี approved change request
- [ ] SDS interface/module รองรับทุก requirement ที่เปลี่ยน
- [ ] WBS dependency/effort/owner ถูกปรับตามผลกระทบ
- [ ] Automated test และ UAT reference มีอยู่จริง
- [ ] Requirement ที่กระทบ schema/rules/events มี version/ledger review
- [ ] Requirement ที่กระทบผู้เยาว์/วิจัยมี Privacy/Research review
- [ ] Actual evidence อ้าง commit/build/environment เดียวกัน
- [ ] Feature-off/Standard fallback coverage ยังครบ
- [ ] Product Owner, QA Lead และ Tech Lead อนุมัติ matrix revision

## 14. Approval

| Role | Decision | Name | Date | Notes |
|---|---|---|---|---|
| Business Analyst | Approve / Revise |  |  |  |
| QA Lead | Approve / Revise |  |  |  |
| UX/Product Owner | Approve / Revise |  |  |  |
| Tech Lead | Approve / Revise |  |  |  |
| Research/Privacy Owner | Approve / N/A / Revise |  |  |  |
