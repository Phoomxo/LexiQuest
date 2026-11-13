import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';

void main() {
  late AppDatabase database;
  late DriftLearningRepository learning;
  late DriftProgressQueries progress;
  var sequence = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    learning = DriftLearningRepository(database);
    progress = DriftProgressQueries(database);
    sequence = 0;
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in const [
      ('word-1', 'station', 'สถานี'),
      ('word-2', 'ticket', 'ตั๋ว'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: 'owner-1',
              categoryId: 'category-1',
              spelling: word.$2,
              normalizedSpelling: word.$2,
              meaning: word.$3,
              normalizedMeaning: word.$3,
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
  });

  tearDown(() => database.close());

  Future<void> startSession([String ownerId = 'owner-1']) =>
      learning.startSession(
        LearningSessionDraft(
          id: 'session-$ownerId',
          ownerId: ownerId,
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 10),
          appVersion: 'test',
          buildId: 'test',
        ),
      );

  Future<RecordAnswerCommand> record(
    String mode,
    bool correct, {
    String ownerId = 'owner-1',
    String wordId = 'word-1',
  }) async {
    final command = RecordAnswerCommand(
      id: 'synthetic-attempt-${++sequence}',
      ownerId: ownerId,
      sessionId: 'session-$ownerId',
      wordId: wordId,
      promptMode: mode,
      isCorrect: correct,
      responseTimeMs: 500,
      attemptNumber: sequence,
      occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 0, sequence),
      providerProvenance: 'local:synthetic-skill-test:v1',
    );
    await learning.recordAnswer(command);
    return command;
  }

  Future<ProgressSnapshot> load([String ownerId = 'owner-1']) async {
    final before = await _databaseSnapshot(database);
    final result = await progress.load(
      ownerId: ownerId,
      nowUtc: DateTime.utc(2026, 7, 30, 12),
    );
    expect(await _databaseSnapshot(database), before);
    return result;
  }

  Future<void> addSecondCategory() async {
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-b',
            ownerId: 'owner-1',
            name: 'Kitchen',
            normalizedName: 'kitchen',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-b',
            ownerId: 'owner-1',
            categoryId: 'category-b',
            spelling: 'plate',
            normalizedSpelling: 'plate',
            meaning: 'จาน',
            normalizedMeaning: 'จาน',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  }

  Future<void> completeCategorySession(
    String id,
    List<(String, bool)> answers,
    int minute,
  ) async {
    final start = DateTime.utc(2026, 7, 30, 10, minute);
    await learning.startSession(
      LearningSessionDraft(
        id: id,
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: start,
        appVersion: 'test',
        buildId: 'test',
      ),
    );
    for (var index = 0; index < answers.length; index++) {
      await learning.recordAnswer(
        RecordAnswerCommand(
          id: '$id:attempt:$index',
          ownerId: 'owner-1',
          sessionId: id,
          wordId: answers[index].$1,
          promptMode: 'meaningChoice',
          isCorrect: answers[index].$2,
          responseTimeMs: 500,
          attemptNumber: index + 1,
          occurredAtUtc: start.add(Duration(seconds: index)),
        ),
      );
    }
    await learning.finishSession(
      ownerId: 'owner-1',
      sessionId: id,
      endedAtUtc: start.add(const Duration(minutes: 1)),
    );
  }

  test(
    'category results keep A and B scores linked to their own saved ids',
    () async {
      await addSecondCategory();
      await completeCategorySession('session-a', [('word-1', false)], 0);
      await completeCategorySession('session-b', [('word-b', true)], 2);
      final useCases = ProgressUseCases(
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'unused',
          nowUtc: () => DateTime.utc(2026, 7, 30),
        ),
        queries: progress,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      );
      final before = await _databaseSnapshot(database);
      final resultA = await useCases.loadLatestSessionForCategory('category-1');
      final resultB = await useCases.loadLatestSessionForCategory('category-b');
      expect(resultA!.summary.id, 'session-a');
      expect(resultA.summary.score, 0);
      expect(resultA.categoryId, 'category-1');
      expect(resultA.categoryName, 'Travel');
      expect(resultB!.summary.id, 'session-b');
      expect(resultB.summary.score, 100);
      expect(resultB.categoryId, 'category-b');
      expect(resultB.categoryName, 'Kitchen');
      final snapshot = await load();
      expect(snapshot.recentSessions.map((entry) => entry.categoryName), [
        'Kitchen',
        'Travel',
      ]);
      expect(await _databaseSnapshot(database), before);
    },
  );

  test(
    'category result lookup does not lose A behind twenty newer B rounds',
    () async {
      await addSecondCategory();
      await completeCategorySession('old-a', [('word-1', false)], 0);
      for (var index = 0; index < 21; index++) {
        await completeCategorySession('new-b-$index', [
          ('word-b', true),
        ], index + 2);
      }
      final snapshot = await load();
      expect(snapshot.recentSessions, hasLength(20));
      expect(
        snapshot.recentSessions.every(
          (entry) => entry.categoryId == 'category-b',
        ),
        isTrue,
      );
      final before = await _databaseSnapshot(database);
      final result = await progress.loadLatestSessionForCategory(
        ownerId: 'owner-1',
        categoryId: 'category-1',
      );
      expect(result!.summary.id, 'old-a');
      expect(result.summary.score, 0);
      expect(await _databaseSnapshot(database), before);
    },
  );

  test('mixed and empty rounds have no invented category context', () async {
    await addSecondCategory();
    await completeCategorySession('single-a', [('word-1', true)], 0);
    await completeCategorySession('mixed', [
      ('word-1', false),
      ('word-b', true),
    ], 2);
    await completeCategorySession('empty', [], 4);
    for (final id in ['mixed', 'empty']) {
      final result = await progress.loadSession(
        ownerId: 'owner-1',
        sessionId: id,
      );
      expect(result!.categoryId, isNull);
      expect(result.categoryName, isNull);
    }
    final latestA = await progress.loadLatestSessionForCategory(
      ownerId: 'owner-1',
      categoryId: 'category-1',
    );
    expect(latestA!.summary.id, 'single-a');
    expect(
      await progress.loadLatestSessionForCategory(
        ownerId: 'other-owner',
        categoryId: 'category-1',
      ),
      isNull,
    );
    expect(
      await progress.loadLatestSessionForCategory(
        ownerId: 'owner-1',
        categoryId: 'missing-category',
      ),
      isNull,
    );
  });

  test(
    'category context uses the current owner-matched name without rewriting a result',
    () async {
      await completeCategorySession('saved-a', [('word-1', false)], 0);
      await database.customStatement(
        'UPDATE vocabulary_categories SET name = ? WHERE id = ?',
        ['Travel renamed', 'category-1'],
      );
      final before = await _databaseSnapshot(database);
      final renamed = await progress.loadSession(
        ownerId: 'owner-1',
        sessionId: 'saved-a',
      );
      expect(renamed!.categoryName, 'Travel renamed');
      expect(renamed.summary.score, 0);
      expect(await _databaseSnapshot(database), before);

      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 1),
          );
      await database.customStatement(
        'UPDATE vocabulary_categories SET owner_id = ? WHERE id = ?',
        ['owner-2', 'category-1'],
      );
      final mismatched = await progress.loadSession(
        ownerId: 'owner-1',
        sessionId: 'saved-a',
      );
      expect(mismatched!.categoryId, isNull);
      expect(mismatched.categoryName, isNull);
      expect(mismatched.summary.wrongCount, 1);
      expect(
        await progress.loadLatestSessionForCategory(
          ownerId: 'owner-1',
          categoryId: 'category-1',
        ),
        isNull,
      );
      await database.customStatement(
        'UPDATE srs_states SET due_at_utc_ms = 1 WHERE word_id = ?',
        ['word-1'],
      );
      final due = await load();
      expect(due.dueReviewCount, 1);
      expect(due.nextDueSpelling, 'station');
      expect(due.nextDueCategoryName, isNull);
    },
  );

  test(
    'empty evidence returns sample size zero without invented scores',
    () async {
      final result = await load();

      expect(result.sampleSize, 0);
      expect(result.vocabularyWordCount, 2);
      expect(result.nextDueSpelling, isNull);
      expect(result.accuracy, isNull);
      expect(result.streakDays, 0);
      expect(result.weaknesses, isEmpty);
      expect(result.recommendations, isEmpty);
      expect({
        for (final skill in result.skills) skill.key: skill.label,
      }, _labels);
      expect(result.skills, hasLength(4));
      for (final skill in result.skills) {
        expect(skill.sampleSize, 0);
        expect(skill.accuracy, isNull);
      }
    },
  );

  test('home preview excludes other owners and deleted due words', () async {
    await startSession();
    await record('meaningChoice', false);
    await database.customStatement(
      'UPDATE srs_states SET due_at_utc_ms = 1 WHERE word_id = ?',
      ['word-1'],
    );
    final due = await load();
    expect(due.dueReviewCount, 1);
    expect(due.nextDueSpelling, 'station');
    expect(due.nextDueCategoryName, 'Travel');
    expect((await load('another-owner')).vocabularyWordCount, 0);
    expect((await load('another-owner')).nextDueSpelling, isNull);

    await database.customStatement(
      'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ?',
      ['word-1'],
    );
    final deleted = await load();
    expect(deleted.vocabularyWordCount, 1);
    expect(deleted.dueReviewCount, 0);
    expect(deleted.nextDueSpelling, isNull);
  });

  test(
    'history and saved detail contain only completed owner sessions',
    () async {
      await startSession();
      await record('meaningChoice', false);
      await learning.finishSession(
        ownerId: 'owner-1',
        sessionId: 'session-owner-1',
        endedAtUtc: DateTime.utc(2026, 7, 30, 11),
      );
      await learning.startSession(
        LearningSessionDraft(
          id: 'pending-owner-1',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 12),
          appVersion: 'test',
          buildId: 'test',
        ),
      );
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 1),
          );
      await startSession('owner-2');
      await learning.finishSession(
        ownerId: 'owner-2',
        sessionId: 'session-owner-2',
        endedAtUtc: DateTime.utc(2026, 7, 30, 11, 30),
      );

      final snapshot = await load();
      expect(snapshot.recentSessions, hasLength(1));
      expect(snapshot.recentSessions.single.summary.id, 'session-owner-1');
      final before = await _databaseSnapshot(database);
      final detail = await progress.loadSession(
        ownerId: 'owner-1',
        sessionId: 'session-owner-1',
      );
      expect(detail!.summary.correctCount, 0);
      expect(detail.summary.wrongCount, 1);
      expect(detail.summary.score, 0);
      expect(detail.mistakes.single.id, 'word-1');
      expect(
        await progress.loadSession(
          ownerId: 'owner-1',
          sessionId: 'session-owner-2',
        ),
        isNull,
      );
      expect(
        await progress.loadSession(
          ownerId: 'owner-1',
          sessionId: 'pending-owner-1',
        ),
        isNull,
      );
      expect(await _databaseSnapshot(database), before);
    },
  );

  test(
    'history keeps the latest twenty completed sessions in stable order',
    () async {
      for (var index = 0; index < 22; index++) {
        await learning.startSession(
          LearningSessionDraft(
            id: 'history-$index',
            ownerId: 'owner-1',
            activityType: 'quiz',
            startedAtUtc: DateTime.utc(2026, 7, 30, 10, index),
            appVersion: 'test',
            buildId: 'test',
          ),
        );
        await learning.finishSession(
          ownerId: 'owner-1',
          sessionId: 'history-$index',
          endedAtUtc: DateTime.utc(2026, 7, 30, 11, index),
        );
      }
      final snapshot = await load();
      expect(snapshot.recentSessions, hasLength(20));
      expect(snapshot.recentSessions.first.summary.id, 'history-21');
      expect(snapshot.recentSessions.last.summary.id, 'history-2');
    },
  );

  test('mixed attempts derive accuracy points weakness and streak', () async {
    await learning.startSession(
      LearningSessionDraft(
        id: 'session-1',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 29, 10),
        appVersion: 'test',
        buildId: 'test',
      ),
    );
    await learning.recordAnswer(
      RecordAnswerCommand(
        id: 'attempt-1',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 500,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 29, 10),
      ),
    );
    await learning.recordAnswer(
      RecordAnswerCommand(
        id: 'attempt-2',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-2',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 2,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10),
      ),
    );
    await learning.finishSession(
      ownerId: 'owner-1',
      sessionId: 'session-1',
      endedAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
    );

    final result = await progress.load(
      ownerId: 'owner-1',
      nowUtc: DateTime.utc(2026, 7, 30, 12),
    );

    expect(result.sampleSize, 2);
    expect(result.accuracy, 0.5);
    expect(result.totalXp, 1);
    expect(result.completedSessions, 1);
    expect(result.streakDays, 2);
    expect(result.weaknesses.single.wordId, 'word-1');
    expect(result.weaknesses.single.incorrectCount, 1);
    expect(result.recommendations.single.sampleSize, 1);
  });

  for (final (mode, key) in const [
    ('ghostSpelling', 'spelling'),
    ('associativeRecall', 'retention'),
    ('pronunciationTranscript', 'pronunciation'),
  ]) {
    test('$mode contributes only to $key using persisted attempts', () async {
      await startSession();
      await record(mode, true);
      await record(mode, false);

      final result = await load();

      expect(result.sampleSize, 2);
      expect(result.correctCount, 1);
      expect(result.wrongCount, 1);
      expect(result.accuracy, 0.5);
      expect(result.skills.map((skill) => skill.key), _labels.keys);
      for (final skill in result.skills) {
        expect(skill.sampleSize, skill.key == key ? 2 : 0);
        expect(skill.accuracy, skill.key == key ? 0.5 : isNull);
      }
    });
  }

  test(
    'mixed modes weight attempts and retain deliberate dictation overlap',
    () async {
      await startSession();
      for (final (mode, correct) in const [
        ('listening', true),
        ('dictation', false),
        ('dictation', true),
        ('pronunciation', false),
        ('shadowing', true),
        ('pronunciationTranscript', true),
        ('pronunciationTranscript', true),
        ('pronunciationTranscript', false),
        ('spelling', false),
        ('ghostSpelling', true),
        ('ghostSpelling', false),
        ('ghostSpelling', true),
        ('meaningChoice', true),
        ('srsRecall', false),
        ('activeRecall', false),
        ('associativeRecall', true),
        ('associativeRecall', true),
        ('associativeRecall', false),
      ]) {
        await record(mode, correct);
      }

      final result = await load();

      expect(result.sampleSize, 18);
      expect(result.correctCount, 10);
      expect(result.wrongCount, 8);
      expect(result.accuracy, 10 / 18);
      expect(result.totalXp, 10);
      expect(
        result.skills.map(
          (skill) => (skill.key, skill.sampleSize, skill.accuracy),
        ),
        [
          ('listening', 3, 2 / 3),
          ('pronunciation', 5, 3 / 5),
          ('spelling', 6, 3 / 6),
          ('retention', 6, 3 / 6),
        ],
      );
      expect(result.skills.fold(0, (sum, skill) => sum + skill.sampleSize), 20);
    },
  );

  test(
    'unknown and similar future modes stay ungrouped but count overall',
    () async {
      await startSession();
      for (final (mode, correct) in const [
        ('futureMode', true),
        ('ghostSpellingFuture', false),
        ('associativeRecallFuture', true),
        ('pronunciationTranscriptFuture', false),
      ]) {
        await record(mode, correct);
      }

      final result = await load();

      expect(result.sampleSize, 4);
      expect(result.accuracy, 0.5);
      for (final skill in result.skills) {
        expect(skill.sampleSize, 0);
        expect(skill.accuracy, isNull);
      }
    },
  );

  test('stable persisted attempt replay is counted once', () async {
    await startSession();
    final command = await record('ghostSpelling', true);
    final replay = await learning.recordAnswer(command);
    expect(replay.inserted, isFalse);

    final result = await load();

    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    expect(result.sampleSize, 1);
    expect(result.totalXp, 1);
    final spelling = result.skills.singleWhere(
      (skill) => skill.key == 'spelling',
    );
    expect(spelling.sampleSize, 1);
    expect(spelling.accuracy, 1);
  });

  test('new and legacy mode aggregates remain isolated per owner', () async {
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-2',
            ownerId: 'owner-2',
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
            id: 'word-3',
            ownerId: 'owner-2',
            categoryId: 'category-2',
            spelling: 'synthetic',
            normalizedSpelling: 'synthetic',
            meaning: 'สังเคราะห์',
            normalizedMeaning: 'สังเคราะห์',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await startSession();
    await startSession('owner-2');
    for (final mode in [
      'ghostSpelling',
      'associativeRecall',
      'pronunciationTranscript',
    ]) {
      await record(mode, true);
      await record(mode, false);
    }
    for (final (mode, correct) in const [
      ('ghostSpelling', true),
      ('ghostSpelling', true),
      ('ghostSpelling', true),
      ('associativeRecall', false),
      ('pronunciationTranscript', false),
      ('dictation', true),
    ]) {
      await record(mode, correct, ownerId: 'owner-2', wordId: 'word-3');
    }

    final ownerA = await load();
    final ownerB = await load('owner-2');
    final absentOwner = await load('absent-owner');

    expect(ownerA.sampleSize, 6);
    expect(ownerA.accuracy, 0.5);
    expect(ownerA.skills.map((s) => (s.key, s.sampleSize, s.accuracy)), [
      ('listening', 0, null),
      ('pronunciation', 2, 0.5),
      ('spelling', 2, 0.5),
      ('retention', 2, 0.5),
    ]);
    expect(ownerB.sampleSize, 6);
    expect(ownerB.accuracy, 4 / 6);
    expect(ownerB.skills.map((s) => (s.key, s.sampleSize, s.accuracy)), [
      ('listening', 1, 1.0),
      ('pronunciation', 1, 0.0),
      ('spelling', 4, 1.0),
      ('retention', 1, 0.0),
    ]);
    expect(absentOwner.sampleSize, 0);
    expect(absentOwner.accuracy, isNull);
    for (final skill in absentOwner.skills) {
      expect(skill.sampleSize, 0);
      expect(skill.accuracy, isNull);
    }
  });
}

const _labels = {
  'listening': 'การฟัง',
  'pronunciation': 'การพูด (ความตรงของข้อความ)',
  'spelling': 'การสะกดคำ',
  'retention': 'การจำและเรียกคืน',
};

Future<Map<String, List<String>>> _databaseSnapshot(
  AppDatabase database,
) async => {
  for (final table in database.allTables)
    table.actualTableName:
        (await database
                .customSelect('SELECT * FROM "${table.actualTableName}"')
                .get())
            .map((row) => jsonEncode(row.data))
            .toList()
          ..sort(),
};
