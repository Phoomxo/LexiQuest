import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';

import '../../support/srs_review_harness.dart';

void main() {
  late SrsReviewHarness h;
  setUp(() async => h = await SrsReviewHarness.open());
  tearDown(() async => h.close());

  test(
    'notification probe preserves the actual inherited transaction executor',
    () async {
      expect(h.notificationTransactions, isEmpty);
      await h.database.transaction(() async {
        h.learning.onLocalMutation!();
        await h.settleNotifications();
      });
      expect(h.notifications, 1);
      expect(h.notificationTransactions, [true]);
    },
  );

  test(
    'prepare reads owned due targets without creating any persisted fact',
    () async {
      final before = await h.storage.snapshot();
      final review = (await h.prepare())!;
      expect(review.ownerId, configuredOwnerId);
      expect(review.selection, SrsReviewSelection.due);
      expect(review.words.map((word) => word.id), h.wordIds);
      expect(
        review.words.every(
          (word) => word.contentRevision == 'local-vocabulary-v1:1',
        ),
        isTrue,
      );
      expect(await h.storage.snapshot(), before);
      expect(h.notifications, 0);
    },
  );

  test(
    'source preparation does not require due state or substitute other words',
    () async {
      await h.database.customStatement('DELETE FROM srs_states');
      final ids = <String>[h.wordIds.last];
      final review = (await h.prepare(sourceWordIds: ids))!;
      ids.add(configuredWordIds[2]);
      expect(review.selection, SrsReviewSelection.source);
      expect(review.words.map((word) => word.id), [h.wordIds.last]);
      expect(() => review.words.clear(), throwsUnsupportedError);
      expect(await h.storage.count('learning_sessions'), 0);
    },
  );

  test(
    'the original usecase and original current scope own a prepared handle',
    () async {
      final review = (await h.prepare())!;
      final replacement = h.useCases();
      await expectLater(
        replacement.startSrsReview(review, stillCurrent: () => true),
        throwsStateError,
      );
      h.current = false;
      await expectLater(
        h.learning.startSrsReview(review, stillCurrent: () => true),
        throwsStateError,
      );
      h.current = true;
      await expectLater(
        h.learning.startSrsReview(review, stillCurrent: () => true),
        throwsStateError,
      );
      expect(await h.storage.count('learning_sessions'), 0);
      expect(h.notifications, 0);
    },
  );

  test(
    'ratings cannot be prepared before the original start receipt is confirmed',
    () async {
      final review = (await h.prepare())!;
      expect(() => h.answer(review), throwsStateError);
      await h.learning.startSrsReview(review, stillCurrent: () => h.current);
      expect(h.answer(review).review, same(review));
    },
  );

  test(
    'a pending rating freezes its identity time choice latency and context',
    () async {
      final review = await h.ready();
      final intent = h.answer(review, recalled: false, responseTimeMs: 5678);
      h.now = h.now.add(const Duration(seconds: 17));
      final retried = h.answer(review, recalled: false, responseTimeMs: 5678);
      expect(retried, same(intent));
      expect(intent.cardIndex, 0);
      expect(intent.command.id, 'attempt:srs:${review.id}:0');
      expect(intent.command.ownerId, review.ownerId);
      expect(intent.command.wordId, review.words.first.id);
      expect(intent.command.promptMode, 'srsRecall');
      expect(intent.command.attemptNumber, 1);
      expect(intent.command.responseTimeMs, 5678);
      expect(intent.command.providerProvenance, isNull);
      final context = intent.command.evidenceContext;
      expect(context.evidenceClass.name, 'independentRecall');
      expect(context.skillId, 'srs-recall');
      expect(context.contentRevision, review.words.first.contentRevision);
      expect(context.classificationSource.name, 'declared');
      expect(context.rolloutMode.name, 'legacy');
      expect(
        () => h.answer(review, recalled: true, responseTimeMs: 5678),
        throwsStateError,
      );
      expect(
        () => h.answer(review, recalled: false, responseTimeMs: 1),
        throwsStateError,
      );
    },
  );

  test(
    'the next card cannot be prepared before the current rating receipt',
    () async {
      final review = await h.ready();
      expect(() => h.answer(review, cardIndex: 1), throwsStateError);
      final first = h.answer(review);
      await h.learning.commitSrsRating(first, stillCurrent: () => h.current);
      expect(h.answer(review, cardIndex: 1).command.attemptNumber, 2);
    },
  );

  test(
    'copied intents and replacement usecases cannot adopt original operations',
    () async {
      final review = await h.ready();
      final original = h.answer(review);
      final copy = SrsReviewAnswerIntent(
        review: review,
        cardIndex: original.cardIndex,
        command: original.command,
      );
      await expectLater(
        h.learning.commitSrsRating(copy, stillCurrent: () => true),
        throwsStateError,
      );
      final replacement = h.useCases();
      expect(
        () => replacement.prepareSrsRating(
          review: review,
          cardIndex: 0,
          recalled: true,
          responseTimeMs: 1234,
        ),
        throwsStateError,
      );
      await expectLater(
        replacement.commitSrsRating(original, stillCurrent: () => true),
        throwsStateError,
      );
      expect(await h.storage.count('answer_attempts'), 0);
    },
  );

  for (final stage in ['start', 'rating', 'finish']) {
    test(
      'first confirmed $stage receipt notifies once after a commit then lost ACK',
      () async {
        final ack = SrsAckRepository(h.repository)..loseAfter = stage;
        final learning = h.useCases(repository: ack);
        final review = (await learning.prepareSrsReview(
          expectedOwnerId: configuredOwnerId,
          sourceWordIds: [h.wordIds.first],
          stillCurrent: () => h.current,
        ))!;
        if (stage == 'start') {
          await expectLater(
            learning.startSrsReview(review, stillCurrent: () => h.current),
            throwsStateError,
          );
          expect(await h.storage.count('learning_sessions'), 1);
          expect(h.notifications, 0);
          final before = await h.storage.snapshot();
          await learning.startSrsReview(review, stillCurrent: () => h.current);
          expect(h.notifications, 1);
          await learning.startSrsReview(review, stillCurrent: () => h.current);
          expect(h.notifications, 1);
          expect(await h.storage.snapshot(), before);
        } else {
          await learning.startSrsReview(review, stillCurrent: () => h.current);
          final intent = learning.prepareSrsRating(
            review: review,
            cardIndex: 0,
            recalled: true,
            responseTimeMs: 1234,
          );
          if (stage == 'rating') {
            await expectLater(
              learning.commitSrsRating(intent, stillCurrent: () => h.current),
              throwsStateError,
            );
            expect(await h.storage.count('answer_attempts'), 1);
            expect(h.notifications, 1);
            expect(h.questEvents, 0);
            expect(h.streakEvents, 0);
            final before = await h.storage.snapshot();
            final receipt = await learning.commitSrsRating(
              intent,
              stillCurrent: () => h.current,
            );
            expect(receipt.inserted, isFalse);
            expect(h.notifications, 2);
            expect(h.questEvents, 1);
            expect(h.streakEvents, 1);
            await learning.commitSrsRating(
              intent,
              stillCurrent: () => h.current,
            );
            expect((h.notifications, h.questEvents, h.streakEvents), (2, 1, 1));
            expect(await h.storage.snapshot(), before);
          } else {
            await learning.commitSrsRating(
              intent,
              stillCurrent: () => h.current,
            );
            final finish = learning.prepareSrsFinish(review);
            await expectLater(
              learning.finishSrsReview(finish, stillCurrent: () => h.current),
              throwsStateError,
            );
            expect((await h.storage.session(review.id))['state'], 'completed');
            expect(h.notifications, 2);
            final before = await h.storage.snapshot();
            final result = await learning.finishSrsReview(
              finish,
              stillCurrent: () => h.current,
            );
            expect(result.state, 'completed');
            expect(h.notifications, 3);
            h.now = h.now.add(const Duration(days: 1));
            expect(learning.prepareSrsFinish(review), same(finish));
            final replay = await learning.finishSrsReview(
              finish,
              stillCurrent: () => h.current,
            );
            expect(
              (
                replay.id,
                replay.state,
                replay.correctCount,
                replay.wrongCount,
                replay.score,
              ),
              (
                result.id,
                result.state,
                result.correctCount,
                result.wrongCount,
                result.score,
              ),
            );
            expect(h.notifications, 3);
            expect(await h.storage.snapshot(), before);
          }
        }
        await h.settleNotifications();
        expect(h.notificationTransactions, isNotEmpty);
        expect(h.notificationTransactions, everyElement(isFalse));
      },
    );
  }

  test(
    'finish requires every original confirmed rating and preserves the original end',
    () async {
      final review = await h.ready();
      expect(() => h.learning.prepareSrsFinish(review), throwsStateError);
      for (var index = 0; index < review.words.length; index++) {
        final rating = h.answer(review, cardIndex: index, recalled: index != 0);
        await h.learning.commitSrsRating(rating, stillCurrent: () => h.current);
      }
      h.now = h.now.add(const Duration(seconds: 10));
      final end = h.learning.prepareSrsFinish(review);
      h.now = h.now.add(const Duration(seconds: 50));
      expect(h.learning.prepareSrsFinish(review), same(end));
      final result = await h.learning.finishSrsReview(
        end,
        stillCurrent: () => h.current,
      );
      expect(
        (result.correctCount, result.wrongCount, result.score),
        (1, 1, 50),
      );
      expect(
        (await h.storage.session(review.id))['ended_at_utc_ms'],
        end.endedAtUtc.millisecondsSinceEpoch,
      );
    },
  );

  test(
    'replay returns current saved canonical SRS without inventing a frozen posterior',
    () async {
      final first = await h.ready(sourceWordIds: [h.wordIds.first]);
      final intent = h.answer(first, recalled: true);
      await h.learning.commitSrsRating(intent, stillCurrent: () => h.current);
      h.now = h.now.add(const Duration(hours: 1));
      final second = await h.ready(sourceWordIds: [h.wordIds.first]);
      final later = await h.learning.commitSrsRating(
        h.answer(second, recalled: false),
        stillCurrent: () => h.current,
      );
      final before = await h.storage.snapshot();
      final replay = await h.learning.commitSrsRating(
        intent,
        stillCurrent: () => h.current,
      );
      expect(replay.inserted, isFalse);
      expect(replay.srs!.dueAtUtc, later.srs!.dueAtUtc);
      expect(replay.srs!.lapses, later.srs!.lapses);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'generic-only repositories never receive a fallback SRS write',
    () async {
      final learning = h.useCases(
        repository: GenericLearningDelegate(h.repository),
      );
      await expectLater(
        learning.prepareSrsReview(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(await h.storage.count('learning_sessions'), 0);
    },
  );
}

class GenericLearningDelegate implements LearningRepository {
  GenericLearningDelegate(this.delegate);
  final DriftLearningRepository delegate;
  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    afterWordId: afterWordId,
    limit: limit,
  );
  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);
  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) =>
      delegate.recordAnswer(command);
  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => delegate.finishSession(
    ownerId: ownerId,
    sessionId: sessionId,
    endedAtUtc: endedAtUtc,
  );
  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) => delegate.listDueWords(ownerId: ownerId, nowUtc: nowUtc, limit: limit);
  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => delegate.readReadingProgress(
    ownerId: ownerId,
    documentId: documentId,
    documentRevision: documentRevision,
  );
  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => delegate.saveReadingProgress(command);
}

final class SrsAckRepository extends GenericLearningDelegate
    implements SrsReviewRepository {
  SrsAckRepository(super.delegate);
  String? loseAfter;
  bool _lost = false;
  Future<T> _ack<T>(String stage, Future<T> Function() operation) async {
    final result = await operation();
    if (!_lost && stage == loseAfter) {
      _lost = true;
      throw StateError('Synthetic committed $stage ACK lost');
    }
    return result;
  }

  @override
  Future<SrsReviewSession?> prepareSrsReview({
    required LearningSessionDraft session,
    required SrsReviewSelection selection,
    Iterable<String>? sourceWordIds,
    int limit = 20,
    required bool Function() stillCurrent,
  }) => delegate.prepareSrsReview(
    session: session,
    selection: selection,
    sourceWordIds: sourceWordIds,
    limit: limit,
    stillCurrent: stillCurrent,
  );
  @override
  Future<SrsReviewStartResult> startSrsReview(
    SrsReviewSession review, {
    required bool Function() stillCurrent,
  }) => _ack(
    'start',
    () => delegate.startSrsReview(review, stillCurrent: stillCurrent),
  );
  @override
  Future<AnswerRecordResult> commitSrsRating(
    SrsReviewAnswerIntent intent, {
    required bool Function() stillCurrent,
  }) => _ack(
    'rating',
    () => delegate.commitSrsRating(intent, stillCurrent: stillCurrent),
  );
  @override
  Future<SrsReviewFinishResult> finishSrsReview(
    SrsReviewFinishIntent intent, {
    required bool Function() stillCurrent,
  }) => _ack(
    'finish',
    () => delegate.finishSrsReview(intent, stillCurrent: stillCurrent),
  );
}
