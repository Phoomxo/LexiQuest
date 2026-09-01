# Adventure Motivation Mode — System Design and Delivery Blueprint

**Date:** 2026-09-01
**Status:** PROPOSED FOR OWNER REVIEW
**Baseline:** `99f7fb21` (`feature/alltcas-8-44-integration` remote baseline)
**Scope:** ออกแบบระบบและลำดับการพัฒนาเท่านั้น ยังไม่เปิดใช้ใน production

## 1. Decision

LexiQuest จะพัฒนา **Adventure Motivation Mode** เป็นมุมมองทางเลือกเหนือวงจรการเรียนเดิม ไม่ใช่เกมหรือระบบการเรียนอีกชุดหนึ่ง ระบบแบ่งเป็น **11 logical modules** ใน bounded context เดียวชื่อ `adventure` และเชื่อมกับ authority ที่มีอยู่ผ่าน typed application interfaces เท่านั้น

การตัดสินใจหลักมีดังนี้:

1. Standard Today Hub ยังคงเป็นเส้นทางหลักและเป็น fallback ที่ใช้งานได้เสมอ
2. Adventure ไม่มี authority ของ Vocabulary, SRS, Mastery, Assessment, Quest, Streak, Achievement, XP, Coins, Rewards, Recommendation, Today Hub หรือ History
3. แผนที่และความก้าวหน้า Adventure ในรุ่นแรกเป็น rebuildable read model ไม่เพิ่ม `adventure_progress` table
4. คำตอบทุกข้อยังผ่าน Unified Lesson Shell และ Evidence Gateway เดิม
5. Feature delivery, experiment assignment, consent และ learner preference เป็น state คนละชุด ห้ามอนุมานแทนกัน
6. Feature เริ่ม `hidden` และต้องผ่าน Internal และ Pilot ก่อน Enabled
7. ไม่มี hearts/lives, shame streak, forced timer, public leaderboard หรือการลด progress เมื่อผู้เรียนตอบผิด
8. เฟสแรกไม่มี generative AI, camera quest, multiplayer หรือ social network

## 2. Why This Direction

### 2.1 ผู้ใช้ต้องการอะไร

ผู้เรียนต้องสามารถ:

- เข้าใจได้ทันทีว่าวันนี้ควรเรียนอะไร;
- เริ่มเรียนได้ด้วยแรงกดดันต่ำ;
- เห็นความคืบหน้าแบบมีความหมาย แต่ไม่ถูกหลอกว่ารางวัลคือความรู้;
- ตอบผิดได้โดยไม่เสียชีวิต ไม่เสีย streak และไม่ถูกลงโทษ;
- กลับมาเรียนต่อหลังหยุดหรือออฟไลน์ได้;
- สลับกลับ Today Hub ปกติได้ทุกเวลา;
- ใช้ระบบได้ด้วย screen reader, text scaling และ reduced motion;
- เข้าใจว่าข้อมูลใดใช้เพื่อการวิจัยและถอนความยินยอมได้

### 2.2 ระบบปัจจุบันกำหนดข้อจำกัดอะไร

Baseline 8/44 มีข้อกำหนดที่ Adventure ต้องรักษา:

- `TodayHubReader` ประกอบข้อมูลจาก authority เดิมและไม่เป็นเจ้าของ progress;
- `FeatureRegistry` ควบคุม availability และ kill switch แต่ไม่กำหนด experiment cohort;
- `ExperimentRegistry` ให้ stable assignment แยกจาก feature delivery;
- `AnswerAttempts` เป็น canonical answer evidence;
- `EventEnvelopeV2` ถูก freeze และห้ามเพิ่ม research fields โดยไม่มี version decision;
- Quest, Gentle Streak, Achievement และ Reward มี authority ของตนแล้ว;
- XP เป็น lifetime progression และ Coins เป็น spendable currency คนละ ledger semantics;
- owner-scoped data ใหม่ต้องมี upgrade, sync, export, withdrawal, deletion และ retention;
- local-first commit ต้องเกิดก่อน cloud sync

## 3. Goals

### 3.1 Product goals

- เพิ่มความเต็มใจเริ่มเซสชันและกลับมาเรียน โดยไม่ทำให้คุณภาพการเรียนลดลง
- ทำให้ Today Hub มี presentation แบบ Adventure ที่เข้าใจง่ายและเลือกกลับแบบปกติได้
- ใช้เนื้อหา โหมดเรียน Feedback, Review และ Recommendation ชุดเดียวกับระบบปัจจุบัน
- ให้ความผิดพลาดเป็นข้อมูลเพื่อช่วยเรียน ไม่ใช่โทษ

### 3.2 Research goals

- เปรียบเทียบ Standard Today Hub กับ Adventure treatment บน learning core เดียวกัน
- วัด Motivation, Behavior, Effort และ Learning แยกแกน
- เก็บ assignment, consent, treatment, instrument, content และ policy version ที่ตรวจย้อนกลับได้
- รองรับ intention-to-treat analysis และบันทึก crossover เมื่อผู้ใช้สลับมุมมอง

### 3.3 Engineering goals

- Feature-off แล้วระบบ 8/44 ต้องทำงานเหมือน baseline
- Adventure package ลบออกได้โดยไม่สูญเสีย evidence หรือ progress
- ไม่มี UI เขียนตาราง learning/motivation โดยตรง
- ทุก side effect retry ได้แบบ idempotent
- Offline/restart ไม่สร้างคำตอบหรือรางวัลซ้ำ

## 4. Non-Goals

รุ่นแรกจะไม่ทำ:

- ระบบคำศัพท์หรือ SRS ใหม่;
- Adventure-specific mastery score;
- hearts, lives, energy หรือ pay-to-continue;
- mandatory countdown;
- global/public leaderboard;
- generative companion หรือ AI tutor integration;
- camera/object-scanner quests;
- multiplayer, friend, room หรือ chat;
- branching story choices ที่ต้องเก็บ durable state;
- remote executable story scripts;
- achievement share card ใน treatment แรก;
- เปลี่ยนการซื้อ cosmetic ให้กระทบ lifetime XP

## 5. Architectural Principles

### 5.1 One authority per fact

| Fact | Canonical owner | Adventure permission |
|---|---|---|
| Word/content identity | Vocabulary and Learning Pack authorities | Read by ID/revision only |
| Answer correctness/evidence | Learning/Evidence Gateway | Supply origin context only |
| Review due state | SRS/Review | Read and launch only |
| Mastery/weakness | Mastery projections | Read-only presentation |
| Quest progress | Quest authority | Request/evaluate through use case |
| Streak | Gentle Streak authority | Read reaction only |
| Achievement | Achievement policy/projection | Read unlock result |
| Lifetime XP/Coins | Reward authority | Read balance/progression; no direct write |
| Today work | Today Hub read model | Compose an Adventure representation |
| Recommendation | Recommendation read model | Preserve reason and learner override |
| Home presentation choice | Learner Preferences v2 | Read and request typed mutation only |
| Experiment assignment | Experiment Registry | Read exact assignment only |
| Consent | Consent Registry | Enforce upload/research eligibility |
| Adventure journey position | Derived Journey Projection | Rebuild from canonical readers; never write authority |
| Motivation instrument responses | Research measurement authority (schema v24) | Collect through consent-aware use case only |

### 5.2 Presentation can disappear

Adventure must be removable without migration rollback, evidence deletion or progress loss. Durable learning remains valid when the feature is hidden or emergency-off.

### 5.3 Learning before reward

Reward and narrative unlocks occur only after canonical learning/effort evidence commits successfully. A UI animation is never proof that a reward was granted.

### 5.4 Support before punishment

Incorrect, hint-assisted, skipped, timed-out and technical-failure states are distinct. Technical failure never penalizes the learner.

## 6. System Context

```text
FeatureRegistry ───────────────┐
ExperimentRegistry ───────────┤
ConsentRegistry ──────────────┤
                              ▼
                    Adventure Entry Control
                              ▼
World/Story Catalog ──► Adventure Experience Shell
                              ▲
Today Hub/History/Quest ─► Journey Projection
                              ▼
                    Adventure Session Composer
                              ▼
                    Unified Lesson Shell
                              ▼
                       Evidence Gateway
                   ┌──────────┼───────────┐
                   ▼          ▼           ▼
              SRS/Mastery   Effort   Quest/Streak/Reward
                   └──────────┼───────────┘
                              ▼
                 Result/Recovery/Companion
                              ▼
                 Research Measurement/Export
```

## 7. Module Map

### M01 — Adventure Delivery & Entry Control

**Responsibility**

- Resolve effective availability from `FeatureRegistry`;
- apply hidden/internal/pilot/enabled/emergency-off states;
- resolve Standard vs Adventure presentation without changing cohort;
- expose typed unavailable/fallback states;
- route to Standard Today Hub when any required dependency is unavailable

**Consumes**

- `FeatureRegistry`;
- `ExperimentRegistry` when a study protocol is active;
- `ConsentRegistry` for research upload, not for ordinary local use;
- session-local presentation choice in Phase 1;
- `LearnerPreferences` v2 home-experience authority from Phase 3 onward

**Produces**

- `AdventureEntryDecision` with availability, presentation, treatment identity, fallback reason and version pins

**Persistence**

- Phase 1 developer/internal preview keeps the Standard/Adventure choice session-local and adds no schema migration;
- before the choice is released as a durable product preference, schema v23 adds typed `homeExperience` to `LearnerPreferences`, bumps `preferenceVersion` from 1 to 2 and migrates every existing owner to `standard`;
- schema v23 must update owner lifecycle, guest-upgrade, sync, conflict, export, deletion and rollback-compatibility tests;
- experiment assignment remains in the existing assignment authority

**Fail-safe**

- Missing/malformed configuration resolves to Standard Today Hub;
- emergency-off blocks new Adventure entry but lets an accepted lesson close safely

### M02 — Adventure Experience Shell

**Responsibility**

- Render map, node states, current mission, companion, primary CTA and standard-view switch;
- expose loading, empty, stale, corrupt, offline and unavailable states;
- maintain accessible focus order and reduced-motion alternatives;
- never perform domain writes

**Consumes**

- `AdventureJourneySnapshot`;
- `AdventureEntryDecision`;
- theme/accessibility/motion settings

**Produces**

- user intents such as `startMission`, `changeDuration`, `switchToStandard`, `openNodeDetails`

**Persistence**

- None

### M03 — World, Story & Asset Catalog

**Responsibility**

- Own immutable world/chapter/node/story definitions;
- pin catalog version, locale, asset checksum and QA state;
- define scripted companion reactions and story fragments;
- provide a non-visual list alternative for accessibility;
- integrate asset download/verification with Offline Content Manager

**Produces**

- `AdventureWorldCatalog`;
- `AdventureWorldDefinition`;
- `AdventureNodeDefinition`;
- `CompanionScriptDefinition`;
- `AdventureAssetManifest`

**Persistence**

- Packaged typed catalog and verified content bundle;
- no owner progress rows

**Validation**

- unique stable IDs;
- acyclic prerequisite graph;
- bounded copy;
- all locale keys resolve;
- every asset checksum matches;
- no remote executable behavior

### M04 — Adventure Journey Projection

**Responsibility**

- Convert canonical read models into map state;
- map Today Hub work, Quest, Achievement, Reward ownership, pack completion and History to visual nodes;
- calculate visible/current/completed/locked states deterministically;
- remain rebuildable from canonical authorities

**Consumes**

- `TodayHubSnapshot`;
- existing Quest, Streak, Achievement, Reward, History and pack-completion readers;
- World/Story Catalog

**Produces**

- `AdventureJourneySnapshot` containing source freshness, dependency states, visible nodes, current mission and next unlock

**Persistence**

- None in Phase 1;
- a journey cache is deferred beyond this plan; any future cache requires a separate design and must remain disposable, rebuildable and non-authoritative

### M05 — Adventure Session Composer

**Responsibility**

- Convert canonical Today Hub work into an Adventure session plan;
- preserve review reasons and recommendation explanation;
- support bounded duration choices without silently changing study arm;
- pin all content/session/policy/treatment identities;
- create deterministic retry identity

**Selection policy v1**

- due/review work is admitted before new work;
- recent incorrect/low-confidence work remains visible through existing Review/Recommendation;
- saved items indicate learner intent, not automatic weakness;
- duration changes reduce or extend item count through existing session-configuration rules;
- the composer never fetches a second vocabulary catalog

**Produces**

- `AdventureSessionPlanV1` with:
  - plan ID and owner ID;
  - source Today Hub evaluation time;
  - node/world/catalog versions;
  - ordered existing content identities;
  - existing lesson modes;
  - session configuration;
  - recommendation/policy versions;
  - experiment/treatment identity when eligible;
  - content revision and checksums

**Persistence**

- No separate plan table in MVP;
- required origin/version data must be carried through an approved versioned session/evidence context

### M06 — Learning Session & Evidence Bridge

**Responsibility**

- Launch the existing Unified Lesson Shell from an Adventure plan;
- translate Adventure origin into approved typed context;
- preserve session lifecycle, active-time tracking, hint classification and exact evidence retry;
- prevent Adventure UI from invoking repositories directly

**Rules**

- `EventEnvelopeV2` is not modified silently;
- learning answer events retain their existing event types and semantics; Adventure origin is carried by an approved `AdventureOriginContextV1` inside the supported versioned evidence-context boundary;
- if that boundary cannot carry the context without changing existing semantics, implementation stops for an explicit envelope-version decision rather than adding fields to `EventEnvelopeV2`;
- Adventure does not supply correctness, mastery weight or reward eligibility;
- assessment sessions cannot be wrapped as reward-granting Adventure missions

### M07 — Motivation & Unlock Coordinator

**Responsibility**

- React only to successfully committed eligible events;
- call canonical Quest, Gentle Streak, Achievement and Reward application ports;
- derive story/cosmetic visibility from canonical receipts;
- make all commands idempotent

**Rules**

- no duplicate quest/streak/reward repository;
- no reward for opening the map alone;
- no reward from assessment evidence;
- hint-assisted work remains guided practice;
- repeated delivery of one source evidence ID cannot duplicate unlocks;
- cosmetic purchase never reduces lifetime XP

### M08 — Companion, Avatar & Narrative Reaction

**Responsibility**

- Select versioned scripted reactions from committed session states;
- render equipped avatar/cosmetics from Reward ownership;
- provide supportive feedback for incorrect, hint, skip, return and completion states;
- avoid claims that engagement equals mastery

**Rules**

- the first treatment is scripted only;
- no free-text AI generation;
- no separate companion relationship score;
- reduced-motion and no-audio alternatives are mandatory;
- copy must never shame absence or failure

### M09 — Result, Recovery & Review Continuity

**Responsibility**

- Present Learning, Effort and Engagement separately;
- handle wrong-answer repair and next-session review;
- resume/close accepted sessions safely across restart;
- reconcile learning success when a later reward projection fails;
- return to Standard Today Hub when Adventure becomes unavailable

**Incorrect-answer policy v1**

1. Commit incorrect evidence through the existing gateway.
2. Show immediate contrastive feedback and optional hint.
3. Requeue after 3–5 intervening items, never immediately.
4. Run at most one repair round in the current session.
5. If fewer than three eligible intervening items remain, do not pad or prolong the session; defer the repair to Review/SRS.
6. If the repair is still incorrect, let Review/SRS schedule the next encounter.
7. Step support from Flashcard → Recognition/Matching → Cloze → Typed Recall according to the existing recall ladder.

**Technical failure policy**

- Evidence failure: freeze completion/reward and retry the exact captured evidence identity;
- reward/projection failure after evidence commit: keep learning result and retry the idempotent projection later;
- app termination: use existing session recovery;
- corrupt world bundle: quarantine bundle and fall back to Standard Today Hub;
- kill switch during session: stop new Adventure operations, close/retire the lesson through its existing lifecycle, then return to Standard

### M10 — Motivation Research & Experiment Measurement

**Responsibility**

- Resolve stable Standard/Adventure assignment independently from delivery flags;
- pin protocol, treatment, assignment, consent, instrument and app/build versions;
- collect bounded self-report motivation measures;
- collect behavior exposure/crossover events;
- export separate Outcome, Learning, Effort and Engagement axes;
- support consent withdrawal and data lifecycle

**Primary analysis**

- Intention-to-treat comparison by stable assignment.

**Secondary analysis**

- exposure, adherence and crossover;
- voluntary start, completion, optional continuation and return behavior;
- active learning time;
- learning guardrails such as independent recall and SRS retention

**Measurement rules**

- XP, streak or app opens alone are not evidence of motivation;
- no single combined score;
- no raw unbounded free text in research response rows;
- research prompts appear only at declared natural breakpoints, always offer Skip and never block ordinary learning completion;
- a protocol involving minors requires the applicable ethics review, guardian permission and learner assent before research collection; Adventure product use itself remains available without research participation;
- study protocol must pre-register instrument, scoring, sample-size method and statistical thresholds before Pilot;
- product functionality remains locally usable without consenting to research upload

**Persistence after MVP shell**

The baseline database is schema v22. After schema v23 has introduced the durable home-experience preference, schema v24 adds exactly two owner-scoped research tables:

- `motivation_measurement_runs`, represented by `MotivationMeasurementRun`, with owner ID, run ID, stable assignment ID, consent receipt ID, protocol/treatment/instrument/form versions, app/build version, started/completed timestamps and run status;
- `motivation_responses`, represented by `MotivationResponse`, with owner ID, run ID, item catalog ID/version, bounded response code, ordinal value where defined and answered timestamp.

For an actively consented measurement run with a stable assignment, Adventure behavior exposure is recorded in existing `EventsV2` through registered versioned event types with bounded payload v1: `AdventurePresented`, `AdventureMissionStarted`, `AdventureSwitchedToStandard` and `AdventureMissionCompleted`. These events use the frozen `EventEnvelopeV2`, its existing experiment/consent contexts and the existing outbox; they add no envelope fields and never replace learning-answer events. Non-participants do not receive research exposure rows merely for using Adventure.

Schema v24 and the four event payload policies cannot ship until migration, identity, lifecycle, sync/rules, export, withdrawal, deletion, retention and replay-compatibility tests pass. If another change occupies schema v23 or v24 before implementation, the migration numbers are rebased upward in order; an occupied version is never reused.

### M11 — Adventure Operations, Quality & Reliability

**Responsibility**

- validate catalogs, locale copy and asset manifests;
- manage Internal/Pilot/Enabled promotion evidence;
- expose bounded diagnostics without research payload leakage;
- support offline bundle verify/repair/remove;
- enforce guest upgrade, owner isolation, export and deletion;
- verify feature-off, emergency-off and forward-only rollback

**Operational signals**

- Adventure entry/fallback counts;
- journey composition failures by typed reason;
- evidence retry and reward-projection retry counts;
- corrupt/missing asset bundle counts;
- session resume/abandon rates;
- experiment assignment mismatch count, which must remain zero;
- duplicate reward/unlock rejection count

## 8. User Experience Flow

### 8.1 Entry

1. App resolves feature availability.
2. Standard Today Hub composes normally regardless of Adventure.
3. Adventure entry resolves assignment/preference without changing either.
4. Journey Projection consumes the same Today Hub snapshot.
5. If composition fails, the learner sees Standard Today Hub with no data loss.

### 8.2 Starting a mission

1. Learner sees one primary mission and an estimated duration.
2. Learner may change duration or switch to Standard.
3. Session Composer pins canonical content and policy versions.
4. Unified Lesson Shell starts the existing lesson session.
5. No reward is granted at start.

### 8.3 During learning

1. Each response is classified as independent recall, recognition, guided practice, incorrect, skip, timeout or technical failure.
2. Feedback and hints come from existing policies.
3. Adventure presents atmosphere and companion reaction but does not score the response.
4. Durable evidence commits before motivation side effects.

### 8.4 Completion

1. Existing lesson lifecycle closes the session.
2. Canonical projections update from eligible evidence.
3. Motivation coordinator requests idempotent quest/streak/achievement/reward updates.
4. Result screen shows Learning, Effort and Engagement separately.
5. Journey is recomposed from canonical state.

### 8.5 Return and continuity

- A resumable lesson takes priority over a new mission.
- A missed day triggers recovery copy, not streak shame.
- A previously incorrect word returns through Review/SRS; Journey Projection represents due repair work as a Review node that references the existing word identity and never copies the word record.
- History replay creates a new session and never edits original evidence.

## 9. Accessibility and Inclusive Design

Adventure cannot be promoted unless it supports:

- screen-reader landmarks and one semantic action per interactive node;
- map-list alternative with identical actions and progress meaning;
- text scaling without clipped CTA or hidden mission details;
- non-color indicators for complete/current/locked/error;
- reduced-motion path transitions and zero-duration alternative;
- untimed mode and no loss from pauses;
- touch targets consistent with Material 3 minimums;
- Thai and English copy with stable glossary;
- audio captions/transcripts and non-audio alternatives;
- standard-view escape visible without scrolling

## 10. Data and Lifecycle Design

### 10.1 MVP journey persistence decision

M01–M09 add no Adventure progress table. World progress is derived from canonical Quest, Achievement, Reward ownership, pack completion and History. Phase 1 keeps the view switch session-local, so its read-only internal shell changes neither schema v22 nor any owner record. This minimizes migration risk and makes feature rollback safe.

### 10.2 Durable home-experience preference

Schema v23 adds `home_experience TEXT NOT NULL DEFAULT 'standard'` to `learner_preferences`. The domain exposes only `HomeExperience.standard` and `HomeExperience.adventure`; unknown serialized values fail closed to Standard and are reported through bounded diagnostics. The migration bumps `preferenceVersion` to 2 without changing goal, duration, activity, theme or motion values. It ships in Phase 3 only after the read-only shell and learning bridge pass their exit gates.

This preference expresses the learner's product choice only. It does not grant feature availability, create experiment assignment or imply research consent.

### 10.3 Durable research data and behavior events

Schema v24 adds `motivation_measurement_runs` and `motivation_responses` only after the shell and learning bridge are proven. Every table must:

- reference an owner and stable assignment;
- pin protocol/treatment/instrument/form/content/policy/app/build versions;
- contain bounded values;
- appear exactly once in the owner lifecycle manifest;
- have deterministic guest-upgrade behavior;
- define local export, consent withdrawal, deletion and retention;
- use local-first outbox sync and exact Firestore rules/version policy;
- reject incompatible replay instead of overwriting

The four Adventure exposure events named in M10 use existing `EventsV2` storage and outbox contracts. Their payload v1 schemas are bounded and registered; no raw narrative copy, free text or duplicated learning answer is stored in them.

### 10.4 Story choices

Branching durable story choices are outside Phase 1. If introduced later, they require a separately approved authority and cannot be inferred from reward ownership when the meaning is not equivalent.

## 11. Offline and Sync

- Standard Today Hub and locally available lessons remain usable when Adventure assets are missing.
- Adventure entry is allowed offline only when required world and learning content revisions are verified locally.
- Asset download/removal uses Offline Content Manager; removing assets never removes learning evidence.
- Learning evidence commits locally before sync.
- Motivation side effects are derived/retried locally with stable idempotency keys.
- Research upload stops immediately after consent withdrawal; allowed local participant export remains available.
- Conflicting treatment/catalog/version metadata fails closed and does not merge.

## 12. Feature Delivery and Experiment Separation

### 12.1 Feature state

Append `adventureMotivation` to `Feature` without renaming or reordering existing serialized names. Add it to every exhaustive registry and production-contract map, with `BuildFeatureRegistry.fieldDefaults()` set to `hidden`. Persisted runtime overrides continue to use stable feature names; unknown names are ignored safely and cannot enable Adventure. Contract tests must prove an old override store still loads and a baseline build remains fail-closed.

### 12.2 Treatment state

Experiment assignment uses `ExperimentRegistry` and persists independently. A feature flag change cannot reassign a participant.

### 12.3 Learner preference

Outside a research protocol, the learner may choose Standard or Adventure. Inside a protocol, the assigned presentation is recorded, but the visible Standard escape remains available; switching is recorded as crossover and never rewrites assignment.

### 12.4 Rollback

- Hide entry and block new Adventure starts.
- Preserve accepted lesson/evidence operations.
- Return to Standard after safe terminal close.
- Keep schema and evidence forward-compatible.
- Never delete Adventure-related research evidence merely because the feature is off.

## 13. Measurement Framework

| Axis | Measures | Interpretation |
|---|---|---|
| Outcome | Versioned pre/post comparison where protocol requires | Learning outcome, isolated from practice rewards |
| Learning | Independent recall, recognition, guided practice, incorrect, SRS retention | What the learner demonstrated |
| Effort | Active learning time, completed work, voluntary continuation | Work invested without idle/background inflation |
| Engagement | Start, completion, return, switch, quest/reward interaction | Product interaction, not mastery |
| Motivation | Versioned bounded self-report instrument | Learner-reported motivation under a declared scoring rule |

Promotion to Pilot requires:

- stable assignment consistency of 100%;
- zero known pathways from assessment to motivational rewards;
- zero duplicate reward grants in retry/restart tests;
- 100% complete required version metadata for eligible research records;
- a pre-registered primary motivation outcome and learning guardrails;
- no unresolved critical accessibility or evidence-integrity defect

This product design does not choose a statistical effect-size threshold; the study protocol must declare it from its power analysis before participant enrollment.

## 14. Testing Strategy

### 14.1 Contract tests

- exactly one Adventure runtime feature mapping;
- adding the feature does not enable it;
- feature visibility does not assign a cohort;
- dependencies resolve and rollback entry exists;
- Adventure package has no imports of Drift tables owned by learning/motivation authorities

### 14.2 Module unit tests

- catalog ID/checksum/graph/localization validation;
- deterministic journey projection;
- deterministic session plan and retry identity;
- invalid/stale/mixed-owner input rejection;
- companion reaction mapping;
- wrong-answer repair limit and recall-ladder routing

### 14.3 Integration tests

- Standard and Adventure produce equivalent canonical learning plans for the same treatment-safe input;
- Adventure launches Unified Lesson Shell without direct repository writes;
- one response maps to one evidence identity across retry/outbox/projections;
- evidence failure grants no reward;
- reward failure preserves learning evidence;
- feature off and emergency-off return to Standard;
- offline start/resume/complete/restart;
- corrupt asset fallback;
- guest upgrade and owner isolation
- v22→v23 preference migration defaults to Standard and preserves every existing preference field;
- v23→v24 research migration, owner lifecycle and forward-only rollback compatibility;
- Adventure payload v1 allowlist, identity, replay and outbox behavior

### 14.4 Research isolation tests

- assignment cannot change from preference or kill switch;
- missing/withdrawn consent blocks research upload;
- assessment cannot update SRS, Mastery, Quest, Streak, Achievement, XP or Coins;
- Standard/Adventure export pins treatment and contract versions;
- crossover does not rewrite assignment;
- Outcome, Learning, Effort, Engagement and Motivation remain separate

### 14.5 Accessibility tests

- semantic node/action uniqueness;
- map-list parity;
- large text and Thai copy layout;
- reduced-motion behavior;
- keyboard/focus traversal where supported;
- color-independent states

### 14.6 Baseline verification note

On 2026-09-01, a bounded Flutter test launch from an isolated worktree at `99f7fb21` crashed inside Flutter 3.44.7 native-assets test compilation with `StateError: Bad state: No element` before tests executed. This is an environment/tooling failure, not evidence that the selected tests passed or failed. Implementation planning must include a clean baseline verification run after repairing or bypassing that SDK issue through an approved environment configuration.

## 15. Delivery Phases

### Phase 0 — Baseline and contracts

**Modules:** M01, M03, M11 foundation
**Deliverables:**

- freeze exact 8/44 baseline;
- add feature-contract design and dependency mapping;
- append the hidden `adventureMotivation` feature and update exhaustive registry/contract mappings without a database migration;
- define World Catalog v1 and validator;
- add negative architecture tests;
- no navigation entry and no learner-facing activation

**Exit gate:** feature-off build is behaviorally equivalent to baseline.

### Phase 1 — Read-only Adventure shell

**Modules:** M02, M04, M05
**Deliverables:**

- one world, three visual nodes and map-list alternative;
- journey snapshot built from fixtures then canonical readers;
- session composer over Today Hub/Review/Recommendation;
- Standard switch and typed fallback;
- session-local presentation choice only;
- no schema change and no new database table

**Exit gate:** Journey recomposes deterministically and cannot write progress.

### Phase 2 — Learning bridge and recovery

**Modules:** M06, M09
**Deliverables:**

- Unified Lesson Shell launch;
- approved origin-context contract;
- exact evidence retry;
- wrong-answer repair flow;
- restart/resume/kill-switch integration;
- separate result axes

**Exit gate:** identical canonical evidence semantics between Standard and Adventure paths.

### Phase 3 — Motivation and companion

**Modules:** M01, M07, M08
**Deliverables:**

- schema v23 durable `homeExperience` preference, defaulting every owner to Standard;
- preference v2 sync, conflict, guest-upgrade, export and delete support;
- canonical Quest/Streak/Achievement/Reward integration;
- idempotent story/cosmetic unlock presentation;
- scripted companion reactions;
- no hearts, penalties or generative AI

**Exit gate:** no duplicate rewards and no Adventure-owned progression.

### Phase 4 — Research instrumentation

**Modules:** M10, M11 lifecycle extensions
**Deliverables:**

- versioned treatment catalog;
- schema v24 `motivation_measurement_runs` and `motivation_responses`;
- four registered Adventure exposure event payloads v1 in existing `EventsV2`;
- motivation instrument and bounded response model;
- consent/assignment enforcement;
- migration, lifecycle, sync/rules and export;
- research-isolation tests;
- pre-registered analysis protocol

**Exit gate:** complete reconstructible metadata and withdrawal-safe behavior.

### Phase 5 — Internal and Pilot rollout

**Modules:** all
**Deliverables:**

- Internal dogfood with diagnostics;
- accessibility and Thai-language review;
- offline/content bundle repair;
- small consented pilot;
- guardrail and data-quality review;
- emergency-off rehearsal

**Exit gate:** promotion evidence approved; otherwise feature remains Limited/Hidden.

### Phase 6 — Controlled enablement

- expand only after pilot evidence;
- maintain Standard Today Hub as permanent fallback;
- treat new worlds, AI, camera and social features as separate design/spec cycles

## 16. Proposed Package Boundaries

```text
lib/features/adventure/
  domain/
    adventure_entry.dart
    adventure_world_catalog.dart
    adventure_journey.dart
    adventure_session_plan.dart
    adventure_origin_context.dart
    adventure_reaction.dart
  application/
    adventure_entry_use_cases.dart
    adventure_journey_reader.dart
    adventure_session_composer.dart
    adventure_learning_bridge.dart
    adventure_motivation_coordinator.dart
    adventure_recovery_use_cases.dart
  presentation/
    adventure_hub_screen.dart
    adventure_result_screen.dart
    widgets/
  data/
    packaged_adventure_world_catalog.dart

lib/features/research/
  domain/
    motivation_instrument.dart
    motivation_measurement.dart
  application/
    motivation_measurement_use_cases.dart
  data/
    # Added only in Phase 4 after lifecycle/schema approval
```

Presentation cannot import Drift tables. Application modules depend on interfaces. Data adapters implement those interfaces and remain owner/lifecycle aware.

## 17. Dependency Order

```text
M01 ─┬─► M02
     └─► M05
M03 ─┬─► M04 ─► M02
     └─► M08
M04 ─► M05 ─► M06 ─► M09
M06 ─► M07 ─► M08
M06/M07/M09 ─► M10
M11 supports and gates M01–M10
```

No module may be implemented before its incoming contract is tested.

## 18. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Adventure duplicates progress authority | Data divergence | Derived journey projection; no Phase-1 progress table |
| Rewards contaminate learning claims | Invalid research | Separate axes; eligible-event policy; assessment isolation |
| Feature flag changes cohort | Invalid causal comparison | Independent Experiment Registry and invariant tests |
| Wrong answer feels punitive | Lower motivation | repair spacing, supportive copy, no loss mechanics |
| Map inaccessible | Excludes users | map-list parity, semantic order, reduced motion |
| Asset bundle corrupt/offline | Entry failure | checksum, quarantine, repair and Standard fallback |
| Retry grants twice | Economy corruption | source evidence ID and idempotent receipts |
| Adventure metadata mutates frozen V2 event | Contract break | approved versioned context or explicit new envelope version |
| Research data cannot be withdrawn | Ethics/lifecycle failure | consent registry, outbox blocking, export/delete/retention tests |
| Too many variables in first study | Uninterpretable result | one world, scripted companion, no AI/camera/social |
| Completed 8/44 baseline is not reproducibly verified | Unknown regression source | repair SDK test crash and record clean baseline before production changes |

## 19. Acceptance Criteria

Adventure Motivation Mode is ready for Pilot only when all conditions hold:

1. Standard Today Hub remains fully usable with Adventure hidden or emergency-off.
2. Adventure creates no Vocabulary, SRS, Mastery, Quest, Streak, XP, Coins, Reward, Recommendation, Today Hub or History authority.
3. Every answer uses the existing Unified Lesson Shell and Evidence Gateway.
4. No reward is granted before durable eligible evidence.
5. Incorrect answers follow repair/review rules without progress loss.
6. Learning, Effort, Engagement and Motivation are displayed/exported separately.
7. Assignment, feature state, preference and consent cannot overwrite one another.
8. Offline/restart/guest-upgrade/export/delete/withdrawal tests pass for every new persisted owner record.
9. Map-list parity, reduced motion, text scaling and screen-reader semantics pass.
10. Feature-off and emergency-off integration tests pass.
11. All catalog/assets have stable IDs, versions, checksums and QA state.
12. Research protocol and statistical decision rules are registered before Pilot.
13. No unresolved critical evidence-integrity, privacy, accessibility or duplicate-reward defect remains.

## 20. Review Decision Requested

Owner review should confirm these decisions before the task-by-task implementation plan is written:

- 11-module architecture;
- Adventure as optional Today Hub presentation;
- no Adventure progress table in MVP;
- session-local switch in Phase 1, followed by schema v23 durable preference in Phase 3;
- no AI/camera/multiplayer in first treatment;
- Standard view always available;
- schema v24 research measurement and registered Adventure exposure events added only after the learning bridge is proven;
- rollout order Hidden → Internal → Pilot → Enabled
