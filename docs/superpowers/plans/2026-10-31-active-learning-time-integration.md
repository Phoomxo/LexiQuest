# Active learning-time integration

Status: Root-approved execution plan under the existing request to complete LexiQuest's remaining systems. No new user approval gate is introduced. Collection stays default-off and local-only; no deployment, real Research enrollment/upload or efficacy claim is authorized.

Baseline: worktree C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest, branch codex/remaining-system-readiness, metadata9d4641bab9d864d780ada85f2a3796c57c5c9752 and application71a230a42ac767c956c0192eed6af01ee2521a59. [Wave22](../../field/2026-10-31-remaining-systems-wave22.md) attests Flutter4552/11:45, analysis0/18.1s, CLI23, offline390/one existing opt-in skip and normal APK with independent readback. All767 Dart inputs match. Schema is20/37; v21 remains unreserved until the genuine baseline capture below.

Grounding: D remaining-systems/focus-learning-time-next-grounding.md SHA242380ad6e56cc254b0dddb0229ebfed2f960c30411f944fb5bb8c9da9816eb2; writer proposal SHAda38f59796f3fe2d8f4d8aff263a96e93cf92423e5b0f8b80711c0841f514fed; activity proposal SHAd7a71c0fe317854dd5bc10282b8f70daf777b2a65fd593e314e9a0e846b577b3. Those proposals are source evidence and sketches; the decisions here supersede their alternatives.

## Outcome and boundaries

Implement one acknowledged behavior-time authority for actual ordinary learning, with owner-scoped durable records, a real runtime switch, and truthful P23/P24 readback. A TimeScope is a real time context; it is not a fabricated LearningSession. Opening a page, session elapsed, answer latency, a countdown or a callback count never grants time.

Support the current eligible configured Quiz family, owned SRS, eligible native/voice practice, early Reading and Tutor through their actual ready/input/wait states. Work in modules against one final model and use one integration checkpoint after those modules. Unknown sources, SRS previews, Focus Timer, generic navigation, menus and recreational Ghost/Word/Sentence Scramble cannot collect. All Research-controlled activities and Assessment are excluded from this ordinary first implementation; existing ordinary learning and optional Research behavior continue.

The 8/44 catalog, its semantic hash and EvidenceContext/EventEnvelopeV2 contracts remain frozen. Time creates no answer, learning session, reward/mastery/SRS, quest/streak, Research row/event or time outbox. Existing canonical writers and their ACKs remain authoritative. No new dependency, background service, OS alarm, cloud wire, calendar/weekly analytics or historical duration backfill is included.

## Seven Root policy decisions

1. Use the whole-feature B model: immutable source-pinned TimeScope identity plus immutable ClosedSegments, with an explicit optional one-time link to an actual canonical session. Early Reading and Tutor may have time without a LearningSession. Session-only admission was an engineering subset, not a frozen requirement.
2. Use confirmed interaction windows, policy revision confirmed-interaction-v1. A current ready source supplies an unconfirmed monotonic anchor. A later accepted semantic/user-edit action confirms a positive gap only when it is at most60 seconds and contains no excluded interval. A larger gap confirms none of that gap and establishes a new anchor. No terminal tail is credited. The60-second threshold is an engineering default, not a validated measure of attention or learning.
3. Suspend before provider/model/permission, canonical save/retry and unresolved speech/TTS/audio-busy work. Programmatic text/scroll/restore, provider replies and transcript fills do not become user input. An actual validated ready state can re-arm an unconfirmed anchor. Recognized semantic controls and user onChanged paths cover keyboard/accessibility as well as pointer input; explicit distinguishable user scroll can qualify, automatic scroll cannot.
4. Own one live credited collector slot. A new admitted activity cuts the preceding collector before it starts. A closed immutable write/link intent may finish after its old route/collector ends while its captured owner/policy permission remains valid. Owner null/error/done/ABA, fence, dependency replacement or capture rollback retires old unacknowledged work. Re-enable never revives it.
5. Seal contiguous confirmed windows at context/question/wait/close boundaries and after an input-triggered60-second checkpoint. Merge only adjacent confirmed pairs with matching context and no excluded gap. Keep at most one unresolved segment and one dependent session-link intent; pause capture while recovery is unresolved, without blocking learning. This bounds retained memory and unacknowledged exposure by the checkpoint plus the largest admitted input gap, not by an invented exact one-minute limit. No periodic capture scheduler is needed.
6. Exclude Research-controlled contexts rather than inferring ordinary authority from a missing database link. Use actual Study/Assessment caller context and canonical receipts in admission. The existing eligibility policy still denies recreational effort. Add no participant measurement or Research export field; current real enrollment/upload remains default-off.
7. Persist an explicit per-owner local capture choice, default false, with revision/CAS and immediate runtime rollback. Do not use global RuntimeFlags as an owner preference. This requires one real owner capture-preference relation in addition to the two time relations. ACKed history remains readable after disabling; disabling is not deletion. Normal account deletion/reset, personal/full export and owner rehome cover the new data. In a merge into an existing owner, that target's choice wins; an absent target choice remains disabled. An anonymous-bound upgrade retaining the same owner retains its choice.

Use microseconds for arithmetic/storage and sum before formatting; round only the displayed value. Store actual contiguous-window UTC observations separately from monotonic duration. A UTC correction cannot create duration; do not force false timestamp ordering or infer a restart gap. Calendar treatment of an uncertain device clock remains outside this card.

## Data shape and migration prerequisite

There is no owner-preference store for this choice. RuntimeFlags has key/bool/source/time fields and no owner column. A current-session-only or device-global switch would change the intended ownership/privacy semantics, so the selected model has three actual relations:

| Relation | Fields/invariants |
| --- | --- |
| learning_time_preferences | owner_id primary key/FK; enabled bool; positive revision; updated_at_utc_ms. Absent row means disabled. Explicit setting commands use original expected revision, desired state and fixed timestamp; exact lost-ACK replay succeeds without changing the revision twice. No-op state changes need not create a row or retire a valid collector. |
| learning_time_scopes | opaque id; owner_id FK; source_kind; strict versioned source_binding_json; created_at_utc_ms; nullable linked_session_id FK; nullable session_link_binding_json. Identity/source pins stay immutable. Link fields are absent together or set atomically once. Repeating the same verified link is idempotent; another target/binding conflicts. Linked scope retention follows its canonical session deletion; ordinary owner deletion removes unlinked scopes too. |
| learning_time_segments | opaque id; scope_id FK/cascade; nonnegative ordinal; strict versioned eligibility_context_json; started_at_utc_ms; ended_at_utc_ms; positive active_duration_us; capture_policy_revision. Unique scope/ordinal. Immutable facts. Child ownership is inherited through TimeScope, as quest progress already does. Duration is bounded by the checkpoint/window policy; UTC endpoints never calculate it. |

No raw input, answers, transcripts, chat text, API/config keys or auth UID enters these relations. Reading uses a strong digest of its actual immutable document/target snapshot; its31-bit fallback locator is insufficient alone. Tutor stores controlled task/mode/scenario and opaque response-display identity/model pins, not a hash of learner or reply text. Stage/question/assistance/context belongs on each segment, not in the stable Reading episode identity.

Materialize a scope with its first positive segment in the same owner-fenced transaction. Page-open/ready alone produces no time row. If a real session becomes available before any duration, keep its verified link in memory until a positive segment needs persistence. A later link for an already recorded scope updates only the dedicated link fields; it never rewrites old segments or inserts a zero-duration link segment.

Before any schema bump/reservation, capture the genuine current AppDatabase20 DDL and synthetic populated rows in every37 table to new test/fixtures/schema_v20.sql and populated_schema_v20.json. Record source9d4641ba/application71a, exact hashes and FK validation. Existing v19 fixtures are inputs, not a substitute for current runtime capture. Only after that evidence exists reserve v21 for these three relations, expected current table count40. Preserve every old row/column and add no historical time.

## Canonical and UI admission contract

Capture predecessor completed before any runtime schema edit: the actual AppDatabase20 generated all37 tables/indexes and64 synthetic rows. Exact replay/reopen, FK/integrity and all63 prior rows/pins pass; a second invocation reconciled identical files. Schema SHA25644b96f263f86fe9e32df8533a793fd14a3449a079bb889c3b0946e2c736581e7; populated SHA256fcb804bb185f2b3c2d43c41fce185ed99597ce18ae06c9a108507afa2cfdbcb4. D f24-schema-capture/schema_v20-capture-ca41b05b0efd2477.json SHA256ca41b05b0efd24778bb0e61106984e14899dc61ccb575aa341d8ff68b7c102ee pins21 actual capture inputs, current HEAD1b56fa03 and unrelated Export edits honestly. Logs wave23-v20-capture-first.log and wave23-v20-capture-reconcile.log each record one passing test. Runtime remains20/37 at capture; this is migration evidence, not f24 readiness.

New time types use a closed source union: configured Quiz state, original owned SRS handle, original accepted eligible native handle, actual Reading snapshot or actual scoped Tutor task. A public session ID/activity string cannot prove an owned prepared SRS/native exercise. Add a separate read-only canonical admission capability to the existing learning repository/use cases; preserve their private original-handle checks. Do not add a new learning writer or repurpose the best-effort single Study lifecycle observer.

Configured/owned source proof is admitted only after canonical start/resume ACK. It pins the same owner/database, accepted source and normalized eligibility context. Closed writes may survive a valid checkpoint advance or canonical finish; they must not require the old prompt to remain live.

Reading's current generic recall start does not persist a document-origin receipt. Migrate its actual start caller to a source-bound real start receipt/capability as needed. It must perform the same real canonical operation once and bind the original displayed snapshot; it must never start a session solely for time. Link only the actual acknowledged receipt with matching owner/source/targets and the prepared link intent. If an ACK is lost, retry the original intent or read acknowledged state; do not guess from UTC or shared words. A crash can leave genuine activity time unlinked; show that honestly rather than claiming crash-durable pending-link recovery.

Keep live collection, already-issued canonical/AI completion permissions and closed time persistence separate. Suspending time must not cancel a legitimate same-owner canonical operation or provider response. New UI actions need current route/pane/foreground and captured owner/context; a late same-owner response may complete only under its original still-valid response authority and cannot restart hidden time capture.

## Application API shape

Names below are the implementation contract to refine mechanically against the source, not new authorities per screen:

- LearningTimeUseCases owns source admission, one collector, clock arithmetic, owner/gate generations, bounded pending intents, source linking and dispatch to one repository.
- LearningTimeRepository owns per-owner gate CAS, immutable scope/segment commit/readback, explicit verified link and pure acknowledged reads. DriftLearningTimeRepository uses the same AppDatabase and OwnerWriteCoordinator as canonical learning.
- TimeSource is a closed typed union. Canonical proof is supplied by the read-only learning admission capability; Reading/Tutor proof uses their real owner/source/controller readiness. Unsupported/unknown contexts fail closed for time.
- LiveTimeLease and ClosedTimeSegmentIntent are opaque and module-issued. Screens cannot submit durations. Methods attach/admit, ready, interacted, suspend, detach, prepareSessionLink, acknowledgeSessionLink and retryPending preserve the original intent identity.
- TimeReadTarget distinguishes owner/activity, scope and real session. RecordedTimeRead distinguishes recorded, noneRecorded, unsupported and unavailable. In-memory pending/partial status is separate from acknowledged duration.
- LearningTimeBinding is the shared presentation owner/route/pane/lifecycle/dependency lease, using actual streams. RecordedTimeView is a pure read presentation used by P23/P24. No read creates an owner or collects time.
- LearningTimeSettingsScreen changes only the captured owner's local choice through the one use case. Old/hidden/foreign callbacks cannot change a new owner. The real runtime revision and in-memory epoch reject disable/re-enable and owner ABA during awaits.

Admission/collection and writes validate owner, fence, source/context pins and current capture policy at their proper boundaries. Reject inherited ambient transactions for operations promising their own commit ACK. Insert/readback exact immutable payloads; changed replays conflict. Return values only to the matching owner generation and original pending operation. Redact internal failures.

## Source write set

New module files: features/learning_time/domain/learning_time_models.dart and learning_time_repository.dart; application/learning_time_use_cases.dart; data/drift_learning_time_repository.dart; presentation/learning_time_binding.dart and recorded_time_view.dart, all under lib/. New lib/screens/learning_time_settings_screen.dart and lib/data/local/tables/learning_time_tables.dart. New read-only canonical admission types/capability under lib/features/learning/domain/learning_time_admission.dart.

Existing core: lib/data/local/app_database.dart and normally generated app_database.g.dart; lib/runtime/app_dependencies.dart and app_bootstrap.dart; lib/features/learning/application/learning_use_cases.dart and data/drift_learning_repository.dart. Capture-preference rehome, time-scope rehome/cascade, snapshot and export changes belong in the existing identity/account_deletion/export modules, including owner_upgrade.dart, drift_owner_upgrade_repository.dart, account_deletion_contracts.dart, drift_account_snapshot.dart, drift_local_account_deletion_gateway.dart, export_contracts.dart, drift_export_reader.dart and export_use_cases.dart where actual callers require them. Keep one writer per file.

Presentation: actual Quiz, owned SRS, eligible Dictation/Cloze/voice practice, associative Reading, Tutor, Score, Source Practice and Mastery screens/controllers; SettingScreen adds a separate time-settings entry. Do not add the control to appearance-only settings or make it depend on unrelated Progress success. Existing configured/native/owned canonical intents and return identities stay intact.

Tests: new learning_time domain/use-case/store/binding/readback/settings/admission/lifecycle suites; new genuine v20 fixtures and migration20→21 test. Extend actual touched screen, owner rehome/purge/full snapshot/personal export/sync exclusion and complete-inventory fixtures. Update a historical table-count assertion only when its actual complete inventory gains these tables; preserve all former data/behavior checks. Do not change37-pin Assessment contracts or historical schema values by blanket replacement.

No AGENTS/guardrail, frozen catalog JSON, backend/network gateway, learning/reward policy, deployment, existing WIP or denied cleanup target belongs to this write set.

## Readback and caller behavior

Quiz uses its real result owner/session after canonical finish ACK. Source Practice and native completion Score callers pass their actual validated summary identity too. Time failure/pending never blocks normal result/Done navigation. No count/latency becomes time.

For normal owned SRS, the existing completed state can show its acknowledged summary/time and Done when the feature is active; Done returns the exact original null result to void hosts. Source SRS retains its original automatic LearningSessionResult return and uses Source Practice's existing Score view. Preview remains unsaved/unrecorded. Do not add an unguarded Back fallback or change caller return types.

Reading can display its real scope total before a session exists; an actual later verified link supports session readback. Tutor can display an activity total, not a fake Score. P24 reads owner totals independently of empty/failed Progress; averageResponseTimeMs remains latency. History remains readable after collection is disabled with clear status.

Thai/English copy identifies locally recorded confirmed interaction time, excludes waits, and explains that long interaction-free reading may be undercounted. It is not attention, efficacy, speaking duration or mastery. Verify320px/200% text, IME, Light/Dark, keyboard/semantics, explicit exits, actual text wrapping and Reduced Motion. Real TalkBack/speech/device calibration remains a distinct release check.

## Execution cards and acceptance

1. Ground/capture: confirm current branch/schema/ledger, existing implementations and exact write sets. Capture/reopen genuine v20 DDL+populated37-table fixture, validate every FK/row and commit evidence. Then reserve21/40 with hashes and the precise three-table shape; no source bump before this.
2. Model/core: freeze compiling typed source/lease/intent/repository signatures before dependent code. Write fake-clock tests first, implement confirmed windows and bounded recovery, then verify threshold edges, UTC jumps, zero tail, exclusion, one-slot handoff and stale generations.
3. Store/lifecycle: add normally generated tables/store. Prove populated migration, exact replay/lost ACK/conflict, original closed A committing after B starts, owner/gate/fence/ambient-transaction rejection, explicit link/collision, target-owner preference merge, export/cascade/backup/sync exclusion. No time outbox or other37-table mutation from time-only operations.
4. Adapters: wire real Quiz/SRS, Reading/Tutor and eligible native/voice modules with their actual ready/input/wait boundaries. Prove early Reading/Tutor positive time without a LearningSession, no row from page-open alone, no programmatic/audio/recreational/Research capture, and unchanged canonical learning/AI completion. Ordinary learning must continue through time failures.
5. Readback/control: prove captured-owner runtime switching, disable/re-enable during writes, all actual P23 paths, independent P24 on sampleSize0/Progress failure, unavailable/none/pending states, no read-time owner creation and old callback/IME/route safety.
6. Integration: stop writers, independently review connected code, run focused and affected checks, analysis, full regression, CLI/offline backend and normal main/debug APK on one frozen committed source. Inspect real rendered UI and actual APK/source identity. Record exact evidence and unresolved release-only limits before any readiness change.

Use disjoint D drafts for parallel implementation; Root alone promotes C changes and serializes Flutter/pub/codegen/analysis/full/build. Keep a decision trail, preserve negative/incomplete evidence and all user WIP, and do not retry denied cleanup. This plan authorizes local engineering work; it does not assert implementation, migration, readiness or deployment completion.

