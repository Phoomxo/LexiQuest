# Software Requirements Specification (SRS) — Adventure Motivation Mode

**Document ID:** LQ-AMM-SRS-001
**Version:** 1.1
**Status:** Draft for Owner Review
**Date:** 2026-09-01
**Baseline:** LexiQuest 8/44, commit `99f7fb21`, schema v22
**Audit reference:** `AMM-AUDIT-001 v1.0`; current baseline is suitable for planning but not Pilot/release clean
**Decision references:** `LQ-AMM-ADR-001 v1.1`, `LQ-AMM-MDS-001 v1.1`

## 1. Purpose and Scope

เอกสารนี้ระบุพฤติกรรมที่ตรวจสอบได้ของ Adventure Motivation Mode โดยใช้คำว่า “ระบบต้อง” สำหรับ mandatory requirement และให้ requirement ID คงที่เพื่อเชื่อม SDS, WBS, automated test และ UAT

Adventure เป็น presentation ทางเลือกของ Today Hub ไม่ใช่ learning system แยก ความถูกต้อง คำศัพท์ SRS/Mastery Recommendation Quest/Streak/Reward และ History ยังคงอยู่กับ authority เดิม

## 2. Product Context

```text
Learner
  └─ Existing Learn surface
       └─ additive `home/learn/today-experience` entry (eligible only)
            ├─ Product Entry Decision: flag/dependency/preference/assignment
            ├─ Standard Today presentation ────────────────────────────────┐
            └─ Adventure presentation                                     │
                 ├─ Journey Projection ◄─ canonical readers               │
                 ├─ Session Composer ◄─ Today Hub work                    │
                 └─ Unified Lesson Shell ── Evidence Gateway ─────────────┤
                                                                         ▼
                                    SRS/Mastery/History/Quest/Streak/Reward
                                                                         │
                                             Result/Recovery ◄────────────┘
```

## 3. Actors

| Actor ID | Actor | Responsibility |
|---|---|---|
| ACT-01 | Learner | เลือก presentation เริ่ม/หยุด/ทำภารกิจ ดูผล และควบคุม consent |
| ACT-02 | Guest learner | ใช้ local-first profile และ upgrade owner ได้ภายหลัง |
| ACT-03 | Product Owner | อนุมัติ copy, rollout, UAT และ emergency-off |
| ACT-04 | Content/Localization Owner | จัดการ world/story catalog และ QA assets/locales |
| ACT-05 | Research Lead | กำหนด protocol, treatment, instrument และ analysis |
| ACT-06 | Release Operator | เปลี่ยน feature state และดำเนิน rollback rehearsal |
| ACT-07 | Existing LexiQuest authorities | ให้ canonical data และรับ typed commands |
| ACT-08 | Sync/Cloud backend | รับ owner-scoped outbox ตาม consent/rules |

## 4. Definitions

- **Canonical work:** งานที่ Today Hub/Review/Recommendation เดิมระบุ
- **Mission:** การนำ canonical work หนึ่งชุดมาแสดงใน Adventure
- **Node:** ตัวแทนเชิงภาพของ canonical state; ไม่ใช่ persisted progress
- **Accepted session:** session ที่ Unified Lesson Controller เริ่มและมี lifecycle identity แล้ว
- **Eligible evidence:** evidence ที่ authority เดิมอนุญาตให้กระตุ้น motivation side effects
- **Repair round:** การนำข้อที่ผิดกลับมาหนึ่งครั้งหลังมี 3–5 intervening items
- **Natural breakpoint:** ก่อนเริ่ม session, หลัง session ปิดสำเร็จ หรือหน้า research transition ที่ไม่ขวางการเรียน
- **Product entry decision:** การเลือก presentation โดยไม่อ่าน consent และไม่มีอำนาจสร้าง assignment/preference
- **Research capture decision:** การอนุญาตบันทึก research record จาก assignment + consent + active run; ไม่มีอำนาจเปลี่ยน presentation

## 5. Assumptions and Constraints

1. Standard Today Hub สร้างได้โดยไม่ขึ้นกับ Adventure
2. Current database schema คือ v22
3. `EventEnvelopeV2` มี 22 fields และ schemaVersion 2 ซึ่ง freeze
4. Flutter Material 3 และ `M3Theme` เป็น UI foundation
5. Thai เป็น primary copy; English locale ต้อง resolve ครบก่อน Pilot
6. Adventure v1 มีหนึ่ง world, สาม visible nodes และ scripted companion
7. Network ไม่เป็น prerequisite ของ canonical local learning เมื่อ content มีในเครื่อง
8. `dailyContinuity`/Today Hub is hidden in current production defaults; Adventure remains hidden until its canonical read dependency and Standard fallback both pass
9. Current learner preference wire/rules contract is v1; durable `home_experience` requires a complete v2 migration/codec/rules/sync rollout
10. Pilot v1 เป็น Android-only; iOS/desktop/AI Voice/field-model ที่ excluded ไม่ถือว่าผ่านและต้องมี gate ของตนก่อน enable

## 6. Functional Requirements

### 6.1 M01 — Delivery and Entry Control

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-001 | ระบบต้องเพิ่ม `Feature.adventureMotivation` โดยไม่เปลี่ยนชื่อหรือลำดับ serialized name เดิม | Contract test |
| AMM-FR-002 | `BuildFeatureRegistry.fieldDefaults()` ต้องกำหนด Adventure เป็น `hidden` | Unit/architecture test |
| AMM-FR-003 | Additive card `home/learn/today-experience` ต้องอยู่ใน Learn surface เดิม แสดงเมื่อ feature visible/enabled และ dependencies พร้อมเท่านั้น; ห้ามเพิ่ม bottom-navigation destination | Widget/integration/architecture test |
| AMM-FR-004 | hidden/disabled/unknown configuration หรือ stale direct route ต้องกลับ Learn โดยไม่สร้าง Host/snapshot/research row; Standard fallback อนุญาตเฉพาะ Host ที่ผ่าน entry authorization แล้ว | Unit/navigation test |
| AMM-FR-005 | Feature state ต้องไม่สร้าง เปลี่ยน หรือลบ experiment assignment | Research isolation test |
| AMM-FR-006 | Outside protocol ระบบต้องใช้ session choice ใน Phase 1 และ `LearnerPreferences.homeExperience` ตั้งแต่ Phase 3 | Unit/migration test |
| AMM-FR-007 | Inside protocol ระบบต้องเก็บ stable assignment เดิม แม้ผู้เรียน switch to Standard | Integration test |
| AMM-FR-008 | Product Entry ต้องมี entryAttemptId, availability, effective presentation, fallback reason/version pins และรับได้เฉพาะ `ActivePresentationPermit` projection โดยห้ามอ่าน raw consent/guardian/assent receipt หรือ measurement response | Unit/architecture test |
| AMM-FR-009 | Emergency-off ต้องบล็อก new Adventure start แต่ไม่ทำลาย accepted learning session | Scenario test |
| AMM-FR-010 | Standard escape ต้องพร้อมโดยไม่ต้อง scroll บนทุก Adventure screen ระดับบน | Widget/UAT |

### 6.2 M02 — Experience Shell

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-011 | Shell ต้อง render จาก `AdventureJourneySnapshot` และห้ามเขียน repository โดยตรง | Architecture test |
| AMM-FR-012 | Shell ต้องมี map view และ list view ที่ action/progress meaning เท่ากัน | Widget/accessibility test |
| AMM-FR-013 | หน้าหลักต้องมี primary mission เพียงหนึ่งรายการที่เด่นที่สุด | Golden/UAT |
| AMM-FR-014 | Shell ต้องรองรับ loading, empty, stale, corrupt, offline, unavailable และ ready states | Widget test |
| AMM-FR-015 | ทุก asynchronous action ต้องป้องกัน double-submit และแสดง recoverable failure | Widget test |
| AMM-FR-016 | Shell ต้องไม่แสดง mastery, XP หรือ reward claim ก่อน canonical receipt | Integration test |
| AMM-FR-017 | การสลับ map/list ต้องไม่เปลี่ยน selection, assignment หรือ canonical data | Widget test |

### 6.3 M03 — World, Story and Asset Catalog

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-018 | Catalog ทุกชุดต้องมี catalog ID, semantic version, locale, checksum และ QA state | Validator test |
| AMM-FR-019 | World, chapter, node, story fragment และ reaction IDs ต้อง unique และ stable | Validator test |
| AMM-FR-020 | Node prerequisite graph ต้องไม่มี cycle และ reference ต้อง resolve | Validator test |
| AMM-FR-021 | Catalog ต้องกำหนดทั้ง visual metadata และ accessible list label | Unit test |
| AMM-FR-022 | Asset manifest ต้องระบุ SHA-256, byte size, media type และ content revision | Unit test |
| AMM-FR-023 | Runtime ต้องไม่ execute script หรือ code ที่ได้จาก remote catalog | Architecture/manual review |
| AMM-FR-024 | Missing locale key หรือ checksum mismatch ต้อง quarantine bundle และ fallback Standard | Integration test |
| AMM-FR-025 | `LearningWorldMapScreen` เดิมต้องไม่ถูกใช้เป็น catalog หรือ production entry ของ Adventure | Architecture test |

### 6.4 M04 — Journey Projection

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-026 | Projection ต้องรับ Today Hub, Quest, Streak, Achievement, Reward, History, pack completion และ catalog ผ่าน read interfaces | Unit/architecture test |
| AMM-FR-027 | Input ที่เหมือนกันทุก version ต้องให้ `AdventureJourneySnapshot` ที่เท่ากัน | Determinism test |
| AMM-FR-028 | Snapshot ต้องระบุ source freshness และ dependency state ของแหล่งที่ใช้ | Unit test |
| AMM-FR-029 | Node state ต้องเป็นหนึ่งใน hidden, locked, available, current, completed หรือ unavailable | Unit test |
| AMM-FR-030 | ระบบต้องไม่สร้าง `adventure_progress` row/table | Schema/architecture test |
| AMM-FR-031 | Review due จากคำที่เคยผิดต้องแสดงเป็น Review node ที่อ้าง word identity เดิม | Integration test |
| AMM-FR-032 | Resumable accepted session ต้องมาก่อน new mission | Unit/UAT |
| AMM-FR-033 | Partial dependency failure ต้องลดเฉพาะ node ที่พึ่ง dependency นั้นและรักษา Standard fallback | Unit/integration test |

### 6.5 M05 — Session Composer

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-034 | Composer ต้องใช้ canonical Today Hub work และห้าม query vocabulary catalog ชุดที่สอง | Architecture test |
| AMM-FR-035 | Due/review work ต้อง admitted ก่อน new work ตาม existing policy | Unit test |
| AMM-FR-036 | Recommendation reason และ learner override ต้องไม่สูญหาย | Unit test |
| AMM-FR-037 | Saved item ต้องหมายถึง learner intent ไม่ถูกแปลงเป็น weakness อัตโนมัติ | Unit test |
| AMM-FR-038 | Duration choice ต้องใช้ existing session configuration policy | Unit/integration test |
| AMM-FR-039 | Plan ต้อง pin owner, plan ID, source evaluation time, content IDs/revisions, modes, policy, recommendation, catalog และ treatment versions | Unit test |
| AMM-FR-040 | Composer ต้อง reject mixed-owner, stale-incompatible หรือ unresolved content input | Negative unit test |
| AMM-FR-041 | Retry ของ request identity เดิมต้องสร้าง plan identity เดิมหรือผล conflict ที่กำหนด ไม่สร้าง mission ซ้ำ | Idempotency test |

### 6.6 M06 — Learning Session and Evidence Bridge

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-042 | Adventure ต้องเริ่มเรียนผ่าน `UnifiedLessonController`/Unified Lesson Shell เดิม | Integration test |
| AMM-FR-043 | Bridge ต้องรับ `AdventureOriginContextV1` เป็น transient launch context และห้ามเพิ่มมันใน `EvidenceContext` หรือ learning-answer payload | Contract test |
| AMM-FR-044 | Learning answer event type, correctness, evidence class และ mastery semantics ต้องเหมือน Standard | Equivalence test |
| AMM-FR-045 | หนึ่ง learner submission ต้อง map ไป evidence identity เดียวข้าม retry/restart | Scenario test |
| AMM-FR-046 | Adventure UI ต้องไม่เรียก Drift learning tables หรือ repositories โดยตรง | Architecture test |
| AMM-FR-047 | Assessment session ต้องไม่ถูก wrap เป็น reward-granting mission | Research isolation test |
| AMM-FR-048 | Participant pre-session events ต้องใช้ `MeasurementOpportunity/opportunityId`; mission start/completion ผูก accepted `LearningSession/learningSessionId` และ opportunity เดิม; ทุก event pin assigned/effective presentation และ nonparticipant ไม่มี persisted origin/opportunity row | Contract/privacy/idempotency test |

### 6.7 M07 — Motivation and Unlock Projection Reader

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-049 | Motivation projection ต้องทำงานหลัง eligible evidence และ canonical side effects commit สำเร็จเท่านั้น | Integration test |
| AMM-FR-050 | Adventure ต้องอ่านผล Quest, Gentle Streak, Achievement และ Reward จาก authority เดิมผ่าน read ports; ห้ามเรียก grant/mutation โดยตรง | Architecture test |
| AMM-FR-051 | Opening map หรือ viewing story ต้องไม่ให้ XP, Coin, quest progress หรือ reward | Negative test |
| AMM-FR-052 | Assessment evidence ต้องไม่ให้ motivation side effect | Isolation test |
| AMM-FR-053 | Hint-assisted response ต้องคงเป็น guided practice ตาม evidence policy | Integration test |
| AMM-FR-054 | Canonical side-effect receipt ที่ Adventure แสดงต้องผูก source evidence ID และ deterministic idempotency key จาก authority เดิม | Unit/integration test |
| AMM-FR-055 | Replay/restart ของ evidence เดิมต้องไม่ให้ reward/unlock ซ้ำ | Scenario test |
| AMM-FR-056 | Cosmetic purchase/equip ต้องไม่ลด lifetime XP | Regression test |

### 6.8 M08 — Companion, Avatar and Narrative Reaction

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-057 | Reaction ต้องเลือกจาก versioned scripted catalog ตาม committed state | Unit test |
| AMM-FR-058 | Companion ต้องไม่สร้าง free text ด้วย AI | Architecture/content test |
| AMM-FR-059 | Equipped avatar/cosmetic ต้องอ่านจาก Reward ownership เดิม | Integration test |
| AMM-FR-060 | Incorrect, hint, skip, return และ completion ต้องมี supportive reaction ที่ไม่ claim mastery เกินจริง | Content/UAT |
| AMM-FR-061 | Companion ต้องไม่มี relationship score หรือ punishment state | Schema/architecture test |
| AMM-FR-062 | Reaction ทุกแบบต้องมี reduced-motion และ no-audio equivalent | Accessibility test |
| AMM-FR-063 | Copy ต้องไม่ shame การหยุดเรียน ตอบผิด หรือเสียเวลา | Content review/UAT |

### 6.9 M09 — Result, Recovery and Review Continuity

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-064 | Result ต้องแสดง Learning, Effort และ Engagement เป็นคนละ section | Widget/UAT |
| AMM-FR-065 | Result ต้องไม่รวมสามแกนเป็นคะแนนเดียว | Widget test |
| AMM-FR-066 | Incorrect evidence ต้อง commit ก่อน feedback/repair scheduling | Integration test |
| AMM-FR-067 | Repair ต้องเกิดหลัง 3–5 eligible intervening items และไม่เกิดทันที | Policy test |
| AMM-FR-068 | Current session มี repair ได้สูงสุดหนึ่งรอบต่อ item | Policy test |
| AMM-FR-069 | ถ้าเหลือ intervening items น้อยกว่า 3 ต้องไม่เพิ่มข้อเพื่อยืด session และส่งงานไป Review/SRS | Policy/UAT |
| AMM-FR-070 | Repair ยังผิดต้องให้ Review/SRS authority นัดครั้งถัดไป | Integration test |
| AMM-FR-071 | Support ladder ต้องเรียง Flashcard → Recognition/Matching → Cloze → Typed Recall ตาม existing active-recall policy | Unit test |
| AMM-FR-072 | Evidence failure ต้อง freeze completion/reward และ retry exact captured identity | Scenario test |
| AMM-FR-073 | Reward projection failure หลัง evidence commit ต้องเก็บ learning result และ retry projection | Scenario test |
| AMM-FR-074 | App termination ต้องใช้ existing session recovery และไม่สร้าง answer/reward ซ้ำ | Restart test |
| AMM-FR-075 | Kill switch ระหว่าง session ต้อง close/retire ผ่าน lifecycle เดิมแล้วกลับ Standard | Scenario/UAT |

### 6.10 M10 — Research and Experiment Measurement

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-076 | Assignment ต้องมาจาก `ExperimentRegistry` และคงที่ตาม experiment/version/owner | Repository/integration test |
| AMM-FR-077 | Preference, feature flag, emergency-off หรือ crossover ต้องไม่ rewrite assignment | Isolation test |
| AMM-FR-078 | Research collection และ protocol treatment ต้องเกิดเฉพาะ valid `ResearchParticipationPermit`; Product Entry เห็นเพียง active projection | Permit/consent/rules test |
| AMM-FR-079 | Prompt ต้องอยู่ natural breakpoint มี Skip และไม่ขวาง learning completion | Widget/UAT |
| AMM-FR-080 | `MotivationMeasurementRun` ต้อง pin protocol, treatment, assignment, consent, instrument, form, app/build และ policy/content versions | Repository test |
| AMM-FR-081 | `MotivationResponse` ต้องใช้ bounded catalog response code ไม่มี free text | Domain/rules test |
| AMM-FR-082 | ระบบต้องลงทะเบียน neutral Today Experience events v1: `TodayExperiencePresented`, `TodayExperiencePresentationChanged`, `TodayExperienceMissionStarted`, `TodayExperienceMissionCompleted` สำหรับทั้ง Standard/Adventure | Event policy test |
| AMM-FR-083 | Neutral research event ต้องใช้ `EventEnvelopeV2` เดิมและไม่เพิ่ม envelope field | Contract test |
| AMM-FR-084 | Non-participant ต้องไม่มี `MeasurementOpportunity` หรือ research event จากการใช้ Standard/Adventure ปกติ | Negative test |
| AMM-FR-085 | Consent withdrawal ต้องหยุด create/enqueue/upload research record ใหม่ทันที | Integration/rules test |
| AMM-FR-086 | Export ต้องแยก Outcome, Learning, Effort, Engagement และ Motivation | Export test |
| AMM-FR-087 | Primary analysis ต้องรองรับ intention-to-treat; crossover/adherence เป็น secondary metadata | Data validation |
| AMM-FR-088 | Minor protocol ต้องมี runtime-validated signed permit ที่อ้าง guardian permission และ learner assent ทั้งคู่ก่อน treatment/collection | Permit/rules/UAT |

### 6.11 M11 — Operations, Quality and Reliability

| ID | Requirement | Verification |
|---|---|---|
| AMM-FR-089 | ระบบต้อง expose bounded diagnostics สำหรับ entry/fallback, composition failure, evidence retry, projection retry และ asset failure | Unit/integration test |
| AMM-FR-090 | Diagnostics ต้องไม่รวม answer payload, research response, raw story copy หรือ direct identifier ที่ไม่จำเป็น | Privacy test |
| AMM-FR-091 | Offline entry ต้องเกิดเฉพาะเมื่อ required world/content revisions verify แล้ว | Offline scenario test |
| AMM-FR-092 | Asset removal ต้องไม่ลบ learning evidence หรือ canonical progress | Integration test |
| AMM-FR-093 | Corrupt bundle ต้อง quarantine และมี verify/repair/remove path | Offline test/UAT |
| AMM-FR-094 | Feature promotion ต้องเป็น Hidden → Internal → Limited → Controlled Expansion → Enabled โดย MS-08A ไปได้สูงสุด Limited และ MS-08B จึงปล่อย class ต่อได้ | Release checklist |
| AMM-FR-095 | Emergency-off rehearsal ต้องผ่านก่อน MS-08A และก่อน class-specific Controlled Expansion/Enabled | Operational test |
| AMM-FR-096 | Unknown enum/event/schema payload ต้อง fail closed และไม่ overwrite compatible record | Compatibility test |
| AMM-FR-097 | ระบบต้อง validate `ResearchParticipationPermit` และ expose `ActivePresentationPermit` แบบ minimal projection โดยไม่ส่ง raw receipt fields เข้า Product Entry | Permit/architecture test |
| AMM-FR-098 | Permit missing/invalid/expired/revoked หรือ withdrawal ต้องหยุด treatment start ใหม่และ fallback `session choice → preference → Standard` โดยการเรียนทั่วไปยังใช้ได้ | Scenario/race test |
| AMM-FR-099 | Standard และ Adventure ต้อง emit neutral event policy v1 ชุดเดียวกันพร้อม `assignedTreatment` และ `effectivePresentation` | Event-policy/equivalence test |
| AMM-FR-100 | Participant Host opening ต้องมี `MeasurementOpportunity` เป็น denominator อิสระ; nonparticipant ต้องไม่มี research row | Repository/privacy test |
| AMM-FR-101 | `entryAttemptId` ต้องเป็น UUID v4 หนึ่งค่าต่อ authorized Host opening และ reuse ระหว่าง rebuild/retry/switch | Identity/widget test |
| AMM-FR-102 | `TodayExperienceHost` ต้อง load Today snapshot หนึ่งครั้งและส่ง object เดียวให้ `TodayHubView(snapshot)` หรือ `AdventureHubScreen(snapshot)` | Loader/identity test |
| AMM-FR-103 | Minor enrollment ต้องใช้ guardian-led signed permit, age-band code, guardian receipt ref และ learner assent ref โดยไม่เก็บ DOB/guardian PII ในแอป | Domain/privacy/UAT |
| AMM-FR-104 | Rollout ต้องตัดสินแยก `adult`/`minor`; class ที่ไม่ผ่าน sample, guardrail หรือ comprehension ต้องคง Limited | Release-decision test |

## 7. Preference and Database Requirements

| ID | Requirement | Verification |
|---|---|---|
| AMM-DATA-001 | Phase 1 ต้องไม่เปลี่ยน schema v22 | Schema diff |
| AMM-DATA-002 | Migration preference v2 ซึ่งวางแผนเป็น v23 ต้องเพิ่ม `home_experience TEXT NOT NULL DEFAULT 'standard'` ใน `learner_preferences`; หากเลขถูกจองแล้วต้องใช้เลขถัดไป | Migration/ledger test |
| AMM-DATA-003 | Preference domain v2 ต้องรองรับเฉพาะ `standard` และ `adventure` | Domain test |
| AMM-DATA-004 | v22→v23 ต้องรักษา goal, available minutes, activity, theme, motion, timestamps และ revisions เดิมทุกค่า | Fixture comparison |
| AMM-DATA-005 | Unknown home experience ต้องไม่เปิด Adventure และต้องแสดง Standard | Negative sync test |
| AMM-DATA-006 | Preference mutation ต้องผ่าน `LearnerPreferencesUseCases` และ owner operation gate | Architecture/integration test |
| AMM-DATA-007 | Migration research measurement ซึ่งวางแผนเป็น v24 ต้องเพิ่ม `motivation_measurement_runs`, `motivation_responses`, `research_participation_permits` และ `measurement_opportunities`; หากเลขถูกจองแล้วต้องใช้เลขถัดไป | Schema/ledger test |
| AMM-DATA-008 | Measurement run ID และ response identity ต้อง idempotent และ owner-scoped | Repository test |
| AMM-DATA-009 | ทุก research row ต้องอยู่ใน owner lifecycle manifest หนึ่งครั้งพอดี | Manifest test |
| AMM-DATA-010 | Guest upgrade ต้องย้าย preference/research rows และรักษา assignment/consent identity ตาม policy | Scenario test |
| AMM-DATA-011 | Sync payload ต้อง versioned, bounded และ reject incompatible replay | Sync test |
| AMM-DATA-012 | Export/delete/withdrawal/retention ต้องครอบคลุม v23/v24 records | Lifecycle test |
| AMM-DATA-013 | หาก schema v23/v24 ถูกใช้ก่อน implementation ต้อง rebase เลขขึ้นตาม schema ledger และห้ามใช้เลขซ้ำ | Ledger review/test |
| AMM-DATA-014 | `research_participation_permits` ต้องอยู่ใน owner lifecycle, sync, Firestore rules, export, withdrawal, deletion และ retention manifest พร้อม signature/revision conflict handling | Lifecycle/rules test |
| AMM-DATA-015 | `measurement_opportunities` ต้องอยู่ใน lifecycle เดียวกันและ update switch ordinal 1–10 แบบ transaction; ส่วนเกินเพิ่มเฉพาะ suppressed counter | Repository/concurrency/lifecycle test |

## 8. External Interface Requirements

### 8.1 User interface

| ID | Requirement |
|---|---|
| AMM-UI-001 | ใช้ Material 3 และ `M3Theme`; ห้าม hard-code theme ที่ทำลาย light/dark/high contrast |
| AMM-UI-002 | Thai copy ใช้ศัพท์จาก navigation glossary; English key ต้องมีครบ |
| AMM-UI-003 | Primary CTA ต้องมี loading/disabled semantics และป้องกัน repeated activation |
| AMM-UI-004 | Locked/current/completed/error ต้องแยกด้วย icon/shape/text นอกเหนือจากสี |
| AMM-UI-005 | ทุก interactive element ต้องมี semantic label, role, state และ action ที่ไม่ซ้ำ |
| AMM-UI-006 | Focus order ต้องเริ่ม AppBar → mission → journey → secondary actions → Standard switch ตาม visual intent |
| AMM-UI-007 | Keyboard traversal ต้องไม่มี trap บน platform ที่รองรับ |
| AMM-UI-008 | Text scaling 200% ต้องไม่ clip CTA, mission reason หรือ fallback action |
| AMM-UI-009 | Touch target ต้องไม่น้อยกว่า 48×48 logical pixels |
| AMM-UI-010 | Reduced motion ต้องเปลี่ยน transition duration เป็น zero ผ่าน `M3Theme.motionDuration` |
| AMM-UI-011 | Audio/story sound ต้องมี caption/transcript และ no-audio alternative |
| AMM-UI-012 | Technical failure copy ต้องบอก action ที่ทำได้และไม่กล่าวโทษผู้ใช้ |
| AMM-UI-013 | Result ต้องใช้ข้อความที่แยก “เรียนรู้อะไร”, “ลงแรงเท่าไร”, “ทำอะไรในแอป” |
| AMM-UI-014 | Research prompt ต้องอธิบายวัตถุประสงค์แบบสั้น มี Skip และ link ไป consent details |
| AMM-UI-015 | Guardian permission flow ต้องอธิบาย purpose, data, Skip/withdraw/no-learning-impact และสถานะการออก permitอย่างชัดเจน |
| AMM-UI-016 | Learner assent ต้องใช้ภาษาตาม age band มี Agree/Not now เท่าเทียมกันและ restore focus หลังจบ flow |
| AMM-UI-017 | Invalid/expired/revoked permit ต้องอธิบายว่า research mode หยุดแต่ผู้เรียนยังเรียนต่อแบบ product ได้ พร้อม action กลับ Learn/Standard |

### 8.2 Existing application interfaces

| Interface | Adventure usage |
|---|---|
| `TodayHubSnapshotLoader.load()` | อ่าน canonical work หนึ่ง snapshot |
| `TodayHubActionDelegate` | รักษา semantics ของ resume/review/history/assessment |
| `FeatureRegistry` | ตรวจ visibility/invocation เท่านั้น |
| `ExperimentRegistry.getAssignment()` | Enrollment authority ใช้อ่าน stable assignment; Product Entry ไม่อ่านโดยตรงเมื่อ protocol treatment มาจาก permit |
| `ResearchParticipationPermitValidator` | ตรวจ owner/assignment/consent/guardian/assent/protocol/expiry/revocation/signature/revision และสร้าง active projection |
| `ActivePresentationPermitReader` | ส่ง minimal projection ให้ Product Entry โดยไม่ expose receipt fields |
| `ConsentRegistry.snapshot()` | ใช้เฉพาะ enrollment/capture/withdrawal authority; ไม่ส่งตรงเข้า Product Entry |
| `LearnerPreferencesUseCases` | อ่าน/เปลี่ยน home presentation ตั้งแต่ v23 |
| `UnifiedLessonController` | start, submit, complete, pause, resume, abandon |
| `LearningSideEffectReconciler` + Quest/Streak/Reward readers | commit side effects ผ่าน authority เดิม แล้วให้ Adventure อ่านผล |
| `OfflineContentManager` | catalog/download/verify/repair/remove assets |
| Sync/Export/Owner Lifecycle | จัดการ persisted owner-scoped data |

### 8.3 Cloud and sync

- No new unauthenticated endpoint
- Firestore rules ต้อง allow เฉพาะ owner ที่ตรงกันและ payload version ที่ allowlist
- Research upload ต้องตรวจ consent context และ measurement run state
- Outbox replay ต้องใช้ idempotency key เดิม
- Unknown cloud fields ไม่อนุญาตให้เปิด feature หรือเปลี่ยน assignment

## 9. Non-Functional Requirements

### 9.1 Reliability and consistency

| ID | Requirement |
|---|---|
| AMM-NFR-001 | Feature-off path ต้อง behaviorally equivalent กับ baseline สำหรับ test fixtures เดียวกัน |
| AMM-NFR-002 | Journey projection ต้อง deterministic และ rebuildable 100% |
| AMM-NFR-003 | Duplicate reward จาก retry/restart ที่รู้จักต้องเป็นศูนย์ |
| AMM-NFR-004 | Accepted evidence ต้องไม่สูญหายเมื่อ reward/story projection ล้มเหลว |
| AMM-NFR-005 | Mixed-owner mutation ต้องถูก reject ก่อน write |
| AMM-NFR-006 | Missing dependency ต้อง fallback ไม่ crash |
| AMM-NFR-007 | App restart ต้อง recover accepted session ตาม lifecycle เดิม |
| AMM-NFR-032 | Full logical/shared baseline suite ต้องไม่มี unclassified failure; 15 findings ใน `AMM-AUDIT-001` ต้องมี fresh closure หรือ explicit excluded-platform/capability disposition ตาม Android Pilot matrix ก่อน Pilot |
| AMM-NFR-033 | Adventure implementation ต้องไม่ทำให้ Gitleaks, OSV, platform contract หรือ model-certification gate แย่ลง และ release ต้องผ่าน policy ที่อนุมัติ |

### 9.2 Performance budgets

Budgets วัดบน device certification profile ที่โครงการกำหนดและใช้ release/profile build:

| ID | Budget |
|---|---|
| AMM-NFR-008 | Entry decision local p95 ≤ 50 ms หลัง dependencies พร้อม |
| AMM-NFR-009 | Journey projection 3-node p95 ≤ 100 ms บน warm local DB |
| AMM-NFR-010 | First meaningful Adventure shell render p95 ≤ 1.5 s จาก tap เมื่อ assets local |
| AMM-NFR-011 | Map/list switch p95 frame work ≤ 16.7 ms ต่อ frame และไม่มี long task > 100 ms |
| AMM-NFR-012 | Session start overhead ที่ Adventure เพิ่ม p95 ≤ 150 ms เหนือ Standard |
| AMM-NFR-013 | Event/measurement local commit p95 ≤ 100 ms และไม่ block lesson animation |
| AMM-NFR-014 | World v1 packaged visual assets รวม ≤ 5 MB; audio แยกเป็น downloadable bundle |

### 9.3 Accessibility

| ID | Requirement |
|---|---|
| AMM-NFR-015 | Map/list action parity ต้อง 100% |
| AMM-NFR-016 | Screen-reader action/state labels ต้องผ่าน automated semantics และ manual traversal |
| AMM-NFR-017 | Text 200%, dark theme, high contrast และ reduced motion ต้องผ่าน required screens |
| AMM-NFR-018 | Color contrast ต้องเป็นไปตาม WCAG 2.2 AA สำหรับ text/control states |
| AMM-NFR-019 | ไม่มี timeout บังคับสำหรับ ordinary Adventure learning |

### 9.4 Privacy and safety

| ID | Requirement |
|---|---|
| AMM-NFR-020 | Data minimization: non-participant ไม่มี `MeasurementOpportunity` หรือ persisted research event |
| AMM-NFR-021 | Research response ไม่มี free text และไม่มี duplicated answer content |
| AMM-NFR-022 | Withdrawal gate ต้องมีผลก่อน enqueue operation ถัดไป |
| AMM-NFR-023 | Export/delete ต้องตรวจ owner isolation และ complete manifest |
| AMM-NFR-024 | Diagnostic logs ต้อง redact owner/research payload ตาม policy |
| AMM-NFR-025 | Story/reward copy ต้องไม่ใช้ shame, coercion หรือ false mastery claim |

### 9.5 Maintainability and compatibility

| ID | Requirement |
|---|---|
| AMM-NFR-026 | Adventure presentation package ห้าม import Drift-generated row classes |
| AMM-NFR-027 | ทุก persisted enum ใช้ explicit codec และ fail-closed unknown handling |
| AMM-NFR-028 | Catalog/event/preference/research payload มี independent version |
| AMM-NFR-029 | Generated Drift code ต้องสร้างด้วย repository toolchain ไม่แก้ด้วยมือ |
| AMM-NFR-030 | New modules ต้องมี unit tests และ public interfaces มี doc comments |
| AMM-NFR-031 | การปิด feature ไม่ต้อง rollback database migration |
| AMM-NFR-034 | หนึ่ง authorized Host opening ต้องเรียก `TodayHubSnapshotLoader.load()` หนึ่งครั้ง; rebuild/switch/focus restoration ห้าม reload |
| AMM-NFR-035 | Offline permit verification ต้อง fail closed เมื่อ signature, expiry, revocation-known revision หรือ protocol ไม่ผ่าน โดย product learning ยังใช้ได้ |
| AMM-NFR-036 | Class ที่ missing post >15% หรือ arm difference >5 percentage points ต้องถูกบล็อกที่ MS-08B |
| AMM-NFR-037 | Release flag/eligibility ต้อง isolate adult/minor class เพื่อไม่ให้ class ที่ไม่ผ่านได้รับ Controlled Expansion/Enabled |

## 10. Core Use Cases

### UC-01 — Open Adventure normally

**Primary actor:** Learner

**Preconditions:** owner resolved; feature visible/enabled; dependencies ready; world/content local or verified

**Main flow:**

1. Learner opens existing Learn surface.
2. Eligible additive card `home/learn/today-experience` appears without changing bottom navigation; learner opens it.
3. Today Experience Host composes canonical Today snapshot once.
4. Product Entry Control reads feature/dependency state, session choice/preference and optional `ActivePresentationPermit`; it never reads raw consent/guardian/assent receipts.
5. Journey Projection builds snapshot.
6. Host renders resolved Standard or Adventure presentation.
7. Adventure shell shows current mission, progress nodes and Standard switch when selected.

**Alternate flows:**

- Feature hidden → card absent; Learn surface remains baseline-equivalent
- Hidden/disabled/unknown or stale direct route → Learn without constructing Host/snapshot
- Today dependency unavailable/corrupt → return Learn with bounded fallback reason
- Assets absent online → offer download; Standard remains available
- Assets absent offline → Standard immediately
- Preference Standard → Standard even if Adventure enabled

**Postcondition:** No progress/reward/evidence write occurs from opening

### UC-02 — Start and complete mission

**Preconditions:** UC-01 ready; canonical work available

1. Learner reviews mission reason and duration.
2. Learner accepts or changes duration.
3. Composer pins plan identities/versions.
4. Bridge launches Unified Lesson Shell.
5. Existing controller records responses/evidence.
6. Lesson closes through existing lifecycle.
7. Existing `LearningSideEffectReconciler` processes eligible committed evidence idempotently; Adventure reads its committed/pending projection.
8. Result shows separate axes.
9. Journey recomposes from canonical readers.

**Postcondition:** canonical learning evidence and receipts are durable; no Adventure progress row

### UC-03 — Answer incorrectly and recover

1. Existing gateway commits incorrect evidence.
2. Existing feedback policy shows contrastive feedback and optional hint.
3. Repair scheduler counts eligible intervening items.
4. At 3–5 items, item returns once using support ladder.
5. If not enough items remain, no padding occurs.
6. Remaining need is sent to Review/SRS.

**Postcondition:** no progress/reward/streak penalty; review authority owns next due state

### UC-04 — Resume after app termination

1. App resolves accepted resumable learning session.
2. Journey marks resume as highest-priority current node.
3. Learner resumes through existing controller.
4. Exact pending evidence identity is retried if needed.
5. Duplicate answer/reward is rejected by idempotency.

### UC-05 — Switch to Standard during protocol

1. Learner activates visible Standard switch.
2. Active research recorder transactionally updates the opportunity and writes `TodayExperiencePresentationChanged` only when active permit/run remain valid, using `entryAttemptId` and bounded switch ordinal.
3. Preference updates only when user explicitly chooses “จำตัวเลือกนี้” outside protocol policy.
4. Assignment remains unchanged.
5. Pure `TodayHubView(snapshot)` renders from the same once-loaded snapshot inside the authorized Host.

### UC-06 — Withdraw research consent

1. Learner opens consent management.
2. Existing consent authority records withdrawal.
3. Recorder rejects future research rows before enqueue.
4. Pending upload is cancelled/blocked according to withdrawal policy.
5. Product learning remains usable; protocol treatment falls back through session choice/preference/Standard.
6. Export/delete options remain available as policy permits.

### UC-07 — Corrupt or missing world asset

1. Offline manager verifies manifest/checksum.
2. Mismatch marks bundle quarantined.
3. Adventure entry resolves typed unavailable reason.
4. Standard Today Hub opens.
5. User can repair/remove bundle without deleting learning data.

### UC-08 — Emergency-off during session

1. Runtime registry receives emergency-off.
2. New Adventure operation/start is blocked.
3. Accepted Unified Lesson session is safely completed/retired using existing lifecycle.
4. Evidence already accepted remains valid.
5. App returns Standard; no new Adventure projection/research operation occurs after cutoff.

## 11. State Models

### 11.1 Entry state

```text
hidden/disabled/unknown/stale route ──► Learn baseline/reason (no Host)
emergencyOff before Host/start ───────► Learn or authorized-host Standard
visible + dependency missing/corrupt ─► Learn(reason)
visible + preference standard ────────► Standard
visible + preference adventure
       + dependencies ready ──────────► Adventure Ready
Adventure Ready + accepted session ──► Adventure Active
Adventure Active + emergency-off ────► Safe Close ─► Standard
```

### 11.2 Journey node state

```text
hidden → locked → available → current → completed
                    └──────────────► unavailable (dependency failure)
completed is derived and can be recomputed; it is not directly mutated.
```

### 11.3 Measurement run state

```text
eligible → started → completed
    │          ├──► skipped
    │          ├──► abandoned
    └──────────┴──► withdrawn

withdrawn is terminal for new research collection under that consent receipt.
```

## 12. Business Rules

| ID | Rule |
|---|---|
| AMM-BR-001 | Learning authority wins over narrative state in every conflict |
| AMM-BR-002 | Resume accepted session before offering new mission |
| AMM-BR-003 | Review/due before new work unless existing policy explicitly overrides |
| AMM-BR-004 | Reward only after committed eligible evidence |
| AMM-BR-005 | Opening/viewing/switching presentation earns no learning reward |
| AMM-BR-006 | Assessment never updates motivational ledgers |
| AMM-BR-007 | Hint-assisted answer is guided practice, not independent recall |
| AMM-BR-008 | One source evidence ID can cause each reward/unlock at most once |
| AMM-BR-009 | Incorrect/skip/timeout/technical failure are different states |
| AMM-BR-010 | Technical failure never penalizes learner |
| AMM-BR-011 | XP and Coins retain separate existing ledger semantics |
| AMM-BR-012 | Preference never grants feature availability |
| AMM-BR-013 | Feature availability never assigns cohort |
| AMM-BR-014 | Consent never implies treatment assignment |
| AMM-BR-015 | Crossover never rewrites assignment |
| AMM-BR-016 | Result axes are never collapsed into one score |
| AMM-BR-017 | World v1 cannot branch into durable choices |
| AMM-BR-018 | Standard fallback cannot be removed by a world catalog |
| AMM-BR-019 | Active presentation permit มี precedence เหนือ session choice/preference เฉพาะ protocol treatment และ Product Entry ห้ามอ่าน raw receipts |
| AMM-BR-020 | เมื่อไม่มี active permit ให้ใช้ session choice → preference → Standard และสร้าง research row เป็นศูนย์ |
| AMM-BR-021 | Minor permit ต้องมี guardian permission + learner assent runtime evidence; governance checklist อย่างเดียวไม่พอ |
| AMM-BR-022 | MS-08A ตัดสิน feasibility เท่านั้นและสถานะสูงสุดคือ Limited |
| AMM-BR-023 | Controlled Expansion/Enabled ต้องผ่าน MS-08B แยก adult/minor และห้ามใช้ผลของอีก class แทนกัน |

## 13. Error Catalogue

| Code | Condition | User behavior | System behavior |
|---|---|---|---|
| AMM-E001 | Feature unavailable | Show Standard | No Adventure start |
| AMM-E002 | Dependency unavailable | Explain briefly; Standard action | Record bounded dependency code |
| AMM-E003 | Journey stale | Show last safe state with refresh label | Recompose; block unsafe start |
| AMM-E004 | Catalog invalid | Do not render bundle | Quarantine and Standard fallback |
| AMM-E005 | Content revision missing | Offer download when online | No session composition |
| AMM-E006 | Owner mismatch | Generic safe error | Reject before write; bounded diagnostic |
| AMM-E007 | Session start conflict | Offer resume/refresh | Do not create second accepted session |
| AMM-E008 | Evidence commit failed | Keep answer pending; retry | Freeze completion/reward |
| AMM-E009 | Reward projection failed | Show learning success, reward pending | Retry idempotently |
| AMM-E010 | Consent absent/withdrawn | Skip research silently or explain opt-in | No research row/outbox |
| AMM-E011 | Assignment conflict | Standard or protocol-safe fallback | Fail closed; do not reassign |
| AMM-E012 | Unknown payload version | Safe unavailable state | Reject replay; preserve existing row |
| AMM-E013 | Offline asset absent | Standard available | No network loop |
| AMM-E014 | Emergency-off | Safe close then Standard | Block new Adventure ops |

## 14. Acceptance Criteria

Adventure พร้อมเข้าสู่ MS-08A Feasibility (สถานะสูงสุด Limited) เมื่อ:

1. AMM-FR-001 ถึง AMM-FR-104 มี test or governance evidence ตาม RTM
2. AMM-DATA-001 ถึง AMM-DATA-015 ผ่าน lifecycle/migration evidence
3. AMM-UI-001 ถึง AMM-UI-017 ผ่าน widget/manual UX evidence
4. AMM-NFR-001 ถึง AMM-NFR-037 และ AMM-BR-001 ถึง AMM-BR-023 ผ่าน budget/gate ที่ระบุ
5. Required UAT cases ผ่าน 100%
6. Blocker/Critical defect เท่ากับ 0
7. Stable assignment และ required version metadata เท่ากับ 100%
8. Duplicate reward known path เท่ากับ 0
9. Standard fallback, offline, restart, corrupt bundle และ emergency-off ผ่าน
10. Product Owner, CTO, QA, UX และ Research/Privacy owner ลงนาม gate ที่เกี่ยวข้อง
11. `AMM-AUDIT-001` findings ที่จัดเป็น before-Pilot ของ Android path ปิดครบ; full inventory run มี fresh evidence, logical/shared/touched set ผ่าน และ finding ที่เหลือ map ไป explicit exclusion โดยไม่มี unclassified failure
12. Gitleaks gate สะอาดตาม reviewed policy และ dependency/platform exceptions ที่กระทบ release มี approved disposition

Controlled Expansion/Enabled ต้องผ่าน MS-08B เพิ่มเติมตาม MDS v1.1: powered sample ต่อ participant class, baseline-adjusted post-session ANCOVA, pre-registered multiple imputation/tipping-point, learning/safety thresholds, missing post ≤15%, arm difference ≤5 percentage points และ class-specific signed decision
