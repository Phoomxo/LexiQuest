# P1.1 Feature Inventory

**Date:** 2026-08-08
**Branch:** `integration/p0-baseline`

## Screen Inventory (45 screens)

### Navigable (28) — reachable from production navigation

| Screen | Via | Persisted | Offline | Notes |
|---|---|---|---|---|
| login_screen.dart | NAV | ✅ | ✅ | Auth entry |
| register_screen.dart | NAV | ✅ | ✅ | Registration |
| otp_screen.dart | NAV | ✅ | ✅ | Email verification |
| email_action_screen.dart | NAV | ✅ | ✅ | Deep link handler |
| main_navigation_screen.dart | NAV | ✅ | ✅ | Home hub |
| categories_page.dart | MNS | ✅ | ✅ | Vocabulary categories |
| choose_mode_screen.dart | MNS | ✅ | ✅ | Learning mode select |
| quiz_screen.dart | t:choose_mode | ✅ | ✅ | Quiz mode |
| score_screen.dart | t:quiz | ✅ | ✅ | Quiz results |
| select_category_for_quiz.dart | t:choose_mode | ✅ | ✅ | Category picker |
| srs_flashcards_screen.dart | t:choose_mode | ✅ | ✅ | SRS flashcards |
| vocab_list_screen.dart | t:categories | ✅ | ✅ | Word list |
| add_vocab_screen.dart | t:vocab_list | ✅ | ✅ | Add word |
| add_multiple_words_screen.dart | t:vocab_list | ✅ | ✅ | Bulk add |
| achievements_screen.dart | MNS | ✅ | ✅ | Achievements |
| ai_tutor_screen.dart | MNS | ✅ | partial | Needs BYOK key |
| export_center_screen.dart | MNS | ✅ | ✅ | Data export |
| gemini_settings_screen.dart | MNS | ✅ | ✅ | Gemini BYOK config |
| ghost_shadow_duel_screen.dart | MNS | ✅ | ✅ | Game mode |
| mastery_dashboard_screen.dart | MNS | ✅ | ✅ | Mastery/progress |
| object_scanner_screen.dart | MNS | partial | partial | Needs LiteRT model |
| profile_settings_screen.dart | MNS | ✅ | ✅ | Profile settings |
| setting_screen.dart | MNS | ✅ | ✅ | App settings |
| shadowing_challenge_screen.dart | MNS | ✅ | partial | Needs TTS |
| shop_page.dart | MNS | ✅ | ✅ | Shop |
| select_wallpaper_screen.dart | t:shop | ✅ | ✅ | Wallpaper select |
| avatar_equipment_screen.dart | t:shop | ✅ | ✅ | Avatar equipment |
| weakness_clinic_screen.dart | MNS | ✅ | ✅ | Weakness analysis |

### Orphan Screens (17) — NOT reachable from navigation

| Screen | Status | Disposition |
|---|---|---|
| ai_tutor_settings_screen.dart | UNREACHABLE | **Wire up** — needed for BYOK config |
| associative_reading_session_screen.dart | UNREACHABLE | **Wire up** — P3 Associative Reading |
| boss_battle_screen.dart | UNREACHABLE | **Wire up** — P4 Games |
| cefr_article_reader_screen.dart | UNREACHABLE | **Wire up** — P4 Reading activities |
| cefr_diagnostic_test_screen.dart | UNREACHABLE | **Wire up** — P4 CEFR Diagnostic |
| cefr_selection_screen.dart | UNREACHABLE | **Wire up** — P4 CEFR |
| dictation_quiz_screen.dart | UNREACHABLE | **Wire up** — P4 Dictation |
| fill_in_the_blanks_screen.dart | UNREACHABLE | **Wire up** — P4 Fill in Blank |
| learning_world_map_screen.dart | UNREACHABLE | **Wire up** — P4 World Map |
| phonetic_explorer_screen.dart | UNREACHABLE | **Wire up** — P4 Phonetic |
| result_screen.dart | UNREACHABLE | **Investigate** — may be result display |
| sentence_scramble_screen.dart | UNREACHABLE | **Wire up** — P4 Sentence Scramble |
| smart_audio_playlist_screen.dart | UNREACHABLE | **Wire up** — P6 Voice |
| speak_to_text_screen.dart | UNREACHABLE | **Wire up** — P4 Speak to Text |
| thesis_chart_screen.dart | UNREACHABLE | **RESEARCH_ONLY** — owner tool |
| word_scramble_screen.dart | UNREACHABLE | **Wire up** — P4 Word Scramble |
| wordbook_import_screen.dart | UNREACHABLE | **Wire up** — P3 Import |

## Feature Directory Inventory (16 directories, 102 files)

### In Feature Registry (learner-facing)

| Directory | Registry Feature | Files | Status |
|---|---|---|---|
| vocabulary/ | vocabulary | 10 | Integrated |
| ai_tutor/ | aiTutor | 7 | Integrated (P0 Slice 6) |
| export/ | export | 4 | Integrated |
| media_practice/ | objectScanner + speechPractice | 8 | Integrated (P0 Slice 6) |
| gemini/ | aiTutor (backend) | 4 | Integrated |
| quest/ | questV2 | 5 | Integrated |
| rewards/ | achievements/shop | 7 | Integrated |
| learning/ | srs/mastery/weakness | 8 | Integrated |
| voice/ | (via aiTutor) | 1 | Integrated (P0 Slice 6) |

### Infrastructure (not in registry — by design)

| Directory | Purpose | Files | Status |
|---|---|---|---|
| account/ | Firebase auth | 3 | Integrated |
| consent/ | Research consent | 3 | Integrated |
| device_model/ | LiteRT model management | 8 | Integrated |
| events/ | Event bus v2 | 2 | Integrated |
| identity/ | Local owner + upgrade | 7 | Integrated |
| motivation/ | Streak tracking | 4 | Integrated |
| progress/ | Progress aggregation | 3 | Integrated |
| session/ | App entry state | 2 | Integrated (P0 Slice 6) |
| sync/ | Cloud sync engine | 13 | Integrated |

## Registry Gaps

### Missing from registry but should be registered
- **streak** — `motivation/` has streak tracking but no feature flag
- **sync** — `sync/` has no kill-switch entry

### Registry features without dedicated directory
These are implemented via screens + services rather than feature dirs:
- `quiz`, `reading`, `mastery`, `weakness`, `ghostDuel`, `achievements`, `shop`

## Game Mode Inventory (for P4)

| Game | Screen | Service | Reachable | Status |
|---|---|---|---|---|
| Quiz | quiz_screen.dart | — | YES | Integrated |
| SRS Flashcards | srs_flashcards_screen.dart | — | YES | Integrated |
| Ghost Shadow Duel | ghost_shadow_duel_screen.dart | ghost_shadow_duel_service.dart | YES | Integrated |
| Word Scramble | word_scramble_screen.dart | — | NO (orphan) | Needs wiring |
| Sentence Scramble | sentence_scramble_screen.dart | — | NO (orphan) | Needs wiring |
| Fill in the Blank | fill_in_the_blanks_screen.dart | sentence_service.dart | NO (orphan) | Needs wiring |
| Dictation | dictation_quiz_screen.dart | — | NO (orphan) | Needs wiring |
| Boss Battle | boss_battle_screen.dart | rank_service.dart | NO (orphan) | Needs wiring |
| CEFR Diagnostic | cefr_diagnostic_test_screen.dart | cefr_service.dart | NO (orphan) | Needs wiring |
| Shadowing Challenge | shadowing_challenge_screen.dart | — | YES | Integrated |
| Speak to Text | speak_to_text_screen.dart | — | NO (orphan) | Needs wiring |
| Phonetic Explorer | phonetic_explorer_screen.dart | — | NO (orphan) | Needs wiring |
| World Map | learning_world_map_screen.dart | — | NO (orphan) | Needs wiring |
