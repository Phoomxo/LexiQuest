# Requirements Traceability Matrix — Adventure Motivation Mode

**Document ID:** LQ-AMM-RTM-001
**Version:** 1.3
**Status:** As-built engineering overlay recorded; external acceptance pending
**Date:** 2026-09-04; evidence update 2026-09-05
**Requirements source:** `02-srs.md` v1.2
**Design source:** `03-sds.md` v1.3
**Delivery source:** `04-project-plan-wbs.md` v1.2
**Verification sources:** `06-test-plan-and-test-cases.md` v1.2 และ `07-uat-script.md` v1.3
**Decision sources:** `00b-architecture-decision-records.md` และ `09-measurement-decision-spec.md` v1.2

## 1. วิธีใช้ Matrix

RTM นี้ทำให้ requirement ทุกข้อมี design owner, work package และ verification
evidence ที่วางแผนไว้ ตาราง requirement เดิมเก็บสถานะ planning baseline เพื่อ
ไม่สร้าง UAT/owner acceptance เทียม และใช้ §12.1 เป็น execution overlay ที่
authoritative สำหรับ implementation รอบปัจจุบัน

| Code | ความหมาย |
|---|---|
| `P` | Planned — มี design/work/test ครบ แต่ยังไม่มี execution evidence |
| `B` | Baseline evidence — ตรวจระบบปัจจุบันแล้ว ไม่ใช่ผล Adventure |
| `I` | Implemented — ใช้หลัง code review เท่านั้น |
| `V` | Verified — ต้องมี fresh command/device/UAT evidence |
| `A` | Accepted — Product/UAT sign-off แล้ว |
| `GOV` | Governance/manual evidence เป็นหลัก |
| `V-AUTO` | Verified เฉพาะ automated/local engineering; manual/device/UAT ส่วนที่เกี่ยวข้องยังไม่ผ่าน |
| `BLOCKED` | ยังเริ่มไม่ได้เพราะขาด approval, participant evidence หรือ separate delivery authorization |

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
| AMM-FR-003 | eligible additive Learn card; no bottom tab | ADR-001 / M01 | 0.10,0.12,1.11 | ENT-001/003/004, UX-001/015 | 001,002 | P |
| AMM-FR-004 | unauthorized hidden/disabled/unknown/stale route → Learn; authorized Host may Standard fallback | ADR-001 / M01 | 0.14,1.10–1.14 | ENT-002/003/006/013 | 001,004,035 | P |
| AMM-FR-005 | feature state ไม่แก้ assignment | M01/M10 | 0.13,4.5 | ENT-010 | 003,026 | P |
| AMM-FR-006 | Phase 1 session choice; Phase 3 preference | M01 | 1.9,3.3 | ENT-004/005, DAT-005 | 002,003 | P |
| AMM-FR-007 | switch ไม่ rewrite stable assignment | M01/M10 | 4.5,4.8 | ENT-010, RSH-006 | 003,026 | P |
| AMM-FR-008 | Product Entry มี UUID/pins; active projection only, no raw receipts | ADR-002 / M01 | 0.14,0.16,4.15 | ENT-002–006/014/015, RSH-016–020 | 002–004,026,035 | P |
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
| AMM-FR-048 | pre-session opportunity; mission session link; neutral deterministic occurrence | ADR-003 / M06/M10 | 4.7–4.8/4.16 | LRN-006, RSH-004–007/021–024 | 025,026,036 | P |
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
| AMM-FR-078 | protocol treatment/collect เมื่อ signed permit+run ครบ | M01/M10 | 4.5/4.8/4.15 | RSH-001–004/016–020 | 025,026,033–035 | P |
| AMM-FR-079 | prompt ที่ breakpoint, Skip ได้ | M10 | 4.6 | RSH-010/011, UX-013 | 027 | P |
| AMM-FR-080 | measurement run pins versions | M10 / §4 | 4.1–4.5 | RSH-004/014/015 | 026,029 | P |
| AMM-FR-081 | bounded response ไม่มี free text | M10 | 4.1/4.5 | RSH-012/013 | 027 | P |
| AMM-FR-082 | exact four neutral events v1 for both treatments | M10 | 4.7–4.8/4.16 | RSH-004/006/007/021–024 | 026,036 | P |
| AMM-FR-083 | ใช้ EventEnvelopeV2 เดิม | M10 | 4.7–4.8 | RSH-004, OPS-014 | 026,031 | P |
| AMM-FR-084 | nonparticipant zero-row | M10 | 4.5/4.8 | ENT-011, RSH-001/005 | 025 | P |
| AMM-FR-085 | withdrawal หยุด create/enqueue/upload | M10 | 4.5/4.12 | RSH-008/009 | 028 | P |
| AMM-FR-086 | export แยกห้า axes | M10 | 4.12 | RSH-014 | 029 | P |
| AMM-FR-087 | ITT primary; crossover secondary | M10 | 4.13 | RSH-015 | 026,029 | P |
| AMM-FR-088 | minor guardian+assent runtime permit | M10 / §8 | 4.15/4.17/5.14 | RSH-017–020, UX-016/017 | 033,034 | P |
| AMM-FR-089 | bounded operational diagnostics | M11 | 5.5–5.7/6.2 | OPS-007/008/011/013 | 004,019,022,031 | P |
| AMM-FR-090 | diagnostics ไม่เก็บ sensitive payload | M11 / §8 | 6.2 | OPS-013 | 031 | P |
| AMM-FR-091 | offline entry เฉพาะ verified revisions | M11/M03 | 2.13/5.5 | JRN-011, OPS-006 | 018 | P |
| AMM-FR-092 | asset removal ไม่ลบ learning/progress | M11 | 5.5 | JRN-010–012 | 019 | P |
| AMM-FR-093 | corrupt bundle repair/remove path | M11 | 5.5 | JRN-010–012, OPS-008 | 019 | P |
| AMM-FR-094 | rollout Hidden→Internal→Limited→Controlled→Enabled | M11 / §13 | 5.1/5.10/5.13/6.7–6.9 | OPS-015–017 | 032,038 | P/GOV |
| AMM-FR-095 | emergency-off rehearsal ก่อน rollout | M11 | 5.7/6.6 | OPS-011/015 | 022,032 | P |
| AMM-FR-096 | unknown payload fail closed | M11 / §6 | 5.5/6.2 | OPS-014 | 031 | P |
| AMM-FR-097 | validate signed permit; Product Entry sees active projection only | M01/M10 / ADR-002 | 4.15 | DAT-017/018, RSH-016–020 | 033–035 | P |
| AMM-FR-098 | withdrawal/expiry/revocation fallback without learning loss | M01/M10 | 4.15/5.7 | ENT-015, DAT-021, OPS-018 | 028,035 | P |
| AMM-FR-099 | neutral symmetric events for both treatments | M10 / ADR-003 | 4.16 | RSH-021/022/024 | 036 | P |
| AMM-FR-100 | participant opportunity ledger; nonparticipant zero-row | M10 / §4 | 4.16 | DAT-022, RSH-023 | 025,036 | P |
| AMM-FR-101 | one UUID v4 per Host opening, reuse on rebuild/retry/switch | M01/M10 | 1.14/4.16 | ENT-014, DAT-020 | 035,036 | P |
| AMM-FR-102 | one Today load; pure Standard/Adventure views share snapshot | M01/M02 / ADR-006 | 1.14 | ENT-014 | 035,036 | P |
| AMM-FR-103 | guardian-led minor permit; age-band/no guardian PII | M10 / ADR-007 | 4.15/4.17 | DAT-017/019, UX-016/017 | 033,034 | P |
| AMM-FR-104 | adult/minor class-specific release isolation | M11 / ADR-008 | 4.19/6.7–6.9 | RSH-027, OPS-017 | 038 | P |

## 7. Data Requirements

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-DATA-001 | Phase 1 schema v22 unchanged | M01–M06 / §4 | 1.13 | DAT-001 | 001,005 | P |
| AMM-DATA-002 | preference v2 เพิ่ม home_experience บนเลขที่ reserve จริง | M01 / §4 | 0.11,3.1–3.2 | DAT-002–004 | 003 | P |
| AMM-DATA-003 | codec มี standard/adventure เท่านั้น | M01 | 3.1–3.2 | DAT-005–007 | 003 | P |
| AMM-DATA-004 | migration รักษา v1 fields ทุกค่า | M01 | 3.1–3.2 | DAT-004 | 003 | P |
| AMM-DATA-005 | unknown experience → effective Standard | M01 | 3.2–3.3 | DAT-006/007 | 003,004 | P |
| AMM-DATA-006 | mutation ผ่าน use case/owner gate | M01 | 3.3 | DAT-005/010 | 003,023 | P |
| AMM-DATA-007 | research migration เพิ่ม 4 tables บนเลข reserve จริง | M10 / §4 | 0.11,4.2–4.3/4.15–4.16 | DAT-003/011/016 | 025–036 | P |
| AMM-DATA-008 | research identity idempotent/owner-scoped | M10 | 4.3–4.5 | DAT-014, RSH-013 | 020,027 | P |
| AMM-DATA-009 | research rows ครบ owner lifecycle manifest | M10 | 4.11 | DAT-011/012 | 020,021 | P |
| AMM-DATA-010 | guest upgrade รักษา identity ตาม policy | M10/M01 | 3.4,4.11 | DAT-009 | 020 | P |
| AMM-DATA-011 | sync payload versioned/bounded/reject replay | M10 | 3.4,4.9–4.10 | DAT-007/008/014 | 020,026–029 | P |
| AMM-DATA-012 | lifecycle ครอบคลุม preference/research | M10/M11 | 3.4,4.11–4.12 | DAT-009–013 | 020,021,028,029 | P |
| AMM-DATA-013 | schema ledger ห้าม reuse/released edit | §4/§13 | 0.11,3.1,4.2 | DAT-002/003 | pre-build review | P/GOV |
| AMM-DATA-014 | participation permit lifecycle/rules/sync/export/withdraw/delete/retention | M10 / §4 | 4.9–4.12/4.15 | DAT-016–019/021 | 020,021,028,033–035 | P |
| AMM-DATA-015 | opportunity lifecycle + transactional switch/suppression | M10 / §4 | 4.9–4.12/4.16 | DAT-016/019/020/022 | 025,036 | P |

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
| AMM-UI-015 | guardian permission flow and no-learning-impact copy | M10 / UX-12 | 4.17/5.14 | UX-016/019/020 | 033,037 | P |
| AMM-UI-016 | age-banded independent learner assent | M10 / UX-13 | 4.17/5.14 | UX-017/019/020 | 034,037 | P |
| AMM-UI-017 | invalid/expired/revoked permit product-continuation UX | M01/M10 / UX-14/15 | 4.17/5.15 | UX-018–020 | 035,037 | P |

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
| AMM-NFR-032 | shared foundation clean + Android scoped dispositions | ADR-005 / §12/§13 | 0.3–0.9, BG-01–10 | fresh logical/Android matrix | 032 | B→P |
| AMM-NFR-033 | scans/platform/model gates ไม่แย่ลง | §8/§12 | 0.6–0.9, BG-07–11 | Gitleaks/OSV/platform/model/diff | 032 | B→P |
| AMM-NFR-034 | one loader call and snapshot identity per Host | §3 M01/§10 | 1.14 | ENT-014 | 035,036 | P |
| AMM-NFR-035 | offline signed-permit validation fail closed | §3 M10/§8 | 4.15/5.15 | DAT-018/021, RSH-020 | 035,037 | P |
| AMM-NFR-036 | >15% total or >5pp arm missing post blocks efficacy | MDS §7 | 4.18/6.4–6.5 | RSH-026/027 | 038 | P |
| AMM-NFR-037 | adult/minor rollout isolation | §13 / ADR-008 | 4.19/6.7–6.9 | OPS-017 | 038 | P |

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
| AMM-BR-019 | active permit precedence; no raw receipts in Product Entry | M01/M10 | 4.15 | ENT-010/015, RSH-016 | 026,035 | P |
| AMM-BR-020 | no permit → session choice → preference → Standard; zero research rows | M01/M10 | 1.14/4.15 | ENT-015, DAT-022 | 025,035 | P |
| AMM-BR-021 | minor requires guardian + assent runtime evidence | M10 | 4.15/4.17 | RSH-017–019 | 033,034 | P |
| AMM-BR-022 | MS-08A ceiling is Limited | M11 / ADR-008 | 5.13/5.17 | OPS-016 | 038 | P/GOV |
| AMM-BR-023 | MS-08B powered decision separate per class | M11 / MDS | 6.4–6.9 | RSH-027, OPS-017 | 038 | P/GOV |

## 11. Pair Matching Prototype Requirements

### 11.1 Functional requirements

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-FR-105 | reuse f10/matching route/shell/gateway; no f45 | ADR-009 / M12 / §15 | PM0, PM8 | PMT-001/044 | 039,050 | P |
| AMM-FR-106 | contextual Learn/Today/Review/Adventure entry; no main menu | M12 / §15.1 | PM1, PM6 | PMT-001–004/043 | 039,049 | P |
| AMM-FR-107 | immutable pinned PairMatchingPlanV1 | ADR-010 / M12 / §15.2 | PM1, PM2 | PMT-002–012/040 | 039–041,050 | P |
| AMM-FR-108 | entry-owned canonical source; Adventure does not recompose | ADR-010 / M12 / §15.3 | PM1, PM7 | PMT-002–004/042 | 039,050 | P |
| AMM-FR-109 | merge provenance before rank/deduplicate | M12 / §15.3 | PM1 | PMT-004/005 | 039 | P |
| AMM-FR-110 | reject unsafe/colliding content; exact 4/6 | ADR-010 / M12 / §15.3 | PM1 | PMT-007–009/012 | 039–041 | P |
| AMM-FR-111 | one EN→TH or TH→EN direction per session | M12 / §15.2 | PM1, PM2 | PMT-010/011 | 041 | P |
| AMM-FR-112 | explicit compact4/standard6 product preference | M12 / §15.2 | PM1, PM6 | PMT-006–008 | 040 | P |
| AMM-FR-113 | selection reducer creates no answer evidence before submit | M12 / §15.4 | PM2 | PMT-013/014 | 041,042 | P |
| AMM-FR-114 | mismatch evidence attaches once to prompt word only | M12 / §15.4 | PM2, PM3 | PMT-011/016 | 042 | P |
| AMM-FR-115 | matched progress monotonic on success only | ADR-011 / M12 / §15.4 | PM2, PM3 | PMT-015/016 | 042 | P |
| AMM-FR-116 | supportive wrong state plus repair ticket; no penalty | ADR-011 / M12 / §15.4 | PM3, PM6 | PMT-016–021 | 042 | P |
| AMM-FR-117 | delayed repair after 2/3 distinct correct pairs | ADR-011 / M12 / §15.4 | PM3 | PMT-017–019 | 042 | P |
| AMM-FR-118 | tail guided completion and canonical Review deferral | ADR-011 / M12 / §15.4 | PM3 | PMT-020/021 | 042 | P |
| AMM-FR-119 | visible pronunciation neutral; revealing support guided | ADR-011 / M12 / §15.5 | PM3, PM6 | PMT-022–024 | 043 | P |
| AMM-FR-120 | timer default off; explicit 60/90/120 | ADR-012 / M12 / §15.6 | PM4 | PMT-025 | 044 | P |
| AMM-FR-121 | active-interaction timer with bounded pause reasons | ADR-012 / M12 / §15.6 | PM4 | PMT-026 | 044 | P |
| AMM-FR-122 | durable timeoutDecision; no false answer/completion | ADR-012 / M12 / §15.6 | PM4 | PMT-027/028 | 045 | P |
| AMM-FR-123 | +30 seconds once, idempotent and durable | ADR-012 / M12 / §15.6 | PM4 | PMT-029/031 | 046 | P |
| AMM-FR-124 | timeout restart is same session/new round/exact set | ADR-012 / M12 / §15.6 | PM4 | PMT-030/031 | 045,046 | P |
| AMM-FR-125 | stars derived from committed terminal ledger | ADR-012 / M12 / §15.7 | PM5 | PMT-032–037 | 047 | P |
| AMM-FR-126 | versioned 3/2/1 star thresholds | ADR-012 / M12 / §15.7 | PM5 | PMT-032–036 | 047 | P |
| AMM-FR-127 | time/timely status presentation-only | ADR-012 / M12 / §15.6–15.7 | PM4, PM5 | PMT-028/037 | 044,045,047 | P |
| AMM-FR-128 | Practice Replay is new linked practice session | ADR-012 / M12 / §15.7 | PM5 | PMT-038–040 | 048 | P |
| AMM-FR-129 | Practice Replay has zero authority/reward/research-primary delta | ADR-012 / M12 / §15.7 | PM5, PM7 | PMT-038/039/042 | 048,050 | P |
| AMM-FR-130 | Standard/Adventure share normalized contracts | ADR-009/013 / M12 / §15.8 | PM7, PM8 | PMT-042–044 | 039,047,050 | P |

### 11.2 Data requirements

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-DATA-016 | plan/checkpoint pins exact lexical and policy inputs | M12 / §15.2 | PM1, PM2 | PMT-002–012/040 | 039–041,050 | P |
| AMM-DATA-017 | checkpoint carries selection/progress/repair/timer/extension state | M12 / §15.2/15.4/15.6 | PM2–PM4 | PMT-013–031/040/041 | 042,044–046 | P |
| AMM-DATA-018 | learning/replay purpose and round lineage are distinct | M12 / §15.2/15.7 | PM4, PM5 | PMT-030/038–040 | 045,046,048 | P |
| AMM-DATA-019 | owner-scoped density preference separate from research | M12 / §15.2 | PM1 | PMT-006–008/040 | 040 | P |
| AMM-DATA-020 | star read model is rebuildable; never a balance | M12 / §15.5/15.7 | PM5 | PMT-032–039 | 047,048 | P |
| AMM-DATA-021 | bounded pair telemetry and lifecycle | M12 / §15.5 | PM5, PM7 | PMT-024/038/042 | 043,048,050 | P |

### 11.3 UI/UX requirements

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-UI-018 | contextual source/count/timer setup; one CTA | UI §17.1–17.2 / M12 | PM1, PM6 | PMT-001–008/025 | 039,040,044 | P |
| AMM-UI-019 | balanced constrained two-column regular layout | UI §17.3 / M12 | PM6 | PMT-010/043 | 041,049 | P |
| AMM-UI-020 | focused equivalent layout at narrow/200%/assistive | UI §17.3/17.9 / M12 | PM6 | PMT-037/043 | 049 | P |
| AMM-UI-021 | 56/64px tiles, 48px actions, multimodal state | UI §17.4/17.9 / M12 | PM6 | PMT-043 | 042,049 | P |
| AMM-UI-022 | supportive wrong/repair explanation | UI §17.5 / M12 | PM3, PM6 | PMT-016–021/043 | 042 | P |
| AMM-UI-023 | neutral timeout sheet and action hierarchy | UI §17.6 / M12 | PM4, PM6 | PMT-027–031/043 | 045,046,049 | P |
| AMM-UI-024 | result separates evidence, stars and elapsed time | UI §17.7 / M12 | PM5, PM6 | PMT-032–039/043 | 047–049 | P |
| AMM-UI-025 | history separates normal and Practice Replay | UI §17.7 / M12 | PM5, PM6 | PMT-038/039/043 | 048,049 | P |
| AMM-UI-026 | Thai-first/localized/TTS-safe copy; brand protected | UI §17.9 / M12 | PM6 | PMT-009/024/043 | 041,043,049 | P |
| AMM-UI-027 | Adventure changes theme only; hierarchy parity | UI §17.10 / M12 | PM7 | PMT-037/042–044 | 039,047,050 | P |

### 11.4 Non-functional requirements

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-NFR-038 | deterministic plan/shuffle/repair/restart/stars | M12 / §15.2–15.7 | PM1–PM5 | PMT-005/017–021/030–037 | 040,042,046,047 | P |
| AMM-NFR-039 | start session/checkpoint atomically after revalidation | M12 / §15.3 | PM1, PM2 | PMT-008/009/031/040 | 039–041,046 | P |
| AMM-NFR-040 | reader-first checkpoint evolution and no retroactive inference | ADR-013 / M12 / §15.9 | PM0, PM8 | PMT-040/044 | 050 | P |
| AMM-NFR-041 | coalesced bounded persistence with terminal reserve | M12 / §15.5/15.6 | PM2–PM5 | PMT-026/031/041 | 044–047 | P |
| AMM-NFR-042 | responsive local board; audio/network nonblocking | UI §17.3 / M12 | PM6 | PMT-024/026/043 | 043,044,049 | P |
| AMM-NFR-043 | accessibility across all pair states/layouts | UI §17.9 / M12 | PM6 | PMT-022/024/043 | 043–049 | P |
| AMM-NFR-044 | owner/callback/TTS privacy fences | M12 / §15.3/15.5 | PM1–PM3, PM7 | PMT-008/014/024/040 | 039,043,050 | P |
| AMM-NFR-045 | normalized cross-renderer parity | ADR-013 / M12 / §15.8 | PM7 | PMT-037/042 | 039,047,050 | P |
| AMM-NFR-046 | hidden delivery control and safe accepted-session lifecycle | ADR-009/013 / M12 / §15.9 | PM7, PM8 | PMT-001/044 | 039,050 | P |

### 11.5 Business rules

| Requirement | Short intent | SDS/Module | WBS | Verification | UAT | Status |
|---|---|---|---|---|---|---|
| AMM-BR-024 | Pair prototype is f10 semantic revision, not f45 | ADR-009 / M12 | PM0, PM8 | PMT-001/044 | 039,050 | P |
| AMM-BR-025 | entry source owns plan; provenance merges before rank | ADR-010 / M12 | PM1 | PMT-002–005 | 039 | P |
| AMM-BR-026 | exact 4/6; explicit downgrade; <4 unavailable | ADR-010 / M12 | PM1 | PMT-006–008 | 039,040 | P |
| AMM-BR-027 | explicit density/guardian precedence; no inference | M12 / §15.2 | PM1 | PMT-006–008 | 040 | P |
| AMM-BR-028 | wrong records truth without progress/reward penalty | ADR-011 / M12 | PM2, PM3 | PMT-015/016 | 042 | P |
| AMM-BR-029 | repair counts distinct successes; tail to Review | ADR-011 / M12 | PM3 | PMT-017–021 | 042 | P |
| AMM-BR-030 | visible speech neutral; revealing mapping is support | ADR-011 / M12 | PM3 | PMT-022–024 | 043 | P |
| AMM-BR-031 | timer neutral; Continue untimed always available | ADR-012 / M12 | PM4 | PMT-025–031/037 | 044–047 | P |
| AMM-BR-032 | stars are descriptive projection only | ADR-012 / M12 | PM5 | PMT-032–039 | 047,048 | P |
| AMM-BR-033 | timeout restart/replay/technical retry stay distinct | ADR-012 / M12 | PM4, PM5 | PMT-029–031/038–041 | 046,048 | P |
| AMM-BR-034 | presentation-only renderer difference and layered flags | ADR-013 / M12 | PM7, PM8 | PMT-042–044 | 039,050 | P |

## 12. Coverage Summary

| Requirement family | Count | Design mapped | WBS mapped | Verification mapped | Current verified |
|---|---:|---:|---:|---:|---:|
| Functional | 130 | 130 | 130 | 130 | Adventure product FR-001–075, FR-089–093, FR-095–096 and FR-101–102 are I/V-AUTO; research/rollout and Pair ranges remain Planned/BLOCKED |
| Data | 21 | 21 | 21 | 21 | DATA-002–006 are I/V-AUTO on schema v23; research DATA-007–015 and Pair DATA-016–021 remain BLOCKED |
| UI/UX | 27 | 27 | 27 | 27 | UI-001–013 have automated implementation evidence; physical assistive-tech/UAT remains pending; research and Pair UI remain BLOCKED |
| Non-functional | 46 | 46 | 46 | 46 | Product invariants and source-gated host-GPU emulator performance have local evidence; certified physical-device performance/manual accessibility, research efficacy and Pair gates remain pending/BLOCKED |
| Business rules | 34 | 34 | 34 | 34 | Product authority/repair/reward rules have local evidence; research decisions and Pair rules remain Planned/BLOCKED |
| **Total** | **258** | **258** | **258** | **258** | **No requirement is marked A; local verification cannot substitute for owner/UAT acceptance** |

### 12.1 As-built execution overlay

| Scope | Status | Actual evidence |
|---|---|---|
| G0A, MS-02, MS-03, MS-04, MS-05 product implementation | I/V-AUTO | Checkpoint records `docs/development/2026-09-04-adventure-motivation-checkpoint-0.md`, `-2.md`, `-3.md`, `-4.md`; source through `be2ef6db` |
| Task 6.1 diagnostics/catalog recovery | I/V-AUTO | Adventure diagnostics, download adapter and recovery suites are included in the 391-test focused product result |
| Task 6.2 automated responsive/accessibility/media scope | V-AUTO | 34 dedicated tests; 320px/text 200%/dark/high-contrast/reduced-motion/no-audio coverage; packaged visual/audio bytes = 0 |
| Task 6.2 Android performance rehearsal | V-AUTO | Source `85b17755`; 187/187 runner contracts; pre/post source clean; Android 15 Pixel 6 host-GPU emulator passed all budgets with 20/20 real-frame transitions, frame p95 4.290 ms and maximum 7.031 ms; evidence remains `emulator_rehearsal` / `not_certified` |
| Task 6.2 physical accessibility/performance | Pending external | TalkBack, Switch Access, keyboard traversal and approved physical-device profiles are not yet signed; emulator evidence cannot satisfy this gate |
| Task 6.3 BG-01–BG-12 Android/shared scope | V-AUTO | `docs/development/2026-09-04-adventure-motivation-checkpoint-6-local-verification.md`; 3,403 full Flutter tests pass default and serial with four explicit release exclusions |
| Task 6.4 UAT/MS-08A/MS-08B | BLOCKED/Not Run | `07-uat-script.md` v1.3 records required cohorts, denominators, signatures and the missing research/device prerequisites; no UAT result is fabricated |
| M10 research implementation | BLOCKED | No approved MDS/protocol/instrument/form/response-code/power/analysis/privacy-ethics package; schema/capture intentionally absent |
| M12 Pair PM0–PM8 | BLOCKED | Pair ADR/SRS/SDS/RTM v1.2 and separate delivery authorization are not approved |

The executable feature map remains revision 1.3.0 with exactly 44 product
capabilities and hash
`41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`.
The schema-v23 Final 8/44 Test Plan fingerprint is
`ec068b590b05103e2c33f2dbcd51bd570e37262b15cf175f7a6826d3e19b9b81`.

## 13. Gate Traceability

| Gate | Requirements chiefly protected | Required evidence |
|---|---|---|
| G0A Implementation-ready | FR-001–010, NFR-001/005/006/026/030 | BL-05/06/07 + worktree bootstrap + touched-foundation green |
| G0B Android Pilot-ready | NFR-032/033 และทุก safety invariant | shared/touched foundation clean + scoped BG-01–BG-12 + explicit exclusions |
| MS-02 Hidden contract | FR-001–010, NFR-001 | feature-off equivalence |
| MS-03 Read-only preview | FR-011–041, DATA-001 | deterministic/zero-write/schema v22 |
| MS-04 Product Core MVP decision | FR-042–048/066–075 | exact command/evidence/restart equivalence + Accept/Stop/Continue record |
| MS-05 Core motivation | FR-049–065, DATA-002–006 | read-only receipt projection + preference lifecycle |
| MS-06 Research ready | FR-076–103, DATA-007–015 | permit/opportunity/neutral events/rules/sync/export/delete/zero-row |
| MS-07 Internal accepted | UI-001–017, NFR-008–035 | product + research-flow accessibility/offline/performance/UAT |
| MS-08A Feasibility | FR-088/094/095/097–103, NFR-020–025/032–035, BR-021/022 | protocol, permit, data quality, comprehension, safety; Limited ceiling |
| MS-08B Efficacy per class | FR-104, NFR-036/037, BR-023 | powered ANCOVA/MI/tipping, learning/safety/missingness, UAT-038 |
| G4P Pair Prototype contract | FR-105–130, DATA-016–021, UI-018–027, NFR-038–046, BR-024–034 | PMT-001–044 + UAT-039–050 + no-new-menu/f45/star-ledger proof |
| PM-A Contract/engine proof | FR-105–119, DATA-016–019, BR-024–030 | exact-plan/reducer/repair/property tests; no production rollout |
| PM-B Interaction prototype | FR-120–127, UI-018–027, NFR-041–045 | timer/stars/accessibility/parity prototype evidence |
| PM-C Replay/integration readiness | FR-128–130, DATA-018/020/021, NFR-040/046 | replay zero-delta, reader-first compatibility and rollback evidence |

## 13.1 Decision and Measurement Traceability

| Decision/measurement | Requirements protected | WBS | Test/UAT evidence |
|---|---|---|---|
| ADR-001 Learn entry/no bottom tab | FR-003/004/010/101, NFR-001/006 | 0.10/0.12/1.11/1.14 | ENT-001–006/013/014, UX-001/015, UAT-001/002/004/035/036 |
| ADR-002 Active presentation permit | FR-005/007/008/076–085/097/098, BR-012–015/019/020 | 0.14/4.5/4.8/4.15 | ENT-010/011/015, RSH-001–020, UAT-025–035 |
| ADR-003 Neutral events/opportunity | FR-048/082/083/096/099/100, DATA-015, NFR-020/027/028 | 4.7/4.8/4.16 | RSH-004–007/021–024, OPS-014, UAT-026/036 |
| ADR-004 MVP stop point | DATA-001/002/007/013, NFR-031 | 1.13/2.14/3.1/4.2 | DAT-001–003/015, MS-04 decision |
| ADR-005 Android Pilot scope | FR-094/095, NFR-032/033 | 0.6–0.9/5.2/5.10 | BG-01–12, OPS-015, UAT-032 |
| ADR-006 Single-load Today snapshot | FR-101/102, NFR-034 | 1.14 | ENT-014, UAT-035/036 |
| ADR-007 Runtime minor participation | FR-088/103, DATA-014, UI-015/016, BR-021 | 4.15/4.17/5.14 | DAT-017–019, RSH-017–020, UX-016/017, UAT-033/034 |
| ADR-008 Feasibility/Efficacy split | FR-094/104, NFR-036/037, BR-022/023 | 5.13/5.17/6.4–6.9 | RSH-027, OPS-016/017, UAT-038 |
| ADR-009 Reuse f10/M12 boundary | FR-105/106/130, NFR-046, BR-024/034 | PM0/PM7/PM8 | PMT-001/042–044, UAT-039/050 |
| ADR-010 Immutable entry-aware exact plan | FR-107–112, DATA-016/019, NFR-038/039, BR-025–027 | PM1 | PMT-002–012, UAT-039–041 |
| ADR-011 Progress/evidence/repair semantics | FR-113–119, DATA-017, BR-028–030 | PM2/PM3 | PMT-013–024, UAT-042/043 |
| ADR-012 Timer/stars/restart/replay semantics | FR-120–129, DATA-018/020, BR-031–033 | PM4/PM5 | PMT-025–041, UAT-044–048 |
| ADR-013 Adaptive renderer and rollback | FR-130, UI-019/020/027, NFR-040/043/045/046, BR-034 | PM6–PM8 | PMT-040/042–044, UAT-049/050 |
| MDS primary motivation/guardrails | FR-078–088/104, NFR-020–025/036/037 | 4.1/4.13/4.18/6.4–6.7 | RSH-001–027, UAT-025–038 |
| MDS Pair process/learning guardrails | FR-113–129, DATA-020/021, NFR-045, BR-028–033 | PM3–PM7 | PMT-013–043, UAT-042–049; replay excluded from primary denominator |
| MDS UAT sample | UI-001–017, NFR-015–019/025/035 | 5.4/5.8/5.12/5.14/5.15 | UX-001–020, UAT denominators/sign-off |

## 14. RTM Change Control Checklist

- [ ] SRS requirement count/IDs ยังเป็น FR 130, DATA 21, UI 27, NFR 46, BR 34 รวม 258
- [ ] ไม่มี requirement ถูกลบหรือเปลี่ยนความหมายโดยไม่มี approved change request
- [ ] SDS interface/module รองรับทุก requirement ที่เปลี่ยน
- [ ] WBS dependency/effort/owner ถูกปรับตามผลกระทบ
- [ ] Automated test และ UAT reference มีอยู่จริง
- [ ] Requirement ที่กระทบ schema/rules/events มี version/ledger review
- [ ] Requirement ที่กระทบผู้เยาว์/วิจัยมี Privacy/Research review
- [ ] Actual evidence อ้าง commit/build/environment เดียวกัน
- [ ] Feature-off/Standard fallback coverage ยังครบ
- [ ] Automated test inventory 188 และ UAT inventory 50; ทุก RTM reference resolve ได้
- [ ] MS-08A ไม่ชี้ Enabled และ MS-08B แยก adult/minor
- [ ] Pair Matching ยัง map กลับ `f10`; ไม่มี `f45`, main menu, star currency/ledger หรือ replay side effect
- [ ] PMT-001–044 และ UAT-039–050 resolve ได้; reader-first/Standard fallback/Adventure parity ครบ
- [ ] Product Owner, QA Lead และ Tech Lead อนุมัติ matrix revision

## 15. Approval

| Role | Decision | Name | Date | Notes |
|---|---|---|---|---|
| Business Analyst | Approve / Revise |  |  |  |
| QA Lead | Approve / Revise |  |  |  |
| UX/Product Owner | Approve / Revise |  |  |  |
| Tech Lead | Approve / Revise |  |  |  |
| Research/Privacy Owner | Approve / N/A / Revise |  |  |  |
