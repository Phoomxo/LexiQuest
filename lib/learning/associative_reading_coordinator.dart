import 'learning_commit.dart';
import 'learning_repository.dart';
import 'reading_content_source.dart';
import 'reading_session.dart';
import 'recall_attempt.dart';
import 'secure_id_generator.dart';
import 'vocabulary_mixer.dart';

typedef ReadingClock = DateTime Function();

final class ReadingStartRequest {
  const ReadingStartRequest({
    required this.ownerId,
    required this.cefrLevel,
    required this.mixRequest,
  });

  final String ownerId;
  final String cefrLevel;
  final VocabularyMixRequest mixRequest;
}

final class ReadingAnswerSubmission {
  const ReadingAnswerSubmission({
    required this.wordKey,
    required this.correct,
    required this.responseTimeMs,
    required this.confidence,
    required this.cueLevel,
  });

  final String wordKey;
  final bool correct;
  final int responseTimeMs;
  final int confidence;
  final RecallCueLevel cueLevel;
}

final class AssociativeReadingState {
  const AssociativeReadingState({required this.session, required this.content});

  final ReadingSession session;
  final ReadingContent content;
}

enum ReadingCoordinatorErrorCode {
  contentUnavailable,
  sessionNotFound,
  illegalTransition,
  invalidSubmission,
}

final class ReadingCoordinatorException implements Exception {
  const ReadingCoordinatorException(this.code);

  final ReadingCoordinatorErrorCode code;

  @override
  String toString() => 'ReadingCoordinatorException($code)';
}

final class AssociativeReadingCoordinator {
  AssociativeReadingCoordinator({
    required this.repository,
    required this.reader,
    required this.contentSource,
    required this.mixer,
    required this.idGenerator,
    required this.clock,
  });

  final LearningRepository repository;
  final LearningReader reader;
  final ReadingContentSource contentSource;
  final VersionedVocabularyMixer mixer;
  final SecureIdGenerator idGenerator;
  final ReadingClock clock;

  AssociativeReadingState? _state;

  AssociativeReadingState? get state => _state;

  Future<AssociativeReadingState> start(ReadingStartRequest request) async {
    if (_state != null && !_isTerminal(_state!.session.currentStage)) {
      throw const ReadingCoordinatorException(
        ReadingCoordinatorErrorCode.illegalTransition,
      );
    }
    final mix = mixer.mix(request.mixRequest);
    final content = await _obtainContent(
      ReadingContentRequest(
        cefrLevel: request.cefrLevel,
        targetWords: mix.words,
      ),
    );
    final now = clock().toUtc();
    final session = ReadingSession(
      sessionId: idGenerator.nextId(),
      ownerId: request.ownerId,
      cefrLevel: request.cefrLevel,
      targetWordKeys: mix.words,
      mixPolicyVersion: mix.algorithmVersion,
      contentId: content.contentId,
      contentVersion: content.contentVersion,
      currentStage: ReadingSessionStage.supportedReading,
      startedAtUtc: now,
      updatedAtUtc: now,
    );
    await repository.commit(
      LearningCommit(
        commitId: idGenerator.nextId(),
        ownerId: request.ownerId,
        recordedAtUtc: now,
        sessions: [session],
      ),
    );
    return _state = AssociativeReadingState(session: session, content: content);
  }

  Future<AssociativeReadingState> resume({
    required String ownerId,
    required String sessionId,
  }) async {
    final session = await reader.readSession(
      ownerId: ownerId,
      sessionId: sessionId,
    );
    if (session == null) {
      throw const ReadingCoordinatorException(
        ReadingCoordinatorErrorCode.sessionNotFound,
      );
    }
    final content = await _obtainContent(
      ReadingContentRequest(
        cefrLevel: session.cefrLevel,
        targetWords: session.targetWordKeys,
        preferredContentId: session.contentId,
      ),
    );
    return _state = AssociativeReadingState(session: session, content: content);
  }

  Future<AssociativeReadingState> advance() async {
    final current = _requireState();
    final next = switch (current.session.currentStage) {
      ReadingSessionStage.supportedReading => ReadingSessionStage.cueFading,
      ReadingSessionStage.cueFading => ReadingSessionStage.recall,
      ReadingSessionStage.association => ReadingSessionStage.transfer,
      _ => throw const ReadingCoordinatorException(
        ReadingCoordinatorErrorCode.illegalTransition,
      ),
    };
    return _commitTransition(next);
  }

  Future<AssociativeReadingState> submit(
    ReadingAnswerSubmission submission,
  ) async {
    final current = _requireState();
    final stage = current.session.currentStage;
    if (!current.session.targetWordKeys.contains(submission.wordKey) ||
        (stage != ReadingSessionStage.recall &&
            stage != ReadingSessionStage.transfer)) {
      throw const ReadingCoordinatorException(
        ReadingCoordinatorErrorCode.invalidSubmission,
      );
    }
    final now = clock().toUtc();
    final attempt = RecallAttempt(
      attemptId: idGenerator.nextId(),
      ownerId: current.session.ownerId,
      sessionId: current.session.sessionId,
      wordKey: submission.wordKey,
      recallMode: stage == ReadingSessionStage.transfer
          ? RecallMode.transfer
          : submission.cueLevel == RecallCueLevel.none
          ? RecallMode.unaided
          : RecallMode.cued,
      cueLevel: submission.cueLevel,
      correctness: submission.correct,
      responseTimeMs: submission.responseTimeMs,
      confidence: submission.confidence,
      algorithmVersion: 'reading-v1',
      occurredAtUtc: now,
    );
    return _commitTransition(
      stage == ReadingSessionStage.recall
          ? ReadingSessionStage.association
          : ReadingSessionStage.scheduling,
      attempt: attempt,
      now: now,
    );
  }

  Future<AssociativeReadingState> finalize() async {
    final current = _requireState();
    if (current.session.currentStage == ReadingSessionStage.completed) {
      return current;
    }
    if (current.session.currentStage != ReadingSessionStage.scheduling) {
      throw const ReadingCoordinatorException(
        ReadingCoordinatorErrorCode.illegalTransition,
      );
    }
    return _commitTransition(ReadingSessionStage.completed);
  }

  Future<AssociativeReadingState> abandon() async {
    final current = _requireState();
    if (current.session.currentStage == ReadingSessionStage.abandoned) {
      return current;
    }
    if (current.session.currentStage == ReadingSessionStage.completed) {
      throw const ReadingCoordinatorException(
        ReadingCoordinatorErrorCode.illegalTransition,
      );
    }
    return _commitTransition(ReadingSessionStage.abandoned);
  }

  Future<AssociativeReadingState> _commitTransition(
    ReadingSessionStage next, {
    RecallAttempt? attempt,
    DateTime? now,
  }) async {
    final current = _requireState();
    final recordedAt = (now ?? clock()).toUtc();
    final session = ReadingSession(
      sessionId: current.session.sessionId,
      ownerId: current.session.ownerId,
      cefrLevel: current.session.cefrLevel,
      targetWordKeys: current.session.targetWordKeys,
      mixPolicyVersion: current.session.mixPolicyVersion,
      contentId: current.session.contentId,
      contentVersion: current.session.contentVersion,
      currentStage: next,
      startedAtUtc: current.session.startedAtUtc,
      updatedAtUtc: recordedAt,
      completedAtUtc: next == ReadingSessionStage.completed ? recordedAt : null,
      abandonedAtUtc: next == ReadingSessionStage.abandoned ? recordedAt : null,
      schemaVersion: current.session.schemaVersion,
    );
    await repository.commit(
      LearningCommit(
        commitId: idGenerator.nextId(),
        ownerId: session.ownerId,
        recordedAtUtc: recordedAt,
        sessions: [session],
        recallAttempts: attempt == null ? const [] : [attempt],
      ),
    );
    return _state = AssociativeReadingState(
      session: session,
      content: current.content,
    );
  }

  AssociativeReadingState _requireState() {
    final current = _state;
    if (current == null) {
      throw const ReadingCoordinatorException(
        ReadingCoordinatorErrorCode.sessionNotFound,
      );
    }
    return current;
  }

  Future<ReadingContent> _obtainContent(ReadingContentRequest request) async {
    final result = await contentSource.obtain(request);
    if (result is ReadingContentAvailable) {
      return result.content;
    }
    throw const ReadingCoordinatorException(
      ReadingCoordinatorErrorCode.contentUnavailable,
    );
  }
}

bool _isTerminal(ReadingSessionStage stage) {
  return stage == ReadingSessionStage.completed ||
      stage == ReadingSessionStage.abandoned;
}
