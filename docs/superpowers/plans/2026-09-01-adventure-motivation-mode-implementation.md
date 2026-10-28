# Adventure Motivation Mode — Implementation Plan

**Version:** 1.2

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. This planning task does not authorize production implementation.

**Goal:** เพิ่ม Adventure Motivation Mode เป็น optional presentation บน Today/learning authorities เดิม โดย Standard ยังคงเป็น fallback, evidence/reward semantics ไม่เปลี่ยน และ research data เกิดเฉพาะ consented protocol

**Architecture:** Existing Learn surface → authorized `home/learn/today-experience` card → one UUID v4 + one Today snapshot → Product Entry with optional `ActivePresentationPermit` projection → pure Standard/Adventure view → canonical Today session composer → existing Unified Lesson Controller/Side Effect Reconciler. Raw consent/guardian/assent receipts stay outside Product Entry; participant-only opportunity/events form a separate research boundary; no `adventure_progress` is created.

**Tech Stack:** Flutter/Dart, Material 3, Drift/SQLite, existing owner/sync/export/event contracts, Firebase rules emulator, Node test tooling

**Authoritative documents:**

- `docs/adventure-motivation-mode/00a-current-system-audit.md`
- `docs/adventure-motivation-mode/00b-architecture-decision-records.md`
- `docs/adventure-motivation-mode/01-tor.md`
- `docs/adventure-motivation-mode/02-srs.md`
- `docs/adventure-motivation-mode/03-sds.md`
- `docs/adventure-motivation-mode/04-project-plan-wbs.md`
- `docs/adventure-motivation-mode/05-ui-ux-design-spec-wireframes.md`
- `docs/adventure-motivation-mode/06-test-plan-and-test-cases.md`
- `docs/adventure-motivation-mode/07-uat-script.md`
- `docs/adventure-motivation-mode/08-requirements-traceability-matrix.md`
- `docs/adventure-motivation-mode/09-measurement-decision-spec.md`

**Pinned baseline:** Adventure planning `99f7fb21`; Pair Matching source closure `f56e2eb`; feature catalog revision 1.3.0/hash `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`; Drift schema v22; EventEnvelopeV2 unchanged

**ROM baseline:** 452 person-days ±30%, management reserve 83 person-days, 28–40 calendar weeks excluding ethics/recruitment/efficacy waiting time. Increments A/B/C/D/E are 90/48/48/168/98 person-days; Increment E คือ Pair Matching Prototype และหยุดได้โดยไม่เปิด research/Adventure rollout.

**Binding interface fields:**

```text
ResearchParticipationPermit
  id, ownerId, participantClass, ageBandCode
  assignmentId, assignedTreatment, consentReceiptId
  guardianPermissionReceiptRef?, learnerAssentReceiptRef?
  protocolId/version, issuedAtUtc, expiresAtUtc, revokedAtUtc?
  issuerKeyId, payloadSha256, signature
  local/cloud revisions, isDeleted

ActivePresentationPermit
  permitId, ownerId, assignedPresentation
  protocolId/version, assignmentId, expiresAtUtc

MeasurementOpportunity
  id, ownerId, measurementRunId, permitId, entryAttemptId
  assignedTreatment, effectivePresentation, presentedEventId?
  learningSessionId?, startedEventId?, completedEventId?
  lastSwitchOrdinal, suppressedSwitchCount, openedAtUtc, closedAtUtc?

PairMatchingPlanV1
  planId, ownerId, learningSessionId, entryKind, sourceSnapshotId?
  pairCount(compact4|standard6), direction(enToTh|thToEn)
  lexicalSnapshots[], mergedSourceReasons[], promptOrder[], targetOrder[]
  shuffleSeed, timerChoice(off|60|90|120)
  repairPolicyVersion, starPolicyVersion, checkpointPolicyVersion
  contentFingerprint, createdAtUtc

PairMatchingCheckpointNext
  planFingerprint, roundId, roundOrdinal, operationRevision
  selectedTileId?, matchedPairIds[], firstOpportunityLedger[]
  repairTickets[], dueRepairOrdinal?, supportState
  activeElapsedMs, remainingActiveMs?, timeoutState, extensionUsed
  sessionPurpose(learning|practiceReplay), sourceSessionId?
```

---

## 0. Execution Guardrails

1. เริ่มจาก isolated worktree/branch `feature/...`; ห้ามใช้ prefix `codex`; รัน `flutter pub get --offline` แล้วพิสูจน์ว่า `.dart_tool/package_config.json` อยู่ใน worktree นั้น
2. ห้ามแก้ production และ baseline-remediation ปะปน commit เดียวกัน
3. ใช้ TDD: เขียน failing test → รันให้เห็น failure ที่ถูกเหตุ → ทำ minimal implementation → รัน targeted + related regression → focused diff review
4. Adventure presentation ห้าม import Drift-generated rows หรือเรียก learning/reward repositories เพื่อ write
5. ห้ามเพิ่ม field Adventure ใน `EvidenceContext`, answer payload หรือ `EventEnvelopeV2`
6. ห้ามสร้าง `adventure_progress`, parallel vocabulary/SRS/mastery/reward ledger หรือ reward grant API
7. M07 อ่าน committed/pending receipts หลัง `LearningSideEffectReconciler` เท่านั้น
8. schema v23/v24 เป็นเลข “วางแผน”; ก่อน migration ต้องอ่าน ledger แล้ว reserve เลขจริง ถ้าถูกใช้ให้ rebase ขึ้น ห้ามแก้ released migration
9. Phase A ไม่มี schema; Phase B preference local; Phase C cloud preference/research หลัง rules/version cutoff พร้อม
10. Hidden/disabled/unknown/stale route ต้องกลับ Learn; Standard fallback ใช้เฉพาะ authorized Host และ emergency-off ต้องทดสอบก่อน MS-08A/MS-08B expansion
11. ห้ามใช้ historical passing log แทน fresh evidence
12. ก่อน Android Pilot ต้องปิด shared/touched-foundation failures, ผ่าน Android/reachable capability gates และบันทึก iOS/desktop/AI Voice/field-model exclusions โดยไม่เรียกว่า passed
13. ห้ามเพิ่ม bottom tab; production entry ใช้ `home/learn/today-experience` ภายใน Learn และ hidden path ต้อง baseline-equivalent
14. Product Entry ห้ามอ่าน raw consent/guardian/assent receipts; protocol treatment ใช้ได้เฉพาะ `ActivePresentationPermit`; Research Capture ห้าม mutate presentation
15. Standard/Adventure ใช้ neutral event policy เดียวกันและ participant opportunity เป็น denominator; `entryAttemptId` เป็น UUID v4 หนึ่งค่าต่อ Host opening
16. หลัง MS-04 ต้องหยุดรอ Product Owner เลือก Accept/Stop/Continue; Stop ต้องไม่ทำ migration
17. Pilot v1 เป็น Android-only; excluded capability/platform ห้ามรายงานว่า passed
18. Minor permit ต้องมี guardian permission + learner assent runtime evidence; แอปไม่เก็บ full DOB/guardian PII
19. MS-08A ไปได้สูงสุด Limited; Controlled Expansion/Enabled ต้องผ่าน MS-08B แยก adult/minor
20. Pair Matching เป็น semantic revision ของ `f10`; ห้ามสร้าง `f45`, main menu, star currency/ledger หรือ learning authority ใหม่
21. Pair plan ต้อง exact 4/6, entry-aware, deterministic และ atomic; no silent filler/downgrade
22. Pair checkpoint ใช้ reader-first/writer-later, reserve next available version ตอน implement และห้าม write ต่อ timer tick
23. Practice Replay ต้องพิสูจน์ zero delta ต่อ SRS/Mastery/Weakness/accuracy/reward/quest/streak/achievement/Today/research-primary ก่อนเปิด UI

## 1. Checkpoint 0 — Reproduce and Remediate the Baseline

### Task 0.1 — Bootstrap the isolated worktree reproducibly

**Files:**

- Verify: `.dart_tool/package_config.json`
- Modify if needed: `docs/runbooks/` repository setup documentation chosen by Tech Lead
- Test: feature-map tool/test already present in repository

**Steps:**

1. Record `git rev-parse HEAD`, `flutter --version` and `dart --version`.
2. Run `flutter pub get --offline`.
3. Resolve the package config path and assert it begins with the active worktree absolute path.
4. Run the exact 8/44 feature-map check and `flutter analyze --no-pub lib`.
5. Save command, exit code, count and tool versions under the approved evidence location; do not commit generated plugin registrar drift.

**Exit:** worktree-local resolution, feature map exact, production analyze starts/finishes locally

### Task 0.2 — Fix stale historical contract assertions BL-05, BL-06 and BL-08

**Files:**

- Modify: `test/phase_minus_1/week_1_2_verification_test.dart`
- Modify: `test/screens/associative_reading_launcher_screen_test.dart`
- Reference: `test/support/current_database_contract.dart`
- Reference: `lib/navigation/navigation_glossary.dart`
- Test: same files

**Steps:**

1. Add/adjust a test so the Phase -1 audit references `AppDatabase.currentSchemaVersion` or is explicitly scoped to its historical snapshot, not hard-coded current v11. Run it and confirm old assertion fails.
2. Replace broad `\bpoints\b` source regex with an authority-semantic boundary that does not flag handwriting coordinate variables. Keep a negative fixture that still flags a prohibited reward alias. Run and confirm red→green.
3. Change associative-reading navigation test to stable route/semantic/glossary identity. Confirm it fails against the obsolete English assumption and passes with Thai `อ่านเชื่อมโยงความจำ`.
4. Run the full Phase -1 and associative-reading screen groups.
5. Commit only the contract-test remediation.

**Exit:** BL-05/06/08 targeted tests green with no production behavior change

### Task 0.3 — Add the application-support-directory test seam for BL-07

**Files:**

- Modify: `lib/runtime/app_bootstrap.dart`
- Modify if composition owns it: `lib/features/offline_content/application/offline_content_manager.dart`
- Modify: `test/scenarios/ai_voice_fallback_journey_test.dart`
- Modify: `test/scenarios/associative_reading_restart_test.dart`
- Modify: `test/scenarios/current_activity_evidence_bootstrap_test.dart`
- Modify: `test/scenarios/production_vocabulary_restart_test.dart`
- Reference: `test/runtime/app_bootstrap_test.dart`

**Steps:**

1. Write a failing scenario proving bootstrap accepts an injected `applicationSupportDirectoryProvider` without platform-channel binding.
2. Thread the existing/inferred provider seam through the offline composition root; production default still calls `getApplicationSupportDirectory`.
3. Give each affected scenario a unique temporary support directory and close owned resources once.
4. Run the seven previously failing cases; confirm all pass and no shared Drift executor warning was introduced.
5. Run `test/runtime/app_bootstrap_test.dart` and offline-content manager tests.
6. Commit seam + scenario harness together.

**Exit:** BL-07 seven failures green; no production path behavioral change

### Task 0.4 — Classify and close shared/Android Pilot baseline gates

**Files:**

- Modify/regenerate under approved workflow: final 8/44 test plan artifact referenced by `test/architecture/final_8_44_test_plan_contract_test.dart`
- Decide/modify: `ios/Podfile` or approved replacement contract
- Prepare outside source as policy allows: `build/model-fixtures/mobilenet.tflite`
- Modify fixtures if approved: `test/features/learning/drift_learning_event_store_test.dart`
- Modify fixtures if approved: `test/features/sync/firestore_sync_gateway_test.dart`
- Modify fixtures if approved: `test/features/sync/reward_transaction_sync_test.dart`
- Modify dependency lock/requirements only through owning backend project

**Steps:**

1. Regenerate the fingerprint artifact from current source and review the diff; never hand-edit a digest.
2. Record iOS Podfile/notification issue as excluded from Android Pilot v1 and still blocked for iOS enablement; do not label its contract green.
3. Record field-model/AI Voice as excluded unless reachable from the Android Pilot build; when reachable, prepare checksum-pinned fixtures and run their certification before Pilot.
4. Replace synthetic secret-like fixtures with deterministic non-secret forms or add narrowly reviewed fingerprint allowlisting; rerun tracked-history Gitleaks.
5. Upgrade LM `datasets` to a fixed compatible version (≥5.0.1) and resolve/approve Voice optional-GPU findings before policy expiry; run affected backend suites and OSV.
6. Run default and serial full Flutter inventory suites. Require the logical/shared/touched set to pass; map any remaining failure to an approved explicit exclusion and require zero unclassified failures.
7. Archive shared/Android BG-01–BG-11 evidence plus an explicit exclusion matrix and commit each owner area separately.

**Exit:** `G0A` for implementation; shared/touched foundation clean and Android Pilot matrix green for `G0B`; excluded platforms remain blocked for their own enablement

## 2. Checkpoint 1 — Hidden Contract and Catalog Foundation

### Task 1.1 — Add the hidden broad feature contract

**Files:**

- Modify: `lib/runtime/registries/feature.dart`
- Modify: `lib/runtime/registries/feature_registry.dart`
- Modify: `lib/runtime/production_feature_contract.dart`
- Test: `test/runtime/field_feature_registry_test.dart`
- Test: `test/architecture/production_feature_contract_test.dart`
- Test: `test/architecture/production_feature_delivery_cardinality_test.dart`
- Create: `test/features/adventure/application/adventure_feature_contract_test.dart`

**Steps:**

1. Write failing tests for `Feature.adventureMotivation`, serialized-name stability of every prior feature, default `hidden`, and “not f45”.
2. Run targeted tests and confirm failure is missing enum/registry mapping.
3. Add the enum/mapping minimally; do not change the 8/44 catalog.
4. Run runtime + architecture feature suites and exact 8/44 check.
5. Commit: `feat(adventure): register hidden presentation feature`.

### Task 1.2 — Define entry and versioned catalog domain types

**Files:**

- Create: `lib/features/adventure/domain/adventure_entry.dart`
- Create: `lib/features/adventure/domain/adventure_world_catalog.dart`
- Create: `lib/features/adventure/data/packaged_adventure_world_catalog.dart`
- Create: `lib/features/adventure/data/adventure_world_catalog_validator.dart`
- Create: `test/features/adventure/domain/adventure_entry_test.dart`
- Create: `test/features/adventure/data/adventure_world_catalog_validator_test.dart`
- Add packaged assets only after Content/UX review under the repository asset convention

**Steps:**

1. Write domain tests for closed enums, exact codec, unknown fail-closed behavior and immutable version pins.
2. Write validator tests for duplicate IDs, graph cycle/unreachable ref, missing locale/accessibility label, path traversal, checksum/size/type/revision mismatch and remote executable content.
3. Implement value types and pure validator only.
4. Add the smallest Thai/English three-node catalog fixture with stable IDs and SHA-256 metadata.
5. Run tests twice with shuffled input order; output/errors must be deterministic.
6. Commit domain and fixture separately from visual assets.

### Task 1.3 — Implement authorized Product Entry and active-permit projection boundary

**Files:**

- Create: `lib/features/adventure/application/adventure_entry_use_cases.dart`
- Create: `lib/features/adventure/application/adventure_rollout_gate.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/runtime/production_feature_gate.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Create: `lib/features/research/domain/research_participation_permit.dart`
- Create: `lib/features/research/application/research_participation_permit_validator.dart`
- Create: `test/features/adventure/application/adventure_entry_use_cases_test.dart`
- Create: `test/features/research/research_participation_permit_validator_test.dart`
- Modify: `test/runtime/production_feature_gate_test.dart`
- Modify: `test/runtime/app_bootstrap_test.dart`

**Steps:**

1. Write ENT-001–015 and RSH-016–020 decision tables as parameterized failing tests.
2. Host creates UUID v4 `entryAttemptId` once; resolver receives it and returns availability, destination, effective presentation, fallback reason and version pins.
3. Define the full `ResearchParticipationPermit` and minimal `ActivePresentationPermit` contracts from SDS v1.2; validator checks owner/assignment/consent/guardian+assent for minor/protocol/expiry/revocation/signature/revisions.
4. Add architecture tests proving Product Entry can depend only on `ActivePresentationPermitReader`, not `ConsentRegistry`, receipt fields or measurement responses.
5. Require identity-consistent Today/Learning/catalog dependencies; unauthorized hidden/disabled/unknown/stale/missing paths return Learn without Host/snapshot; post-authorization asset failure may render Standard.
6. Fence asynchronous resolution by owner/session generation.
7. Verify feature state never creates/changes assignment, permit or preference; invalid permit uses session choice → preference → Standard.
8. Run entry, permit, bootstrap, production gate and feature-off equivalence tests.

**Checkpoint review:** focused diff must show hidden/default-off behavior, no schema diff and no Adventure presentation route yet

## 3. Checkpoint 2 — Read-only Journey and Shell

### Task 2.1 — Build deterministic journey domain and authority read ports

**Files:**

- Create: `lib/features/adventure/domain/adventure_journey.dart`
- Create: `lib/features/adventure/application/adventure_journey_reader.dart`
- Reference/read through: `lib/features/today_hub/application/today_hub_use_cases.dart`
- Reference/read through: `lib/features/today_hub/domain/today_hub_models.dart`
- Create: `test/features/adventure/domain/adventure_journey_test.dart`
- Create: `test/features/adventure/application/adventure_journey_reader_test.dart`

**Steps:**

1. Write JRN-001–006 tests, including shuffled source ordering and resume/review priority.
2. Define closed node states and snapshot freshness/dependency metadata.
3. Add typed read ports over existing Today, Quest, Streak, Achievement, Reward, History and pack-completion projections; no mutation methods.
4. Implement a pure deterministic projection with canonical sort keys.
5. Add an architecture test rejecting `adventure_progress` and Drift-row imports.
6. Run journey tests plus Today Hub reader tests.

### Task 2.2 — Compose pinned sessions from canonical Today work

**Files:**

- Create: `lib/features/adventure/domain/adventure_session_plan.dart`
- Create: `lib/features/adventure/application/adventure_session_composer.dart`
- Create: `test/features/adventure/domain/adventure_session_plan_test.dart`
- Create: `test/features/adventure/application/adventure_session_composer_test.dart`

**Steps:**

1. Write failing tests for FR-034–041: Today-only input, due priority, preserved reason/override, duration policy, all pins, mixed-owner/stale rejection and idempotency.
2. Implement immutable `AdventureSessionPlan` and `AdventureOriginContextV1` as transient application metadata.
3. Compose using canonical Today work identity; never query a second vocabulary catalog.
4. Confirm same request identity produces same plan or declared conflict, never duplicate mission.
5. Run LRN-001/003–005 equivalents with property/determinism fixtures.

### Task 2.3 — Implement shell, Map/List parity and fallback states

**Files:**

- Create: `lib/features/adventure/presentation/adventure_hub_screen.dart`
- Create: `lib/features/adventure/presentation/adventure_today_entry_card.dart`
- Create: `lib/features/adventure/presentation/today_experience_host.dart`
- Create: `lib/features/adventure/presentation/adventure_mission_sheet.dart`
- Create: `lib/features/adventure/presentation/widgets/adventure_map.dart`
- Create: `lib/features/adventure/presentation/widgets/adventure_map_list.dart`
- Create: `lib/features/adventure/presentation/widgets/adventure_status_panel.dart`
- Create: `lib/features/adventure/presentation/widgets/adventure_standard_switch.dart`
- Modify: `lib/screens/main_navigation_screen.dart`
- Modify: `lib/screens/today_hub_screen.dart`
- Create: `lib/screens/today_hub_view.dart`
- Create: `test/features/adventure/presentation/adventure_hub_screen_test.dart`
- Create: `test/features/adventure/presentation/adventure_map_list_parity_test.dart`
- Modify: `test/screens/main_navigation_screen_test.dart`
- Modify: `test/navigation/navigation_glossary_test.dart`

**Steps:**

1. Write red navigation tests for stable child route `home/learn/today-experience`, no new bottom destination and byte/value-equivalent Learn layout when hidden.
2. Write widget tests for one eligible additive Learn card, one primary mission, always-visible Standard switch, loading/empty/stale/corrupt/offline/unavailable, CTA single-flight and Map/List parity.
3. Render from `AdventureJourneySnapshot`; widgets receive callbacks/read models only.
4. Refactor `TodayHubScreen` into legacy loader wrapper + pure `TodayHubView(snapshot)`. Make `TodayExperienceHost` call `TodayHubSnapshotLoader.load()` exactly once, pass the same snapshot object/fingerprint to Standard/Adventure, and reuse UUID across rebuild/retry/switch.
5. Add loader-call-count, snapshot object-identity, explicit-refresh-new-ID and stale-owner-result tests; hidden/stale direct route must construct neither Host nor loader.
6. Never reuse `LearningWorldMapScreen`; use `M3Theme`, glossary keys, 48×48 targets and non-color state cues.
7. Add semantics/focus/text-200%/dark/high-contrast/reduced-motion golden/widget coverage.
8. Run navigation, Today Hub and all new widget tests.

**Checkpoint review:** schema remains v22/44 tables; database write snapshot = zero; Standard fixtures equivalent; MS-03 evidence archived

## 4. Checkpoint 3 — Canonical Learning, Repair and Recovery

### Task 3.1 — Characterize Standard and add the learning bridge

**Files:**

- Create: `lib/features/adventure/application/adventure_learning_bridge.dart`
- Reference: `lib/features/learning/application/unified_lesson_controller.dart`
- Reference: `lib/features/learning/presentation/unified_lesson_shell.dart`
- Reference/freeze: `lib/features/learning/domain/evidence_context.dart`
- Create: `test/features/adventure/application/adventure_learning_bridge_test.dart`
- Modify: `test/features/learning/evidence_context_test.dart`
- Modify: `test/features/learning/unified_lesson_controller_test.dart`

**Steps:**

1. Capture Standard golden fixtures for start command, answer payload and evidence JSON.
2. Write failing Adventure-vs-Standard byte/value equality tests and an exact EvidenceContext keyset test rejecting Adventure fields.
3. Implement bridge to call existing controller with the same work IDs/revisions/modes/policy.
4. Keep origin transient; pass plan/session correlation only to the separate consented behavior recorder boundary.
5. Verify mixed owner/stale plan rejection occurs before write.
6. Run learning controller, evidence context, assessment isolation and bridge tests.

### Task 3.2 — Implement wrong-answer repair policy

**Files:**

- Create: `lib/features/adventure/application/adventure_repair_policy.dart`
- Create: `test/features/adventure/application/adventure_repair_policy_test.dart`
- Modify only through public extension seam if required: `lib/features/learning/application/unified_lesson_controller.dart`
- Reference: `lib/features/learning/srs/` or current SRS policy location discovered with `rg`

**Steps:**

1. Write parameterized red tests: 3–5 eligible intervening items, maximum one repair, no immediate repeat, no padding when <3 remain, independent identities for multiple wrong items.
2. Add typed incorrect/skip/technical/guided states; do not infer from display copy.
3. Implement in-session repair scheduling as a bounded plan decoration; canonical evidence remains owned by Learning.
4. Defer unmet/failed repair to existing Review/SRS authority using its public policy.
5. Test support ladder Flashcard → Recognition/Matching → Cloze → Typed Recall under existing active-recall eligibility.

### Task 3.3 — Implement exact retry, restart and kill-switch lifecycle

**Files:**

- Create: `lib/features/adventure/application/adventure_recovery_use_cases.dart`
- Create: `test/features/adventure/application/adventure_recovery_use_cases_test.dart`
- Create/modify: `test/scenarios/adventure_learning_restart_test.dart`
- Modify: `test/scenarios/runtime_kill_switch_journey_test.dart`
- Reference: existing session lifecycle APIs discovered in `lib/features/learning/`

**Steps:**

1. Write red scenarios for evidence-write failure, lost acknowledgement, app termination after commit, owner switch and emergency-off during accepted session.
2. Capture immutable retry identity before write; retry exact identity/payload only.
3. Resume accepted session before new mission and use existing close/retire semantics.
4. Emergency-off blocks new starts; accepted session safely finishes/closes then returns Standard.
5. Assert duplicate evidence/reward counts remain zero after repeated replay.

### Task 3.4 — Build result model/screen with pending receipts

**Files:**

- Create: `lib/features/adventure/domain/adventure_result.dart`
- Create: `lib/features/adventure/presentation/adventure_result_screen.dart`
- Create: `test/features/adventure/domain/adventure_result_test.dart`
- Create: `test/features/adventure/presentation/adventure_result_screen_test.dart`

**Steps:**

1. Write red tests requiring separate Learning/Effort/Engagement sections and forbidding a combined score.
2. Model pending canonical reward receipt separately from accepted learning.
3. Render Review/SRS next action from canonical authority.
4. Add supportive Thai/English copy and technical-error state without shame/false mastery claim.
5. Run REC-012–015 and UX-010–012 equivalents.

**Checkpoint review:** Standard/Adventure command and evidence equivalence, duplicate count zero, assessment isolation and schema v22. Record MS-04 Product Owner decision:

- **Accept/Stop:** archive Product Core MVP hidden; perform no preference/research migration; plan execution ends successfully.
- **Accept/Continue:** authorize Product Extension tasks only.
- **Revise:** return only to the failed P2 work package and rerun the affected gate.

## 5. Checkpoint 4 — Preference, Canonical Motivation Projection and Companion

### Task 4.1 — Reserve and migrate Learner Preferences v2

**Files:**

- Modify: `lib/features/preferences/domain/learner_preferences.dart`
- Modify: `lib/features/preferences/application/learner_preferences_use_cases.dart`
- Modify: `lib/features/preferences/data/drift_learner_preferences_repository.dart`
- Modify: `lib/data/local/tables/preference_tables.dart`
- Modify: `lib/data/local/app_database.dart`
- Generated: `lib/data/local/app_database.g.dart`
- Modify: `test/features/preferences/learner_preferences_use_cases_test.dart`
- Modify: `test/features/sync/learner_preferences_sync_test.dart`
- Add migration fixture test under `test/database/`

**Steps:**

1. Read current schema ledger and reserve actual migration number; record rebase if planned v23 is occupied.
2. Freeze v22 fixtures for every preference field and timestamps/revisions.
3. Write red migration/domain tests for `home_experience`, default Standard, exact two-value codec, unknown fail closed and v1 field preservation.
4. Add forward-only column/migration and regenerate Drift code through repository toolchain.
5. Thread read/save through owner-gated use cases; preference never grants feature or assignment.
6. Phase B: keep local only. Phase C: update versioned sync codec/rules/cutoff, then test older client cannot overwrite v2.
7. Run migration, preferences, sync, guest-upgrade, export/delete and feature-off rollback tests.

### Task 4.2 — Read canonical motivation receipts; never grant

**Files:**

- Create: `lib/features/adventure/application/adventure_motivation_projection_reader.dart`
- Reference: `lib/features/learning/application/learning_side_effect_reconciler.dart`
- Create: `test/features/adventure/application/adventure_motivation_projection_reader_test.dart`
- Modify: `test/features/learning/learning_side_effect_reconciler_test.dart`
- Create: `test/architecture/adventure_authority_boundary_test.dart`

**Steps:**

1. Write architecture tests that fail on Adventure imports/calls to grant/mutation APIs.
2. Write integration tests for learning committed/reward pending, committed receipts, assessment exclusion, replay and map/story no-op.
3. Implement read-only adapters for Quest, Gentle Streak, Achievement and Reward receipts.
4. Refresh projection after the existing reconciler/outbox commits; never synthesize optimistic reward.
5. Assert receipt source evidence and idempotency identities come from existing authority.

### Task 4.3 — Add scripted companion/reaction catalog

**Files:**

- Create: `lib/features/adventure/domain/adventure_reaction.dart`
- Create: `lib/features/adventure/application/adventure_reaction_selector.dart`
- Create: `lib/features/adventure/presentation/widgets/adventure_companion_panel.dart`
- Create: `test/features/adventure/domain/adventure_reaction_test.dart`
- Create: `test/features/adventure/presentation/adventure_companion_panel_test.dart`

**Steps:**

1. Write tests for deterministic catalog selection across correct/incorrect/hint/skip/return/completion.
2. Reject AI/free-text configuration, relationship score and punishment state in validator/architecture tests.
3. Read equipped cosmetic from existing Reward ownership projection.
4. Provide reduced-motion, no-audio and semantic equivalents.
5. Run content lint for shame/coercion/false mastery and complete bilingual review.

**Checkpoint review:** no duplicate authority or reward grant; preference lifecycle complete; MS-05

## 6. Checkpoint 5 — Consented Research Instrumentation

### Task 5.1 — Define versioned motivation instrument and reserve research schema

**Files:**

- Create: `lib/features/research/domain/motivation_instrument.dart`
- Create: `lib/features/research/domain/motivation_measurement.dart`
- Create: `lib/features/research/domain/motivation_measurement_repository.dart`
- Modify: `lib/features/research/domain/research_participation_permit.dart`
- Create: `lib/features/research/domain/measurement_opportunity.dart`
- Modify: `lib/data/local/tables/research_tables.dart`
- Modify: `lib/data/local/app_database.dart`
- Generated: `lib/data/local/app_database.g.dart`
- Create tests under: `test/features/research/` and `test/database/`

**Steps:**

1. Require approved MDS/protocol/instrument/form/response-code catalog, class-specific power calculation, baseline ≤24h, post ≤30m after first accepted completion, ANCOVA/MI/tipping-point and missingness gates before implementation.
2. Read schema ledger and reserve the next actual number after preference migration; do not assume v24.
3. Write red migration tests for exactly four tables: `motivation_measurement_runs`, `motivation_responses`, `research_participation_permits`, `measurement_opportunities`; cover v1→current fixtures, owner IDs, minor receipt constraints, signature/revision fields, unique/idempotent constraints and unknown-code rejection.
4. Implement the SDS v1.2 public field contracts exactly; no full DOB, guardian PII, free text or duplicated learning answer.
5. Add forward-only tables/migration and regenerate Drift code; opportunity switch ordinal is constrained 0–10 and suppression counter nonnegative.
6. Run current/full migration matrix and exact table inventory.

### Task 5.2 — Add separate Research Capture decision and measurement use cases

**Files:**

- Create: `lib/features/research/data/drift_motivation_measurement_repository.dart`
- Create: `lib/features/research/application/motivation_measurement_use_cases.dart`
- Create: `lib/features/research/application/adventure_research_capture_gate.dart`
- Modify: `lib/features/research/application/research_participation_permit_validator.dart`
- Create: `lib/features/research/application/measurement_opportunity_use_cases.dart`
- Create: `test/features/research/drift_motivation_measurement_repository_test.dart`
- Create: `test/features/research/motivation_measurement_use_cases_test.dart`
- Create: `test/features/research/adventure_research_capture_gate_test.dart`
- Reference: `lib/runtime/registries/experiment_registry.dart`

**Steps:**

1. Encode RSH-001–003 and RSH-016–020 as red decision-table tests; each incomplete/invalid permit gate creates zero opportunity/event/outbox and product learning falls back safely.
2. Add an architecture test forbidding Research Capture from importing/calling Product Entry mutation or presentation-selection APIs.
3. Implement `ActivePresentationPermit` projection from signed permit + existing authorities; Product Entry receives no receipt fields. Implement capture eligibility from active permit + run + versions without presentation mutation.
4. Implement owner-scoped idempotent run state machine with stable assignment and all version pins.
5. Check withdrawal/assent withdrawal/expiry/revocation immediately before Host/start/persistence/enqueue, not only when screen opens.
6. Implement bounded response submit/skip; learning/reward/access remain unchanged.
7. Test duplicate submit, owner switch, withdrawal race and restart.

### Task 5.3 — Record neutral events with an independent opportunity ledger

**Files:**

- Create: `lib/features/events/domain/today_experience_event_payload_policy.dart`
- Create: `lib/features/research/application/adventure_behavior_event_recorder.dart`
- Create: `test/features/events/today_experience_event_payload_policy_test.dart`
- Create: `test/features/research/adventure_behavior_event_recorder_test.dart`
- Reference/freeze: existing EventEnvelopeV2 files/tests under `lib/features/events/` and `test/features/events/`

**Steps:**

1. Write allowlist tests for exactly four neutral v1 payloads used by both treatments: `TodayExperiencePresented`, `TodayExperiencePresentationChanged`, `TodayExperienceMissionStarted`, `TodayExperienceMissionCompleted`.
2. Assert EventEnvelopeV2 exact keyset unchanged.
3. Open one participant-only `MeasurementOpportunity` per permit/run/entryAttempt before Presented; nonparticipant remains zero-row and keeps UUID transient only.
4. Pin `assignedTreatment` and `effectivePresentation` in every event. Presented/Changed attach to opportunity; Started/Completed attach accepted `learningSessionId` and the same opportunity.
5. Update `lastSwitchOrdinal` transactionally for 1–10; excess attempts increment only `suppressedSwitchCount`. Use deterministic IDs and reconcile a missing Presented event from the opportunity without duplicating denominator.
6. Never persist origin into learning evidence; assert EventEnvelopeV2 keyset unchanged.
7. Test Standard/Adventure schema symmetry, before/after-session events, concurrent switch, lost acknowledgement, event-write failure after opportunity open, replay idempotency, crossover without reassignment and privacy-redacted diagnostics.

### Task 5.4 — Complete sync, rules and lifecycle coverage

**Files:**

- Modify: `lib/features/identity/domain/owner_lifecycle_manifest.dart`
- Modify: `lib/features/identity/data/drift_owner_upgrade_repository.dart`
- Modify: `lib/features/sync/domain/sync_entity.dart`
- Modify: `lib/features/sync/data/drift_sync_store.dart`
- Modify: `lib/features/export/data/drift_export_reader.dart`
- Modify: `lib/features/export/application/owner_lifecycle_archive.dart`
- Modify: `firestore.rules`
- Modify/create targeted tests under `test/features/identity/`, `test/features/sync/`, `test/features/export/`
- Modify: `test/security/firestore-rules.test.cjs`

**Steps:**

1. Write failing manifest cardinality test: each of the four research entities appears exactly once; preserved global content unchanged.
2. Add guest-upgrade conflict/replay, export-axis, deletion-order, owner-isolation and retention/withdrawal tests.
3. Add versioned bounded sync payloads and incompatible replay rejection.
4. Write rules-emulator tests before rules: owner only, schema allowlist, bounded keys/codes, immutable assignment/permit pins, signature/revision constraints and denied unauthorized/unknown writes.
5. Implement minimal lifecycle/sync/rules changes and run Firestore/Auth emulator suites.
6. Reconstruct adult/minor ITT/crossover export fixtures with permit/opportunity completeness 100%, baseline/post timepoints and missingness disposition.

**Checkpoint review:** consent-safe zero-row behavior, complete lifecycle/rules/export evidence, MS-06

## 7. Checkpoint 6 — Diagnostics, Offline, Accessibility and Release

### Task 6.1 — Add bounded diagnostics and catalog repair operations

**Files:**

- Create: `lib/features/adventure/application/adventure_diagnostics.dart`
- Extend approved offline-content interface under: `lib/features/offline_content/`
- Create: `test/features/adventure/application/adventure_diagnostics_test.dart`
- Create: `test/scenarios/adventure_offline_catalog_recovery_test.dart`

**Steps:**

1. Write red tests for entry/fallback, composition, evidence retry, projection retry and asset failure codes.
2. Reject answer payload, raw response, raw story and unnecessary direct identifiers.
3. Implement verify/quarantine/repair/remove with bounded retry/backoff.
4. Confirm corrupt repeated open does not loop and asset removal does not delete learning/canonical progress.
5. Run offline/network-flap/restart/resource-close scenarios.

### Task 6.2 — Certify accessibility, responsive behavior and performance

**Files:**

- Modify new Adventure presentation/tests only as findings require
- Evidence: approved QA report location

**Steps:**

1. Run automated semantics/widget/golden suite for required screens/states.
2. Manually traverse screen reader and keyboard; record focus order/restoration and Map/List parity.
3. Test text 200%, narrow phone, dark, high contrast, reduced motion and no-audio.
4. Run Research Prompt, guardian permission, learner assent, invalid/expired/revoked permit and withdrawal flows with TalkBack, Switch Access/keyboard, text 200%, focus restoration and offline validation.
5. Measure entry p95 ≤50ms, projection p95 ≤100ms, render p95 ≤1.5s, added start overhead p95 ≤150ms, event commit p95 ≤100ms and frame/long-task budget on certified profiles.
6. Verify packaged visuals ≤5MB and audio separately downloadable.
7. Resolve every S0/S1 accessibility/performance issue before Internal UAT.

### Task 6.3 — Run the complete verification pyramid

**Commands/gates:**

1. exact 8/44 feature-map check;
2. `flutter analyze --no-pub lib test` with any info-level disposition recorded;
3. targeted adventure/domain/widget/architecture/scenario tests;
4. current authority suites: Today, Learning, SRS, Mastery, Weakness, Quest, Streak, Achievement, Reward, Owner, Sync, Export;
5. full Flutter inventory suite default and serial, with required logical/shared/touched pass set and explicit exclusion mapping;
6. AI, Voice, LM and affected backend suites;
7. Firestore/Auth emulator suites;
8. tracked-history Gitleaks, OSV/dependency audits under approved Android/reachable scopes;
9. Android platform contract; archive iOS/desktop/AI Voice/field-model as excluded and still blocked for their own enablement;
10. focused diff, generated-code check, schema/table/manifest cardinality and feature-off comparison

**Pass:** scoped BG-01–BG-12 green with fresh commit/build/environment evidence; exclusions have owner and are never counted as pass

### Task 6.4 — Execute UAT and rollout rehearsal

**Files:**

- Execute/update: `docs/adventure-motivation-mode/07-uat-script.md`
- Update actual links/status: `docs/adventure-motivation-mode/08-requirements-traceability-matrix.md`
- Update as-built: `docs/adventure-motivation-mode/03-sds.md`

**Steps:**

1. Internal UAT: UAT-001–024 and 030–032 with ≥12 learner representatives and ≥4 accessibility sessions; record every numerator/denominator; no open S0/S1.
2. Complete guardian-led permit enrollment and run UAT-025–037: general learners ≥12 with minors ≥4, accessibility sessions ≥4, adult research comprehension ≥10/10 and guardian–learner dyads ≥5 with guardian 5/5 + learner 5/5 independent comprehension.
3. MS-08A checks data quality, usability, comprehension, safety, zero-row and reconstructibility; release state can be only Limited/Revise/Stop.
4. Collect powered adult/minor samples separately, freeze baseline/post windows and run ANCOVA + multiple imputation + tipping-point; missing >15% or >5pp arm gap blocks affected class.
5. Run UAT-038 and sign MS-08B decisions per class before any Controlled Expansion/Enabled targeting.
6. Rehearse emergency-off before MS-08A and again before class expansion; accepted session closes through canonical lifecycle.
7. Update RTM statuses only from current evidence; archive MS-08A/MS-08B decision logs and unresolved backlog separately.

## 8. Checkpoint 7 — Pair Matching Prototype (M12 / Increment E)

Checkpoint นี้เริ่มได้หลัง Pair contracts/ADR/SRS/SDS/RTM v1.2 ได้รับอนุมัติ และแยก delivery flag จาก Adventure rollout งานทุก Task ใช้ TDD, commit ขนาดเล็กและ exact requirement IDs; ห้ามเปิด renderer ก่อน engine/evidence parity ผ่าน

### Task PM0 — Baseline characterization and f10 boundary lock (6 pd)

**Requirements:** FR-105/106/130, NFR-040/046, BR-024/034

**Inspect first:**

- `lib/screens/matching_mode_screen.dart`
- `lib/features/learning/application/matching_mode_adapter.dart`
- `lib/features/learning/application/lesson_mode_registry.dart`
- `lib/features/learning/domain/lesson_mode.dart`
- `lib/navigation/app_routes.dart`
- `lib/runtime/registries/feature_registry.dart`

**Tests to add/update:**

- `test/architecture/pair_matching_f10_boundary_test.dart`
- `test/screens/matching_mode_screen_test.dart`
- `test/features/learning/matching_mode_adapter_test.dart`
- `test/scenarios/production_feature_navigation_test.dart`

**Steps:**

1. บันทึก current f10 route, adapter, session/evidence path, restart/checkpoint behavior และ current screen output เป็น characterization fixtures;
2. เขียน failing architecture test ว่าไม่มี f45/new main destination/new star table และ Pair launch resolve กลับ f10;
3. เพิ่ม hidden delivery contract เฉพาะเมื่อ test ต้องการ โดยยังไม่เปลี่ยน behavior ผู้ใช้;
4. รัน `TC-PMT-001`, existing 8/44 exact-map tests และ feature-off navigation regression;
5. ตรวจ diff ให้ไม่มี schema/event/evidence payload change

**Exit:** baseline behavior reproducible, f10 identity locked, rollback target identified; no prototype UI visible

### Task PM1 — Entry-aware immutable plan and safe source composer (8 pd)

**Requirements:** FR-106–112, DATA-016/019, UI-018, NFR-038/039/044, BR-025–027

**Files:**

- Create `lib/features/learning/pair_matching/domain/pair_matching_launch.dart`
- Create `lib/features/learning/pair_matching/domain/pair_matching_plan.dart`
- Create `lib/features/learning/pair_matching/application/pair_matching_source_composer.dart`
- Modify only through typed adapters: Today/Review/Learn launch owners identified in PM0
- Add `test/features/learning/pair_matching/pair_matching_plan_test.dart`
- Add `test/features/learning/pair_matching/pair_matching_source_composer_test.dart`
- Add `test/features/learning/pair_matching/pair_matching_source_property_test.dart`

**Steps:**

1. เขียน failing fixtures สำหรับ Learn overlap, fixed Today snapshot, selected Review list และ Adventure pass-through;
2. นิยาม closed enums สำหรับ entry, direction, density, timer และ typed unavailable/confirm outcomes;
3. compose โดย merge provenance → deduplicate canonical identity → revalidate locale/revision/checksum/report/delete/collision → rank → exact select;
4. ใช้ curated EN–TH allowlist; ห้ามเพิ่ม sense table หรือ remote lookup เพื่อเติม plan;
5. resolve density จาก guardian product policy ก่อน learner preference; unknown prompt ครั้งเดียว/fallback 4; 6→4 ต้อง explicit accept; <4 ไม่ start;
6. สร้าง Learning Session + initial checkpoint แบบ atomic หลัง owner/source revalidation และ pin fingerprint/order/seed/version;
7. รัน `TC-PMT-002–012`, owner-switch/crash-injection และ Today single-load regressions

**Exit:** same pinned inputs ให้ plan/fingerprint เดิม; exact 4/6; zero session/evidence on unavailable/cancel; Adventure cannot recompose

### Task PM2 — Pure reducer, selection and evidence roles (10 pd)

**Requirements:** FR-107/113–115, DATA-016/017, NFR-038/039/041, BR-028

**Files:**

- Create `lib/features/learning/pair_matching/domain/pair_matching_engine.dart`
- Create `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart`
- Extend the existing matching adapter only behind typed M12 interfaces
- Add `test/features/learning/pair_matching/pair_matching_engine_test.dart`
- Add `test/features/learning/pair_matching/pair_matching_idempotency_test.dart`
- Add `test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart`

**Steps:**

1. เขียน transition table tests สำหรับ select/deselect/reselect ทั้งสองฝั่งและ duplicate operation ID;
2. ทำ reducer ให้ pure: state + command → state + effects; UI ห้ามเขียน repository ตรง;
3. correct เพิ่ม matched pair ครั้งเดียว; mismatch ไม่เพิ่ม/ลด matched progress;
4. attach incorrect recognition ครั้งเดียวกับ prompt-side canonical word; distractor ไม่รับ incorrect evidence;
5. persist first-opportunity/attempt-role ledger ด้วย operation identity และ coalesced checkpoint boundary;
6. fence stale callback/owner change/rebuild และ reserve terminal revision;
7. รัน `TC-PMT-013–016` พร้อม Unified Lesson/Evidence Gateway regressions

**Exit:** deterministic reducer, monotonic matched progress, no duplicate/lost attempt and no presentation write path

### Task PM3 — Delayed repair, semantic support and Review handoff (13 pd)

**Requirements:** FR-116–119, DATA-017/021, UI-022, NFR-038/041/043/044, BR-028–030

**Files:**

- Create `lib/features/learning/pair_matching/domain/pair_repair_policy.dart`
- Extend `pair_matching_engine.dart` and coordinator
- Add typed Review deferral adapter near existing Review/SRS application boundary
- Add `test/features/learning/pair_matching/pair_repair_policy_test.dart`
- Add `test/features/learning/pair_matching/pair_support_classification_test.dart`
- Add `test/features/learning/pair_matching/pair_review_deferral_test.dart`

**Steps:**

1. เขียน failing schedule fixtures: compact after 2 distinct correct other pairs, standard after 3, same-pair/non-answer not counted;
2. stable-order concurrent repair tickets by due ordinal/original ordinal/canonical ID;
3. wrong repair ซ้ำไม่สร้าง recursive queue; one unresolved canonical Review need ต่อ word/source evidence;
4. เมื่อ spacing ไม่พอ ให้ guided-complete อย่างโปร่งใสและ defer independent retry ไป Review โดยไม่ padding;
5. classify pronunciation/visible TalkBack as neutral; classify semantic reveal/corrective mapping as guided;
6. เมื่อ audio missing/offline/private remote disallowed ให้ text/IPA fallback และ board ทำงานต่อ;
7. รัน `TC-PMT-017–024`, SRS/Weakness/Review ownership regressions และ payload redaction tests

**Exit:** repair spacing exact, tail finite, no penalty/padding, Review receives one valid need, hint classification audit-ready

### Task PM4 — Active timer, timeout recovery and restart (16 pd)

**Requirements:** FR-120–124/127, DATA-017/018, UI-023, NFR-038/041/043, BR-031/033

**Files:**

- Extend Pair domain with injected monotonic active clock interface
- Create/update checkpoint codec under `lib/features/learning/pair_matching/data/`
- Add timeout presentation state to shared experience host; no renderer-specific timer logic
- Add `test/features/learning/pair_matching/pair_active_timer_test.dart`
- Add `test/features/learning/pair_matching/pair_timeout_recovery_test.dart`
- Add `test/features/learning/pair_matching/pair_timeout_race_test.dart`

**Steps:**

1. เขียน fake-clock tests สำหรับ off/60/90/120 และยืนยัน timer ไม่ auto-enable จากรอบก่อน;
2. นับ active interaction เท่านั้น; pause/resume ด้วย reason set ที่อ้างอิงได้สำหรับ background/modal/persistence/accessibility narration;
3. timeout สร้าง durable decision state โดยไม่สร้าง incorrect/completion;
4. Continue untimed ใช้ state/evidence เดิม; +30 idempotent หนึ่งครั้งต่อ Learning Session; Restart สร้าง round/seed ใหม่แต่ exact content/revisions/direction เดิม;
5. serialize answer-timeout-extension-restart race และ persist entitlement/evidence ก่อน acknowledgement;
6. kill/relaunch/lost-ack tests ต้อง restore exact decision โดยไม่ reset clock/evidence;
7. รัน `TC-PMT-025–031` และ checkpoint write-budget proof

**Exit:** timer neutral and recoverable; no per-tick durable write; timeout never forces failure or reward/mastery change

### Task PM5 — Stars, results, history and Practice Replay isolation (14 pd)

**Requirements:** FR-125–129, DATA-018/020/021, UI-024/025, NFR-038/041, BR-032/033

**Files:**

- Create `lib/features/learning/pair_matching/domain/pair_star_policy.dart`
- Create `lib/features/learning/pair_matching/presentation/pair_matching_result_view.dart`
- Extend existing history read model through a typed Pair projection
- Add `test/features/learning/pair_matching/pair_star_policy_test.dart`
- Add `test/features/learning/pair_matching/pair_practice_replay_test.dart`
- Extend `test/features/history/learning_history_replay_test.dart`

**Steps:**

1. เขียน table-driven boundary tests สำหรับ 3 ดาว, 3/4, 5/6, 4/6, guided tail และ incomplete;
2. derive จาก committed immutable ledger + `starPolicyVersion`; cached valueเป็น rebuildable read modelเท่านั้น;
3. แสดง matched/independent/assisted/stars/timer/elapsed/Review next แยกแกน ไม่มี combined score;
4. Practice Replay สร้าง session purpose ใหม่, exact valid content, shuffle ใหม่และ immutable source link;
5. เขียน before/after projection harness ครบ SRS/Mastery/Weakness/global accuracy/XP/reward/quest/streak/achievement/Today/research-primary และบังคับ delta=0;
6. History group/label replay; latest/best normal ไม่ถูก overwrite;
7. รัน `TC-PMT-032–041` และ reward/history/Today regressions

**Exit:** stars reproducible/non-economic, incomplete unscored, replay visible but zero-authority/reward effect

### Task PM6 — Adaptive Standard UI, copy and accessibility (11 pd)

**Requirements:** UI-018–026, NFR-042/043, FR-106/112/116/119–127

**Files:**

- Create `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart`
- Create `lib/features/learning/pair_matching/presentation/pair_board_view.dart`
- Update `lib/screens/matching_mode_screen.dart` as compatibility wrapper only
- Add `test/features/learning/pair_matching/pair_board_view_test.dart`
- Add `test/features/learning/pair_matching/pair_board_accessibility_test.dart`
- Add responsive/localization goldens under existing approved golden structure

**Steps:**

1. implement setup card with source reason, 4/6, direction, timer default off and one primary CTA;
2. regular effective width renders bounded balanced columns; narrow/200%/assistive policy renders focused prompt-to-target list;
3. preserve command/evidence semantics across layouts; tiles 56px/compact 64px and actions 48×48 minimum;
4. wrong/repair state uses text+icon+border and supportive copy; no shake/loss/shame;
5. timeout primary action Continue untimed with approved Thai copy; result/history axes remain separate;
6. add TalkBack/Switch/keyboard/focus restoration/status announcement/reduced-motion/no-audio coverage;
7. validate Thai wrapping/combining marks, English locale and language-aware pronunciation labels;
8. รัน `TC-PMT-043`, golden matrix และ UAT-039–049 dry run on prototype fixtures

**Exit:** all Pair paths operable without sight/audio/precision gesture/forced timer and no semantic divergence by layout

### Task PM7 — Adventure renderer parity and bounded measurement (8 pd)

**Requirements:** FR-108/129/130, DATA-021, UI-027, NFR-044/045/046, BR-034

**Files:**

- Create `lib/features/adventure/presentation/adventure_pair_renderer.dart`
- Add `test/features/adventure/adventure_pair_renderer_parity_test.dart`
- Add/update research event projection tests only if Pair is inside an approved participant opportunity
- Add `test/features/learning/pair_matching/pair_measurement_boundary_test.dart`

**Steps:**

1. render the same immutable plan/ViewModel; permit only theme, companion, narrative and return-target differences;
2. normalize IDs/timestamps then compare commands, attempts, repair, timer, stars, evidence and terminal outcome against Standard;
3. participant uses neutral existing mission events/opportunity; restart/rebuild does not add denominator;
4. Practice Replay excluded from primary outcome and nonparticipant research row/outbox/upload stays zero;
5. bounded diagnostics omit raw word/meaning/DOB/guardian text and obey owner/retention policy;
6. simulate renderer failure/Adventure-off and continue through Standard with same checkpoint;
7. รัน `TC-PMT-038/042–044` และ UAT-050 rehearsal

**Exit:** normalized parity 100%, zero nonparticipant research rows, zero replay primary delta, safe Standard fallback

### Task PM8 — Compatibility rollout, G4P evidence and prototype sign-off (12 pd)

**Requirements:** all FR-105–130, DATA-016–021, UI-018–027, NFR-038–046, BR-024–034

**Files/evidence:**

- Update as-built SDS, RTM, Test Plan and UAT evidence links
- Add checkpoint v1–v5 plus next-version fixtures in the repository's existing codec test location
- Add feature/emergency-off integration fixtures without enabling production
- Archive G4P evidence under the approved build-evidence location; do not place private/raw vocabulary in docs

**Steps:**

1. reserve the actual next checkpoint version; Release A reads old+new and writes old;
2. run recovery/rollback matrix and set minimum compatible build; only then Release B may write new checkpoint under hidden f10 flag;
3. run PMT-001–044, UAT-039–050, 8/44 registry/navigation, learning/SRS/mastery/weakness/reward/history/Today and Adventure fallback regressions;
4. run `flutter analyze --no-pub lib test`, focused dependency/privacy checks and bounded manual diff review;
5. verify feature off, Pair emergency-off, Adventure-off, accepted-session close and unrelated Quiz modes;
6. reconcile RTM exactly 258/258 and record current build/commit/config/device evidence;
7. Product, Learning/Data, UX/Accessibility, QA and Tech choose Accept/Revise/Reject;
8. keep status Hidden/Internal; G4P does not authorize MS-08A/MS-08B or production enablement

**Exit:** signed G4P package, reproducible rollback and zero open S0/S1; otherwise Revise/Reject with owner/date

### Checkpoint 7 stop rule

PM0–PM5 เป็น contract/engine core และหยุดได้ก่อน Adventure renderer PM7 หาก parity/replay zero-delta/checkpoint budget ยังไม่ผ่าน PM6 prototype ห้ามเชื่อม production navigation ก่อน PM8 sign-off งาน Pair ห้ามเพิ่ม research migration และห้ามใช้ Pair result เป็น motivation efficacy evidenceโดยไม่มี protocol amendment

## 9. Pull Request and Commit Boundaries

Recommended PR sequence:

1. baseline test-seam remediation;
2. hidden feature/domain/catalog contracts;
3. read-only journey/composer/shell;
4. learning bridge/repair/recovery/result;
5. preference migration + lifecycle;
6. read-only motivation + companion;
7. research migration/domain/use cases;
8. participation permits/opportunities/neutral events/sync/rules/lifecycle;
9. offline/diagnostics/accessibility/performance;
10. Pilot evidence/as-built documentation;
11. Pair f10 characterization + immutable plan;
12. Pair reducer/repair/timer;
13. Pair stars/result/replay isolation;
14. Pair adaptive Standard UI;
15. Pair Adventure renderer/parity;
16. Pair checkpoint writer + G4P evidence/as-built docs

Each PR must include:

- Requirement IDs and WBS IDs;
- failing-test evidence before implementation;
- targeted and related-regression command results;
- schema/rules/protocol/version impact;
- owner/data/privacy/accessibility impact;
- feature-off/Standard fallback evidence;
- focused diff with unrelated user changes excluded;
- rollback/emergency-off effect

## 10. Final Definition of Done

- [ ] 8/44 catalog exact; Adventure is not f45
- [ ] feature hidden/default-off and Standard behavior equivalent
- [ ] no new bottom tab; `home/learn/today-experience` is the only production entry and hidden Learn layout is equivalent
- [ ] Product Entry sees only ActivePresentationPermit; zero raw consent/guardian/assent dependency; Research Capture has zero presentation mutation authority
- [ ] no `adventure_progress` or parallel learning/reward authority
- [ ] EvidenceContext and EventEnvelopeV2 keysets unchanged
- [ ] Adventure → Unified Lesson command/evidence equals Standard
- [ ] repair spacing/no-padding/restart/idempotency proven
- [ ] M07 has zero grant/mutation call path
- [ ] actual migration numbers reserved, forward-only and full fixtures green
- [ ] all four research tables have owner lifecycle, upgrade, sync, export/delete, withdrawal/retention and rules coverage
- [ ] minor permit runtime guardian+assent evidence, signature/expiry/revocation/offline checks proven
- [ ] nonparticipant zero-row and withdrawal-before-Host/start/enqueue proven
- [ ] neutral Standard/Adventure opportunity/events, transactional 1–10 switches and deterministic identities match ADR-003
- [ ] TodayHubView is pure and Host load count/snapshot identity/UUID reuse are proven
- [ ] accessibility/performance/offline/corrupt/emergency-off gates pass
- [ ] shared/touched foundation and Android Pilot gates pass; every excluded platform/capability is explicit and still blocked for its enablement
- [ ] MDS baseline/post timepoints, ANCOVA, MI/tipping, learning margins, missingness and powered class rules are applied without post-hoc relaxation
- [ ] MS-08A remains Limited and MS-08B decision/targeting is isolated per adult/minor class
- [ ] UAT ≥12 learners (minors ≥4), ≥4 accessibility sessions, adult comprehension 10/10 and ≥5 dyads with guardian/learner 5/5 meet exact thresholds
- [ ] Pair Matching remains f10 with contextual Learn/Today/Review/Adventure entry; no f45/main menu
- [ ] immutable exact 4/6 EN↔TH plan, no silent filler/downgrade and curated collision validation proven
- [ ] wrong/repair/tail-guided/Review handoff and pronunciation-versus-semantic-support roles proven
- [ ] timer default-off, active pause, +30 once, Continue untimed and same-session Restart survive recovery/races
- [ ] stars rebuild from terminal ledger and never act as currency/reward/mastery; incomplete is not zero-star
- [ ] Practice Replay zero delta across every prohibited authority/reward/research-primary projection
- [ ] regular/focused/accessibility/localization layouts have command/evidence parity
- [ ] Standard/Adventure normalized plan/engine/timer/repair/evidence/stars parity and safe fallback proven
- [ ] checkpoint reader-first/writer-later, actual version reservation and rollback matrix pass
- [ ] RTM 258/258 requirements, 188 test cases and 50 UAT scripts have current evidence and sign-off
- [ ] Product, QA, Tech, Accessibility, Research/Privacy and Release decisions recorded
