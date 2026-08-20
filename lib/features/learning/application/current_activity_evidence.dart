import '../../events/domain/event_envelope_v2.dart';
import '../../../product/feature_contract/feature_contract_digest.dart';
import '../domain/evidence_context.dart';
import '../domain/evidence_policy_rollout.dart';
import '../domain/learning_event_context.dart';
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
    required CurrentActivityInput input,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    String? providerProvenance,
    int hintLevel = 0,
  }) {
    final declaration = _declarationFor(input);
    final generatedId = generateId().trim();
    if (generatedId.isEmpty) {
      throw StateError('learning id generator returned blank');
    }
    final occurredAtUtc = nowUtc();
    if (!occurredAtUtc.isUtc) {
      throw ArgumentError.value(occurredAtUtc, 'nowUtc', 'must be UTC');
    }
    return PendingCurrentActivityEvidence._(
      learning: learning,
      input: input,
      declaration: declaration,
      hintLevel: hintLevel,
      rolloutModeProvider: rolloutModeProvider,
      researchStateProvider: researchStateProvider,
      command: FrozenLearningEvidenceCommand(
        sourceEvidenceId: 'attempt:$generatedId',
        occurredAtUtc: occurredAtUtc,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: declaration.promptMode,
        isCorrect: isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: providerProvenance,
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
    required this._input,
    required this._declaration,
    required this._hintLevel,
    required this._rolloutModeProvider,
    required this._researchStateProvider,
    required this._command,
  });

  final LearningUseCases _learning;
  final CurrentActivityInput _input;
  final _CurrentActivityDeclaration _declaration;
  final int _hintLevel;
  final EvidencePolicyRolloutModeProvider _rolloutModeProvider;
  final CurrentActivityResearchStateProvider _researchStateProvider;
  final FrozenLearningEvidenceCommand _command;

  PendingCurrentActivityEvidenceStatus _status =
      PendingCurrentActivityEvidenceStatus.captured;
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
      final result = await _learning.recordResolvedEvidence(resolved);
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
      final resolved = await _learning.resolveEvidenceForRecording(
        command: _command,
        resolveContexts: ({required ownerId, required command}) async {
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
          final evidenceClass =
              evidenceClassOverride ?? _declaration.evidenceClass;
          final evidenceContext =
              rolloutMode == EvidencePolicyRolloutMode.legacy
              ? EvidenceContext.legacyCompatibility(
                  evidenceClass: evidenceClass,
                  skillId: _declaration.skillId,
                  hintLevel: _hintLevel,
                  contentRevision: _declaration.contentRevision,
                  engagementAllowed: research.engagementAllowed,
                )
              : EvidenceContext.forNewEvidence(
                  evidenceClass: evidenceClass,
                  skillId: _declaration.skillId,
                  hintLevel: _hintLevel,
                  contentRevision: _declaration.contentRevision,
                  rolloutMode: rolloutMode,
                  protocolId: research.protocolId,
                  protocolVersion: research.protocolVersion,
                  experimentId: research.experimentContext?.experimentId,
                  experimentVersion: research.experimentVersion,
                  assignmentId: research.assignmentId,
                  cohort: research.experimentContext?.variantId,
                  researchConsentVersion:
                      research.consentContext.researchConsentVersion,
                  engagementAllowed: research.engagementAllowed,
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
