import 'dart:async';

import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

export 'srs_review_harness.dart';

/// Keep real Drift subscription cleanup in the zone captured by runAsync.
/// Owner events still reach the widget synchronously, including null/ABA.
Stream<T> srsRealIoStream<T>(Stream<T> source, {required Zone ioZone}) =>
    Stream<T>.multi((events) {
      final subscription = ioZone.run(
        () => source.listen(
          events.addSync,
          onError: events.addErrorSync,
          onDone: events.closeSync,
        ),
      );
      events.onCancel = () => ioZone.run(subscription.cancel);
      events.onPause = () => ioZone.run(subscription.pause);
      events.onResume = () => ioZone.run(subscription.resume);
    }, isBroadcast: source.isBroadcast);

/// Failure/ACK controls wrap the real SRS capability, never generic writers.
final class SrsReviewUiRepository
    implements LearningRepository, SrsReviewRepository {
  SrsReviewUiRepository(this.delegate);
  final LearningRepository delegate;
  SrsReviewRepository get _srs => delegate as SrsReviewRepository;
  Future<void> Function()? beforePrepare;
  Future<void> Function()? beforeStart;
  Future<void> Function()? afterStart;
  Future<void> Function()? beforeRating;
  Future<void> Function()? afterRating;
  Future<void> Function()? beforeFinish;
  Future<void> Function()? afterFinish;
  final starts = <SrsReviewSession>[];
  final ratings = <SrsReviewAnswerIntent>[];
  final finishes = <SrsReviewFinishIntent>[];
  int preparations = 0;
  int genericWrites = 0;

  @override
  Future<SrsReviewSession?> prepareSrsReview({
    required LearningSessionDraft session,
    required SrsReviewSelection selection,
    Iterable<String>? sourceWordIds,
    int limit = 20,
    required bool Function() stillCurrent,
  }) async {
    preparations++;
    await beforePrepare?.call();
    return _srs.prepareSrsReview(
      session: session,
      selection: selection,
      sourceWordIds: sourceWordIds,
      limit: limit,
      stillCurrent: stillCurrent,
    );
  }

  @override
  Future<SrsReviewStartResult> startSrsReview(
    SrsReviewSession review, {
    required bool Function() stillCurrent,
  }) async {
    starts.add(review);
    await beforeStart?.call();
    final result = await _srs.startSrsReview(
      review,
      stillCurrent: stillCurrent,
    );
    await afterStart?.call();
    return result;
  }

  @override
  Future<AnswerRecordResult> commitSrsRating(
    SrsReviewAnswerIntent intent, {
    required bool Function() stillCurrent,
  }) async {
    ratings.add(intent);
    await beforeRating?.call();
    final result = await _srs.commitSrsRating(
      intent,
      stillCurrent: stillCurrent,
    );
    await afterRating?.call();
    return result;
  }

  @override
  Future<SrsReviewFinishResult> finishSrsReview(
    SrsReviewFinishIntent intent, {
    required bool Function() stillCurrent,
  }) async {
    finishes.add(intent);
    await beforeFinish?.call();
    final result = await _srs.finishSrsReview(
      intent,
      stillCurrent: stillCurrent,
    );
    await afterFinish?.call();
    return result;
  }

  @override
  Future<void> startSession(LearningSessionDraft session) {
    genericWrites++;
    return delegate.startSession(session);
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) {
    genericWrites++;
    return delegate.recordAnswer(command);
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) {
    genericWrites++;
    return delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  }

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

final class SrsUiVoice implements VoiceProvider {
  final requests = <VoiceRequest>[];
  int stops = 0;
  Future<void>? holdSpeak;
  Future<void>? holdStop;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    await holdSpeak;
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    await holdStop;
  }
}
