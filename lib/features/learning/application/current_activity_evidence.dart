import '../../events/domain/event_envelope_v2.dart';
import '../../../product/feature_contract/feature_contract_digest.dart';
import '../domain/evidence_context.dart';
import '../domain/contrastive_explanation.dart';
import '../domain/evidence_policy_rollout.dart';
import '../domain/hint_policy.dart';
import '../domain/learning_event_context.dart';
import '../domain/learning_models.dart';
import '../domain/lexical_prompt_artifact_identity.dart';
import 'learning_use_cases.dart';

enum CurrentActivityInput {
  meaningMultipleChoice,
  meaningToWordMultipleChoice,
  definitionMultipleChoice,
  clozeSelected,
  clozeTyped,
  matchingPair,
  srsRecall,
  typedRecall,
  associativeRecall,
  ghostDuel,
  speakToText,
  shadowing,
  readingExposure,
  dictation,
  sentenceScramble,
  wordScramble,
}

HintEvidenceClassification classifyCurrentActivityEvidence(
  CurrentActivityInput input, {
  required int hintLevel,
}) {
  final declaration = _declarationFor(input);
  if ((input == CurrentActivityInput.definitionMultipleChoice ||
          input == CurrentActivityInput.clozeSelected ||
          input == CurrentActivityInput.matchingPair) &&
      hintLevel != 0) {
    return HintEvidenceClassification(
      evidenceClass: EvidenceClass.guidedPractice,
      hintLevel: hintLevel < 0 ? 2 : hintLevel,
    );
  }
  return HintPolicy.classifyEvidence(
    declaredClass: declaration.evidenceClass,
    hint: HintUsageSnapshot.fromRecordedLevel(hintLevel),
  );
}

/// One immutable, read-only research-state snapshot for an occurrence.
final class CurrentActivityResearchSnapshot {
  const CurrentActivityResearchSnapshot({
    required this.engagementAllowed,
    required this.consentContext,
    required this.experimentContext,
    required this.protocolId,
    required this.protocolVersion,
    required this.experimentVersion,
    required this.assignmentId,
    this.protocolEvidenceClassOverride,
  });

  const CurrentActivityResearchSnapshot.legacyCompatibility()
    : engagementAllowed = true,
      consentContext = const ConsentContext.none(),
      experimentContext = null,
      protocolId = null,
      protocolVersion = null,
      experimentVersion = null,
      assignmentId = null,
      protocolEvidenceClassOverride = null;

  final bool engagementAllowed;
  final ConsentContext consentContext;
  final ExperimentContext? experimentContext;
  final String? protocolId;
  final String? protocolVersion;
  final int? experimentVersion;
  final String? assignmentId;
  final EvidenceClass? protocolEvidenceClassOverride;

  bool get hasCompleteResearchProtocol =>
      consentContext.researchConsentVersion > 0 &&
      experimentContext != null &&
      protocolId != null &&
      protocolVersion != null &&
      experimentVersion != null &&
      assignmentId != null;

  LearningEventContext eventContextFor(EvidenceContext evidenceContext) {
    if (evidenceContext.rolloutMode == EvidencePolicyRolloutMode.legacy) {
      return LearningEventContext.noResearch(evidenceContext);
    }
    return LearningEventContext(
      consentContext: consentContext,
      experimentContext: experimentContext,
      protocolId: protocolId,
      protocolVersion: protocolVersion,
      experimentVersion: experimentVersion,
      assignmentId: assignmentId,
      featureContractIdentity: FeatureContractIdentity(
        revision: evidenceContext.featureContractRevision,
        semanticHash: evidenceContext.featureContractHash,
      ),
    );
  }
}

/// Canonical read-only research state used by activity classification and by
/// all other learning-event recording paths.
abstract interface class CurrentActivityResearchStateProvider
    implements LearningEventContextProvider {
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  });
}

/// One baseline object serves both interfaces in safe Legacy composition.
final class BaselineCurrentActivityResearchStateProvider
    implements CurrentActivityResearchStateProvider {
  const BaselineCurrentActivityResearchStateProvider();

  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  }) async {
    if (ownerId.trim() != ownerId || ownerId.isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'invalid identifier');
    }
    if (!occurredAtUtc.isUtc) {
      throw ArgumentError.value(occurredAtUtc, 'occurredAtUtc', 'must be UTC');
    }
    if (rolloutMode != EvidencePolicyRolloutMode.legacy) {
      throw StateError('persisted research state is unavailable');
    }
    return const CurrentActivityResearchSnapshot.legacyCompatibility();
  }

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) {
    return const BaselineLearningEventContextProvider().resolve(
      ownerId: ownerId,
      evidenceContext: evidenceContext,
      occurredAtUtc: occurredAtUtc,
    );
  }
}

final class CurrentActivityEvidenceAdapter {
  CurrentActivityEvidenceAdapter({
    required this.learning,
    this.rolloutModeProvider =
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
    this.researchStateProvider =
        const BaselineCurrentActivityResearchStateProvider(),
    LearningIdGenerator? generateId,
    LearningUtcNow? nowUtc,
  }) : generateId = generateId ?? learning.generateId,
       nowUtc = nowUtc ?? learning.nowUtc;

  final LearningUseCases learning;
  final LearningIdGenerator generateId;
  final LearningUtcNow nowUtc;
  final EvidencePolicyRolloutModeProvider rolloutModeProvider;
  final CurrentActivityResearchStateProvider researchStateProvider;

  /// Captures occurrence identity and every response semantic synchronously.
  PendingCurrentActivityEvidence capture({
    String? ownerId,
    required CurrentActivityInput input,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    String? providerProvenance,
    int hintLevel = 0,
  }) {
    if (input == CurrentActivityInput.definitionMultipleChoice ||
        input == CurrentActivityInput.clozeSelected ||
        input == CurrentActivityInput.clozeTyped ||
        input == CurrentActivityInput.matchingPair) {
      throw StateError(
        'This activity requires its typed mode capture contract.',
      );
    }
    final declaration = _declarationFor(input);
    return _capture(
      ownerId: ownerId,
      input: input,
      declaration: declaration,
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: providerProvenance,
      hintLevel: hintLevel,
    );
  }

  /// Captures meaning recognition against an exact verified lexical revision.
  PendingCurrentActivityEvidence capturePinnedMeaningRecognition({
    String? ownerId,
    required CurrentActivityInput input,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required int contentRevision,
    required String checksumSha256,
    ContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    if (input != CurrentActivityInput.meaningMultipleChoice &&
        input != CurrentActivityInput.meaningToWordMultipleChoice) {
      throw ArgumentError.value(input, 'input', 'must be a meaning choice');
    }
    if (contentRevision <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksumSha256)) {
      throw ArgumentError('Pinned meaning content identity is invalid.');
    }
    final declaration = _declarationFor(input);
    return _capture(
      ownerId: ownerId,
      input: input,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: declaration.evidenceClass,
        skillId: declaration.skillId,
        promptMode: declaration.promptMode,
        contentRevision: contrastiveEvidenceContentRevision(
          promptMode: declaration.promptMode,
          wordId: wordId,
          revision: contentRevision,
          checksumSha256: checksumSha256,
        ),
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance:
          'reviewed-lexical-meaning:$contentRevision:$checksumSha256',
      hintLevel: 0,
      contrastiveFeedback: contrastiveFeedback,
    );
  }

  /// Captures a reviewed, version-pinned definition-recognition occurrence.
  /// The hint snapshot is resolved by the shell-owned f19 authority before
  /// this immutable pending command is created.
  PendingCurrentActivityEvidence captureDefinitionRecognition({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required int contentRevision,
    required String checksumSha256,
    required HintEvidenceClassification classification,
    ContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    if (contentRevision <= 0) {
      throw ArgumentError.value(
        contentRevision,
        'contentRevision',
        'must be positive',
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksumSha256)) {
      throw ArgumentError.value(
        checksumSha256,
        'checksumSha256',
        'must be lowercase SHA-256',
      );
    }
    final hintLevel = classification.hintLevel;
    final evidenceClass = classification.evidenceClass;
    if ((hintLevel == 0 && evidenceClass != EvidenceClass.recognition) ||
        (hintLevel > 0 && evidenceClass != EvidenceClass.guidedPractice) ||
        hintLevel < 0) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must be unhinted recognition or hinted guided practice',
      );
    }
    return _capture(
      ownerId: ownerId,
      input: CurrentActivityInput.definitionMultipleChoice,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: evidenceClass,
        skillId: 'definition-recognition',
        promptMode: 'definitionChoice',
        contentRevision:
            LexicalPromptArtifactResolver.formatEvidenceContentRevision(
              promptMode: 'definitionChoice',
              wordId: wordId,
              revision: contentRevision,
              checksumSha256: checksumSha256,
            ),
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance:
          'reviewed-lexical-definition:$contentRevision:$checksumSha256',
      hintLevel: hintLevel,
      contrastiveFeedback: contrastiveFeedback,
    );
  }

  /// Captures the recognition leg hosted by the explicit typed-recall route.
  /// The legacy f07 quiz remains unassisted recognition; this ingress accepts
  /// only the shell-owned support classification frozen by the typed adapter.
  PendingCurrentActivityEvidence captureSupportedMeaningRecognition({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required HintEvidenceClassification classification,
  }) {
    final validUnassisted =
        classification.hintLevel == 0 &&
        classification.evidenceClass == EvidenceClass.recognition;
    final validAssisted =
        classification.hintLevel > 0 &&
        classification.hintLevel <= 2 &&
        classification.evidenceClass == EvidenceClass.guidedPractice;
    if ((!validUnassisted && !validAssisted) || responseTimeMs < 0) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must be unhinted recognition or hinted guided practice',
      );
    }
    return _capture(
      ownerId: ownerId,
      input: CurrentActivityInput.meaningMultipleChoice,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: classification.evidenceClass,
        skillId: 'meaning-recall',
        promptMode: 'meaningChoice',
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: null,
      hintLevel: classification.hintLevel,
    );
  }

  /// Captures one reviewed, revision-pinned cloze occurrence. The adapter
  /// owns response scoring and assistance classification; this gateway owns
  /// the sole canonical evidence write.
  PendingCurrentActivityEvidence captureCloze({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required int contentRevision,
    required String checksumSha256,
    required bool typed,
    required HintEvidenceClassification classification,
    ContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    if (contentRevision <= 0) {
      throw ArgumentError.value(
        contentRevision,
        'contentRevision',
        'must be positive',
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksumSha256)) {
      throw ArgumentError.value(
        checksumSha256,
        'checksumSha256',
        'must be lowercase SHA-256',
      );
    }
    final expectedUnassisted = typed
        ? EvidenceClass.independentRecall
        : EvidenceClass.recognition;
    final validUnassisted =
        classification.hintLevel == 0 &&
        classification.evidenceClass == expectedUnassisted;
    final validAssisted =
        classification.hintLevel > 0 &&
        classification.evidenceClass == EvidenceClass.guidedPractice;
    if ((!validUnassisted && !validAssisted) || classification.hintLevel < 0) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must match the cloze input and assistance snapshot',
      );
    }
    return _capture(
      ownerId: ownerId,
      input: typed
          ? CurrentActivityInput.clozeTyped
          : CurrentActivityInput.clozeSelected,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: classification.evidenceClass,
        skillId: 'cloze-context',
        promptMode: typed ? 'clozeTyped' : 'clozeSelected',
        contentRevision:
            LexicalPromptArtifactResolver.formatEvidenceContentRevision(
              promptMode: typed ? 'clozeTyped' : 'clozeSelected',
              wordId: wordId,
              revision: contentRevision,
              checksumSha256: checksumSha256,
            ),
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance:
          'reviewed-lexical-example:$contentRevision:$checksumSha256',
      hintLevel: classification.hintLevel,
      contrastiveFeedback: contrastiveFeedback,
    );
  }

  /// Captures one version-pinned productive spelling response. Correctness
  /// and assistance classification are owned by the typed-recall adapter;
  /// this gateway only freezes the resulting controlled evidence command.
  PendingCurrentActivityEvidence captureTypedRecall({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    required int contentRevision,
    required String checksumSha256,
    required bool contextual,
    required String providerProvenance,
    required HintEvidenceClassification classification,
  }) {
    if (contentRevision <= 0) {
      throw ArgumentError.value(
        contentRevision,
        'contentRevision',
        'must be positive',
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksumSha256)) {
      throw ArgumentError.value(
        checksumSha256,
        'checksumSha256',
        'must be lowercase SHA-256',
      );
    }
    final validUnassisted =
        classification.hintLevel == 0 &&
        classification.evidenceClass == EvidenceClass.independentRecall;
    final validAssisted =
        classification.hintLevel > 0 &&
        classification.evidenceClass == EvidenceClass.guidedPractice;
    if ((!validUnassisted && !validAssisted) ||
        classification.hintLevel < 0 ||
        providerProvenance.isEmpty ||
        providerProvenance.length > 96) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must be unassisted recall or assisted guided practice',
      );
    }
    final input = contextual
        ? CurrentActivityInput.associativeRecall
        : CurrentActivityInput.typedRecall;
    return _capture(
      ownerId: ownerId,
      input: input,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: classification.evidenceClass,
        skillId: contextual ? 'associative-recall' : 'typed-recall',
        promptMode: contextual ? 'associativeRecall' : 'typedRecall',
        contentRevision:
            LexicalPromptArtifactResolver.formatEvidenceContentRevision(
              promptMode: contextual ? 'associativeRecall' : 'typedRecall',
              wordId: wordId,
              revision: contentRevision,
              checksumSha256: checksumSha256,
            ),
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: providerProvenance,
      hintLevel: classification.hintLevel,
    );
  }

  /// Typed exposure ingress for a flashcard answer reveal. Research assignment
  /// still resolves against the SRS activity while the durable declaration is
  /// exposure, so a reveal can never masquerade as independent recall.
  PendingCurrentActivityEvidence captureFlashcardExposure({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required int? responseTimeMs,
    required int attemptNumber,
  }) => _capture(
    ownerId: ownerId,
    input: CurrentActivityInput.srsRecall,
    declaration: const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.exposure,
      skillId: 'srs-recall',
      promptMode: 'flashcardExposure',
    ),
    sessionId: sessionId,
    wordId: wordId,
    isCorrect: false,
    responseTimeMs: responseTimeMs,
    attemptNumber: attemptNumber,
    providerProvenance: null,
    hintLevel: 0,
  );

  /// Captures one matching resolution through the canonical AnswerAttempts
  /// authority. Matching is recognition unless the shell-owned hint/support
  /// snapshot proves any assistance, in which case it is guided practice.
  PendingCurrentActivityEvidence captureMatching({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required String contentRevision,
    required HintEvidenceClassification classification,
    ContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    final validUnassisted =
        classification.hintLevel == 0 &&
        classification.evidenceClass == EvidenceClass.recognition;
    final validAssisted =
        classification.hintLevel > 0 &&
        classification.evidenceClass == EvidenceClass.guidedPractice;
    if ((!validUnassisted && !validAssisted) || responseTimeMs < 0) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must be unassisted recognition or assisted guided practice',
      );
    }
    return _capture(
      ownerId: ownerId,
      input: CurrentActivityInput.matchingPair,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: classification.evidenceClass,
        skillId: 'matching-recognition',
        promptMode: 'matchingPair',
        contentRevision: contentRevision,
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: 'pinned-lexical-matching',
      hintLevel: classification.hintLevel,
      contrastiveFeedback: contrastiveFeedback,
    );
  }

  /// Reconstructs a previously checkpointed matching occurrence with its
  /// exact caller-owned identity. The returned command deliberately requires
  /// an explicit retry before any canonical write can occur.
  PendingCurrentActivityEvidence restoreMatching({
    String? ownerId,
    required String sourceEvidenceId,
    required DateTime occurredAtUtc,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required String contentRevision,
    required HintEvidenceClassification classification,
    required ResolvedLearningEvidenceContexts contexts,
    String? actorIdentity,
    String providerProvenance = 'pinned-lexical-matching',
    FrozenContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    final validUnassisted =
        classification.hintLevel == 0 &&
        classification.evidenceClass == EvidenceClass.recognition;
    final validAssisted =
        classification.hintLevel > 0 &&
        classification.evidenceClass == EvidenceClass.guidedPractice;
    if ((!validUnassisted && !validAssisted) ||
        responseTimeMs < 0 ||
        !occurredAtUtc.isUtc) {
      throw ArgumentError.value(
        classification,
        'classification',
        'invalid restored matching evidence',
      );
    }
    final frozenEvidenceContext = contexts.evidenceContext;
    final frozenContrastiveFeedback = contrastiveFeedback;
    if (providerProvenance != 'pinned-lexical-matching' &&
        !isContrastiveFeedbackAttemptProvenance(providerProvenance)) {
      throw ArgumentError.value(
        providerProvenance,
        'providerProvenance',
        'invalid restored matching provenance',
      );
    }
    if (frozenContrastiveFeedback != null &&
        providerProvenance !=
            contrastiveFeedbackAttemptProvenance(frozenContrastiveFeedback)) {
      throw StateError(
        'restored matching contrastive feedback identity is corrupt',
      );
    }
    try {
      contexts.eventContext.validateAgainst(
        evidenceContext: frozenEvidenceContext,
        occurredAtUtc: occurredAtUtc,
      );
    } on Object catch (error) {
      throw StateError('restored matching contexts are corrupt: $error');
    }
    if (frozenEvidenceContext.evidenceClass != classification.evidenceClass ||
        frozenEvidenceContext.hintLevel != classification.hintLevel ||
        frozenEvidenceContext.skillId != 'matching-recognition' ||
        frozenEvidenceContext.contentRevision != contentRevision) {
      throw StateError(
        'restored matching contexts conflict with their classification',
      );
    }
    return PendingCurrentActivityEvidence._(
      learning: learning,
      ownerId: ownerId,
      input: CurrentActivityInput.matchingPair,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: classification.evidenceClass,
        skillId: 'matching-recognition',
        promptMode: 'matchingPair',
        contentRevision: contentRevision,
      ),
      hintLevel: classification.hintLevel,
      rolloutModeProvider: rolloutModeProvider,
      researchStateProvider: researchStateProvider,
      contrastiveFeedback: frozenContrastiveFeedback,
      restoredContexts: contexts,
      command: FrozenLearningEvidenceCommand(
        sourceEvidenceId: sourceEvidenceId,
        occurredAtUtc: occurredAtUtc,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: 'matchingPair',
        isCorrect: isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: providerProvenance,
        actorIdentity: actorIdentity,
      ),
    ).._status = PendingCurrentActivityEvidenceStatus.retryRequired;
  }

  PendingCurrentActivityEvidence _capture({
    required String? ownerId,
    required CurrentActivityInput input,
    required _CurrentActivityDeclaration declaration,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    required String? providerProvenance,
    required int hintLevel,
    ContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    final generatedId = generateId().trim();
    if (generatedId.isEmpty) {
      throw StateError('learning id generator returned blank');
    }
    final occurredAtUtc = nowUtc();
    if (!occurredAtUtc.isUtc) {
      throw ArgumentError.value(occurredAtUtc, 'nowUtc', 'must be UTC');
    }
    final frozenContrastiveFeedback = contrastiveFeedback?.freeze();
    final canonicalProviderProvenance = frozenContrastiveFeedback == null
        ? providerProvenance
        : contrastiveFeedbackAttemptProvenance(frozenContrastiveFeedback);
    return PendingCurrentActivityEvidence._(
      learning: learning,
      ownerId: ownerId,
      input: input,
      declaration: declaration,
      hintLevel: hintLevel,
      rolloutModeProvider: rolloutModeProvider,
      researchStateProvider: researchStateProvider,
      contrastiveFeedback: frozenContrastiveFeedback,
      command: FrozenLearningEvidenceCommand(
        sourceEvidenceId: 'attempt:$generatedId',
        occurredAtUtc: occurredAtUtc,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: declaration.promptMode,
        isCorrect: isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: canonicalProviderProvenance,
      ),
    );
  }
}

enum PendingCurrentActivityEvidenceStatus {
  captured,
  resolving,
  writing,
  retryRequired,
  committed,
}

final class PendingCurrentActivityEvidence {
  PendingCurrentActivityEvidence._({
    required this._learning,
    required this._ownerId,
    required this._input,
    required this._declaration,
    required this._hintLevel,
    required this._rolloutModeProvider,
    required this._researchStateProvider,
    required this._command,
    this._contrastiveFeedback,
    this._restoredContexts,
  });

  final LearningUseCases _learning;
  final String? _ownerId;
  final CurrentActivityInput _input;
  final _CurrentActivityDeclaration _declaration;
  final int _hintLevel;
  final EvidencePolicyRolloutModeProvider _rolloutModeProvider;
  final CurrentActivityResearchStateProvider _researchStateProvider;
  final FrozenLearningEvidenceCommand _command;
  final FrozenContrastiveFeedbackContext? _contrastiveFeedback;
  final ResolvedLearningEvidenceContexts? _restoredContexts;

  PendingCurrentActivityEvidenceStatus _status =
      PendingCurrentActivityEvidenceStatus.captured;
  Future<OwnerBoundLearningEvidenceBasis>? _bindingInFlight;
  OwnerBoundLearningEvidenceBasis? _boundBasis;
  Future<ResolvedLearningEvidenceRecord>? _resolutionInFlight;
  ResolvedLearningEvidenceRecord? _resolved;
  Future<AnswerRecordResult>? _recordInFlight;
  AnswerRecordResult? _result;

  String get sourceEvidenceId => _command.sourceEvidenceId;
  DateTime get occurredAtUtc => _command.occurredAtUtc;
  String get sessionId => _command.sessionId;
  String get wordId => _command.wordId;
  String get promptMode => _command.promptMode;
  bool get isCorrect => _command.isCorrect;
  int? get responseTimeMs => _command.responseTimeMs;
  int get attemptNumber => _command.attemptNumber;
  String? get providerProvenance => _command.providerProvenance;
  String? get actorIdentity => _command.actorIdentity ?? _boundBasis?.ownerId;
  FrozenContrastiveFeedbackContext? get contrastiveFeedback =>
      _contrastiveFeedback;
  EvidenceContext? get evidenceContext => _resolved?.contexts.evidenceContext;
  PendingCurrentActivityEvidenceStatus get status => _status;
  bool get requiresRetry =>
      _status == PendingCurrentActivityEvidenceStatus.retryRequired;
  bool get isCommitted =>
      _status == PendingCurrentActivityEvidenceStatus.committed;
  bool get isInFlight => _recordInFlight != null;

  /// Once captured, mutable response controls remain locked until the owning
  /// screen advances after a successful commit.
  bool get isResponseLocked => !isCommitted;

  Future<ResolvedLearningEvidenceContexts> freezeContexts() async {
    return (await _resolveOnce()).contexts;
  }

  Future<AnswerRecordResult> record() {
    final inFlight = _recordInFlight;
    if (inFlight != null) return inFlight;
    if (requiresRetry) {
      return Future<AnswerRecordResult>.error(
        StateError('explicit retry is required for pending evidence'),
      );
    }
    final result = _result;
    if (result != null) return Future<AnswerRecordResult>.value(result);
    return _startRecord();
  }

  Future<AnswerRecordResult> retry() {
    final inFlight = _recordInFlight;
    if (inFlight != null) return inFlight;
    if (!requiresRetry) {
      return Future<AnswerRecordResult>.error(
        StateError('pending evidence is not awaiting retry'),
      );
    }
    return _startRecord();
  }

  Future<AnswerRecordResult> _startRecord() {
    final future = _executeRecord();
    _recordInFlight = future;
    return future;
  }

  Future<AnswerRecordResult> _executeRecord() async {
    try {
      _status = PendingCurrentActivityEvidenceStatus.resolving;
      final resolved = await _resolveOnce();
      _status = PendingCurrentActivityEvidenceStatus.writing;
      final result = await _learning.recordResolvedEvidence(
        resolved,
        contrastiveFeedback: _contrastiveFeedback,
      );
      _result = result;
      _status = PendingCurrentActivityEvidenceStatus.committed;
      return result;
    } catch (_) {
      _status = PendingCurrentActivityEvidenceStatus.retryRequired;
      rethrow;
    } finally {
      _recordInFlight = null;
    }
  }

  Future<ResolvedLearningEvidenceRecord> _resolveOnce() {
    final resolved = _resolved;
    if (resolved != null) {
      return Future<ResolvedLearningEvidenceRecord>.value(resolved);
    }
    return _resolutionInFlight ??= _resolveAndMemoize();
  }

  Future<ResolvedLearningEvidenceRecord> _resolveAndMemoize() async {
    try {
      final basis = await _bindOnce();
      final restoredContexts = _restoredContexts;
      final resolved = await _learning.resolveOwnerBoundEvidenceForRecording(
        basis: basis,
        resolveContexts: ({required ownerId, required command}) async {
          if (restoredContexts != null) return restoredContexts;
          final rolloutMode = await _rolloutModeProvider.resolve(
            ownerId: ownerId,
            evidenceContext: null,
          );
          final research = await _researchStateProvider.resolveActivity(
            ownerId: ownerId,
            input: _input,
            occurredAtUtc: command.occurredAtUtc,
            rolloutMode: rolloutMode,
          );
          final evidenceClassOverride = research.protocolEvidenceClassOverride;
          if (evidenceClassOverride != null &&
              (_input != CurrentActivityInput.ghostDuel ||
                  rolloutMode == EvidencePolicyRolloutMode.legacy ||
                  !research.hasCompleteResearchProtocol)) {
            throw StateError(
              'protocol evidence-class overrides require a complete '
              'non-Legacy Ghost Duel protocol',
            );
          }
          final declaredEvidenceClass =
              evidenceClassOverride ?? _declaration.evidenceClass;
          final hintClassification = HintPolicy.classifyEvidence(
            declaredClass: declaredEvidenceClass,
            hint: HintUsageSnapshot.fromRecordedLevel(_hintLevel),
          );
          final useVersionedLegacyMatrix =
              rolloutMode == EvidencePolicyRolloutMode.legacy &&
              _input == CurrentActivityInput.matchingPair;
          final evidenceContext =
              rolloutMode == EvidencePolicyRolloutMode.legacy &&
                  !useVersionedLegacyMatrix
              ? EvidenceContext.legacyCompatibility(
                  evidenceClass: hintClassification.evidenceClass,
                  skillId: _declaration.skillId,
                  hintLevel: hintClassification.hintLevel,
                  contentRevision: _declaration.contentRevision,
                  engagementAllowed: research.engagementAllowed,
                )
              : EvidenceContext.forNewEvidence(
                  evidenceClass: hintClassification.evidenceClass,
                  skillId: _declaration.skillId,
                  hintLevel: hintClassification.hintLevel,
                  contentRevision: _declaration.contentRevision,
                  rolloutMode: rolloutMode,
                  protocolId: research.protocolId,
                  protocolVersion: research.protocolVersion,
                  experimentId: research.experimentContext?.experimentId,
                  experimentVersion: research.experimentVersion,
                  assignmentId: research.assignmentId,
                  cohort: research.experimentContext?.variantId,
                  researchConsentVersion: useVersionedLegacyMatrix
                      ? null
                      : research.consentContext.researchConsentVersion,
                  engagementAllowed: useVersionedLegacyMatrix
                      ? false
                      : research.engagementAllowed,
                );
          return ResolvedLearningEvidenceContexts(
            evidenceContext: evidenceContext,
            eventContext: research.eventContextFor(evidenceContext),
          );
        },
      );
      _resolved = resolved;
      return resolved;
    } finally {
      _resolutionInFlight = null;
    }
  }

  Future<OwnerBoundLearningEvidenceBasis> _bindOnce() {
    final basis = _boundBasis;
    if (basis != null) {
      return Future<OwnerBoundLearningEvidenceBasis>.value(basis);
    }
    return _bindingInFlight ??= _bindAndMemoize();
  }

  Future<OwnerBoundLearningEvidenceBasis> _bindAndMemoize() async {
    try {
      final basis = await _learning.bindEvidenceForRecording(
        command: _command,
        ownerId: _ownerId,
      );
      _boundBasis = basis;
      return basis;
    } finally {
      _bindingInFlight = null;
    }
  }
}

final class _CurrentActivityDeclaration {
  const _CurrentActivityDeclaration({
    required this.evidenceClass,
    required this.skillId,
    required this.promptMode,
    this.contentRevision = 'built-in-v1',
  });

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
    CurrentActivityInput.meaningToWordMultipleChoice =>
      const _CurrentActivityDeclaration(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'meaning-recall',
        promptMode: 'wordChoice',
      ),
    CurrentActivityInput.definitionMultipleChoice =>
      const _CurrentActivityDeclaration(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'definition-recognition',
        promptMode: 'definitionChoice',
      ),
    CurrentActivityInput.clozeSelected => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.recognition,
      skillId: 'cloze-context',
      promptMode: 'clozeSelected',
    ),
    CurrentActivityInput.clozeTyped => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'cloze-context',
      promptMode: 'clozeTyped',
    ),
    CurrentActivityInput.matchingPair => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.recognition,
      skillId: 'matching-recognition',
      promptMode: 'matchingPair',
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
    CurrentActivityInput.dictation => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'dictation-spelling',
      promptMode: 'dictation',
    ),
    CurrentActivityInput.sentenceScramble => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.recreational,
      skillId: 'sentence-scramble',
      promptMode: 'sentenceScramble',
    ),
    CurrentActivityInput.wordScramble => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.recreational,
      skillId: 'word-scramble',
      promptMode: 'wordScramble',
    ),
  };
}
