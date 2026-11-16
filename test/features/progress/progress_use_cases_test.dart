import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';

void main() {
  test('history excludes a missed word in a tombstoned set', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedCompletedHistory(database);
    final progress = ProgressUseCases(
      owners: _MutableOwners('owner-a'),
      queries: DriftProgressQueries(database),
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
    final original = (await progress.loadSession('finished-a'))!;
    expect(original.mistakes.single.id, 'word-a');

    // Sync can remove a set before the individual word's tombstone arrives.
    await (database.update(database.vocabularyCategories)
          ..where((row) => row.id.equals('category-a')))
        .write(const VocabularyCategoriesCompanion(isDeleted: Value(true)));
    expect(
      (await database.select(database.vocabularyWords).getSingle()).isDeleted,
      isFalse,
    );
    final reopened = (await progress.loadSession('finished-a'))!;
    expect(reopened.summary.id, original.summary.id);
    expect(reopened.summary.wrongCount, 1);
    expect(reopened.summary.score, 0);
    expect(reopened.mistakes, isEmpty);
    expect(original.mistakes.single.localRevision, 4);
  });

  test(
    'a saved history origin cannot follow a session to another owner',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedCompletedHistory(database);
      final owners = _MutableOwners('owner-a');
      final progress = ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026, 11, 14),
      );
      final original = (await progress.loadSession(
        'finished-a',
        expectedOwnerId: 'owner-a',
      ))!;

      await database.transaction(() async {
        await database.customStatement(
          'UPDATE local_owners SET is_active = 0 WHERE id = ?',
          ['owner-a'],
        );
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(id: 'owner-b', createdAtUtcMs: 6),
            );
        for (final table in [
          'vocabulary_categories',
          'vocabulary_words',
          'learning_sessions',
          'answer_attempts',
        ]) {
          await database.customStatement(
            'UPDATE $table SET owner_id = ? WHERE owner_id = ?',
            ['owner-b', 'owner-a'],
          );
        }
      });
      owners.id = 'owner-b';
      final transferred = (await progress.loadSession(original.summary.id))!;
      expect(transferred.summary.id, original.summary.id);
      expect(transferred.ownerId, 'owner-b');
      expect(transferred.mistakes.single.id, original.mistakes.single.id);
      await expectLater(
        progress.loadSession(
          original.summary.id,
          expectedOwnerId: original.ownerId,
        ),
        throwsStateError,
      );
    },
  );

  for (final switchOwner in [false, true]) {
    test(
      switchOwner
          ? 'summary rejects A when the same owner provider switches during its query'
          : 'summary returns A when its owner remains active during the query',
      () async {
        final gate = _HeldProgressQuery();
        final database = AppDatabase(
          NativeDatabase.memory().interceptWith(gate),
        );
        final owners = _MutableOwners('owner-a');
        try {
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(id: 'owner-a', createdAtUtcMs: 1),
              );
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'owner-b',
                  createdAtUtcMs: 2,
                  isActive: const Value(false),
                ),
              );
          await database
              .into(database.vocabularyCategories)
              .insert(
                VocabularyCategoriesCompanion.insert(
                  id: 'category-a',
                  ownerId: 'owner-a',
                  name: 'Private A',
                  normalizedName: 'private a',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: 'word-a',
                  ownerId: 'owner-a',
                  categoryId: 'category-a',
                  spelling: 'mug',
                  normalizedSpelling: 'mug',
                  meaning: 'แก้ว',
                  normalizedMeaning: 'แก้ว',
                  partOfSpeech: 'noun',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
          final wordsBefore = await database
              .select(database.vocabularyWords)
              .get();
          final outboxBefore = await database
              .select(database.outboxOperations)
              .get();
          final progress = ProgressUseCases(
            owners: owners,
            queries: DriftProgressQueries(database),
            nowUtc: () => DateTime.utc(2026, 11, 14),
          );
          gate.armed = true;
          final pending = progress.load();
          await gate.started.future;
          if (switchOwner) owners.id = 'owner-b';
          final checked = switchOwner
              ? expectLater(pending, throwsStateError)
              : expectLater(
                  pending,
                  completion(
                    isA<ProgressSnapshot>().having(
                      (snapshot) => snapshot.vocabularyWordCount,
                      'A vocabulary count',
                      1,
                    ),
                  ),
                );
          gate.release.complete();
          await checked;
          if (switchOwner) {
            expect((await progress.load()).vocabularyWordCount, 0);
          }
          expect(
            await database.select(database.vocabularyWords).get(),
            wordsBefore,
          );
          expect(
            await database.select(database.outboxOperations).get(),
            outboxBefore,
          );
        } finally {
          if (!gate.release.isCompleted) gate.release.complete();
          await database.close();
        }
      },
    );
  }
}

Future<void> _seedCompletedHistory(AppDatabase database) async {
  await database
      .into(database.localOwners)
      .insert(LocalOwnersCompanion.insert(id: 'owner-a', createdAtUtcMs: 1));
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-a',
          ownerId: 'owner-a',
          name: 'Travel',
          normalizedName: 'travel',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 2,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-a',
          ownerId: 'owner-a',
          categoryId: 'category-a',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          localRevision: const Value(4),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 2,
        ),
      );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'finished-a',
          ownerId: 'owner-a',
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: 3,
          endedAtUtcMs: const Value(5),
          wrongCount: const Value(1),
          score: const Value(0),
          appVersion: 'test',
          buildId: 'test',
        ),
      );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: 'attempt-a',
          ownerId: 'owner-a',
          sessionId: 'finished-a',
          wordId: 'word-a',
          promptMode: 'meaningChoice',
          isCorrect: false,
          attemptNumber: 1,
          occurredAtUtcMs: 4,
        ),
      );
}

final class _HeldProgressQuery extends QueryInterceptor {
  bool armed = false;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (armed &&
        statement.contains('answer_attempts') &&
        args.contains('owner-a')) {
      armed = false;
      started.complete();
      await release.future;
    }
    return executor.runSelect(statement, args);
  }
}

final class _MutableOwners implements LocalOwnerRepository {
  _MutableOwners(this.id);

  String id;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 11, 14));

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => throw UnimplementedError();
}
