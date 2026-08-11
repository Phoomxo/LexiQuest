# Runtime Feature Ledger — 2026-08-09 P0 Baseline

Source baseline: `c706ce2` on `codex/runtime-convergence`.

This ledger is an inventory, not a release claim. It contains all 15 members of
`Feature.values` and all 47 files returned by `rg --files lib/screens` (62 rows
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
| Feature: quiz | `Feature.quiz` (`enabled`) | `home/learn/quiz` → `QuizScreen` | `LearningUseCases` | Drift learning sessions, answer attempts, SRS state, stable V2 learning events, and versioned projection receipts; `localOwnerId` | File-backed production-use-case journey plus post-commit failure/replay injection | None; host test only | verified |
| Feature: SRS | `Feature.srs` (`enabled`) | `home/learn/srs` → `SrsFlashcardsScreen` | `LearningUseCases` (voice has a screen fallback) | Drift learning sessions, answer attempts, SRS state, and stable V2 learning events; `localOwnerId` | Correct/incorrect SRS state and due time survive same-file close/reopen | None; host test only | verified |
| Feature: associative reading delivery target | `Feature.reading` (`enabled`) | `ChooseModeScreen` reading tile → `AssociativeReadingLauncherScreen` → `AssociativeReadingSessionScreen` | `VocabularyUseCases`, `LearningUseCases`, `DriftAssociativeLearningAdapter` from the production scope; the launcher explicitly passes learning and associative persistence | Drift `association_records`, `associative_memory_states`, and reading progress; active `localOwnerId` | Production shell journey plus same-file SQLite close/reopen verifies both association tables and excludes an inactive foreign owner | None; host test only | verified |
| Feature: mastery | `Feature.mastery` (`enabled`) | `home/mastery` → `MasteryDashboardScreen` | `ProgressUseCases` | Drift-derived learning/progress evidence; `localOwnerId` | File-backed progress reload verifies mastery count from durable evidence | None; host test only | verified |
| Feature: weakness | `Feature.weakness` (`enabled`) | `home/weakness` → `WeaknessClinicScreen` | `ProgressUseCases` | Drift-derived answer/SRS evidence; `localOwnerId` | File-backed progress reload verifies incorrect-count weakness evidence | None; host test only | verified |
| Feature: ghost duel | `Feature.ghostDuel` (`enabled`) | `drawer/learning/ghost-duel` | `LearningUseCases`, `ProgressUseCases` | Drift learning sessions and answer attempts; `localOwnerId` | None from production shell | None | wired |
| Feature: achievements | `Feature.achievements` (`enabled`) | `home/achievements` → `AchievementsScreen` | `ProgressUseCases` | Drift achievement unlocks and progress evidence; `localOwnerId` | None from production shell | None | wired |
| Feature: shop | `Feature.shop` (`enabled`) | `drawer/rewards/shop` | `RewardUseCases` | Drift reward transactions, owned/equipped items; `localOwnerId` | None from production shell | None | wired |
| Feature: object scanner | `Feature.objectScanner` (`limited`) | `drawer/practice/object-scanner` | `ObjectScannerController`, `DeviceModelUseCases`, vocabulary use cases | Drift model downloads and accepted vocabulary; `localOwnerId` where applicable | None from production shell | None; host fakes are not device evidence | wired |
| Feature: speech practice | `Feature.speechPractice` (`limited`) | `drawer/practice/shadowing` | `SpeechPracticeUseCases`, `LearningUseCases` (voice has a screen fallback) | Drift learning/answer and speech evidence; `localOwnerId` | None from production shell | None; host fakes are not microphone evidence | wired |
| Feature: AI tutor | `Feature.aiTutor` (`limited`) | `drawer/ai-tutor/chat` and `drawer/ai-tutor/settings` | `AiTutorController`, `AiUsageRepository` (voice has a screen fallback) | Drift AI usage plus saved provider settings/secret store; `localOwnerId` | None from production shell | None; fake replies are not provider evidence | wired |
| Feature: export | `Feature.export` (`enabled`) | `drawer/export/center` | `ExportUseCases` | Reads allowlisted Drift data and writes a selected file | None from production shell | None | wired |
| Feature: shadow reward V2 | `Feature.shadowRewardV2` (`hidden` by omission) | None; not adapted into legacy navigation | Shadow reward orchestrator is internal only | Drift V2 event/reward projections | None from production shell | None | hidden |
| Feature: quest V2 | `Feature.questV2` (`limited`) | Missing: no `FieldFeature` mapping or user-visible quest entry | `QuestUseCases` plus durable learning reconciler are composed | Drift quest definitions, instances, objective progress, and versioned learning projection receipts; `localOwnerId` | File-backed answer replay proves stable source-event de-duplication; no user-visible shell entry | None; host test only | orphan |
| Screen: `achievements_screen.dart` | `Feature.achievements` | `MainNavigationScreen` bottom destination | `ProgressUseCases.load` through `AppDependenciesScope` | Drift achievement/progress evidence | None from production shell | None | wired |
| Screen: `add_multiple_words_screen.dart` | `Feature.vocabulary` | `CategoriesPage` → `VocabListScreen` → bulk add | `ImportVocabulary` through `AppDependenciesScope`; production route passes no dependency | Drift vocabulary import and word tables | Production Home shell opens the scoped bulk-add route; import behavior is not executed | None; host test only | wired |
| Screen: `add_vocab_screen.dart` | `Feature.vocabulary` | `CategoriesPage` → `VocabListScreen` → add/edit | `VocabularyUseCases` through `AppDependenciesScope` | Drift vocabulary word/category tables | Production Home shell creates and renders a word | None; host test only | verified |
| Screen: `ai_tutor_screen.dart` | `Feature.aiTutor` | `MainNavigationScreen` drawer `ai-tutor/chat` | Composed `AiTutorController`/speech when present; constructs voice fallback in screen | Drift AI usage/settings; chat list is widget memory | None from production shell | None | wired |
| Screen: `ai_tutor_settings_screen.dart` | `Feature.aiTutor` | Drawer `ai-tutor/settings`; also opened by `AiTutorScreen` | `AiTutorController`, `AiUsageRepository` through scope | Provider settings/secret store and Drift usage | None from production shell | None | wired |
| Screen: `associative_reading_launcher_screen.dart` | `Feature.reading` | `ChooseModeScreen` reading tile | Resolves scoped `VocabularyUseCases`, `LearningUseCases`, and `AssociativeLearningPort`; loads at most 10 active-owner words and explicitly injects the latter two into the session | Reads owner-scoped Drift vocabulary; session writes reading and association evidence | Production shell file-backed close/reopen journey | None; host test only | verified |
| Screen: `associative_reading_session_screen.dart` | `Feature.reading` | `AssociativeReadingLauncherScreen` | Explicit `LearningUseCases` and production `DriftAssociativeLearningAdapter`; missing dependencies render a typed unavailable state | Drift reading progress, `association_records`, and `associative_memory_states`; active `localOwnerId` | Same-file SQLite close/reopen with foreign-owner exclusion | None; host test only | verified |
| Screen: `avatar_equipment_screen.dart` | `Feature.shop` | No production caller | Optional `RewardUseCases`; delegates to `ShopPage` | Drift reward ownership if injected | None | None | orphan |
| Screen: `boss_battle_screen.dart` | `Feature.quiz` | `ChooseModeScreen` → `GameLauncherScreen` → boss battle | Screen constructs `RankService`; questions are passed from vocabulary | No result persistence in screen | None | None | legacy |
| Screen: `categories_page.dart` | `Feature.vocabulary` | `MainNavigationScreen` bottom destination | `VocabularyUseCases` through scope | Drift vocabulary categories/words | Production Home shell creates and opens a category | None; host test only | verified |
| Screen: `cefr_article_reader_screen.dart` | `Feature.reading` | No production caller | Optional voice; constructs default voice in screen | None | None | None | orphan |
| Screen: `cefr_diagnostic_test_screen.dart` | `Feature.reading` | `ChooseModeScreen` diagnostic tile | Static screen-owned question list | None; answers/results are widget memory | None | None | legacy |
| Screen: `cefr_selection_screen.dart` | `Feature.srs` | `ChooseModeScreen` → `LearningWorldMapScreen` | Screen constructs legacy `CefrService`; passes map data to SRS | No CEFR selection persistence | None | None | legacy |
| Screen: `choose_mode_screen.dart` | Parent aggregate plus an independently guarded `Feature.reading` tile; other legacy tiles retain parent-only checks | `MainNavigationScreen` learn destination | Reads `FeatureRegistry` from `AppDependenciesScope` for the associative-reading entry | None | Reading-tile visible/hidden widget coverage and production-shell reachability | None; host test only | wired |
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
category, list, and single-word screens to `verified`. The production-shell
journey also proves the bulk-add route resolves `ImportVocabulary` from
`AppDependenciesScope`, but bulk import remains `wired` because the journey does
not execute an import. There is still no physical process-restart, APK, or
device evidence, so vocabulary is not `field-certified`.

## P2 learning durability update

Task 3 records one stable `EventEnvelopeV2` beside each answer attempt inside
the same local Drift transaction as the attempt, SRS, core XP, and attempt/SRS
outbox rows. Event ID and idempotency key derive from the durable attempt ID,
not a process-local counter. Quest, streak, and quest-reward projections run
after that transaction through a reconciler. Each successful projection writes
an independent version-1 result to the existing `events_v2` table. Applied
work uses `LearningProjectionApplied`; a confirmed no-op uses
`LearningProjectionSkipped`, so a reward receipt never claims a grant for an
ineligible source event. Failed work remains result-free. Reward processing is
gated on the quest receipt, and each projection stops at its oldest failure so
newer events cannot overtake it. Quest objective evidence rejects a repeated
source event ID, replay finalizes an already-fully-progressed active quest, and
completed-quest reward retry reuses the quest completion idempotency key.

No schema bump was needed. Schema 12 already includes `events_v2`, its unique
owner/idempotency constraint, owner-upgrade inventory entry, and owner deletion
coverage. Reconciliation reads fixed pending batches and is scheduled without
blocking bootstrap or answer completion; its lifecycle disposer drains active
local work before the database closes. Streak replay applies the owner and UTC
time captured by the durable event. The reconciler adds no network call to the
local learning transaction. Evidence is a same-file SQLite close/reopen
journey, injected progress-to-completion and reward-to-receipt crashes,
out-of-order streak and owner-switch tests, bounded/non-blocking scheduler
tests, independent result retry tests, and focused host gates.
Each projection maintains one durable contiguous-prefix cursor in `events_v2`;
indexed reads begin strictly after its `(occurredAtUtc, eventId)` position,
while immutable applied/skipped receipts remain intact. Receipt and cursor
persistence is one conflict-safe transaction without per-event receipt
lookups. Quest receipts carry the bounded completion grants consumed by reward
replay, eliminating per-event quest-history scans. Bootstrap seeds the daily
quest before replay, and events before its assignment time are deterministically
skipped; equality is explicitly eligible.
On merged-owner upgrade, projection cursors are re-keyed to the account and
merged at the earlier safe contiguous prefix; quest receipt reward owners are
normalized in the same transaction so pending guest evidence remains replayable.
This is not physical process, APK, or device evidence, so the promoted learning
rows are `verified`, not `field-certified`; quest remains `orphan` because it
still lacks a user-visible production entry.

## P2 associative reading update

Task 4 adds a `Feature.reading`-guarded tile to the production Choose Mode
surface. Its launcher reads at most 10 words through the active-owner
`VocabularyUseCases`, derives the stable vocabulary IDs, passage, CEFR level,
document ID, and revision, and explicitly passes the bootstrap-composed
`LearningUseCases` and `DriftAssociativeLearningAdapter` into the session.
Empty vocabulary has one deterministic route to vocabulary creation. Missing
learning or associative persistence renders a typed unavailable state; no
production screen or composition path creates the in-memory adapter.

Completing a memory cue writes an owner-scoped association record and initial
associative memory state keyed by the durable vocabulary word ID. A production
shell journey closes the dependency graph, reopens the same SQLite file, and
verifies both records for the unchanged active owner while excluding an
inactive foreign owner's rows. Disposal unmounts the route before closing the
bootstrap-owned resources. This is bounded host evidence, not a physical
process, APK, or device result, so the slice is `verified`, not
`field-certified`.

## P2 sync and owner-upgrade update

Task 5 replaces owner-scoped fixed run leases with one renewable persisted
owner-operation gate shared by sync and every concrete UID/active-owner
transition. Sync rereads owner and Firebase UID after acquisition, reserves at
most five sends per Firebase UID namespace immediately before provider push,
and token-fences every acknowledgement, retry, terminal, conflict, release, and
pull-page transaction. Pulls remain one page per collection per run and advance
the full timestamp/document cursor before mutation. Permanent failure stops the
batch and does not automatically reopen permission denial.

Two file-backed host test files provide the Task 5 evidence. Vocabulary and
learning work is first applied by an idempotent fake before its retryable
acknowledgement is lost; after the retry deadline and reopen the same
`(uid, operationId)` is requested twice but applied once, then a second reopen
makes zero pushes with stable IDs, attempts, acknowledgement, and checkpoint.
Mutable SRS operations use an event-specific, revision-suffixed SHA-256 identity.
Two independent databases under one UID at the same base revision emit distinct
raw operations; the second receives its own explicit cloud conflict, immutable
answer evidence remains authoritative locally, and no receipt is aliased.

A no-prior-UID anonymous owner keeps all 25 directly owner-scoped inventory
tables plus import-row and quest-objective children through bind/reopen/replay,
with stable owner, row, and operation IDs across all seven sync types and an
inactive foreign owner's inventory byte-equivalent throughout. A separate
fully populated `mergedExisting` scenario overlaps both owners' natural keys,
foreign keys, bookkeeping, and event IDs, then proves deterministic merge,
reopen/replay, stable target identity, byte-equivalent foreign data, and a
zero-push second run. Direct non-null UID A-to-B rebinding is rejected with all
state unchanged; callers must use the upgrade path. A sync request during
upgrade waits and then uses only the committed UID.

Legacy schema-12 SRS repair is owner-gate-fenced and restart-idempotent. Each
claim scans the authoritative owner's SRS/answer/outbox evidence once and
inserts at most 20 missing latest-answer operations; the write bound does not
claim a bounded row scan. SQLite identity, inventory, projection, conflict,
rehome, and checkpoint changes are one token-fenced transaction. External
owner-secret deletion is deliberately non-transactional and cannot be restored
by rollback. Schema remains 12. This is file-backed host/fake-cloud evidence,
not physical restart, APK, device, or provider receipt evidence, so it is
`verified`, not `field-certified`. MaxPlus advisory evidence is unavailable
after two identical `invalidKey` failures and was not retried without changed
external configuration.

## Baseline gaps carried forward

- `Feature.questV2` is visible under `BuildFeatureRegistry.fieldDefaults()` but
  still has no declared user-visible production path. The associative-reading
  gap is closed by Task 4. `LearningWorldMapScreen` remains a separate legacy
  surface under the reading flag.
- `ChooseModeScreen` is shown when any of quiz, SRS, or reading is visible, but
  only its new associative-reading tile independently enforces its feature
  state. Other legacy tiles retain parent-only checks. The shadowing tile is
  also reachable independently of the drawer guard.
- Ten screen files are unreachable from `lib/main.dart`: avatar equipment,
  CEFR article reader, Gemini settings, result, wallpaper selection, sentence
  scramble, smart audio playlist, speak-to-text, thesis chart, and wordbook
  import.
- Several reachable media/voice screens create their own default voice provider;
  this is not single-composition evidence.
- The existing device-certification scenario uses in-memory Drift and explicitly
  says it is not an integration/device test. It is not field evidence.
