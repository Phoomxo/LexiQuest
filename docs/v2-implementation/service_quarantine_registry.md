# Service Quarantine Registry
**Phase:** Phase -1 Week 1-2 (D1.5)  
**Date:** 2026-08-04  
**Authority:** Architecture Team  
**Status:** ACTIVE

---

> **Quarantine Rule:** Quarantined services MUST NOT be imported in `lib/features/`.  
> Existing `lib/screens/` imports of quarantined services are legacy debt — do not  
> add NEW screen imports. Quarantined services will be migrated or deleted in Phase 0–1.  
>
> **Keep Rule:** Services marked KEEP are safe to call from new code (stateless computation only).  
> They must NOT be called directly from screens — route through use cases.

---

## Summary

| Classification | Count | Description |
|----------------|-------|-------------|
| 🔴 QUARANTINE | 6 | Critical issues: mutable state, storage bypass, model conflicts |
| 🟡 EVALUATE | 28 | Need individual review before V2 use |
| 🟢 KEEP (stateless) | 8 | Safe computation utilities |

---

## 🔴 QUARANTINE — Must Not Be Used in New Code

### Q1: `streak_and_daily_quest_service.dart`
**Reason:** In-memory mutable state. Data resets on app restart.  
**Authority boundary:** Non-authoritative and excluded from production composition. Operational streak state belongs only to `StreakUseCases` + `DriftStreakRepository`; this legacy service remains quarantined and is not activated or deleted here.
**Specific issues:**
```dart
int _currentStreakDays = 1;    // ← hardcoded, not persisted
int _streakFreezeCount = 1;    // ← hardcoded, not persisted  
final List<DailyQuest> _quests = [ ... ]; // ← resets on restart
```
**V2 replacement:** `features/quest/` + `features/motivation/streak/` (Week 5-6)  
**Current imports:** `lib/screens/home_screen.dart` (legacy — do not add more)  
**Action:** Replace with `QuestUseCases` + `StreakProjection` in Phase 0

---

### Q2: `adaptive_daily_quest_service.dart`
**Reason:** Incompatible `DailyQuest` model, no persistence, model name collision.  
**Specific issues:**
```dart
// This service defines:
class DailyQuest { String title; String description; String targetMode; }
// Conflicts with streak_and_daily_quest_service.dart:
class DailyQuest { String id; int targetCount; int currentProgress; ... }
// SAME CLASS NAME, DIFFERENT SHAPE
```
**V2 replacement:** `QuestDomainService` (D3.5, Week 5-6) uses `QuestInstance` model  
**Current imports:** None found in screens (isolated service)  
**Action:** Delete after D3.5 is complete

---

### Q3: `srs_service.dart`
**Reason:** SharedPreferences-backed SRS. Fully superseded by `features/learning/data/drift_learning_repository.dart`.  
**Specific issues:**
```dart
// Stores SRS data in SharedPreferences[srs_storage_key]
// features/learning stores same data in Drift SrsStates table
// Two sources of truth for SRS state
```
**V2 replacement:** `features/learning` SrsStates table (already exists)  
**Current imports:** Check `lib/screens/` — may be used in legacy SRS screen  
**Action:** Migrate all callers to `LearningUseCases.getDueWords()` then delete

---

### Q4: `local_user_progress_store.dart`
**Reason:** SharedPreferences storage for streak, ZPD level, mastered words — all conflict with Drift schema.  
**Authority boundary:** Non-authoritative and excluded from production composition. Its `streak_count` must never feed or write operational streak state; `StreakUseCases` + `DriftStreakRepository` remain authoritative. This legacy store remains quarantined and is not activated or deleted here.
**Specific issues:**
```
zpd_level     → should be in RuntimeFlags Drift table
streak_count  → should be in StreakStates Drift table (v8)
mastered_words → duplicate of SrsStates data
srs_progress  → duplicate of SrsStates data
```
**V2 replacement:** Drift tables (existing + v8 additions)  
**Current imports:** `lib/progress/local_progress_repository.dart` (also quarantined)  
**Action:** Migrate and delete in Phase 0

---

### Q5: `word_service.dart`
**Reason:** Direct Firestore writes, bypasses outbox pattern, offline-unsafe, no idempotency keys.  
**Specific issues:**
```dart
await _wordsCollection.doc(wordId).delete();   // ← direct Firestore
await _wordsCollection.doc(wordId).update(word.toMap()); // ← direct Firestore
```
**V2 replacement:** `VocabularyUseCases` → `DriftVocabularyRepository` → `OutboxOperations` → `FirestoreSyncGateway`  
**Current imports:** Unknown — needs screen scan  
**Action:** Replace all callers with `VocabularyUseCases` then delete

---

### Q6: `lib/progress/local_progress_repository.dart`
**Reason:** SharedPreferences-backed progress blob. No schema migration path.  
**Specific issues:**
```dart
// Stores entire progress as JSON blob in SharedPreferences[_kProgressKey]
// No idempotency, no event sourcing, no sync
```
**V2 replacement:** `features/progress/data/drift_progress_queries.dart` (already exists)  
**Note:** This is in `lib/progress/` not `lib/services/` but quarantine rule applies  
**Action:** Migrate callers to `ProgressUseCases` then delete

---

## 🟢 KEEP — Safe Stateless Utilities

These services perform pure computation with no side effects and no storage.  
They MAY be called from use cases (not directly from screens).

| Service | Purpose | Notes |
|---------|---------|-------|
| `cefr_service.dart` | CEFR level lookup table | Stateless lookup — keep |
| `collocation_service.dart` | Word collocation data | Stateless lookup — keep |
| `cosine_similarity_evaluator_service.dart` | NLP cosine similarity | Pure computation — keep |
| `lexical_diversity_evaluator_service.dart` | Text diversity metrics | Pure computation — keep |
| `phrasal_verb_service.dart` | Phrasal verb content | Stateless lookup — keep |
| `sentence_service.dart` | Sentence generation | Stateless — keep |
| `rank_service.dart` | XP→Rank calculation | Stateless calculator (no persistence). Note: `calculateXpGain()` returns values — caller must persist via XP grant pipeline |
| `interleaved_srs_scheduler.dart` | SRS card ordering algorithm | Pure scheduling computation — keep |

---

## 🟡 EVALUATE — Needs Review Before V2 Use

Each service needs individual analysis before being imported into `lib/features/`.  
Analysis should happen when the relevant feature domain is designed.

| Service | Domain | Notes | Blocker |
|---------|--------|-------|---------|
| `adaptive_decay_scheduler.dart` | Learning | May have state — audit needed | Audit in Week 3-4 |
| `ai_reading_content_adapter.dart` | AI/Reading | Wraps AI calls — check if Gemini-specific | Audit in Week 5-6 |
| `apriori_error_miner_service.dart` | Analytics | Reads from DB? Writes? | Audit in Week 3-4 |
| `associative_memory_service.dart` | Learning | State unclear | Audit in Week 3-4 |
| `background_audio_player_service.dart` | Media | Platform service — check lifecycle | Audit in Week 3-4 |
| `background_service.dart` | Platform | WorkManager integration — check writes | Audit in Week 3-4 |
| `brahmawong_research_analytics_service.dart` | Research | May write to Firestore directly | Audit in Week 3-4 |
| `cognitive_attention_analyzer_service.dart` | Analytics | Pure computation likely | Audit in Week 3-4 |
| `crisp_dm_analytics_service.dart` | Analytics | Check for writes | Audit in Week 3-4 |
| `custom_wordbook_importer.dart` | Vocabulary | May duplicate `VocabularyImportUseCases` | Audit in Week 3-4 |
| `dataset_partitioning_service.dart` | Analytics | Likely stateless | Audit in Week 3-4 |
| `dynamic_story_contextualizer_service.dart` | AI/Reading | Check for state | Audit in Week 5-6 |
| `ghost_model_trainer_service.dart` | AI | Local model writes? | Audit in Week 5-6 |
| `ghost_shadow_duel_service.dart` | Game | Check for reward writes | Audit in Week 3-4 |
| `global_word_service.dart` | Vocabulary | Possible Firestore direct writes | Audit in Week 3-4 |
| `guest_session_service.dart` | Identity | In `AppDependenciesScope` — currently KEEP | In composition root — safe |
| `kmeans_learner_profiler_service.dart` | Analytics | Used by adaptive_daily_quest (quarantined) | Evaluate independently |
| `lexi_vision_accessibility_service.dart` | Accessibility | Platform wrapper | Audit in Week 3-4 |
| `object_vocabulary_database.dart` | Vocabulary | In-memory dict? | Audit in Week 3-4 |
| `persistent_audio_cache.dart` | Media | File system cache — check purge policy | Audit in Week 3-4 |
| `rapid_naming_speed_service.dart` | Learning | Likely stateless | Audit in Week 3-4 |
| `research_experiment_service.dart` | Research | May write to research tables | Audit in Week 3-4 |
| `soundscape_audio_service.dart` | Media | Platform audio — check lifecycle | Audit in Week 3-4 |
| `spaced_review_reminder_service.dart` | Notifications | Notification scheduling — check state | Audit in Week 3-4 |
| `thesis_appendix_exporter_service.dart` | Export | Likely wraps ExportUseCases | Audit in Week 3-4 |
| `voice_reading_adapter.dart` | Voice | Wraps VoiceProvider — needs VoiceUseCases boundary | D2.2 scope (Week 3-4) |
| `weakness_clinic_service.dart` | Learning | Reads SRS data? | Audit in Week 3-4 |
| `zpd_auto_tuner_service.dart` | Learning | May write ZPD to SharedPreferences | Audit in Week 3-4 |
| `zpd_recommender_service.dart` | Learning | Likely reads SRS states | Audit in Week 3-4 |

---

## Quarantine Enforcement Rules

### For lib/features/ code:
```dart
// ❌ FORBIDDEN — importing quarantined services:
import 'package:lexiquest/services/streak_and_daily_quest_service.dart';
import 'package:lexiquest/services/srs_service.dart';
import 'package:lexiquest/services/local_user_progress_store.dart';
import 'package:lexiquest/services/word_service.dart';
import 'package:lexiquest/services/adaptive_daily_quest_service.dart';
import 'package:lexiquest/progress/local_progress_repository.dart';
```

### Architecture Fitness Test (D2.1):
```dart
test('features/ must not import quarantined services', () {
  final quarantined = [
    'streak_and_daily_quest_service',
    'adaptive_daily_quest_service',
    'srs_service',
    'local_user_progress_store',
    'word_service',
    'local_progress_repository',
  ];
  
  final violations = <String>[];
  for (final file in findDartFiles('lib/features/')) {
    final content = File(file).readAsStringSync();
    for (final service in quarantined) {
      if (content.contains(service) && !content.contains('// legacy')) {
        violations.add('$file imports $service');
      }
    }
  }
  expect(violations, isEmpty, reason: violations.join('\n'));
});
```

---

## Migration Timeline

| Service | Target Week | Replacement | Status |
|---------|-------------|-------------|--------|
| `streak_and_daily_quest_service.dart` | Phase 0 Week 10-11 | `QuestUseCases` | ⚠️ `@Deprecated` added 2026-08-04; removal target Phase 1 |
| `adaptive_daily_quest_service.dart` | Phase 0 Week 10-11 | `QuestUseCases` | ⚠️ Pending removal — no screen imports found |
| `srs_service.dart` | Phase 0 Week 14-15 | `LearningUseCases.startDueReview()` | ✅ Removed from screens 2026-08-04; `@Deprecated` added |
| `local_user_progress_store.dart` | Phase 1 | Drift tables + `ProgressUseCases` | 🔒 Still quarantined |
| `word_service.dart` | Phase 1 | `VocabularyUseCases` | 🔒 Still quarantined |
| `local_progress_repository.dart` | Phase 1 | `ProgressUseCases` | 🔒 Still quarantined |

**Gate 1.5:** All 42 services categorized ✅ (6 quarantined, 8 keep, 28 evaluate)

**Phase 0 progress (2026-08-04):** 2/6 quarantined services deprecated; `srs_service` removed from all screen imports.

**Gate 1.5:** All 42 services categorized ✅ (6 quarantined, 8 keep, 28 evaluate)
