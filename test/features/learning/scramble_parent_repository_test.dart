import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/cloze_prompt_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/quiz_round.dart';
import 'package:vocab_learning_app/features/learning/domain/scramble_prompt_policy.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';

final _at = DateTime.utc(2026, 11, 15, 9);
const _ownerId = 'scramble-owner';
const _categoryId = 'scramble-travel';
const _platform = QuizWord(
  id: 'platform',
  categoryId: _categoryId,
  spelling: 'platform',
  meaning: 'ชานชาลา',
  partOfSpeech: 'noun',
);
const _ticket = QuizWord(
  id: 'ticket',
  categoryId: _categoryId,
  spelling: 'ticket',
  meaning: 'ตั๋ว',
  partOfSpeech: 'noun',
);

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'sentence requires current correct cloze feedback before opening',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seed(database);
      final repository = DriftLearningRepository(database);
      final clozeQuestion = ClozePromptPolicy.build(
        words: [_platform, _ticket],
        kind: QuizPromptKind.clozeChoice,
      ).single;
      final parent = await _open(repository, 'parent', clozeQuestion);
      final sentence = ScramblePromptPolicy.first([
        _platform,
      ], QuizPromptKind.sentenceScramble)!;

      Future<QuizRound> openChild(String id) =>
          _open(repository, id, sentence, parentId: parent.sessionId);
      await expectLater(openChild('too-early'), throwsStateError);
      final wrong = await _answer(
        repository,
        parent,
        const QuizChoiceResponse(slot: 0, selectedOption: 1),
      );
      await expectLater(openChild('wrong-parent-answer'), throwsStateError);
      final retry = await _advance(repository, wrong, QuizStep.retryQuestion);
      final correct = await _answer(
        repository,
        retry,
        const QuizChoiceResponse(slot: 0, selectedOption: 0),
      );
      final child = await openChild('first-child');
      expect(child.plan.origin.parentId, parent.sessionId);
      expect(child.plan.questions.single.word.id, _platform.id);
      expect((await openChild('duplicate-child')).sessionId, child.sessionId);
      await _advance(repository, correct, QuizStep.retryQuestion);

      await expectLater(openChild('stale-parent-reopen'), throwsStateError);
      final sessions = await database.select(database.learningSessions).get();
      expect(sessions.map((row) => row.id).toSet(), {
        parent.sessionId,
        child.sessionId,
      });
    },
  );

  test(
    'file reopen reads the same repeated-t spelling answer and score',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-scramble-',
      );
      final file = File('${directory.path}/round.sqlite');
      addTearDown(() async {
        for (final suffix in ['', '-wal', '-shm', '-journal']) {
          final artifact = File('${file.path}$suffix');
          if (await artifact.exists()) await artifact.delete();
        }
        await directory.delete();
      });
      final question = ScramblePromptPolicy.first([
        _ticket,
      ], QuizPromptKind.wordScramble)!;
      final unused = question.scrambleTokens.indexed
          .map((entry) => entry.$1)
          .toList();
      final order = [
        for (final letter in 'ticket'.split(''))
          unused.removeAt(
            unused.indexWhere(
              (index) => question.scrambleTokens[index] == letter,
            ),
          ),
      ];
      final response = QuizOrderResponse(slot: 0, indexes: order);
      final writer = AppDatabase(NativeDatabase(file));
      try {
        await _seed(writer);
        final repository = DriftLearningRepository(writer);
        final round = await _open(repository, 'spelling', question);
        final answered = await _answer(repository, round, response);
        expect(
          (await _advance(
            repository,
            answered,
            QuizStep.finish,
          )).summary?.score,
          100,
        );
      } finally {
        await writer.close();
      }

      final reader = AppDatabase(NativeDatabase(file));
      addTearDown(reader.close);
      final round = await DriftLearningRepository(
        reader,
      ).loadQuizRound(ownerId: _ownerId, sessionId: 'spelling');
      expect(round?.cursor.phase, QuizPhase.finished);
      expect(round?.feedback, response);
      expect(
        round?.plan.questions.single.scrambleTokens,
        question.scrambleTokens,
      );
      final history = await DriftProgressQueries(
        reader,
      ).loadSession(ownerId: _ownerId, sessionId: 'spelling');
      expect(history?.summary.score, 100);
      expect(history?.originalAnswers?.single.chosenAnswer, 'ticket');
      expect(history?.originalAnswers?.single.isCorrect, isTrue);
    },
  );
}

Future<QuizRound> _open(
  DriftLearningRepository repo,
  String id,
  QuizQuestion question, {
  String? parentId,
}) => repo.openOrStartAuthoredRound(
  LearningSessionDraft(
    id: id,
    ownerId: _ownerId,
    activityType: question.kind.isCloze ? 'cloze' : question.kind.name,
    startedAtUtc: _at,
    appVersion: 'synthetic',
    buildId: 'synthetic',
    quizPlan: QuizPlan(
      origin: QuizOrigin(
        route: question.kind.isCloze ? 'cloze' : 'word-games',
        promptKind: question.kind,
        categoryId: question.word.categoryId,
        wordIds: parentId == null ? null : [question.word.id],
        parentId: parentId,
      ),
      questions: [question],
    ),
  ),
  skipUnavailable: false,
);

Future<QuizRound> _answer(
  DriftLearningRepository repo,
  QuizRound round,
  QuizResponse response,
) async {
  final question = round.plan.questions.single;
  final ordinal = round.committedAnswers + 1;
  final written = await repo.recordAnswer(
    RecordAnswerCommand(
      id: '${round.sessionId}-answer-$ordinal',
      ownerId: _ownerId,
      sessionId: round.sessionId,
      wordId: question.word.id,
      promptMode: question.kind.name,
      isCorrect: response.isCorrectFor(question),
      responseTimeMs: 500,
      attemptNumber: ordinal,
      occurredAtUtc: _at.add(Duration(seconds: ordinal)),
      quiz: (expectedRevision: round.cursor.revision, response: response),
    ),
  );
  expect(written.inserted, isTrue);
  return written.durableRound!;
}

Future<QuizRound> _advance(
  DriftLearningRepository repo,
  QuizRound round,
  QuizStep step,
) => repo.advanceQuizRound(
  ownerId: _ownerId,
  sessionId: round.sessionId,
  expectedRevision: round.cursor.revision,
  step: step,
  atUtc: _at.add(const Duration(seconds: 10)),
);

Future<void> _seed(AppDatabase database) async {
  await database.customStatement(
    'INSERT INTO local_owners (id,created_at_utc_ms,is_active) VALUES (?,1,1)',
    [_ownerId],
  );
  await database.customStatement(
    'INSERT INTO vocabulary_categories '
    '(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) '
    "VALUES (?,?,'Travel','travel',1,1)",
    [_categoryId, _ownerId],
  );
  for (final word in [_platform, _ticket]) {
    await database.customStatement(
      'INSERT INTO vocabulary_words '
      '(id,owner_id,category_id,spelling,normalized_spelling,meaning,'
      'normalized_meaning,part_of_speech,local_revision,created_at_utc_ms,'
      'updated_at_utc_ms) VALUES (?,?,?,?,?,?,?,?,1,1,1)',
      [
        word.id,
        _ownerId,
        _categoryId,
        word.spelling,
        word.spelling,
        word.meaning,
        word.meaning,
        word.partOfSpeech,
      ],
    );
  }
}
