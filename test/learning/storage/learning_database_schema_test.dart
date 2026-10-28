import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/storage/learning_database.dart';

void main() {
  late LearningDatabase database;

  setUp(() {
    database = LearningDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('creates the complete owner-scoped learning schema', () async {
    const expectedTables = <String>{
      'learning_commits',
      'associations',
      'reading_sessions',
      'recall_attempts',
      'memory_states',
      'learning_events',
      'sync_outbox',
      'deletion_tombstones',
    };

    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' AND name != 'drift_schema'",
        )
        .get();

    expect(
      rows.map((row) => row.read<String>('name')).toSet(),
      containsAll(expectedTables),
    );

    for (final table in expectedTables) {
      final columns = await database
          .customSelect('PRAGMA table_info($table)')
          .get();
      final names = columns
          .map((column) => column.read<String>('name'))
          .toSet();

      expect(names, contains('owner_id'), reason: table);
      expect(names, contains('schema_version'), reason: table);
      expect(names, contains('created_at_utc'), reason: table);
      expect(names, contains('updated_at_utc'), reason: table);
    }
  });

  test('uses composite owner keys for durable identity', () async {
    final commits = await database
        .customSelect('PRAGMA table_info(learning_commits)')
        .get();
    final memories = await database
        .customSelect('PRAGMA table_info(memory_states)')
        .get();

    expect(_primaryKeyColumns(commits), ['owner_id', 'commit_id']);
    expect(_primaryKeyColumns(memories), ['owner_id', 'word_key']);
  });

  test('stores a content fingerprint for idempotency validation', () async {
    final commits = await database
        .customSelect('PRAGMA table_info(learning_commits)')
        .get();

    expect(
      commits.map((column) => column.read<String>('name')),
      contains('content_fingerprint'),
    );
  });

  test('starts at schema version one', () {
    expect(database.schemaVersion, 1);
  });
}

List<String> _primaryKeyColumns(List<QueryRow> columns) {
  final keyed = columns.where((column) => column.read<int>('pk') > 0).toList()
    ..sort(
      (left, right) => left.read<int>('pk').compareTo(right.read<int>('pk')),
    );

  return keyed.map((column) => column.read<String>('name')).toList();
}
