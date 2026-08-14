import '../domain/evidence_context.dart';
import '../domain/learning_models.dart';
import 'learning_use_cases.dart';

enum CurrentActivityInput {
  meaningMultipleChoice,
  srsRecall,
  typedRecall,
  associativeRecall,
  ghostDuel,
  speakToText,
  shadowing,
  readingExposure,
}

abstract interface class CurrentActivityRolloutProvider {
  Future<EvidencePolicyRolloutMode> resolve(CurrentActivityInput input);
}

final class FixedCurrentActivityRolloutProvider
    implements CurrentActivityRolloutProvider {
  const FixedCurrentActivityRolloutProvider(this.mode);

  const FixedCurrentActivityRolloutProvider.legacy()
    : mode = EvidencePolicyRolloutMode.legacy;

  final EvidencePolicyRolloutMode mode;

  @override
  Future<EvidencePolicyRolloutMode> resolve(CurrentActivityInput input) async =>
      mode;
}

final class CurrentActivityResearchContext {
  const CurrentActivityResearchContext({
    required this.engagementAllowed,
    this.protocolEvidenceClassOverride,
    this.protocolId,
    this.protocolVersion,
    this.experimentId,
    this.experimentVersion,
    this.assignmentId,
    this.cohort,
    this.researchConsentVersion,
  });

  const CurrentActivityResearchContext.legacyCompatibility()
    : engagementAllowed = true,
      protocolEvidenceClassOverride = null,
      protocolId = null,
      protocolVersion = null,
      experimentId = null,
      experimentVersion = null,
      assignmentId = null,
      cohort = null,
      researchConsentVersion = null;

  final bool engagementAllowed;
  final EvidenceClass? protocolEvidenceClassOverride;
  final String? protocolId;
  final String? protocolVersion;
  final String? experimentId;
  final int? experimentVersion;
  final String? assignmentId;
  final String? cohort;
  final int? researchConsentVersion;
}

abstract interface class CurrentActivityResearchContextProvider {
  Future<CurrentActivityResearchContext> resolve({
    required CurrentActivityInput input,
    required EvidencePolicyRolloutMode rolloutMode,
  });
}

final class LegacyCurrentActivityResearchContextProvider
    implements CurrentActivityResearchContextProvider {
  const LegacyCurrentActivityResearchContextProvider();

  @override
  Future<CurrentActivityResearchContext> resolve({
    required CurrentActivityInput input,
    required EvidencePolicyRolloutMode rolloutMode,
  }) async {
    if (rolloutMode != EvidencePolicyRolloutMode.legacy) {
      throw StateError('research context is unavailable outside Legacy');
    }
    return const CurrentActivityResearchContext.legacyCompatibility();
  }
}

final class CurrentActivityEvidenceAdapter {
  const CurrentActivityEvidenceAdapter({
    required this.generateId,
    required this.nowUtc,
    required this.rolloutProvider,
    required this.researchContextProvider,
  });

  factory CurrentActivityEvidenceAdapter.legacy(LearningUseCases learning) {
    return CurrentActivityEvidenceAdapter(
      generateId: learning.generateId,
      nowUtc: learning.nowUtc,
      rolloutProvider: const FixedCurrentActivityRolloutProvider.legacy(),
      researchContextProvider:
          const LegacyCurrentActivityResearchContextProvider(),
    );
  }

  final LearningIdGenerator generateId;
  final LearningUtcNow nowUtc;
  final CurrentActivityRolloutProvider rolloutProvider;
  final CurrentActivityResearchContextProvider researchContextProvider;

  Future<PendingCurrentActivityEvidence> prepare({
    required CurrentActivityInput input,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    String? providerProvenance,
    int hintLevel = 0,
  }) async {
    final declaration = _declarationFor(input);
    final rolloutMode = await rolloutProvider.resolve(input);
    final research = await researchContextProvider.resolve(
      input: input,
      rolloutMode: rolloutMode,
    );
    final evidenceClassOverride = research.protocolEvidenceClassOverride;
    if (evidenceClassOverride != null &&
        (input != CurrentActivityInput.ghostDuel ||
            rolloutMode == EvidencePolicyRolloutMode.legacy ||
            research.protocolId == null)) {
      throw StateError(
        'protocol evidence-class overrides are restricted to Ghost Duel',
      );
    }
    final evidenceClass = evidenceClassOverride ?? declaration.evidenceClass;
    final context = rolloutMode == EvidencePolicyRolloutMode.legacy
        ? EvidenceContext.legacyCompatibility(
            evidenceClass: evidenceClass,
            skillId: declaration.skillId,
            hintLevel: hintLevel,
            contentRevision: declaration.contentRevision,
            engagementAllowed: research.engagementAllowed,
          )
        : EvidenceContext.forNewEvidence(
            evidenceClass: evidenceClass,
            skillId: declaration.skillId,
            hintLevel: hintLevel,
            contentRevision: declaration.contentRevision,
            rolloutMode: rolloutMode,
            protocolId: research.protocolId,
            protocolVersion: research.protocolVersion,
            experimentId: research.experimentId,
            experimentVersion: research.experimentVersion,
            assignmentId: research.assignmentId,
            cohort: research.cohort,
            researchConsentVersion: research.researchConsentVersion,
            engagementAllowed: research.engagementAllowed,
          );
    final generatedId = generateId().trim();
    if (generatedId.isEmpty) {
      throw StateError('learning id generator returned blank');
    }
    final occurredAtUtc = nowUtc();
    if (!occurredAtUtc.isUtc) {
      throw ArgumentError.value(occurredAtUtc, 'nowUtc', 'must be UTC');
    }
    return PendingCurrentActivityEvidence(
      sourceEvidenceId: 'attempt:$generatedId',
      occurredAtUtc: occurredAtUtc,
      evidenceContext: context,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: declaration.promptMode,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: providerProvenance,
    );
  }
}

final class PendingCurrentActivityEvidence {
  const PendingCurrentActivityEvidence({
    required this.sourceEvidenceId,
    required this.occurredAtUtc,
    required this.evidenceContext,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.attemptNumber,
    required this.providerProvenance,
  });

  final String sourceEvidenceId;
  final DateTime occurredAtUtc;
  final EvidenceContext evidenceContext;
  final String sessionId;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final int? responseTimeMs;
  final int attemptNumber;
  final String? providerProvenance;

  Future<AnswerRecordResult> record(LearningUseCases learning) {
    return learning.recordEvidence(
      sourceEvidenceId: sourceEvidenceId,
      occurredAtUtc: occurredAtUtc,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: promptMode,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      evidenceContext: evidenceContext,
      providerProvenance: providerProvenance,
    );
  }
}

final class _CurrentActivityDeclaration {
  const _CurrentActivityDeclaration({
    required this.evidenceClass,
    required this.skillId,
    required this.promptMode,
  }) : contentRevision = 'built-in-v1';

  final EvidenceClass evidenceClass;
  final String skillId;
  final String promptMode;
  final String contentRevision;
}

_CurrentActivityDeclaration _declarationFor(CurrentActivityInput input) {
  return switch (input) {
    CurrentActivityInput.meaningMultipleChoice =>
      const _CurrentActivityDeclaration(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'meaning-recall',
        promptMode: 'meaningChoice',
      ),
    CurrentActivityInput.srsRecall => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'srs-recall',
      promptMode: 'srsRecall',
    ),
    CurrentActivityInput.typedRecall => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'typed-recall',
      promptMode: 'typedRecall',
    ),
    CurrentActivityInput.associativeRecall => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'associative-recall',
      promptMode: 'associativeRecall',
    ),
    CurrentActivityInput.ghostDuel => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.recreational,
      skillId: 'ghost-duel',
      promptMode: 'ghostSpelling',
    ),
    CurrentActivityInput.speakToText => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.pronunciation,
      skillId: 'pronunciation-transcript',
      promptMode: 'pronunciationTranscript',
    ),
    CurrentActivityInput.shadowing => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.pronunciation,
      skillId: 'shadowing-pronunciation',
      promptMode: 'shadowing',
    ),
    CurrentActivityInput.readingExposure => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.exposure,
      skillId: 'reading-exposure',
      promptMode: 'readingExposure',
    ),
  };
}
