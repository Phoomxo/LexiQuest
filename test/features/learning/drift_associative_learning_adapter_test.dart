import 'package:drift/native.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_associative_learning_adapter.dart';

void main() {
  late db.AppDatabase database;
  late DriftAssociativeLearningAdapter adapter;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    adapter = DriftAssociativeLearningAdapter(database);

    await database.customInsert(
      "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
      "VALUES ('owner-da', 'localGuest', 1722758400000)",
    );
  });

  tearDown(() async => database.close());

  group('DriftAssociativeLearningAdapter — D8.3', () {
    // ── Associations ────────────────────────────────────────────────────────

    test('saveAssociation persists row', () async {
      await adapter.saveAssociation(
        AssociationRecord(
          associationId: 'assoc-1',
          ownerId: 'owner-da',
          wordKey: 'banana',
          type: 'keyword',
          content: 'yellow fruit',
          createdAtUtc: DateTime.utc(2026, 8, 4, 10, 0),
        ),
      );

      final associations = await adapter.getAssociationsForWord(
        'owner-da',
        'banana',
      );
      expect(associations, hasLength(1));
      expect(associations.first.content, 'yellow fruit');
      expect(associations.first.type, 'keyword');
    });

    test('saveAssociation upserts on same (owner, wordKey, type)', () async {
      final record = AssociationRecord(
        associationId: 'assoc-up',
        ownerId: 'owner-da',
        wordKey: 'apple',
        type: 'keyword',
        content: 'round red fruit',
        createdAtUtc: DateTime.utc(2026, 8, 4),
      );
      await adapter.saveAssociation(record);
      await adapter.saveAssociation(
        AssociationRecord(
          associationId: 'assoc-up-2',
          ownerId: 'owner-da',
          wordKey: 'apple',
          type: 'keyword',
          content: 'crunchy snack',
          createdAtUtc: DateTime.utc(2026, 8, 4),
        ),
      );

      final associations = await adapter.getAssociationsForWord(
        'owner-da',
        'apple',
      );
      expect(associations, hasLength(1));
      expect(associations.first.content, 'crunchy snack');
    });

    test('deleteAssociation removes the row', () async {
      await adapter.saveAssociation(
        AssociationRecord(
          associationId: 'assoc-del',
          ownerId: 'owner-da',
          wordKey: 'grape',
          type: 'story',
          content: 'purple cluster',
          createdAtUtc: DateTime.utc(2026, 8, 4),
        ),
      );
      await adapter.deleteAssociation('assoc-del');
      final associations = await adapter.getAssociationsForWord(
        'owner-da',
        'grape',
      );
      expect(associations, isEmpty);
    });

    test('getAssociationsForWord returns only matching rows', () async {
      for (final word in ['cat', 'dog', 'cat']) {
        await adapter.saveAssociation(
          AssociationRecord(
            associationId:
                'assoc-$word-${DateTime.now().microsecondsSinceEpoch}',
            ownerId: 'owner-da',
            wordKey: word,
            type: word == 'cat' ? 'keyword' : 'story',
            content: '$word cue',
            createdAtUtc: DateTime.utc(2026, 8, 4),
          ),
        );
      }
      final catAssociations = await adapter.getAssociationsForWord(
        'owner-da',
        'cat',
      );
      expect(catAssociations, hasLength(1));
      expect(catAssociations.first.wordKey, 'cat');
    });

    // ── Memory states ────────────────────────────────────────────────────────

    test('getMemoryState returns null before any update', () async {
      final state = await adapter.getMemoryState('owner-da', 'missing');
      expect(state, isNull);
    });

    test('updateMemoryState persists and retrieves state', () async {
      final state = AssociativeMemoryState(
        ownerId: 'owner-da',
        wordKey: 'cat',
        stability: 2.5,
        difficulty: 4.0,
        cueDependency: 0.2,
        lapseCount: 1,
        lastReviewedAtUtc: DateTime.utc(2026, 8, 4, 9, 0),
        nextDueAtUtc: DateTime.utc(2026, 8, 7, 9, 0),
        algorithmVersion: 'v1.0.0',
      );
      await adapter.updateMemoryState(state);

      final retrieved = await adapter.getMemoryState('owner-da', 'cat');
      expect(retrieved, isNotNull);
      expect(retrieved!.stability, closeTo(2.5, 0.001));
      expect(retrieved.lapseCount, 1);
      expect(retrieved.algorithmVersion, 'v1.0.0');
    });

    test('updateMemoryState is idempotent (upsert)', () async {
      final base = AssociativeMemoryState(
        ownerId: 'owner-da',
        wordKey: 'dog',
        stability: 1.0,
        difficulty: 5.0,
        cueDependency: 0.0,
        lapseCount: 0,
        nextDueAtUtc: DateTime.utc(2026, 8, 5),
        algorithmVersion: 'v1.0.0',
      );
      await adapter.updateMemoryState(base);
      final updated = AssociativeMemoryState(
        ownerId: 'owner-da',
        wordKey: 'dog',
        stability: 3.0,
        difficulty: 4.0,
        cueDependency: 0.1,
        lapseCount: 0,
        lastReviewedAtUtc: DateTime.utc(2026, 8, 4, 10, 0),
        nextDueAtUtc: DateTime.utc(2026, 8, 7),
        algorithmVersion: 'v1.0.0',
      );
      await adapter.updateMemoryState(updated);

      final all = await adapter.getAllMemoryStates('owner-da');
      final dog = all.where((s) => s.wordKey == 'dog').toList();
      expect(dog, hasLength(1));
      expect(dog.first.stability, closeTo(3.0, 0.001));
    });
  });
}
