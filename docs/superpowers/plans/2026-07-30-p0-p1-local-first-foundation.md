# P0-P1 Local-First Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a reproducible field-build baseline, hide fabricated participant paths, and deliver durable offline vocabulary CRUD/import on a versioned Drift data spine.

**Architecture:** Drift is the only runtime source of truth. Feature-first domain and application ports isolate Flutter screens from persistence. A local transaction writes each entity change and its future sync operation together, while Firebase synchronization remains disabled until P2 supplies the gateway and rules.

**Tech Stack:** Flutter 3.44.7, Dart 3.12.2, Drift/SQLite, drift_dev, build_runner, existing Flutter test stack.

## Execution Status

This table is the authoritative execution record. The unchecked boxes in the
runbook below preserve the original command sequence and are not a second
backlog.

| Package | Status | Evidence |
|---|---|---|
| P0 baseline and field controls | Complete | Baseline recorded; unverified participant features hidden |
| P1-A Drift schema | Complete | Schema version 1 and constraint tests pass |
| P1-B identity and vocabulary repository | Complete | Stable owner, CRUD, tombstone, ownership, revision, and atomic outbox tests pass |
| P1-C use cases and import | Complete | Validation, limits, cancellation, duplicate, and replay tests pass |
| P1-D composition and screens | Complete | Drift opens before cloud; vocabulary journey survives widget reconstruction |
| P1 automated integration gate | Complete | 6/6 phases passed on 2026-07-30 |
| Android force-stop/restart check | Pending hardware | No Android device was connected to this CLI session |

Gate evidence is recorded in
`docs/development/p1-local-first-gate-2026-07-30.md`.

## Global Constraints

- Apply RED-GREEN-REFACTOR to every behavior change.
- Run only focused tests during a task, affected-slice tests at a task boundary, and the bounded integration gate after the slice.
- Never repeat a failed command without changing code, configuration, or environment.
- Preserve the owner's generated-file changes and untracked `AGENTS.md`.
- Widgets must not import Firebase, Drift, HTTP, or platform plugins.
- All identifiers are client-generated stable strings; all persisted timestamps are UTC.
- A local mutation and its outbox operation commit in one Drift transaction.
- No participant-visible random, sample, canned-success, or fabricated result.
- Do not invoke Codex Security, Security Scan, Deep Scan, or a Codex Security worker.

---

## File Structure

### Runtime controls

- `lib/runtime/field_feature.dart`: stable field-build feature identifiers.
- `lib/runtime/field_feature_registry.dart`: immutable enabled/limited/hidden policy.
- `test/runtime/field_feature_registry_test.dart`: policy and build-default tests.

### Local database

- `lib/data/local/tables/identity_tables.dart`: local owner and consent tables.
- `lib/data/local/tables/vocabulary_tables.dart`: category, word, import, and import-row tables.
- `lib/data/local/tables/learning_tables.dart`: session, answer, SRS, and reading tables.
- `lib/data/local/tables/progress_tables.dart`: points and achievement tables.
- `lib/data/local/tables/sync_tables.dart`: outbox, checkpoint, and conflict tables.
- `lib/data/local/tables/model_tables.dart`: resumable model-download state.
- `lib/data/local/app_database.dart`: Drift database, schema version, migrations, and transaction helpers.
- `lib/data/local/app_database.g.dart`: generated Drift implementation.
- `test/data/local/app_database_test.dart`: schema, constraints, cascade, and migration tests.

### Identity

- `lib/features/identity/domain/local_owner.dart`: provider-neutral local owner.
- `lib/features/identity/domain/local_owner_repository.dart`: owner port.
- `lib/features/identity/data/drift_local_owner_repository.dart`: Drift adapter.
- `test/features/identity/drift_local_owner_repository_test.dart`: owner persistence and replay tests.

### Vocabulary

- `lib/features/vocabulary/domain/vocabulary_category.dart`: category entity.
- `lib/features/vocabulary/domain/vocabulary_word.dart`: word entity.
- `lib/features/vocabulary/domain/vocabulary_failure.dart`: typed validation and storage failures.
- `lib/features/vocabulary/domain/vocabulary_repository.dart`: category/word query and mutation port.
- `lib/features/vocabulary/data/drift_vocabulary_repository.dart`: Drift transaction adapter.
- `lib/features/vocabulary/application/vocabulary_use_cases.dart`: validation and command orchestration.
- `test/features/vocabulary/drift_vocabulary_repository_test.dart`: durable CRUD, limits, tombstones, and outbox tests.
- `test/features/vocabulary/vocabulary_use_cases_test.dart`: validation and duplicate behavior.

### Import

- `lib/features/vocabulary/domain/vocabulary_import.dart`: import batch and row results.
- `lib/features/vocabulary/application/import_vocabulary.dart`: CSV/row normalization and atomic import use case.
- `test/features/vocabulary/import_vocabulary_test.dart`: accepted/rejected/duplicate/retry behavior.

### Composition and screens

- `lib/runtime/app_dependencies.dart`: exposes the database and vocabulary use cases.
- `lib/runtime/app_bootstrap.dart`: opens Drift before optional cloud providers.
- `lib/main.dart`: closes the database with application lifecycle ownership.
- `lib/screens/categories_page.dart`: reads category streams and dispatches use cases.
- `lib/screens/vocab_list_screen.dart`: reads word streams and dispatches use cases.
- `lib/screens/add_vocab_screen.dart`: creates words through a use case.
- `lib/screens/add_multiple_words_screen.dart`: imports through a use case.
- `lib/screens/main_navigation_screen.dart`: hides unverified field features.
- `test/screens/offline_vocabulary_journey_test.dart`: end-to-end widget journey over in-memory Drift.
- `test/runtime/app_bootstrap_test.dart`: local database startup when cloud is unavailable.

### Development evidence

- `docs/development/field-build-baseline-2026-07-30.md`: reproducible baseline results and classified failures.
- `tool/cli/verify-local-first.ps1`: bounded P0-P1 integration gate.

---

### Task 1: Record the bounded baseline

**Files:**

- Create: `docs/development/field-build-baseline-2026-07-30.md`

**Interfaces:**

- Consumes: current Git SHA, Flutter/Dart versions, analyzer, focused tests, and Android debug build.
- Produces: an evidence record that distinguishes package failures from pre-existing failures.

- [ ] **Step 1: Capture toolchain and repository identity**

Run:

```powershell
git rev-parse --short HEAD
flutter --version
dart --version
git status --short
```

Expected: commands return normally; dirty generated files and `AGENTS.md` are recorded as owner state.

- [ ] **Step 2: Run baseline checks once**

Run:

```powershell
flutter analyze
flutter test test/runtime test/progress test/learning test/screens/main_navigation_screen_test.dart --reporter compact
flutter build apk --debug `
  --dart-define=LEXIQUEST_VERSION=1.0.0+1 `
  --dart-define=LEXIQUEST_BUILD_ID=p0-baseline `
  --dart-define=LEXIQUEST_VOICE_API_URL=http://10.0.2.2:8001 `
  --dart-define=LEXIQUEST_AI_API_URL=http://10.0.2.2:8000
```

Expected: each command is run once. Every failure is copied into the baseline and classified; no unrelated production fix is made in this task.

- [ ] **Step 3: Write the baseline record**

Use this exact structure:

```markdown
# Field Build Baseline — 2026-07-30

- Commit: `<captured SHA>`
- Flutter: `<captured version>`
- Dart: `<captured version>`
- Working tree exclusions: generated Linux/macOS/Windows plugin files and AGENTS.md

| Check | Result | Classification | Planned gate |
|---|---|---|---|
| Flutter analyze | PASS or exact count | baseline | P0-P1 |
| Focused foundation tests | PASS or exact failures | baseline | owning gate |
| Android debug APK | PASS or exact failure | environment/baseline | P0-P1 |
```

- [ ] **Step 4: Review without committing unrelated changes**

Run:

```powershell
git diff -- docs/development/field-build-baseline-2026-07-30.md
git status --short
```

Expected: only the baseline document is new for this task.

---

### Task 2: Add field-build feature controls

**Files:**

- Create: `lib/runtime/field_feature.dart`
- Create: `lib/runtime/field_feature_registry.dart`
- Create: `test/runtime/field_feature_registry_test.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/screens/main_navigation_screen.dart`

**Interfaces:**

- Produces:

```dart
enum FieldFeature {
  vocabulary,
  quiz,
  srs,
  reading,
  mastery,
  weakness,
  achievements,
  shop,
  objectScanner,
  speechPractice,
  aiTutor,
  export,
}

enum FieldFeatureState { enabled, limited, hidden }

abstract interface class FieldFeatureRegistry {
  FieldFeatureState stateOf(FieldFeature feature);
  bool isVisible(FieldFeature feature);
}
```

- [ ] **Step 1: Write the failing policy tests**

```dart
test('field defaults expose only evidence-backed foundation features', () {
  const registry = BuildFieldFeatureRegistry.fieldDefaults();

  expect(registry.stateOf(FieldFeature.vocabulary), FieldFeatureState.enabled);
  expect(registry.stateOf(FieldFeature.quiz), FieldFeatureState.hidden);
  expect(registry.stateOf(FieldFeature.reading), FieldFeatureState.hidden);
  expect(registry.stateOf(FieldFeature.srs), FieldFeatureState.hidden);
  expect(registry.stateOf(FieldFeature.shop), FieldFeatureState.hidden);
  expect(registry.stateOf(FieldFeature.objectScanner), FieldFeatureState.hidden);
  expect(registry.stateOf(FieldFeature.aiTutor), FieldFeatureState.hidden);
});

test('isVisible excludes hidden features', () {
  const registry = BuildFieldFeatureRegistry({
    FieldFeature.shop: FieldFeatureState.hidden,
    FieldFeature.vocabulary: FieldFeatureState.enabled,
  });

  expect(registry.isVisible(FieldFeature.shop), isFalse);
  expect(registry.isVisible(FieldFeature.vocabulary), isTrue);
});
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test test/runtime/field_feature_registry_test.dart
```

Expected: compilation fails because the registry files do not exist.

- [ ] **Step 3: Implement the immutable registry**

```dart
final class BuildFieldFeatureRegistry implements FieldFeatureRegistry {
  const BuildFieldFeatureRegistry(this._states);

  const BuildFieldFeatureRegistry.fieldDefaults()
      : _states = const {
          FieldFeature.vocabulary: FieldFeatureState.enabled,
        };

  final Map<FieldFeature, FieldFeatureState> _states;

  @override
  FieldFeatureState stateOf(FieldFeature feature) =>
      _states[feature] ?? FieldFeatureState.hidden;

  @override
  bool isVisible(FieldFeature feature) =>
      stateOf(feature) != FieldFeatureState.hidden;
}
```

Add `fieldFeatures` to `AppDependencies`. Filter drawer entries and field-build destinations through the registry. Existing test composition may inject a registry that enables legacy destinations until their tests are migrated.

- [ ] **Step 4: Verify GREEN and navigation regression**

Run:

```powershell
dart format lib/runtime/field_feature.dart lib/runtime/field_feature_registry.dart lib/runtime/app_dependencies.dart lib/screens/main_navigation_screen.dart test/runtime/field_feature_registry_test.dart
flutter test test/runtime/field_feature_registry_test.dart test/screens/main_navigation_screen_test.dart
```

Expected: both test files pass.

- [ ] **Step 5: Commit the bounded package**

```powershell
git add lib/runtime/field_feature.dart lib/runtime/field_feature_registry.dart lib/runtime/app_dependencies.dart lib/screens/main_navigation_screen.dart test/runtime/field_feature_registry_test.dart docs/development/field-build-baseline-2026-07-30.md
git commit -m "feat(runtime): add field-build feature controls"
```

---

### Task 3: Install Drift and define the version-one schema

**Files:**

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/data/local/tables/identity_tables.dart`
- Create: `lib/data/local/tables/vocabulary_tables.dart`
- Create: `lib/data/local/tables/learning_tables.dart`
- Create: `lib/data/local/tables/progress_tables.dart`
- Create: `lib/data/local/tables/sync_tables.dart`
- Create: `lib/data/local/tables/model_tables.dart`
- Create: `lib/data/local/app_database.dart`
- Create: `lib/data/local/app_database.g.dart`
- Create: `test/data/local/app_database_test.dart`

**Interfaces:**

- Produces:

```dart
@DriftDatabase(tables: [
  LocalOwners,
  ResearchConsents,
  VocabularyCategories,
  VocabularyWords,
  VocabularyImports,
  VocabularyImportRows,
  LearningSessions,
  AnswerAttempts,
  SrsStates,
  ReadingProgressEntries,
  ReadingEvents,
  PointsLedgerEntries,
  AchievementUnlocks,
  OutboxOperations,
  SyncCheckpoints,
  SyncConflicts,
  ModelDownloads,
])
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);
  AppDatabase.production() : super(driftDatabase(name: 'lexiquest'));

  @override
  int get schemaVersion => 1;
}
```

- [ ] **Step 1: Add dependency declarations**

Run:

```powershell
flutter pub add drift drift_flutter uuid
flutter pub add --dev drift_dev build_runner
```

Expected: dependency resolution succeeds against Dart 3.12 and updates only `pubspec.yaml` and `pubspec.lock`.

- [ ] **Step 2: Write failing database tests**

Tests must construct `AppDatabase(NativeDatabase.memory())` and prove:

```dart
test('schema version one creates every field table', () async {
  final tables = await database
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .map((row) => row.read<String>('name'))
      .get();

  expect(tables, containsAll(<String>[
    'local_owners',
    'vocabulary_categories',
    'vocabulary_words',
    'vocabulary_imports',
    'vocabulary_import_rows',
    'learning_sessions',
    'answer_attempts',
    'srs_states',
    'reading_progress_entries',
    'reading_events',
    'points_ledger_entries',
    'achievement_unlocks',
    'outbox_operations',
    'sync_checkpoints',
    'sync_conflicts',
    'model_downloads',
  ]));
});
```

Also test UTC integer timestamps, owner/category foreign keys, normalized-word uniqueness, outbox operation-ID uniqueness, points idempotency-key uniqueness, and tombstone columns.

- [ ] **Step 3: Verify RED**

Run:

```powershell
flutter test test/data/local/app_database_test.dart
```

Expected: compilation fails because `AppDatabase` does not exist.

- [ ] **Step 4: Implement focused table groups**

Use Drift `text()`, `integer()`, and `boolean()` columns. Persist timestamps as
UTC epoch milliseconds. Each synchronized mutable row includes:

```dart
TextColumn get ownerId => text()();
IntColumn get localRevision => integer().withDefault(const Constant(1))();
BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
IntColumn get createdAtUtcMs => integer()();
IntColumn get updatedAtUtcMs => integer()();
```

Define composite unique keys:

```dart
@override
List<Set<Column<Object>>> get uniqueKeys => [
  {ownerId, normalizedName},
];
```

Words use `{ownerId, categoryId, normalizedSpelling, normalizedMeaning}`. Import rows use `{importId, payloadHash}`.

- [ ] **Step 5: Generate and verify GREEN**

Run:

```powershell
dart run build_runner build --delete-conflicting-outputs
dart format lib/data/local test/data/local/app_database_test.dart
flutter test test/data/local/app_database_test.dart
```

Expected: database tests pass with no warning or exception.

- [ ] **Step 6: Commit the schema**

```powershell
git add pubspec.yaml pubspec.lock lib/data/local test/data/local/app_database_test.dart
git commit -m "feat(data): add versioned Drift field schema"
```

---

### Task 4: Persist a stable local guest owner

**Files:**

- Create: `lib/features/identity/domain/local_owner.dart`
- Create: `lib/features/identity/domain/local_owner_repository.dart`
- Create: `lib/features/identity/data/drift_local_owner_repository.dart`
- Create: `test/features/identity/drift_local_owner_repository_test.dart`

**Interfaces:**

```dart
final class LocalOwner {
  const LocalOwner({
    required this.id,
    required this.createdAtUtc,
    this.firebaseUid,
    this.upgradedAtUtc,
  });

  final String id;
  final String? firebaseUid;
  final DateTime createdAtUtc;
  final DateTime? upgradedAtUtc;
}

abstract interface class LocalOwnerRepository {
  Future<LocalOwner> getOrCreateActiveOwner();
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid);
}
```

- [ ] **Step 1: Write failing repository tests**

Cover first creation, restart returning the same owner, concurrent calls returning one owner, whitespace Firebase UID rejection, and idempotent UID binding.

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test test/features/identity/drift_local_owner_repository_test.dart
```

Expected: compilation fails because the repository does not exist.

- [ ] **Step 3: Implement with a database transaction**

`getOrCreateActiveOwner` selects the one active owner; if absent, inserts
`local:<UUID v4>`. It uses the injected UUID source and UTC clock so tests are deterministic. Binding the same Firebase UID is a no-op; binding a different UID records the new value without changing the local owner ID.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
dart format lib/features/identity test/features/identity/drift_local_owner_repository_test.dart
flutter test test/features/identity/drift_local_owner_repository_test.dart
```

Expected: all identity repository tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/identity test/features/identity/drift_local_owner_repository_test.dart
git commit -m "feat(identity): persist stable local guest ownership"
```

---

### Task 5: Implement Drift vocabulary repository with atomic outbox

**Files:**

- Create: `lib/features/vocabulary/domain/vocabulary_category.dart`
- Create: `lib/features/vocabulary/domain/vocabulary_word.dart`
- Create: `lib/features/vocabulary/domain/vocabulary_failure.dart`
- Create: `lib/features/vocabulary/domain/vocabulary_repository.dart`
- Create: `lib/features/vocabulary/data/drift_vocabulary_repository.dart`
- Create: `test/features/vocabulary/drift_vocabulary_repository_test.dart`

**Interfaces:**

```dart
abstract interface class VocabularyRepository {
  Stream<List<VocabularyCategory>> watchCategories(String ownerId);
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId);
  Future<VocabularyCategory> createCategory({
    required String ownerId,
    required String id,
    required String name,
    required DateTime nowUtc,
  });
  Future<VocabularyCategory> renameCategory({
    required String ownerId,
    required String categoryId,
    required String name,
    required DateTime nowUtc,
  });
  Future<void> deleteCategory({
    required String ownerId,
    required String categoryId,
    required DateTime nowUtc,
  });
  Future<VocabularyWord> createWord(VocabularyWord word);
  Future<VocabularyWord> updateWord(VocabularyWord word);
  Future<void> deleteWord({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
  });
}
```

- [ ] **Step 1: Write failing repository tests**

Prove:

- category/word streams emit local changes;
- restart reads persisted rows;
- normalized duplicates are rejected;
- 50 active words per category is enforced transactionally;
- edits increment local revision;
- deletes create tombstones and remove rows from active queries;
- each mutation appends one pending outbox operation;
- repeating a mutation with the same operation ID is idempotent;
- another owner cannot read or mutate the row.

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test test/features/vocabulary/drift_vocabulary_repository_test.dart
```

Expected: compilation fails because the vocabulary repository does not exist.

- [ ] **Step 3: Implement normalization and typed failures**

```dart
String normalizeVocabularyText(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

sealed class VocabularyFailure implements Exception {
  const VocabularyFailure();
}

final class DuplicateVocabularyFailure extends VocabularyFailure {
  const DuplicateVocabularyFailure();
}

final class CategoryWordLimitFailure extends VocabularyFailure {
  const CategoryWordLimitFailure(this.limit);
  final int limit;
}
```

Map Drift uniqueness violations to `DuplicateVocabularyFailure`; do not expose SQL text to the UI.

- [ ] **Step 4: Implement atomic mutations**

Each mutation runs:

```dart
return database.transaction(() async {
  final entity = await _writeEntity(...);
  await database.into(database.outboxOperations).insert(
    OutboxOperationsCompanion.insert(
      operationId: operationId,
      ownerId: ownerId,
      entityType: const Value('word'),
      entityId: entity.id,
      operationKind: const Value('upsert'),
      payloadVersion: const Value(1),
      baseRevision: Value(entity.localRevision - 1),
      createdAtUtcMs: nowUtc.millisecondsSinceEpoch,
    ),
    mode: InsertMode.insertOrIgnore,
  );
  return entity;
});
```

The outbox payload is reconstructed from the authoritative entity during P2; P1 stores identifiers and revisions only.

- [ ] **Step 5: Verify GREEN**

Run:

```powershell
dart format lib/features/vocabulary test/features/vocabulary/drift_vocabulary_repository_test.dart
flutter test test/features/vocabulary/drift_vocabulary_repository_test.dart
```

Expected: all repository behaviors pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/features/vocabulary test/features/vocabulary/drift_vocabulary_repository_test.dart
git commit -m "feat(vocabulary): persist CRUD with atomic outbox"
```

---

### Task 6: Add validated vocabulary use cases

**Files:**

- Create: `lib/features/vocabulary/application/vocabulary_use_cases.dart`
- Create: `test/features/vocabulary/vocabulary_use_cases_test.dart`

**Interfaces:**

```dart
final class VocabularyUseCases {
  VocabularyUseCases({
    required LocalOwnerRepository owners,
    required VocabularyRepository vocabulary,
    required IdGenerator ids,
    required UtcClock clock,
  });

  Stream<List<VocabularyCategory>> watchCategories();
  Stream<List<VocabularyWord>> watchWords(String categoryId);
  Future<VocabularyCategory> createCategory(String name);
  Future<VocabularyCategory> renameCategory(String categoryId, String name);
  Future<void> deleteCategory(String categoryId);
  Future<VocabularyWord> createWord(CreateWordCommand command);
  Future<VocabularyWord> updateWord(UpdateWordCommand command);
  Future<void> deleteWord(String wordId);
}
```

- [ ] **Step 1: Write failing command tests**

Cover blank IDs/text, maximum lengths, UTC normalization, owner propagation, stable ID generation, repository failure mapping, and no outbox call from the application layer.

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test test/features/vocabulary/vocabulary_use_cases_test.dart
```

Expected: compilation fails because `VocabularyUseCases` does not exist.

- [ ] **Step 3: Implement validation**

Use these limits:

```dart
const maxCategoryNameLength = 80;
const maxSpellingLength = 120;
const maxMeaningLength = 500;
const maxPartOfSpeechLength = 60;
```

Trim input, preserve user-facing case, and reject empty normalized values before calling the repository.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
dart format lib/features/vocabulary/application test/features/vocabulary/vocabulary_use_cases_test.dart
flutter test test/features/vocabulary/vocabulary_use_cases_test.dart
```

Expected: all use-case tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/vocabulary/application test/features/vocabulary/vocabulary_use_cases_test.dart
git commit -m "feat(vocabulary): add validated local use cases"
```

---

### Task 7: Implement replay-safe vocabulary import

**Files:**

- Create: `lib/features/vocabulary/domain/vocabulary_import.dart`
- Create: `lib/features/vocabulary/application/import_vocabulary.dart`
- Create: `test/features/vocabulary/import_vocabulary_test.dart`

**Interfaces:**

```dart
final class VocabularyImportResult {
  const VocabularyImportResult({
    required this.importId,
    required this.accepted,
    required this.duplicates,
    required this.rejected,
  });

  final String importId;
  final int accepted;
  final int duplicates;
  final List<VocabularyImportRowFailure> rejected;
}

final class ImportVocabulary {
  Future<VocabularyImportResult> call({
    required String categoryId,
    required List<Map<String, String>> rows,
    required String sourceName,
  });
}
```

- [ ] **Step 1: Write failing import tests**

Cover an empty import, mixed valid/invalid rows, duplicate rows in one batch, duplicates against existing words, 50-word capacity, cancellation before commit, and replay of the same source hash.

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test test/features/vocabulary/import_vocabulary_test.dart
```

Expected: compilation fails because the import use case does not exist.

- [ ] **Step 3: Implement deterministic row hashing**

```dart
String canonicalImportRow(Map<String, String> row) => [
  normalizeVocabularyText(row['word'] ?? ''),
  normalizeVocabularyText(row['meaning'] ?? ''),
  normalizeVocabularyText(row['partOfSpeech'] ?? ''),
].join('\u001f');
```

Hash the canonical row with a non-secret stable digest. Insert accepted words, import rows, import summary, and outbox operations in one database transaction. Replaying the same source/import hash returns the stored result.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
dart format lib/features/vocabulary test/features/vocabulary/import_vocabulary_test.dart
flutter test test/features/vocabulary/import_vocabulary_test.dart
```

Expected: all import tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/vocabulary test/features/vocabulary/import_vocabulary_test.dart
git commit -m "feat(vocabulary): add replay-safe local import"
```

---

### Task 8: Compose Drift before optional cloud providers

**Files:**

- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `lib/main.dart`
- Modify: `test/runtime/app_bootstrap_test.dart`

**Interfaces:**

- `AppDependencies` produces stable instances of `AppDatabase`, `LocalOwnerRepository`, and `VocabularyUseCases`.
- `AppBootstrap.initialize()` opens the database before Firebase/Supabase and returns usable local dependencies even when cloud initialization fails.

- [ ] **Step 1: Extend bootstrap tests**

```dart
test('local vocabulary remains ready when every cloud initializer fails', () async {
  final dependencies = await bootstrapWithFailingCloud.initialize();

  expect(dependencies.runtimeStatus.localData, RuntimeAvailability.ready);
  expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.unavailable);
  expect(dependencies.vocabulary, isNotNull);
});
```

Also assert the database is opened once and disposed once by the application lifecycle owner.

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test test/runtime/app_bootstrap_test.dart
```

Expected: assertions fail because local data dependencies are absent.

- [ ] **Step 3: Implement local-first composition**

Add an injected `AppDatabaseFactory` to `AppBootstrap`. Open and validate Drift first. Cloud initialization remains independently guarded. A local database failure is startup-blocking and renders a recovery screen; a cloud failure is degraded status only.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
dart format lib/runtime lib/main.dart test/runtime/app_bootstrap_test.dart
flutter test test/runtime/app_bootstrap_test.dart
```

Expected: bootstrap tests pass, including degraded cloud operation.

- [ ] **Step 5: Commit**

```powershell
git add lib/runtime lib/main.dart test/runtime/app_bootstrap_test.dart
git commit -m "feat(runtime): compose local data before cloud"
```

---

### Task 9: Migrate vocabulary screens off Firebase

**Files:**

- Modify: `lib/screens/categories_page.dart`
- Modify: `lib/screens/vocab_list_screen.dart`
- Modify: `lib/screens/add_vocab_screen.dart`
- Modify: `lib/screens/add_multiple_words_screen.dart`
- Create: `test/screens/offline_vocabulary_journey_test.dart`

**Interfaces:**

- Screens consume only `VocabularyUseCases`.
- Category/word streams produce loading, empty, data, and typed-failure states.
- Add/edit/delete/import actions complete after the local transaction, not cloud acknowledgement.

- [ ] **Step 1: Write the failing offline widget journey**

The test must:

```dart
testWidgets('guest vocabulary survives screen reconstruction without Firebase',
    (tester) async {
  await tester.pumpWidget(testApp(database));
  await createCategory(tester, 'Travel');
  await createWord(tester, word: 'station', meaning: 'สถานี');

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(testApp(database));
  await tester.pumpAndSettle();

  expect(find.text('Travel'), findsOneWidget);
  await tester.tap(find.text('Travel'));
  await tester.pumpAndSettle();
  expect(find.text('station'), findsOneWidget);
  expect(find.text('สถานี'), findsOneWidget);
});
```

The widget journey covers the participant-critical create and reconstruction
path. Delete, duplicate, category limit, cancellation, import summary, replay,
and storage constraints are covered at their owning repository/application
layer in this slice.

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test test/screens/offline_vocabulary_journey_test.dart
```

Expected: tests fail because screens instantiate Firebase-backed services.

- [ ] **Step 3: Replace screen-created services**

Resolve `VocabularyUseCases` from `AppDependenciesScope` or accept an injected
override. Remove Firebase imports and direct service construction. Keep visible
Thai copy valid UTF-8. Typed-route migration remains one bounded package in the
Navigation/UI phase and does not block the local persistence gate.

- [ ] **Step 4: Verify GREEN and affected screens**

Run:

```powershell
dart format lib/screens/categories_page.dart lib/screens/vocab_list_screen.dart lib/screens/add_vocab_screen.dart lib/screens/add_multiple_words_screen.dart test/screens/offline_vocabulary_journey_test.dart
flutter test test/screens/offline_vocabulary_journey_test.dart test/screens/wordbook_import_screen_test.dart
```

Expected: tests pass without Firebase initialization.

- [ ] **Step 5: Prove no infrastructure imports remain**

Run:

```powershell
rg -n "cloud_firestore|firebase_auth|FirebaseFirestore|FirebaseAuth|package:http|package:drift" `
  lib/screens/categories_page.dart `
  lib/screens/vocab_list_screen.dart `
  lib/screens/add_vocab_screen.dart `
  lib/screens/add_multiple_words_screen.dart
```

Expected: no matches.

- [ ] **Step 6: Commit**

```powershell
git add lib/screens/categories_page.dart lib/screens/vocab_list_screen.dart lib/screens/add_vocab_screen.dart lib/screens/add_multiple_words_screen.dart test/screens/offline_vocabulary_journey_test.dart
git commit -m "feat(vocabulary): move field screens to local data"
```

---

### Task 10: Add the bounded P0-P1 integration gate

**Files:**

- Create: `tool/cli/verify-local-first.ps1`
- Modify: `docs/superpowers/plans/2026-07-30-p0-p1-local-first-foundation.md`

**Interfaces:**

- Produces one fail-fast CLI command for the accepted slice.

- [ ] **Step 1: Implement the gate**

The script runs, in order:

```powershell
dart format --output=none --set-exit-if-changed lib/data/local lib/features/identity lib/features/vocabulary test/data/local test/features/identity test/features/vocabulary
flutter analyze lib/data/local lib/features/identity lib/features/vocabulary lib/runtime lib/screens/categories_page.dart lib/screens/vocab_list_screen.dart lib/screens/add_vocab_screen.dart lib/screens/add_multiple_words_screen.dart
flutter test test/data/local test/features/identity test/features/vocabulary test/runtime/field_feature_registry_test.dart test/runtime/app_bootstrap_test.dart test/screens/offline_vocabulary_journey_test.dart --reporter compact
flutter build apk --debug --dart-define=LEXIQUEST_VERSION=1.0.0+1 --dart-define=LEXIQUEST_BUILD_ID=p1-local-first
git diff --check
```

The script stops on the first failing phase and prints one summary. It does not run backend, model, camera, speech, Gemini, export, or release-signing suites.

- [ ] **Step 2: Run the gate once**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-local-first.ps1
```

Expected: every phase passes once. A failure is fixed in its owning package; the command is rerun only after a measurable change.

- [ ] **Step 3: Review requirements**

Confirm:

- Drift contains the full version-one data spine.
- Category/word/import production screens use local data.
- Data survives screen reconstruction and a real Android force-stop/restart.
- Every local mutation has one outbox row.
- Cloud unavailability does not block vocabulary.
- Unverified participant features are hidden.

- [ ] **Step 4: Update checkboxes and commit**

```powershell
git add tool/cli/verify-local-first.ps1 docs/superpowers/plans/2026-07-30-p0-p1-local-first-foundation.md
git commit -m "test(local-first): add bounded foundation gate"
```

---

## P0-P1 Completion Gate

- [ ] Baseline is reproducible and unrelated failures are classified.
- [ ] Field-build defaults hide fabricated/unverified paths.
- [ ] Drift schema version 1 creates all master data-spine tables.
- [ ] Stable local guest ownership survives restart.
- [ ] Vocabulary CRUD and import are durable and owner-scoped.
- [ ] Local mutation and outbox append are atomic and idempotent.
- [ ] Vocabulary screens contain no direct Firebase, HTTP, Drift, or plugin calls.
- [ ] Cloud initialization failure leaves local vocabulary usable.
- [ ] Focused package tests, P0-P1 integration tests, analyzer scope, and Android debug build pass.
- [ ] Manual Android force-stop/restart confirms persisted vocabulary.

## Next Plan

After this gate passes, create
`docs/superpowers/plans/2026-07-30-p2-firebase-sync-and-guest-upgrade.md`.
That plan consumes the frozen Drift schema and outbox interfaces from this plan;
it must not redesign vocabulary persistence.
