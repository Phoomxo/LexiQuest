# AllTCAS 8–44 Final Local Verification Record

Verification date: 2026-09-01

## Decision and scope

The 44-capability implementation package is **READY for local source closure** at commit `f56e2eb598e88cbdf24d446c53051b262d284998`.

This decision is deliberately narrower than a field or production release decision:

- Local implementation review: **Critical 0, Important 0, Minor 0 — READY**.
- Field/release acceptance: **NOT READY and not claimed by this record**.
- No production cloud deployment, Firestore Rules deployment, release signing, release packaging, push, or merge was performed as part of this verification.
- Local Firestore/Auth emulator results are verification evidence only; they are not deployment evidence.
- iOS was excluded by explicit owner direction. The Android-first verification did not modify or certify the parked iOS work.

This record does not supersede the immutable historical field records or the earlier shared-foundation record. Those documents describe older source and artifact identities.

## Canonical source identity

| Authority | Verified value |
| --- | --- |
| Final local source commit | `f56e2eb598e88cbdf24d446c53051b262d284998` |
| Final-plan source commit metadata | `48ab087804eaddaf61948dd1a72769acf22c177a` |
| Final-plan source fingerprint | `898beedb8fbe1fd08722d606662938b6d06a711d6c45c6adf8752b58684a7e31` |
| Product-contract revision | `1.3.0` |
| Product-contract semantic SHA-256 | `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4` |
| Product capabilities | exactly 44 |
| Completion contracts | exactly 8 (`C1`–`C8`) |
| Runtime features | exactly 19 |
| Database | `AppDatabase` schema v22, exactly 44 tables |

The generated [Markdown test plan](../generated/alltcas-8-44-final-test-plan.md) and [JSON test plan](../generated/alltcas-8-44-final-test-plan.json) are the machine-verifiable command, source-fingerprint, and inventory authorities. Their `sourceCommit` records the pre-final-plan source identity used by the generator; the final closure commit above contains the checked generated artifacts and Android physical-acceptance corrections.

## Database and migration authority

The current v22 inventory is exactly:

`achievement_unlocks`, `ai_usage_events`, `answer_attempts`, `assessment_runs`, `association_records`, `associative_memory_states`, `content_download_states`, `content_manifests`, `content_quality_reports`, `equipped_reward_items`, `events_v2`, `experiment_assignments`, `learner_preferences`, `learning_day_log`, `learning_goals`, `learning_pack_items`, `learning_packs`, `learning_sessions`, `learning_time_segments`, `local_owners`, `model_downloads`, `outbox_operations`, `owned_reward_items`, `points_ledger_entries`, `quest_definitions`, `quest_instances`, `quest_objective_progress`, `reading_events`, `reading_progress_entries`, `research_consents`, `reward_transactions`, `runtime_flags`, `saved_learning_items`, `session_configurations`, `speech_evidence`, `srs_states`, `streak_states`, `study_reminders`, `sync_checkpoints`, `sync_conflicts`, `vocabulary_categories`, `vocabulary_import_rows`, `vocabulary_imports`, and `vocabulary_words`.

The generated plan covers every forward transition from v1 through v22 plus the full-upgrade path. The schema remains forward-only: there is no downgrade migration, and older binaries must not open a v22 database.

## Content and protocol authorities

- Learning-pack revisions are immutable per `ContentManifest`, governed by `lib/features/learning_packs/domain/content_quality_policy.dart`; there is no invented global pack revision in this record.
- Assessment instrument/form revisions and packaged-byte checksums are immutable per approved catalog entry in `lib/features/assessment/domain/assessment_instrument_catalog.dart`.
- Contextual companion reactions use the local compile-time `CompanionReactionCatalog.v1` authority in `lib/features/companion/domain/companion_reaction_catalog.dart`.
- Research assignment, consent, protocol, assessment, evidence, and sync boundaries remain the existing typed authorities. Runtime visibility never assigns a research cohort.

The exact deployed-rules compatibility identifiers represented in source are:

| Collection/contract | Rules revision |
| --- | --- |
| Legacy | `legacy-v1` |
| AnswerAttempt v2 | `answer-attempt-v2-r1` |
| VocabularyWord v2 | `vocabulary-word-v2-r1` |
| ExperimentAssignment v1 | `experiment-assignment-v1-r1` |
| AssessmentRun v1 | `assessment-run-v1-r3` |
| SavedLearningItem v1 | `saved-learning-item-v1-r1` |
| ContentQualityReport v1 | `content-quality-report-v1-r1` |
| LearningTimeSegment v1 | `learning-time-segment-v1-r1` |
| LearningGoal v1 | `learning-goal-v1-r1` |
| LearnerPreference v1 | `learner-preference-v1-r1` |

These identifiers describe local compatibility contracts. They do not establish that corresponding Rules were deployed.

## Runtime handoff state

Code presence does not enable delivery, a missing dependency fails closed, and feature visibility does not assign cohorts.

| State | Runtime features |
| --- | --- |
| `enabled` | `vocabulary`, `quiz`, `srs`, `reading`, `mastery`, `weakness`, `ghostDuel`, `achievements`, `shop`, `export` |
| `limited` | `objectScanner`, `speechPractice`, `aiTutor`, `questV2` |
| `hidden` | `shadowRewardV2`, `studyPlanning`, `researchAssessment`, `dailyContinuity`, `offlineContent` |

The hidden and limited labels are delivery states, not evidence that a field cohort or external provider is available. Research collection sync and assessment invocation remain fail-closed unless their exact typed rollout, rules revision, consent, protocol, assignment, and dependency gates are deliberately supplied.

## Execution evidence

### Fresh final-closure gates

These gates were run during the final closure sequence on the source fingerprints that introduced or last affected the covered paths. Every recorded command exited `0`. Where the transient console count was not retained in a durable artifact, this record intentionally does not invent a count.

| Closure | Exact command | Exit | Count/result | Closing commit |
| --- | --- | ---: | --- | --- |
| Architecture contracts | `flutter test --no-pub test/architecture` | 0 | passed; exact count not retained | `04527b7f` |
| Unit/domain acceptance | `flutter test --no-pub test/features/accessibility test/features/account test/features/achievements test/features/ai_tutor test/features/assessment test/features/companion test/features/consent test/features/device_model test/features/events test/features/gemini test/features/goals test/features/history test/features/learning test/features/learning_packs test/features/media_practice test/features/motivation test/features/preferences test/features/progress test/features/quest test/features/recommendation test/features/reminders test/features/research test/features/review test/features/rewards test/features/session test/features/sync test/features/time_tracking test/features/today_hub test/features/vocabulary test/features/voice --reporter compact` | 0 | passed; exact count not retained | `5a920258` |
| Widget surfaces | `flutter test --no-pub test/screens test/widgets --reporter compact` | 0 | passed; exact count not retained | `2a658243` |
| Feature-control integration | `flutter test -d flutter-tester --no-pub --reporter compact integration_test/field_trial_feature_controls_test.dart` | 0 | passed | `ac433e4b` |
| Media integration | `flutter test -d flutter-tester --no-pub --reporter compact integration_test/field_trial_media_smoke_test.dart` | 0 | passed | `ac433e4b` |
| Migration transitions | Exact v1→v22 commands in the generated final plan | 0 | every transition passed; aggregate count not retained | `da7681e1` |
| Full database upgrade | `flutter test --no-pub test/data/local/app_database_migration_test.dart --reporter compact` | 0 | passed; exact count not retained | `da7681e1` |
| Owner lifecycle/restart | `flutter test --no-pub test/features/identity test/scenarios/guest_upgrade_restart_test.dart --reporter compact` | 0 | passed; exact count not retained | `48ab0878` |
| Android bounded core smoke | `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/run-android-smoke.ps1` | 0 | 1/1 on HONOR DNP-NX9, Android 16 / SDK 36 | `f56e2eb5` |

The Android run is local/debug physical-device acceptance. It is not a release-signed build, field certification, or production rollout.

### Fingerprint-reused gates

The following generated-plan gates retained their last successful results because the files covered by each gate had not changed after its accepted source fingerprint. They were not represented as fresh reruns at `f56e2eb5`:

| Gate | Exact command | Recorded exit/result |
| --- | --- | --- |
| Product-contract artifacts | `dart run tool/feature_contract/generate_feature_map.dart --check` | 0 / no drift |
| Final test-plan artifacts | `dart run tool/final_test_plan/generate_final_test_plan.dart --check --source-commit 48ab087804eaddaf61948dd1a72769acf22c177a` | 0 / no drift |
| Static analysis | `flutter analyze` | 0 / no issues at its accepted fingerprint |
| Local Firestore Rules | `npm run test:rules` | 0 / local emulator passed; not deployment evidence |
| Local Auth contract | `npm run test:auth` | 0 / local emulator passed; not deployment evidence |
| Offline/restart recovery | `flutter test --no-pub test/features/offline_content test/scenarios/file_backed_sync_recovery_test.dart test/scenarios/production_learning_restart_test.dart --reporter compact` | 0 / passed |
| Default-Off | `flutter test --no-pub test/runtime/runtime_feature_controls_test.dart --plain-name "durable feature decision epochs distinguish off and clear" --reporter compact` | 0 / 1/1 |
| Emergency-Off | `flutter test --no-pub test/scenarios/runtime_kill_switch_journey_test.dart --plain-name "production entry live route direct route and restart all fail closed" --reporter compact` | 0 / 1/1 |
| Export/withdraw/delete | `flutter test --no-pub test/features/export test/scenarios/complete_owner_export_delete_test.dart --reporter compact` | 0 / passed; aggregate count not retained |
| Android debug build | `flutter build apk --debug --no-pub` | 0 / debug build completed; no release artifact claimed |
| Forward-only rollback drill | `flutter test --no-pub test/scenarios/runtime_kill_switch_journey_test.dart --plain-name "file-backed permanent clear and TTL controls converge across restart" --reporter compact` | 0 / 1/1 |

### Historical evidence explicitly excluded from the final-source claim

The [shared-foundation verification record](2026-08-14-alltcas-shared-foundation-verification.md) is valid only for its recorded `b486544f…` source, schema v15/33-table inventory, product contract `1.0.0`, and its named debug APK. Its test counts and APK digest are not reused as fresh evidence for the v22/44-table source in this record.

Likewise, the existing `docs/field/2026-08-09-*` records describe their own historical source and artifact identities. They do not certify `f56e2eb5`.

## Completion-contract outcome

Local verification covers the eight shared completion contracts and their five typed evidence families without creating competing authorities:

- canonical identity, owner lifecycle, restart, export, withdrawal, and explicit deletion;
- local-first transactional writes, durable outbox identity, bounded recovery, and fail-closed sync;
- evidence/session authority, immutable replay, projection isolation, and recreational evidence excluded from Active Effort;
- controlled delivery, dependency gates, emergency-off, and forward-only rollback behavior;
- accessibility and Android production-composition acceptance across the canonical mode set.

The verified rollback drill passed locally. Because schema v22 is forward-only, rollback means disabling delivery and converging durable runtime controls; it does not mean downgrading the database or running an older binary against v22.

## Remaining field and release constraints

The following remain outside this local closure and must be satisfied before any field/release READY decision:

- a current release-signed artifact built from the exact approved source identity;
- low-, mid-, and high-device certification against that exact artifact, including provider/App Check/assets/kill-switch conditions;
- production Rules/cloud deployment evidence and post-deployment verification;
- owner approval of cost/budget controls, private feedback/support and research references, beta operations, and rollback ownership;
- final artifact digest, distribution provenance, field matrix, and release-verifier evidence tied to the same immutable candidate.

No frozen field-release candidate was replaced by this work.

## Working-tree hygiene

At document creation, the staged set was empty. The only pre-existing working-tree changes were the explicitly protected Android-first parked iOS files and seven generated plugin registrants carrying line-ending noise. This document is the sole file authorized for staging in its commit.
