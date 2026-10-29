import '../../learning/domain/learning_evidence_contract.dart';
import '../../research/domain/research_trusted_time.dart';
import '../domain/assessment_authority.dart';
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

/// Descriptive differences between compatible measures, not an efficacy claim.
final class AssessmentOutcomeComparison {
  const AssessmentOutcomeComparison({
    required this.correctCountDelta,
    required this.accuracyDelta,
  });
  final int correctCountDelta;
  final double accuracyDelta;
}

final class AssessmentComparison {
  const AssessmentComparison({
    required this._repository,
    required AssessmentInstrumentCatalog instrumentCatalog,
    required this._contentAuthority,
    required this._cycleReader,
    required this._trustedTime,
  }) : _catalog = instrumentCatalog;

  final AssessmentRepository _repository;
  final AssessmentInstrumentCatalog _catalog;
  final AssessmentFormContentAuthority _contentAuthority;
  final AssessmentCycleReader _cycleReader;
  final ResearchTrustedTimeSource _trustedTime;

  Future<AssessmentComparisonResult> compare({
    required String ownerId,
    required String studyCycleId,
    required bool Function() stillVisible,
  }) async {
    try {
      _visible(stillVisible);
      AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
      AssessmentRun.validateCanonicalText(studyCycleId, 'studyCycleId');
      final runs = await _repository.listRunsForStudyCycle(
        ownerId: ownerId,
        studyCycleId: studyCycleId,
      );
      _visible(stillVisible);
      if (runs.any(
        (run) => run.ownerId != ownerId || run.studyCycleId != studyCycleId,
      )) {
        throw StateError('Foreign Assessment pair.');
      }
      final pres = runs
          .where((run) => run.phase == AssessmentPhase.pre)
          .toList();
      final posts = runs
          .where((run) => run.phase == AssessmentPhase.post)
          .toList();
      if (pres.length > 1 || posts.length > 1) {
        throw StateError('Ambiguous Assessment pair.');
      }
      if (pres.isEmpty ||
          posts.isEmpty ||
          pres.single.state != AssessmentRunState.completed ||
          posts.single.state != AssessmentRunState.completed) {
        return const AssessmentComparisonMissingPair();
      }
      final pre = pres.single;
      final post = posts.single;
      if (!_compatiblePins(pre, post)) {
        throw StateError('Incompatible original Assessment pins.');
      }
      final definition = assessmentDefinitionForRun(pre, _catalog);
      assessmentDefinitionForRun(post, _catalog);
      await requireVerifiedAssessmentForm(
        definition: definition,
        contentAuthority: _contentAuthority,
      );
      _visible(stillVisible);
      final preEvidence = List<AssessmentOutcomeEvidence>.unmodifiable(
        await _repository.listOutcomeEvidence(
          ownerId: ownerId,
          learningSessionId: pre.learningSessionId,
        ),
      );
      _visible(stillVisible);
      final postEvidence = List<AssessmentOutcomeEvidence>.unmodifiable(
        await _repository.listOutcomeEvidence(
          ownerId: ownerId,
          learningSessionId: post.learningSessionId,
        ),
      );
      _visible(stillVisible);
      verifiedAssessmentItemIds(pre, definition, preEvidence);
      verifiedAssessmentItemIds(post, definition, postEvidence);

      // The pre is historical now. Requiring it to remain unexposed would reject
      // every genuine completed intervention; only the current post proof is read.
      final cycle = await _cycleReader.requirePhase(run: post);
      _visible(stillVisible);
      final time = await _trustedTime.read();
      _visible(stillVisible);
      if (time == null ||
          !time.isFresh ||
          !_bracketsIntervention(pre, post, cycle, time.effectiveNowUtc)) {
        throw StateError('Assessment pair lacks current canonical timing.');
      }
      final before = _summarize(preEvidence);
      final after = _summarize(postEvidence);
      return AssessmentComparisonReady(
        preOutcome: before,
        postOutcome: after,
        comparison: AssessmentOutcomeComparison(
          correctCountDelta: after.correctCount - before.correctCount,
          accuracyDelta: after.accuracy - before.accuracy,
        ),
      );
    } on Object {
      return const AssessmentComparisonIncompatibleMetadata();
    }
  }
}

/// Integrity helpers shared by presentation and comparison, not capture grants.
AssessmentInstrumentDefinition assessmentDefinitionForRun(
  AssessmentRun run,
  AssessmentInstrumentCatalog catalog,
) {
  final definition = catalog.lookup(
    instrumentId: run.instrumentId,
    instrumentVersion: run.instrumentVersion,
    formId: run.formId,
    formVersion: run.formVersion,
  );
  if (definition.protocolId != run.protocolId ||
      definition.experimentId != run.experimentId ||
      definition.experimentVersion != run.experimentVersion ||
      definition.formContentRevision != run.formContentRevision ||
      definition.contentRevision != run.contentRevision ||
      definition.instrumentChecksumSha256 != run.instrumentChecksumSha256 ||
      definition.formChecksumSha256 != run.formChecksumSha256) {
    throw StateError('Assessment catalog does not match the original run.');
  }
  return definition;
}

Set<String> verifiedAssessmentItemIds(
  AssessmentRun run,
  AssessmentInstrumentDefinition definition,
  List<AssessmentOutcomeEvidence> evidence,
) {
  if (run.state == AssessmentRunState.abandoned) {
    throw StateError('Abandoned Assessment evidence is unavailable.');
  }
  final expected = definition.items.map((item) => item.itemId).toSet();
  final observed = <String>{};
  for (final fact in evidence) {
    final context = fact.evidenceContext;
    final itemId = context.assessmentItemId;
    if (itemId == null ||
        !expected.contains(itemId) ||
        !observed.add(itemId) ||
        fact.sourceEvidenceId != assessmentResponseIdentity(run.id, itemId) ||
        fact.ownerId != run.ownerId ||
        fact.learningSessionId != run.learningSessionId ||
        !LearningEvidenceContract.strictAssessmentShape(
          persistedEvidenceClass: fact.persistedEvidenceClass,
          context: context,
        ) ||
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
        context.contentRevision != run.contentRevision ||
        context.policyVersion != run.evidencePolicyVersion ||
        context.featureContractRevision != run.featureContractRevision ||
        context.featureContractHash != run.featureContractHash ||
        fact.responseTimeMs < 0 ||
        fact.responseTimeMs > LearningEvidenceContract.maxResponseTimeMs ||
        fact.occurredAtUtc.isBefore(run.startedAtUtc) ||
        (run.completedAtUtc != null &&
            fact.occurredAtUtc.isAfter(run.completedAtUtc!))) {
      throw StateError('Assessment evidence does not match the original run.');
    }
    final item = definition.item(itemId);
    if (fact.wordId != item.wordId ||
        fact.promptMode != item.promptMode ||
        context.skillId != item.wordId ||
        context.scoringRuleVersion != item.scoringRuleVersion ||
        !item.responses.values.any(
          (response) =>
              response.responseCode == context.assessmentResponseCode &&
              response.isCorrect == fact.isCorrect,
        )) {
      throw StateError('Assessment evidence has mismatched item semantics.');
    }
  }
  if (run.state == AssessmentRunState.completed &&
      observed.length != expected.length) {
    throw StateError('Completed Assessment lacks its exact pinned items.');
  }
  return Set.unmodifiable(observed);
}

bool _compatiblePins(AssessmentRun pre, AssessmentRun post) =>
    pre.id != post.id &&
    pre.learningSessionId != post.learningSessionId &&
    pre.ownerId == post.ownerId &&
    pre.studyCycleId == post.studyCycleId &&
    pre.protocolId == post.protocolId &&
    pre.protocolVersion == post.protocolVersion &&
    pre.protocolRevision == post.protocolRevision &&
    pre.experimentId == post.experimentId &&
    pre.experimentVersion == post.experimentVersion &&
    pre.assignmentId == post.assignmentId &&
    pre.assignmentRevision == post.assignmentRevision &&
    pre.cohort == post.cohort &&
    pre.consentVersion == post.consentVersion &&
    pre.consentDecidedAtUtc == post.consentDecidedAtUtc &&
    pre.instrumentId == post.instrumentId &&
    pre.instrumentVersion == post.instrumentVersion &&
    pre.instrumentRevision == post.instrumentRevision &&
    pre.formId == post.formId &&
    pre.formVersion == post.formVersion &&
    pre.formContentRevision == post.formContentRevision &&
    pre.participationPermitId == post.participationPermitId &&
    pre.participationPermitRevision == post.participationPermitRevision &&
    pre.participationPermitPayloadSha256 ==
        post.participationPermitPayloadSha256 &&
    pre.instrumentChecksumSha256 == post.instrumentChecksumSha256 &&
    pre.formChecksumSha256 == post.formChecksumSha256 &&
    pre.appVersion == post.appVersion &&
    pre.buildId == post.buildId &&
    pre.databaseSchemaVersion == post.databaseSchemaVersion &&
    pre.contentRevision == post.contentRevision &&
    pre.evidencePolicyVersion == post.evidencePolicyVersion &&
    pre.featureContractRevision == post.featureContractRevision &&
    pre.featureContractHash == post.featureContractHash;

bool _bracketsIntervention(
  AssessmentRun pre,
  AssessmentRun post,
  AssessmentCycleReceipt cycle,
  DateTime comparedAtUtc,
) {
  final exposure = cycle.firstExposureAtUtc;
  final start = cycle.interventionStartedAtUtc;
  final end = cycle.interventionCompletedAtUtc;
  if (cycle.ownerId != post.ownerId ||
      cycle.studyCycleId != post.studyCycleId ||
      cycle.phase != AssessmentPhase.post ||
      cycle.opportunityId == null ||
      cycle.interventionSessionId == null ||
      cycle.interventionSessionId == pre.learningSessionId ||
      cycle.interventionSessionId == post.learningSessionId ||
      exposure == null ||
      start == null ||
      end == null) {
    return false;
  }
  AssessmentRun.validateCanonicalText(cycle.opportunityId!, 'opportunityId');
  AssessmentRun.validateCanonicalText(cycle.interventionSessionId!, 'indexId');
  for (final at in [exposure, start, end]) {
    AssessmentRun.validateUtcTimestamp(at, 'intervention time');
  }
  return !pre.completedAtUtc!.isAfter(exposure) &&
      !exposure.isAfter(start) &&
      !start.isAfter(end) &&
      !end.isAfter(post.startedAtUtc) &&
      !pre.completedAtUtc!.isAfter(post.startedAtUtc) &&
      !post.completedAtUtc!.isAfter(comparedAtUtc);
}

AssessmentOutcomeSummary _summarize(List<AssessmentOutcomeEvidence> facts) {
  final correct = facts.where((fact) => fact.isCorrect).length;
  return AssessmentOutcomeSummary(
    sampleSize: facts.length,
    correctCount: correct,
    incorrectCount: facts.length - correct,
    accuracy: correct / facts.length,
  );
}

void _visible(bool Function() stillVisible) {
  if (!stillVisible()) {
    throw StateError('Assessment presentation binding is no longer visible.');
  }
}
