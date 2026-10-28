# LexiQuest Real Local-First Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an Android functional prototype in which every visible
LexiQuest feature uses real persisted data, a real device API, a deterministic
algorithm, or an explicitly configured provider, with no fabricated production
result.

**Architecture:** Drift/SQLite is the local source of truth and an idempotent
outbox synchronizes registered-user data to Firebase. Provider-independent
application services isolate Flutter screens from Firebase, Gemini, camera,
speech, TensorFlow Lite, secure storage, and file APIs. Device capability
policy selects CPU/XNNPACK or Android GPU execution without changing feature
meaning.

**Tech Stack:** Flutter 3.44.7, Dart 3.12.2, Android 10+, Drift/SQLite,
Firebase Auth/Firestore/Functions/App Check, Android WorkManager,
TensorFlow Lite, Android camera/TTS/STT, Gemini REST API with user-owned key,
Material 3.

## Global Constraints

- Platform is Android 10 or newer.
- Baseline device is 4 GB RAM with 2 GB available storage.
- Application version remains `0.1.0`; distributed builds increment build
  number.
- Firebase is the only account and synchronization platform.
- Gemini is the only AI provider and uses a user-supplied key.
- Drift/SQLite is the local source of truth.
- Supabase is absent from runtime and Android build inputs.
- Production code contains no mock, sample-history, simulated sensor, random
  inference, placeholder transaction, or canned AI response path.
- Curated learning packs are versioned product content and identify their
  source.
- Missing capability or configuration produces a truthful unavailable state.
- Screens consume injected application interfaces, not Firebase, HTTP,
  secure-storage, camera, speech, or inference plugins directly.
- Thai copy is natural UTF-8 and all screens use the central Material 3 system.
- No password, email, token, action code, Gemini key, prompt, vocabulary,
  captured image, or raw audio is written to logs.
- No branch created for this work contains `codex`.
- Do not invoke Codex Security workflows; use repository-approved bounded
  local verification.
- Do not retry a repeated filesystem/tool failure; stop and report according
  to `AGENTS.md`.

## Verification Strategy

This program intentionally avoids a full-test loop after every subheading.

1. Implementers add or update focused tests with their work package.
2. Mechanical compile/format checks may run during implementation.
3. A single consolidated verification gate runs at the end of each Phase.
4. Full `tool/cli/verify.ps1` runs only after Phases 3, 7, and 10.
5. Physical-device checks run after Phases 4 and 10.
6. A failed phase gate blocks the next Phase and is fixed in one review wave.

---

## Phase 0 — Freeze the Prototype Baseline

### Purpose

Close the interrupted Plan 2 broad review, record the exact baseline, and
replace the previous production-ready claim with the approved functional
prototype contract.

### Work package 0.1 — Bounded Plan 2 final review

**Files:**

- Read: `docs/superpowers/plans/2026-07-29-v0.1-navigation-accounts.md`
- Read: `.superpowers/sdd/plan-2-final-review-package.diff`
- Update: `.superpowers/sdd/progress.md`
- Create: `.superpowers/sdd/plan-2-final-reviewer-report.md`

**Actions:**

- [ ] Review only tracked files from the existing review package.
- [ ] Do not recursively enumerate `build/`, `.dart_tool/`, or volatile plugin
  transform directories.
- [ ] Resolve Critical and Important cross-task account findings in one fix
  wave.
- [ ] Record Plan 2 final review as complete only after re-review approval.

### Work package 0.2 — Prototype contract and inventory

**Files:**

- Use: `docs/superpowers/specs/2026-07-30-real-local-first-prototype-design.md`
- Create: `docs/prototype/feature-inventory.md`
- Create: `tool/cli/tests/prototype-production-paths.tests.ps1`

**Actions:**

- [ ] Inventory every production route, data source, dependency, permission,
  offline behavior, and unavailable state.
- [ ] Classify confirmed blockers: direct remote screen calls, legacy routes,
  sample/simulation paths, screen-local economy, missing secure AI key, and
  missing real device adapters.
- [ ] Add bounded scans that reject known production sample/simulation markers
  while allowing test fakes and documented curated packs.

### Phase 0 gate

Run once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1
flutter analyze
flutter test test/account test/navigation test/screens/session_gate_screen_test.dart --reporter compact
```

Exit criteria:

- Plan 2 broad review approved.
- Feature inventory maps every visible menu item.
- Prototype contract scan is committed and initially reports the known
  remaining production blockers precisely.

---

## Phase 1 — Canonical Local Data and Offline Synchronization

### Purpose

Make all learning data durable on-device and provide a complete, retryable
Firebase synchronization path.

### Work package 1.1 — Complete the Drift schema

**Files:**

- Modify: `lib/learning/storage/learning_database.dart`
- Modify: `lib/learning/storage/drift_learning_repository.dart`
- Create: `lib/data/local/vocabulary_local_repository.dart`
- Create: `lib/data/local/progress_projection_repository.dart`
- Create: `lib/data/local/economy_projection_repository.dart`
- Create: `lib/data/local/content_pack_repository.dart`
- Test: `test/data/local/`

**Actions:**

- [ ] Add canonical tables for categories, vocabulary, imports, review events,
  progress projections, weakness projections, economy projections, ownership,
  equipment, content packs, export jobs, migration state, and conflicts.
- [ ] Preserve immutable learning events and stable primary keys.
- [ ] Add repository transactions for lesson completion and derived
  projections.
- [ ] Ensure guest and registered owner IDs are explicit in every owned table.

### Work package 1.2 — Implement the sync state machine

**Files:**

- Modify: `lib/learning/sync_outbox_entry.dart`
- Create: `lib/sync/sync_models.dart`
- Create: `lib/sync/sync_repository.dart`
- Create: `lib/sync/sync_worker.dart`
- Create: `lib/sync/sync_conflict_policy.dart`
- Create: `lib/sync/connectivity_monitor.dart`
- Create: `lib/sync/firebase_sync_adapter.dart`
- Test: `test/sync/`

**Actions:**

- [ ] Implement pending, in-flight, acknowledged, retryable-failure,
  permanent-failure, and conflict states.
- [ ] Implement bounded exponential backoff with jitter.
- [ ] Make remote operations idempotent by operation ID.
- [ ] Implement event merge, revision conflict copy, and tombstone rules.
- [ ] Trigger foreground sync after boot, sign-in, manual retry, and restored
  connectivity.

### Work package 1.3 — Android background sync

**Files:**

- Create: `lib/sync/background_sync_scheduler.dart`
- Modify: `lib/main.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Test: `test/sync/background_sync_scheduler_test.dart`
- Test: `integration_test/offline_reconnect_sync_test.dart`

**Actions:**

- [ ] Register one unique Android WorkManager job with network constraints.
- [ ] Prevent concurrent foreground/background flushes.
- [ ] Bound attempts, duration, and batch size.
- [ ] Keep local lesson completion independent from worker success.

### Work package 1.4 — Guest ownership migration

**Files:**

- Create: `lib/sync/guest_data_migrator.dart`
- Modify: `lib/account/account_models.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Test: `test/sync/guest_data_migrator_test.dart`

**Actions:**

- [ ] Reassign guest-owned records transactionally to the linked account.
- [ ] Persist a stable migration operation ID before mutation.
- [ ] Resume after interruption without duplicate events.
- [ ] Queue migrated records through the standard outbox.

### Phase 1 gate

Run once:

```powershell
flutter test test/learning test/data/local test/sync test/progress --reporter compact
npm run test:rules
npm run test:functions-emulator
flutter test integration_test/offline_reconnect_sync_test.dart -d windows --timeout 3m
```

Exit criteria:

- A lesson completes offline, survives restart, and syncs once after reconnect.
- Guest upgrade preserves local learning data.
- Duplicate delivery and revision conflict scenarios are proven.

---

## Phase 2 — Real Vocabulary, Reading, and Practice Flows

### Purpose

Move every core learning screen to canonical local repositories and remove
screen-local sample content and direct Firebase/HTTP calls.

### Work package 2.1 — Vocabulary ownership

**Files:**

- Modify: `lib/screens/categories_page.dart`
- Modify: `lib/screens/add_vocab_screen.dart`
- Modify: `lib/screens/main_vocabulary.dart`
- Modify: `lib/screens/vocab_list_screen.dart`
- Modify: `lib/screens/add_multiple_words_screen.dart`
- Modify: `lib/screens/wordbook_import_screen.dart`
- Create: `lib/vocabulary/vocabulary_service.dart`
- Test: `test/vocabulary/`

**Actions:**

- [ ] Replace direct Firebase and screen HTTP access with injected use cases.
- [ ] Support create, edit, delete, bulk entry, import, tombstone, restart, and
  empty states.
- [ ] Read UI state from Drift projections.

### Work package 2.2 — Assessment event pipeline

**Files:**

- Modify: `lib/screens/quiz_screen.dart`
- Modify: `lib/screens/score_screen.dart`
- Modify: `lib/screens/result_screen.dart`
- Modify: `lib/screens/select_category_for_quiz.dart`
- Modify: `lib/services/quiz_service.dart`
- Create: `lib/learning/assessment_session_service.dart`
- Test: `test/learning/assessment_session_service_test.dart`

**Actions:**

- [ ] Build distractors only from valid vocabulary records.
- [ ] Persist each answer and one completed-session event.
- [ ] Make completion idempotent across double taps and restart.
- [ ] Derive progress and weakness projections from committed events.

### Work package 2.3 — SRS and adaptive practice

**Files:**

- Modify: `lib/screens/srs_flashcards_screen.dart`
- Modify: `lib/screens/weakness_clinic_screen.dart`
- Modify: `lib/services/srs_service.dart`
- Modify: `lib/services/weakness_clinic_service.dart`
- Modify: `lib/services/zpd_recommender_service.dart`
- Create: `lib/learning/adaptive_practice_service.dart`
- Test: `test/learning/adaptive_practice_service_test.dart`

**Actions:**

- [ ] Derive scheduling from persisted review events.
- [ ] Use real learner weakness data for recommendations.
- [ ] Remove screen-local synthetic history and random recommendation noise.

### Work package 2.4 — Real reading content

**Files:**

- Modify: `lib/services/cefr_interactive_storybook_service.dart`
- Modify: `lib/screens/interactive_storybook_screen.dart`
- Modify: `lib/screens/cefr_article_reader_screen.dart`
- Modify: `lib/screens/associative_reading_session_screen.dart`
- Create: `assets/content/manifest.json`
- Create: `lib/content/versioned_content_pack_service.dart`
- Test: `test/content/`

**Actions:**

- [ ] Replace `_sampleChapters` with a versioned curated pack.
- [ ] Persist reading position and completion events.
- [ ] Record curated or Gemini-generated source metadata.
- [ ] Show a truthful empty/unavailable state when a pack is absent.

### Phase 2 gate

Run once:

```powershell
flutter test test/vocabulary test/learning test/content --reporter compact
flutter test test/screens/full_system_audit_test.dart --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1
```

Exit criteria:

- Core learning journeys use persisted real records.
- No vocabulary, quiz, SRS, weakness, or reading screen depends on sample
  history or direct Firebase/HTTP construction.

---

## Phase 3 — Device Capability, CPU/GPU, Camera, and Speech

### Purpose

Use each phone's real CPU/GPU and Android device services while remaining
stable on the baseline device.

### Work package 3.1 — Capability policy

**Files:**

- Create: `lib/device/device_capability_models.dart`
- Create: `lib/device/device_capability_probe.dart`
- Create: `lib/device/inference_policy.dart`
- Create: `android/app/src/main/kotlin/com/lexiquest/app/DeviceCapabilityPlugin.kt`
- Modify: `lib/runtime/app_dependencies.dart`
- Test: `test/device/`

**Actions:**

- [ ] Probe Android version, ABI, memory class, free storage, battery saver,
  and thermal state.
- [ ] Run a bounded benchmark and assign Lite, Balanced, or Enhanced.
- [ ] Attempt GPU delegate only when supported and benchmarked.
- [ ] Fall back to XNNPACK CPU without changing label semantics.

### Work package 3.2 — Real object scanner

**Files:**

- Modify: `lib/screens/object_scanner_screen.dart`
- Replace: `lib/services/ml_image_labeling_service.dart`
- Create: `lib/vision/camera_controller_adapter.dart`
- Create: `lib/vision/tflite_image_labeler.dart`
- Create: `assets/models/object_labeler.tflite`
- Create: `assets/models/object_labeler.metadata.json`
- Test: `test/vision/`
- Test: `integration_test/object_scanner_device_test.dart`

**Actions:**

- [ ] Implement permission, preview, capture, lifecycle, and camera error states.
- [ ] Verify model checksum before activation.
- [ ] Run inference on GPU or CPU according to policy.
- [ ] Require confidence threshold and user confirmation before saving.
- [ ] Remove the simulation button and random confidence values.

### Work package 3.3 — Real speech and pronunciation

**Files:**

- Modify: `lib/screens/speak_to_text_screen.dart`
- Modify: `lib/screens/shadowing_challenge_screen.dart`
- Modify: `lib/services/phoneme_alignment_clinic_service.dart`
- Create: `lib/speech/speech_recognition_adapter.dart`
- Create: `lib/speech/pronunciation_evaluator.dart`
- Test: `test/speech/`
- Test: `integration_test/speech_device_test.dart`

**Actions:**

- [ ] Implement microphone permission and recognizer availability.
- [ ] Use captured recognition results and real audio-derived measurements.
- [ ] Label edit-distance or heuristic feedback as an estimate.
- [ ] Remove random pitch curves and simulated phoneme measurements.
- [ ] Release recorder and playback resources on lifecycle changes.

### Work package 3.4 — Model lifecycle

**Files:**

- Create: `lib/device/model_pack_manager.dart`
- Create: `lib/device/model_pack_manifest.dart`
- Test: `test/device/model_pack_manager_test.dart`

**Actions:**

- [ ] Implement consent, storage check, pause, resume, retry, checksum, atomic
  activation, rollback, and deletion.
- [ ] Keep bundled baseline inference operational without an optional pack.

### Phase 3 gate

Run once:

```powershell
flutter test test/device test/vision test/speech test/voice --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
```

Physical Android gate:

- Camera permission, preview, capture, CPU inference, and supported GPU
  inference.
- TTS, STT, background/foreground transitions, denial, and cancellation.
- Ten-minute thermal and memory smoke run before the later 30-minute gate.

---

## Phase 4 — Gemini BYOK and AI Features

### Purpose

Connect every AI entry point to the user's real Gemini key without placing a
provider secret in the APK.

### Work package 4.1 — Secure key lifecycle

**Files:**

- Create: `lib/ai/gemini_key_store.dart`
- Create: `lib/ai/secure_gemini_key_store.dart`
- Create: `lib/screens/gemini_settings_screen.dart`
- Modify: `lib/navigation/app_route.dart`
- Modify: `lib/navigation/app_router.dart`
- Test: `test/ai/gemini_key_store_test.dart`
- Test: `test/screens/gemini_settings_screen_test.dart`

**Actions:**

- [ ] Store only in Android Keystore-backed secure storage.
- [ ] Implement save, validate, replace, delete, and unavailable states.
- [ ] Never persist the key in Drift, preferences, Firebase, logs, exports, or
  build defines.

### Work package 4.2 — Gemini adapter

**Files:**

- Modify: `lib/ai/ai_models.dart`
- Create: `lib/ai/gemini_provider.dart`
- Create: `lib/ai/gemini_error_mapper.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Test: `test/ai/gemini_provider_test.dart`

**Actions:**

- [ ] Implement bounded REST requests and response validation.
- [ ] Distinguish invalid key, quota, model, offline, timeout, and outage.
- [ ] Redact key, prompts, responses, headers, and query values.
- [ ] Cancel requests when their screen is disposed.

### Work package 4.3 — Remove canned AI behavior

**Files:**

- Modify: `lib/screens/ai_tutor_screen.dart`
- Modify: `lib/ai/generated_reading_content_source.dart`
- Modify: `lib/services/dynamic_story_contextualizer_service.dart`
- Test: `test/ai/ai_feature_integration_test.dart`

**Actions:**

- [ ] Route live tutor and generation through `AiProvider`.
- [ ] Replace canned replies with actionable unavailable states.
- [ ] Label curated offline reading content accurately.
- [ ] Persist accepted generated content with source and safety metadata.

### Phase 4 gate

Run once:

```powershell
flutter test test/ai test/screens/gemini_settings_screen_test.dart --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/model-loading-security.tests.ps1
```

Exit criteria:

- Key lifecycle works on a physical Android device.
- APK/source/build scans contain no Gemini key.
- Live AI never produces a canned result when Gemini is unavailable.

---

## Phase 5 — Progress, Games, and Trusted Economy

### Purpose

Make every game and reward consume canonical learner data and trusted,
idempotent operations.

### Work package 5.1 — Canonical progress projection

**Files:**

- Modify: `lib/screens/learning_world_map_screen.dart`
- Modify: `lib/screens/mastery_dashboard_screen.dart`
- Modify: `lib/screens/achievements_screen.dart`
- Modify: `lib/services/achievement_service.dart`
- Modify: `lib/services/streak_and_daily_quest_service.dart`
- Create: `lib/progress/canonical_progress_service.dart`
- Test: `test/progress/canonical_progress_service_test.dart`

**Actions:**

- [ ] Derive nodes, mastery, streaks, quests, ranks, and achievements from
  immutable events.
- [ ] Persist award operation IDs to prevent duplicate rewards.

### Work package 5.2 — Real game inputs

**Files:**

- Modify: `lib/screens/boss_battle_screen.dart`
- Modify: `lib/screens/ghost_shadow_duel_screen.dart`
- Modify: `lib/services/ghost_shadow_duel_service.dart`
- Test: `test/game/`

**Actions:**

- [ ] Use persisted weakness words and mastery state.
- [ ] Make the opponent deterministic from documented bot rules.
- [ ] Remove `_sampleWords` and screen-local reward authority.

### Work package 5.3 — Trusted purchase and ownership

**Files:**

- Create: `functions/src/economy_writer.ts`
- Create: `functions/src/economy_writer.test.ts`
- Modify: `functions/src/index.ts`
- Modify: `functions/src/firestore_economy_store.ts`
- Modify: `lib/progress/purchase_remote_writer.dart`
- Modify: `lib/screens/shop_page.dart`
- Modify: `lib/screens/avatar_equipment_screen.dart`
- Modify: `lib/screens/select_wallpaper_screen.dart`
- Modify: `lib/services/avatar_equipment_service.dart`
- Test: `functions/test/`
- Test: `test/economy/`

**Actions:**

- [ ] Validate point credits, debit, ownership, duplicate prevention, and
  equipment operations in trusted Functions.
- [ ] Queue offline purchase intent without claiming success before trusted
  acknowledgement.
- [ ] Persist ownership and equipment projections.
- [ ] Remove placeholder shop and pre-equipped sample state.

### Phase 5 gate

Run once:

```powershell
flutter test test/progress test/game test/economy --reporter compact
npm --prefix functions test
npm run test:functions-emulator
npm run test:rules
```

Exit criteria:

- Games use real learner records.
- Client cannot mint or spend authoritative currency directly.
- Duplicate reward and purchase operations are idempotent.

---

## Phase 6 — Research, Analytics, and Real Exports

### Purpose

Replace sample export cards and fabricated observations with reproducible
artifacts generated from selected persisted records.

### Work package 6.1 — Export dataset builder

**Files:**

- Create: `lib/export/export_dataset_builder.dart`
- Create: `lib/export/export_manifest.dart`
- Modify: `lib/services/research_data_exporter_service.dart`
- Test: `test/export/export_dataset_builder_test.dart`

**Actions:**

- [ ] Select signed-in or explicit guest datasets.
- [ ] Include schema version, time zone, app version, build ID, filters, and
  sync state.
- [ ] Produce an explained empty dataset when no records match.

### Work package 6.2 — Export formats and sharing

**Files:**

- Modify: `lib/screens/export_center_screen.dart`
- Modify: `lib/services/pdf_glossary_exporter_service.dart`
- Modify: `lib/services/anki_dictionary_exporter_service.dart`
- Modify: `lib/services/thesis_appendix_exporter_service.dart`
- Modify: `lib/services/research_report_pdf_exporter_service.dart`
- Create: `lib/export/export_file_service.dart`
- Test: `test/export/`

**Actions:**

- [ ] Remove `_sampleCards`.
- [ ] Generate CSV, SPSS-style, PDF, glossary, Anki/dictionary, appendix, and
  chart data from the dataset builder.
- [ ] Handle storage, cancellation, write failure, and partial cleanup.

### Work package 6.3 — Analytics screens

**Files:**

- Modify: `lib/screens/thesis_chart_screen.dart`
- Modify: `lib/screens/mastery_dashboard_screen.dart`
- Test: `test/screens/research_analytics_screen_test.dart`

**Actions:**

- [ ] Render persisted observations only.
- [ ] Display sample size and missing-data explanations.
- [ ] Keep research calculations deterministic and unit-tested.

### Phase 6 gate

Run once:

```powershell
flutter test test/export test/services/research_data_exporter_service_test.dart test/screens/research_analytics_screen_test.dart --reporter compact
```

Exit criteria:

- Every export is reproducible from a real selected dataset.
- Empty and cancelled exports are truthful and recoverable.

---

## Phase 7 — Typed Navigation and Unified Material 3 UI

### Purpose

Give every feature one guarded production entry point and eliminate mixed old
and new UI systems.

### Work package 7.1 — Complete the route registry

**Files:**

- Modify: `lib/navigation/app_route.dart`
- Modify: `lib/navigation/app_router.dart`
- Modify: `lib/screens/main_navigation_screen.dart`
- Modify: all production files still using `MaterialPageRoute`
- Test: `test/navigation/complete_route_inventory_test.dart`

**Actions:**

- [ ] Add five top-level destinations: Learn, Progress, Weakness, Rewards,
  Profile.
- [ ] Add one typed route for every inventory item.
- [ ] Add auth, verification, guest, capability, and provider guards.
- [ ] Remove direct legacy route construction.

### Work package 7.2 — Remove screen remote boundaries

**Files:**

- Modify: all production screens still importing Firebase or HTTP.
- Modify: `lib/runtime/app_dependencies.dart`
- Test: `test/architecture/presentation_boundary_test.dart`

**Actions:**

- [ ] Move remote calls behind injected application interfaces.
- [ ] Add a structural test prohibiting Firebase/HTTP/plugin imports under
  `lib/screens/`.

### Work package 7.3 — Shared visual system

**Files:**

- Modify: `lib/config/m3_theme.dart`
- Create: `lib/ui/lexi_page_scaffold.dart`
- Create: `lib/ui/lexi_states.dart`
- Create: `lib/ui/lexi_form.dart`
- Modify: all route-inventory screens
- Test: `test/accessibility/`

**Actions:**

- [ ] Apply one spacing, radius, button, form, card, loading, empty, error,
  offline, and unavailable system.
- [ ] Remove decorative AI-style gradients, emoji-heavy headings, and mixed
  component families.
- [ ] Validate Thai/Latin metrics, text scaling, touch targets, labels, and
  contrast.

### Phase 7 gate

Run once:

```powershell
flutter test test/navigation test/architecture test/accessibility test/screens/full_system_audit_test.dart --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
```

Exit criteria:

- Every menu is reachable and guarded.
- No production screen imports Firebase/HTTP or uses `MaterialPageRoute`.
- Confirmed sample/simulation/placeholder paths are zero.
- Screenshot inventory shows one visual system.

---

## Phase 8 — Migration, Diagnostics, Privacy, and Budget Controls

### Purpose

Preserve existing user data, expose truthful runtime health, and bound cloud
cost and data handling.

### Work package 8.1 — Restart-safe migration

**Files:**

- Create: `lib/migration/prototype_migration_service.dart`
- Create: `lib/migration/migration_quarantine_repository.dart`
- Create: `test/fixtures/migrations/`
- Test: `test/migration/`

**Actions:**

- [ ] Migrate representative legacy vocabulary, SRS, progress, and preferences.
- [ ] Deduplicate with documented keys.
- [ ] Quarantine unconvertible records and support diagnostic export.
- [ ] Commit schema marker only after the transaction succeeds.
- [ ] Prove restart and rollback.

### Work package 8.2 — Runtime health and privacy

**Files:**

- Create: `lib/runtime/runtime_health_service.dart`
- Create: `lib/screens/runtime_health_screen.dart`
- Create: `docs/prototype/privacy-notice-th.md`
- Test: `test/runtime/runtime_health_service_test.dart`

**Actions:**

- [ ] Report local DB, sync, Firebase, Gemini, camera model, speech, and voice
  availability.
- [ ] Provide actionable recovery without exposing secrets or personal data.
- [ ] Add invited-test privacy, deletion, support, and feedback information.

### Work package 8.3 — Budget controls

**Files:**

- Modify: trusted Firebase Functions configuration and tests.
- Create: `docs/runbooks/prototype-cloud-budget.md`
- Modify: production release contracts.

**Actions:**

- [ ] Record THB 1,000 monthly ceiling.
- [ ] Configure and evidence 50%, 80%, and 100% alerts.
- [ ] Enforce request-size, per-user, per-device, and daily discretionary
  quotas.
- [ ] Limit optional Cloud Run service to scale-to-zero and one maximum
  instance.
- [ ] Document and test a kill switch preserving offline learning.

### Phase 8 gate

Run once:

```powershell
flutter test test/migration test/runtime --reporter compact
npm --prefix functions test
npm run test:functions-emulator
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/production-release-workflow.tests.ps1
```

Exit criteria:

- Representative old data migrates without uninstall.
- Health UI never reports unavailable systems as ready.
- Budget owner, alerts, quotas, shutdown, and rollback steps are recorded.

---

## Phase 9 — Integrated Prototype Journeys

### Purpose

Validate cross-system behavior without repeating every lower-level suite.

### Work package 9.1 — Automated journeys

**Files:**

- Create: `integration_test/prototype_learning_journey_test.dart`
- Create: `integration_test/prototype_guest_upgrade_test.dart`
- Create: `integration_test/prototype_ai_key_test.dart`
- Create: `integration_test/prototype_purchase_export_test.dart`
- Modify: `tool/cli/verify.ps1`
- Modify: `.github/workflows/ci.yml`

**Journeys:**

- [ ] Register, verify, sign in, change/reset password, and sign out.
- [ ] Complete a lesson offline, restart, reconnect, and sync once.
- [ ] Learn as guest, upgrade, and preserve records.
- [ ] Save, validate, replace, and delete a Gemini key.
- [ ] Scan and confirm a real object on Android.
- [ ] Complete TTS/STT/pronunciation fallback paths.
- [ ] Earn a trusted reward, purchase once, equip, and restore after restart.
- [ ] Export selected records and handle share cancellation.

### Work package 9.2 — Demonstration script

**Files:**

- Create: `docs/prototype/demo-script-th.md`
- Create: `docs/prototype/known-limitations.md`

**Actions:**

- [ ] Define a 15–20 minute repeatable academic demonstration.
- [ ] Separate real connected behavior from external owner-gated behavior.
- [ ] Include offline and unavailable-state demonstrations.

### Phase 9 gate

Run once:

```powershell
flutter test integration_test/prototype_learning_journey_test.dart -d windows --timeout 5m
flutter test integration_test/prototype_guest_upgrade_test.dart -d windows --timeout 5m
flutter test integration_test/prototype_ai_key_test.dart -d windows --timeout 5m
flutter test integration_test/prototype_purchase_export_test.dart -d windows --timeout 5m
```

Android-only scanner and speech journeys run on the physical test device.

Exit criteria:

- Every demonstration journey finishes from a clean app state.
- Failures identify their dependency and recovery action.

---

## Phase 10 — Signed APK and Prototype Acceptance

### Purpose

Produce the exact signed prototype APK, verify it on representative devices,
and package evidence for the academic review.

### Work package 10.1 — Release candidate

**Files:**

- Modify: `pubspec.yaml` build number.
- Create: `docs/prototype/releases/v0.1-prototype-evidence.md`
- Create: `docs/prototype/releases/v0.1-prototype-rollback.md`

**Actions:**

- [ ] Freeze dependency lockfiles and exact commit.
- [ ] Run complete verification from a clean committed HEAD.
- [ ] Build a release-signed APK with production identifiers and no secret.
- [ ] Record build command, signer fingerprint, APK size, SHA-256, build ID,
  schema version, and rollback artifact.

### Work package 10.2 — Physical-device matrix

**Devices:**

- Android 10 / 4 GB baseline.
- Mid-tier 6 GB device.
- Enhanced device with supported GPU delegate.

**Actions:**

- [ ] Install, first launch, upgrade, restart, background/foreground, and
  uninstall/reinstall behavior.
- [ ] Run offline learning and reconnect sync.
- [ ] Run camera, CPU inference, supported GPU inference, TTS, STT, Gemini,
  purchase, and export journeys.
- [ ] Complete a 30-minute session without OOM or sustained severe thermal
  state.
- [ ] Verify Firebase email actions and Android App Links with the release
  certificate.

### Work package 10.3 — Invited prototype handoff

**Files:**

- Create: `docs/prototype/tester-guide-th.md`
- Create: `docs/prototype/feedback-template-th.md`

**Actions:**

- [ ] Package consent/privacy, install instructions, support channel, known
  limitations, feedback path, and rollback instructions.
- [ ] Begin with a three-device owner smoke test.
- [ ] Expand to the invited group only after the owner smoke gate passes.

### Phase 10 final gate

Run once from clean committed HEAD:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
flutter analyze
flutter test --reporter compact
flutter build apk --release --dart-define=LEXIQUEST_VERSION=0.1.0+2
```

The candidate is accepted only when:

- every Phase gate is recorded as passed;
- all production routes are reachable;
- production path scans report no fabricated behavior;
- physical-device journeys pass;
- remote Firebase/App Link owner gates pass;
- APK hash and rollback artifact are recorded.

---

## Execution Order and Dependencies

1. Phase 0 must close before implementation resumes.
2. Phase 1 blocks Phases 2, 5, 6, and 8.
3. Phase 2 blocks progress/game integration in Phase 5.
4. Phase 3 can begin after Phase 1 and blocks Android device acceptance.
5. Phase 4 can begin after Phase 1 and blocks AI journey acceptance.
6. Phases 5 and 6 begin after canonical records from Phases 1–2 exist.
7. Phase 7 begins after feature interfaces stabilize.
8. Phase 8 begins after schema and remote contracts stabilize.
9. Phase 9 integrates all prior phases.
10. Phase 10 is the only signed prototype distribution gate.

Only one implementation subagent works in the shared worktree at a time. Each
Phase receives one implementer/reviewer cycle and one consolidated fix wave,
instead of a full-test/review loop for every work-package bullet.
