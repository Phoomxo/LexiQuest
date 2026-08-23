import '../../learning/domain/evidence_context.dart';
import '../domain/assessment_instrument_catalog.dart';
import '../domain/assessment_models.dart';
import '../domain/assessment_repository.dart';

sealed class AssessmentComparisonResult {
  const AssessmentComparisonResult();
}

final class AssessmentComparisonReady extends AssessmentComparisonResult {
  const AssessmentComparisonReady({
    required this.preOutcome,
    required this.postOutcome,
    required this.comparison,
  });

  final AssessmentOutcomeSummary preOutcome;
  final AssessmentOutcomeSummary postOutcome;
  final AssessmentOutcomeComparison comparison;
}

final class AssessmentComparisonMissingPair extends AssessmentComparisonResult {
  const AssessmentComparisonMissingPair();
}

final class AssessmentComparisonIncompatibleMetadata
    extends AssessmentComparisonResult {
  const AssessmentComparisonIncompatibleMetadata();
}

final class AssessmentOutcomeSummary {
  const AssessmentOutcomeSummary({
    required this.sampleSize,
    required this.correctCount,
    required this.incorrectCount,
    required this.accuracy,
  });

  final int sampleSize;
  final int correctCount;
  final int incorrectCount;
  final double accuracy;
}

final class AssessmentOutcomeComparison {
  const AssessmentOutcomeComparison({
    required this.correctCountDelta,
    required this.accuracyDelta,
  });

  final int correctCountDelta;
  final double accuracyDelta;
}

final class AssessmentComparison {
  const AssessmentComparison(this._repository, this._instrumentCatalog);

  final AssessmentRepository _repository;
  final AssessmentInstrumentCatalog _instrumentCatalog;

  Future<AssessmentComparisonResult> compare({
    required String ownerId,
    required String studyCycleId,
  }) async {
    try {
      final runs = await _repository.listRunsForStudyCycle(
        ownerId: ownerId,
        studyCycleId: studyCycleId,
      );
      final pre = _singleCompleted(runs, AssessmentPhase.pre);
      final post = _singleCompleted(runs, AssessmentPhase.post);
      if (pre == null || post == null) {
        return const AssessmentComparisonMissingPair();
      }
      if (!_compatibleRuns(pre, post)) {
        return const AssessmentComparisonIncompatibleMetadata();
      }

      final preEvidence = await _repository.listOutcomeEvidence(
        ownerId: ownerId,
        learningSessionId: pre.learningSessionId,
      );
      final postEvidence = await _repository.listOutcomeEvidence(
        ownerId: ownerId,
        learningSessionId: post.learningSessionId,
      );
      if (preEvidence.isEmpty ||
          postEvidence.isEmpty ||
          !_canonicalEvidence(pre, preEvidence, _instrumentCatalog) ||
          !_canonicalEvidence(post, postEvidence, _instrumentCatalog)) {
        return const AssessmentComparisonIncompatibleMetadata();
      }
      final scoringRules = <String>{
        ...preEvidence.map((item) => item.evidenceContext.scoringRuleVersion!),
        ...postEvidence.map((item) => item.evidenceContext.scoringRuleVersion!),
      };
      if (scoringRules.length != 1) {
        return const AssessmentComparisonIncompatibleMetadata();
      }

      final preOutcome = _summarize(preEvidence);
      final postOutcome = _summarize(postEvidence);
      return AssessmentComparisonReady(
        preOutcome: preOutcome,
        postOutcome: postOutcome,
        comparison: AssessmentOutcomeComparison(
          correctCountDelta: postOutcome.correctCount - preOutcome.correctCount,
          accuracyDelta: postOutcome.accuracy - preOutcome.accuracy,
        ),
      );
    } on Object {
      return const AssessmentComparisonIncompatibleMetadata();
    }
  }
}

AssessmentRun? _singleCompleted(
  List<AssessmentRun> runs,
  AssessmentPhase phase,
) {
  final matching = runs.where((run) => run.phase == phase).toList();
  if (matching.length != 1 ||
      matching.single.state != AssessmentRunState.completed) {
    return null;
  }
  return matching.single;
}

bool _compatibleRuns(AssessmentRun pre, AssessmentRun post) {
  return pre.ownerId == post.ownerId &&
      pre.studyCycleId == post.studyCycleId &&
      pre.protocolId == post.protocolId &&
      pre.protocolVersion == post.protocolVersion &&
      pre.experimentId == post.experimentId &&
      pre.experimentVersion == post.experimentVersion &&
      pre.assignmentId == post.assignmentId &&
      pre.cohort == post.cohort &&
      pre.consentVersion == post.consentVersion &&
      pre.consentDecidedAtUtc == post.consentDecidedAtUtc &&
      pre.instrumentId == post.instrumentId &&
      pre.instrumentVersion == post.instrumentVersion &&
      pre.formId == post.formId &&
      pre.formVersion == post.formVersion &&
      pre.instrumentChecksumSha256 == post.instrumentChecksumSha256 &&
      pre.formChecksumSha256 == post.formChecksumSha256 &&
      pre.appVersion == post.appVersion &&
      pre.buildId == post.buildId &&
      pre.databaseSchemaVersion == post.databaseSchemaVersion &&
      pre.contentRevision == post.contentRevision &&
      pre.evidencePolicyVersion == post.evidencePolicyVersion &&
      pre.featureContractRevision == post.featureContractRevision &&
      pre.featureContractHash == post.featureContractHash;
}

bool _canonicalEvidence(
  AssessmentRun run,
  List<AssessmentOutcomeEvidence> evidence,
  AssessmentInstrumentCatalog instrumentCatalog,
) {
  final terminalAtUtc = switch (run.state) {
    AssessmentRunState.completed => run.completedAtUtc,
    AssessmentRunState.abandoned => run.abandonedAtUtc,
    AssessmentRunState.active => null,
  };
  if (terminalAtUtc == null) {
    return false;
  }
  final definition = instrumentCatalog.lookup(
    instrumentId: run.instrumentId,
    instrumentVersion: run.instrumentVersion,
    formId: run.formId,
    formVersion: run.formVersion,
  );
  if (definition.protocolId != run.protocolId ||
      definition.experimentId != run.experimentId ||
      definition.experimentVersion != run.experimentVersion ||
      definition.contentRevision != run.contentRevision ||
      definition.instrumentChecksumSha256 != run.instrumentChecksumSha256 ||
      definition.formChecksumSha256 != run.formChecksumSha256) {
    return false;
  }
  for (final item in evidence) {
    final context = item.evidenceContext;
    if (item.ownerId != run.ownerId ||
        item.learningSessionId != run.learningSessionId ||
        item.persistedEvidenceClass != EvidenceClass.assessment.name ||
        context.evidenceClass != EvidenceClass.assessment ||
        context.classificationSource != EvidenceClassificationSource.declared ||
        context.rolloutMode != EvidencePolicyRolloutMode.enforced ||
        context.engagementAllowed ||
        context.protocolId != run.protocolId ||
        context.protocolVersion != run.protocolVersion ||
        context.experimentId != run.experimentId ||
        context.experimentVersion != run.experimentVersion ||
        context.assignmentId != run.assignmentId ||
        context.cohort != run.cohort ||
        context.researchConsentVersion != run.consentVersion ||
        context.instrumentId != run.instrumentId ||
        context.instrumentVersion != run.instrumentVersion ||
        context.formId != run.formId ||
        context.formVersion != run.formVersion ||
        context.assessmentItemId == null ||
        context.assessmentResponseCode == null ||
        context.scoringRuleVersion == null ||
        context.contentRevision != run.contentRevision ||
        context.policyVersion != run.evidencePolicyVersion ||
        context.featureContractRevision != run.featureContractRevision ||
        context.featureContractHash != run.featureContractHash) {
      return false;
    }
    final catalogItem = definition.item(context.assessmentItemId!);
    if (catalogItem.wordId != item.wordId ||
        catalogItem.promptMode != item.promptMode ||
        item.occurredAtUtc.isBefore(run.startedAtUtc) ||
        item.occurredAtUtc.isAfter(terminalAtUtc) ||
        catalogItem.scoringRuleVersion != context.scoringRuleVersion ||
        !catalogItem.responses.values.any(
          (response) =>
              response.responseCode == context.assessmentResponseCode &&
              response.isCorrect == item.isCorrect,
        )) {
      return false;
    }
  }
  return true;
}

AssessmentOutcomeSummary _summarize(List<AssessmentOutcomeEvidence> evidence) {
  final correct = evidence.where((item) => item.isCorrect).length;
  final sampleSize = evidence.length;
  return AssessmentOutcomeSummary(
    sampleSize: sampleSize,
    correctCount: correct,
    incorrectCount: sampleSize - correct,
    accuracy: correct / sampleSize,
  );
}
