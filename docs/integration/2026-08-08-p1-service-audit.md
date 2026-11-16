# P1.2 Service Audit

**Date:** 2026-08-08
**Branch:** `integration/p0-baseline`
**Total services:** 57

## Disposition Criteria

- **KEEP** — imported by production lib/ code, actively used
- **MIGRATE** — imported by orphan screens only, needs wiring into feature architecture (P3–P4)
- **RESEARCH_ONLY** — owner-only research/analytics tools, no participant-facing UI
- **DELETE** — no importers in lib/ or test/, superseded by feature architecture

## KEEP (6 services)

| Service | Importers | Justification |
|---|---|---|
| guest_session_service.dart | 3 lib + 6 test | Core auth/guest lifecycle, used by AppDependencies |
| object_vocabulary_database.dart | 1 lib + 2 test | ObjectScanner feature, Drift database |
| ghost_shadow_duel_service.dart | 1 lib + 1 test | Active game mode (MNS-navigable) |
| cefr_service.dart | 2 lib + 1 test | CEFR level management |
| custom_wordbook_importer.dart | 1 lib + 1 test | Wordbook import (will wire in P3) |
| background_audio_player_service.dart | 1 lib + 1 test | Audio playback (will wire in P6) |

## MIGRATE (16 services) — imported by orphan screens or test-only, will wire in P3–P6

### Learning & Motivation (P3)

| Service | Test Importers | Target Architecture |
|---|---|---|
| srs_service.dart | 3 test | → feature/learning/ (superseded by SrsStates drift table + LearningUseCases) |
| streak_and_daily_quest_service.dart | 3 test | → feature/motivation/ (superseded by StreakUseCases) |
| adaptive_daily_quest_service.dart | 3 test | → feature/quest/ (adaptive quest) |
| adaptive_decay_scheduler.dart | 1 test | → feature/learning/ (SRS decay) |
| interleaved_srs_scheduler.dart | 1 test | → feature/learning/ (SRS scheduling) |
| spaced_review_reminder_service.dart | 1 test | → feature/learning/ (review reminders) |
| associative_memory_service.dart | 1 test | → feature/learning/ (superseded by DriftAssociativeLearningAdapter) |
| local_user_progress_store.dart | 3 test | → feature/progress/ (superseded by DriftProgressQueries) |
| word_service.dart | 2 test | → feature/vocabulary/ (superseded by VocabularyUseCases) |
| suggestion_service.dart | 0 | → feature/vocabulary/ (word suggestions) |

### Games (P4)

| Service | Test Importers | Target Architecture |
|---|---|---|
| sentence_service.dart | 1 lib + 0 test | → feature/games/ (sentence scramble/fill blank) |
| rank_service.dart | 1 lib + 1 test | → feature/games/ (boss battle ranking) |
| weakness_clinic_service.dart | 1 test | → feature/learning/ (weakness analysis) |
| ghost_model_trainer_service.dart | 1 test | → feature/games/ (ghost shadow training) |

### AI & Voice (P6)

| Service | Test Importers | Target Architecture |
|---|---|---|
| ai_reading_content_adapter.dart | 1 test | → feature/learning/ (AI reading content) |
| voice_reading_adapter.dart | 1 test | → feature/voice/ (voice for reading) |
| dynamic_story_contextualizer_service.dart | 1 test | → feature/learning/ (story context) |

## RESEARCH_ONLY (18 services) — owner tools, no participant-facing UI needed

| Service | Purpose |
|---|---|
| apriori_error_miner_service.dart | Apriori association rule mining |
| brahmawong_research_analytics_service.dart | Brahmawong E1/E2 analysis |
| cognitive_attention_analyzer_service.dart | Cognitive attention metrics |
| cosine_similarity_evaluator_service.dart | Cosine similarity NLP evaluator |
| crisp_dm_analytics_service.dart | CRISP-DM analytics |
| dataset_partitioning_service.dart | Train/test dataset partitioning |
| kmeans_learner_profiler_service.dart | K-means learner profiling |
| lexical_diversity_evaluator_service.dart | Lexical diversity evaluation |
| rapid_naming_speed_service.dart | Rapid naming speed test |
| research_data_exporter_service.dart | Research data export |
| research_experiment_service.dart | Research experiment runner |
| research_export_errors.dart | Export error types |
| research_report_pdf_exporter_service.dart | Research report PDF generation |
| thesis_appendix_exporter_service.dart | Thesis appendix export |
| collocation_service.dart | Collocation analysis |
| phrasal_verb_service.dart | Phrasal verb analysis |
| pdf_glossary_exporter_service.dart | PDF glossary export |
| anki_dictionary_exporter_service.dart | Anki dictionary export |

These services must:
- Run from real data (exported datasets)
- Produce deterministic output
- Have golden dataset tests
- Never claim "production-ready" without evidence

## DELETE (17 services) — no importers, superseded, or unused

| Service | Reason |
|---|---|
| achievement_service.dart | Superseded by rewards/feature architecture |
| avatar_equipment_service.dart | Superseded by shop logic in screens |
| background_service.dart | Unused — sync uses workmanager_sync_scheduler |
| cefr_interactive_storybook_service.dart | No importers, unused |
| global_word_service.dart | No importers, superseded |
| lexi_vision_accessibility_service.dart | No importers, unused |
| ml_image_labeling_service.dart | No importers, superseded by LiteRT classifier |
| multi_accent_pitch_calibration_service.dart | No importers, unused |
| persistent_audio_cache.dart | No importers, superseded by voice_audio_cache |
| phoneme_alignment_clinic_service.dart | No importers, unused |
| shop_service.dart | Superseded by rewards/feature architecture |
| soundscape_audio_service.dart | No importers, unused |
| user_service.dart | No importers, superseded by account/ |
| vocab_service.dart | No importers, superseded by vocabulary/ |
| zpd_auto_tuner_service.dart | No importers, unused |
| zpd_recommender_service.dart | No importers, unused |
| thesis_chart_screen support (part of thesis_appendix_exporter) | Covered by thesis_appendix_exporter_service |

## Quarantine Verification

Before deleting any DELETE service, verify with:
1. `grep -r 'ServiceName' lib/ test/` confirms zero production importers
2. Contract test (if exists) passes independently
3. Deletion does not break `flutter analyze` or `flutter test`

## Summary

| Disposition | Count |
|---|---|
| KEEP | 6 |
| MIGRATE | 16 |
| RESEARCH_ONLY | 18 |
| DELETE | 17 |
| **Total** | **57** |
