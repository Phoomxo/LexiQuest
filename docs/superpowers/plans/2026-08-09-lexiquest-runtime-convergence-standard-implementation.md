# LexiQuest Runtime Convergence and Field-Trial Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the existing P0–P10 file inventory into one coherent LexiQuest field-trial application whose advertised capabilities are reachable from the production entry point, use the production composition root, persist under the correct owner, pass bounded automated gates, and are supported by exact APK and device evidence.

**Architecture:** Keep `AppDatabase` schema 12 and `localOwnerId` as the local source of truth. Compose all production dependencies in `AppBootstrap`, expose them through `AppDependenciesScope`, route every visible feature through a declared production entry point, and treat Firebase, AI, voice, and model services as bounded optional extensions around an offline-capable learning core. Integrate behavior in vertical slices; divergent branches are read-only donor sources and are never merged wholesale.

**Tech Stack:** Flutter/Dart, Drift/SQLite schema 12, Firebase Auth/Firestore/App Check, optional Supabase policy surfaces, Android Gradle/Kotlin, PowerShell 5.1 release gates, Python `uv` CPU-only backend tests, Gitleaks 8.30.1, OSV-Scanner 2.4.0, signed Android APKs.

## Global Constraints

- Canonical worktree: `C:\Users\Phet\Documents\LexiQuest\.worktrees\p0-integration`.
- Canonical branch: `codex/runtime-convergence`, created from `c706ce2`.
- Single Writer: only Codex in this task edits files, runs mutating commands, stages, commits, rebases, or decides integration.
- Preserve the user's dirty checkout and every existing branch/worktree. Do not delete, reset, clean, or overwrite them.
- Treat `release/v0.1-complete-system`, `feature/associative-reading-loop`, `feature/production-readiness-integration`, `feature/p8a-voice-architecture`, and other branches as read-only donor sources. Import only reviewed hunks or commits with compatible tests.
- MaxPlus Specialist Adaptive may be used when it can materially reduce architecture, migration, concurrency, release, or acceptance risk. Specialists remain read-only; their output is advisory and never substitutes for code, tests, APK, or device evidence.
- Do not invoke, install, resume, or recommend Codex Security, Security Scan, Deep Scan, or any Codex Security worker workflow.
- Keep `AppDatabase` schema version monotonic at 12 or higher. A schema change must include migration tests, generated Drift code, owner-upgrade inventory, export, and deletion coverage in the same slice.
- `localOwnerId` owns local business and research data. Firebase UID is an account binding, not a replacement primary key.
- Do not use `InMemoryAssociativeLearningAdapter` or another in-memory user-data repository in production composition.
- `FeatureRegistry` and `RuntimeFeatureControls` must govern both visibility and invocation. A hidden or disabled capability cannot be opened by an alternate UI path.
- Local vocabulary, Quiz, SRS, reading, progress, rewards, quest, streak, and export remain usable when cloud, AI, voice, or model services are unavailable.
- Central operating cost target is 0–100 THB/month. Do not make Supabase Pro, Hugging Face PRO, GPU VPS, or Cloud Run a baseline dependency.
- Use test-first development for behavior changes: one failing focused test, one minimal implementation, one passing focused gate.
- Do not repeat passing gates without a relevant code or environment change. Do not run test loops.
- If the same failure occurs twice, stop that method and record a root-cause hypothesis before another attempt. Stop and report if no measurable progress occurs for ten minutes.
- Never fabricate signing, physical-device, App Check, provider, consent, participant, or owner-approval evidence.

---

## Authority and current baseline

This document is the execution authority for runtime convergence after `c706ce2`. It supersedes the execution mechanics in `docs/superpowers/plans/2026-08-08-lexiquest-complete-field-trial-release-execution.md`. The 2026-08-08 convergence design and `docs/superpowers/plans/2026-08-09-p0-p10-verification-and-correction.md` remain historical evidence and design input; their completion marks do not prove current runtime delivery.

Known baseline facts:

- `lib/main.dart` always selects `AppRoute.login` for a normal launch even though `AppStartRouteResolver` exists.
- `AppBootstrap` composes `InMemoryAssociativeLearningAdapter` in production even though `DriftAssociativeLearningAdapter` exists and is tested.
- `AssociativeReadingSessionScreen` has no production launcher from `ChooseModeScreen` and silently creates an in-memory adapter.
- There is no `integration_test/` directory.
- The current “device certification journey” is a host test with in-memory Drift; it is not device evidence.
- The production shell navigation test manually enters Home with mostly-null dependencies, so it does not prove bootstrap-to-feature composition.
- The last reachability audit found 206 of 315 Dart files reachable from `lib/main.dart`, 109 unreachable Dart files, 11 unreachable screens, 35 of 41 unreachable `lib/services` files, and 13 of 14 unreachable `lib/learning` files.
- Current release status is not ready: signing/APK, real-device, provider, beta, and release-approval evidence remain external gates.

## Source-of-truth ledger

| Subsystem | Runtime authority | Durable authority | Donor policy |
|---|---|---|---|
| App launch and dependency graph | `lib/main.dart`, `lib/runtime/app_bootstrap.dart`, `lib/runtime/app_dependencies.dart` | persisted app-entry state plus active owner | Adapt tested entry-state behavior only |
| Navigation and feature availability | `lib/navigation/`, `lib/runtime/registries/feature_registry.dart`, `lib/runtime/runtime_feature_override_store.dart` | Drift runtime overrides | No screen is accepted from file presence alone |
| Local identity | `lib/features/identity/` | `local_owners` and owner-upgrade inventory | `localOwnerId` remains stable across account binding |
| Account identity | `lib/features/account/` | Firebase Auth session plus local UID binding | Cloud failure must not destroy the local owner |
| Vocabulary | `lib/features/vocabulary/` | Drift vocabulary/category tables | Legacy services cannot bypass owner-scoped repositories |
| Learning, SRS, progress | `lib/features/learning/`, `lib/features/progress/` | Drift attempts, SRS state, progress projections, event envelope | `lib/learning/` algorithms may be adapted behind production ports |
| Quest, streak, rewards | `lib/features/quest/`, `lib/features/motivation/`, `lib/features/rewards/` | Drift projections and idempotency keys | Replay from durable learning events when side effects fail |
| Associative reading | `AssociativeReadingSessionScreen` plus production launcher | `association_records`, `associative_memory_states`, reading progress | Production receives `DriftAssociativeLearningAdapter` explicitly |
| Sync | `lib/features/sync/` | Drift outbox/checkpoint/lease plus Firestore | Local commit precedes best-effort cloud delivery |
| AI and voice | `lib/features/ai_tutor/`, `lib/features/gemini/`, `lib/features/voice/` | owner-scoped usage/settings/evidence stores | One composed facade per capability; bounded fallback only |
| Device model and media | `lib/features/device_model/`, `lib/features/media_practice/` | pinned manifest, checksum, download ledger | Physical behavior requires exact-device evidence |
| Export and deletion | `lib/features/export/`, `LocalDataDeletion` | every owner-scoped table and owner secret | Schema additions update both surfaces in the same commit |
| Release evidence | `tool/cli/package-field-release.ps1`, `tool/cli/verify-field-release.ps1` | exact source SHA, APK SHA-256, certificate digest, evidence JSON | Old APK evidence expires after any byte-changing rebuild |

## Delivery-state vocabulary

- `orphan`: file exists but no production caller.
- `wired`: reachable from the production shell with real composed dependencies.
- `durable`: state survives database close/reopen and is owner-scoped.
- `verified`: focused automated behavior and production-composition tests pass.
- `field-certified`: exact APK/device/provider evidence passes the release verifier.
- `hidden`: intentionally unavailable and blocked at every invocation path.
- `legacy`: retained only because a verified production path still depends on it.

## Definition of Ready and Done

A capability may enter a slice only when its production entry point, dependency owner, durable repository, failure behavior, focused test, and rollback commit are named.

A capability is locally complete only when this chain is proven:

`production launch → visible entry point → screen/controller → use case → owner-scoped repository → durable database/outbox → restart/replay test`

A capability is field complete only when the local chain passes and the exact release APK hash is connected to required device, App Check, provider, consent, and owner-approval evidence.

## Execution protocol

1. Record `git rev-parse HEAD` as the pre-slice rollback point.
2. Write one focused failing test for the missing production behavior.
3. Run only that test and confirm it fails for the expected reason.
4. Implement the smallest production path that satisfies the test.
5. Run the focused test, the slice gate, `flutter analyze` when Dart production code changed, and `git diff --check`.
6. Review `git diff --stat` and `git diff --name-status`; confirm no unrelated user file is present.
7. Commit one coherent vertical slice. To reject the just-created slice, run `$sliceCommit = (git rev-parse HEAD).Trim()` followed by `git revert $sliceCommit`; never use a destructive reset.
8. Update the feature ledger with status, test command, commit, and evidence path.
9. Advance only when the slice Exit Gate passes; an external gate may remain explicitly blocked without preventing unrelated local development.

## MaxPlus Specialist Adaptive protocol

Codex remains the Single Writer and final decision-maker. MaxPlus specialists may inspect one explicitly named file and return advice, but they never edit files, run mutating commands, stage, commit, rebase, manage Git, or approve a release. Codex must independently inspect the advice, implement any accepted change, and prove it with the plan's normal code, test, APK, and device gates.

Before the first MaxPlus analysis in each work period, run Health once:

~~~powershell
& 'C:\Users\Phet\AppData\Local\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1' `
  -Command Health `
  -ProjectRoot 'C:\Users\Phet\Documents\LexiQuest\.worktrees\p0-integration'
~~~

Proceed only when Health reports `ready`. Health is a control-plane check, not a provider call and not release evidence. The currently observed Health status is `ready`, with routes:

- `gpt-stable` -> `gpt-5.6-sol`.
- `claude-reviewer` -> `claude-sonnet-5` for normal review or `claude-opus-5` for high-risk review.
- Do not claim Terra, Fable, or GLM was used through this connector until Health/config exposes a route that can actually be selected.

Choose effort and reviewer from this table:

| Situation | Effort | Reviewer |
|---|---|---|
| Inventory, log summary, or failure triage | `Low` | None; use `-NoReviewer` |
| One-file change or bounded test design | `Medium` | None; use `-NoReviewer` |
| Multi-part behavior or complex regression | `High` | `claude-sonnet-5` only when a second opinion is material |
| Architecture, schema, migration, sync, concurrency, or auth | `XHigh` | `claude-opus-5` required; omit `-NoReviewer` |
| Release blocker with explicit verification criteria | `Max` | `claude-opus-5` required; omit `-NoReviewer` |

Provider-call budgets apply per task decision gate: ordinary work permits at most one provider call; high-risk work permits at most two provider calls in sequence. A reviewed `Analyze` run counts as the primary provider call followed by the reviewer call. Never issue provider calls concurrently.

Every `Analyze` request must name one repository-relative file, one focused question, the selected effort, and concrete acceptance criteria. Never send a secret, credential, auth token, private key, keystore, participant or field evidence, APK, build artifact, generated release package, or denylisted file. The denylist includes `android/key.properties`, `*.jks`, `*.keystore`, `.env*`, `field/evidence/**`, `build/**`, `*.apk`, and any file containing real provider keys or participant identifiers.

Use MaxPlus only at the named decision gates in Tasks 1, 3, 5, 7, 8, 10, and 12. Do not use it for formatting, an obvious local correction, routine test execution, or to repeat a conclusion Codex has already proved from code or evidence.

For a one-provider request, use:

~~~powershell
& 'C:\Users\Phet\AppData\Local\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1' `
  -Command Analyze `
  -ProjectRoot 'C:\Users\Phet\Documents\LexiQuest\.worktrees\p0-integration' `
  -Task 'Read-only focused analysis with concrete acceptance criteria' `
  -Path 'lib/path/to/single_file.dart' `
  -Effort Medium `
  -NoReviewer `
  -TimeoutSeconds 120
~~~

For an architecture or release-blocker gate, replace `-Task`, `-Path`, and `-Effort` with the gate's exact values, use `XHigh` or `Max`, and omit `-NoReviewer` so the required Opus review runs sequentially.

Treat empty, non-actionable, or failed provider output as advisory failure: Codex continues independently and never retries the same prompt. If the same MaxPlus-path failure occurs twice, or the path makes no measurable progress for ten minutes, stop using MaxPlus for that decision and record the observed failure, root-cause hypothesis, and unaffected work that can continue.

## Checkpoints

| Checkpoint | Included tasks | Required outcome |
|---|---|---|
| A — platform/data | Tasks 0–5 | launch, identity, vocabulary, learning, associative reading, and sync are wired and durable |
| B — device/AI/voice | Tasks 6–7 | visible advanced features use composed dependencies and bounded fallbacks |
| C — hardening | Task 8 | controls, deletion/export, observability, cost, secrets, and dependency gates pass |
| D — release | Tasks 9–12 | integration journeys, signed APK, physical evidence, readiness, and acceptance are consistent |

### Task 0: P0 baseline, authority, and runtime feature ledger

**Files:**
- Create: `docs/field/2026-08-09-runtime-feature-ledger.md`
- Create: `test/architecture/production_feature_contract_test.dart`
- Inspect: `lib/runtime/registries/feature_registry.dart`
- Inspect: every file under `lib/screens/`

**Interfaces:**
- Consumes: `Feature.values`, `FeatureRegistry.stateOf(Feature)`, production UI entry points.
- Produces: one ledger row per `Feature` and per user-visible screen, with `orphan|wired|durable|verified|field-certified|hidden|legacy` status.

- [x] **Step 1: Preserve the user checkout and establish the integration branch**

Run:

~~~powershell
git status --short --branch
git log -1 --oneline
git worktree list --porcelain
~~~

Expected: clean `codex/runtime-convergence` at `c706ce2`; the dirty normal checkout remains untouched.

- [x] **Step 2: Save this standard execution plan without rewriting historical plans**

Expected: this file exists only on `codex/runtime-convergence` and names the current base.

- [ ] **Step 3: Write the feature ledger**

Use this exact column contract:

~~~markdown
| Capability | Feature flag | Production entry | Composed dependency | Durable store | Restart test | Field evidence | State |
~~~

List every `Feature.values` member and all screens returned by `rg --files lib/screens`. Mark the current state from code evidence; do not infer delivery from filename or historical phase labels.

- [ ] **Step 4: Write the failing production feature contract**

The test must assert:

~~~dart
expect(Feature.values.toSet(), equals(deliveryContract.keys.toSet()));
for (final entry in deliveryContract.entries) {
  if (entry.value.isVisible) {
    expect(entry.value.productionEntryId, isNotEmpty);
    expect(entry.value.dependencyId, isNotEmpty);
  }
}
~~~

Define `deliveryContract` inside the test initially. Move it to production code only in Task 6 when the UI consumes it.

- [ ] **Step 5: Run the bounded baseline**

Run:

~~~powershell
flutter analyze
flutter test test/architecture/fitness_test.dart test/runtime/app_bootstrap_test.dart test/screens/production_shell_navigation_test.dart test/scenarios/device_certification_journey_test.dart --reporter compact
git diff --check
~~~

Expected: analysis and existing tests pass; the new contract fails only for visible capabilities without a declared production path.

- [ ] **Step 6: Commit the P0 authority checkpoint**

Run:

~~~powershell
git add docs/superpowers/plans/2026-08-09-lexiquest-runtime-convergence-standard-implementation.md docs/field/2026-08-09-runtime-feature-ledger.md test/architecture/production_feature_contract_test.dart
git commit -m "docs(p0): establish runtime convergence authority"
~~~

Expected: one commit containing plan, ledger, and executable baseline contract.

### Task 1: P1 production launch and persisted identity

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `lib/runtime/app_start_route_resolver.dart`
- Modify: `lib/features/session/data/shared_preferences_app_entry_state_store.dart`
- Modify: `lib/services/guest_session_service.dart`
- Modify: `lib/features/account/application/account_use_cases.dart`
- Create: `test/runtime/app_start_route_resolver_test.dart`
- Create: `test/features/session/shared_preferences_app_entry_state_store_test.dart`
- Modify: `test/runtime/app_bootstrap_test.dart`
- Modify: `test/services/guest_session_service_test.dart`
- Modify: `test/features/account/account_use_cases_test.dart`
- Modify: `test/screens/production_shell_navigation_test.dart`

**Interfaces:**
- Consumes: `AppEntryStateStore.read()`, `markGuest()`, `clear()` and `AccountUseCases.currentSession`.
- Produces: `AppDependencies.initialRoute: AppRoute` and `AppEntryStateStoreFactory = Future<AppEntryStateStore> Function()`.

**MaxPlus decision gate (required after Step 2, before Step 3):**
- Question: `Review the production bootstrap identity boundary. Which concrete initialization, ownership, or rollback defects could make signed-out, explicit-guest, authenticated, or sign-out launch state diverge across restart?`
- Path: `lib/runtime/app_bootstrap.dart`
- Effort: `XHigh`
- Reviewer: `claude-opus-5` required; omit `-NoReviewer`.
- Acceptance criteria: findings are actionable against this file; one entry-state store instance feeds route resolution and session transitions; `localOwnerId` remains stable through account binding; failed auth/bootstrap cannot erase the local owner or guest choice; initialization and disposal cannot duplicate or leak composed services. Codex validates accepted findings with the Task 1 focused tests and production-shell gate.

- [ ] **Step 1: Write failing launch-state tests**

Cover this exact matrix:

~~~dart
expect(await resolver.resolve(hasAuthenticatedSession: false), AppRoute.login);
await entryState.markGuest();
expect(await resolver.resolve(hasAuthenticatedSession: false), AppRoute.home);
expect(await resolver.resolve(hasAuthenticatedSession: true), AppRoute.home);
await entryState.clear();
expect(await resolver.resolve(hasAuthenticatedSession: false), AppRoute.login);
~~~

Also assert that clearing an already-empty `SharedPreferencesAppEntryStateStore` succeeds.

- [ ] **Step 2: Verify the tests fail for production integration reasons**

Run:

~~~powershell
flutter test test/runtime/app_start_route_resolver_test.dart test/features/session/shared_preferences_app_entry_state_store_test.dart test/runtime/app_bootstrap_test.dart test/services/guest_session_service_test.dart test/features/account/account_use_cases_test.dart --reporter compact
~~~

Expected: failure because `AppDependencies` lacks `initialRoute` and bootstrap/session flows do not persist the explicit entry choice.

- [ ] **Step 3: Add the public launch-state interfaces**

Implement these signatures:

~~~dart
typedef AppEntryStateStoreFactory = Future<AppEntryStateStore> Function();

final class AppStartRouteResolver {
  AppStartRouteResolver({required AppEntryStateStore entryState})
      : _entryState = entryState;

  final AppEntryStateStore _entryState;
}
~~~

Add `required this.initialRoute` and `final AppRoute initialRoute;` to `AppDependencies`.

- [ ] **Step 4: Compose entry state once in bootstrap**

Production creates:

~~~dart
Future<AppEntryStateStore> createProductionEntryStateStore() async {
  final preferences = await SharedPreferences.getInstance();
  return SharedPreferencesAppEntryStateStore(preferences);
}
~~~

`AppBootstrap.initialize()` must create one store, pass it to guest/account services, resolve from `account?.currentSession != null`, and return the resulting `initialRoute` in `AppDependencies`.

- [ ] **Step 5: Persist transitions**

`OwnerBindingGuestSessionService.start()` calls `markGuest()` before returning local guest success. `AccountUseCases.register()` and `signIn()` clear the guest marker after successful owner binding. `signOutToLocalGuest()` clears the marker as part of the rollback-aware sign-out operation. `SharedPreferencesAppEntryStateStore.clear()` is idempotent when the key is absent.

- [ ] **Step 6: Remove the hard-coded startup route**

`MyApp` uses:

~~~dart
initialRoute: dependencies.initialRoute.path,
~~~

Delete the private logic that always maps a normal platform launch to Login. Keep deep-link handling only where `AppRouteFactory` supports it.

- [ ] **Step 7: Run the identity gate and commit**

Run:

~~~powershell
dart format lib/main.dart lib/runtime lib/features/session lib/features/account/application/account_use_cases.dart lib/services/guest_session_service.dart test/runtime test/features/session test/features/account/account_use_cases_test.dart test/services/guest_session_service_test.dart test/screens/production_shell_navigation_test.dart
flutter test test/runtime/app_start_route_resolver_test.dart test/features/session/shared_preferences_app_entry_state_store_test.dart test/runtime/app_bootstrap_test.dart test/services/guest_session_service_test.dart test/features/account/account_use_cases_test.dart test/screens/production_shell_navigation_test.dart --reporter compact
flutter analyze
git diff --check
git add lib test
git commit -m "fix(p1): persist production launch identity"
~~~

Expected: signed-out launch opens Login; an explicit guest choice survives restart; authenticated launch opens Home; sign-out returns the next launch to Login.

### Task 2: P1 owner-scoped vocabulary vertical slice

**Files:**
- Modify when a failing test proves a gap: `lib/features/vocabulary/`, `lib/screens/categories_page.dart`, `lib/screens/vocab_list_screen.dart`, `lib/screens/add_vocab_screen.dart`, `lib/screens/add_multiple_words_screen.dart`
- Create: `test/scenarios/production_vocabulary_restart_test.dart`
- Modify: `test/screens/production_shell_navigation_test.dart`

**Interfaces:**
- Consumes: `VocabularyUseCases.createCategory(String)`, `createWord(CreateWordCommand)`, `watchCategories()`, `watchWords(String)`.
- Produces: a production-shell journey that opens vocabulary, writes through `DriftVocabularyRepository`, closes the database, reopens the same SQLite file, and reads only the active owner's rows.

- [ ] **Step 1: Write the failing file-backed restart journey**

Use `AppDatabase(NativeDatabase(File(databasePath)))`. Create a category and word through `VocabularyUseCases`, dispose all dependencies, reopen the same path, and assert spelling, meaning, category, and `ownerId` are unchanged.

- [ ] **Step 2: Add the production-shell assertion**

Pump `MyApp(dependencies: await bootstrap.initialize())` from the resolved Home route, navigate through the visible vocabulary entry, create a word, and verify it appears without manually pushing `MainNavigationScreen`.

- [ ] **Step 3: Run the failing tests**

Run:

~~~powershell
flutter test test/scenarios/production_vocabulary_restart_test.dart test/screens/production_shell_navigation_test.dart --reporter compact
~~~

Expected: a failure identifies either a missing entry point, a missing dependency, or a persistence defect.

- [ ] **Step 4: Repair only the proven link**

UI code obtains `VocabularyUseCases` from `AppDependenciesScope`. No screen constructs a repository, database, or in-memory vocabulary list as production authority.

- [ ] **Step 5: Run the local-first gate and commit**

Run:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-local-first.ps1
flutter test test/scenarios/production_vocabulary_restart_test.dart --reporter compact
git diff --check
git add lib test docs/field/2026-08-09-runtime-feature-ledger.md
git commit -m "feat(p1): prove durable vocabulary journey"
~~~

Expected: restart and owner-isolation tests pass; ledger marks vocabulary `verified`.

### Task 3: P2 learning, SRS, progress, quest, streak, and rewards

**Files:**
- Modify when required: `lib/features/learning/application/learning_use_cases.dart`
- Modify when required: `lib/features/learning/data/drift_learning_repository.dart`
- Modify when required: `lib/features/quest/`, `lib/features/motivation/`, `lib/features/rewards/`
- Create: `test/scenarios/production_learning_restart_test.dart`
- Create only if the failure is reproduced: `lib/features/learning/application/learning_side_effect_reconciler.dart`
- Create only with that reconciler: `test/features/learning/learning_side_effect_reconciler_test.dart`

**Interfaces:**
- Consumes: `LearningUseCases.startQuiz`, `recordAnswer`, Drift event envelope/outbox, quest/streak/reward idempotency keys.
- Produces when needed: `LearningSideEffectReconciler.reconcileOwner(String ownerId): Future<void>`, replaying durable learning events into idempotent projections.

**MaxPlus decision gate (conditional after Step 2, before creating a reconciler):**
- Trigger: invoke only when failure injection leaves the transaction/replay boundary or duplicate-prevention behavior materially ambiguous.
- Question: `Review the learning write and side-effect boundary. Is a separate reconciler required, and what exact event identity and applied-version rules prevent duplicate XP, quest, streak, or reward projections after failure and restart?`
- Path: `lib/features/learning/application/learning_use_cases.dart`
- Effort: `High`
- Reviewer: `claude-sonnet-5` when the trigger requires a material second opinion; otherwise use one provider with `-NoReviewer`.
- Acceptance criteria: the core attempt and SRS commit are never rolled back by a projection failure; replay uses stable event-derived idempotency keys; each projection is independently retryable; network sync stays outside the local transaction; no reconciler is added when existing code and tests already prove these properties.

- [ ] **Step 1: Write the file-backed learning journey**

Create vocabulary through production use cases, start Quiz, record correct and incorrect answers, close/reopen the database, then assert attempt count, SRS due state, mastery/weakness projections, XP, quest progress, streak day, and outbox event identity.

- [ ] **Step 2: Write failure-injection assertions**

Inject quest and streak sinks that throw after the core repository transaction. Assert the learning attempt and SRS state persist, the event remains replayable, and retry does not duplicate XP or quest progress.

- [ ] **Step 3: Run focused tests**

Run:

~~~powershell
flutter test test/features/learning/drift_learning_repository_test.dart test/features/learning/learning_use_cases_test.dart test/features/rewards test/features/quest test/features/motivation test/scenarios/production_learning_restart_test.dart --reporter compact
~~~

Expected: any failure must name the missing projection or replay path; core local learning must remain committed.

- [ ] **Step 4: Implement durable reconciliation only if the failure exists**

Read committed event-envelope rows for the owner, call quest/streak/reward sinks with stable event-derived idempotency keys, and record each projection's applied version. Do not place network sync inside the local learning transaction.

- [ ] **Step 5: Run the learning gate and commit**

Run:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-learning-core.ps1
flutter test test/scenarios/production_learning_restart_test.dart --reporter compact
git diff --check
git add lib test docs/field/2026-08-09-runtime-feature-ledger.md
git commit -m "feat(p2): converge durable learning projections"
~~~

Expected: one answer produces one durable attempt and idempotent downstream projections across restart.

### Task 4: P2 associative reading production path

**Files:**
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/screens/choose_mode_screen.dart`
- Modify: `lib/screens/associative_reading_session_screen.dart`
- Create: `lib/screens/associative_reading_launcher_screen.dart`
- Create: `test/screens/associative_reading_launcher_screen_test.dart`
- Modify: `test/screens/associative_reading_session_screen_test.dart`
- Create: `test/scenarios/associative_reading_restart_test.dart`

**Interfaces:**
- Consumes: `VocabularyUseCases.getGameWords({int limit = 10})`, `LearningUseCases`, `DriftAssociativeLearningAdapter(AppDatabase)`.
- Produces: launcher-selected target words, word IDs, passage, CEFR level, document ID/revision, and an explicitly injected `AssociativeLearningPort`.

- [ ] **Step 1: Write failing reachability and restart tests**

Assert that Choose Mode contains an Associative Reading tile when `Feature.reading` is visible, tapping it opens the launcher, completing an association writes `association_records` and `associative_memory_states`, and reopening the SQLite file restores the records for the active owner.

- [ ] **Step 2: Verify the tests fail**

Run:

~~~powershell
flutter test test/screens/associative_reading_launcher_screen_test.dart test/screens/associative_reading_session_screen_test.dart test/scenarios/associative_reading_restart_test.dart --reporter compact
~~~

Expected: failure because no launcher exists and production bootstrap currently composes the in-memory adapter.

- [ ] **Step 3: Replace the production adapter**

`AppBootstrap` imports `drift_associative_learning_adapter.dart` and creates:

~~~dart
final associativeLearning = DriftAssociativeLearningAdapter(database);
~~~

Remove the production comment and contract that promises an in-memory fallback.

- [ ] **Step 4: Build the launcher from owned vocabulary**

The launcher calls `getGameWords(limit: 10)`, requires at least one saved word, builds `targetWordIds` from `VocabularyWord.id`, and passes `dependencies.learning` and `dependencies.associativeLearning` into `AssociativeReadingSessionScreen`. Empty vocabulary shows a deterministic action back to vocabulary creation.

- [ ] **Step 5: Eliminate the screen-level production fallback**

In `didChangeDependencies`, obtain `associativeLearning` from the widget or `AppDependenciesScope`. If neither exists, render a typed unavailable state; do not create `InMemoryAssociativeLearningAdapter` inside the screen.

- [ ] **Step 6: Run and commit**

Run:

~~~powershell
dart format lib/runtime/app_bootstrap.dart lib/runtime/app_dependencies.dart lib/screens/choose_mode_screen.dart lib/screens/associative_reading_launcher_screen.dart lib/screens/associative_reading_session_screen.dart test/screens test/scenarios/associative_reading_restart_test.dart
flutter test test/features/learning/drift_associative_learning_adapter_test.dart test/screens/associative_reading_launcher_screen_test.dart test/screens/associative_reading_session_screen_test.dart test/scenarios/associative_reading_restart_test.dart --reporter compact
flutter analyze
git diff --check
git add lib test docs/field/2026-08-09-runtime-feature-ledger.md
git commit -m "feat(p2): wire durable associative reading"
~~~

Expected: reading is reachable, owner-scoped, restart-safe, and no production caller creates the in-memory adapter.

### Task 5: P2 sync, reconnect, and guest upgrade

**Files:**
- Modify when proven: `lib/features/sync/`
- Modify when proven: `lib/features/identity/application/upgrade_guest_owner.dart` and repositories
- Modify when proven: `lib/services/guest_session_service.dart`
- Create: `test/scenarios/file_backed_sync_recovery_test.dart`
- Create: `test/scenarios/guest_upgrade_restart_test.dart`

**Interfaces:**
- Consumes: `SyncEngine.run()`, `SyncTrigger.request(SyncTriggerReason)`, `UpgradeGuestOwner.call`, Drift outbox/checkpoint/lease.
- Produces: restart-safe outbox replay, bounded retry, and one-owner continuity across anonymous/authenticated upgrade.

**MaxPlus decision gate (required after Step 3, before Step 4):**
- Question: `Review the sync engine's concurrency and recovery contract. Which exact lease, checkpoint, idempotency, and error-classification invariants are required to prevent duplicate upload, skipped outbox work, or concurrent runs after restart?`
- Path: `lib/features/sync/application/sync_engine.dart`
- Effort: `XHigh`
- Reviewer: `claude-opus-5` required; omit `-NoReviewer`.
- Acceptance criteria: at most one active run owns the lease; replay preserves existing event IDs; checkpoints advance only after accepted durable delivery; permanent configuration/provider errors stop immediately; transient retry is bounded; a crash or restart leaves recoverable work without duplicate upload. Codex proves accepted findings with the Task 5 file-backed sync and guest-upgrade tests.

- [ ] **Step 1: Write offline/reconnect tests**

Queue vocabulary and learning mutations with a failing gateway, close/reopen the database, switch to a successful fake gateway, run sync once, and assert each event uploads once and the checkpoint advances.

- [ ] **Step 2: Write guest-upgrade tests**

Create guest-owned category, word, learning attempt, SRS, association, quest, streak, reward, consent, AI usage, and outbox rows. Bind a Firebase UID and assert all inventory rows remain under the same local owner with no duplicates after restart.

- [ ] **Step 3: Run focused tests**

Run:

~~~powershell
flutter test test/features/sync test/features/identity test/scenarios/file_backed_sync_recovery_test.dart test/scenarios/guest_upgrade_restart_test.dart --reporter compact
~~~

- [ ] **Step 4: Repair only failed inventory, lease, or replay contracts**

Every retry uses existing idempotency IDs. Permanent provider/configuration failures stop immediately; transient retry counts remain bounded.

- [ ] **Step 5: Run Checkpoint A**

Run:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-sync.ps1
flutter test test/scenarios/production_vocabulary_restart_test.dart test/scenarios/production_learning_restart_test.dart test/scenarios/associative_reading_restart_test.dart test/scenarios/file_backed_sync_recovery_test.dart test/scenarios/guest_upgrade_restart_test.dart --reporter compact
flutter analyze
git diff --check
~~~

Expected: Checkpoint A passes without network access.

- [ ] **Step 6: Commit**

Run:

~~~powershell
git add lib test docs/field/2026-08-09-runtime-feature-ledger.md
git commit -m "feat(p2): prove restart-safe sync and owner upgrade"
~~~

### Task 6: P3 production navigation, games, device model, and media

**Files:**
- Create: `lib/runtime/production_feature_contract.dart`
- Modify: `lib/runtime/registries/feature_registry.dart`
- Modify: `lib/screens/main_navigation_screen.dart`
- Modify: `lib/screens/choose_mode_screen.dart`
- Modify: `lib/screens/game_launcher_screen.dart` and user-visible game screens
- Modify: `lib/screens/object_scanner_screen.dart`, `lib/screens/shadowing_challenge_screen.dart`, `lib/screens/speak_to_text_screen.dart`
- Modify: `test/architecture/production_feature_contract_test.dart`
- Create: `test/scenarios/production_feature_navigation_test.dart`

**Interfaces:**
- Produces: `ProductionFeatureDelivery` with `Feature feature`, `String productionEntryId`, `String dependencyId`, and `bool durable`; `productionFeatureContract: Map<Feature, ProductionFeatureDelivery>`.
- Consumes: `FeatureRegistry.isVisible(Feature)` and the composed vocabulary/device/media dependencies.

- [ ] **Step 1: Move the complete delivery contract into production code**

Use this shape:

~~~dart
final class ProductionFeatureDelivery {
  const ProductionFeatureDelivery({
    required this.feature,
    required this.productionEntryId,
    required this.dependencyId,
    required this.durable,
  });

  final Feature feature;
  final String productionEntryId;
  final String dependencyId;
  final bool durable;
}
~~~

The map contains every `Feature.values` member exactly once.

- [ ] **Step 2: Write navigation and kill-switch tests**

For every enabled or limited capability, start from `MyApp` and tap its declared entry. For every hidden capability, assert no tile/action is present and direct invocation returns the shared unavailable experience.

- [ ] **Step 3: Replace demo data paths**

Game launchers request `VocabularyUseCases.getGameWords`. Object scanner uses `ObjectScannerController` from dependencies. Speech surfaces use composed speech/voice interfaces. When no owned vocabulary or platform capability exists, show a typed empty/unavailable state without synthetic participant progress.

- [ ] **Step 4: Run P3 gates**

Run sequentially:

~~~powershell
flutter test test/architecture/production_feature_contract_test.dart test/scenarios/production_feature_navigation_test.dart --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-device-model.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-camera-speech.ps1
git diff --check
~~~

Expected: host and debug-APK gates pass. Ledger states remain `verified`, not `field-certified`.

- [ ] **Step 5: Commit**

Run:

~~~powershell
git add lib test docs/field/2026-08-09-runtime-feature-ledger.md
git commit -m "feat(p3): enforce production feature delivery"
~~~

### Task 7: P4 single-composition AI and voice

**Files:**
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/features/ai_tutor/`, `lib/features/gemini/`, `lib/features/voice/`
- Modify: AI/voice/media screens that construct providers directly
- Create: `test/architecture/provider_composition_boundary_test.dart`
- Create: `test/scenarios/ai_voice_fallback_journey_test.dart`
- Modify: `test/runtime/app_bootstrap_test.dart`

**Interfaces:**
- Consumes: one `AiTutorController`/`GeminiTutorController` and one `VoiceUseCases` from `AppDependencies`.
- Produces: provider-neutral screen boundaries, owner-scoped usage accounting, explicit offline/native fallback, and bounded failures.

**MaxPlus decision gate (required after Step 2, before Step 3):**
- Question: `Review the AI and voice composition root. What concrete lifecycle, ownership, fallback, or secret-boundary defects could create duplicate provider clients, unbounded retries, cross-owner usage, or screen-level provider construction?`
- Path: `lib/runtime/app_bootstrap.dart`
- Effort: `XHigh`
- Reviewer: `claude-opus-5` required; omit `-NoReviewer`.
- Acceptance criteria: bootstrap creates and disposes one provider-neutral facade per capability; screens receive only composed interfaces; provider keys never cross into UI construction; usage is scoped to the active local owner; timeout, disabled, and circuit-open failures are typed and bounded; local learning and native TTS remain available without cloud providers.

- [ ] **Step 1: Write composition-boundary tests**

Scan production screen sources and fail when they call `VoiceUseCases.createDefault()`, instantiate HTTP clients, read provider keys, or construct AI gateways. Widget tests must receive providers only through `AppDependenciesScope` or explicit test parameters.

- [ ] **Step 2: Write fallback and usage tests**

Prove local learning remains usable when AI/voice initialization throws; one request increments only the active owner's usage ledger; timeout/circuit-open/provider-disabled states are typed and do not retry without a bound.

- [ ] **Step 3: Centralize composition**

`AppBootstrap` owns provider clients and disposal. Screens invoke composed controller/use-case interfaces. Native TTS is the offline voice fallback; cloud voice and mirror behavior require consent and explicit availability.

- [ ] **Step 4: Run Checkpoint B**

Run sequentially:

~~~powershell
flutter test test/architecture/provider_composition_boundary_test.dart test/scenarios/ai_voice_fallback_journey_test.dart test/runtime/app_bootstrap_test.dart --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-gemini-byok.ps1
uv run --project backend/ai_api pytest backend/ai_api/tests -q
uv run --project backend/voice_api pytest backend/voice_api/tests -q
uv run --project backend/lexiquest_lm pytest backend/lexiquest_lm/tests -q
git diff --check
~~~

Expected: CPU-only tests pass; no real provider success is claimed from fakes.

- [ ] **Step 5: Commit**

Run:

~~~powershell
git add lib test backend docs/field/2026-08-09-runtime-feature-ledger.md
git commit -m "refactor(p4): centralize AI and voice composition"
~~~

### Task 8: P5/P8 security, reliability, observability, and cost control

**Files:**
- Modify: `lib/runtime/runtime_feature_override_store.dart` and `lib/runtime/registries/feature_registry.dart`
- Modify: circuit-breaker, usage, download-counter, export, and deletion files proven by tests
- Modify: `tool/cli/verify-product-completion.ps1` when new mandatory tests must enter the gate
- Create: `test/scenarios/runtime_kill_switch_journey_test.dart`
- Create: `test/scenarios/complete_owner_export_delete_test.dart`
- Create: `docs/field/2026-08-09-p8-hardening-evidence.md`

**Interfaces:**
- Consumes: `RuntimeFeatureControls`, `LocalDataDeletion`, `ExportUseCases`, owner-scoped AI usage, model download counter, bounded retry/circuit-breaker state.
- Produces: durable kill switches, complete export/deletion inventory, redacted diagnostics, and measurable cost/download limits.

**MaxPlus decision gate (required before Step 2 defines the owner lifecycle inventory):**
- Question: `Review schema 12 as the owner-lifecycle authority. Which owner-scoped tables, secrets, foreign-key ordering constraints, migration obligations, export allowlist rules, and deletion invariants must the lifecycle test cover?`
- Path: `lib/data/local/app_database.dart`
- Effort: `XHigh`
- Reviewer: `claude-opus-5` required; omit `-NoReviewer`.
- Acceptance criteria: the inventory names every schema-12 owner-scoped table; deletion order preserves foreign-key integrity; export is allowlisted and redacts credentials, auth tokens, participant identifiers, and provider secrets; no owner row or secret survives deletion; another owner's data is unchanged; any future schema change updates migration, export, and deletion coverage together. Codex proves accepted findings through `complete_owner_export_delete_test.dart`; specialist advice never substitutes for Gitleaks, OSV, policy tests, or focused diff review.

- [ ] **Step 1: Write kill-switch and invocation tests**

Enable a feature, open it, persist a disabled override, rebuild/restart, and assert the UI entry disappears and stale/direct invocation is rejected. Expired overrides restore the build default.

- [ ] **Step 2: Write full owner lifecycle tests**

Populate every owner-scoped table in schema 12, export allowed fields, delete the owner, and assert no owner row or owner secret remains. Assert exported diagnostics exclude credentials, auth tokens, raw participant identifiers, and provider secrets.

- [ ] **Step 3: Write reliability and cost tests**

Assert retry maxima, timeout budgets, circuit-open behavior, AI usage owner scoping, model download counts, and local fallback. The measured baseline must fit the 0–100 THB/month central-cost policy.

- [ ] **Step 4: Run hardening gates**

Run sequentially:

~~~powershell
flutter test test/runtime/runtime_feature_controls_test.dart test/scenarios/runtime_kill_switch_journey_test.dart test/scenarios/complete_owner_export_delete_test.dart --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-product-completion.ps1
gitleaks git . --redact --no-banner
osv-scanner scan source --recursive .
flutter pub outdated
git diff --check
~~~

Expected: no committed secret, no unresolved applicable dependency vulnerability, no missing owner table, and no unbounded production retry. `flutter pub outdated` is an inventory report; a newer version alone is not a failure.

- [ ] **Step 5: Record and commit Checkpoint C**

`docs/field/2026-08-09-p8-hardening-evidence.md` records command, UTC time, source SHA, exit code, and any accepted non-applicable advisory with evidence.

Run:

~~~powershell
git add lib test tool/cli docs/field
git commit -m "feat(p8): complete bounded production hardening"
~~~

### Task 9: Production integration-test harness

**Files:**
- Modify: `pubspec.yaml`
- Create: `integration_test/field_trial_core_journey_test.dart`
- Create: `integration_test/field_trial_feature_controls_test.dart`
- Create: `integration_test/field_trial_media_smoke_test.dart`
- Modify: `tool/cli/verify-product-completion.ps1`

**Interfaces:**
- Adds: Flutter SDK `integration_test` under `dev_dependencies`.
- Consumes: injectable `AppBootstrap` with a file-backed `AppDatabase` and fake external gateways.
- Produces: real widget/application journeys launched through `main.dart` composition boundaries; physical plugin assertions remain separate.

- [ ] **Step 1: Add the SDK test dependency**

Use:

~~~yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
~~~

Run `flutter pub get` and include `pubspec.lock`.

- [ ] **Step 2: Write the core journey**

Launch signed out, select Guest, create category/word, complete Quiz/SRS/associative reading, inspect progress/rewards/quest/streak, restart with the same SQLite file, export, and sign out. Each action starts from the rendered production shell.

- [ ] **Step 3: Write controls and media journeys**

Persist a feature override and verify it survives restart. Exercise camera/speech/model permission and unavailability UI with fake plugin boundaries; do not label these host fakes as physical-device results.

- [ ] **Step 4: Run the harness**

Run:

~~~powershell
flutter test integration_test/field_trial_core_journey_test.dart integration_test/field_trial_feature_controls_test.dart integration_test/field_trial_media_smoke_test.dart --reporter compact
flutter analyze
git diff --check
~~~

Expected: all journeys pass from the production shell and real persisted database.

- [ ] **Step 5: Add the tests to the product gate and commit**

Run the integration tests as a named phase in `verify-product-completion.ps1`, then:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-product-completion.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-product-completion.ps1
git add pubspec.yaml pubspec.lock integration_test tool/cli
git commit -m "test: add production field-trial journeys"
~~~

### Task 10: P6 frozen internal APK checkpoint

**Files:**
- Inspect/modify if tests require: `android/`, `pubspec.yaml`, `tool/cli/package-field-release.ps1`
- Generate ignored artifacts: `build/field-release/`
- Create genuine metadata only: `docs/field/2026-08-09-internal-apk-checkpoint.md`

**Interfaces:**
- Consumes: clean committed source, owner-controlled `android/key.properties`, pinned model checksum.
- Produces: signed APK, `release-manifest.json`, source SHA, APK SHA-256, signing-certificate SHA-256, version/build ID, and model SHA-256.

**MaxPlus decision gate (required after Step 2, before Step 3):**
- Question: `Review the release packaging script as a fail-closed release blocker. Can any path package an unsigned, stale, mismatched, or unverifiable APK, expose signing material, or emit metadata that is not bound to the frozen source?`
- Path: `tool/cli/package-field-release.ps1`
- Effort: `Max`
- Reviewer: `claude-opus-5` required; omit `-NoReviewer`.
- Acceptance criteria: missing signing prerequisites stop before packaging; no secret value or keystore content is printed or sent; source SHA, APK SHA-256, certificate SHA-256, version/build ID, and model SHA-256 come from the exact produced artifact; stale output cannot be mistaken for the current package; any byte-changing rebuild invalidates prior metadata. Specialist advice is not signing, APK, or verifier evidence.

- [ ] **Step 1: Freeze and verify source**

Run:

~~~powershell
git status --short
git rev-parse HEAD
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-product-completion.ps1
~~~

Expected: clean worktree and passing product gate.

- [ ] **Step 2: Confirm signing prerequisites without printing secrets**

Run:

~~~powershell
Test-Path -LiteralPath android/key.properties
Get-Command apksigner
~~~

Expected: both exist. If `android/key.properties` is absent, P6 is externally blocked and no unsigned APK is substituted.

- [ ] **Step 3: Package the exact release**

Run:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/package-field-release.ps1 -Version 1.0.0+13
Get-FileHash build/field-release/*.apk -Algorithm SHA256
~~~

Expected: manifest and calculated hash agree.

- [ ] **Step 4: Verify and record checkpoint**

Run the APK runtime verifier named by the package script, record tool versions and hashes, then commit only non-sensitive metadata. Any source change after this point invalidates the checkpoint and requires a new package.

### Task 11: P7/P8 physical-device and beta evidence

**Files:**
- Create from repository generator: `field/evidence/release-evidence.json`
- Create: `docs/field/2026-08-09-device-beta-matrix.md`

**Interfaces:**
- Consumes: the exact APK and `release-manifest.json` from Task 10.
- Produces: hashed-device evidence for low-, mid-, and high-tier Android devices; App Check valid/enforced traffic; real camera, microphone, model, offline/reconnect, AI, voice, export/deletion, consent, and beta observations.

- [ ] **Step 1: Generate the evidence shell**

Run:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/new-field-release-evidence.ps1
~~~

Expected: required fields are explicit and unresolved external checks remain `pending`.

- [ ] **Step 2: Execute the device matrix**

On each device, install the exact APK, confirm its hash/build ID, then execute cold offline start, guest restart, vocabulary/Quiz/SRS/reading restart, reconnect/sync, model download/checksum/inference, camera, microphone, native voice fallback, provider-enabled AI/voice where authorized, export, deletion, and crash recovery.

- [ ] **Step 3: Execute beta operations**

Record tester count, consent version, issue severity, crash-free sessions, sync failures, provider cost/download counters, rollback drill, kill-switch drill, and owner decisions. Participant identifiers remain hashed or excluded.

- [ ] **Step 4: Run the field verifier**

Run:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-field-release.ps1 -EvidencePath field/evidence/release-evidence.json -ParticipantPackagePath build/field-release
~~~

Expected: pass only when evidence and release manifest refer to identical artifact fields.

### Task 12: P9 release readiness and P10 final acceptance

**Files:**
- Update: `docs/field/2026-08-09-current-release-readiness.md`
- Create: `docs/field/2026-08-09-final-acceptance.md`
- Update only if version changes: `pubspec.yaml` and exact release metadata/evidence.

**Interfaces:**
- Consumes: Checkpoints A–D, exact source/APK/device/provider evidence, owner approval.
- Produces: one truthful final decision: `READY` or `NOT READY`, with every failed or external gate named.

**MaxPlus decision gate (required before Step 2 on the frozen candidate):**
- Question: `Review the field-release verifier's final acceptance logic. Can any local fake, missing external record, mismatched source/artifact identity, unknown status, or stale evidence incorrectly produce an accepted release?`
- Path: `tool/cli/verify-field-release.ps1`
- Effort: `Max`
- Reviewer: `claude-opus-5` required; omit `-NoReviewer`.
- Acceptance criteria: acceptance binds one source SHA, APK SHA-256, certificate digest, version/build ID, and evidence set; physical/provider gates cannot be satisfied by host fakes; missing mandatory evidence fails or remains explicitly `blocked-external`; only declared statuses are accepted; stale or mismatched evidence fails closed. Codex independently runs the exact final gates and remains the final `READY|NOT READY` authority.

- [ ] **Step 1: Reconcile every feature ledger row**

No `orphan` capability may remain visible. Every visible feature is at least `verified`; every device/provider-dependent release feature is `field-certified` or explicitly hidden.

- [ ] **Step 2: Run final gates once on the frozen SHA**

Run sequentially:

~~~powershell
git status --short
flutter analyze
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-product-completion.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-field-release.ps1 -EvidencePath field/evidence/release-evidence.json -ParticipantPackagePath build/field-release
gitleaks git . --redact --no-banner
osv-scanner scan source --recursive .
git diff --check
~~~

Expected: all mandatory local and external gates pass against the same source and artifact identities.

- [ ] **Step 3: Publish the acceptance matrix**

The final record separates:

~~~markdown
| Gate | Status | Source SHA | Artifact SHA-256 | Command/evidence | Owner |
~~~

Only `pass`, `fail`, `blocked-external`, and `not-applicable` are allowed. A local fake or host test cannot satisfy a physical/provider gate.

- [ ] **Step 4: Commit final metadata and finish the branch**

Run:

~~~powershell
git add docs/field pubspec.yaml pubspec.lock
git commit -m "release: record field-trial acceptance"
git status --short
~~~

Use `verification-before-completion` before a completion claim and `finishing-a-development-branch` only after the final status is genuinely `READY`.

## Rollback and blocker reporting

For every slice, record pre-slice SHA, slice commit, changed files, focused gate, and ledger rows. Revert a rejected slice with a new revert commit. Never discard a user's branch or worktree.

A blocker report contains:

~~~markdown
Observed:
Expected:
Exact command:
Exit code:
Evidence path:
Attempts and distinct hypotheses:
Smallest required external action:
Unaffected work that can continue:
~~~

Missing signing credentials, devices, provider access, App Check console state, participant consent, or owner approval are external blockers. They do not justify fabricated evidence and do not prevent unrelated local slices from advancing.
