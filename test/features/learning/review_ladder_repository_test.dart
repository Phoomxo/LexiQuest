import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/quiz_round.dart';
import 'package:vocab_learning_app/features/learning/domain/review_ladder.dart';

final _reviewedAt = DateTime.utc(2026, 11, 15, 9);
final _exerciseAt = DateTime.utc(2026, 11, 15, 10);

void main() {
  test('reopens the independent miss, guided retry and typed result', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-review-ladder-',
    );
    final file = File('${directory.path}/review.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    try {
      await _seed(db);
      var repository = DriftLearningRepository(db);
      await _reviewStation(repository);
      final pair = (await repository.findReviewLadderPair(ownerId: 'owner-a'))!;
      expect((pair.target.id, pair.contrast.id), ('station-a', 'platform-a'));
      expect(pair.reviewAttemptId, 'attempt:review-a:0');
      var round = await repository.openReviewLadderRound(
        session: _session('ladder-a', 'reviewLadder', _exerciseAt),
        pair: pair,
      );
      expect(round.phase, ReviewLadderPhase.intro);
      expect(
        (await repository.openReviewLadderRound(
          session: _session('unused', 'reviewLadder', _exerciseAt),
          pair: pair,
        )).sessionId,
        'ladder-a',
      );

      Future<ReviewLadderRound> advance(
        ReviewLadderAction action, {
        int? option,
        String? typed,
        ReviewLadderRound? expected,
      }) => repository.changeReviewLadderRound(
        ownerId: 'owner-a',
        expected: expected ?? round,
        action: action,
        atUtc: _exerciseAt,
        option: option,
        text: typed,
      );

      round = await advance(ReviewLadderAction.startMeaning);
      final beforeCheck = round;
      round = await advance(ReviewLadderAction.checkMeaning, option: 0);
      expect(round.phase, ReviewLadderPhase.compare);
      expect(
        (await advance(
          ReviewLadderAction.checkMeaning,
          option: 0,
          expected: beforeCheck,
        )).revision,
        round.revision,
      );
      await expectLater(
        advance(
          ReviewLadderAction.checkMeaning,
          option: 1,
          expected: beforeCheck,
        ),
        throwsStateError,
      );
      await expectLater(
        repository.recordAnswer(_ladderAnswer()),
        throwsStateError,
      );
      round = await advance(ReviewLadderAction.retryMeaning);
      round = await advance(ReviewLadderAction.checkMeaning, option: 1);
      round = await advance(ReviewLadderAction.startTyping);
      expect(round.phase, ReviewLadderPhase.typed);
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      repository = DriftLearningRepository(db);
      expect(
        await repository.readLatestReviewLadder(ownerId: 'owner-a'),
        isNull,
      );
      final draft = await repository.openReviewLadderRound(
        session: _session('resume', 'reviewLadder', _exerciseAt),
        pair: pair,
      );
      expect(
        (draft.sessionId, draft.phase),
        ('ladder-a', ReviewLadderPhase.typed),
      );
      expect(draft.independentChoice?.option, 0);
      round = draft;
      round = await advance(ReviewLadderAction.checkTyped, typed: 'station');
      expect(round.phase, ReviewLadderPhase.result);
      await expectLater(
        repository.finishReviewLadderRound(
          ownerId: 'owner-a',
          expected: round,
          endedAtUtc: _exerciseAt,
        ),
        throwsStateError,
      );
      await expectLater(
        repository.recordAnswer(_ladderAnswer(correct: true)),
        throwsStateError,
      );
      expect((await repository.recordAnswer(_ladderAnswer())).inserted, isTrue);
      expect(
        (await repository.recordAnswer(_ladderAnswer())).inserted,
        isFalse,
      );
      final result = await repository.finishReviewLadderRound(
        ownerId: 'owner-a',
        expected: round,
        endedAtUtc: _exerciseAt,
      );
      expect(
        (result.id, result.correctCount, result.wrongCount, result.score),
        ('ladder-a', 0, 1, 0),
      );
      expect(
        (await repository.recordAnswer(_ladderAnswer())).inserted,
        isFalse,
      );
      final replay = await repository.finishReviewLadderRound(
        ownerId: 'owner-a',
        expected: round,
        endedAtUtc: _exerciseAt.add(const Duration(minutes: 1)),
      );
      expect((replay.id, replay.score), ('ladder-a', 0));
      final saved = await repository.readLatestReviewLadder(ownerId: 'owner-a');
      expect(encodeReviewLadderRound(saved!), encodeReviewLadderRound(round));
      expect(
        (await db.select(db.answerAttempts).get()).map((row) => row.id),
        unorderedEquals(['attempt:review-a:0', 'attempt:ladder-a:review:0']),
      );
      expect(
        await repository.loadQuizRound(
          ownerId: 'owner-a',
          sessionId: 'ladder-a',
        ),
        isNull,
      );
    } finally {
      await db.close();
      if (await file.exists()) await file.delete();
      await directory.delete();
    }
  });

  test(
    'selection needs the active owner and an unchanged reviewed pair',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);
      final repository = DriftLearningRepository(db);
      expect(await repository.findReviewLadderPair(ownerId: 'owner-a'), isNull);
      await _reviewStation(repository);
      final pair = (await repository.findReviewLadderPair(ownerId: 'owner-a'))!;
      final round = await repository.openReviewLadderRound(
        session: _session('ladder-a', 'reviewLadder', _exerciseAt),
        pair: pair,
      );
      await (db.update(db.vocabularyWords)
            ..where((row) => row.id.equals('platform-a')))
          .write(const VocabularyWordsCompanion(meaning: Value('edited')));
      await expectLater(
        repository.changeReviewLadderRound(
          ownerId: 'owner-a',
          expected: round,
          action: ReviewLadderAction.startMeaning,
          atUtc: _exerciseAt,
        ),
        throwsA(isA<QuizVocabularyChanged>()),
      );
      expect(
        await repository.readLatestReviewLadder(ownerId: 'owner-a'),
        isNull,
      );
      await (db.update(db.localOwners)
            ..where((row) => row.id.equals('owner-a')))
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await _seed(db, suffix: 'b');
      await expectLater(
        repository.readLatestReviewLadder(ownerId: 'owner-a'),
        throwsStateError,
      );
      expect(await repository.findReviewLadderPair(ownerId: 'owner-b'), isNull);
      expect(
        await repository.readLatestReviewLadder(ownerId: 'owner-b'),
        isNull,
      );
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
    },
  );

  test(
    'a revealed choice completes without an attempt or assessed score',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);
      final repository = DriftLearningRepository(db);
      await _reviewStation(repository);
      final pair = (await repository.findReviewLadderPair(ownerId: 'owner-a'))!;
      var round = await repository.openReviewLadderRound(
        session: _session('ladder-a', 'reviewLadder', _exerciseAt),
        pair: pair,
      );
      for (final action in [
        ReviewLadderAction.revealCard,
        ReviewLadderAction.startMeaning,
        ReviewLadderAction.checkMeaning,
        ReviewLadderAction.startTyping,
        ReviewLadderAction.checkTyped,
      ]) {
        round = await repository.changeReviewLadderRound(
          ownerId: 'owner-a',
          expected: round,
          action: action,
          atUtc: _exerciseAt,
          option: action == ReviewLadderAction.checkMeaning ? 1 : null,
          text: action == ReviewLadderAction.checkTyped ? 'station' : null,
        );
      }
      expect(round.independentChoice, isNull);
      expect(round.meaningChecks.single.assisted, isTrue);
      await expectLater(
        repository.recordAnswer(_ladderAnswer(correct: true)),
        throwsStateError,
      );
      await repository.finishReviewLadderRound(
        ownerId: 'owner-a',
        expected: round,
        endedAtUtc: _exerciseAt,
      );
      final row = await (db.select(
        db.learningSessions,
      )..where((row) => row.id.equals('ladder-a'))).getSingle();
      expect(
        (row.state, row.correctCount, row.wrongCount, row.score),
        ('completed', 0, 0, null),
      );
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
    },
  );
}

LearningSessionDraft _session(String id, String activity, DateTime startedAt) =>
    LearningSessionDraft(
      id: id,
      ownerId: 'owner-a',
      activityType: activity,
      startedAtUtc: startedAt,
      appVersion: 'test',
      buildId: 'test',
    );

RecordAnswerCommand _ladderAnswer({bool correct = false}) =>
    RecordAnswerCommand(
      id: 'attempt:ladder-a:review:0',
      ownerId: 'owner-a',
      sessionId: 'ladder-a',
      wordId: 'station-a',
      promptMode: 'meaningChoice',
      isCorrect: correct,
      responseTimeMs: null,
      attemptNumber: 1,
      occurredAtUtc: _exerciseAt,
    );

Future<void> _reviewStation(DriftLearningRepository repository) async {
  await repository.startSession(_session('review-a', 'srsReview', _reviewedAt));
  await repository.recordAnswer(
    RecordAnswerCommand(
      id: 'attempt:review-a:0',
      ownerId: 'owner-a',
      sessionId: 'review-a',
      wordId: 'station-a',
      promptMode: 'srsRecall',
      isCorrect: true,
      responseTimeMs: null,
      attemptNumber: 1,
      occurredAtUtc: _reviewedAt,
      srsRecallSnapshot: (
        spelling: 'station',
        meaning: 'สถานี',
        partOfSpeech: 'noun',
      ),
    ),
  );
  await repository.finishSession(
    ownerId: 'owner-a',
    sessionId: 'review-a',
    endedAtUtc: _reviewedAt,
  );
}

Future<void> _seed(AppDatabase db, {String suffix = 'a'}) async {
  final owner = 'owner-$suffix';
  final category = 'category-$suffix';
  await db
      .into(db.localOwners)
      .insert(LocalOwnersCompanion.insert(id: owner, createdAtUtcMs: 1));
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: category,
          ownerId: owner,
          name: 'Travel',
          normalizedName: 'travel',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  for (final (spelling, meaning) in [
    ('station', 'สถานี'),
    ('platform', 'ชานชาลา'),
  ]) {
    await db
        .into(db.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: '$spelling-$suffix',
            ownerId: owner,
            categoryId: category,
            spelling: spelling,
            normalizedSpelling: spelling,
            meaning: meaning,
            normalizedMeaning: meaning,
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  }
}
