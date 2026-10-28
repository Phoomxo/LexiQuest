# Current System Audit and Adventure Impact Assessment

**Document ID:** AMM-AUDIT-001
**Version:** 1.0
**Status:** Baseline Evidence for Planning
**Audit date:** 2026-09-01
**Product:** LexiQuest
**Production-code baseline:** commit `99f7fb21`
**Planning HEAD at audit:** commit `76300065`
**Database:** Drift schema v22
**Flutter/Dart:** Flutter 3.44.7 / Dart 3.12.2
**Audit rule:** read-only inspection and bounded local verification; no production implementation or remediation was performed

## 1. Executive Decision

ผลตรวจสนับสนุนให้ดำเนินงาน **Adventure Motivation Mode ในขั้นเอกสาร สถาปัตยกรรม prototype และ hidden internal build** ได้ โดยมีเงื่อนไขว่า Adventure ต้องเป็น presentation ทางเลือกเหนือ authority เดิม ไม่ใช่ระบบการเรียนหรือระบบรางวัลชุดที่สอง

สถานะการตัดสินใจแบ่งเป็นสามระดับ:

| ระดับ | ผลตัดสิน | เหตุผล |
|---|---|---|
| จัดทำเอกสารและ prototype แบบไม่เขียนข้อมูล | **GO** | learning core, evidence, SRS, progress, Today Hub และ lifecycle มี authority ชัดเจนพอให้วาง integration boundary |
| เริ่ม implementation แบบ hidden/default-off | **CONDITIONAL GO** | ต้องปิด baseline blockers ที่เกี่ยวข้องกับไฟล์ที่จะเปลี่ยน และสร้าง feature contract/kill switch ก่อน |
| เปิด Android Pilot v1 หรือ production | **NO-GO ณ วันที่ตรวจ** | Android Pilot ยังมี shared/touched-scope failures, Gitleaks/dependency disposition และ release evidence ที่ไม่พร้อม; iOS/desktop/AI Voice/field-model เป็น explicit exclusions ตาม ADR-005 และไม่ถูกนับว่า “ผ่าน” |

ข้อค้นพบสำคัญที่สุดคือ **Today Hub ซึ่งเหมาะจะเป็นฐานของ Adventure มี implementation และ composition แล้ว แต่ถูกซ่อนใน production defaults** ผู้ใช้จึงมองไม่เห็นภาพรวม 8/44 แม้งานด้าน source จะเสร็จ การออกแบบ Adventure ต้องแก้ปัญหา “มองไม่เห็นคุณค่าของระบบเดิม” โดยฉายข้อมูลเดิมให้เข้าใจง่ายขึ้น ไม่ใช่สร้าง gameplay แยกที่ทำลาย flow เดิม

## 2. Audit Objectives

การตรวจครั้งนี้มีวัตถุประสงค์เพื่อ:

1. ระบุว่าระบบ 8 หมวด 44 ความสามารถมีอะไรและอยู่ตรงไหนจริง;
2. ระบุ authority ของข้อมูลการเรียน ความจำ ความก้าวหน้า รางวัล งานวิจัย และ sync;
3. ตรวจเส้นทางหน้าจอ production ว่าผู้ใช้เข้าถึงอะไรได้จริง;
4. ตรวจ schema, owner lifecycle, export, deletion, guest upgrade และ offline behavior;
5. ตรวจ baseline ด้วย static analysis, tests, emulator tests, secret scan และ dependency scan;
6. หา integration seam ที่ Adventure ใช้ได้โดยไม่สร้าง state ซ้ำ;
7. สร้าง gate ที่แยก “ต้องแก้ก่อนเริ่ม”, “ต้องแก้ก่อน Pilot” และ “ต้องแก้ก่อน release” อย่างชัดเจน

## 3. Scope and Method

### 3.1 Included

- Flutter application under `lib/`;
- Flutter/Dart tests under `test/`;
- Drift schema, migrations, sync codecs and owner lifecycle manifests;
- Firebase/Firestore rules and emulator-backed tests;
- AI API, Voice API, LexiQuest LM and Hugging Face Space dependency locks/tests;
- production feature registry, feature delivery contract and composition root;
- screen inventory, route factory, navigation glossary and static reference reachability;
- 8/44 catalog and generated feature map;
- local secret and vulnerability scanning permitted by repository guardrails;
- existing development, release and field evidence documents.

### 3.2 Excluded

- production deployment, cloud mutation, signing or store submission;
- penetration testing against external systems;
- correction of pre-existing defects or dependency versions;
- Adventure production code;
- proof that a statically orphaned screen cannot be opened by every possible dynamic mechanism;
- field-device certification that requires hardware/model preparation.

### 3.3 Evidence classes

| Class | Meaning |
|---|---|
| Source fact | Directly observed in tracked source/configuration |
| Executed evidence | Command or test executed during this audit |
| Static signal | Search/reference result that requires runtime confirmation |
| Historical evidence | Existing document or generated artifact; freshness must be checked |
| Planned requirement | Adventure decision; not evidence that implementation exists |

## 4. Repository and Product Inventory

### 4.1 Scale

| Item | Observed value |
|---|---:|
| Repository files observed | approximately 1,203 |
| Git-tracked files | 1,221 |
| Dart source under `lib/` | approximately 495 |
| Feature-area Dart files | approximately 244 |
| Screen files | 63 |
| Flutter/Dart tests executed by full suite | 3,217 total outcomes: 3,202 pass, 15 fail |

Counts describe the audited checkout and are inventory aids, not contractual cardinalities except where explicitly frozen below.

### 4.2 Exact 8/44 catalog

The catalog is frozen at revision `1.3.0` with semantic hash:

`41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`

| Domain | IDs | Count |
|---|---|---:|
| C1 Learning Content and Packs | f01–f04 | 4 |
| C2 Unified Learning Experience | f05–f13 | 9 |
| C3 Recall, Feedback and Control | f14–f21 | 8 |
| C4 Review, Time and Assessment | f22–f28 | 7 |
| C5 Motivation and Engagement | f29–f34 | 6 |
| C6 Personalization and Accessibility | f35–f39 | 5 |
| C7 Local Reliability, Offline and Rollout | f40, f41, f44 | 3 |
| C8 Daily Continuity and History | f42, f43 | 2 |
| **Total** | **f01–f44** | **44** |

There are two experimental candidates outside the approved 8/44 catalog. They are not counted as current product capabilities.

### 4.3 Adventure catalog decision

Adventure must **not** become `f45`. It is a broad runtime delivery feature that maps existing capabilities into another presentation. Adding it to the 8/44 catalog would change the user-approved baseline, blur capability versus experience delivery, and make the generated contract cardinality misleading.

## 5. Runtime Delivery State

### 5.1 Exact runtime feature set

The current runtime feature enum has 19 values:

`vocabulary`, `quiz`, `srs`, `reading`, `mastery`, `weakness`, `ghostDuel`, `achievements`, `shop`, `objectScanner`, `speechPractice`, `aiTutor`, `export`, `shadowRewardV2`, `questV2`, `studyPlanning`, `researchAssessment`, `dailyContinuity`, `offlineContent`.

### 5.2 Production defaults

| State | Features |
|---|---|
| Enabled | vocabulary, quiz, srs, reading, mastery, weakness, ghostDuel, achievements, shop, export |
| Limited | objectScanner, speechPractice, aiTutor, questV2 |
| Hidden/default-off | shadowRewardV2, studyPlanning, researchAssessment, dailyContinuity, offlineContent |

### 5.3 What the user currently sees

The visible production shell emphasizes Vocabulary, Learn, Mastery, Weakness, Achievements and Profile. Today Hub, Study Planning, Assessment and Offline Content are composed or implemented but hidden by the current delivery contract.

This creates a product-communication gap:

- the source contains a richer 8/44 system than the visible first-level navigation communicates;
- completed features may appear absent to a user who cannot reach their parent entry;
- a new Adventure home could make this worse if it becomes another hidden or competing parent;
- therefore Adventure entry must be explicit, reversible and accompanied by Standard fallback.

### 5.4 Proposed runtime seam

The future runtime feature should be a new broad feature such as `Feature.adventureMotivation`, with:

- production default `hidden`;
- durable emergency-off control;
- one composed dependency/facade;
- no automatic enablement of child features;
- exact mapping to existing 8/44 capability IDs;
- updated registry cardinality, persisted names, generated feature map and architecture tests;
- dependency on a usable daily-continuity/Today Hub read path, while preserving Standard fallback.

This is a planned requirement, not current implementation.

## 6. Canonical Authorities and Data Flow

### 6.1 Authority matrix

| Fact | Current authority | Adventure permission |
|---|---|---|
| Vocabulary/category | existing vocabulary repositories/use cases | read/select only; writes use existing use cases |
| Learning session/answer | Unified Lesson Controller and learning repository | start/submit/finish through existing application ports only |
| Evidence | Evidence Gateway with strict `EvidenceContext` | no schema extension; no direct table write |
| SRS state/due work | existing SRS authority/projector | read due work and submit qualifying evidence only |
| Mastery/weakness | existing evidence-derived projectors | display projections only |
| Today work | Today Hub reader | transform read model into journey nodes only |
| Recommendation | existing recommendation authority | explain/present; never recompute canonically |
| Quest | existing quest repository/projector | display existing progress only |
| Streak | existing streak authority | calm display only; no punishment or parallel counter |
| XP/Coins/rewards | learning side-effect reconciler and reward authorities | consume committed outcome; never grant directly |
| Achievements | existing unlock authority | display unlocked state only |
| History/review | existing history and review readers | deep-link to canonical review/history |
| Consent | consent repository | read exact granted/withdrawn state; never infer |
| Experiment assignment | assignment repository | stable assignment; never overwrite on crossover |
| Learner preference | learner preference repository | planned v2 `home_experience`; separate from assignment |

### 6.2 Current committed learning flow

```text
Existing/Adventure presentation
        |
        v
Unified Lesson Controller
        |
        v
Evidence Gateway -> Learning Repository -> canonical attempt/event
        |
        +-> SRS / mastery / weakness / history projections
        |
        +-> LearningSideEffectReconciler
              +-> XP / Coins
              +-> Quest
              +-> Streak
              +-> Achievement / reward receipts
```

Adventure may add context around the session, but must not insert a second write path at any arrow.

### 6.3 Evidence contract constraint

`EvidenceContext` is schema v1 with an exact closed key set and strict length equality. Adding Adventure fields to it would invalidate the contract and risk rejecting existing evidence.

The approved design is:

- `AdventureOriginContextV1` exists only as transient application metadata;
- it is not serialized into `EvidenceContext`, answer payloads or `EventEnvelopeV2`;
- consented research measurement uses separate exposure events and never modifies learning evidence;
- the later ADR-003 decision assigns pre-session events to `AdventurePresentation/entryDecisionId` and mission events to `LearningSession/learningSessionId` with plan correlation when required;
- a nonparticipant receives no research exposure row.

### 6.4 Learning side effects

`LearningSideEffectReconciler` owns the post-evidence coordination of progress, rewards, quest and streak effects. Adventure must wait for or read its committed outcome. It must never award XP, Coins, quest credit, streak continuity or achievements directly, including after retries or resume.

## 7. Database, Lifecycle and Sync

### 7.1 Current database facts

| Item | Current value |
|---|---:|
| Drift schema version | 22 |
| Exact table count | 44 |
| Active schema ledger | v1–v22 |

The next migration number must be reserved in the schema ledger at implementation time. Planning labels v23/v24 are placeholders: if another approved change occupies them first, Adventure must rebase forward and never reuse a released number.

### 7.2 Owner lifecycle manifest

The lifecycle manifest covers all 44 current tables:

| Dimension | Count |
|---|---:|
| Direct owner authority | 34 |
| Transitive owner authority | 2 |
| Root | 1 |
| Global | 3 |
| Packaged content | 3 |
| Device-local | 1 |
| Delete direct | 34 |
| Delete transitive | 2 |
| Delete root | 1 |
| Delete owner metadata only | 1 |
| Preserve global | 6 |
| Physical deletion order | 38 |

Preserved resources are `content_manifests`, `learning_packs`, `learning_pack_items`, `content_download_states`, `model_downloads` and `quest_definitions`.

Any Adventure-owned durable table would therefore require simultaneous updates to:

- table inventory;
- migration matrix;
- lifecycle manifest and deletion order;
- owner export;
- local deletion;
- guest-to-account upgrade;
- sync policy and rules where applicable;
- retention and consent withdrawal behavior;
- exact contract tests.

This is one reason the MVP prohibits an `adventure_progress` table.

### 7.3 Current sync inventory

The exact sync collection set has 14 values:

`categories`, `words`, `attempts`, `readingEvents`, `rewardTransactions`, `srsStates`, `achievementUnlocks`, `experimentAssignments`, `assessmentRuns`, `savedLearningItems`, `contentQualityReports`, `learningTimeSegments`, `learningGoals`, `learnerPreferences`.

Learning time, goals, preferences and research sync are optional rollouts and are off by default in production. Supabase support is optional/no-op and is not on the learning critical path.

### 7.4 Learner preference limitation

Learner preference currently uses payload/preference version 1 and rules revision `learner-preference-v1-r1`. A durable `home_experience` value therefore cannot be added safely by changing only a local Dart model.

The safe staged design is:

1. **Prototype stage:** session-local choice; no schema or cloud sync;
2. **Durable local stage:** reserve migration, add preference v2 codec and migrate v1 without changing existing semantics;
3. **Cloud stage:** deploy/test exact preference v2 rules and enable optional sync only after version agreement;
4. **Fail-closed rule:** an unknown version or rules mismatch preserves Standard and does not silently rewrite the preference.

## 8. Research, Consent and Measurement

Research providers currently fail closed. Feature availability, learner preference, experiment assignment and consent are separate states and must remain separate.

Required Adventure measurement rules:

- no research row for nonparticipants;
- assignment is stable and is never changed because a participant switches to Standard;
- switching presentation during treatment becomes a crossover/exposure event;
- consent withdrawal immediately stops new measurement writes;
- deletion/export/retention behavior is declared before the first durable measurement table;
- learning evidence remains valid and separate from research exposure;
- product analytics must not be presented as learning outcome;
- motivation outcome must be measured with declared constructs, not inferred only from XP, streak or time-on-task.

## 9. Screen and Route Reachability

### 9.1 Evidence freshness

The historical runtime ledger dated 2026-08-09 covers 49 screens, while the current `lib/screens` contains 63 screen files. The ledger is therefore not authoritative for current reachability and must be regenerated or replaced before Adventure navigation work.

### 9.2 Static orphan candidates

Static class-reference inspection found no caller outside the defining file for these 11 current screen candidates:

1. `CefrDiagnosticTestScreen`
2. `GameLauncherScreen`
3. `GeminiSettingsScreen`
4. `LearningWorldMapScreen`
5. `PhoneticExplorerScreen`
6. `ResultScreen`
7. `SelectCategoryForQuiz`
8. `SelectWallpaperScreen`
9. `SmartAudioPlaylistScreen`
10. `ThesisChartScreen`
11. `WordbookImportScreen`

This is a static signal, not proof of runtime impossibility. The current named route factory directly covers login, register, home and email-action paths; typed navigation may cover additional screens. Every candidate must be classified as production, internal, prototype, deprecated or dynamically reached before deletion or reuse.

### 9.3 Adventure consequence

`LearningWorldMapScreen` must not be used as the Adventure foundation merely because its name resembles the new concept. It is currently a screen-owned/static candidate without a proven caller or canonical journey authority. Adventure needs a new read-only projection and typed entry contract, with any reusable visuals extracted only after ownership review.

## 10. Verification Evidence

### 10.1 Passed checks

| Check | Result |
|---|---|
| Generated 8/44 feature map `--check` | PASS |
| `flutter analyze --no-pub lib` | PASS — no issues |
| `flutter analyze --no-pub lib test` | No errors/warnings; 3 info-level deprecated test APIs |
| 8/44 architecture catalog tests | 13/13 PASS |
| Targeted authority/integration group | 302 PASS |
| Full Flutter suite, default concurrency | 3,202 PASS / 15 FAIL |
| Full Flutter suite, `--concurrency=1` | 3,202 PASS / 15 FAIL in 10m33s |
| Runtime tests isolated | 176 PASS |
| Feature tests isolated | 1,566 PASS / 3 FAIL |
| AI API backend | 76 PASS |
| Voice API backend | 55 PASS / 1 opt-in external E2E SKIP |
| LexiQuest LM backend | 75 PASS |
| Firestore Rules emulator | 84 PASS / 0 FAIL |
| Firebase Auth emulator | 3 PASS / 0 FAIL |
| HF Space requirement vulnerability scan | no finding |

The full-suite figures are reproducible under both normal and serial execution. This rules out a simple concurrency-only count inflation.

### 10.2 Exact 15 Flutter failures

| ID | Area | Count | Root cause classification | Adventure consequence |
|---|---|---:|---|---|
| BL-01 | final 8/44 plan fingerprint | 1 | generated/historical test-plan hash for `android/app/build.gradle.kts` is stale | regenerate and re-review baseline evidence before claiming sign-off |
| BL-02 | iOS notification contract | 1 | tracked `ios/Podfile` is absent while test requires iOS 13 CocoaPods contract | release blocker for iOS; resolve platform intent before Adventure Pilot |
| BL-03 | LiteRT benchmark | 1 | field model fixture not prepared | environment/certification prerequisite, not learning-core failure |
| BL-04 | LiteRT classifier | 2 | checksum-pinned model and `build/model-fixtures/mobilenet.tflite` absent | prepare via approved model workflow before device-model certification |
| BL-05 | historical schema audit | 1 | Phase -1 test hard-codes schema v11 while current schema is v22 | stale test/evidence must be retired or versioned |
| BL-06 | ambiguous `points` guard | 1 | regex flags drawing coordinates in handwriting scratchpad | narrow semantic guard; current matches are not reward authority duplication |
| BL-07 | scenario bootstrap/path provider | 7 | missing test binding or mocked `getApplicationSupportDirectory` after offline manager composition | fix test harness/application-support injection before Adventure bootstrap scenarios |
| BL-08 | associative reading screen copy | 1 | test expects obsolete English `Associative Reading`; current glossary uses Thai `อ่านเชื่อมโยงความจำ` | align test to stable navigation identity, not fragile display copy |
| **Total** |  | **15** |  |  |

The seven BL-07 cases are:

- two cases in `ai_voice_fallback_journey_test.dart`;
- three cases in `associative_reading_restart_test.dart`;
- one case in `current_activity_evidence_bootstrap_test.dart`;
- one case in `production_vocabulary_restart_test.dart`.

### 10.3 Test hygiene observations

- Several tests create more than one Drift `AppDatabase` over a shared executor and emit a non-failing race/corruption warning. The tests should use isolated executors or explicitly justified suppression.
- Three info-level deprecations in `main_navigation_screen_test.dart` use `hasFlag`/`pipelineOwner` APIs that should be migrated before the SDK removes them.
- The test worktree initially lacked its own `.dart_tool/package_config.json`; Dart resolved package imports through the parent checkout. `flutter pub get --offline` restored a worktree-local package configuration. Reproducible setup must include this step or an equivalent immutable bootstrap.

## 11. Secret and Dependency Findings

### 11.1 Gitleaks

The history scan covered 705 commits and reported 15 `generic-api-key` findings, all in test fixture files:

| File | Findings |
|---|---:|
| `test/features/learning/drift_learning_event_store_test.dart` | 1 |
| `test/features/sync/firestore_sync_gateway_test.dart` | 8 |
| `test/features/sync/reward_transaction_sync_test.dart` | 6 |

Line-level inspection indicates test variables such as tokens, owner-gate tokens and idempotency keys rather than confirmed live credentials. Nevertheless, the current Gitleaks gate exits nonzero. Until the fixtures are safely replaced or narrowly allowlisted with reviewed fingerprints, this is release-blocking policy debt. Secret literal values must never be copied into planning documents.

The initial directory scan also traversed a generated `.venv` and inflated findings. Future scans must exclude generated environments while still scanning tracked source and history.

### 11.2 OSV/dependency results

| Lock/source | Result | Decision |
|---|---|---|
| `pubspec.lock` | no issue | pass |
| root `package-lock.json` | no unignored issue; one `uuid` issue is under a time-bounded policy until 2026-10-26 | monitor policy expiry |
| AI API lock | no issue | pass |
| Voice API lock | 8 known issues filtered by explicit optional Torch/OmniVoice GPU research policy | feature remains release-blocked; do not treat filter as remediation |
| LexiQuest LM lock | `datasets 5.0.0`, `PYSEC-2026-3716`, CVSS 6.9 Medium; fixed in 5.0.1 | update/verify before release of affected tooling |
| HF Space requirements | no issue | pass |

These findings are independent of Adventure, but Adventure must not be used to justify bypassing them.

## 12. Documentation and Release Evidence Freshness

| Evidence | Finding |
|---|---|
| Final 8/44 verification document | records local source closure but field/release state is not ready; no cloud deployment or release signing evidence |
| Generated final test plan | input fingerprint no longer matches current Android build file |
| Runtime feature ledger | stale: 49 recorded screens versus 63 current files |
| README | does not fully describe current 8/44 runtime and contains stale voice telemetry wording |
| Historical schema Phase -1 checks | hard-code schema v11 while runtime is v22 |

Historical evidence may explain decisions but must not be used as current pass evidence without regeneration.

## 13. Adventure Impact Matrix

| Existing subsystem | Intended Adventure use | Forbidden impact | Required gate |
|---|---|---|---|
| Production feature registry | one hidden broad parent and kill switch | changing 44 capability count or enabling children | exact registry/cardinality tests |
| Today Hub | source for today journey nodes and Standard fallback | copying/recomputing canonical priorities | Today read-model contract tests |
| Unified Lesson Shell | run existing learning modes | Adventure-owned answer semantics | equivalence tests per mode |
| Evidence Gateway | commit answers | adding origin fields to strict context | schema/closed-key tests |
| SRS | choose due work and schedule later review | separate retry queue or due date | wrong-answer/resume integration tests |
| Progress/Mastery/Weakness | read projections | `adventure_progress` or duplicate mastery | no-new-authority architecture test |
| Quest/Streak/XP/Coins | show existing outcomes | direct grant, penalty or double credit | idempotent side-effect tests |
| Achievements/Shop/Avatar | show owned cosmetics/reactions | new economy or inventory | reward receipt and owner tests |
| Learner preferences | future `home_experience` | mixing with experiment assignment | preference v2 migration/sync/rules tests |
| Research assignment/consent | treatment and measurement eligibility | rows for nonparticipants or assignment rewrite | consent/withdrawal/isolation tests |
| Owner lifecycle | export/delete/upgrade new data | orphan measurement rows | manifest/export/delete/upgrade matrix |
| Offline content | local world asset availability | making learning unavailable because art is missing | placeholder and Standard fallback tests |
| Navigation glossary | stable Thai identity and semantics | copy-bound test selectors | key/semantic navigation tests |

## 14. Risk Register

| Risk ID | Severity | Risk | Owner | Required response |
|---|---|---|---|---|
| R-01 | High | Adventure duplicates learning/reward authority | Tech Lead | facade/read-only projection; architecture fitness tests |
| R-02 | High | Today Hub remains hidden or unavailable, leaving Adventure without a stable work source | Product + Tech Lead | decide delivery relationship and pass fallback tests before shell activation |
| R-03 | High | preference v2 is persisted locally before sync/rules support exists | Data/Sync Owner | staged rollout and exact version negotiation |
| R-04 | High | research exposure leaks to nonparticipants | Research + Privacy Owner | fail-closed eligibility and zero-row isolation tests |
| R-05 | High | baseline/release evidence falsely reported as clean | QA Lead | close 15 Flutter failures and regenerate evidence |
| R-06 | High | secret-scanning policy gate remains red | Security/QA Owner | review and remediate/allowlist fixtures without exposing literals |
| R-07 | High | missing iOS Podfile invalidates iOS notification/release contract | Mobile Platform Owner | restore/replace contract and test on supported iOS pipeline |
| R-08 | Medium | missing/corrupt world assets make learning unreachable | Adventure Owner | placeholders, cached manifest validation and Standard fallback |
| R-09 | Medium | old screens are accidentally reused as authorities | UX + Tech Lead | screen disposition ledger before implementation |
| R-10 | Medium | motivation design becomes pressure through streak/timer/lives | Product/Research | support-first copy, no punishment, qualitative UAT |
| R-11 | Medium | result screen conflates learning, effort and engagement | UX/Data | separate axes and measurement labels |
| R-12 | Medium | database/lifecycle work misses one exact inventory | Data Owner | generated exact-set tests and migration matrix |
| R-13 | Medium | Drift test warnings hide real executor-sharing defects | QA/Data Owner | isolate test databases and keep warnings actionable |
| R-14 | Medium | dependency policy exceptions expire or remain release-blocked | Backend/ML Owners | upgrade or reapprove with documented boundary before release |

## 15. Gate Classification

### 15.1 Must close before Adventure production-code implementation

1. Approve this audit and the authority matrix.
2. Refresh the screen/route disposition ledger.
3. Resolve BL-05 and BL-06 so historical tests no longer assert false current contracts.
4. Resolve BL-07 because Adventure bootstrap/restart tests will share the same composition seam.
5. Define and test the new runtime feature contract as hidden/default-off.
6. Freeze Standard fallback behavior and Today Hub dependency behavior.
7. Reserve actual schema numbers only when the implementation branch starts.

### 15.2 May be deferred during read-only prototype, but must close before internal build sign-off

1. BL-08 navigation-copy test alignment.
2. Worktree bootstrap/runbook and package configuration reproducibility.
3. Updated README and current runtime feature ledger.
4. Drift multiple-database test warnings in touched areas.
5. Deprecated Flutter test APIs in touched navigation tests.

### 15.3 Must close before Android Pilot v1

1. Logical/shared Flutter suite และ touched Adventure scope มี fresh passing evidence โดยไม่มี unclassified failure; field-model tests ต้องถูกแยกเป็น explicit excluded hardware gate และห้ามรายงานว่า passed.
2. Preference v2 local migration, codec, rules and sync compatibility complete if durable choice is included.
3. Measurement lifecycle, consent withdrawal, export/deletion and retention tests green.
4. Accessibility, reduced motion, 200% text and screen-reader UAT complete.
5. Offline, corrupt-asset, emergency-off and Standard fallback rehearsals complete.
6. Pilot protocol, MDS sample calculation, stopping rule and crossover analysis approved.
7. Android device matrix ผ่านครบ; iOS, desktop, AI Voice และ field model ระบุเป็น excluded พร้อม gate ก่อน enable ของตนเอง.

### 15.4 Must close before production release

1. BL-01 and BL-02 resolved and current platform evidence regenerated.
2. Gitleaks gate clean under reviewed policy.
3. LexiQuest LM vulnerability upgraded/contained and verified.
4. Voice optional GPU research dependency release block resolved for any released affected component.
5. Cloud configuration, rules deployment, signing, device certification and rollback evidence attached.
6. No open Critical/High defect and no unapproved Medium defect affecting data, consent or accessibility.

## 16. Non-Regression Contract for Adventure

Adventure implementation is acceptable only if all statements remain true:

1. Turning Adventure off restores baseline navigation and behavior without data repair.
2. Standard is always reachable in at most two intentional actions from Adventure home.
3. A given answer produces the same canonical learning evidence in Standard and Adventure.
4. A retry or app restart cannot double-grant XP, Coins, quest credit, streak or achievement.
5. Wrong answers do not reduce existing progress or access.
6. Missing story/art assets do not block learning.
7. No Adventure field is added to strict learning evidence contracts.
8. No nonparticipant research row is created.
9. Guest upgrade, export and deletion cover every new owner-scoped row.
10. The approved 8/44 catalog remains exactly 44 capabilities.

## 17. Audit Conclusion

The current system has a strong local-first authority foundation suitable for an optional Adventure presentation. The safest direction is to build Adventure as a projection of Today Hub and existing learning/reward outcomes, with a new hidden runtime parent and no new progress authority.

The baseline is **not release-clean**. The 15 Flutter failures are reproducible and mostly indicate stale contracts, missing test/platform prerequisites and test harness gaps rather than broad learning-core failure. Secret/dependency and evidence-freshness issues add independent release blockers. ADR-005 เปลี่ยนเฉพาะการจัดกลุ่ม gate ตาม capability: finding ที่อยู่นอก Android Pilot ไม่หายไปและไม่ถือว่าผ่าน แต่ไม่บล็อก Pilot path ที่ไม่เรียกใช้ capability นั้นเมื่อมี explicit exclusion และ owner approval.

Accordingly:

- documentation, wireframes and a non-persistent prototype may proceed;
- hidden implementation may proceed only after the “before implementation” gates are closed;
- Pilot/production enablement is prohibited until its corresponding gates have fresh evidence.

## 18. Sign-off

| Role | Name | Decision | Date | Notes |
|---|---|---|---|---|
| Product Owner |  | Approve / Revise / Reject |  |  |
| CTO/Tech Lead |  | Approve / Revise / Reject |  |  |
| QA Lead |  | Approve / Revise / Reject |  |  |
| Data/Privacy Owner |  | Approve / Revise / Reject |  |  |
| Research Owner |  | Approve / Revise / Reject |  |  |
