/// Tests for DriftLearningProjectionRebuilder
///
/// Verifies rebuildWord() replays AnswerAttempts to reconstruct
/// SrsStates + XP PointsLedgerEntries, and is idempotent.
///
/// Run: flutter test test/features/learning/data/drift_learning_projection_rebuilder_test.dart
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_projection_rebuilder.dart';

AppDatabase _openMemory() => AppDatabase(NativeDatabase.memory());

Future<void> _seedOwnerAndWord(AppDatabase db) async {
  await db
      .into(db.localOwners)
      .insert(
        LocalOwnersCompanion.insert(id: 'owner-rebuild', createdAtUtcMs: 1),
      );
  // AnswerAttempts.session_id has FK → LearningSessions
  await db
      .into(db.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'session-rebuild',
          ownerId: 'owner-rebuild',
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: 1,
          appVersion: '0.0.0',
          buildId: 'test',
        ),
      );
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'cat-rebuild',
          ownerId: 'owner-rebuild',
          name: 'rebuild-test',
          normalizedName: 'rebuild-test',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await db
      .into(db.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-rebuild',
          ownerId: 'owner-rebuild',
          categoryId: 'cat-rebuild',
          spelling: 'rebuild',
          normalizedSpelling: 'rebuild',
          meaning: 'test',
          normalizedMeaning: 'test',
          partOfSpeech: 'verb',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _insertAttempt(
  AppDatabase db, {
  required bool isCorrect,
  required int seqMs,
  required int attemptNumber,
}) async {
  await db
      .into(db.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: 'attempt-$seqMs',
          ownerId: 'owner-rebuild',
          wordId: 'word-rebuild',
          sessionId: 'session-rebuild',
          promptMode: 'meaningChoice',
          isCorrect: isCorrect,
          attemptNumber: attemptNumber,
          occurredAtUtcMs:
              DateTime.utc(2026, 1, 1).millisecondsSinceEpoch + seqMs,
        ),
      );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _openMemory();
    await _seedOwnerAndWord(db);
  });
  tearDown(() => db.close());

  group('DriftLearningProjectionRebuilder', () {
    test('rebuildWord writes SrsState row from answer history', () async {
      await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
      await _insertAttempt(db, isCorrect: false, seqMs: 1000, attemptNumber: 2);
      await _insertAttempt(db, isCorrect: true, seqMs: 2000, attemptNumber: 3);

      final rebuilder = DriftLearningProjectionRebuilder(db);
      final snapshot = await rebuilder.rebuildWord(
        ownerId: 'owner-rebuild',
        wordId: 'word-rebuild',
      );

      expect(snapshot.intervalDays, greaterThanOrEqualTo(1));

      final srsRows = await (db.select(
        db.srsStates,
      )..where((row) => row.ownerId.equals('owner-rebuild'))).get();
      expect(srsRows.length, 1);
    });

    test('rebuildWord inserts XP entry for each correct answer', () async {
      await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
      await _insertAttempt(db, isCorrect: true, seqMs: 1000, attemptNumber: 2);
      await _insertAttempt(db, isCorrect: false, seqMs: 2000, attemptNumber: 3);

      final rebuilder = DriftLearningProjectionRebuilder(db);
      await rebuilder.rebuildWord(
        ownerId: 'owner-rebuild',
        wordId: 'word-rebuild',
      );

      final entries = await (db.select(
        db.pointsLedgerEntries,
      )..where((row) => row.ownerId.equals('owner-rebuild'))).get();
      expect(entries.length, 2); // 2 correct answers → 2 XP entries
      expect(entries.every((e) => e.amount > 0), isTrue);
    });

    test('rebuildWord throws StateError when no attempts exist', () async {
      final rebuilder = DriftLearningProjectionRebuilder(db);
      await expectLater(
        () => rebuilder.rebuildWord(
          ownerId: 'owner-rebuild',
          wordId: 'word-rebuild',
        ),
        throwsStateError,
      );
    });

    test(
      'rebuildWord is idempotent — XP count stable across two runs',
      () async {
        await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
        await _insertAttempt(
          db,
          isCorrect: true,
          seqMs: 1000,
          attemptNumber: 2,
        );

        final rebuilder = DriftLearningProjectionRebuilder(db);
        await rebuilder.rebuildWord(
          ownerId: 'owner-rebuild',
          wordId: 'word-rebuild',
        );
        // Second run — idempotency key must prevent duplicate XP entries
        await rebuilder.rebuildWord(
          ownerId: 'owner-rebuild',
          wordId: 'word-rebuild',
        );

        final entries = await (db.select(
          db.pointsLedgerEntries,
        )..where((row) => row.ownerId.equals('owner-rebuild'))).get();
        expect(entries.length, 2);
      },
    );
  });
}
