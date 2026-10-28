import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_learning_history_queries.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_history_models.dart';

void main() {
  late AppDatabase database;
  late DriftLearningHistoryQueries history;
  final now = DateTime(2026, 10, 28, 12).toUtc();

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    history = DriftLearningHistoryQueries(database);
    for (final owner in ['a', 'b']) {
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: owner,
              createdAtUtcMs: 1,
              isActive: Value(owner == 'a'),
            ),
          );
      await database
          .into(database.vocabularyCategories)
          .insert(
            VocabularyCategoriesCompanion.insert(
              id: 'category-$owner',
              ownerId: owner,
              name: 'Synthetic',
              normalizedName: 'synthetic',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'word-$owner',
              ownerId: owner,
              categoryId: 'category-$owner',
              spelling: 'sample',
              normalizedSpelling: 'sample',
              meaning: 'ตัวอย่าง',
              normalizedMeaning: 'ตัวอย่าง',
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
  });

  tearDown(() => database.close());

  Future<void> session(
    String id, {
    String owner = 'a',
    String state = 'completed',
    DateTime? started,
    String mode = 'quiz',
  }) => database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: id,
          ownerId: owner,
          activityType: mode,
          state: state,
          startedAtUtcMs: (started ?? now).millisecondsSinceEpoch,
          endedAtUtcMs: state == 'completed'
              ? Value(now.millisecondsSinceEpoch)
              : const Value.absent(),
          correctCount: const Value(99),
          wrongCount: const Value(99),
          appVersion: 'synthetic',
          buildId: 'synthetic',
        ),
      )
      .then((_) {});

  Future<void> answer(
    String id,
    String sessionId, {
    String owner = 'a',
    String? wordId,
    bool correct = true,
    DateTime? occurred,
  }) => database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: id,
          ownerId: owner,
          sessionId: sessionId,
          wordId: wordId ?? 'word-$owner',
          promptMode: 'meaningChoice',
          isCorrect: correct,
          attemptNumber: 1,
          occurredAtUtcMs: (occurred ?? now).millisecondsSinceEpoch,
        ),
      )
      .then((_) {});

  test(
    'history includes unfinished rounds and counts canonical owner answers',
    () async {
      await session(
        'completed',
        started: now.subtract(const Duration(hours: 3)),
      );
      await session(
        'abandoned',
        state: 'abandoned',
        started: now.subtract(const Duration(hours: 2)),
      );
      await session('active', state: 'active');
      await session('private-b', owner: 'b');
      await answer('correct', 'completed');
      await answer('wrong', 'completed', correct: false);
      await answer('retained', 'abandoned');
      await answer('other-owner', 'private-b', owner: 'b');
      // A malformed legacy relation must not contaminate either owner's counts.
      await answer('cross-owner', 'completed', owner: 'b');
      await (database.update(database.vocabularyWords)
            ..where((word) => word.id.equals('word-a')))
          .write(const VocabularyWordsCompanion(isDeleted: Value(true)));

      final before = await _snapshot(database);
      final result = await history.load(ownerId: 'a', nowUtc: now);

      expect(result.ownerId, 'a');
      expect(result.entries.map((entry) => entry.sessionId), [
        'active',
        'abandoned',
        'completed',
      ]);
      expect(result.entries.map((entry) => entry.state), [
        'active',
        'abandoned',
        'completed',
      ]);
      expect(
        result.entries.map((entry) => (entry.answerCount, entry.correctCount)),
        [(0, 0), (1, 1), (2, 1)],
      );
      expect(result.entries.last.activityType, 'quiz');
      expect(result.entries.last.endedAtUtc, now);
      expect(result.days.fold(0, (sum, day) => sum + day.answerCount), 3);
      final other = await history.load(ownerId: 'b', nowUtc: now);
      expect(other.entries.single.answerCount, 1);
      expect(other.days.fold(0, (sum, day) => sum + day.answerCount), 1);
      expect(
        await _snapshot(database),
        before,
        reason:
            'Viewing history must not create learning, reward, research, or outbox rows.',
      );
    },
  );

  test(
    'history identifies stored quiz recovery without creating a plan for legacy rows',
    () async {
      for (final mode in ['quiz', 'weaknessPractice', 'sourcePractice']) {
        await session(mode, state: 'active', mode: mode);
        await database.customStatement(
          'UPDATE learning_sessions SET accepted_plan_id = ?, accepted_plan_json = ?, '
          'checkpoint_revision = 3, checkpoint_json = ? WHERE id = ?',
          [
            'synthetic-plan-$mode',
            'synthetic-plan-body-$mode',
            'synthetic-checkpoint-$mode',
            mode,
          ],
        );
      }
      await session('legacy', state: 'active');
      await session('partial', state: 'active');
      await database.customStatement(
        "UPDATE learning_sessions SET accepted_plan_id = 'synthetic-partial' WHERE id = 'partial'",
      );
      final before = await _snapshot(database);
      final result = await history.load(ownerId: 'a', nowUtc: now);
      expect(
        result.entries
            .where((entry) => entry.hasAcceptedQuiz)
            .map((entry) => entry.sessionId)
            .toSet(),
        {'quiz', 'weaknessPractice', 'sourcePractice'},
      );
      expect(
        result.entries
            .where((entry) => !entry.hasAcceptedQuiz)
            .map((entry) => entry.sessionId)
            .toSet(),
        {'legacy', 'partial'},
      );
      expect(await _snapshot(database), before);
    },
  );

  test(
    'daily answer frequency follows seven local civil dates across midnight',
    () async {
      await session('round');
      await answer(
        'before-midnight',
        'round',
        occurred: DateTime(2026, 10, 27, 23, 59).toUtc(),
      );
      await answer(
        'after-midnight',
        'round',
        occurred: DateTime(2026, 10, 28, 0, 1).toUtc(),
      );
      await answer(
        'today',
        'round',
        occurred: DateTime(2026, 10, 28, 11).toUtc(),
      );
      await answer(
        'first-day',
        'round',
        occurred: DateTime(2026, 10, 22).toUtc(),
      );
      await answer(
        'outside-window',
        'round',
        occurred: DateTime(2026, 10, 21, 23, 59).toUtc(),
      );
      await answer(
        'tomorrow',
        'round',
        occurred: DateTime(2026, 10, 29).toUtc(),
      );

      final result = await history.load(ownerId: 'a', nowUtc: now);

      expect(
        result.days.map(
          (day) => (day.day.year, day.day.month, day.day.day, day.answerCount),
        ),
        [
          (2026, 10, 22, 1),
          (2026, 10, 23, 0),
          (2026, 10, 24, 0),
          (2026, 10, 25, 0),
          (2026, 10, 26, 0),
          (2026, 10, 27, 1),
          (2026, 10, 28, 2),
        ],
      );
    },
  );

  test(
    'stable cursor reaches older rounds once and daily counts ignore pagination',
    () async {
      for (var i = 0; i < 52; i++) {
        await session('round-${i.toString().padLeft(3, '0')}');
      }
      await answer('old-answer', 'round-000');
      final first = await history.load(ownerId: 'a', nowUtc: now);
      expect(first.entries, hasLength(50));
      expect(first.hasMore, isTrue);
      expect(first.nextCursor!.ownerId, 'a');
      final second = await history.load(
        ownerId: 'a',
        nowUtc: now,
        before: first.nextCursor,
      );
      expect(second.entries.map((entry) => entry.sessionId), [
        'round-001',
        'round-000',
      ]);
      expect(second.hasMore, isFalse);
      expect({
        ...first.entries.map((entry) => entry.sessionId),
        ...second.entries.map((entry) => entry.sessionId),
      }, hasLength(52));
      expect(first.days.last.answerCount, 1);
      expect(second.days.last.answerCount, 1);
      expect(
        () => history.load(ownerId: 'b', nowUtc: now, before: first.nextCursor),
        throwsStateError,
      );
    },
  );

  test(
    'each page keeps exact multiword counts across a large owner history',
    () async {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'word-a-second',
              ownerId: 'a',
              categoryId: 'category-a',
              spelling: 'second',
              normalizedSpelling: 'second',
              meaning: 'ที่สอง',
              normalizedMeaning: 'ที่สอง',
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      var expectedAnswers = 0;
      for (var index = 0; index < 105; index++) {
        final id = 'dense-${index.toString().padLeft(3, '0')}';
        await session(id, started: now.subtract(Duration(minutes: index)));
        final count = index % 4 + 1;
        expectedAnswers += count;
        for (var attempt = 0; attempt < count; attempt++) {
          await answer(
            'answer-$index-$attempt',
            id,
            wordId: attempt.isEven ? 'word-a' : 'word-a-second',
            correct: attempt.isEven,
          );
        }
      }
      await session('private-b', owner: 'b');
      await answer('private-answer', 'private-b', owner: 'b');
      await answer('cross-owner-forward', 'dense-000', owner: 'b');
      await answer('cross-owner-reverse', 'private-b');
      final entries = <LearningHistoryEntry>[];
      LearningHistoryCursor? cursor;
      final pageLengths = <int>[];
      do {
        final page = await history.load(
          ownerId: 'a',
          nowUtc: now,
          before: cursor,
        );
        pageLengths.add(page.entries.length);
        expect(page.days.last.answerCount, expectedAnswers);
        entries.addAll(page.entries);
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(pageLengths, [50, 50, 5]);
      expect(
        entries.map((entry) => entry.sessionId),
        List.generate(
          105,
          (index) => 'dense-${index.toString().padLeft(3, '0')}',
        ),
      );
      for (var index = 0; index < entries.length; index++) {
        final count = index % 4 + 1;
        expect(entries[index].answerCount, count);
        expect(entries[index].correctCount, (count + 1) ~/ 2);
      }
    },
  );

  test(
    'owner with no evidence has no invented sessions or answer counts',
    () async {
      final result = await history.load(ownerId: 'a', nowUtc: now);
      expect(result.entries, isEmpty);
      expect(result.hasMore, isFalse);
      expect(result.days, hasLength(7));
      expect(result.days.every((day) => day.answerCount == 0), isTrue);
    },
  );

  test('application rejects history if owner changed while reading', () async {
    final owners = _Owners(['a', 'b']);
    final useCases = ProgressUseCases(
      owners: owners,
      queries: DriftProgressQueries(database),
      nowUtc: () => now,
    );
    await expectLater(useCases.loadHistory(), throwsStateError);
  });

  test(
    'application rejects a previous owner pagination cursor before reading',
    () async {
      final useCases = ProgressUseCases(
        owners: _Owners(['b']),
        queries: DriftProgressQueries(database),
        nowUtc: () => now,
      );
      await expectLater(
        useCases.loadHistory(
          before: LearningHistoryCursor(
            ownerId: 'a',
            startedAtUtc: now,
            sessionId: 'old',
          ),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'active owner stream reports account changes without writing rows',
    () async {
      final useCases = ProgressUseCases(
        owners: _Owners(['a']),
        queries: DriftProgressQueries(database),
        nowUtc: () => now,
      );
      final events = <String?>[];
      final first = useCases.watchActiveOwnerId().listen(events.add);
      await pumpEventQueue();
      expect(events, ['a']);
      await database.transaction(() async {
        await (database.update(database.localOwners)
              ..where((owner) => owner.id.equals('a')))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await (database.update(database.localOwners)
              ..where((owner) => owner.id.equals('b')))
            .write(const LocalOwnersCompanion(isActive: Value(true)));
      });
      await pumpEventQueue();
      expect(events, ['a', 'b']);
      await first.cancel();
    },
  );
}

final class _Owners implements LocalOwnerRepository {
  _Owners(this.ids);
  final List<String> ids;
  var reads = 0;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => LocalOwner(
    id: ids[reads < ids.length ? reads++ : ids.length - 1],
    createdAtUtc: DateTime.utc(2026),
  );
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

Future<Map<String, List<String>>> _snapshot(AppDatabase database) async => {
  for (final table in database.allTables)
    table.actualTableName:
        (await database
                .customSelect('SELECT * FROM "${table.actualTableName}"')
                .get())
            .map((row) => jsonEncode(row.data))
            .toList()
          ..sort(),
};
