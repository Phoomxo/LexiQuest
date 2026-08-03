# LexiQuest V2 Evolution Framework and Architecture Gap Design

**Status:** DRAFT FOR OWNER REVIEW

**Date:** 2026-08-03

**Scope:** Current-State Reconciliation, V1-to-V2 Compatibility, Stable Kernel,
Capability Governance, LexiMotivation, Safe Delivery, and Long-Term Evolution

## 1. Purpose

เอกสารนี้รวบรวมแนวคิดสถาปัตยกรรม LexiQuest V2 ให้เป็นกรอบเดียวที่สามารถ
ส่งต่อไปออกแบบ implementation plan ได้โดยไม่ทำลายระบบปัจจุบัน โดยมีเป้าหมาย:

1. รักษาฐาน local-first, learning evidence, sync, consent, voice, AI และ field release
2. กำหนด authority และ contract ก่อนเพิ่มฟีเจอร์ V2
3. ป้องกันข้อมูลสองโลก การให้รางวัลซ้ำ mastery ขัดกัน และ legacy write ใหม่
4. ทำให้ทุก capability มี lifecycle, metric, test, migration และ rollback
5. ทำให้ V1, V2 และเวอร์ชันถัดไปสามารถวิวัฒนาการต่อเนื่องได้

เอกสารนี้เป็น proposed V2 architecture authority แต่ยังไม่แทนที่ active P8
scope จนกว่าเจ้าของโครงการจะอนุมัติและกำหนด integration sequence อย่างชัดเจน

## 2. Verified Current Baseline

ข้อมูลต่อไปนี้ตรวจจาก repository ปัจจุบัน ณ วันที่ 2026-08-03:

- Drift เป็น runtime source of truth ของข้อมูล field application
- `AppDatabase.schemaVersion` ปัจจุบันคือ `6` ไม่ใช่ `9`
- Firestore sync payload version ปัจจุบันคือ `1`
- มี owner-scoped vocabulary, imports, learning sessions, answer attempts,
  SRS states, reading evidence, points ledger, achievements, rewards, outbox,
  checkpoints, conflicts, consent, runtime flags และ model downloads
- UI หลักเข้าถึงระบบผ่าน application use cases และ `AppDependencies`
- มี legacy/prototype services หลายชุด แต่บริการ quarantine ที่ระบุยังไม่ถูก
  wire เข้ากับ production composition root
- ยังไม่มี implementation ชื่อ `EventEnvelopeV2`
- P8 Hybrid Voice and Field Release ยังเป็น active delivery scope ของงานที่เหลือ

Current evidence locations:

- `lib/data/local/app_database.dart`
- `lib/features/sync/domain/sync_entity.dart`
- `lib/runtime/app_bootstrap.dart`
- `lib/data/local/tables/`
- `docs/superpowers/specs/2026-07-31-p8-hybrid-voice-field-release-design.md`

### 2.1 Baseline Correction

ห้ามวาง migration plan โดยสมมติว่า schema ปัจจุบันคือ `9` ต้องตรวจ migration
history และฐานข้อมูล field จริงก่อนตัดสินใจว่า schema `7-9` จะถูกใช้ จอง หรือ
ข้ามอย่างมีหลักฐาน การเริ่ม V2 ที่ schema `10` เป็น target design ไม่ใช่
ข้อเท็จจริงของฐานข้อมูลปัจจุบัน

## 3. Executive Architecture Decisions

### 3.1 Recommended Evolution Strategy

ใช้ **Contract-first Strangler Architecture**:

1. freeze contract ของ authority เดิม
2. สร้าง V2 contract และ namespace ข้างระบบเดิม
3. อ่าน legacy ผ่าน compatibility adapter เท่านั้น
4. เปิด V2 แบบ shadow/internal/pilot ก่อน cutover
5. ย้าย authority ทีละ bounded context
6. deprecate และ remove legacy เมื่อผ่าน removal gate

ไม่เลือก full parallel V2 database เพราะจะสร้างข้อมูลสองโลก และไม่เลือก
big-bang rewrite เพราะเสี่ยงทำลาย offline data, sync, voice, AI และ field evidence

### 3.2 Core Authority Invariant

```text
Learning Evidence
    -> Learner Model / Mastery Projection
    -> Curriculum Decision

Learning Evidence
    -> Engagement Signal / XP Projection

Eligible Source Event
    -> Reward Grant Decision
    -> Reward Ledger Transaction

Verified Assessment Evidence
    -> Certification Decision
    -> Credential
```

แต่ละลูกศรต้องผ่าน versioned contract และไม่มี domain ใดเขียน projection ของ
domain อื่นโดยตรง

### 3.3 Dependency Direction

```text
Screen / UI
    -> Application Use Case
    -> Domain Contract
    -> Repository / Provider Port
    -> Drift, Firestore, Voice, AI, Device, or External Service
```

กฎบังคับ:

- Screen ห้ามเขียน Drift, Firestore หรือ SharedPreferences โดยตรง
- Motivation ห้ามเขียน mastery หรือ reward ledger โดยตรง
- Social ห้ามแก้ learner model
- AI ห้าม publish content, grant reward, change mastery หรือ issue certification
- Teacher Console อ่าน projection และส่ง assignment contract เท่านั้น
- Infrastructure implement contract แต่ห้ามกำหนด pedagogical policy
- การสื่อสารข้าม domain ใช้ command, query, event หรือ projection contract

## 4. Architecture Planes

### 4.1 Learning Foundation and Effectiveness

- Curriculum Intelligence
- Learner Model
- Adaptive Placement
- Spaced Repetition Intelligence
- Mistake Intelligence and Error Graph
- Weakness Clinic
- Explain My Answer

### 4.2 Dialogue, Content, and AI Intelligence

- Interactive Dialogue Drill
- Dialogue Adventure World
- AI Roleplay Coach
- Content Studio
- AI Content Generator
- Exercise Compiler
- Speech, pronunciation, target voice, and provider orchestration

### 4.3 LexiMotivation, Social, and Character

- Intrinsic, extrinsic, social, narrative, recovery, and personalized motivation
- Quest, achievement, collection, reward, streak, and notification policy
- Friend learning, class, community, and opt-in competition
- Character identity, role, affinity, relationship, and narrative continuity

### 4.4 Operations, Teacher, Research, and Ecosystem

- Teacher Console
- Research Platform
- Experiment Platform
- Creator Marketplace
- School Platform
- Certification

### 4.5 Platform, Governance, Trust, and Growth

- Offline-first storage and synchronization
- Stable Kernel
- Identity, consent, privacy, export, deletion, and audit
- Feature lifecycle and release train
- AI governance, trust and safety, observability, cost, and reliability
- Habit and retention intelligence under wellbeing guardrails

## 5. Capability Inventory: 35 Systems

ค่า Current Maturity เป็นคำอธิบายฐานปัจจุบันและไม่แทน lifecycle มาตรฐานใน
section 6

| ID | Group | Capability | V2 Coverage | Current-State Assessment | Current Maturity |
|---|---|---|---|---|---|
| CAP-01 | Learning Foundation | Curriculum Intelligence | Explicit | CEFR and vocabulary metadata exist; no curriculum graph authority | Designed |
| CAP-02 | Learner Intelligence | Learner Model | Explicit | Progress, SRS, mastery-style UI and weakness evidence exist separately | Partial Foundation |
| CAP-03 | Learner Intelligence | Adaptive Placement | Explicit | Static/prototype diagnostic exists | Prototype |
| CAP-04 | Dialogue Intelligence | Interactive Dialogue Drill | Explicit | No central dialogue domain or session authority | Designed |
| CAP-05 | Dialogue Intelligence | Dialogue Adventure World | Explicit | New system | Roadmap |
| CAP-06 | Dialogue Intelligence | AI Roleplay Coach | Explicit | Gemini/AI tutor gateway provides reusable foundation | Partial Foundation |
| CAP-07 | Learning Effectiveness | Explain My Answer | Explicit | Screen-level feedback exists; no shared explanation engine | Prototype |
| CAP-08 | Learning Effectiveness | Mistake Intelligence | Explicit as Error Graph | Word-level error evidence exists; no versioned error graph | Partial Foundation |
| CAP-09 | Learning Effectiveness | Weakness Clinic | Explicit | Working vocabulary-level experience and projections exist | Internal Foundation |
| CAP-10 | Learning Effectiveness | Spaced Repetition Intelligence | Explicit | Multiple SRS/memory implementations require authority consolidation | Production Foundation |
| CAP-11 | Content Intelligence | Content Studio | Explicit | New system | Roadmap |
| CAP-12 | Content Intelligence | AI Content Generator | Explicit | Content provider and adapters exist at prototype level | Prototype |
| CAP-13 | Content Intelligence | Exercise Compiler | Explicit | New system | Roadmap |
| CAP-14 | Motivation | Intrinsic Motivation | Implicit | Progress/mastery presentation exists; no policy domain | Captured |
| CAP-15 | Motivation | Curiosity System | Implicit | No central story-fragment or curiosity policy | Captured |
| CAP-16 | Motivation | Autonomy System | Implicit | Users choose modes; choices are not personalized | Partial Foundation |
| CAP-17 | Motivation | Achievement System | Explicit | Evidence-backed projection and UI exist | Production Foundation |
| CAP-18 | Motivation | Quest System | Explicit | Multiple prototypes exist; no production authority | Prototype |
| CAP-19 | Motivation | Recovery Motivation | Explicit | No recovery state machine or policy history | Designed |
| CAP-20 | Social Learning | Friend Learning | Explicit | New system | Roadmap |
| CAP-21 | Social Learning | Class and Community | Explicit | New system | Roadmap |
| CAP-22 | Character Universe | Lexi Character System | Explicit | Avatar/equipment foundation only | Partial Foundation |
| CAP-23 | Character Universe | Character Relationship | Explicit | New system | Roadmap |
| CAP-24 | Teacher and Research | Teacher Console | Explicit | New system | Roadmap |
| CAP-25 | Teacher and Research | Research Platform | Explicit | Consent, export and analytics foundations exist; experiment service is prototype | Partial Foundation |
| CAP-26 | Business and Ecosystem | Creator Marketplace | Explicit | New system | Roadmap |
| CAP-27 | Business and Ecosystem | School Platform | Explicit | New system | Roadmap |
| CAP-28 | Business and Ecosystem | Certification | Explicit | New system | Roadmap |
| CAP-29 | AI Safety and Trust | AI Governance | Explicit | Gateway, consent and usage controls provide foundation | Partial Foundation |
| CAP-30 | AI Safety and Trust | Privacy System | Explicit | Consent, export, deletion and voice privacy provide strong foundation | Production Foundation |
| CAP-31 | Growth Intelligence | Habit Engine | Implicit | Streak state exists in multiple legacy sources; no authority | Prototype |
| CAP-32 | Growth Intelligence | Retention Intelligence | Implicit | No central decision system | Captured |
| CAP-33 | Platform | Offline-first | Explicit | Drift, outbox, idempotency and sync are strong foundations | Production Foundation |
| CAP-34 | Platform | Experiment Platform | Explicit | Static feature registry and experiment prototype exist separately | Prototype |
| CAP-35 | Platform | Analytics Platform | Explicit | Events, progress, voice telemetry and exports are not unified | Partial Foundation |

Summary:

- 30 capabilities are explicit in V2
- 5 capabilities remain implicit: Intrinsic, Curiosity, Autonomy, Habit, Retention
- no capability is production-complete merely because a class or screen exists
- every capability still requires end-to-end traceability before production

## 6. Capability Lifecycle

```text
Captured
-> Classified
-> Designed
-> Contracted
-> Implementing
-> Shadow
-> Internal
-> Pilot
-> Production
-> Deprecated
-> Removed
```

- **Captured:** มีแนวคิดและเหตุผล แต่ยังไม่เลือก architecture
- **Classified:** มี owner system, plane, risk และ dependency
- **Designed:** ผ่าน design review แต่ contract ยังไม่ frozen
- **Contracted:** command, event, query, schema และ invariants ถูก version แล้ว
- **Implementing:** กำลังเขียน storage, adapter, use case หรือ UI
- **Shadow:** ทำงานข้าง authority เดิมแต่ยังไม่ควบคุมผลผู้ใช้
- **Internal:** เปิดสำหรับทีมและ test accounts
- **Pilot:** เปิดให้ cohort จำกัดพร้อม observability และ rollback
- **Production:** ผ่าน acceptance gate และมี operational owner
- **Deprecated:** ห้าม consumer ใหม่และมี removal deadline
- **Removed:** ไม่มี runtime path และ migration/retention ปิดครบ

## 7. Duolingo-Inspired Transformation Registry

| Source Mechanism | LexiQuest Transformation | Decision |
|---|---|---|
| Learning Path | Curriculum Graph and Adaptive Route | Adopted |
| Short Lesson | Micro Dialogue Session | Transformed |
| Personalized Practice | Learner Model, SRS and Error Graph | Extended |
| Mistake Review | Weakness Clinic and Dialogue Repair | Extended |
| Stories | Dialogue Adventure World | Adopted |
| Daily Quest | Learning-aware Adaptive Quest | Transformed |
| Badge/Achievement | Evidence-backed Achievement | Adopted |
| Punitive Streak | Flexible Momentum | Transformed |
| Streak Freeze | Grace, Recovery and Streak Repair | Transformed |
| Friend Quest | Co-op Dialogue Quest | Extended |
| Forced Public League | Opt-in Mastery-weighted League | Transformed |
| Gems/Coins | Idempotent Reward Ledger | Adopted with economy redesign |
| Quantity XP | Evidence-weighted engagement signal | Constrained by section 8 |
| Punitive Hearts | Non-blocking Support and Hint Budget | Transformed |
| Character Mascot | Teacher, Friend, Guide and Challenger roles | Extended |
| Aggressive Notifications | Policy-controlled Supportive Reminder | Transformed |
| Chests/Unlocks | Collection and Story Fragment | Adopted |
| Legendary Level | Transfer Challenge and Certification Evidence | Extended |
| Subscription | Phase-limited entitlement and ecosystem access | Adopted with integrity rules |
| Pay-to-win Progress | Direct mastery or certification purchase | Rejected |
| Guilt Notifications | Negative reinforcement and shame messaging | Rejected |
| Engagement-at-all-costs | Optimization without wellbeing guardrails | Rejected |

Rejected and transformed mechanisms remain in the registry permanently with
rationale, known harm, approved replacement, owner, reconsideration gate และ
evidence required before any future policy change.

## 8. Semantic Authority and Economy Invariants

### 8.1 Learning Evidence

ข้อเท็จจริงที่เกิดขึ้นแล้ว เช่น answer attempt, reading checkpoint, speech
assessment, dialogue outcome หรือ verified assessment result

- append-only หรือ immutable revision
- มี source, actor, timestamp และ provenance
- ไม่เท่ากับ mastery
- ห้ามแก้เพื่อทำให้ผู้ใช้ดูเก่งขึ้น

### 8.2 Mastery

ค่าประมาณความสามารถจาก evidence ภายใต้ learner-model policy version

- เป็น projection ที่ rebuild ได้
- ไม่ใช้ซื้อของ
- ไม่เพิ่มจาก streak, purchase, notification click หรือเวลาที่เปิดแอป
- ใช้ curriculum gate ได้เมื่อมี confidence และ evidence threshold

### 8.3 XP

สัญญาณ engagement/effort ที่ไม่ใช้เป็นหลักฐานรับรองความสามารถ

- non-spendable
- ไม่ปลดล็อก curriculum gate โดยตรง
- ต้องระบุ source event และ scoring policy version
- สามารถเลิกใช้ได้หากสร้างความสับสนกับ mastery

### 8.4 Points

คำว่า `Points` เป็นคำ legacy ที่มีความหมายไม่ชัดเจน ใน V2 ห้ามสร้าง contract
ใหม่ด้วยคำนี้โดยไม่ระบุชนิด การ migration ต้อง map อย่างชัดเจนว่า legacy points
หมายถึง engagement XP หรือ spendable currency ห้ามเดาจากจำนวนหรือชื่อ field

### 8.5 Coins or Reward Credits

หน่วยเศรษฐกิจที่ใช้ซื้อ cosmetic, collection หรือ convenience ที่ไม่กระทบ
learning integrity

- spendable ผ่าน ledger authority เดียว
- ทุก grant และ spend มี idempotency key
- ทุก grant อ้างอิง eligible source event หรือ administrative adjustment
- ห้ามซื้อ mastery, prerequisite bypass หรือ certification

### 8.6 Badge and Achievement

รางวัลเชิงสัญลักษณ์จาก evidence-backed rule

- versioned definition
- immutable unlock evidence
- ไม่เท่ากับ certification
- การเปลี่ยนนิยามไม่แก้ achievement เก่าย้อนหลังโดยไม่มี migration policy

### 8.7 Certification

หลักฐานรับรองความสามารถจาก assessment protocol ที่กำหนดไว้

- อ้างอิง verified assessment evidence
- มี rubric, policy และ content revision
- auditable และอาจ revoke ได้ตาม formal policy
- ไม่ซื้อ ไม่ grant จาก motivation และไม่อนุมานจาก XP

## 9. LexiMotivation Domain Specification

### 9.1 Motivation Dimensions

1. **Intrinsic:** mastery visibility, curiosity and autonomy
2. **Extrinsic:** quest, badge, reward and collection
3. **Social:** friend, team, recognition and accountability
4. **Narrative:** character, world, mission and story continuity
5. **Recovery:** gentle return, reduced session and streak repair
6. **Personalization:** profile, tolerance, fatigue and intervention selection

### 9.2 Required Contracts

- `MotivationProfile`
- `MotivationState`
- `InterventionCatalog`
- `MotivationPolicyDecision`
- `QuestDefinition`
- `QuestInstance`
- `StreakPolicy`
- `RecoveryStateMachine`
- `RewardGrantRequest`
- `RewardLedgerTransaction`
- `NotificationBudget`
- `CompetitionTolerance`
- `MotivationConsent`
- `InterventionExplanation`

### 9.3 Motivation Decision Record

ทุกการเลือก intervention ต้องบันทึก:

- decision ID
- owner/learner reference
- policy version
- input projection references
- selected intervention
- reason codes
- cooldown/fatigue state
- consent and opt-out state
- experiment context
- expected learning/wellbeing outcome
- timestamp and timezone policy

### 9.4 Prohibited Actions

LexiMotivation ห้าม:

- แก้ mastery หรือ learning evidence
- เพิ่ม coin หรือ reward ledger transaction เอง
- สร้าง quest completion เอง
- ตีความหรือวินิจฉัยสภาวะทางจิตใจ
- ส่ง notification โดยไม่ผ่าน notification policy
- เปลี่ยน teacher goal
- ปลดล็อกเนื้อหาที่ขัด curriculum gate
- บังคับ competition หรือ social participation
- ปรับเพื่อ engagement โดยไม่คำนึง wellbeing guardrail

## 10. Current-State Risk Register

### 10.1 Multiple Progress and Streak Sources

พบ Drift progress projection, SharedPreferences progress, local progress store,
streak/quest prototype และ legacy Firestore state

Decision:

- Drift learning evidence และ versioned projections เป็น future authority
- legacy sources เป็น read-only compatibility input
- V2 ห้ามเพิ่ม SharedPreferences progress write ใหม่
- migration ต้องมี reconciliation report ก่อน cutover

### 10.2 Duplicate Quest Implementations

Quest prototypes ยังไม่มี claim transaction, policy version, eligible source
event และ idempotency contract ที่ครบถ้วน

Decision:

- ห้ามเชื่อม prototype quest กับ production reward ledger
- quest completion ต้องเป็น immutable event
- reward eligibility และ reward grant เป็นคนละ decision
- claim/grant/ledger write ต้อง atomic หรือพิสูจน์ replay safety

### 10.3 Multiple Reward Balances

พบ points ledger, reward transaction, legacy Firestore total points,
prototype XP/coin และ catalog purchase

Decision:

- มี spendable ledger authority เพียงหนึ่งชุด
- legacy balances ต้องผ่าน explicit migration mapping
- projection balance ต้อง rebuild จาก ledger ได้
- administrative adjustment ต้องมี reason, actor และ audit event

### 10.4 Distributed Learning Evidence

พบ learning event V1, answer attempts, reading events, associative events,
speech evidence, AI usage, voice telemetry และ research events

Decision:

- ไม่รวมทุกอย่างเป็นตารางเดียวทันที
- ใช้ `EventEnvelopeV2` เป็น metadata contract กลาง
- payload schema ยังคงแยกตาม bounded context
- legacy adapters แปลงเฉพาะเมื่อถูก consume

### 10.5 Multiple Identity Names

พบ owner ID, pseudonymous ID, participant ID, Firebase UID และ learner ID

Decision:

- สร้าง Identity Mapping Contract
- ห้าม rename primary identity เดิมโดยตรง
- research pseudonym แยกจาก authentication identifier
- tenant membership และ role แยกจาก identity

### 10.6 Feature and Experiment Confusion

Feature visibility ไม่เท่ากับ experiment assignment

- Feature Registry เปิด/ปิด capability
- Experiment Registry กำหนด cohort/variant
- Consent Registry อนุญาต data use
- Entitlement Registry กำหนดสิทธิ์ผลิตภัณฑ์
- Teacher Assignment กำหนดกิจกรรมจากครู

## 11. LexiQuest Stable Kernel

ทุก plane ใช้ Stable Kernel ร่วมกันและห้ามสร้างรูปแบบทดแทนเอง

```text
LexiQuest Stable Kernel
|- Identity and Tenant IDs
|- Clock, Learning Day and Timezone Policy
|- ID and Idempotency Generation
|- Event Envelope and Contract Versioning
|- Content and Revision IDs
|- Consent Context
|- Experiment Context
|- Reward Grant Contract
|- Feature Lifecycle
|- Policy Decision Record
|- Error and Result Contracts
`- Data Classification and Provenance
```

### 11.1 EventEnvelopeV2 Minimum Contract

```text
eventId
eventType
eventVersion
occurredAtUtc
recordedAtUtc
actorIdentity
ownerIdentity
tenantContext
aggregateType
aggregateId
correlationId
causationId
idempotencyKey
consentContext
experimentContext
contentRevision
policyVersion
appVersion
buildId
providerProvenance
privacyClassification
payload
```

Requirements:

- event ID และ idempotency key มี canonical format
- timestamp เป็น UTC และ decision ที่อิงวันต้องมี timezone policy reference
- payload version แยกจาก envelope version
- sensitive fields ห้ามอยู่ใน envelope metadata
- serialization ที่ publish แล้ว immutable
- unknown optional fields ต้องไม่ทำให้ consumer รุ่นก่อนพัง

### 11.2 Identity Mapping Contract

ต้องรองรับ:

- local owner ID
- Firebase UID
- learner ID
- research participant pseudonym
- teacher/school membership
- creator identity
- account merge, guest upgrade, deletion and unlink

ห้ามใช้ Firebase UID เป็น universal domain ID และห้ามนำ participant pseudonym
กลับไปเชื่อมกับ authentication context โดยไม่มีสิทธิ์และ purpose ที่กำหนด

## 12. Additional Evolution Systems

### 12.1 Domain Language Registry

เก็บศัพท์กลาง นิยาม owner และคำ legacy เพื่อป้องกันคำเดียวกันมีหลายความหมาย
โดยเฉพาะ mastery, score, points, level, session, quest และ completion

### 12.2 Architecture Decision and Exception Registry

ทุก ADR/RFC ระบุ decision, owner, approver, alternatives, consequences,
affected contracts, review date, exception expiry และ supersession path

### 12.3 Contract and Schema Registry

เก็บ producer, consumer, version, compatibility, privacy class, lifecycle และ
removal gate ของ command, event, query, table, Firestore document และ export

### 12.4 Data Governance and Lineage

ทุก data field ต้องระบุ source, purpose, classification, consent, retention,
export/delete behavior และ downstream projections

### 12.5 Reconciliation and Repair Framework

ต้องมี bounded tools สำหรับ:

- rebuild projections from evidence
- verify ledger balances
- detect orphaned or stuck outbox entries
- detect duplicate reward grants
- inspect identity mapping conflicts
- compare local/cloud revisions
- verify migration completion
- forward-repair without destructive rollback

### 12.6 Operational Reliability Contract

กำหนด SLO, retry budget, dead-letter state, degraded mode, health status,
participant-safe errors, kill switches และ runbooks

### 12.7 Deterministic Test Data Platform

มี clock/timezone fixtures, identity factories, event builders, migration
snapshots, policy fixtures และ golden datasets โดยไม่ใช้ข้อมูล participant จริง

### 12.8 Content Lifecycle and Provenance

```text
Draft -> Reviewed -> Approved -> Published -> Retired
```

- published revision immutable
- AI สร้างได้เฉพาะ draft
- เก็บ creator, model, prompt, reviewer, license, locale และ CEFR mapping
- exercise compiler ใช้เฉพาะ approved content revision

### 12.9 AI, Prompt, and Model Registry

เก็บ model version, prompt version, capability, safety policy, evaluation,
provider, cost, latency, consent requirement และ fallback behavior

### 12.10 Authorization and Tenant Model

แยก identity, role, tenant membership, consent และ entitlement สำหรับ learner,
participant, teacher, researcher, creator, school และ administrator

### 12.11 Cost and Resource Governance

กำหนด quota, rate limit, budget, degraded mode และ kill switch สำหรับ AI,
voice, storage, Firestore, telemetry และ model download

### 12.12 Trust and Safety

Social, creator, marketplace และ AI-generated content ต้องมี reporting,
blocking, moderation, appeal, takedown, child-safety และ abuse-prevention contract

## 13. Feature Lifecycle Registries

### 13.1 Feature Registry States

- `disabled`
- `internal`
- `shadow`
- `pilot`
- `enabled`
- `deprecated`
- `emergency_off`

ทุก feature มี owner, default state, dependency, rollout cohort, expiry,
rollback behavior และ deletion/export impact

### 13.2 Experiment Registry

Experiment assignment ต้องมี experiment ID/version, hypothesis, eligible
population, consent, assignment unit, deterministic allocation, schedule,
metrics, guardrails, stop criteria และ analysis plan

Feature flag ห้ามสุ่ม cohort หรือทำหน้าที่เป็น research assignment

## 14. Architecture Fitness Tests

ต้องเพิ่ม automated structural tests อย่างน้อย:

1. UI ห้าม import Drift table, Firestore SDK หรือ SharedPreferences
2. V2 code ห้าม import quarantined legacy services
3. Motivation ห้าม import learner-model repository หรือ reward repository
4. Social ห้ามเขียน mastery/evidence tables
5. AI-generated content ห้าม publish โดยไม่มี approval record
6. Dialogue ขอเสียงผ่าน application-facing voice contract เท่านั้น
7. Reward grant ทุกครั้งมี source event, policy version และ idempotency key
8. Published event/content serialization ห้ามเปลี่ยนแบบ breaking
9. Published content revision immutable
10. Entity ใหม่ต้องอยู่ใน export/delete inventory ก่อน pilot
11. Firestore collection ใหม่ถูก deny จนกว่าจะมี rules และ emulator test
12. Projection ใหม่ต้องมี deterministic rebuild test
13. Migration ใหม่ต้องมี upgrade fixture จากทุก supported schema
14. Feature เปิด pilot ไม่ได้หากไม่มี kill switch และ owner
15. AI/voice provider ใหม่ต้องมี consent, fallback, cost และ retention policy

## 15. Golden Journeys

ทุก release train ต้องไม่ทำลายเส้นทางต่อไปนี้:

1. Guest เรียน offline แล้วกลับมาเรียนต่อ
2. เรียน offline แล้ว sync ซ้ำโดยไม่เกิด reward ซ้ำ
3. อัปเกรด guest เป็น account โดยข้อมูลไม่หาย
4. เปิด content revision เก่าและวิเคราะห์ย้อนหลังได้
5. Dialogue ค้างกลางทางแล้ว resume ได้
6. ปิด AI แล้ว fixed-content learning ยังใช้ได้
7. ปิด voice provider แล้วใช้ fallback ตาม policy
8. ถอน consent แล้วหยุด research/AI/social data use
9. กลับมาเรียนหลังหยุดหลายวันโดยไม่ถูกลงโทษ
10. rollback feature แล้ว authority เดิมยังทำงาน
11. เปลี่ยน timezone แล้ว learning day/streak ไม่ซ้ำหรือหาย
12. duplicate/out-of-order event ให้ projection ผลลัพธ์เดิม
13. account deletion กระจายไปยัง export, AI, voice และ derived projections
14. cloud sync ถูก emergency-off แต่ local learning ยังทำงาน
15. migration ล้มกลางทางแล้วเปิดแอปได้ด้วย forward-repair ที่กำหนด

## 16. Worktree and Release Train Rules

- integration branch เดียวเป็น canonical baseline
- หนึ่ง worktree รับผิดชอบหนึ่ง bounded domain
- central files ต้องมี explicit ownership
- ห้ามหลาย worktree แก้ database schema, event contracts, Firestore rules,
  composition root หรือ dependency manifest พร้อมกันโดยไม่มี reservation
- contract merge ก่อน consumer
- migration number ต้องจองใน schema ledger
- branch ต้อง sync integration baseline ก่อนแก้ central contract
- feature ที่ยังไม่พร้อม hidden โดยค่าเริ่มต้น
- integration ตาม dependency order ไม่ใช่เวลาที่ branch เสร็จ

Recommended merge sequence:

```text
Contract
-> Storage Migration
-> Repository Adapter
-> Application Use Case
-> Projection
-> UI
-> Sync and Rules
-> Export and Deletion
-> Observability
-> Feature Enablement
```

## 17. Phase -1: Current-State Reconciliation and Compatibility Foundation

Phase -1 ไม่สร้าง user-facing capability ใหม่

### 17.1 Required Deliverables

1. Capability and Idea Traceability Registry
2. Current-State Authority Matrix
3. Adopt/Extend/New/Deprecate Matrix
4. V1-V2 Compatibility Contract
5. Unified Event Envelope and Event Catalog
6. Identity Mapping Contract
7. Data and Schema Migration Sequence
8. Schema Reservation Ledger
9. Legacy Deprecation Registry
10. LexiMotivation Domain Specification
11. Economy and Reward Invariants
12. Policy Decision Record Contract
13. Feature/Experiment/Consent/Entitlement Boundary
14. Phase Acceptance, Regression and Rollback Gates
15. Worktree and Release Train Integration Rules
16. Domain Language Registry
17. Data Classification and Lineage Matrix
18. Operational Ownership Matrix

### 17.2 Phase -1 Exit Gate

Phase -1 ผ่านเมื่อ:

- ทุก current write path มี authority owner เพียงหนึ่งราย
- semantic separation ของ mastery, XP, points, coins, badge และ certification
  ได้รับการอนุมัติ
- legacy service ทุกตัวมี status, migration target และ removal gate
- schema history ถูกตรวจและเลข migration ถัดไปถูกจอง
- V1 events ถูกจัดประเภท retain/adapt/deprecate/reject
- architecture tests ป้องกัน legacy consumer และ direct infrastructure access
- export/delete/rules inventory รองรับ entity แรกของ V2
- golden journeys มี baseline evidence
- cutover และ rollback playbook ผ่าน review
- vertical slice แรกได้รับ approval

## 18. Recommended First Vertical Slice

ใช้เส้นทาง:

```text
Learning Evidence
-> EventEnvelopeV2 Adapter
-> Reward Eligibility Decision
-> RewardGrantRequest
-> Reward Ledger Transaction
-> Reward Balance Projection
-> Outbox and Sync
```

เหตุผล:

- ทดสอบ identity, event, idempotency, transaction, policy, projection และ sync
  ใน bounded slice เดียว
- ใช้ฐาน learning/reward/outbox ปัจจุบันได้
- ตรวจ semantic separation ระหว่าง mastery, XP และ spendable reward ได้
- สามารถเปิด shadow mode โดยไม่เปลี่ยนประสบการณ์ผู้ใช้

ห้ามเริ่ม social, marketplace, league หรือ school platform ก่อน slice นี้พิสูจน์
Stable Kernel และ migration strategy ได้

## 19. Definition of Ready

ก่อนเริ่ม capability ใหม่ต้องมี:

- domain owner
- purpose and non-goals
- source of truth
- inputs, outputs and prohibited actions
- command/query/event contracts
- identity and tenant context
- privacy classification and consent
- dependencies
- success metric and wellbeing guardrail
- policy/content/model version requirements
- migration and compatibility plan
- rollback and kill-switch behavior
- acceptance criteria
- test strategy
- export/delete/rules impact
- operational owner and cost budget

## 20. Definition of Done

ก่อนเลื่อนเป็น Production ต้องมี:

- unit, contract, integration and architecture tests
- offline behavior
- sync/idempotency and out-of-order behavior
- migration verification
- deterministic projection rebuild
- export/delete coverage
- observability and participant-safe error handling
- feature kill switch
- backward compatibility
- content/model/policy versions
- cost and quota controls
- security policy tests and bounded dependency checks
- documentation, runbook and deprecation impact
- golden journey evidence
- owner acceptance record

## 21. Traceability Template for Every Capability

| Field | Required Answer |
|---|---|
| Capability ID | Stable identifier |
| Owner System | Bounded context with decision authority |
| Architecture Plane | One primary plane |
| Lifecycle State | Common lifecycle value |
| Source of Truth | Authoritative store/projection |
| Read Inputs | Contracts and projections consumed |
| Allowed Writes | Commands/entities owned |
| Prohibited Writes | Explicit authority boundaries |
| Commands | Versioned application requests |
| Events | Versioned facts emitted |
| Queries | Read contracts exposed |
| Metrics | Formula, denominator, window and version |
| Consent | Required purpose and opt-out behavior |
| Dependencies | Upstream/downstream systems |
| Feature State | Default and rollout lifecycle |
| Experiment Context | Assignment and guardrails |
| Tests | Unit, contract, migration, architecture, journey |
| Migration | V1 source and V2 target |
| Rollback | Authority restoration strategy |
| Legacy Impact | Retain, adapt, deprecate or remove |
| Operational Owner | Runbook, alert and escalation |

## 22. Decision Gates Requiring Owner Approval

Recommendations are provided so these are not unspecified placeholders:

1. **XP:** retain as non-spendable engagement signal; never use for mastery or
   certification
2. **Points:** prohibit as a new ambiguous V2 contract term
3. **Spendable currency:** use one canonical concept, initially named Coins or
   Reward Credits, backed by one ledger
4. **Schema 7-9:** inspect history and field databases before reservation;
   do not assume they exist
5. **Learning day:** compute through versioned timezone policy, not device-local
   midnight alone
6. **Tenant:** introduce tenant context as optional in Stable Kernel before
   Teacher/School implementation
7. **Certification:** require verified assessment evidence and independent
   policy; never derive from XP
8. **Rejected ideas:** retain permanently with rationale and reconsideration gate
9. **P8 interaction:** V2 foundation runs as a sidecar workstream until active
   P8 dependencies and release gates permit integration

## 23. Non-Goals of Phase -1

Phase -1 does not:

- rewrite the application
- delete legacy data
- migrate all V1 events immediately
- implement all 35 capabilities
- introduce dual-write without proven idempotency
- change participant-facing behavior
- reopen accepted P0-P7 behavior without verified regression
- replace current P8 scope automatically

## 24. Approval Outcome

เมื่อเอกสารนี้ได้รับอนุมัติ ขั้นตอนถัดไปคือ:

1. สร้าง Phase -1 implementation plan แบบ file-by-file
2. ทำ current-state authority inventory จาก code paths จริง
3. freeze Stable Kernel contracts ก่อน consumer implementation
4. เพิ่ม architecture fitness tests ก่อน migration
5. ทำ vertical slice แรกใน shadow mode
6. review evidence ก่อน authority cutover
