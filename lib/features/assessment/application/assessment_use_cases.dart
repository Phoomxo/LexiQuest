import '../../learning/domain/learning_evidence_contract.dart';
import '../domain/assessment_instrument_catalog.dart';
import '../domain/assessment_models.dart';
import '../domain/assessment_repository.dart';
import 'assessment_comparison.dart';

final class AssessmentUseCases {
  const AssessmentUseCases({
    required this._repository,
    required AssessmentInstrumentCatalog instrumentCatalog,
    required this._contentAuthority,
  }) : _catalog = instrumentCatalog;

  final AssessmentRepository _repository;
  final AssessmentInstrumentCatalog _catalog;
  final AssessmentFormContentAuthority _contentAuthority;

  Future<AssessmentPresentation> beginPresentation(
    AssessmentStartCommand command, {
    required String ownerId,
    required bool Function() stillVisible,
  }) async {
    _visible(stillVisible);
    AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
    AssessmentRun.validateRunId(command.runId);
    AssessmentRun.validateCanonicalText(command.learningSessionId, 'sessionId');
    AssessmentRun.validateCanonicalText(command.studyCycleId, 'studyCycleId');
    final definition = _catalog.lookup(
      instrumentId: command.instrumentId,
      instrumentVersion: command.instrumentVersion,
      formId: command.formId,
      formVersion: command.formVersion,
    );
    // Content may be supplied remotely. It is resolved before the SQL writer's TX.
    await requireVerifiedAssessmentForm(
      definition: definition,
      contentAuthority: _contentAuthority,
    );
    _visible(stillVisible);
    final run = await _repository.start(
      command,
      ownerId: ownerId,
      stillVisible: stillVisible,
    );
    _visible(stillVisible);
    _active(run, ownerId, command.runId);
    if (run.learningSessionId != command.learningSessionId ||
        run.studyCycleId != command.studyCycleId ||
        run.phase != command.phase ||
        run.instrumentId != command.instrumentId ||
        run.instrumentVersion != command.instrumentVersion ||
        run.formId != command.formId ||
        run.formVersion != command.formVersion) {
      throw StateError(
        'Assessment start did not preserve the requested intent.',
      );
    }
    assessmentDefinitionForRun(run, _catalog);
    final evidence = List<AssessmentOutcomeEvidence>.unmodifiable(
      await _repository.listOutcomeEvidence(
        ownerId: ownerId,
        learningSessionId: run.learningSessionId,
      ),
    );
    _visible(stillVisible);
    final answered = verifiedAssessmentItemIds(run, definition, evidence);

    // This is the last await: fresh authority and phase are checked together in
    // DATA after earlier content/evidence reads, followed by its final local guards.
    final current = await _repository.requireActivePresentation(
      ownerId: ownerId,
      runId: run.id,
      stillVisible: stillVisible,
    );
    _visible(stillVisible);
    if (current.run != run ||
        evidence.any(
          (fact) => fact.occurredAtUtc.isAfter(current.verifiedAtUtc),
        )) {
      throw StateError(
        'Assessment presentation facts changed during the read.',
      );
    }
    return AssessmentPresentation(
      run: run,
      verifiedAtUtc: current.verifiedAtUtc,
      validUntilUtc: current.validUntilUtc,
      items: [
        for (final item in definition.items)
          AssessmentPresentationItem(
            itemId: item.itemId,
            prompt: item.prompt,
            options: item.responses.keys.toList()..sort(),
          ),
      ],
      answeredItemIds: answered,
    );
  }

  Future<AssessmentSubmissionReceipt> submitPresentedResponse({
    required String ownerId,
    required String runId,
    required String itemId,
    required String option,
    required int responseTimeMs,
    required bool Function() stillVisible,
  }) async {
    _visible(stillVisible);
    AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
    AssessmentRun.validateRunId(runId);
    AssessmentRun.validateCanonicalText(itemId, 'itemId');
    AssessmentRun.validateCanonicalText(option, 'option');
    if (responseTimeMs < 0 ||
        responseTimeMs > LearningEvidenceContract.maxResponseTimeMs) {
      throw ArgumentError.value(responseTimeMs, 'responseTimeMs');
    }
    final run = await _repository.getRun(ownerId: ownerId, runId: runId);
    _visible(stillVisible);
    _active(run, ownerId, runId);
    final definition = assessmentDefinitionForRun(run, _catalog);
    final item = definition.item(itemId);
    final controlled = item.responses[option];
    if (controlled == null) {
      throw ArgumentError.value(
        option,
        'option',
        'must be a controlled option',
      );
    }
    await requireVerifiedAssessmentForm(
      definition: definition,
      contentAuthority: _contentAuthority,
    );
    _visible(stillVisible);
    final result = await _repository.recordResponse(
      ownerId: ownerId,
      runId: runId,
      itemId: itemId,
      option: option,
      responseTimeMs: responseTimeMs,
      stillVisible: stillVisible,
    );
    _visible(stillVisible);
    // Option aliases with identical catalog code/correctness are the same
    // canonical controlled response. The exact submitted key must still exist.
    if (result.sourceEvidenceId != assessmentResponseIdentity(runId, itemId) ||
        result.responseCode != controlled.responseCode ||
        result.isCorrect != controlled.isCorrect) {
      throw StateError(
        'Assessment acknowledgement changed canonical semantics.',
      );
    }
    return AssessmentSubmissionReceipt(
      itemId: itemId,
      inserted: result.inserted,
    );
  }

  Future<void> completePresentation({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) async {
    _references(ownerId, runId, stillVisible);
    final run = await _repository.complete(
      ownerId: ownerId,
      runId: runId,
      stillVisible: stillVisible,
    );
    _visible(stillVisible);
    _terminal(run, ownerId, runId, AssessmentRunState.completed);
  }

  Future<void> abandonPresentation({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) async {
    _references(ownerId, runId, stillVisible);
    final run = await _repository.abandon(
      ownerId: ownerId,
      runId: runId,
      stillVisible: stillVisible,
    );
    _visible(stillVisible);
    _terminal(run, ownerId, runId, AssessmentRunState.abandoned);
  }
}

void _references(String ownerId, String runId, bool Function() stillVisible) {
  _visible(stillVisible);
  AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
  AssessmentRun.validateRunId(runId);
}

void _active(AssessmentRun run, String ownerId, String runId) {
  if (run.id != runId ||
      run.ownerId != ownerId ||
      run.state != AssessmentRunState.active) {
    throw StateError('Assessment active run does not match.');
  }
}

void _terminal(
  AssessmentRun run,
  String ownerId,
  String runId,
  AssessmentRunState state,
) {
  if (run.id != runId || run.ownerId != ownerId || run.state != state) {
    throw StateError('Assessment terminal acknowledgement does not match.');
  }
}

void _visible(bool Function() stillVisible) {
  if (!stillVisible()) {
    throw StateError('Assessment presentation binding is no longer visible.');
  }
}
