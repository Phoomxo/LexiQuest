# Terms of Reference (TOR) — Adventure Motivation Mode

**Document ID:** LQ-AMM-TOR-001
**Version:** 1.0
**Status:** Draft for Owner Review
**Date:** 2026-09-01
**Project baseline:** LexiQuest 8/44 at commit `99f7fb21`, schema v22
**Audit reference:** `AMM-AUDIT-001 v1.0` — 3,202 Flutter tests pass / 15 fail; Pilot and production remain blocked
**Decision references:** `LQ-AMM-ADR-001 v1.0`, `LQ-AMM-MDS-001 v1.0`
**Document type:** Internal product-engineering TOR; procurement price and commercial payment terms are outside scope

## 1. Background

LexiQuest มีระบบเรียนหลักที่รวม Today Hub, Learning Pack, Unified Lesson Shell, Feedback/Hint, Review/SRS, History, Recommendation, Quest, Gentle Streak, Achievement, Avatar/Cosmetic, XP/Coins, consent และ experiment infrastructure อยู่แล้ว โครงการนี้เพิ่ม Adventure Motivation Mode เพื่อช่วยให้ผู้เรียนอยากเริ่มและกลับมาเรียน โดยเปลี่ยนวิธีนำเสนอและเชื่อมแรงจูงใจกับผลการเรียนเดิม ไม่สร้างระบบคำศัพท์หรือระบบคะแนนอีกชุด

มีหน้าจอเดิม `lib/screens/learning_world_map_screen.dart` ซึ่งเป็น static orphan ไม่มี production caller และใช้ screen-owned CEFR nodes หน้าจอนี้ไม่ใช่ฐานข้อมูลหรือ authority ของ Adventure ใหม่ โครงการจะไม่คืนชีพ class ดังกล่าวเป็น production flow; นำมาใช้ได้เฉพาะเป็น historical UX reference เท่านั้น

## 2. Project Purpose

สร้าง Adventure presentation ทางเลือกเหนือ Today Hub ที่:

1. ทำให้ผู้เรียนเห็นภารกิจวันนี้และเริ่มเรียนได้ง่าย;
2. แสดงความคืบหน้าในรูปแผนที่โดยอิง canonical state;
3. ใช้คำตอบ Feedback, Review/SRS และหลักฐานชุดเดียวกับ Standard;
4. ตอบผิดได้โดยไม่ถูกลงโทษ;
5. วัดแรงจูงใจแยกจาก engagement และ learning;
6. ปิดหรือถอด Adventure ได้โดยไม่ทำให้ข้อมูล 8/44 เสียหาย

## 3. Objectives

### 3.1 Product objectives

- เพิ่มสัดส่วนผู้ใช้ที่เริ่ม session ที่ระบบแนะนำด้วยความสมัครใจ
- เพิ่มการกลับมาเรียนโดยไม่ใช้ความกลัวเสีย streak หรือ progress
- ลด cognitive load โดยมี primary mission เดียวและเวลาโดยประมาณ
- ให้ผู้เรียนสลับกลับ Standard ได้ตลอดเวลา
- รักษาหรือปรับปรุง learning guardrails เทียบกับ Standard

### 3.2 Engineering objectives

- ทำ Adventure เป็น bounded context 11 โมดูลที่สื่อสารผ่าน typed interfaces
- ใช้ read model ที่ rebuild ได้และไม่มี Adventure-owned progression
- ใช้ local-first commit, outbox, idempotency และ owner lifecycle เดิม
- ให้ feature hidden เป็นค่าเริ่มต้นและมี emergency-off
- ทำ preference v2 และ research measurement ด้วย forward-only migration โดยใช้เลข v23/v24 เฉพาะเมื่อ schema ledger ยังว่าง มิฉะนั้น rebase ไปเลขถัดไป
- มี test evidence และ UAT evidence ก่อนแต่ละ rollout gate

### 3.3 Research objectives

- เปรียบเทียบ Standard กับ Adventure บน learning core เดียวกัน
- รักษา stable assignment โดยไม่ให้ feature flag หรือ preference เปลี่ยน cohort
- วัด Motivation, Engagement, Effort, Learning และ Outcome แยกแกน
- รองรับ Skip, withdrawal, export และ deletion
- เก็บเฉพาะ bounded response/event data ที่ protocol อนุมัติ

## 4. Scope of Work

### 4.1 In scope

| Scope ID | งาน |
|---|---|
| TOR-S01 | เพิ่ม `Feature.adventureMotivation` แบบ fail-closed และ production contract |
| TOR-S02 | Additive entry `learn/today-experience` ภายใน Learn surface และ Product entry decision ที่รวม availability, dependency, preference, assignment และ fallback โดยไม่มี consent เป็น input |
| TOR-S03 | Adventure shell: map/list, mission card, companion area, status/error/fallback states |
| TOR-S04 | Versioned World/Story/Asset Catalog แบบ immutable และตรวจ checksum/localization/graph |
| TOR-S05 | Journey Projection จาก Today Hub, Quest, Streak, Achievement, Reward, History และ pack completion |
| TOR-S06 | Session Composer ที่ใช้ canonical content/recommendation/review และ duration policy เดิม |
| TOR-S07 | Learning Bridge ไป Unified Lesson Shell โดยใช้ `AdventureOriginContextV1` เป็น transient application metadata เท่านั้น ไม่เพิ่มลง evidence/answer envelope |
| TOR-S08 | Motivation projection ที่อ่านผล side effect ซึ่ง `LearningSideEffectReconciler` commit แล้ว; Adventure ห้ามเรียก grant/mutation ของ Quest/Streak/Achievement/Reward โดยตรง |
| TOR-S09 | Scripted companion, equipped avatar/cosmetics และ supportive copy |
| TOR-S10 | Result, wrong-answer repair, resume/restart และ Standard fallback |
| TOR-S11 | Preference v2 บน migration number ที่จองจริง พร้อม sync/export/delete/guest upgrade และ staged rollout จาก session-local |
| TOR-S12 | Research measurement บน migration number ที่จองจริง และ consented exposure events v1 |
| TOR-S13 | Accessibility, localization, offline asset verify/repair/remove และ reduced motion |
| TOR-S14 | Diagnostics, test automation, UAT, rollout gates และ emergency-off rehearsal |

### 4.2 Out of scope

- ระบบ vocabulary, SRS, mastery, recommendation หรือ scoring ใหม่
- Durable branching story choices
- Adventure-specific XP, coin, heart, life, energy หรือ relationship score
- Pay-to-continue, loot box หรือ reward ที่กระทบโอกาสเรียน
- Generative AI companion, AI tutor integration หรือ remote executable scripts
- Camera/object-scanner quest
- Multiplayer, friend, room, chat, social network หรือ public leaderboard
- Achievement share card ใน treatment แรก
- การลบหรือ refactor `LearningWorldMapScreen` ซึ่งต้องเป็น cleanup change แยก
- bottom-navigation destination ใหม่หรือการแทนที่ Learn screen เดิม
- การกำหนด sample size/effect size โดยไม่มี protocol และ power analysis
- Production enablement ก่อนผ่าน Pilot

## 5. Target Users and Stakeholders

### 5.1 User groups

| กลุ่ม | ความต้องการสำคัญ | Design response |
|---|---|---|
| ผู้เริ่มเรียน | ไม่รู้ว่าจะเริ่มตรงไหน | Primary mission เดียว คำอธิบายสั้น เวลาโดยประมาณ |
| ผู้เรียนต่อเนื่อง | ต้องการเห็นความก้าวหน้า | Journey จาก canonical progress และ next unlock |
| ผู้กลับมาหลังหยุด | กลัวเสีย streak/ตามไม่ทัน | Recovery copy, no punishment, resumable session priority |
| ผู้ตอบผิดบ่อย | ต้องการความช่วยเหลือไม่ใช่โทษ | Contrastive feedback, recall ladder, bounded repair |
| ผู้มีเวลาจำกัด | ต้องการควบคุมระยะเวลา | Duration options จาก existing session policy; ไม่มี forced timer |
| ผู้ใช้ screen reader/large text | ต้องการ action parity | Map-list parity, semantics, focus order, text scaling |
| ผู้ไวต่อ animation/audio | ต้องการลดสิ่งกระตุ้น | Reduced/zero motion และ no-audio alternative |
| ผู้ใช้ offline | ต้องการเรียนต่อได้ | Verified local assets, Standard fallback, local evidence commit |
| ผู้เยาว์ | ต้องการการคุ้มครองเพิ่มเติม | Product ใช้ได้โดยไม่เข้าวิจัย; research ต้องผ่าน ethics/permission/assent |
| ผู้เข้าร่วมวิจัย | ต้องการรู้และควบคุมข้อมูล | consent, Skip, crossover visibility, withdrawal/export/delete |

### 5.2 Stakeholders

- Product Owner: ตัดสิน scope, copy, rollout และ final acceptance
- Sponsor: อนุมัติทรัพยากรและ Pilot
- CTO/Tech Lead: authority, architecture, data contract และ technical gate
- UX/Product Designer: flow, accessibility, copy และ visual acceptance
- Flutter Engineers: implementation และ automated tests
- Data/Research Lead: protocol, instrument, analysis และ data quality
- QA Lead: test plan, evidence, defect gate และ UAT coordination
- Privacy/Ethics Reviewer: consent, minor participation, retention, withdrawal
- Content/Localization Owner: world/story copy, Thai/English glossary และ asset QA
- Operations/Release Owner: feature flags, monitoring, emergency-off และ rollback rehearsal
- Learner/UAT Participants: usability and acceptance feedback

## 6. Required Logical Modules

| Module | Name | TOR responsibility |
|---|---|---|
| M01 | Delivery & Entry Control | Learn-surface entry, availability, preference, assignment และ typed fallback; ไม่อ่าน consent |
| M02 | Experience Shell | Render-only Adventure surface and state handling |
| M03 | World, Story & Asset Catalog | Immutable versioned definitions and validation |
| M04 | Journey Projection | Rebuildable map from canonical readers |
| M05 | Session Composer | Canonical work → pinned Adventure session plan |
| M06 | Learning Session & Evidence Bridge | Unified Lesson Shell and evidence context integration |
| M07 | Motivation & Unlock Projection Reader | อ่าน canonical committed/pending receipts โดยไม่ grant หรือ mutate |
| M08 | Companion, Avatar & Narrative Reaction | Scripted supportive presentation |
| M09 | Result, Recovery & Review Continuity | Result axes, repair, resume and fallback |
| M10 | Research & Experiment Measurement | Stable assignment, consent, instruments and events |
| M11 | Operations, Quality & Reliability | Validation, diagnostics, lifecycle and rollout gates |

## 7. Deliverables and Acceptance

| Deliverable ID | Deliverable | Minimum acceptance evidence |
|---|---|---|
| D01 | Approved TOR/SRS/SDS/ADR/MDS/RTM | Signed review record; zero unresolved authority conflict; measurement decision complete |
| D02 | Feature and entry contract foundation | Contract tests prove hidden default, no cohort assignment, no bottom-tab change, Learn-surface parity and old override compatibility |
| D03 | World Catalog v1 + validator | Stable IDs, acyclic graph, complete locales, checksum and asset QA tests pass |
| D04 | Read-only Adventure shell | Golden/widget/accessibility tests; zero domain writes; Standard escape visible |
| D05 | Journey Projection | Deterministic/rebuild tests from identical canonical input |
| D06 | Session Composer | Same canonical work and reasons as Standard for treatment-safe input |
| D07 | Learning Bridge | One response → one canonical evidence identity; no envelope mutation |
| D08 | Wrong-answer/recovery flow | Repair spacing/limit, restart, offline and fallback tests pass |
| D09 | Motivation integration | Adventure has no grant path; canonical receipts remain idempotent in retry/restart; assessment isolation passes |
| D10 | Preference v2/planned schema v23 | actual ledger number reserved; v22→new matrix, sync, guest-upgrade, export/delete tests pass |
| D11 | Research/planned schema v24 | actual ledger number reserved; consent, assignment, bounded response, events, withdrawal and retention tests pass |
| D12 | UI/UX and content bundle | Thai/English, map-list parity, text scaling, reduced motion, asset checks |
| D13 | Test report | Required suites run in approved Flutter environment; no unresolved blocker/critical defect |
| D14 | UAT report | Required UAT scenarios pass with denominator/numerator and minimum sample from MDS; deviations dispositioned; sign-off recorded |
| D15 | Rollout package | Android Pilot matrix, explicit platform/capability exclusions, Internal/Pilot/Enabled gates, monitoring, emergency-off rehearsal and rollback record |

## 8. Technical Constraints

1. Flutter/Dart และ Material 3 ตาม repository เดิม
2. Drift schema v22 เป็น baseline; migration ใหม่ต้องลง schema ledger ก่อนแก้ code
3. `EventEnvelopeV2.schemaVersion == 2` คงเดิมใน scope นี้
4. Adventure presentation ห้าม import Drift tables
5. Application layer พึ่ง interface; data adapters implement interface
6. UI ห้ามคำนวณ correctness, mastery weight หรือ reward eligibility
7. `FeatureRegistry` เป็น availability authority เท่านั้น
8. `ExperimentRegistry` เป็น assignment authority เท่านั้น
9. `ConsentRegistry` เป็น research-processing eligibility authority เท่านั้น
10. `LearnerPreferences` v2 เป็น home-experience preference authority เท่านั้น
11. Date/time ที่ persist ต้องเป็น UTC; user-facing streak ใช้ existing timezone policy
12. Owner identities ต้อง canonical และ mixed-owner input ต้องถูก reject
13. Side effects ใช้ deterministic idempotency key และ replay-safe receipt
14. Assets ต้องมี stable ID, version, SHA-256 checksum, locale และ QA state
15. Remote content เป็น data only; ห้าม executable behavior

## 9. User Experience Constraints

- Adventure ต้องไม่ทำให้ผู้ใช้ถูกบังคับอยู่ในโหมดนี้
- Switch to Standard ต้องเห็นโดยไม่ scroll
- Primary CTA ต่อหน้าจอไม่เกินหนึ่ง action ที่เด่นที่สุด
- Assessment ต้องไม่ถูกแต่งเป็น reward mission
- ตอบผิดต้องได้ feedback ที่บอกความแตกต่างและทางช่วย
- Repair ใน session เกิดหลัง 3–5 intervening items; ถ้าเหลือไม่พอให้ส่งไป Review/SRS
- ไม่มี progress loss เมื่อ pause, timeout, app crash หรือ technical failure
- Questionnaire ต้อง Skip ได้และอยู่ที่ natural breakpoint
- Map state ต้องใช้ shape/icon/text ไม่พึ่งสีอย่างเดียว
- Touch target ขั้นต่ำ 48×48 logical pixels
- Text scaling 200% ต้องไม่ซ่อน action สำคัญ
- Motion ต้องเป็นศูนย์ได้เมื่อ platform/user ขอ reduced motion

## 10. Data and Privacy Conditions

- Phase 1 ไม่มี schema change และ presentation choice เป็น session-local
- Phase 3 วางแผนใช้ schema v23 เพิ่ม `home_experience`, preferenceVersion 2, default `standard`; implementation ต้องตรวจ ledger และ rebase ถ้า v23 ถูกใช้แล้ว
- Phase 4 วางแผนใช้ schema v24 เพิ่ม `motivation_measurement_runs` และ `motivation_responses`; implementation ต้องตรวจ ledger และ rebase ถ้า v24 ถูกใช้แล้ว
- Research exposure events สร้างเฉพาะ measurement run ที่ consented และ assigned
- Payload ไม่มี free text, raw story copy, duplicated answer หรือ provider data
- Consent withdrawal หยุด enqueue/upload ใหม่ทันที
- Deletion และ export ต้องครอบคลุมทุก owner-scoped row ตาม lifecycle manifest
- Retention ต้องถูกกำหนดใน protocol ก่อน Pilot
- Product Adventure ต้องใช้ได้โดยไม่ให้ research consent

## 11. Quality Gates

### G0A — Implementation-ready baseline

- worktree มี local package configuration จาก approved offline dependency bootstrap
- BL-05, BL-06 และ BL-07 ใน `AMM-AUDIT-001` ถูกปิด เพราะกระทบ schema guard, architecture guard และ bootstrap seam ที่ Adventure จะใช้
- screen/route ledger ปัจจุบันได้รับอนุมัติและ `LearningWorldMapScreen` ไม่ถูกใช้เป็น authority
- targeted foundation suites ไม่มี unclassified failure
- worktree สะอาดก่อน production change แรก

### G0B — Pilot/release-ready baseline

- shared/touched-foundation failures ถูกปิดทั้งหมด และ baseline finding ทุกข้อมี owner/disposition ที่ตรวจย้อนกลับได้
- full Flutter inventory suite รันจริงทั้ง approved concurrency; logical/shared/touched set ต้องผ่าน และ failure ที่เหลือต้อง map เป็น approved explicit exclusion โดยไม่มี unclassified failure
- Gitleaks/OSV findings มี remediation หรือ approved time-bounded disposition ตาม release policy
- Android Pilot v1 capability matrix ผ่านทุก gate ที่ reachable
- iOS, desktop, AI Voice และ field-model ระบุเป็น excluded ไม่ใช่ passed; ยัง block การเปิดบน platform/capability นั้น

### G1 — Feature-off equivalence

- Adventure hidden by default
- ไม่มี navigation entry เมื่อ hidden
- Standard scenarios ให้ผลเทียบเท่า baseline

### G2 — Learning semantics equivalence

- Standard/Adventure สร้าง canonical plan เทียบเท่ากันเมื่อ input เดียวกัน
- one submission → one answer/evidence identity
- assessment ไม่มี motivation side effects

### G3 — Data lifecycle

- migration, sync, owner isolation, guest upgrade, export, withdrawal, deletion, retention ผ่าน
- forward-only rollback เปิด app รุ่นก่อนหน้าได้ตาม compatibility policy หรือถูก block ด้วยข้อความปลอดภัยที่กำหนด

### G4 — Accessibility and resilience

- screen reader, map-list parity, 200% text, reduced motion, offline, corrupt bundle, restart และ emergency-off ผ่าน

### G5 — Pilot readiness

- stable assignment 100%
- required version metadata 100%
- duplicate reward known path 0
- unresolved blocker/critical defect 0
- protocol/instrument/scoring/sample-size method pre-registered
- เกณฑ์ motivation/learning guardrail และ sample-size calculation ผ่าน `LQ-AMM-MDS-001`
- Pilot report ระบุ Android-only และ capability exclusions
- UAT sign-off ครบ

## 12. Project Approach

ทำงาน 7 ระยะภายใต้ 4 independently closable increments ตาม ADR-004:

1. Phase 0 Baseline and contracts
2. Phase 1 Read-only shell
3. Phase 2 Learning bridge and recovery
4. Phase 3 Preference, motivation and companion
5. Phase 4 Research instrumentation
6. Phase 5 Internal and consented Pilot
7. Phase 6 Controlled enablement

แต่ละ phase ต้องส่งมอบ software ที่ทดสอบได้เอง มี reviewer gate และ commit แยก ห้าม merge phase ถัดไปเมื่อ exit gate ก่อนหน้ายังไม่ผ่าน งาน protocol ที่ไม่เขียน production state ทำคู่ขนานได้ตาม WBS

หลัง Phase 2 ต้องมี **MS-04 Product MVP decision**: Accept/Stop/Continue การหยุดหลัง Phase 1 หรือ Phase 2 เมื่อ gate ผ่านเป็น bounded successful outcome และไม่บังคับให้ทำ preference/research migration

## 13. Governance and RACI Summary

| Decision | Accountable | Responsible | Consulted | Informed |
|---|---|---|---|---|
| Scope/priority | Product Owner | Project Manager | CTO, UX, Research | Team |
| Architecture/schema/event | CTO | Tech Lead | QA, Privacy, Data | Product Owner |
| UX/copy/accessibility | Product Owner | UX Designer | Accessibility reviewer, learners | Engineering |
| Research protocol | Research Lead | Data/Research team | Privacy/Ethics, CTO | Product Owner |
| Test release gate | QA Lead | QA + Engineers | CTO, UX | Product Owner |
| Feature rollout/emergency-off | Product Owner | Release Owner | CTO, QA | Stakeholders |
| Final UAT acceptance | Product Owner | UAT Lead | Learner participants, QA | Sponsor |

## 14. Assumptions

- 8/44 source ที่ commit `99f7fb21` เป็น functional source of truth แต่ยังไม่ถือว่า release-clean จนกว่า Audit gates จะผ่าน
- Existing authority interfaces พร้อมใช้งานหรือปรับแบบ additive ได้
- World v1 ใช้หนึ่ง world และสาม visible nodes เพื่อลดตัวแปร
- Companion v1 ใช้ scripted catalog เท่านั้น
- Pilot มี consented participants และ protocol ที่อนุมัติแล้ว
- ไม่มีการเพิ่ม third-party SDK สำหรับ Adventure v1

## 15. Dependencies

- Today Hub snapshot/readers
- Unified Lesson Controller/Shell และ Lesson Mode Registry
- Evidence/learning event store และ outbox
- Review/SRS/Recommendation/History
- Quest, Gentle Streak, Achievement, Reward
- Learner Preferences, Experiment Registry, Consent Registry
- Owner lifecycle, guest upgrade, export/delete, sync engine
- Offline Content Manager และ content manifest
- Material 3 theme, accessibility scope และ navigation glossary

## 16. Principal Risks

| Risk | Severity | Control |
|---|---|---|
| Adventure กลายเป็น progress authority | Critical | No progress table; projection-only architecture tests |
| Reward ทำให้ผลวิจัย learning ปนเปื้อน | High | Separate axes, assessment isolation, eligible-event policy |
| Preference เปลี่ยน assignment | Critical | Separate repositories and invariant tests |
| Retry ให้รางวัลซ้ำ | Critical | Evidence ID causation + idempotent receipts |
| UI แผนที่เข้าไม่ถึง | High | List parity, semantics, focus and scaling tests |
| Wrong-answer loop ทำให้ผู้ใช้ท้อ | High | One repair maximum, no padding, SRS deferral |
| Asset เสียทำให้เข้าเรียนไม่ได้ | High | Quarantine, repair, Standard fallback |
| Research เก็บข้อมูลโดยไม่ยินยอม | Critical | Consent-aware recorder, rules tests, withdrawal gate |
| Schema migration ทำ owner data เสีย | Critical | v1→current matrix, backup fixture, exact field preservation |
| Baseline ทดสอบซ้ำไม่ได้ | High | G0 blocks implementation until clean evidence |
| Today Hub มี implementation แต่ hidden ทำให้ entry source ใช้งานไม่ได้ | High | ADR-001 กำหนด internal route และ additive card ใน Learn; ห้ามเพิ่ม bottom tabหรือเปิด production card ก่อน canonical Today path พร้อม |
| Preference v2 local/cloud version ไม่ตรงกัน | Critical | staged local→migration→rules/sync rollout และ fail closed |
| Baseline 15 failures หรือ Gitleaks/OSV debt ถูกมองข้าม | Critical | Audit gate และ fresh evidence ก่อน Pilot/release |

## 17. Completion Definition

Full program ถือว่าเสร็จเมื่อ:

1. Deliverables D01–D15 ผ่าน acceptance;
2. Requirement ทุกข้อใน RTM มี design owner และ test evidence;
3. UAT required cases ผ่าน 100%;
4. ไม่มี unresolved blocker/critical defect;
5. Standard fallback และ emergency-off rehearsal ผ่าน;
6. Research lifecycle ผ่านกรณี consent, Skip, crossover, withdrawal, export และ deletion;
7. Pilot evidence ได้รับอนุมัติให้ Enabled หรือมีการตัดสินใจเก็บ Hidden อย่างเป็นทางการ

การเขียนโค้ดครบแต่ gate เหล่านี้ไม่ผ่าน ไม่ถือว่าโครงการเสร็จ

Product Core MVP ถือว่าส่งมอบสำเร็จแยกได้เมื่อ Phase 2/MS-04 ผ่าน แม้ Product Owner ตัดสินใจ Stop และไม่อนุมัติ Increment C/D; ในกรณีนั้นต้อง archive decision/evidence, เก็บ feature hidden และไม่มี schema migration

## 18. Approval Record

การอนุมัติ TOR ต้องบันทึกใน review/commit record ด้วยข้อความที่ระบุ `LQ-AMM-TOR-001 v1.0` พร้อมชื่อบทบาท วันที่ และ decision อย่างใดอย่างหนึ่ง: `Approved`, `Approved with recorded conditions`, `Revise`, `Rejected` การอนุมัติด้วยเงื่อนไขต้องเชื่อม issue IDs ที่ปิดได้ก่อน G3
