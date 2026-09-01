# Test Plan and Test Cases — Adventure Motivation Mode

**Document ID:** LQ-AMM-TP-001
**Version:** 1.0
**Status:** Draft for QA/Owner Review
**Date:** 2026-09-01
**References:** `AMM-AUDIT-001`, TOR/SRS/SDS/UI/ADR/MDS/RTM v1.0
**Baseline:** commit `99f7fb21`, Drift schema v22
**Current baseline evidence:** 3,202 Flutter tests pass / 15 fail; no Pilot or release pass claim is permitted

## 1. Test Objectives

The test program proves that Adventure:

1. is optional, hidden by default and removable through emergency-off;
2. preserves the exact 8/44 capability catalog;
3. reads Today/learning/reward authorities without creating parallel state;
4. produces the same canonical learning evidence as Standard;
5. handles wrong answers, retry, restart and failure without punishment or duplication;
6. separates product preference, feature state, assignment and consent;
7. creates research data only for eligible consented runs;
8. supports owner isolation, guest upgrade, sync, export, withdrawal and deletion;
9. remains usable offline and when Adventure assets/dependencies fail;
10. meets accessibility, performance, privacy and rollout gates.
11. adds only `learn/today-experience` within Learn, never a bottom tab, and leaves hidden Learn layout equivalent;
12. keeps Product Entry independent from Research Capture and applies lifecycle-correct exposure IDs.

## 2. Scope

### 2.1 In scope

- M01–M11;
- new runtime feature and exact production contract;
- world/story/asset catalog and journey projection;
- session composer and Unified Lesson bridge;
- canonical side-effect receipt projection;
- scripted companion and result/recovery;
- preference v2 and planned research migrations on actual reserved schema numbers;
- sync/rules/lifecycle/export/deletion;
- Thai/English UI, map/list parity and accessibility;
- offline/restart/emergency-off/platform/device behavior;
- research exposure, prompt, crossover and measurement data quality;
- regression against Standard and all 8/44 authorities.

### 2.2 Out of scope for v1

- AI-generated story/companion copy;
- camera quest, multiplayer, leaderboard or social features;
- hearts/lives/energy/new economy;
- durable branching story;
- proving effectiveness before a protocol-approved Pilot;
- external provider E2E that requires credentials unless executed in its separately approved gate.
- iOS/desktop/AI Voice/field-model certification in Pilot v1; each remains excluded, not passed, and requires its own gate before enablement.

## 3. Test Strategy

| Layer | Purpose | Primary tools/evidence |
|---|---|---|
| Static/contract | exact enums, imports, keysets, no duplicate authority | Dart architecture tests, generated feature map |
| Domain unit | validation, deterministic selection, state machines | `flutter test` pure tests |
| Application unit | use cases and failure mapping | fakes, clocks, deterministic IDs |
| Repository/migration | schema preservation, identity, lifecycle | in-memory/file-backed Drift fixtures |
| Widget | rendering, semantics, focus, states | `testWidgets`, golden where stable |
| Integration | existing ports and canonical equivalence | real repositories with isolated DB |
| Scenario/restart | file reopen, offline, owner switch, kill switch | file-backed database, fake platform ports |
| Cloud policy | owner/version/consent rules | Firestore/Auth emulators |
| Backend | API/research processing regressions | backend pytest suites |
| Security/dependency | secrets, vulnerable dependencies, diff | Gitleaks, OSV, dependency audits |
| Manual/device | screen reader, hardware, rendering, platform lifecycle | certified device matrix |
| UAT | user comprehension and business acceptance | scripted evidence and sign-off |

## 4. Test Environments

| Environment | Purpose | Data/network | Feature state |
|---|---|---|---|
| E0 Baseline worktree | reproduce current product | fixture/local; no Adventure code | absent |
| E1 Unit | deterministic logic | fake clock/IDs/readers | explicit per test |
| E2 Widget | UI/semantics | fake dependencies | hidden/internal/error states |
| E3 Local integration | Drift/outbox/restart | in-memory and temp file | hidden/internal |
| E4 Emulator | Auth/Firestore rules/sync | local emulators | internal/research fixtures |
| E5 Internal build | device/accessibility/offline | local plus controlled network | staff-only |
| E6 Android Pilot v1 | approved participants on MDS Android matrix only | production-like approved services | Pilot assignment/consent |
| E7 Android release candidate | signed/profile builds | production config, no test secrets | controlled enablement |

### 4.1 Reproducible worktree setup

1. Create isolated branch/worktree from the approved baseline.
2. Run approved offline dependency bootstrap so the worktree has its own `.dart_tool/package_config.json`.
3. Verify package roots resolve inside the worktree.
4. Run generated 8/44 feature map check.
5. Record Flutter/Dart/Java/Gradle/platform versions.
6. Record feature contract, catalog, schema and rules revisions.
7. Keep generated setup changes out of the production diff unless explicitly required.

## 5. Test Data Design

### 5.1 Owners

- O-GUEST-A: active guest with local data;
- O-GUEST-B: unrelated guest;
- O-ACCOUNT-A: target account for upgrade;
- O-ACCOUNT-B: foreign account;
- O-PARTICIPANT: consented assigned owner;
- O-NONPARTICIPANT: product user without research eligibility;
- O-WITHDRAWN: previously consented, now withdrawn.

### 5.2 Learning data

- due SRS work: 0, 1, 3, 8 and >session limit;
- new content: verified and missing revisions;
- saved item, weakness and recommendation combinations;
- accepted session in active, pending-evidence, completed and abandoned states;
- correct independent, correct guided, incorrect, skip and technical failure evidence;
- fewer than 3 and at least 5 eligible intervening items;
- assessment and recreational evidence that must remain reward-ineligible.

### 5.3 World/catalog data

- valid v1 world with three visible nodes and Thai/English keys;
- missing locale, duplicate ID, cyclic graph, unknown state, unsafe asset path;
- valid/invalid checksum;
- missing, corrupt, quarantined and repaired asset bundle.

### 5.4 Research data

- matching/nonmatching assignment and protocol;
- current/stale/withdrawn consent receipt;
- started/completed/skipped/abandoned/withdrawn run;
- supported/unknown instrument and response codes;
- crossover from Adventure to Standard;
- v1/v2/incompatible sync payloads.

## 6. Entry and Exit Criteria

### 6.1 Entry to implementation testing

- approved TOR/SRS/SDS/UI/ADR/MDS/Test/RTM;
- Audit before-implementation findings closed;
- current screen/route ledger approved;
- exact migration numbers reserved when schema work begins;
- test fixtures and reviewer assigned;
- no unclassified baseline failure in the touched foundation.

### 6.2 Exit for hidden/internal

- all P0–P3 required tests pass;
- feature-off equivalence passes;
- no direct Adventure grant/progress/evidence mutation path;
- Standard fallback passes every failure state;
- no Blocker/Critical/High defect in the internal path;
- targeted accessibility and restart checks pass.

### 6.2A Exit for Product Core MVP / MS-04

- Increment A/B cases for Learn entry, projection, canonical learning bridge, repair, result, restart and emergency-off pass;
- Standard and Adventure produce byte/value-equivalent canonical commands and evidence for the controlled fixtures;
- duplicate canonical evidence/reward count = 0 and schema remains v22;
- no preference or research migration exists in the Product Core MVP diff;
- Product Owner records one explicit decision: `Accept`, `Stop` or `Continue`;
- `Stop` is accepted as a complete bounded outcome: feature remains hidden, evidence is archived and no Increment C/D work is required.

### 6.3 Exit for Pilot

- all applicable automated cases below pass;
- full logical/shared Flutter suite has fresh passing evidence and zero unclassified failure;
- Android Pilot capability gates and affected backend/emulator/security/dependency scopes meet policy;
- iOS/desktop/AI Voice/field-model exclusions are recorded as excluded, not passed;
- lifecycle/export/delete/withdrawal matrix passes;
- accessibility manual certification passes;
- emergency-off rehearsal passes;
- UAT uses ≥12 learner representatives, ≥4 accessibility sessions and ≥10 research-comprehension participants with MDS numerator/denominator thresholds;
- protocol/ethics/consent/MDS sample-size inputs, output and stopping rules approved.

### 6.4 Exit for production

- Pilot decision approves controlled expansion;
- no open Blocker/Critical/High; Medium risks approved with owner/date;
- Gitleaks and dependency policies pass;
- platform signing/device evidence current;
- rollback and monitoring rehearsed;
- as-built SDS/RTM/test report signed.

## 7. Baseline and Regression Gates

| Gate ID | Check | Pass condition |
|---|---|---|
| BG-01 | 8/44 generated feature map | revision/hash exact and 44 capabilities |
| BG-02 | Flutter analysis | no error/warning in production; test info dispositioned |
| BG-03 | Full Flutter inventory suite | complete run archived; logical/shared/touched set passes; every remaining failure maps to approved explicit exclusion; zero unclassified failure |
| BG-04 | Targeted authority suite | evidence/SRS/progress/reward/Today/lifecycle green |
| BG-05 | Backend suites | Android Pilot-reachable and shared services green; AI/Voice excluded unless reachable; exclusions declared |
| BG-06 | Emulator policy | Firestore/Auth exact suites green |
| BG-07 | Gitleaks | nonzero result prohibited unless reviewed narrow policy yields clean gate |
| BG-08 | OSV/dependencies | no unapproved or expired finding in release scope |
| BG-09 | Platform contracts | Android Pilot contract green; iOS/desktop remain blocked until their enablement gate |
| BG-10 | Field model | excluded from Pilot v1; required and certified only before a reachable model capability is enabled |
| BG-11 | Focused diff | no unrelated/generated/native registrar drift |
| BG-12 | Feature-off comparison | Standard fixture outputs/evidence equivalent |

## 8. Detailed Test Cases

Controlled inventory รวม **114 test cases**: ENT/JRN อย่างละ 12 และ LRN/REC/DAT/RSH/UX/OPS อย่างละ 15 ทุกกรณียังมีสถานะ planned จนกว่าจะมี implementation และ fresh execution evidence

In every case, “no write” means no new/changed row in learning, SRS, progress, quest, streak, reward, achievement, research or preference authorities unless the case explicitly requires it.

### 8.1 Delivery, entry and fallback

| ID | Preconditions | Action | Expected result |
|---|---|---|---|
| TC-ENT-001 | Adventure absent/hidden | Open Learn | Learn layout/action set equals baseline; no card/bottom-tab/write |
| TC-ENT-002 | Adventure visible but disabled; Today ready | Open direct/stale `learn/today-experience` | Host resolves Standard; bounded reason; Back returns Learn |
| TC-ENT-003 | Enabled, Today dependency missing | Open Learn/direct route | No card; stale route returns Learn; Adventure subtree not constructed |
| TC-ENT-004 | Enabled, all dependencies ready, session-local choice Adventure | Open Learn card | Host loads one canonical Today snapshot and Adventure Home |
| TC-ENT-005 | Same as 004, choice Standard | Open Learn card | Standard Today presentation loads; assignment unchanged |
| TC-ENT-006 | Unknown/corrupt persisted feature state | Restart/open Learn/direct route | Fail closed to Standard if Today ready, else Learn; config preserved |
| TC-ENT-007 | Existing emergency-off override | Open Adventure route | No new Adventure operation; Standard shown |
| TC-ENT-008 | Emergency-off toggled while Home open | Tap mission after toggle | Start rejected; safe Standard action |
| TC-ENT-009 | Emergency-off toggled after accepted session | Continue/finish | Existing lifecycle safely closes; no evidence loss; new mission blocked |
| TC-ENT-010 | Participant assigned Adventure, preference Standard | Open Learn card | Standard presentation; assignment remains Adventure; consented crossover only if Research Capture eligible |
| TC-ENT-011 | Nonparticipant uses Adventure product mode | Open/complete mission | Product works; zero research rows/events |
| TC-ENT-012 | Owner switches while entry resolution awaits | Complete stale async result | Stale owner result discarded; no mixed-owner UI/write |

### 8.2 World catalog, assets and journey projection

| ID | Preconditions | Action | Expected result |
|---|---|---|---|
| TC-JRN-001 | Valid catalog and fixed Today snapshot | Compose twice | Byte/value-equivalent node order/state/reasons |
| TC-JRN-002 | Same data inserted in different DB order | Compose | Same projection as canonical order fixture |
| TC-JRN-003 | Active accepted session exists | Compose | Resume node is primary; no new mission offered first |
| TC-JRN-004 | Due review and new work exist | Compose | Existing policy priority preserved; Adventure does not override |
| TC-JRN-005 | Completed canonical work | Recompose | Node derives completed; no Adventure progress write |
| TC-JRN-006 | Stale source fingerprint | Tap current node | Start disabled; refresh/Standard available |
| TC-JRN-007 | Duplicate node ID | Validate catalog | Whole bundle rejected/quarantined |
| TC-JRN-008 | Cyclic/unreachable graph | Validate catalog | Rejected with bounded diagnostic; Standard available |
| TC-JRN-009 | Thai or English key missing | Validate catalog | Bundle invalid before Pilot |
| TC-JRN-010 | Asset checksum mismatch | Open Adventure | Bundle quarantined; no learning data deleted; repair/Standard offered |
| TC-JRN-011 | Asset missing offline | Open Adventure | No retry loop; immediate Standard fallback |
| TC-JRN-012 | Asset repaired | Verify/reopen | Valid catalog becomes available without changing canonical progress |

### 8.3 Session composition and learning equivalence

| ID | Preconditions | Action | Expected result |
|---|---|---|---|
| TC-LRN-001 | Same owner/work/config in Standard and Adventure | Compose start commands | Canonical work IDs/revisions/modes/policy equal |
| TC-LRN-002 | Adventure plan valid | Start mission | Existing `UnifiedLessonController` accepts one session |
| TC-LRN-003 | Double-tap Start | Tap rapidly | One accepted session; CTA single-flight |
| TC-LRN-004 | Mixed-owner plan | Start | Rejected before any write |
| TC-LRN-005 | Stale incompatible content revision | Start | Rejected/refresh; no fallback to unpinned content |
| TC-LRN-006 | Valid transient origin | Serialize learning answer/evidence | Exact Standard payload/keyset; no Adventure field |
| TC-LRN-007 | Correct independent response | Submit | One canonical evidence identity and existing semantics |
| TC-LRN-008 | Correct guided/hint response | Submit | Guided evidence preserved; no independent-recall claim |
| TC-LRN-009 | Incorrect response | Submit | Incorrect evidence commits before feedback; no penalty |
| TC-LRN-010 | Skip | Submit/skip | Typed skip state, no false incorrect/technical state |
| TC-LRN-011 | Evidence local write fails | Submit | Completion/reward frozen; exact captured identity retained |
| TC-LRN-012 | Retry after failure | Retry | Same identity/payload commits once |
| TC-LRN-013 | App terminates after evidence commit before acknowledgement | Reopen/replay | Idempotent receipt; no duplicate answer/side effect |
| TC-LRN-014 | Assessment session | Attempt to wrap as mission | Reward-granting wrapper rejected; assessment isolation preserved |
| TC-LRN-015 | Adventure context absent | Run Standard fixture after Adventure code ships | Same Standard evidence and behavior |

### 8.4 Wrong answer, repair, result and motivation projection

| ID | Preconditions | Action | Expected result |
|---|---|---|---|
| TC-REC-001 | Incorrect with ≥5 eligible later items | Continue | Item returns once after 3–5 intervening items |
| TC-REC-002 | Incorrect with 0–2 later items | Finish | No padding; need delegated to Review/SRS |
| TC-REC-003 | Repair answer correct | Submit | Existing evidence semantics; no extra Adventure reward |
| TC-REC-004 | Repair answer incorrect | Submit | No second repair round; Review/SRS owns future schedule |
| TC-REC-005 | Two wrong items | Continue | Each has independent bounded repair identity/order |
| TC-REC-006 | Technical failure | Continue/retry | Not counted as incorrect; no penalty/shame copy |
| TC-REC-007 | Learning committed, canonical side effects pending | Open Result | Learning shown; reward pending; no grant call from Adventure |
| TC-REC-008 | Canonical receipts committed | Refresh Result | Exact Quest/Streak/Achievement/Reward projection shown |
| TC-REC-009 | Replay same evidence/result | Restart/refresh | No duplicate XP, Coins, quest, streak or unlock |
| TC-REC-010 | Open map/story only | Exit | No XP/Coin/quest/reward mutation |
| TC-REC-011 | Cosmetic purchase/equip exists | Show companion | Reads ownership; lifetime XP unchanged |
| TC-REC-012 | Result fixture | Render | Learning, Effort, Engagement are separate; no combined score |
| TC-REC-013 | Wrong-answer result | Inspect | “needs review” shown without reducing completed prior state |
| TC-REC-014 | Existing review due after session | Tap next action | Routes to canonical Review/SRS, not Adventure queue |
| TC-REC-015 | Accepted session plus owner logout | Execute safe lifecycle | Source owner session closed/retired; target owner receives no row |

### 8.5 Preference, schema and lifecycle

| ID | Preconditions | Action | Expected result |
|---|---|---|---|
| TC-DAT-001 | Phase 1 read-only code | Compare schema/table set | Still v22/44 tables; zero schema diff |
| TC-DAT-002 | Ledger v23 free | Reserve preference migration | One immutable ledger reservation |
| TC-DAT-003 | Planned number occupied | Start migration work | Rebase to next number; no reuse/edit of released migration |
| TC-DAT-004 | Frozen v22 owner preferences | Upgrade to preference v2 | All v1 fields preserved; home experience Standard |
| TC-DAT-005 | New v2 preference | Save Adventure | Owner-scoped use case commits exact supported value |
| TC-DAT-006 | Unknown local value | Read | Effective Standard + diagnostic; original not silently overwritten |
| TC-DAT-007 | Unknown cloud payload/version | Pull | Reject/quarantine; local compatible row preserved |
| TC-DAT-008 | Old v1 client mutation after cutoff | Sync | Cannot overwrite newer v2 state |
| TC-DAT-009 | Guest with Adventure preference | Upgrade to account | Preference moves/merges by declared conflict policy once |
| TC-DAT-010 | Foreign owner exists | Export/delete owner A | Owner B byte/value-equivalent |
| TC-DAT-011 | Research tables added | Inspect exact inventory | Each appears once in schema/lifecycle/export/delete/upgrade plan |
| TC-DAT-012 | Delete owner with research rows | Execute deletion | Rows removed in declared order; global content preserved |
| TC-DAT-013 | Export owner | Inspect archive | Preference and research axes complete, bounded and owner-only |
| TC-DAT-014 | Sync lost acknowledgement | Restart/replay | Same operation identity; no duplicate research response |
| TC-DAT-015 | Forward-only feature rollback | Disable Adventure after migration | App uses Standard; no destructive down migration |

### 8.6 Research, consent and data quality

| ID | Preconditions | Action | Expected result |
|---|---|---|---|
| TC-RSH-001 | No research consent | Use Adventure | Zero measurement/exposure row/outbox |
| TC-RSH-002 | Consent granted but no assignment | Use Adventure | Zero research row; product continues |
| TC-RSH-003 | Assignment exists but consent missing | Use Adventure | Zero research row; assignment unchanged |
| TC-RSH-004 | Matching assignment/consent/active run | Open host before plan, then start mission | `AdventurePresented` uses entryDecisionId/optional correlation; `AdventureMissionStarted` uses learningSessionId/required planId |
| TC-RSH-005 | Nonparticipant completes mission | Complete | No persisted origin/exposure row |
| TC-RSH-006 | Participant switches Standard before or after plan | Switch | Assignment unchanged; presentation aggregate uses entryDecisionId and plan correlation only when available |
| TC-RSH-007 | Participant switches repeatedly/replays | Switch/replay >10 attempts | Deterministic occurrence keys, bounded ordinal 1–10, no duplicate/cohort rewrite |
| TC-RSH-008 | Consent withdrawn before enqueue | Trigger event | No new local row/outbox/upload |
| TC-RSH-009 | Withdrawal while prompt open | Submit | Rejected safely; learning result unaffected |
| TC-RSH-010 | Prompt at non-natural breakpoint | Attempt render | Prompt suppressed/deferred |
| TC-RSH-011 | Prompt valid | Tap Skip | Run becomes skipped per protocol; no reward/access change |
| TC-RSH-012 | Unknown response code/free text attempt | Submit | Rejected before persistence |
| TC-RSH-013 | Valid bounded response | Submit twice | One response per owner/run/item |
| TC-RSH-014 | Export research data | Inspect | Outcome/Learning/Effort/Engagement/Motivation separated with version pins |
| TC-RSH-015 | Analysis fixture with crossover | Reconstruct | ITT assignment preserved; adherence/crossover secondary metadata complete |

### 8.7 UI, copy and accessibility

| ID | Preconditions | Action | Expected result |
|---|---|---|---|
| TC-UX-001 | Learn + Adventure Home | Inspect navigation/first viewport | No new bottom tab; one eligible Learn card; one primary mission; Standard visible |
| TC-UX-002 | Map snapshot | Toggle List | Identical nodes, order, states and actions |
| TC-UX-003 | Screen reader | Traverse Home | Primary mission/Standard reachable; decoration excluded |
| TC-UX-004 | Keyboard-supported device | Traverse sheet/map/list | Logical order, no trap, focus restored |
| TC-UX-005 | Text scale 200% narrow phone | Render required screens | No clipped essential text/CTA; reflow/list-first |
| TC-UX-006 | Dark theme | Render all states | Readable and derived from M3 color scheme |
| TC-UX-007 | High contrast | Render node states | Icon/text/shape distinguish states; contrast passes |
| TC-UX-008 | Reduced motion | Trigger transitions/reaction | Zero-duration/static equivalent; no essential loss |
| TC-UX-009 | Audio unavailable | Open story/feedback | Text/caption alternative complete |
| TC-UX-010 | Wrong response | Inspect copy | Supportive; no shame/loss/false mastery claim |
| TC-UX-011 | Technical failure | Inspect actions | Clear Standard/retry action; no learner blame |
| TC-UX-012 | Result | Comprehension/widget check | Three axes separate; canonical reward area labeled separately |
| TC-UX-013 | Research prompt | Inspect/tap | Skip and consent details accessible; learning not blocked |
| TC-UX-014 | Brand surfaces | Search/render | `LexiQuest` retained; removed “เก่งศัพท์” absent |
| TC-UX-015 | Stable navigation tests | Change display copy | Tests use `learn/today-experience`/semantics; route remains green |

### 8.8 Reliability, performance and operations

| ID | Preconditions | Action | Expected result |
|---|---|---|---|
| TC-OPS-001 | Warm local DB, 3-node world | Measure entry/projection | p95 within 50/100 ms budgets |
| TC-OPS-002 | Local assets | Measure first meaningful render | p95 ≤1.5 s on certified profile |
| TC-OPS-003 | Compare Standard/Adventure start | Measure added overhead | Adventure p95 overhead ≤150 ms |
| TC-OPS-004 | Map/list transitions | Profile frames | no >100 ms long task; frame budget assessed |
| TC-OPS-005 | World v1 assets | Measure package | packaged visual assets ≤5 MB; audio separate |
| TC-OPS-006 | Offline network | Complete local mission | Canonical learning works; no network prerequisite |
| TC-OPS-007 | Network flaps | Open/refresh | bounded backoff; no retry loop or duplicate work |
| TC-OPS-008 | Corrupt catalog | Repeated opens | quarantined once; stable fallback; no crash |
| TC-OPS-009 | Database close/dispose | Exit app | all owned resources close once; no late write |
| TC-OPS-010 | Owner switch during async projection | Resolve late result | result fenced; active owner state only |
| TC-OPS-011 | Emergency-off rehearsal | Execute runbook | new starts blocked; accepted session safe; Standard restored |
| TC-OPS-012 | Feature re-enabled after review | Open | compatible state resumes; assignment/preferences preserved |
| TC-OPS-013 | Diagnostic events | Inspect payload | bounded codes/counters only; no answer/raw response/direct ID/story text |
| TC-OPS-014 | Unsupported enum/schema/event | Replay | fail closed; compatible state not overwritten |
| TC-OPS-015 | Android Pilot candidate | Execute scoped BG-01–BG-12 | Android/shared gates green; exclusions archived and never labelled pass |

## 9. Automation Mapping

| Case family | Target location |
|---|---|
| ENT | `test/architecture/`, `test/runtime/`, `test/features/adventure/entry/` |
| JRN | `test/features/adventure/catalog/`, `journey/`, `test/scenarios/` |
| LRN | `test/features/adventure/learning/`, learning equivalence architecture tests |
| REC | `test/features/adventure/recovery/`, reward/restart scenarios |
| DAT | `test/database/`, identity/export/sync/lifecycle tests |
| RSH | research domain/repository/rules/emulator tests |
| UX | widget/semantics/golden tests and manual certification |
| OPS | performance profile, platform/scenario/runbook evidence |

## 10. Defect Management

| Severity | Examples | Rule |
|---|---|---|
| Blocker | data loss, app cannot start, no Standard fallback | stop work/gate |
| Critical | owner leak, consent bypass, evidence corruption, duplicate economy, inaccessible primary path | no merge/Pilot |
| High | mission/lesson/recovery unavailable without safe workaround | fix before next gate |
| Medium | partial degradation with safe workaround | disposition before Pilot |
| Low | cosmetic/copy issue without semantic harm | backlog with UX owner |

Every defect records environment, build/commit, owner, data fixture, exact repro, expected/actual, logs/screenshots with privacy review, requirement/test IDs, severity and regression test.

## 11. Test Evidence Package

For every gate retain:

- command and exact tool versions;
- start/end time and exit code;
- test counts and named skips/exclusions;
- sanitized logs;
- device/build/config identity;
- feature/catalog/schema/rules/protocol revisions;
- defect links and disposition;
- screenshots/accessibility reports where applicable;
- reviewer and approval decision.

An historical log or generated plan is not current evidence when source fingerprints differ.

## 12. Test Sign-off

| Role | Decision | Name | Date | Evidence/conditions |
|---|---|---|---|---|
| QA Lead | Approve / Revise / Reject |  |  |  |
| Tech Lead | Approve / Revise / Reject |  |  |  |
| Product Owner | Approve / Revise / Reject |  |  |  |
| Accessibility Reviewer | Approve / Revise / Reject |  |  |  |
| Research/Privacy Owner | Approve / Revise / Reject |  |  |  |
