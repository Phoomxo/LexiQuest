import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning/data/learning_session_lifecycle_observer.dart';

const configuredOwnerId = 'synthetic-configured-owner-a';
const configuredOtherOwnerId = 'synthetic-configured-owner-b';
const configuredFirebaseUid = 'synthetic-configured-uid-a';
const configuredCategoryId = 'synthetic-configured-category-a';
const configuredOtherCategoryId = 'synthetic-configured-category-b';
const configuredWordIds = <String>[
  'synthetic-configured-word-1',
  'synthetic-configured-word-2',
  'synthetic-configured-word-3',
  'synthetic-configured-word-4',
];
final configuredStart = DateTime.utc(2026, 10, 29, 12, 0, 0, 123);

final class ConfiguredQuizHarness {
  ConfiguredQuizHarness._(this.database, this.file) {
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-created-owner',
      nowUtc: () => now,
    );
    ownerWrites = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => now,
      nonceGenerator: () => 'synthetic-configured-nonce-${++_nextNonce}',
    );
  }

  static Future<ConfiguredQuizHarness> open({
    File? file,
    bool seed = true,
  }) async {
    final database = db.AppDatabase(
      file == null ? NativeDatabase.memory() : NativeDatabase(file),
    );
    final result = ConfiguredQuizHarness._(database, file);
    if (seed) await result._seed();
    return result;
  }

  final db.AppDatabase database;
  final File? file;
  late final DriftLocalOwnerRepository owners;
  late final DriftOwnerWriteCoordinator ownerWrites;
  DateTime now = configuredStart;
  int _nextNonce = 0;
  bool _closed = false;

  Future<ConfiguredQuizHarness> reopen() async {
    if (file == null) throw StateError('reopen requires a file database');
    await close();
    final next = await open(file: file, seed: false);
    next.now = now;
    return next;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await database.close();
  }

  Future<void> switchOwner(String ownerId) => database.customStatement(
    'UPDATE local_owners SET is_active = (id = ?)',
    [ownerId],
  );

  Future<int> count(String table) async =>
      (await database
              .customSelect('SELECT COUNT(*) AS count FROM $table')
              .getSingle())
          .read<int>('count');

  Future<Map<String, Object?>> session(String sessionId) async =>
      (await database
              .customSelect(
                'SELECT * FROM learning_sessions WHERE id = ?',
                variables: [drift.Variable<String>(sessionId)],
              )
              .getSingle())
          .data;

  Future<Map<String, List<String>>> snapshot() async {
    final result = <String, List<String>>{};
    for (final table in database.allTables) {
      final rows = await database
          .customSelect('SELECT * FROM ${table.actualTableName}')
          .get();
      result[table.actualTableName] =
          rows.map((row) => jsonEncode(row.data)).toList()..sort();
    }
    return result;
  }

  Future<Map<String, int>> researchCounts() async => {
    for (final table in const [
      'research_consents',
      'experiment_assignments',
      'research_participation_permits',
      'motivation_measurement_runs',
      'motivation_responses',
      'measurement_opportunities',
      'events_v2',
    ])
      table: await count(table),
  };

  Future<void> addWord({
    required String id,
    required String spelling,
    required String meaning,
    String ownerId = configuredOwnerId,
    String categoryId = configuredCategoryId,
  }) async {
    await database
        .into(database.vocabularyWords)
        .insert(
          db.VocabularyWordsCompanion.insert(
            id: id,
            ownerId: ownerId,
            categoryId: categoryId,
            spelling: spelling,
            normalizedSpelling: spelling.toLowerCase(),
            meaning: meaning,
            normalizedMeaning: meaning.toLowerCase(),
            partOfSpeech: 'noun',
            createdAtUtcMs: configuredStart.millisecondsSinceEpoch,
            updatedAtUtcMs: configuredStart.millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> _seed() async {
    await database
        .into(database.localOwners)
        .insert(
          db.LocalOwnersCompanion.insert(
            id: configuredOwnerId,
            firebaseUid: const drift.Value(configuredFirebaseUid),
            accountState: const drift.Value('firebaseBound'),
            createdAtUtcMs: configuredStart.millisecondsSinceEpoch,
          ),
        );
    await database
        .into(database.localOwners)
        .insert(
          db.LocalOwnersCompanion.insert(
            id: configuredOtherOwnerId,
            firebaseUid: const drift.Value('synthetic-configured-uid-b'),
            accountState: const drift.Value('firebaseBound'),
            isActive: const drift.Value(false),
            createdAtUtcMs: configuredStart.millisecondsSinceEpoch,
          ),
        );
    for (final pair in const [
      (configuredOwnerId, configuredCategoryId),
      (configuredOtherOwnerId, configuredOtherCategoryId),
    ]) {
      await database
          .into(database.vocabularyCategories)
          .insert(
            db.VocabularyCategoriesCompanion.insert(
              id: pair.$2,
              ownerId: pair.$1,
              name: pair.$1 == configuredOwnerId
                  ? 'Synthetic travel'
                  : 'Synthetic unrelated',
              normalizedName: pair.$1 == configuredOwnerId
                  ? 'synthetic travel'
                  : 'synthetic unrelated',
              createdAtUtcMs: configuredStart.millisecondsSinceEpoch,
              updatedAtUtcMs: configuredStart.millisecondsSinceEpoch,
            ),
          );
    }
    for (final word in const [
      ('synthetic-configured-word-1', 'station', 'สถานี'),
      ('synthetic-configured-word-2', 'ticket', 'ตั๋ว'),
      ('synthetic-configured-word-3', 'platform', 'ชานชาลา'),
      ('synthetic-configured-word-4', 'journey', 'การเดินทาง'),
    ]) {
      await addWord(id: word.$1, spelling: word.$2, meaning: word.$3);
    }
    await addWord(
      id: 'synthetic-configured-other-word',
      ownerId: configuredOtherOwnerId,
      categoryId: configuredOtherCategoryId,
      spelling: 'unrelated',
      meaning: 'ไม่เกี่ยวข้อง',
    );
  }
}

final class ConfiguredQuizObserver implements LearningSessionLifecycleObserver {
  ConfiguredQuizObserver(this.database);

  @override
  final db.AppDatabase database;
  final acceptedFacts = <LearningSessionLifecycleFact>[];
  final completedFacts = <LearningSessionLifecycleFact>[];
  final acceptedRows = <Map<String, Object?>>[];
  bool denyAccepted = false;
  bool denyCompleted = false;

  @override
  Future<void> accepted(LearningSessionLifecycleFact fact) async {
    acceptedFacts.add(fact);
    acceptedRows.add(
      (await database
              .customSelect(
                'SELECT * FROM learning_sessions WHERE id = ?',
                variables: [drift.Variable<String>(fact.id)],
              )
              .getSingle())
          .data,
    );
    await _marker('accepted', fact.id);
    if (denyAccepted) throw StateError('synthetic research denial');
  }

  @override
  Future<void> completed(LearningSessionLifecycleFact fact) async {
    completedFacts.add(fact);
    await _marker('completed', fact.id);
    if (denyCompleted) throw StateError('synthetic research denial');
  }

  Future<void> _marker(String phase, String sessionId) =>
      database.customStatement(
        'INSERT INTO runtime_flags '
        '(key, bool_value, source, updated_at_utc_ms) VALUES (?, 1, ?, 1) '
        'ON CONFLICT(key) DO UPDATE SET source = excluded.source',
        ['synthetic-configured:$phase:$sessionId', phase],
      );
}
