import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
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
    if (mode == 'srsRecall') {
      // This mixed-session fixture represents historical rows, not a live SRS entry.
      await database.customStatement(
        'INSERT INTO answer_attempts '
        '(id,owner_id,session_id,word_id,prompt_mode,is_correct,response_time_ms,attempt_number,occurred_at_utc_ms,provider_provenance,evidence_class,evidence_context_json) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          command.id,
          command.ownerId,
          command.sessionId,
          command.wordId,
          command.promptMode,
          command.isCorrect ? 1 : 0,
          command.responseTimeMs,
          command.attemptNumber,
          command.occurredAtUtc.millisecondsSinceEpoch,
          command.providerProvenance,
          command.evidenceContext.evidenceClass.name,
          jsonEncode(command.evidenceContext.toJson()),
        ],
      );
      await learning.projections.rebuildWord(ownerId: ownerId, wordId: wordId);
      await learning.projections.rebuildSession(
        ownerId: ownerId,
        sessionId: command.sessionId,
      );
      await learning.projections.rebuildAchievements(ownerId);
    } else {
      await learning.recordAnswer(command);
    }
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

  test(
    'empty evidence returns sample size zero without invented scores',
    () async {
      final result = await load();

      expect(result.sampleSize, 0);
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
