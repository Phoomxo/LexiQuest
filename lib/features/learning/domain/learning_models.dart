import '../../events/domain/event_envelope_v2.dart';
import 'evidence_context.dart';
import 'learning_evidence_contract.dart';
import 'learning_event_context.dart';
import 'session_configuration.dart';

final class QuizWord {
  const QuizWord({
    required this.id,
    required this.categoryId,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    this.cefrLevel,
    this.normalizedSpelling,
    this.normalizedMeaning,
    this.contentRevision,
    this.contentChecksumSha256,
    this.acceptedSpellingVariants = const <String>[],
    this.acceptedSpellingVariantsRevision,
    this.acceptedSpellingVariantsChecksumSha256,
  });

  final String id;
  final String categoryId;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
  final String? cefrLevel;
  final String? normalizedSpelling;
  final String? normalizedMeaning;
  final int? contentRevision;
  final String? contentChecksumSha256;
  final List<String> acceptedSpellingVariants;
  final int? acceptedSpellingVariantsRevision;
  final String? acceptedSpellingVariantsChecksumSha256;
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
    this.sessionConfiguration,
  });

  final String id;
  final List<QuizQuestion> questions;
  final DateTime? startedAtUtc;
  final SessionConfiguration? sessionConfiguration;

  bool get isEmpty => questions.isEmpty;
}

final class LearningSessionHandle {
  const LearningSessionHandle({required this.id, required this.startedAtUtc});

  final String id;
  final DateTime startedAtUtc;
}

final class LearningSessionDraft {
  const LearningSessionDraft({
    required this.id,
    required this.ownerId,
    required this.activityType,
    required this.startedAtUtc,
    required this.appVersion,
    required this.buildId,
    this.sessionConfiguration,
  });

  final String id;
  final String ownerId;
  final String activityType;
  final DateTime? startedAtUtc;
  final String appVersion;
  final String buildId;
  final SessionConfiguration? sessionConfiguration;

  LearningSessionDraft copyWith({DateTime? startedAtUtc}) {
    return LearningSessionDraft(
      id: id,
      ownerId: ownerId,
      activityType: activityType,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      appVersion: appVersion,
      buildId: buildId,
      sessionConfiguration: sessionConfiguration,
    );
  }
}

final class RecordAnswerCandidate {
  const RecordAnswerCandidate({
    required this.id,
    required this.ownerId,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.attemptNumber,
    required this.occurredAtUtc,
    required this.evidenceContext,
    this.providerProvenance,
    this.actorIdentity,
    this.eventContext,
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
  final EvidenceContext evidenceContext;
  final String? providerProvenance;
  final String? actorIdentity;
  final LearningEventContext? eventContext;
}

final class RecordAnswerCommand {
  factory RecordAnswerCommand({
    required String id,
    required String ownerId,
    required String sessionId,
    required String wordId,
    required String promptMode,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    required DateTime occurredAtUtc,
    required EvidenceContext evidenceContext,
    String? providerProvenance,
    required EventEnvelopeV2 event,
  }) {
    if (LearningEvidenceContract.isExactFrozenV13LegacyEvidence(
      evidenceContext,
    )) {
      throw ArgumentError.value(
        evidenceContext,
        'evidenceContext',
        'the frozen v13 sentinel is exclusive to legacy ingress',
      );
    }
    return RecordAnswerCommand._(
      id: id,
      ownerId: ownerId,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: promptMode,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      occurredAtUtc: occurredAtUtc,
      evidenceContext: evidenceContext,
      providerProvenance: providerProvenance,
      event: event,
      isFrozenV13LegacyIngress: false,
    );
  }

  factory RecordAnswerCommand.frozenV13LegacyIngress({
    required String id,
    required String ownerId,
    required String sessionId,
    required String wordId,
    required String promptMode,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    required DateTime occurredAtUtc,
    required EvidenceContext evidenceContext,
    String? providerProvenance,
  }) {
    if (!LearningEvidenceContract.isExactFrozenV13LegacyEvidence(
      evidenceContext,
    )) {
      throw ArgumentError.value(
        evidenceContext,
        'evidenceContext',
        'must equal the frozen v13 legacy evidence sentinel',
      );
    }
    return RecordAnswerCommand._(
      id: id,
      ownerId: ownerId,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: promptMode,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      occurredAtUtc: occurredAtUtc,
      evidenceContext: evidenceContext,
      providerProvenance: providerProvenance,
      event: null,
      isFrozenV13LegacyIngress: true,
    );
  }

  const RecordAnswerCommand._({
    required this.id,
    required this.ownerId,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.attemptNumber,
    required this.occurredAtUtc,
    required this.evidenceContext,
    required this.providerProvenance,
    required this.event,
    required this.isFrozenV13LegacyIngress,
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
  final EvidenceContext evidenceContext;
  final String? providerProvenance;
  final EventEnvelopeV2? event;
  final bool isFrozenV13LegacyIngress;

  RecordAnswerCandidate get candidate => RecordAnswerCandidate(
    id: id,
    ownerId: ownerId,
    sessionId: sessionId,
    wordId: wordId,
    promptMode: promptMode,
    isCorrect: isCorrect,
    responseTimeMs: responseTimeMs,
    attemptNumber: attemptNumber,
    occurredAtUtc: occurredAtUtc,
    evidenceContext: evidenceContext,
    providerProvenance: providerProvenance,
    actorIdentity: event?.actorIdentity,
    eventContext: event == null
        ? null
        : LearningEventContext.fromEvidenceEnvelope(
            envelope: event!,
            evidenceContext: evidenceContext,
          ),
  );
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
  const AnswerRecordResult({
    required this.inserted,
    required this.isCorrect,
    required this.srs,
  });

  final bool inserted;
  final bool isCorrect;
  final SrsSnapshot? srs;
}

final class CommittedAnswerReplay {
  const CommittedAnswerReplay({required this.result, required this.event});

  final AnswerRecordResult result;
  final EventEnvelopeV2 event;
}

final class LearningSessionSummary {
  const LearningSessionSummary({
    required this.id,
    required this.ownerId,
    required this.activityType,
    required this.state,
    required this.startedAtUtc,
    this.endedAtUtc,
    required this.correctCount,
    required this.wrongCount,
    required this.score,
    this.appVersion,
    this.buildId,
    this.sessionConfiguration,
    this.configurationActiveEffort = Duration.zero,
  });

  final String id;
  final String ownerId;
  final String activityType;
  final String state;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;
  final int correctCount;
  final int wrongCount;
  final int score;
  final String? appVersion;
  final String? buildId;
  final SessionConfiguration? sessionConfiguration;
  final Duration configurationActiveEffort;
}

/// Versioned local checkpoint for reconstructing an interrupted activity from
/// the canonical learning session and its immutable event history.
final class LearningActivityCheckpoint {
  const LearningActivityCheckpoint({
    required this.sessionId,
    required this.activityType,
    required this.revision,
    required this.occurredAtUtc,
    required this.state,
    this.terminalAtUtc,
    this.terminalAcknowledged = false,
  });

  final String sessionId;
  final String activityType;
  final int revision;
  final DateTime occurredAtUtc;
  final Map<String, Object?> state;
  final DateTime? terminalAtUtc;
  final bool terminalAcknowledged;
}

/// One repository-authenticated activity reconstruction. Attempts are
/// returned only after their canonical source events have been validated.
final class LearningActivityRecovery {
  const LearningActivityRecovery({
    required this.session,
    required this.checkpoint,
    required this.attempts,
  });

  final LearningSessionSummary session;
  final LearningActivityCheckpoint? checkpoint;
  final List<RecordAnswerCandidate> attempts;
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
