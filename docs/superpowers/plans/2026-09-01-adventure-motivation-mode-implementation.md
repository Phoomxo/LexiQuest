# Adventure Motivation Mode — Implementation Plan

> **Execution note:** แผนนี้เป็น blueprint สำหรับ session พัฒนาในอนาคต ไม่อนุญาตให้ implement Adventure จากงานเอกสารปัจจุบัน ผู้ลงมือควรใช้ skill `executing-plans` และทำทีละ checkpoint

**Goal:** เพิ่ม Adventure Motivation Mode เป็น optional presentation บน Today/learning authorities เดิม โดย Standard ยังคงเป็น fallback, evidence/reward semantics ไม่เปลี่ยน และ research data เกิดเฉพาะ consented protocol

**Architecture:** Hidden broad runtime feature + fail-closed entry decision → deterministic read-only journey projection → canonical Today session composer → existing Unified Lesson Controller → existing Learning Side Effect Reconciler → read-only result/motivation projection. Preference และ research เพิ่มแบบ staged migration หลัง read-only prototype ผ่าน โดยไม่สร้าง `adventure_progress`

**Tech Stack:** Flutter/Dart, Material 3, Drift/SQLite, existing owner/sync/export/event contracts, Firebase rules emulator, Node test tooling

**Authoritative documents:**

- `docs/adventure-motivation-mode/00a-current-system-audit.md`
- `docs/adventure-motivation-mode/01-tor.md`
- `docs/adventure-motivation-mode/02-srs.md`
- `docs/adventure-motivation-mode/03-sds.md`
- `docs/adventure-motivation-mode/04-project-plan-wbs.md`
- `docs/adventure-motivation-mode/05-ui-ux-design-spec-wireframes.md`
- `docs/adventure-motivation-mode/06-test-plan-and-test-cases.md`
- `docs/adventure-motivation-mode/07-uat-script.md`
- `docs/adventure-motivation-mode/08-requirements-traceability-matrix.md`

**Pinned baseline:** `99f7fb21`, feature catalog revision 1.3.0/hash `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`, Drift schema v22, EventEnvelopeV2 unchanged

---

## 0. Execution Guardrails

1. เริ่มจาก isolated worktree/branch `codex/...`; รัน `flutter pub get --offline` แล้วพิสูจน์ว่า `.dart_tool/package_config.json` อยู่ใน worktree นั้น
2. ห้ามแก้ production และ baseline-remediation ปะปน commit เดียวกัน
3. ใช้ TDD: เขียน failing test → รันให้เห็น failure ที่ถูกเหตุ → ทำ minimal implementation → รัน targeted + related regression → focused diff review
4. Adventure presentation ห้าม import Drift-generated rows หรือเรียก learning/reward repositories เพื่อ write
5. ห้ามเพิ่ม field Adventure ใน `EvidenceContext`, answer payload หรือ `EventEnvelopeV2`
6. ห้ามสร้าง `adventure_progress`, parallel vocabulary/SRS/mastery/reward ledger หรือ reward grant API
7. M07 อ่าน committed/pending receipts หลัง `LearningSideEffectReconciler` เท่านั้น
8. schema v23/v24 เป็นเลข “วางแผน”; ก่อน migration ต้องอ่าน ledger แล้ว reserve เลขจริง ถ้าถูกใช้ให้ rebase ขึ้น ห้ามแก้ released migration
9. Phase A ไม่มี schema; Phase B preference local; Phase C cloud preference/research หลัง rules/version cutoff พร้อม
10. Standard fallback ต้องอยู่ในทุก phase และ emergency-off ต้องทดสอบก่อน Pilot
11. ห้ามใช้ historical passing log แทน fresh evidence
12. ก่อน Pilot ต้องปิด 15 baseline failures และผ่าน Gitleaks/OSV/platform/model gates ตาม policy ที่อนุมัติ

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

### Task 0.4 — Close platform, model, fingerprint and supply-chain gates

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
2. Mobile Owner decides whether iOS uses a tracked Podfile or a documented alternative; make the platform contract test express that decision.
3. Prepare checksum-pinned model fixture using the approved model workflow and run benchmark/classifier certification separately from ordinary Flutter tests.
4. Replace synthetic secret-like fixtures with deterministic non-secret forms or add narrowly reviewed fingerprint allowlisting; rerun tracked-history Gitleaks.
5. Upgrade LM `datasets` to a fixed compatible version (≥5.0.1) and resolve/approve Voice optional-GPU findings before policy expiry; run affected backend suites and OSV.
6. Run default and serial full Flutter suites. Classify any new failure; target is zero unclassified failures.
7. Archive BG-01–BG-11 evidence and commit each owner area separately.

**Exit:** `G0A` for implementation; all items plus full clean gates required for `G0B` before Pilot

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

### Task 1.3 — Implement fail-closed entry decision and dependency contract

**Files:**

- Create: `lib/features/adventure/application/adventure_entry_use_cases.dart`
- Create: `lib/features/adventure/application/adventure_rollout_gate.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/runtime/production_feature_gate.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Create: `test/features/adventure/application/adventure_entry_use_cases_test.dart`
- Modify: `test/runtime/production_feature_gate_test.dart`
- Modify: `test/runtime/app_bootstrap_test.dart`

**Steps:**

1. Write the ENT-001–012 decision table as parameterized failing tests.
2. Implement `AdventureEntryDecision` with availability, effective presentation, treatment identity, fallback reason and version pins.
3. Require identity-consistent Today/Learning/catalog dependencies; missing/unknown/corrupt inputs resolve Standard.
4. Fence asynchronous resolution by owner/session generation.
5. Verify feature state never creates/changes assignment or preference.
6. Run entry, bootstrap, production gate and feature-off equivalence tests.

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
- Create: `lib/features/adventure/presentation/adventure_mission_sheet.dart`
- Create: `lib/features/adventure/presentation/widgets/adventure_map.dart`
- Create: `lib/features/adventure/presentation/widgets/adventure_map_list.dart`
- Create: `lib/features/adventure/presentation/widgets/adventure_status_panel.dart`
- Create: `lib/features/adventure/presentation/widgets/adventure_standard_switch.dart`
- Modify: `lib/screens/main_navigation_screen.dart`
- Create: `test/features/adventure/presentation/adventure_hub_screen_test.dart`
- Create: `test/features/adventure/presentation/adventure_map_list_parity_test.dart`
- Modify: `test/screens/main_navigation_screen_test.dart`

**Steps:**

1. Write widget tests for one primary mission, always-visible Standard switch, loading/empty/stale/corrupt/offline/unavailable, CTA single-flight and Map/List parity.
2. Render from `AdventureJourneySnapshot`; widgets receive callbacks/read models only.
3. Host Standard/Adventure at the same Today destination; never reuse `LearningWorldMapScreen` or stack duplicate home routes.
4. Use `M3Theme`, glossary keys, 48×48 targets and non-color state cues.
5. Add semantics/focus/text-200%/dark/high-contrast/reduced-motion golden/widget coverage.
6. Run navigation, Today Hub and all new widget tests.

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

**Checkpoint review:** Standard/Adventure command and evidence equivalence, duplicate count zero, assessment isolation, MS-04

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
- Modify: `lib/data/local/tables/research_tables.dart`
- Modify: `lib/data/local/app_database.dart`
- Generated: `lib/data/local/app_database.g.dart`
- Create tests under: `test/features/research/` and `test/database/`

**Steps:**

1. Require approved protocol/instrument/form/response-code catalog before implementation.
2. Read schema ledger and reserve the next actual number after preference migration; do not assume v24.
3. Write red migration tests for exactly `motivation_measurement_runs` and `motivation_responses`, v1→current fixtures, owner IDs, unique/idempotent constraints and unknown-code rejection.
4. Implement bounded domain models; no free text and no duplicated learning answer.
5. Add forward-only tables/migration and regenerate Drift code.
6. Run current/full migration matrix and exact table inventory.

### Task 5.2 — Add consent/assignment/run-gated measurement use cases

**Files:**

- Create: `lib/features/research/data/drift_motivation_measurement_repository.dart`
- Create: `lib/features/research/application/motivation_measurement_use_cases.dart`
- Create: `test/features/research/drift_motivation_measurement_repository_test.dart`
- Create: `test/features/research/motivation_measurement_use_cases_test.dart`
- Reference: `lib/runtime/registries/experiment_registry.dart`

**Steps:**

1. Encode RSH-001–003 as red decision-table tests; each incomplete gate must create zero row/outbox.
2. Implement owner-scoped idempotent run state machine with stable assignment and all version pins.
3. Check withdrawal immediately before persistence/enqueue, not only when screen opens.
4. Implement bounded response submit/skip; learning/reward/access remain unchanged.
5. Test duplicate submit, owner switch, withdrawal race and restart.

### Task 5.3 — Record exact consented Adventure exposure events

**Files:**

- Create: `lib/features/events/domain/adventure_event_payload_policy.dart`
- Create: `lib/features/research/application/adventure_behavior_event_recorder.dart`
- Create: `test/features/events/adventure_event_payload_policy_test.dart`
- Create: `test/features/research/adventure_behavior_event_recorder_test.dart`
- Reference/freeze: existing EventEnvelopeV2 files/tests under `lib/features/events/` and `test/features/events/`

**Steps:**

1. Write allowlist tests for exactly four v1 payloads: Presented, MissionStarted, SwitchedToStandard, MissionCompleted.
2. Assert EventEnvelopeV2 exact keyset unchanged.
3. Require active consent, stable assignment and active run; nonparticipant remains zero-row.
4. Correlate consented exposure with `aggregateId = learningSessionId`, `correlationId = adventurePlanId`; never persist origin into learning evidence.
5. Test replay idempotency, crossover without reassignment and privacy-redacted diagnostics.

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

1. Write failing manifest cardinality test: each new owner row appears exactly once; preserved global content unchanged.
2. Add guest-upgrade conflict/replay, export-axis, deletion-order, owner-isolation and retention/withdrawal tests.
3. Add versioned bounded sync payloads and incompatible replay rejection.
4. Write rules-emulator tests before rules: owner only, schema allowlist, bounded keys/codes, immutable assignment pins and denied unauthorized/unknown writes.
5. Implement minimal lifecycle/sync/rules changes and run Firestore/Auth emulator suites.
6. Reconstruct an ITT/crossover export fixture with 100% required metadata.

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
4. Measure entry p95 ≤50ms, projection p95 ≤100ms, render p95 ≤1.5s, added start overhead p95 ≤150ms, event commit p95 ≤100ms and frame/long-task budget on certified profiles.
5. Verify packaged visuals ≤5MB and audio separately downloadable.
6. Resolve every S0/S1 accessibility/performance issue before Internal UAT.

### Task 6.3 — Run the complete verification pyramid

**Commands/gates:**

1. exact 8/44 feature-map check;
2. `flutter analyze --no-pub lib test` with any info-level disposition recorded;
3. targeted adventure/domain/widget/architecture/scenario tests;
4. current authority suites: Today, Learning, SRS, Mastery, Weakness, Quest, Streak, Achievement, Reward, Owner, Sync, Export;
5. full Flutter suite default and serial;
6. AI, Voice, LM and affected backend suites;
7. Firestore/Auth emulator suites;
8. tracked-history Gitleaks, OSV/dependency audits under approved scopes;
9. platform contracts and field-model certification;
10. focused diff, generated-code check, schema/table/manifest cardinality and feature-off comparison

**Pass:** BG-01–BG-12 all green with fresh commit/build/environment evidence

### Task 6.4 — Execute UAT and rollout rehearsal

**Files:**

- Execute/update: `docs/adventure-motivation-mode/07-uat-script.md`
- Update actual links/status: `docs/adventure-motivation-mode/08-requirements-traceability-matrix.md`
- Update as-built: `docs/adventure-motivation-mode/03-sds.md`

**Steps:**

1. Internal UAT: UAT-001–024 and 030–032; no open S0/S1.
2. Complete ethics/guardian/assent approvals where applicable.
3. Pilot UAT: UAT-025–029; nonparticipant zero-row and withdrawal cutoff must be 100%.
4. Rehearse emergency-off twice: before Pilot and before Enabled.
5. Roll out Hidden → Internal → Pilot → Enabled using bounded increments with Continue/Hold/Rollback decision each time.
6. Update RTM statuses only from current evidence; archive decision log and unresolved backlog separately.

## 8. Pull Request and Commit Boundaries

Recommended PR sequence:

1. baseline test-seam remediation;
2. hidden feature/domain/catalog contracts;
3. read-only journey/composer/shell;
4. learning bridge/repair/recovery/result;
5. preference migration + lifecycle;
6. read-only motivation + companion;
7. research migration/domain/use cases;
8. exposure events/sync/rules/lifecycle;
9. offline/diagnostics/accessibility/performance;
10. Pilot evidence/as-built documentation

Each PR must include:

- Requirement IDs and WBS IDs;
- failing-test evidence before implementation;
- targeted and related-regression command results;
- schema/rules/protocol/version impact;
- owner/data/privacy/accessibility impact;
- feature-off/Standard fallback evidence;
- focused diff with unrelated user changes excluded;
- rollback/emergency-off effect

## 9. Final Definition of Done

- [ ] 8/44 catalog exact; Adventure is not f45
- [ ] feature hidden/default-off and Standard behavior equivalent
- [ ] no `adventure_progress` or parallel learning/reward authority
- [ ] EvidenceContext and EventEnvelopeV2 keysets unchanged
- [ ] Adventure → Unified Lesson command/evidence equals Standard
- [ ] repair spacing/no-padding/restart/idempotency proven
- [ ] M07 has zero grant/mutation call path
- [ ] actual migration numbers reserved, forward-only and full fixtures green
- [ ] owner lifecycle, upgrade, sync, export/delete and rules complete
- [ ] nonparticipant zero-row and withdrawal-before-enqueue proven
- [ ] accessibility/performance/offline/corrupt/emergency-off gates pass
- [ ] all 15 baseline failures closed; Gitleaks/OSV/platform/model gates pass
- [ ] UAT comprehension and defect thresholds pass
- [ ] RTM 174/174 requirements has current evidence and sign-off
- [ ] Product, QA, Tech, Accessibility, Research/Privacy and Release decisions recorded
