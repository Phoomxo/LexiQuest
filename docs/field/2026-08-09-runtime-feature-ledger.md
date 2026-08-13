# Runtime Feature Ledger — 2026-08-09 P0 Baseline

Source baseline: `c706ce2` on `codex/runtime-convergence`.
Release reconciliation and the signed internal artifact are both bound to
`c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1`; later changes are limited to
declared final-metadata documents.

This ledger is an inventory, not a release claim. It contains all 15 members of
`Feature.values` and all 49 files returned by `rg --files lib/screens` (64 rows
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

For the 15 `Feature` rows, the first value in **Composed dependency** is the
exact frozen `dependencyId` from `productionFeatureContract`; any additional
values are supporting composition and do not alter that contract. `Durable`
means participant state or an output artifact is backed by a durable subsystem.
It does not claim that every route writes, that every row has its own restart
journey, or that host evidence is physical process/device/provider proof. The
restart column therefore cites the closest existing subsystem evidence and
states route-specific gaps rather than inventing field proof.

| Capability | Feature flag | Production entry | Composed dependency | Durable store | Restart test | Field evidence | State |
|---|---|---|---|---|---|---|---|
| Feature: vocabulary | `Feature.vocabulary` (`enabled`) | `home/vocabulary` → `CategoriesPage` | `VocabularyUseCases`, `ImportVocabulary` | Drift `vocabulary_categories`, `vocabulary_words`, import tables; `localOwnerId` | Production Home shell create journey plus same-file SQLite close/reopen and foreign-owner exclusion | None; host test only | verified |
| Feature: quiz | `Feature.quiz` (`enabled`) | `home/learn/quiz` → `QuizScreen` | `LearningUseCases` | Drift learning sessions, answer attempts, SRS state, stable V2 learning events, and versioned projection receipts; `localOwnerId` | File-backed production-use-case journey plus post-commit failure/replay injection | None; host test only | verified |
| Feature: SRS | `Feature.srs` (`enabled`) | `home/learn/srs` → `SrsFlashcardsScreen` | `LearningUseCases`; supporting bootstrap-owned `VoiceUseCases` is consumed through an opaque route session | Drift learning sessions, answer attempts, SRS state, and stable V2 learning events; `localOwnerId` | Correct/incorrect SRS state and due time survive same-file close/reopen; host route tests cover voice takeover and lifecycle fencing | None; host test only | verified |
| Feature: associative reading delivery target | `Feature.reading` (`enabled`) | `home/learn/associative-reading` → `AssociativeReadingLauncherScreen` → `AssociativeReadingSessionScreen` | `VocabularyUseCases+LearningUseCases+AssociativeLearningPort`; production supporting adapter is `DriftAssociativeLearningAdapter` | Drift `association_records`, `associative_memory_states`, and reading progress; active `localOwnerId` | Production shell journey plus same-file SQLite close/reopen verifies both association tables and excludes an inactive foreign owner | None; host test only | verified |
| Feature: mastery | `Feature.mastery` (`enabled`) | `home/mastery` → `MasteryDashboardScreen` | `ProgressUseCases` | Drift-derived learning/progress evidence; `localOwnerId` | File-backed progress reload verifies mastery count from durable evidence | None; host test only | verified |
| Feature: weakness | `Feature.weakness` (`enabled`) | `home/weakness` → `WeaknessClinicScreen` | `ProgressUseCases` | Drift-derived answer/SRS evidence; `localOwnerId` | File-backed progress reload verifies incorrect-count weakness evidence | None; host test only | verified |
| Feature: ghost duel | `Feature.ghostDuel` (`enabled`) | `drawer/learning/ghost-duel` | `LearningUseCases`; supporting `ProgressUseCases` | Drift learning sessions and answer attempts; `localOwnerId` | Shared learning subsystem survives same-file reopen in `production_learning_restart_test.dart`; the exhaustive production invocation journey verifies the guarded route | None; host test only | verified |
| Feature: achievements | `Feature.achievements` (`enabled`) | `home/achievements` → `AchievementsScreen` | `ProgressUseCases` | Drift achievement unlocks and progress evidence; `localOwnerId` | Achievement inventory survives owner upgrade and reopen in `guest_upgrade_restart_test.dart`; the exhaustive production invocation journey verifies the guarded route | None; host test only | verified |
| Feature: shop | `Feature.shop` (`enabled`) | `drawer/rewards/shop` | `RewardUseCases` | Drift reward transactions, owned/equipped items; `localOwnerId` | Atomic durable/idempotent purchase and equipment plus complete reward inventory reopen are covered; the Task 9 production shell inspects the reward surface | None; host test only | verified |
| Feature: object scanner | `Feature.objectScanner` (`limited`) | `drawer/practice/object-scanner` | `ObjectScannerController`; supporting `DeviceModelUseCases`, `VocabularyUseCases`, and `VoiceUseCases`; missing composition fails closed before camera initialization | Drift model-download records, model file, and accepted vocabulary; `localOwnerId` where applicable | Durable model/vocabulary and lifecycle ownership are covered; the Task 9 production shell verifies host-fake camera/model unavailable behavior, not a physical scanner | None; host fakes are not device evidence | verified |
| Feature: speech practice | `Feature.speechPractice` (`limited`) | `drawer/practice/shadowing` | `SpeechPracticeUseCases`; supporting `LearningUseCases` and one bootstrap-owned `VoiceUseCases`; missing media composition fails closed | Drift learning/answer and transcript-assessment provenance; `localOwnerId` | Durable learning and lifecycle ownership are covered; the Task 9 production shell verifies host-fake microphone unavailable behavior, not a physical microphone | None; host fakes are not microphone evidence | verified |
| Feature: AI tutor | `Feature.aiTutor` (`limited`) | `drawer/ai-tutor/chat` and `drawer/ai-tutor/settings` | One bootstrap-owned `AiTutorController`; supporting speech and opaque voice sessions are composed independently; the usage repository is not exposed to UI | Schema-12 Drift AI request journal plus versioned provider settings/secure blobs; owner pinned before outbound work | File-backed pending recovery, owner-gate contention, owner isolation, restart, upgrade, and production invocation journeys are covered; provider replies remain fake/host evidence | None; fake replies are not provider evidence | verified |
| Feature: export | `Feature.export` (`enabled`) | `drawer/export/center` | `ExportUseCases` | Reads allowlisted Drift data and writes a selected file artifact | Task 9 invokes export through the rendered production shell and verifies persisted learning after same-file restart; export construction, owner-consistency fencing, and selected-file writes have focused coverage | None; host test only | verified |
| Feature: shadow reward V2 | `Feature.shadowRewardV2` (`hidden`) | Empty frozen `productionEntryId` | Empty frozen `dependencyId`; Production does not construct or inject `ShadowRewardOrchestrator`, while durable learning projection uses the non-shadow reconciler | No delivery-owned store for this hidden row | Static production-composition boundary test | None | hidden |
| Feature: quest V2 | `Feature.questV2` (`limited`) | `drawer/rewards/quests` → `QuestStatusScreen` (route `rewards/quests`) | `QuestUseCases`; supporting durable learning reconciler remains always composed because the switch gates UI invocation only | Drift quest definitions, instances, objective progress, reward receipts, and versioned learning projection receipts; `localOwnerId` | File-backed replay plus bootstrap emergency-off reconciliation and bounded owner-resolving Quest Status host tests | None; host/debug evidence only | verified |
| Screen: `achievements_screen.dart` | `Feature.achievements` | `MainNavigationScreen` bottom destination | `ProgressUseCases.load` through `AppDependenciesScope` | Drift achievement/progress evidence | None from production shell | None | wired |
| Screen: `add_multiple_words_screen.dart` | `Feature.vocabulary` | `CategoriesPage` → `VocabListScreen` → bulk add | `ImportVocabulary` through `AppDependenciesScope`; production route passes no dependency | Drift vocabulary import and word tables | Production Home shell opens the scoped bulk-add route; import behavior is not executed | None; host test only | wired |
| Screen: `add_vocab_screen.dart` | `Feature.vocabulary` | `CategoriesPage` → `VocabListScreen` → add/edit | `VocabularyUseCases` through `AppDependenciesScope` | Drift vocabulary word/category tables | Production Home shell creates and renders a word | None; host test only | verified |
| Screen: `ai_tutor_screen.dart` | `Feature.aiTutor` | `MainNavigationScreen` drawer `ai-tutor/chat` | Resolves the composed `AiTutorController`, speech facade, and opaque route voice session; never constructs a gateway, HTTP client, or provider | Schema-12 owner-pinned AI request journal and versioned provider settings; chat list is widget memory | Host tests cover dependency rebind, route takeover, app-background cancellation, non-cooperative late-result fencing, and typed unavailable states | None; fake replies are not provider evidence | wired |
| Screen: `ai_tutor_settings_screen.dart` | `Feature.aiTutor` | Drawer `ai-tutor/settings`; also opened by `AiTutorScreen` | Uses the single `AiTutorController` for settings, usage summary, and clear; no raw repository or provider escape | Versioned provider settings/secure blobs and schema-12 AI request journal | File-backed credential-intent recovery, gate fencing, and journal tests; no live provider receipt | None; host/fake-provider evidence only | wired |
| Screen: `associative_reading_launcher_screen.dart` | `Feature.reading` | `ChooseModeScreen` reading tile | Resolves scoped `VocabularyUseCases`, `LearningUseCases`, and `AssociativeLearningPort`; loads at most 10 active-owner words and explicitly injects the latter two into the session | Reads owner-scoped Drift vocabulary; session writes reading and association evidence | Production shell file-backed close/reopen journey | None; host test only | verified |
| Screen: `associative_reading_session_screen.dart` | `Feature.reading` | `AssociativeReadingLauncherScreen` | Explicit `LearningUseCases` and production `DriftAssociativeLearningAdapter`; missing dependencies render a typed unavailable state | Drift reading progress, `association_records`, and `associative_memory_states`; active `localOwnerId` | Same-file SQLite close/reopen with foreign-owner exclusion | None; host test only | verified |
| Screen: `avatar_equipment_screen.dart` | `Feature.shop` | No production caller | Optional `RewardUseCases`; delegates to `ShopPage` | Drift reward ownership if injected | None | None | orphan |
| Screen: `boss_battle_screen.dart` | `Feature.quiz` | `ChooseModeScreen` → `GameLauncherScreen` → boss battle | Requires the bounded owned-vocabulary questions passed by `GameLauncherScreen`; no synthetic defaults or `RankService` | No result persistence or reward grant in screen | Focused host tests cover one-question completion and question-count-derived progress | None; host test only | wired |
| Screen: `categories_page.dart` | `Feature.vocabulary` | `MainNavigationScreen` bottom destination | `VocabularyUseCases` through scope | Drift vocabulary categories/words | Production Home shell creates and opens a category | None; host test only | verified |
| Screen: `cefr_article_reader_screen.dart` | `Feature.reading` | No production caller | Optional injected-then-scoped `VoiceUseCases` through an opaque route session; no provider construction or ownership | None | Focused host composition/voice test | None; host test only | orphan |
| Screen: `cefr_diagnostic_test_screen.dart` | `Feature.reading` | No production caller; removed from `ChooseModeScreen` | Static screen-owned question list | None; answers/results are widget memory | Static production-entry boundary test | None | orphan |
| Screen: `cefr_selection_screen.dart` | `Feature.srs` | No production caller; its former World Map parent is not a production entry | Screen constructs legacy `CefrService`; passes map data to SRS | No CEFR selection persistence | None | None | orphan |
| Screen: `choose_mode_screen.dart` | Visible when the V2 quiz, SRS, or reading aggregate has an enabled/limited member; individual tiles use V2 visibility and shared invocation gates | `MainNavigationScreen` learn destination | Reads the sole `FeatureRegistry` from `AppDependenciesScope`; never substitutes a fail-open registry | None | Host navigation tests cover tile visibility, lazy routes, live emergency-off, and the all-hidden aggregate | None; host test only | verified |
| Screen: `dictation_quiz_screen.dart` | `Feature.quiz`, `Feature.speechPractice` | `ChooseModeScreen` → `GameLauncherScreen` → dictation | Receives the first owned word and resolves injected-then-scoped `VoiceUseCases`; opaque route session denies deferred playback outside foreground; missing voice is typed unavailable | No result persistence in screen | Focused host voice/composition, lifecycle, deferred-start, and launcher tests | None; host test only | wired |
| Screen: `email_action_screen.dart` | No `Feature` member (account shell) | `AppRouteFactory` email action route | `AccountUseCases` through scope | External account state plus local owner binding | None from production shell | None | wired |
| Screen: `export_center_screen.dart` | `Feature.export` | `MainNavigationScreen` drawer `export/center` | `ExportUseCases` through scope | Reads Drift and writes selected export file | None from production shell | None | wired |
| Screen: `fill_in_the_blanks_screen.dart` | `Feature.quiz` | No production caller; Word Scramble completion remains on its own result state | Screen constructs legacy `SentenceService` | No result persistence in screen | Focused Word Scramble host test proves no hidden follow-on | None | orphan |
| Screen: `game_launcher_screen.dart` | `Feature.quiz` | Three V2-gated tiles in `ChooseModeScreen` | `VocabularyUseCases` through scope; exactly one `getGameWords(limit: 10)` load | Reads at most ten owner-scoped Drift vocabulary words and passes only those words to games | Focused host tests cover one load, at most one route, typed missing/empty/failure states, and owned inputs | None; host test only | verified |
| Screen: `gemini_settings_screen.dart` | `Feature.aiTutor` | No production caller | Optional provider-neutral tutor controller through scope; no raw gateway or client construction | Provider settings/secure store if injected | Focused source-boundary coverage | None; host test only | orphan |
| Screen: `ghost_shadow_duel_screen.dart` | `Feature.ghostDuel` | `MainNavigationScreen` drawer `learning/ghost-duel` | `LearningUseCases`, `ProgressUseCases`; duel calculation service | Drift learning sessions/answer attempts | None from production shell | None | wired |
| Screen: `learning_world_map_screen.dart` | `Feature.reading` | No production caller; removed from `ChooseModeScreen` | Static screen-owned campaign nodes | None | Static production-entry boundary test | None | orphan |
| Screen: `login_screen.dart` | No `Feature` member (account shell) | Signed-out app start resolves to `/login` from composed persisted entry/auth state | Account, consent, guest session, and launch route from one bootstrap composition | Local owner plus external account binding; explicit entry choice in SharedPreferences | Resolver/store restart-state tests and production-shell initial-route gate; no physical process/device evidence | None | wired |
| Screen: `main_navigation_screen.dart` | Sole V2 `FeatureRegistry` authority with shared lazy/live/fail-closed `ProductionFeatureGate` routes | Authenticated or explicit-guest app start resolves to `/home` | `AppDependenciesScope`, composed launch route, stable destination identities/keys; no legacy field adapter or fail-open fallback | Runtime flags persist in Drift; explicit guest entry choice persists separately without replacing `localOwnerId` | Host tests cover live entry removal, retained selected-feature unavailable state, stable state across earlier removal, aggregate hiding, and one-entry Profile liveness | None; host/debug evidence only | verified |
| Screen: `media_dependency_unavailable.dart` | Shared typed dependency state for Task 6 media routes | Rendered by Object Scanner, Shadowing, Speak-to-Text, Dictation, and Phonetic Explorer when required composition is absent | No provider construction or ownership | None | Focused five-screen composition tests | None; host test only | wired |
| Screen: `mastery_dashboard_screen.dart` | `Feature.mastery` | `MainNavigationScreen` bottom destination and learn tile | `ProgressUseCases.load` through scope | Drift-derived progress evidence | None from production shell | None | wired |
| Screen: `object_scanner_screen.dart` | `Feature.objectScanner` | Drawer `practice/object-scanner` | Injected-then-scoped scanner and `VoiceUseCases`; camera lease and opaque route voice session fence takeover/app lifecycle; typed unavailable when either is absent | Model downloads and accepted vocabulary in Drift | Host tests cover zero unavailable initialization, replacement and push/pop ownership, app lifecycle, pending-init pause/resume, late-runtime disposal drain, and stale-owner fencing | None; host tests are not device evidence | wired |
| Screen: `otp_screen.dart` | No `Feature` member (account shell) | `/otp` route from registration | `AccountUseCases` through scope | External account state plus local owner binding | None from production shell | None | wired |
| Screen: `phonetic_explorer_screen.dart` | `Feature.speechPractice` | V2-gated `ChooseModeScreen` phonetic tile | Static symbols plus injected-then-scoped `VoiceUseCases`; opaque route session stops on app background; typed unavailable when absent | None | Focused host voice/composition and lifecycle tests | None; host test only | wired |
| Screen: `profile_settings_screen.dart` | No `Feature` member (always-visible shell) | `MainNavigationScreen` profile destination | `ProgressUseCases`; account sign-out through scope | Drift-derived progress and local/account identity | None from production shell | None | wired |
| Screen: `quest_status_screen.dart` | `Feature.questV2` | Drawer `rewards/quests` through exact route `rewards/quests` | Owner-resolving `QuestUseCases` from injection or scope; one bounded read per dependency identity | Read-only Drift quest instances/objective progress | Host tests cover limit 50, loading/empty/failure/unavailable, all lifecycle states, no IDs/mutations, and owner dependency replacement | None; host/debug evidence only | verified |
| Screen: `quiz_screen.dart` | `Feature.quiz` | `ChooseModeScreen` direct/category quiz | `LearningUseCases` through scope | Drift sessions, answer attempts, SRS state | None from production shell | None | wired |
| Screen: `register_screen.dart` | No `Feature` member (account shell) | `/register` route from login | Account and consent use cases through scope | External account state plus local owner binding/consent | None from production shell | None | wired |
| Screen: `result_screen.dart` | No current flag | No production caller | None | None | None | None | orphan |
| Screen: `score_screen.dart` | `Feature.quiz` | `QuizScreen` completion | Presentation-only values passed by quiz | Underlying quiz answer is stored before navigation; screen itself stores nothing | None from production shell | None | legacy |
| Screen: `select_category_for_quiz.dart` | `Feature.quiz`, `Feature.vocabulary` | Category quiz tile in `ChooseModeScreen` | Vocabulary use cases through scope | Reads Drift vocabulary categories | None from production shell | None | wired |
| Screen: `select_wallpaper_screen.dart` | `Feature.shop` | No production caller | Optional `RewardUseCases`; delegates to `ShopPage` | Drift reward ownership if injected | None | None | orphan |
| Screen: `sentence_scramble_screen.dart` | `Feature.quiz`, `Feature.speechPractice` | No production caller | Optional injected-then-scoped `VoiceUseCases` through an opaque route session; no provider construction | No result persistence in screen | Focused host composition test | None; host test only | orphan |
| Screen: `setting_screen.dart` | No `Feature` member (always-visible shell) | `MainNavigationScreen` drawer `settings` | Account, local owner/deletion, consent, runtime status through scope | Drift owner/consent/business data plus secret erasure surface | None from production shell | None | wired |
| Screen: `shadowing_challenge_screen.dart` | `Feature.speechPractice` | Drawer `practice/shadowing` and V2-gated learn tile | Injected-then-scoped voice/speech/learning dependencies; serialized speech and opaque voice sessions own microphone/playback work; typed unavailable for missing media composition | Records Drift learning session/answer evidence with actual `assessment.method` provenance | Host tests cover provenance, unavailable state, double-start, pending replacement, push/pop, app-background cleanup, late work fencing, and disposal drain | None; host microphone fakes only | wired |
| Screen: `shop_page.dart` | `Feature.shop` | Drawer `rewards/shop` | `RewardUseCases` through scope | Drift reward transactions and ownership/equipment | None from production shell | None | wired |
| Screen: `smart_audio_playlist_screen.dart` | `Feature.speechPractice` | No production caller | Injected-then-scoped `VoiceUseCases`; one opaque session is held for an ordered playlist run, with cancellable delay and lifecycle stop; no raw provider access | None | Host tests cover ordering, stop/restart serialization, cancellable delay, app background, typed failure, and disposal | None; host test only | orphan |
| Screen: `speak_to_text_screen.dart` | `Feature.speechPractice` | No production caller | Injected-then-scoped voice/speech/learning dependencies; serialized opaque sessions own microphone/playback work and stop on lifecycle loss; typed unavailable for missing media composition | Records learning only when both session and word IDs exist, but has no production path | Host tests cover shared-voice replacement, unavailable state, app lifecycle, pending replacement/push-pop, disposal drain, and the complete ID write matrix | None; host test only | orphan |
| Screen: `srs_flashcards_screen.dart` | `Feature.srs` | `ChooseModeScreen` and V2-gated weakness clinic | Resolves `LearningUseCases` and bootstrap-owned `VoiceUseCases` through scope; opaque route session blocks deferred/background playback; never constructs or disposes a provider | Drift sessions, answer attempts, SRS state | Host tests cover load failure, optional-voice absence with local-review continuity, lifecycle/deferred-start fencing, and gated weakness invocation; durable SRS state has same-file restart coverage | None; host test only | verified |
| Screen: `thesis_chart_screen.dart` | No current flag | No production caller | Presentation-only score arguments | None | None | None | orphan |
| Screen: `vocab_list_screen.dart` | `Feature.vocabulary` | `CategoriesPage` category selection | Vocabulary/import use cases through scope | Drift vocabulary/import tables | Production Home shell resolves scoped use cases and renders the created word | None; host test only | verified |
| Screen: `weakness_clinic_screen.dart` | `Feature.weakness` | `MainNavigationScreen` bottom destination and learn tile | `ProgressUseCases.load` through scope | Drift-derived answer/SRS evidence | None from production shell | None | wired |
| Screen: `word_scramble_screen.dart` | `Feature.quiz` | `ChooseModeScreen` → `GameLauncherScreen` → word scramble | First owned word passed from the composed vocabulary launcher | No result persistence in screen | Focused host test proves explicit completion remains on-screen with no hidden Fill-in-the-Blanks route | None; host test only | wired |
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
rows are `verified`, not `field-certified`. Task 6 subsequently adds the
read-only Quest Status production entry without changing that durable design.

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

## P3 production feature delivery update

Task 6 freezes one exact 15-row production delivery contract and makes the V2
`FeatureRegistry` the sole UI invocation authority. The shared gate constructs
enabled subtrees lazily, observes live runtime overrides, and fails closed for
missing, hidden, disabled, or emergency-off state. Entry surfaces disappear,
while a retained or direct route renders the same typed unavailable experience.
Stable destination identities preserve selection and widget state when earlier
entries disappear; an all-hidden aggregate cannot expose its enabled subtree,
and Profile remains reachable when it is the only visible destination. The
legacy field adapter and UI fail-open defaults are absent from production.
Fresh `MyApp` journeys key and invoke every one of the 14 enabled/limited
contract entries, assert the intended destination first, and then prove the
same feature fails closed after a live emergency-off. The hidden shadow entry
is absent and a direct invocation renders typed unavailable.

Quest Status is a read-only route at `drawer/rewards/quests`, with route setting
`rewards/quests`. It resolves the active owner through `QuestUseCases`, reads at
most 50 instances in deterministic SQL order, and renders no internal IDs or
mutation action. Changing the composed quest dependency reloads exactly once
for the new identity. The `questV2` switch controls that invocation only:
bootstrap still composes quest seed, projection, reward receipt, reconciliation,
and scheduling under emergency-off. Production does not construct or inject the
hidden shadow reward orchestrator.

The three game routes load owner-scoped vocabulary exactly once with limit 10
and navigate at most once. Boss progress derives only from the supplied owned
questions and grants no synthetic rank, XP, coin, daily, or CEFR result. Word
Scramble completes in place. The demo World Map and CEFR Diagnostic surfaces
are no longer production entries. The five Task 6 media screens resolve
injection first and then the runtime scope, fail closed before side effects when
required composition is missing, and do not create, stop, or dispose a shared
voice provider. Controller-scoped camera leases and use-case-scoped speech
sessions serialize takeover, fence pending replacement and push/pop ownership,
and drain disposal before runtime ownership ends. Shadowing persists the actual
transcript assessment method. Speak-to-Text writes learning evidence only when
both session and word IDs are present; the other three ID combinations write
nothing. There is no Speak-to-Text production entry.

All Task 6 evidence is bounded host/widget/bootstrap/SQLite or debug-script
evidence. It is `verified` where the row says so, never `field-certified`, and
does not establish physical camera, microphone, APK, provider, or device
performance. Schema remains 12 and no generated Drift file changed. MaxPlus
remains advisory-unavailable after repeated `invalidKey`; it was not retried.

## P4 single-composition AI and voice update

Task 7 makes `AppBootstrap` the sole owner of one provider-neutral AI facade and
one voice facade. The two managed builders are independently fault-isolated,
their partial resources roll back, and widget disposal starts one memoized
cleanup whose resource stack awaits and exhausts each owned disposer exactly
once. Missing Cloud configuration still composes BYOK AI settings and
native TTS; remote backend status reflects both configuration and Firebase
availability rather than overstating a local fallback as Cloud readiness.

All screen sources are guarded against HTTP/client, environment/key, gateway,
factory, and raw `VoiceProvider` composition. Voice consumers acquire opaque
`VoiceSession` leases from injection first and then `AppDependenciesScope`.
Synchronous supersession, attempt epochs, conditional stop barriers, foreground
gating, route cover/pop reconciliation, and bounded cleanup prevent an outgoing
or backgrounded screen from stopping or speaking over its replacement. Smart
Audio retains one session for a whole run and cancels both inter-item timers and
the run epoch on stop or lifecycle loss.

AI requests insert a durable schema-12 `pending` event before outbound work,
pin the owner while holding the shared Task 5 owner-operation lease, and finalize
that same row to `success`, `failure`, or recovered `indeterminate`. Gate-token
fences are the first statement in mutating transactions. A paid provider result
is not discarded solely because terminal accounting becomes indeterminate; the
pending row remains recoverable, avoiding a duplicate-billing retry. Provider
settings use immutable secure blobs with fenced schema-12 pointer/intent
metadata, and whole local erasure holds the same heartbeated gate across secret
cleanup and the database transaction. No secret is stored in SQLite.

Provider adapters expose only `AiTutorException`/`AiFailureCode`, physically
abort OpenAI-compatible/Responses/Anthropic/Gemini requests, enforce one
absolute request budget with at most three same-provider Gemini attempts, and
preserve the first cancellation/timeout cause. Disabled MaxPlus performs no
HTTP. Circuit-open, disabled, timeout, cancellation, deterministic rejection,
and cleanup failures are typed; no provider switching occurs.

This is bounded host/widget/SQLite/file-backed/fake-transport evidence, not a
claim of live provider success, physical audio behavior, signed-package
integrity, or field certification. Schema remains 12 and generated Drift files
are unchanged. MaxPlus advisory review remained unavailable after repeated
`invalidKey`; it was not retried, and a local adversarial read-only review was
used instead.

## Baseline gaps carried forward

- Orphan legacy content routes may still contain local-only or historical
  services, but the exhaustive Task 7 boundary proves that no
  production-reachable screen constructs an AI/voice provider, reads provider
  configuration, or owns an HTTP client.
- Unreachable legacy/demo files remain in the tree, including CEFR article,
  diagnostic, and selection screens, Learning World Map, Fill-in-the-Blanks,
  avatar equipment, Gemini settings, result, wallpaper selection, sentence
  scramble, smart audio playlist, Speak-to-Text, thesis chart, and wordbook
  import. Their presence is not a production-entry claim.
- The device/camera/speech verification scripts and widget scenarios are host or
  debug-only checks. They are not physical integration/device field evidence.

## P6-P10 release reconciliation

The production-entry inventory remains exhaustive. Every row marked `orphan`
has no production caller and no visible navigation entry; the production
invocation architecture gate rejects a hidden direct invocation path. No orphan
capability is presented as delivered merely because its source file remains in
the repository.

All visible enabled or limited feature rows have local composition and
invocation evidence. Task 9 adds production-shell Guest learning,
export/restart/sign-out, persistent control, and host-fake media journeys, and
the frozen product-completion gate reruns them. This is local `verified`
evidence at the release-control level; it does not rewrite the more specific
route rows above or promote any row to `field-certified`.

The current signed internal APK is independently bound to source `c55f7bb`,
package `com.lexiquest.app`, version `1.0.0+14`, one pinned certificate, exact
APK and model hashes, and embedded source/build/model provenance. It is the
current frozen candidate; only declared final-metadata commits may follow it.

Object Scanner, Speech Practice, and AI Tutor remain visible `limited`
device/provider-dependent capabilities without exact-artifact physical or live
provider certification. They are therefore explicit final-acceptance blockers,
not hidden or field-certified rows. The exact low/mid/high device matrix, App
Check/provider controls, hosted asset links, cloud kill-switch drill, current
cost evidence, private channels, beta operations, rollback drill, and owner
approval are also absent. The field verifier fails closed across source/artifact,
receipt/payload, device/release, cost, beta, rollback, and approval checks rather
than accepting a host fake or pending record.

Accordingly, the reconciled P10 decision is **NOT READY**. No host fake,
emulator, debug APK, historical record, pending reference, or unknown cost is
treated as field evidence, and no publication or distribution occurred.
