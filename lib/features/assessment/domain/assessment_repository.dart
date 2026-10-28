import '../../learning/domain/evidence_context.dart';
import 'assessment_models.dart';

typedef AssessmentActiveResponseWork<T> =
    Future<T> Function(AssessmentRun activeRun);
typedef AssessmentCompletionAuthorityGuard =
    Future<void> Function(AssessmentRun activeRun);

final class AssessmentOutcomeEvidence {
  factory AssessmentOutcomeEvidence({
    required String sourceEvidenceId,
    required String ownerId,
    required String learningSessionId,
    required String wordId,
    required String promptMode,
    required bool isCorrect,
    required int responseTimeMs,
    required DateTime occurredAtUtc,
    required String persistedEvidenceClass,
    required EvidenceContext evidenceContext,
  }) {
    AssessmentRun.validateCanonicalText(wordId, 'wordId');
    AssessmentRun.validateCanonicalText(promptMode, 'promptMode');
    if (responseTimeMs < 0 || responseTimeMs > 0x7fffffff) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must be a bounded nonnegative integer',
      );
    }
    AssessmentRun.validateUtcTimestamp(occurredAtUtc, 'occurredAtUtc');
    return AssessmentOutcomeEvidence._(
      sourceEvidenceId: sourceEvidenceId,
      ownerId: ownerId,
      learningSessionId: learningSessionId,
      wordId: wordId,
      promptMode: promptMode,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      occurredAtUtc: occurredAtUtc,
      persistedEvidenceClass: persistedEvidenceClass,
      evidenceContext: evidenceContext,
    );
  }

  const AssessmentOutcomeEvidence._({
    required this.sourceEvidenceId,
    required this.ownerId,
    required this.learningSessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.occurredAtUtc,
    required this.persistedEvidenceClass,
    required this.evidenceContext,
  });

  final String sourceEvidenceId;
  final String ownerId;
  final String learningSessionId;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final int responseTimeMs;
  final DateTime occurredAtUtc;
  final String persistedEvidenceClass;
  final EvidenceContext evidenceContext;
}

abstract interface class AssessmentRepository {
  Future<AssessmentRun> start(AssessmentRun run);

  Future<AssessmentRun> getRun(String runId);

  Future<AssessmentRun> complete({
    required String runId,
    required DateTime completedAtUtc,
    AssessmentCompletionAuthorityGuard? authorityGuard,
  });

  Future<AssessmentRun> abandon({
    required String runId,
    required DateTime abandonedAtUtc,
  });

  Future<AssessmentRun> requireActiveForResponse({
    required String runId,
    required DateTime occurredAtUtc,
  });

  Future<T> serializeActiveResponse<T>({
    required String runId,
    required DateTime occurredAtUtc,
    required AssessmentActiveResponseWork<T> work,
  });

  Future<List<AssessmentRun>> listRunsForStudyCycle({
    required String ownerId,
    required String studyCycleId,
  });

  Future<List<AssessmentOutcomeEvidence>> listOutcomeEvidence({
    required String ownerId,
    required String learningSessionId,
  });
}

final class AssessmentRunConflict implements Exception {
  const AssessmentRunConflict({required this.runId, required this.reason});

  final String runId;
  final String reason;

  @override
  String toString() => 'AssessmentRunConflict(runId: $runId, reason: $reason)';
}
