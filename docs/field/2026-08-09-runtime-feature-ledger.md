# Runtime Feature Ledger — 2026-08-09 P0 Baseline

Source baseline: `c706ce2` on `codex/runtime-convergence`.

This ledger is an inventory, not a release claim. It contains all 15 members of
`Feature.values` and all 46 files returned by `rg --files lib/screens` (61 rows
total). Production reachability was traced from `lib/main.dart` through Dart
imports and then checked against the actual navigation callbacks. Dependency
claims require either `AppDependenciesScope` lookup or an explicit value passed
from a production caller. A filename, isolated widget test, or historical phase
label is not delivery evidence.

State uses the execution plan vocabulary. In particular, `wired` does not mean
restart-safe or field-certified. Vocabulary is promoted to `verified` by a
bounded production-bootstrap shell journey plus a same-file SQLite restart and
owner-isolation test. This remains host evidence, not exact APK/device/provider
evidence, so no row is `field-certified`. `legacy` identifies reachable,
user-visible surfaces that the current production path still uses but that
retain static/demo or screen-owned service behavior. `orphan` means no caller
is reachable from `lib/main.dart`.

| Capability | Feature flag | Production entry | Composed dependency | Durable store | Restart test | Field evidence | State |
|---|---|---|---|---|---|---|---|
| Feature: vocabulary | `Feature.vocabulary` (`enabled`) | `home/vocabulary` → `CategoriesPage` | `VocabularyUseCases`, `ImportVocabulary` | Drift `vocabulary_categories`, `vocabulary_words`, import tables; `localOwnerId` | Production Home shell create journey plus same-file SQLite close/reopen and foreign-owner exclusion | None; host test only | verified |
| Feature: quiz | `Feature.quiz` (`enabled`) | `home/learn/quiz` → `QuizScreen` | `LearningUseCases` | Drift learning sessions, answer attempts, SRS state; `localOwnerId` | None from production shell | None | wired |
| Feature: SRS | `Feature.srs` (`enabled`) | `home/learn/srs` → `SrsFlashcardsScreen` | `LearningUseCases` (voice has a screen fallback) | Drift learning sessions, answer attempts, SRS state; `localOwnerId` | None from production shell | None | wired |
| Feature: associative reading delivery target | `Feature.reading` (`enabled`) | Missing: no launcher reaches `AssociativeReadingSessionScreen`; the reachable `LearningWorldMapScreen` is a separate legacy surface under this flag | Production bootstrap currently provides `InMemoryAssociativeLearningAdapter` | Drift association tables exist, but production associative reading uses no durable adapter/path | None | None | orphan |
| Feature: mastery | `Feature.mastery` (`enabled`) | `home/mastery` → `MasteryDashboardScreen` | `ProgressUseCases` | Drift-derived learning/progress evidence; `localOwnerId` | None from production shell | None | wired |
| Feature: weakness | `Feature.weakness` (`enabled`) | `home/weakness` → `WeaknessClinicScreen` | `ProgressUseCases` | Drift-derived answer/SRS evidence; `localOwnerId` | None from production shell | None | wired |
| Feature: ghost duel | `Feature.ghostDuel` (`enabled`) | `drawer/learning/ghost-duel` | `LearningUseCases`, `ProgressUseCases` | Drift learning sessions and answer attempts; `localOwnerId` | None from production shell | None | wired |
| Feature: achievements | `Feature.achievements` (`enabled`) | `home/achievements` → `AchievementsScreen` | `ProgressUseCases` | Drift achievement unlocks and progress evidence; `localOwnerId` | None from production shell | None | wired |
| Feature: shop | `Feature.shop` (`enabled`) | `drawer/rewards/shop` | `RewardUseCases` | Drift reward transactions, owned/equipped items; `localOwnerId` | None from production shell | None | wired |
| Feature: object scanner | `Feature.objectScanner` (`limited`) | `drawer/practice/object-scanner` | `ObjectScannerController`, `DeviceModelUseCases`, vocabulary use cases | Drift model downloads and accepted vocabulary; `localOwnerId` where applicable | None from production shell | None; host fakes are not device evidence | wired |
| Feature: speech practice | `Feature.speechPractice` (`limited`) | `drawer/practice/shadowing` | `SpeechPracticeUseCases`, `LearningUseCases` (voice has a screen fallback) | Drift learning/answer and speech evidence; `localOwnerId` | None from production shell | None; host fakes are not microphone evidence | wired |
| Feature: AI tutor | `Feature.aiTutor` (`limited`) | `drawer/ai-tutor/chat` and `drawer/ai-tutor/settings` | `AiTutorController`, `AiUsageRepository` (voice has a screen fallback) | Drift AI usage plus saved provider settings/secret store; `localOwnerId` | None from production shell | None; fake replies are not provider evidence | wired |
| Feature: export | `Feature.export` (`enabled`) | `drawer/export/center` | `ExportUseCases` | Reads allowlisted Drift data and writes a selected file | None from production shell | None | wired |
| Feature: shadow reward V2 | `Feature.shadowRewardV2` (`hidden` by omission) | None; not adapted into legacy navigation | Shadow reward orchestrator is internal only | Drift V2 event/reward projections | None from production shell | None | hidden |
| Feature: quest V2 | `Feature.questV2` (`limited`) | Missing: no `FieldFeature` mapping or user-visible quest entry | `QuestUseCases` is composed | Drift quest definitions, instances, objective progress; `localOwnerId` | None from production shell | None | orphan |
| Screen: `achievements_screen.dart` | `Feature.achievements` | `MainNavigationScreen` bottom destination | `ProgressUseCases.load` through `AppDependenciesScope` | Drift achievement/progress evidence | None from production shell | None | wired |
| Screen: `add_multiple_words_screen.dart` | `Feature.vocabulary` | `CategoriesPage` → `VocabListScreen` → bulk add | `ImportVocabulary` through `AppDependenciesScope` | Drift vocabulary import and word tables | None from production shell | None | wired |
| Screen: `add_vocab_screen.dart` | `Feature.vocabulary` | `CategoriesPage` → `VocabListScreen` → add/edit | `VocabularyUseCases` through `AppDependenciesScope` | Drift vocabulary word/category tables | Production Home shell creates and renders a word | None; host test only | verified |
| Screen: `ai_tutor_screen.dart` | `Feature.aiTutor` | `MainNavigationScreen` drawer `ai-tutor/chat` | Composed `AiTutorController`/speech when present; constructs voice fallback in screen | Drift AI usage/settings; chat list is widget memory | None from production shell | None | wired |
| Screen: `ai_tutor_settings_screen.dart` | `Feature.aiTutor` | Drawer `ai-tutor/settings`; also opened by `AiTutorScreen` | `AiTutorController`, `AiUsageRepository` through scope | Provider settings/secret store and Drift usage | None from production shell | None | wired |
| Screen: `associative_reading_session_screen.dart` | `Feature.reading` | No production caller | Optional `LearningUseCases`; silently falls back to `InMemoryAssociativeLearningAdapter` | Drift association tables exist but are not used by this production screen path | None | None | orphan |
| Screen: `avatar_equipment_screen.dart` | `Feature.shop` | No production caller | Optional `RewardUseCases`; delegates to `ShopPage` | Drift reward ownership if injected | None | None | orphan |
| Screen: `boss_battle_screen.dart` | `Feature.quiz` | `ChooseModeScreen` → `GameLauncherScreen` → boss battle | Screen constructs `RankService`; questions are passed from vocabulary | No result persistence in screen | None | None | legacy |
| Screen: `categories_page.dart` | `Feature.vocabulary` | `MainNavigationScreen` bottom destination | `VocabularyUseCases` through scope | Drift vocabulary categories/words | Production Home shell creates and opens a category | None; host test only | verified |
| Screen: `cefr_article_reader_screen.dart` | `Feature.reading` | No production caller | Optional voice; constructs default voice in screen | None | None | None | orphan |
| Screen: `cefr_diagnostic_test_screen.dart` | `Feature.reading` | `ChooseModeScreen` diagnostic tile | Static screen-owned question list | None; answers/results are widget memory | None | None | legacy |
| Screen: `cefr_selection_screen.dart` | `Feature.srs` | `ChooseModeScreen` → `LearningWorldMapScreen` | Screen constructs legacy `CefrService`; passes map data to SRS | No CEFR selection persistence | None | None | legacy |
| Screen: `choose_mode_screen.dart` | quiz/SRS/reading/mastery/weakness/speech flags are only checked by its parent aggregate | `MainNavigationScreen` learn destination | Navigation only; does not independently enforce individual feature flags | None | None | None | wired |
| Screen: `dictation_quiz_screen.dart` | `Feature.quiz`, `Feature.speechPractice` | `ChooseModeScreen` → `GameLauncherScreen` → dictation | Optional voice; constructs default voice in screen | No result persistence in screen | None | None | legacy |
| Screen: `email_action_screen.dart` | No `Feature` member (account shell) | `AppRouteFactory` email action route | `AccountUseCases` through scope | External account state plus local owner binding | None from production shell | None | wired |
| Screen: `export_center_screen.dart` | `Feature.export` | `MainNavigationScreen` drawer `export/center` | `ExportUseCases` through scope | Reads Drift and writes selected export file | None from production shell | None | wired |
| Screen: `fill_in_the_blanks_screen.dart` | `Feature.quiz` | `WordScrambleScreen` completion | Screen constructs legacy `SentenceService` | No result persistence in screen | None | None | legacy |
| Screen: `game_launcher_screen.dart` | `Feature.quiz` | Three tiles in `ChooseModeScreen` | `VocabularyUseCases` through scope | Reads owner-scoped Drift vocabulary | None from production shell | None | wired |
| Screen: `gemini_settings_screen.dart` | `Feature.aiTutor` | No production caller | Optional `GeminiTutorController` through scope | Provider settings/secret store if injected | None | None | orphan |
| Screen: `ghost_shadow_duel_screen.dart` | `Feature.ghostDuel` | `MainNavigationScreen` drawer `learning/ghost-duel` | `LearningUseCases`, `ProgressUseCases`; duel calculation service | Drift learning sessions/answer attempts | None from production shell | None | wired |
| Screen: `learning_world_map_screen.dart` | `Feature.reading` | `ChooseModeScreen` world-map tile | Static screen-owned campaign nodes | None | None | None | legacy |
| Screen: `login_screen.dart` | No `Feature` member (account shell) | Signed-out app start resolves to `/login` from composed persisted entry/auth state | Account, consent, guest session, and launch route from one bootstrap composition | Local owner plus external account binding; explicit entry choice in SharedPreferences | Resolver/store restart-state tests and production-shell initial-route gate; no physical process/device evidence | None | wired |
| Screen: `main_navigation_screen.dart` | Legacy `FieldFeature` adapter backed by `FeatureRegistry` | Authenticated or explicit-guest app start resolves to `/home` | `AppDependenciesScope`; `FeatureRegistryFieldAdapter`; composed launch route | Runtime flags persist in Drift; explicit guest entry choice persists separately without replacing `localOwnerId` | Resolver/store restart-state tests and production-shell initial-route gate; no physical process/device evidence | None | wired |
| Screen: `mastery_dashboard_screen.dart` | `Feature.mastery` | `MainNavigationScreen` bottom destination and learn tile | `ProgressUseCases.load` through scope | Drift-derived progress evidence | None from production shell | None | wired |
| Screen: `object_scanner_screen.dart` | `Feature.objectScanner` | Drawer `practice/object-scanner` | Composed scanner/model controller; constructs default voice in screen | Model downloads and accepted vocabulary in Drift | None from production shell | None; host tests only | wired |
| Screen: `otp_screen.dart` | No `Feature` member (account shell) | `/otp` route from registration | `AccountUseCases` through scope | External account state plus local owner binding | None from production shell | None | wired |
| Screen: `phonetic_explorer_screen.dart` | `Feature.speechPractice` | `ChooseModeScreen` phonetic tile | Static symbols; constructs default voice in screen | None | None | None | legacy |
| Screen: `profile_settings_screen.dart` | No `Feature` member (always-visible shell) | `MainNavigationScreen` profile destination | `ProgressUseCases`; account sign-out through scope | Drift-derived progress and local/account identity | None from production shell | None | wired |
| Screen: `quiz_screen.dart` | `Feature.quiz` | `ChooseModeScreen` direct/category quiz | `LearningUseCases` through scope | Drift sessions, answer attempts, SRS state | None from production shell | None | wired |
| Screen: `register_screen.dart` | No `Feature` member (account shell) | `/register` route from login | Account and consent use cases through scope | External account state plus local owner binding/consent | None from production shell | None | wired |
| Screen: `result_screen.dart` | No current flag | No production caller | None | None | None | None | orphan |
| Screen: `score_screen.dart` | `Feature.quiz` | `QuizScreen` completion | Presentation-only values passed by quiz | Underlying quiz answer is stored before navigation; screen itself stores nothing | None from production shell | None | legacy |
| Screen: `select_category_for_quiz.dart` | `Feature.quiz`, `Feature.vocabulary` | Category quiz tile in `ChooseModeScreen` | Vocabulary use cases through scope | Reads Drift vocabulary categories | None from production shell | None | wired |
| Screen: `select_wallpaper_screen.dart` | `Feature.shop` | No production caller | Optional `RewardUseCases`; delegates to `ShopPage` | Drift reward ownership if injected | None | None | orphan |
| Screen: `sentence_scramble_screen.dart` | `Feature.quiz`, `Feature.speechPractice` | No production caller | Optional voice only | No result persistence in screen | None | None | orphan |
| Screen: `setting_screen.dart` | No `Feature` member (always-visible shell) | `MainNavigationScreen` drawer `settings` | Account, local owner/deletion, consent, runtime status through scope | Drift owner/consent/business data plus secret erasure surface | None from production shell | None | wired |
| Screen: `shadowing_challenge_screen.dart` | `Feature.speechPractice` | Drawer `practice/shadowing` and unguarded learn tile | Composed speech and learning; constructs default voice in screen | Records Drift learning session/answer evidence | None from production shell | None; host microphone fakes only | wired |
| Screen: `shop_page.dart` | `Feature.shop` | Drawer `rewards/shop` | `RewardUseCases` through scope | Drift reward transactions and ownership/equipment | None from production shell | None | wired |
| Screen: `smart_audio_playlist_screen.dart` | `Feature.speechPractice` | No production caller | Optional voice and screen-owned audio service | None | None | None | orphan |
| Screen: `speak_to_text_screen.dart` | `Feature.speechPractice` | No production caller | Optional learning/speech/voice with screen voice fallback | Can record learning when injected, but no production path | None | None | orphan |
| Screen: `srs_flashcards_screen.dart` | `Feature.srs` | `ChooseModeScreen`, weakness clinic, and CEFR selection | `LearningUseCases` through scope; constructs default voice in screen | Drift sessions, answer attempts, SRS state | None from production shell | None | wired |
| Screen: `thesis_chart_screen.dart` | No current flag | No production caller | Presentation-only score arguments | None | None | None | orphan |
| Screen: `vocab_list_screen.dart` | `Feature.vocabulary` | `CategoriesPage` category selection | Vocabulary/import use cases through scope | Drift vocabulary/import tables | Production Home shell resolves scoped use cases and renders the created word | None; host test only | verified |
| Screen: `weakness_clinic_screen.dart` | `Feature.weakness` | `MainNavigationScreen` bottom destination and learn tile | `ProgressUseCases.load` through scope | Drift-derived answer/SRS evidence | None from production shell | None | wired |
| Screen: `word_scramble_screen.dart` | `Feature.quiz` | `ChooseModeScreen` → `GameLauncherScreen` → word scramble | Word passed from composed vocabulary launcher | No result persistence in screen | None | None | legacy |
| Screen: `wordbook_import_screen.dart` | `Feature.vocabulary` | No production caller | Screen-owned legacy `CustomWordbookImporter` | Parsed rows are widget memory | None | None | orphan |

## P1 launch-identity update

Task 1 replaces the hard-coded normal launch route with a route resolved during
production bootstrap from one `AppEntryStateStore` instance and the current
authenticated session. That same store is passed to guest and account
transitions. Guest selection is persisted before local guest success;
successful account binding and sign-out clear it. Local account binding still
uses the existing `localOwnerId` and does not replace the owner identifier.
Self-contained cold-start authentication routes (`/login`, `/register`, and
parsed email-action links) remain routable. Internal `/home`, argument-dependent
`/email-verification`, and unsupported platform route strings fall back to the
composed bootstrap route, so platform input cannot bypass persisted identity.

If SharedPreferences initialization fails, bootstrap uses a signed-out,
process-local volatile entry flag so offline business data remains available.
That fallback stores no owner, learning, consent, or research data and makes no
restart-durability claim.

The owner-binding guest adapter is owned by bootstrap. Disposal cancels pending
provider waits and bounded retry delays, drains an already-running owner
upgrade, suppresses post-disposal callbacks, and completes before the database
is closed. Resource cleanup remains reverse-order and continues after an
individual disposer fails.

Evidence is bounded to the resolver matrix, SharedPreferences mock-backed store
tests, bootstrap/session/account tests, and the production-shell widget gate.
This is not a physical process-restart or device/provider result, so the account
shell rows remain `wired` rather than `durable`, `verified`, or
`field-certified`.

## P1 vocabulary update

Task 2 drives the resolved production Home shell through the visible vocabulary
destination, creates a category and word with the bootstrap-composed
`VocabularyUseCases`, and verifies the routed vocabulary list resolves that
dependency from `AppDependenciesScope`. A separate journey uses
`AppDatabase(NativeDatabase(File(databasePath)))`, creates the active owner's
category and word through the same composed use cases, closes the dependency
graph, reopens the exact SQLite file, and verifies spelling, meaning, category,
and `localOwnerId`. An inactive foreign owner's category and word are present in
the same file and excluded from the reopened active-owner reads.

This evidence promotes the bounded vocabulary vertical slice and its exercised
screens to `verified`. Bulk import remains `wired` because the production-shell
journey does not exercise `ImportVocabulary`. There is still no physical
process-restart, APK, or device evidence, so vocabulary is not
`field-certified`.

## Baseline gaps carried forward

- Both the associative-reading delivery target represented by `Feature.reading`
  and `Feature.questV2` are visible under
  `BuildFeatureRegistry.fieldDefaults()` but have no declared production path.
  `LearningWorldMapScreen` remains reachable as a legacy surface under the
  reading flag; that does not deliver `AssociativeReadingSessionScreen`. The
  executable baseline asserts both gaps while expecting the strict enforcement
  routine to fail at this checkpoint.
- `ChooseModeScreen` is shown when any of quiz, SRS, or reading is visible, but
  its individual tiles do not enforce the corresponding feature state. The
  shadowing tile is also reachable independently of the drawer guard.
- Eleven screen files are unreachable from `lib/main.dart`: associative
  reading, avatar equipment, CEFR article reader, Gemini settings, result,
  wallpaper selection, sentence scramble, smart audio playlist, speak-to-text,
  thesis chart, and wordbook import.
- Several reachable media/voice screens create their own default voice provider;
  this is not single-composition evidence.
- The existing device-certification scenario uses in-memory Drift and explicitly
  says it is not an integration/device test. It is not field evidence.
