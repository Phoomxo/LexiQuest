import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import 'assessment_models.dart';

/// A display read's finite freshness snapshot, never a later write grant.
typedef AssessmentPresentationRead = ({
  AssessmentRun run,
  DateTime verifiedAtUtc,
  DateTime validUntilUtc,
});

String assessmentResponseIdentity(String runId, String itemId) {
  AssessmentRun.validateRunId(runId);
  AssessmentRun.validateCanonicalText(itemId, 'itemId');
  return 'assessment-response:'
      '${sha256.convert(utf8.encode(jsonEncode([runId, itemId])))}';
}

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
    AssessmentRun.validateCanonicalText(sourceEvidenceId, 'sourceEvidenceId');
    AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
    AssessmentRun.validateCanonicalText(learningSessionId, 'learningSessionId');
    AssessmentRun.validateCanonicalText(wordId, 'wordId');
    AssessmentRun.validateCanonicalText(promptMode, 'promptMode');
    if (!LearningEvidenceContract.strictAssessmentShape(
      persistedEvidenceClass: persistedEvidenceClass,
      context: evidenceContext,
    )) {
      throw ArgumentError('invalid stored Assessment evidence shape');
    }
    if (responseTimeMs < 0 ||
        responseTimeMs > LearningEvidenceContract.maxResponseTimeMs) {
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
  /// The sole writer derives original pins and trusted time, then rechecks local
  /// authority and [stillVisible] inside its owner-scoped transaction.
  Future<AssessmentRun> start(
    AssessmentStartCommand command, {
    required String ownerId,
    required bool Function() stillVisible,
  });

  Future<AssessmentRun> getRun({
    required String ownerId,
    required String runId,
  });

  /// Final display boundary: fresh authority, exact active container and phase,
  /// then local time/owner/binding/visibility checks. Creates no capture facts.
  Future<AssessmentPresentationRead> requireActivePresentation({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  });

  /// Resolves [option] through the verified pinned catalog. Never accepts caller
  /// correctness, context, raw free text, or a generic SQL work callback.
  /// Exact retries return the original facts and preserve their trusted time.
  Future<AssessmentResponseResult> recordResponse({
    required String ownerId,
    required String runId,
    required String itemId,
    required String option,
    required int responseTimeMs,
    required bool Function() stillVisible,
  });

  Future<AssessmentRun> complete({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  });

  Future<AssessmentRun> abandon({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
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
