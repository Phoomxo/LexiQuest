import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/quiz_round.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

final _at = DateTime.utc(2026, 11, 14, 10);

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'file round resumes question two with original elapsed and history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-quiz-round-',
      );
      final originalPath = await directory.resolveSymbolicLinks();
      final file = File('${directory.path}/round.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      try {
        await _seed(database);
        var repository = DriftLearningRepository(database);
        await repository.startSession(_draft());
        var round = (await _load(repository))!;
        expect(round.cursor.slot, 0);
        expect(round.cursor.phase, QuizPhase.awaitingAnswer);
        expect(round.cursor.revision, 0);
        await repository.recordAnswer(
          _answer('answer-1', slot: 0, revision: 0),
        );
        round = (await _load(repository))!;
        expect(round.cursor.phase, QuizPhase.feedback);
        expect(round.feedback, (slot: 0, selectedOption: 0));
        round = await _advance(repository, round, QuizStep.next);
        expect(round.cursor.slot, 1);
        round = await _advance(
          repository,
          round,
          QuizStep.pause,
          elapsed: 1234,
        );
        expect(round.isPaused, isTrue);
        expect(round.cursor.activeResponseMs, 1234);
        final paused = await _snapshot(database);
        await database.close();

        database = AppDatabase(NativeDatabase(file));
        repository = DriftLearningRepository(database);
        round = (await repository.findOpenQuizRound(
          ownerId: 'owner-a',
          origin: _plan().origin,
        ))!;
        expect(round.sessionId, 'round-1');
        expect(round.isPaused, isTrue);
        expect(round.cursor.slot, 1);
        expect(round.cursor.activeResponseMs, 1234);
        expect(round.plan.questions[1].word.spelling, 'ticket');
        expect(round.plan.questions[1].options, ['สถานี', 'ตั๋ว']);
        expect(await _snapshot(database), paused);

        round = await repository.advanceQuizRound(
          ownerId: 'owner-a',
          sessionId: 'round-1',
          expectedRevision: round.cursor.revision,
          step: QuizStep.resume,
          atUtc: _at.add(const Duration(days: 3)),
        );
        expect(round.cursor.slot, 1);
        expect(round.cursor.activeResponseMs, 1234);
        expect(round.isPaused, isFalse);
        await repository.recordAnswer(
          _answer(
            'answer-2',
            slot: 1,
            revision: round.cursor.revision,
            ordinal: 2,
            responseMs: 1500,
            occurredAt: _at.add(const Duration(days: 3, seconds: 2)),
          ),
        );
        round = (await _load(repository))!;
        expect(round.feedback, (slot: 1, selectedOption: 0));
        round = await _advance(repository, round, QuizStep.finish);
        expect(round.cursor.phase, QuizPhase.finished);
        expect(round.summary!.correctCount, 1);
        expect(round.summary!.wrongCount, 1);
        expect(round.summary!.score, 50);
        expect(round.mistakes.map((word) => word.id), ['word-2']);
        expect(
          await repository.findOpenQuizRound(
            ownerId: 'owner-a',
            origin: _plan().origin,
          ),
          isNull,
        );
        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(2));
        final wrong = attempts.singleWhere((row) => row.id == 'answer-2');
        expect(wrong.responseTimeMs, 1500);
        expect(
          decodeQuizResponse(wrong.answerEvidenceJson!, plan: round.plan),
          (slot: 1, selectedOption: 0),
        );
        final completed = await _snapshot(database);
        await _load(repository);
        await repository.finishSession(
          ownerId: 'owner-a',
          sessionId: 'round-1',
          endedAtUtc: _at.add(const Duration(days: 5)),
        );
        expect(await _snapshot(database), completed);

        await database.customStatement(
          "UPDATE vocabulary_words SET spelling='edited ticket', meaning='changed', local_revision=2, is_deleted=1 WHERE id='word-2'",
        );
        await database.customStatement(
          "UPDATE vocabulary_categories SET name='Renamed' WHERE id='category-a'",
        );
        await database.close();
        database = AppDatabase(NativeDatabase(file));
        repository = DriftLearningRepository(database);
        final edited = await _snapshot(database);
        round = (await _load(repository))!;
        expect(round.plan.categoryName, 'Travel');
        expect(round.plan.questions[1].word.spelling, 'ticket');
        expect(round.plan.questions[1].word.meaning, 'ตั๋ว');
        expect(round.plan.questions[1].word.localRevision, 1);
        expect(round.feedback, (slot: 1, selectedOption: 0));
        expect(
          round.plan.questions[1].options[round.feedback!.selectedOption!],
          'สถานี',
        );
        expect(round.summary!.score, 50);
        expect(await _snapshot(database), edited);
      } finally {
        await database.close();
        final resolved = Directory(await directory.resolveSymbolicLinks());
        expect(resolved.path, originalPath);
        expect(
          resolved.parent.path,
          await Directory.systemTemp.resolveSymbolicLinks(),
        );
        expect(
          resolved.uri.pathSegments.where((part) => part.isNotEmpty).last,
          startsWith('lexiquest-quiz-round-'),
        );
        await resolved.delete(recursive: true);
      }
    },
  );

  test(
    'lost answer acknowledgement cannot repeat a cursor transition or deliberate retry',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seed(database);
        final repository = DriftLearningRepository(database);
        await repository.startSession(_draft());
        final first = _answer('wrong-1', slot: 0, revision: 0, selected: 1);
        expect((await repository.recordAnswer(first)).inserted, isTrue);
        var round = (await _load(repository))!;
        expect(round.cursor.slot, 0);
        expect(round.feedback, (slot: 0, selectedOption: 1));
        final feedback = await _snapshot(database);
        expect((await repository.recordAnswer(first)).inserted, isFalse);
        expect(await _snapshot(database), feedback);
        round = await _advance(repository, round, QuizStep.retryQuestion);
        expect(round.cursor.slot, 0);
        expect(round.cursor.phase, QuizPhase.awaitingAnswer);
        expect(round.cursor.lastAttemptId, isNull);
        expect(round.cursor.activeResponseMs, 0);
        await repository.recordAnswer(
          _answer(
            'intentional-2',
            slot: 0,
            revision: round.cursor.revision,
            ordinal: 2,
            occurredAt: _at.add(const Duration(seconds: 30)),
          ),
        );
        round = await _advance(
          repository,
          (await _load(repository))!,
          QuizStep.next,
        );
        expect(round.cursor.slot, 1);
        expect(round.committedAnswers, 2);
        final advanced = await _snapshot(database);
        expect((await repository.recordAnswer(first)).inserted, isFalse);
        expect(await _snapshot(database), advanced);
        await expectLater(
          repository.recordAnswer(_answer('wrong-1', slot: 0, revision: 0)),
          throwsStateError,
        );
        expect(await _snapshot(database), advanced);
        final answers = await database.select(database.answerAttempts).get();
        expect(answers.map((row) => row.id).toSet(), {
          'wrong-1',
          'intentional-2',
        });
        expect(answers.map((row) => row.attemptNumber).toSet(), {1, 2});
        expect(answers.every((row) => row.wordId == 'word-1'), isTrue);
        for (final answer in answers) {
          expect(
            decodeQuizResponse(
              answer.answerEvidenceJson!,
              plan: round.plan,
            ).slot,
            0,
          );
        }
      } finally {
        await database.close();
      }
    },
  );

  test(
    'edited vocabulary keeps the paused round and permits an explicit new Quiz',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seed(database);
      final repository = DriftLearningRepository(database);
      final origin = _plan().origin;
      await repository.startSession(_draft());
      final first = await repository.recordAnswer(
        _answer('saved-before-edit', slot: 0, revision: 0),
      );
      final next = await _advance(
        repository,
        first.durableRound!,
        QuizStep.next,
      );
      final paused = await _advance(
        repository,
        next,
        QuizStep.pause,
        elapsed: 1200,
      );
      final edited =
          await (database.update(
            database.vocabularyWords,
          )..where((row) => row.id.equals('word-2'))).write(
            const VocabularyWordsCompanion(
              spelling: Value('train ticket'),
              normalizedSpelling: Value('train ticket'),
              meaning: Value('ตั๋วรถไฟ'),
              normalizedMeaning: Value('ตั๋วรถไฟ'),
              localRevision: Value(2),
            ),
          );
      expect(edited, 1);
      final before = await _snapshot(database);

      await expectLater(
        repository.findOpenQuizRound(ownerId: 'owner-a', origin: origin),
        throwsA(isA<QuizVocabularyChanged>()),
      );
      expect(
        await repository.findOpenQuizRound(
          ownerId: 'owner-a',
          origin: origin,
          skipUnavailable: true,
        ),
        isNull,
      );
      expect(await _snapshot(database), before);

      final learning = LearningUseCases(
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => throw StateError('Expected the existing owner'),
          nowUtc: () => _at,
        ),
        repository: repository,
        generateId: () => 'new-after-edit',
        nowUtc: () => _at.add(const Duration(minutes: 1)),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      final fresh = await learning.startQuiz(
        categoryId: 'category-a',
        expectedOwnerId: 'owner-a',
        origin: origin,
        skipUnavailable: true,
      );
      expect(fresh.id, 'session:new-after-edit');
      expect(fresh.durableRound!.cursor, initialQuizCursor);
      expect(fresh.durableRound!.committedAnswers, 0);
      expect(fresh.questions[1].word.spelling, 'train ticket');
      expect(fresh.questions[1].word.meaning, 'ตั๋วรถไฟ');
      expect(fresh.questions[1].word.localRevision, 2);
      expect((await _load(repository))!.cursor, paused.cursor);
      final after = await _snapshot(database);
      expect(after['learning_sessions'], hasLength(2));
      expect(
        after['learning_sessions']!.where(
          (row) => row['id'] == paused.sessionId,
        ),
        before['learning_sessions'],
      );
      expect(after['answer_attempts'], before['answer_attempts']);
      expect(after['outbox_operations'], before['outbox_operations']);
    },
  );

  test(
    'stale cursor and foreign or inactive owner cannot mutate a planned round',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seed(database);
        final repository = DriftLearningRepository(database);
        await repository.startSession(_draft());
        var round = (await _load(repository))!;
        round = await _advance(repository, round, QuizStep.pause, elapsed: 400);
        var before = await _snapshot(database);
        await expectLater(
          repository.advanceQuizRound(
            ownerId: 'owner-a',
            sessionId: 'round-1',
            expectedRevision: 0,
            step: QuizStep.resume,
            atUtc: _at,
          ),
          throwsStateError,
        );
        await expectLater(
          repository.recordAnswer(
            _answer('paused-answer', slot: 0, revision: round.cursor.revision),
          ),
          throwsStateError,
        );
        await expectLater(
          repository.finishSession(
            ownerId: 'owner-a',
            sessionId: 'round-1',
            endedAtUtc: _at,
          ),
          throwsStateError,
        );
        expect(await _snapshot(database), before);
        await database.customStatement(
          "UPDATE local_owners SET is_active=0 WHERE id='owner-a'",
        );
        await database.customStatement(
          "INSERT INTO local_owners (id,created_at_utc_ms,is_active) VALUES ('owner-b',1,1)",
        );
        before = await _snapshot(database);
        expect(
          await repository.loadQuizRound(
            ownerId: 'owner-b',
            sessionId: 'round-1',
          ),
          isNull,
        );
        expect(
          await repository.findOpenQuizRound(
            ownerId: 'owner-b',
            origin: _plan().origin,
          ),
          isNull,
        );
        for (final owner in ['owner-a', 'owner-b']) {
          await expectLater(
            repository.advanceQuizRound(
              ownerId: owner,
              sessionId: 'round-1',
              expectedRevision: round.cursor.revision,
              step: QuizStep.resume,
              atUtc: _at,
            ),
            throwsStateError,
          );
        }
        await expectLater(
          repository.recordAnswer(
            _answer(
              'inactive-answer',
              slot: 0,
              revision: round.cursor.revision,
            ),
          ),
          throwsStateError,
        );
        expect(await _snapshot(database), before);
      } finally {
        await database.close();
      }
    },
  );
}

QuizPlan _plan() => QuizPlan(
  origin: QuizOrigin(
    route: 'category',
    promptKind: QuizPromptKind.meaningChoice,
    categoryId: 'category-a',
  ),
  categoryName: 'Travel',
  returnLabel: 'Travel',
  questions: const [
    QuizQuestion(
      word: QuizWord(
        id: 'word-1',
        categoryId: 'category-a',
        spelling: 'station',
        meaning: 'สถานี',
        partOfSpeech: 'noun',
        localRevision: 1,
      ),
      options: ['สถานี', 'ตั๋ว'],
    ),
    QuizQuestion(
      word: QuizWord(
        id: 'word-2',
        categoryId: 'category-a',
        spelling: 'ticket',
        meaning: 'ตั๋ว',
        partOfSpeech: 'noun',
        localRevision: 1,
      ),
      options: ['สถานี', 'ตั๋ว'],
    ),
  ],
);

LearningSessionDraft _draft() => LearningSessionDraft(
  id: 'round-1',
  ownerId: 'owner-a',
  activityType: 'quiz',
  startedAtUtc: _at,
  appVersion: 'test',
  buildId: 'test',
  quizPlan: _plan(),
);

RecordAnswerCommand _answer(
  String id, {
  required int slot,
  required int revision,
  int selected = 0,
  int ordinal = 1,
  int responseMs = 500,
  DateTime? occurredAt,
}) => RecordAnswerCommand(
  id: id,
  ownerId: 'owner-a',
  sessionId: 'round-1',
  wordId: 'word-${slot + 1}',
  promptMode: 'meaningChoice',
  isCorrect: selected == slot,
  responseTimeMs: responseMs,
  attemptNumber: ordinal,
  occurredAtUtc: occurredAt ?? _at.add(Duration(seconds: ordinal)),
  quiz: (
    expectedRevision: revision,
    response: (slot: slot, selectedOption: selected),
  ),
);

Future<QuizRound?> _load(DriftLearningRepository repository) =>
    repository.loadQuizRound(ownerId: 'owner-a', sessionId: 'round-1');

Future<QuizRound> _advance(
  DriftLearningRepository repository,
  QuizRound round,
  QuizStep step, {
  int elapsed = 0,
}) => repository.advanceQuizRound(
  ownerId: 'owner-a',
  sessionId: 'round-1',
  expectedRevision: round.cursor.revision,
  step: step,
  atUtc: _at.add(
    step == QuizStep.finish
        ? const Duration(days: 4)
        : Duration(seconds: 10 * (round.cursor.revision + 1)),
  ),
  activeResponseMs: elapsed,
);

Future<void> _seed(AppDatabase database) async {
  await database.customStatement(
    "INSERT INTO local_owners (id,created_at_utc_ms,is_active) VALUES ('owner-a',1,1)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('category-a','owner-a','Travel','travel',1,1)",
  );
  for (final (id, spelling, meaning) in [
    ('word-1', 'station', 'สถานี'),
    ('word-2', 'ticket', 'ตั๋ว'),
  ]) {
    await database.customStatement(
      'INSERT INTO vocabulary_words (id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,local_revision,created_at_utc_ms,updated_at_utc_ms) '
      "VALUES (?,'owner-a','category-a',?,?,?,?,'noun',1,1,1)",
      [id, spelling, spelling, meaning, meaning],
    );
  }
}

Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase database,
) async => {
  for (final table in database.allTables)
    table.actualTableName:
        (await database
                .customSelect(
                  'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                )
                .get())
            .map((row) => row.data)
            .toList(),
};
