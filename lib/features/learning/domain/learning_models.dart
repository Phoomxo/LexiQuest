import 'accepted_quiz_plan.dart';
import 'evidence_context.dart';
import 'learning_evidence_contract.dart';

final class QuizWord {
  const QuizWord({
    required this.id,
    required this.categoryId,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    this.contentRevision,
  });

  final String id;
  final String categoryId;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
  final String? contentRevision;
}

final class QuizQuestion {
  const QuizQuestion({required this.word, required this.options});

  final QuizWord word;
  final List<String> options;

  String get correctAnswer => word.meaning;
}

final class QuizSession {
  const QuizSession({
    required this.id,
    required this.questions,
    required this.startedAtUtc,
    this.configured,
  });

  final String id;
  final List<QuizQuestion> questions;
  final DateTime? startedAtUtc;
  final ConfiguredQuizState? configured;

  bool get isEmpty => questions.isEmpty;
}

final class LearningSessionDraft {
  const LearningSessionDraft({
    required this.id,
    required this.ownerId,
    required this.activityType,
    required this.startedAtUtc,
    required this.appVersion,
    required this.buildId,
  });

  final String id;
  final String ownerId;
  final String activityType;
  final DateTime? startedAtUtc;
  final String appVersion;
  final String buildId;

  LearningSessionDraft copyWith({DateTime? startedAtUtc}) {
    return LearningSessionDraft(
      id: id,
      ownerId: ownerId,
      activityType: activityType,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      appVersion: appVersion,
      buildId: buildId,
    );
  }
}

final class RecordAnswerCommand {
  const RecordAnswerCommand({
    required this.id,
    required this.ownerId,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.attemptNumber,
    required this.occurredAtUtc,
    this.providerProvenance,
    this._evidenceContext,
  });

  final String id;
  final String ownerId;
  final String sessionId;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final int? responseTimeMs;
  final int attemptNumber;
  final DateTime occurredAtUtc;
  final String? providerProvenance;
  final EvidenceContext? _evidenceContext;

  EvidenceContext get evidenceContext =>
      _evidenceContext ??
      LearningEvidenceContract.frozenV13LegacyEvidenceContext();
}

final class SrsSnapshot {
  const SrsSnapshot({
    required this.intervalDays,
    required this.repetitions,
    required this.lapses,
    required this.stability,
    required this.difficulty,
    required this.lastReviewAtUtc,
    required this.dueAtUtc,
    required this.algorithmVersion,
  });

  final int intervalDays;
  final int repetitions;
  final int lapses;
  final double stability;
  final double difficulty;
  final DateTime? lastReviewAtUtc;
  final DateTime? dueAtUtc;
  final int algorithmVersion;
}

final class AnswerRecordResult {
  const AnswerRecordResult({required this.inserted, required this.srs});

  final bool inserted;
  final SrsSnapshot srs;
}

final class LearningSessionSummary {
  const LearningSessionSummary({
    required this.id,
    required this.state,
    required this.correctCount,
    required this.wrongCount,
    required this.score,
  });

  final String id;
  final String state;
  final int correctCount;
  final int wrongCount;
  final int score;
}

final class LearningSessionResult {
  LearningSessionResult({
    required this.summary,
    required Iterable<String> mistakeWordIds,
  }) : mistakeWordIds = List.unmodifiable(mistakeWordIds);

  final LearningSessionSummary summary;
  final List<String> mistakeWordIds;
}

final class ReadingProgressCommand {
  const ReadingProgressCommand({
    required this.eventId,
    required this.ownerId,
    required this.documentId,
    required this.documentRevision,
    required this.position,
    required this.isCompleted,
    required this.occurredAtUtc,
  });

  final String eventId;
  final String ownerId;
  final String documentId;
  final int documentRevision;
  final int position;
  final bool isCompleted;
  final DateTime occurredAtUtc;
}

final class ReadingProgressSnapshot {
  const ReadingProgressSnapshot({
    required this.documentId,
    required this.documentRevision,
    required this.lastPosition,
    required this.isCompleted,
    required this.updatedAtUtc,
  });

  final String documentId;
  final int documentRevision;
  final int lastPosition;
  final bool isCompleted;
  final DateTime updatedAtUtc;

  @override
  bool operator ==(Object other) {
    return other is ReadingProgressSnapshot &&
        other.documentId == documentId &&
        other.documentRevision == documentRevision &&
        other.lastPosition == lastPosition &&
        other.isCompleted == isCompleted &&
        other.updatedAtUtc == updatedAtUtc;
  }

  @override
  int get hashCode => Object.hash(
    documentId,
    documentRevision,
    lastPosition,
    isCompleted,
    updatedAtUtc,
  );
}

final class ConfiguredQuizLaunch {
  const ConfiguredQuizLaunch({
    required this.session,
    required this.configuration,
  });

  final LearningSessionDraft session;
  final QuizConfiguration configuration;
}

enum ConfiguredQuizUnavailableReason {
  emptySelection,
  notFound,
  legacy,
  syncedEvidence,
  corrupt,
  ownerChanged,
  contentChanged,
  unsupportedPolicy,
}

final class ConfiguredQuizUnavailable implements Exception {
  const ConfiguredQuizUnavailable(this.reason);
  final ConfiguredQuizUnavailableReason reason;

  @override
  String toString() => 'Configured quiz unavailable: ${reason.name}';
}

final class ConfiguredQuizState {
  ConfiguredQuizState({
    required this.sessionId,
    required this.ownerId,
    required this.activityType,
    required this.startedAtUtc,
    required this.appVersion,
    required this.buildId,
    required this.state,
    required this.endedAtUtc,
    required this.plan,
    required this.checkpointRevision,
    required this.checkpoint,
    Iterable<QuizWord> mistakeWords = const [],
    this.restored = false,
  }) : mistakeWords = List.unmodifiable(mistakeWords);

  final String sessionId;
  final String ownerId;
  final String activityType;
  final DateTime startedAtUtc;
  final String appVersion;
  final String buildId;
  final String state;
  final DateTime? endedAtUtc;
  final AcceptedQuizPlan plan;
  final int checkpointRevision;
  final QuizCheckpoint checkpoint;
  final List<QuizWord> mistakeWords;
  final bool restored;

  QuizSession get asQuizSession => QuizSession(
    id: sessionId,
    questions: plan.questions,
    startedAtUtc: startedAtUtc,
    configured: this,
  );

  ConfiguredQuizState asRestored() => ConfiguredQuizState(
    sessionId: sessionId,
    ownerId: ownerId,
    activityType: activityType,
    startedAtUtc: startedAtUtc,
    appVersion: appVersion,
    buildId: buildId,
    state: state,
    endedAtUtc: endedAtUtc,
    plan: plan,
    checkpointRevision: checkpointRevision,
    checkpoint: checkpoint,
    mistakeWords: mistakeWords,
    restored: true,
  );
}

final class ConfiguredQuizAnswerResult {
  const ConfiguredQuizAnswerResult({required this.state, required this.record});
  final ConfiguredQuizState state;
  final AnswerRecordResult record;
}

final class ConfiguredQuizFinishResult {
  const ConfiguredQuizFinishResult({
    required this.state,
    required this.summary,
  });
  final ConfiguredQuizState state;
  final LearningSessionSummary summary;
}
