# Project Plan / Work Breakdown Structure — Adventure Motivation Mode

**Document ID:** LQ-AMM-PP-001
**Version:** 1.0
**Status:** Draft for Owner Review
**Planning basis:** TOR/SRS/SDS v1.0 and `AMM-AUDIT-001 v1.0`
**Decision basis:** `LQ-AMM-ADR-001 v1.0` and `LQ-AMM-MDS-001 v1.0`
**Estimate class:** ROM ±30% until G1 architecture approval and closure of the Audit before-implementation gate

## 1. Delivery Strategy

โครงการใช้ incremental, test-first, gate-driven delivery แต่ละ phase ต้องได้ artifact ที่ทำงานและทดสอบได้โดยไม่รอ feature ทั้งหมด งาน production ทำใน worktree/branch แยกจาก 8/44 baseline; merge เฉพาะหลัง review และ gate

### 1.1 Reference team for schedule

| Role | Capacity assumption |
|---|---:|
| Tech Lead/Architect | 1.0 FTE |
| Flutter Engineer | 2.0 FTE |
| QA Automation | 1.0 FTE |
| UX/Accessibility | 0.5 FTE |
| Research/Data | 0.5 FTE from Phase 4 |
| Content/Localization | 0.5 FTE from Phase 1 |
| Release/Operations | 0.25 FTE |

With this team the planning range is 18–24 calendar weeks, excluding waiting time for ethics/protocol approval and participant recruitment. Person-day estimates are effort, not elapsed calendar commitments.

### 1.2 Effort summary

| Phase | Focus | Estimate (person-days) | Gate |
|---|---|---:|---|
| P0 | Baseline remediation, contracts, catalog foundation | 42 | G0A/G0B/G1 |
| P1 | Read-only shell and journey | 38 | G2-read-only |
| P2 | Learning bridge, repair, recovery | 48 | G2-learning |
| P3 | Preference v2, motivation, companion | 48 | G3-core |
| P4 | Research schema/events/lifecycle | 58 | G4-research |
| P5 | Internal, hardening, Pilot UAT | 42 | G5-pilot |
| P6 | Controlled enablement and closeout | 18 | G6 |
| **Total** | | **294 person-days** | |

Contingency 15% is held at project level for migration/toolchain/accessibility findings, producing a management reserve of 45 person-days.

### 1.3 Independently closable increments

| Increment | Phases | Base effort | Schema consequence | Owner decision |
|---|---|---:|---|---|
| A Read-only Preview | P0–P1 | 80 pd | v22 unchanged | Accept preview / Revise / Stop |
| B Product Core MVP | P2 | 48 pd | v22 unchanged | **MS-04 Accept / Stop / Continue** |
| C Product Extension | P3 | 48 pd | preference migration only if approved | Accept extension / keep session-local |
| D Research Add-on + rollout | P4–P6 | 118 pd | research migration only if approved | Pilot / Revise / Stop research |

แต่ละ increment มี budget/change decision แยก การหยุดหลัง A หรือ B เมื่อ exit gate ผ่านเป็น successful bounded delivery ไม่บังคับใช้ reserve หรือ phase ที่เหลือ

## 2. Milestones

| Milestone | Exit evidence |
|---|---|
| MS-00 Planning approved | TOR/SRS/SDS/WBS/UI/Test/UAT/RTM approved |
| MS-01A Implementation-ready baseline | BL-05/06/07, worktree bootstrap and route ledger closed; no unclassified failure in touched foundation |
| MS-01B Android Pilot-ready baseline | Shared/touched foundation clean; Android Pilot matrix green; excluded platform/capability findings explicitly remain blocked |
| MS-02 Hidden contract | Feature hidden and feature-off equivalent |
| MS-03 Read-only preview | Map/list, catalog and journey deterministic; no writes |
| MS-04 Product Core MVP decision | Standard/Adventure command/evidence equivalence + Accept/Stop/Continue record; v22 unchanged |
| MS-05 Core motivation ready | planned v23 preference on actual reserved number, read-only canonical reward projection, scripted companion, recovery |
| MS-06 Research ready | planned v24 on actual reserved number, consented events, sync/lifecycle/export/rules |
| MS-07 Internal accepted | Accessibility/offline/restart/emergency-off evidence |
| MS-08 Pilot accepted | UAT + protocol/data quality/guardrail review |
| MS-09 Controlled enablement | Rollout decision and monitoring baseline |
| MS-10 Project close | Docs/evidence/decision log/remaining backlog archived |

## 3. WBS Dictionary

### 3.1 P0 — Baseline and contracts

| WBS | Work package | Output | Depends on | Effort | Owner | Exit test |
|---|---|---|---|---:|---|---|
| 0.1 | Planning approval | Approved document set v1.0 | None | 2 | PO/CTO | MS-00 |
| 0.2 | Reproducible worktree bootstrap | Offline package config/runbook without parent-checkout resolution | 0.1 | 1 | Tech Lead | feature-map check and analyze start locally |
| 0.3 | Baseline issue register | BL-01–BL-08 mapped to owners, gates and evidence paths | 0.1 | 1 | QA Lead | Audit trace review |
| 0.4 | Historical contract cleanup | Regenerate fingerprint; version schema audit; narrow `points`; use stable Thai navigation identity | 0.2,0.3 | 2 | QA/Engineer A | BL-01/05/06/08 targeted tests green |
| 0.5 | Bootstrap/path-provider test seam | Injectable application-support path and corrected scenario harness | 0.2,0.3 | 3 | Engineer A | Seven BL-07 scenarios green |
| 0.6 | iOS platform contract decision | Tracked Podfile/approved replacement and iOS 13 notification evidence | 0.3 | 2 | Mobile Owner | BL-02 contract green |
| 0.7 | Field-model certification preparation | Approved checksum-pinned fixture workflow and separate hardware gate | 0.3 | 2 | ML/Mobile Owner | BL-03/04 pass in declared gate |
| 0.8 | Secret/dependency disposition | Gitleaks fixture remediation; LM/Voice/root policy decisions and expiry owners | 0.3 | 3 | QA/Backend Owners | release scans meet reviewed policy |
| 0.9 | Fresh baseline run | Full default + serial suite, analyze, backend, emulators and scans archived | 0.4–0.8 | 2 | QA | 0 unclassified failures; MS-01B |
| 0.10 | Current route/screen ledger + ADR-001 | 63 screens classified; orphan candidates dispositioned; `learn/today-experience` child route approved; no bottom-tab change | 0.1 | 2 | UX/Tech Lead | reachability/navigation decision signed |
| 0.11 | Schema ledger reservation | actual preference/research migration numbers reserved or rebase recorded | 0.1 | 1 | Tech Lead | ledger review |
| 0.12 | Feature/entry contract tests | Failing tests for hidden/additive broad feature without f45, no Learn-layout drift and no bottom tab | 0.4,0.5,0.10 | 2 | Engineer A | Red test verified; MS-01A |
| 0.13 | Add hidden feature mapping | Feature/registry/production contract | 0.12 | 2 | Engineer A | Contract tests green |
| 0.14 | Dependency contract | `AppDependencies` fail-closed mapping and Today dependency rule | 0.13 | 2 | Engineer A | Missing deps resolve Standard |
| 0.15 | Legacy map boundary | Test keeps orphan map out of entry | 0.10,0.13 | 1 | QA | Architecture test green |
| 0.16 | Domain IDs/codecs | Entry/catalog base value types | 0.12 | 3 | Engineer B | Validation tests green |
| 0.17 | Catalog v1 fixtures | Thai/English/manifest sample | 0.16 | 3 | Content/UX | Locale parity review |
| 0.18 | Catalog validator | ID/graph/locale/checksum/path validation | 0.17 | 4 | Engineer B | Negative matrix green |
| 0.19 | Feature-off equivalence evidence | Standard navigation/read models and zero-write comparison | 0.13–0.18 | 2 | QA | baseline-equivalence suite green |
| 0.20 | Phase review | Diff, tests, Audit closure links and feature-off evidence | 0.9,0.19 | 2 | CTO/QA | MS-02 |

### 3.2 P1 — Read-only shell and journey

| WBS | Work package | Output | Depends on | Effort | Owner | Exit test |
|---|---|---|---|---:|---|---|
| 1.1 | Journey model tests | Node/snapshot/dependency contracts | 0.12 | 3 | Engineer A | Domain tests |
| 1.2 | Canonical reader adapters | Typed read ports over existing sources | 1.1 | 4 | Engineer A | Fake/adapter tests |
| 1.3 | Journey projection | Deterministic resume/review/mission mapping | 1.2 | 5 | Engineer A | Determinism matrix |
| 1.4 | Session plan domain | Plan/origin/version validation | 0.12 | 3 | Engineer B | Domain tests |
| 1.5 | Session composer read-only | Today work → pinned plan | 1.3,1.4 | 5 | Engineer B | Selection/idempotency tests |
| 1.6 | Shell state controller | load/refresh/in-flight/fallback state | 1.3 | 3 | Engineer B | State tests |
| 1.7 | Map widget | Three-node low-motion map | 1.6 | 4 | Engineer A | Widget/golden |
| 1.8 | List parity widget | Same nodes/actions/semantics | 1.7 | 3 | Engineer A | Parity tests |
| 1.9 | Mission sheet | Reason/duration/CTA/Standard switch | 1.5,1.6 | 3 | Engineer B | Widget tests |
| 1.10 | Status/fallback states | Empty/stale/corrupt/offline/unavailable | 1.6 | 3 | Engineer B | State matrix |
| 1.11 | Navigation preview and production entry seam | Internal guarded route + eligible additive Learn card/TodayExperienceHost; hidden path baseline-equivalent | 1.7–1.10 | 3 | Engineer A | ADR-001 navigation tests |
| 1.12 | Accessibility review | Semantics, focus, 200%, reduced motion | 1.11 | 2 | UX/QA | Required checks |
| 1.13 | Phase review | Zero writes/schema diff + deterministic recomposition | all P1 | 1 | CTO/QA | MS-03 |

### 3.3 P2 — Learning bridge, repair and recovery

| WBS | Work package | Output | Depends on | Effort | Owner | Exit test |
|---|---|---|---|---:|---|---|
| 2.1 | Equivalence characterization | Standard start/evidence golden fixtures | 1.13 | 4 | QA/Engineer A | Baseline characterization |
| 2.2 | Learning bridge contract | Failing tests for unchanged evidence | 2.1 | 3 | Engineer A | Red verified |
| 2.3 | Bridge implementation | Existing controller/start command wiring | 2.2 | 5 | Engineer A | Equivalence green |
| 2.4 | Transient origin contract | Plan/session correlation without evidence mutation | 2.3 | 2 | Engineer A | Exact JSON equality |
| 2.5 | Unified shell navigation | Adventure → registered learning screens | 2.3 | 4 | Engineer B | Widget/integration |
| 2.6 | Repair policy tests | 3–5 spacing, one round, no padding | 1.13 | 3 | Engineer B | Red verified |
| 2.7 | Repair implementation | In-session queue + SRS deferral | 2.6 | 5 | Engineer B | Policy green |
| 2.8 | Result model | Separate learning/effort/engagement | 2.3 | 3 | Engineer A | No combined score test |
| 2.9 | Result screen | Pending reward and next action states | 2.8 | 3 | Engineer A | Widget/golden |
| 2.10 | Exact evidence retry | Failure/retry identity integration | 2.3 | 4 | Engineer B | Restart scenario |
| 2.11 | Session recovery | Resume priority and safe terminal close | 2.10 | 4 | Engineer B | Restart/owner switch |
| 2.12 | Kill-switch cutoff | No new op, safe close, Standard return | 2.11 | 3 | Engineer A | Scenario green |
| 2.13 | Offline learning bridge | Verified local content and fallback | 2.3 | 3 | Engineer A | Offline scenario |
| 2.14 | Product Core MVP review | Same evidence semantics; no duplicate response; schema v22; Product Owner Accept/Stop/Continue record | all P2 | 2 | CTO/QA/PO | MS-04 |

### 3.4 P3 — Preference, motivation and companion

| WBS | Work package | Output | Depends on | Effort | Owner | Exit test |
|---|---|---|---|---:|---|---|
| 3.1 | Preference migration tests | v22 fixture preservation/default Standard on actual reserved number | 2.14 | 4 | Engineer A | Red verified |
| 3.2 | Preference v2 domain/table | HomeExperience codec + column | 3.1 | 4 | Engineer A | Migration/domain green |
| 3.3 | Preference use case/UI | Read/save/remember choice | 3.2 | 3 | Engineer A | Owner/conflict tests |
| 3.4 | Preference sync/lifecycle | sync, guest upgrade, export/delete | 3.2 | 6 | Engineer B | Lifecycle scenarios |
| 3.5 | Motivation projection tests | No-grant architecture, receipt reading and assessment exclusion | 2.14 | 4 | Engineer B | Red verified |
| 3.6 | Canonical projection reader | Read Quest/Streak/Achievement/Reward receipts after existing reconciler | 3.5 | 5 | Engineer B | Integration green; zero Adventure mutations |
| 3.7 | Projection refresh | Evidence success/reward pending recovery through canonical outbox | 3.6 | 3 | Engineer B | Pending/refresh tests |
| 3.8 | Reaction catalog/domain | Trigger/copy/asset/no-AI model | 0.11 | 3 | Content/Engineer A | Validator tests |
| 3.9 | Reaction selector | Deterministic scripted mapping | 3.8 | 2 | Engineer A | Unit tests |
| 3.10 | Companion/avatar panel | Existing equipped cosmetics + alternatives | 3.9,3.6 | 4 | Engineer A | Widget/accessibility |
| 3.11 | Content review | Thai/English, shame/mastery claims | 3.10 | 2 | UX/Content | Signed review |
| 3.12 | Full core scenario | Open→learn→repair→result→recompose | 3.3–3.11 | 4 | QA | Scenario green |
| 3.13 | Phase review | No duplicate authority/reward | all P3 | 2 | CTO/QA | MS-05 |

### 3.5 P4 — Research instrumentation and lifecycle

| WBS | Work package | Output | Depends on | Effort | Owner | Exit test |
|---|---|---|---|---:|---|---|
| 4.1 | Protocol/instrument/measurement decision | Versioned bounded items/codes/scoring + MDS primary estimand, +5 threshold, guardrails and power calculation | MS-04 Continue,3.13 | 4 | Research Lead | MDS/protocol review |
| 4.2 | Research migration tests | preference-version→research-version + v1→current matrix using reserved numbers | 4.1 | 5 | Engineer A | Red verified |
| 4.3 | Research tables/domain | Runs/responses/state validation | 4.2 | 5 | Engineer A | Migration/domain green |
| 4.4 | Measurement repository | Owner/idempotency/state machine | 4.3 | 5 | Engineer A | Repository tests |
| 4.5 | Measurement use cases | Consent/assignment/instrument enforcement | 4.4 | 4 | Engineer A | Isolation tests |
| 4.6 | Research prompt UI | Natural breakpoint, Skip, consent details | 4.5 | 3 | Engineer B | Widget/UAT dry run |
| 4.7 | Event payload/identity policy | Exact four event schemas v1; pre-session entryDecisionId vs mission learningSessionId | 4.1 | 3 | Engineer B | ADR-003 allowlist/idempotency tests |
| 4.8 | Research capture gate + recorder | Separate consent/assignment/run decision + EventsV2; no presentation authority | 4.7 | 5 | Engineer B | Nonparticipant zero-row + entry isolation |
| 4.9 | Sync entity and outbox | research rows/events sync/replay under actual schema/payload versions | 4.3,4.8 | 6 | Engineer B | Sync tests |
| 4.10 | Firestore rules | Owner/version/consent constraints | 4.9 | 4 | Engineer B/QA | Emulator tests |
| 4.11 | Lifecycle manifest/upgrade | guest upgrade/owner isolation | 4.3 | 4 | Engineer A | Scenario tests |
| 4.12 | Export/withdraw/delete | Separate axes and lifecycle behavior | 4.5,4.11 | 4 | Engineer A | Complete lifecycle scenario |
| 4.13 | Data validation | Assignment/version/crossover reconstruction | 4.8–4.12 | 3 | Research/QA | 100% metadata fixture |
| 4.14 | Phase review | Consent-safe and reconstructible | all P4 | 3 | CTO/Privacy/QA | MS-06 |

### 3.6 P5 — Internal hardening and Pilot

| WBS | Work package | Output | Depends on | Effort | Owner | Exit test |
|---|---|---|---|---:|---|---|
| 5.1 | Internal build config | Staff-only limited state | 4.14 | 2 | Release Owner | Entry allowlist |
| 5.2 | Android Pilot v1 matrix | Small/mainstream/tablet/TalkBack/offline/corrupt profiles; iOS/desktop explicitly excluded | 5.1 | 4 | QA | MDS Android device report |
| 5.3 | Performance profile | p95 budgets and asset size | 5.1 | 4 | QA/Engineer | NFR report |
| 5.4 | Accessibility manual audit | Screen reader, keyboard, 200%, motion | 5.1 | 5 | UX/QA | No critical finding |
| 5.5 | Offline/corrupt bundle drill | verify/repair/remove/fallback | 5.1 | 3 | QA | Scenario evidence |
| 5.6 | Restart/owner/lifecycle drill | restart, guest upgrade, export/delete | 5.1 | 4 | QA | Scenario evidence |
| 5.7 | Emergency-off rehearsal | accepted session cutoff and Standard | 5.1 | 2 | Release/QA | Signed runbook record |
| 5.8 | Internal UAT | Required nonresearch scripts; ≥12 learner reps + ≥4 accessibility sessions with explicit denominators | 5.2–5.7 | 4 | UAT Lead | MDS Internal sign-off |
| 5.9 | Research readiness review | protocol, ethics, consent, retention | 4.14 | 3 | Research/Privacy | Approval record |
| 5.10 | Pilot deployment | Small consented cohort | 5.8,5.9 | 2 | Release Owner | Assignment 100% |
| 5.11 | Pilot monitoring | guardrails/data quality/defects | 5.10 | 5 | QA/Research | Pilot report |
| 5.12 | Pilot UAT/interviews | usability/comprehension; ≥10 research comprehension participants with 10/10 consent understanding | 5.10 | 3 | UX/UAT | MDS thresholds dispositioned |
| 5.13 | Pilot decision | Enable, revise, or hide | 5.11,5.12 | 1 | Product Owner | MS-08 |

### 3.7 P6 — Controlled enablement and closeout

| WBS | Work package | Output | Depends on | Effort | Owner | Exit test |
|---|---|---|---|---:|---|---|
| 6.1 | Rollout segmentation | Approved exposure increments | 5.13 | 2 | PO/Release | Change record |
| 6.2 | Production monitoring | Fallback/retry/asset/crossover dashboards | 6.1 | 3 | Release/Data | Alert rehearsal |
| 6.3 | Increment 1 | Limited eligible users | 6.2 | 2 | Release | Guardrails stable |
| 6.4 | Increment review | Compare thresholds and defects | 6.3 | 2 | PO/QA/Research | Continue/hold decision |
| 6.5 | Additional increments | Controlled expansion only after review | 6.4 | 3 | Release | Each gate recorded |
| 6.6 | Post-release UAT | Core/rollback/consent smoke | 6.3 | 2 | QA/UAT | Required cases pass |
| 6.7 | Documentation finalization | As-built SDS/RTM/runbooks | 6.4 | 2 | Tech Lead | Version 1.x published |
| 6.8 | Backlog separation | AI/camera/social/new worlds separate specs | 6.7 | 1 | Product Owner | Backlog approved |
| 6.9 | Closeout | Lessons learned, metrics, ownership handoff | 6.5–6.8 | 1 | Project Manager | MS-10 |

## 4. Critical Path

```text
Planning approval
→ Implementation-ready Audit gate
→ Hidden feature contracts
→ Catalog + Journey
→ Session Composer
→ Learning Bridge equivalence
→ Recovery/repair
→ MS-04 Accept/Stop/Continue
→ reserved preference migration/lifecycle
→ Motivation idempotency
→ reserved research migration/lifecycle/rules
→ Pilot-ready clean baseline
→ Internal accessibility/offline/rehearsal
→ Pilot
→ Controlled enablement
```

Research protocol work can begin in parallel with P3 after core flow is stable, but research persistence cannot merge before P3 exit gate. UI asset/content work can run beside domain work after catalog contracts freeze.

## 5. Dependency Rules

1. No production code before MS-00 and MS-01A; no Android Pilot sign-off before scoped MS-01B
2. No presentation work before domain snapshot contracts have failing tests
3. No learning bridge before canonical equivalence fixtures
4. No preference migration before Phase 1 read-only gate and actual ledger reservation
5. No research migration before MS-04 Continue, Phase 3 core gate, approved MDS/protocol and actual ledger reservation
6. No event recording before consent/assignment/run gate tests
7. No Pilot before all lifecycle, accessibility and emergency-off evidence
8. No Enabled state before Pilot decision; platform/capability expansion requires its own gate

## 6. Definition of Ready

A work package can start only when:

- owning SRS IDs are listed;
- input/output interface is frozen for the task;
- exact files and tests are identified;
- upstream dependency tests are green;
- test data/fixtures are available;
- no unresolved authority/schema conflict;
- reviewer is assigned

## 7. Definition of Done

A work package is done only when:

- failing test was observed before implementation where code changes;
- implementation is minimal and scoped;
- targeted test passes;
- required broader suite passes in approved environment;
- `flutter analyze`/format checks pass for touched code;
- manual UX/accessibility step is recorded when applicable;
- no unrelated file change;
- reviewer approves requirement and code quality;
- RTM/test evidence is updated;
- commit is atomic and named by outcome

## 8. Quality Management

### Required local checks

- Dart formatting for touched Dart files
- `flutter analyze`
- targeted unit/widget/integration tests
- migration tests and v1→current matrix when schema changes
- Firestore emulator policy tests when rules/sync change
- Gitleaks, OSV/dependency audit and focused diff review at release gates
- asset manifest/checksum/localization validator
- manual screen reader/text scale/reduced-motion/device checks

No Codex Security/Security Scan/Deep Scan workflow is part of this repository plan.

### Defect severity

| Severity | Definition | Release rule |
|---|---|---|
| Blocker | Data loss, app cannot start, baseline unusable | Stop phase |
| Critical | Owner leak, consent bypass, duplicate economy, evidence corruption, inaccessible primary flow | Stop phase/Pilot |
| High | Major flow unavailable without safe workaround | Fix before next gate |
| Medium | Partial degradation with safe workaround | Disposition before Pilot |
| Low | Cosmetic/copy issue without meaning loss | Prioritize by UX owner |

## 9. Risk Register

| ID | Risk | P | I | Exposure | Trigger | Response owner | Response |
|---|---|---:|---:|---:|---|---|---|
| R01 | 15 reproducible baseline failures are treated as unrelated noise | 4 | 5 | 20 | implementation/Pilot proceeds without closure links | QA Lead | MS-01A/MS-01B split and exact BL-01–BL-08 ownership |
| R02 | Feature enum exhaustive mappings missed | 3 | 4 | 12 | Compile/contract mismatch | Engineer A | Exhaustive architecture tests |
| R03 | Journey duplicates progress | 2 | 5 | 10 | New durable node state proposed | CTO | Reject; projection only |
| R04 | Origin metadata mutates evidence | 2 | 5 | 10 | Evidence JSON diff | CTO | Transient context + separate consented events |
| R05 | preference migration overwrites v1 data or conflicts with cloud rules v1 | 3 | 5 | 15 | fixture/rules mismatch | Engineer A | staged rollout and exact preservation/version tests |
| R06 | research migration lifecycle incomplete | 3 | 5 | 15 | manifest/export/delete gap | Tech Lead | Cross-domain lifecycle gate |
| R07 | Reward replay duplicates | 3 | 5 | 15 | Retry creates new ledger row | Engineer B | Evidence causation/idempotency |
| R08 | Wrong-answer repair frustrates learner | 3 | 4 | 12 | Abandonment/user feedback | UX | One repair/no padding/supportive copy |
| R09 | Map excludes assistive users | 3 | 5 | 15 | Parity/semantics failure | UX/QA | List parity and blocking gate |
| R10 | Research collected without consent | 2 | 5 | 10 | Nonparticipant row | Research/Privacy | Dual gate + zero-row test |
| R11 | Assignment changes on switch | 2 | 5 | 10 | Cohort identity changes | Research Lead | Stable repository/invariant |
| R12 | Asset bundle failure blocks learning | 3 | 4 | 12 | Checksum mismatch | Engineer/QA | Quarantine/repair/Standard |
| R13 | Scope expands to AI/social | 4 | 4 | 16 | New capability requested mid-phase | Product Owner | Separate spec/backlog |
| R14 | Pilot insufficient for conclusion | 3 | 4 | 12 | Power/data quality failure | Research Lead | Pre-register and hold Enabled |
| R15 | Today Hub remains hidden/unavailable under Adventure entry | 3 | 5 | 15 | dependency not composed or parent still hidden | Product/Tech Lead | Standard fallback and exact delivery contract |
| R16 | Gitleaks/OSV/platform/model gates remain red | 3 | 5 | 15 | MS-01B evidence incomplete | QA/Platform/Backend | keep Pilot/release blocked |

P/I use 1–5. Exposure ≥15 is reviewed weekly and at every gate.

## 10. Communication and Reporting

| Cadence | Participants | Artifact |
|---|---|---|
| Per work package | Implementer + reviewer | Task checklist, tests, commit |
| Twice weekly | Engineering/QA/UX | Dependency/defect board |
| Weekly | PO/CTO/PM/Research | Milestone, risk and scope report |
| Gate review | Accountable roles | Signed gate checklist/evidence links |
| Pilot monitoring | PO/QA/Research/Privacy | Guardrail/data quality report |
| Emergency | Release/CTO/PO | Incident record and feature-state decision |

## 11. Change and Scope Control

Changes requiring formal change request:

- new authority/table/event type;
- change to evidence/reward semantics;
- removal of Standard escape;
- AI/camera/social/multiplayer/new economy;
- durable story branching;
- research instrument/protocol after enrollment starts;
- performance/accessibility budget relaxation;
- phase gate bypass

Minor copy/asset corrections within approved semantics use content review and catalog version bump but still update tests/checksum.

## 12. Release Decision Matrix

| Evidence state | Decision |
|---|---|
| Blocker/Critical open | Keep Hidden / emergency-off |
| Learning guardrail worse beyond protocol threshold | Stop Pilot; investigate |
| Motivation improves, learning stable, lifecycle clean | Eligible for controlled expansion |
| Engagement rises but motivation self-report/learning does not | Do not claim success; revise treatment |
| Metadata/assignment completeness <100% | Data invalid for primary decision; hold rollout |
| Accessibility required path fails | Hold rollout regardless of aggregate metrics |
| Asset/offline failure has Standard fallback but high frequency | Hold expansion; repair operations/content |

## 13. Project Closeout Deliverables

- approved as-built architecture and schema ledger
- final RTM with test/UAT evidence IDs
- release/pilot decision record
- runbook for feature states and emergency-off
- data dictionary, consent/retention record and export sample
- accessibility/device certification report
- defect disposition and deferred backlog
- metrics interpretation distinguishing motivation, engagement and learning
- cleanup issue for orphan legacy map, kept separate from Adventure implementation
