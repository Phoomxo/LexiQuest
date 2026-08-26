import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../learning/domain/lesson_mode.dart';
import 'recommendation_models.dart';
import 'recommendation_policy.dart';

enum RecallLadderModeAvailability {
  available,
  missing,
  implementedOff,
  liveOff,
}

/// Immutable protocol bounds supplied by the active session authority.
///
/// The ladder can narrow recommendations through this value, but it cannot
/// unlock a protocol-locked activity or alter a participant assignment.
final class RecallLadderProtocolLimits {
  RecallLadderProtocolLimits({
    required this.ownerId,
    required this.assignmentId,
    required this.version,
    required this.capturedAtUtc,
    Set<LessonMode> lockedModes = const <LessonMode>{},
  }) : lockedModes = Set.unmodifiable(lockedModes);

  static const String currentVersion = 'recall-ladder-protocol-v1';

  final String ownerId;
  final String assignmentId;
  final String version;
  final DateTime capturedAtUtc;
  final Set<LessonMode> lockedModes;

  bool allows(LessonMode mode) => !lockedModes.contains(mode);
}

/// Learner access constraints relevant to the ladder's audio endpoints.
final class RecallLadderAccessibility {
  const RecallLadderAccessibility({
    required this.speechInputAvailable,
    required this.audioPlaybackAvailable,
  });

  const RecallLadderAccessibility.standard()
    : speechInputAvailable = true,
      audioPlaybackAvailable = true;

  final bool speechInputAvailable;
  final bool audioPlaybackAvailable;

  bool allows(LessonMode mode) => switch (mode) {
    LessonMode.speaking => speechInputAvailable,
    LessonMode.dictation => audioPlaybackAvailable,
    _ => true,
  };
}

/// One response-evidence read reference classified by its canonical adapter.
///
/// [successful] records the canonical adapter result. The ladder separately
/// verifies that [evidenceClass] is eligible for that step, so guided,
/// exposure, pronunciation, and recreational evidence are never promoted to
/// independent recall.
final class RecallLadderObservation {
  const RecallLadderObservation({
    required this.mode,
    required this.evidenceClass,
    required this.successful,
    required this.sourceEvidenceId,
    required this.recordVersion,
    required this.observedAtUtc,
    required this.evidenceReference,
  });

  final LessonMode mode;
  final EvidenceClass evidenceClass;
  final bool successful;
  final String sourceEvidenceId;
  final int recordVersion;
  final DateTime observedAtUtc;
  final RecommendationEvidenceReference evidenceReference;
}

/// Lookup-only request accepted by the application boundary.
///
/// Evidence classifications, outcomes, and protocol limits are intentionally
/// absent. They are resolved from [RecallLadderCanonicalAuthority].
final class RecallLadderRequest {
  const RecallLadderRequest({
    required this.ladderVersion,
    required this.ownerId,
    required this.contentId,
    required this.accessibility,
  });

  final String ladderVersion;
  final String ownerId;
  final String contentId;
  final RecallLadderAccessibility accessibility;
}

/// One immutable result from the canonical evidence and protocol read model.
final class CanonicalRecallLadderSnapshot {
  CanonicalRecallLadderSnapshot({
    required this.authorityVersion,
    required this.evidence,
    required List<RecallLadderObservation> observations,
    required this.protocol,
  }) : observations = List.unmodifiable(observations);

  static const String currentVersion = 'recall-authority-v1';

  final String authorityVersion;
  final RecommendationEvidence evidence;
  final List<RecallLadderObservation> observations;
  final RecallLadderProtocolLimits protocol;
}

/// Fully resolved immutable input to the pure domain policy.
final class ActiveRecallLadderInput {
  ActiveRecallLadderInput({
    required this.request,
    required this.snapshot,
    required Map<LessonMode, RecallLadderModeAvailability> modeAvailability,
  }) : modeAvailability = Map.unmodifiable(modeAvailability);

  final RecallLadderRequest request;
  final CanonicalRecallLadderSnapshot snapshot;
  final Map<LessonMode, RecallLadderModeAvailability> modeAvailability;
}

/// f15's deterministic, advisory active-recall sequence.
///
/// This policy consumes read references only and has no repository dependency.
/// Unknown versions and malformed authority data return a neutral typed
/// decision instead of guessing or routing to a screen.
final class ActiveRecallLadder {
  const ActiveRecallLadder({
    this.flashcardFirstPolicy = const FlashcardFirstRecommendationPolicy(),
  });

  static const String policyVersion = 'f15-v1';
  static const Duration maximumEvidenceAge = Duration(days: 30);

  final FlashcardFirstRecommendationPolicy flashcardFirstPolicy;

  static const List<_RecallLadderStep> _steps = <_RecallLadderStep>[
    _RecallLadderStep(
      modes: <LessonMode>[LessonMode.flashcard],
      qualifyingClasses: <EvidenceClass>{EvidenceClass.exposure},
      permittedClasses: <EvidenceClass>{EvidenceClass.exposure},
    ),
    _RecallLadderStep(
      modes: <LessonMode>[LessonMode.meaningQuiz, LessonMode.definitionQuiz],
      qualifyingClasses: <EvidenceClass>{EvidenceClass.recognition},
      permittedClasses: <EvidenceClass>{
        EvidenceClass.recognition,
        EvidenceClass.guidedPractice,
      },
    ),
    _RecallLadderStep(
      modes: <LessonMode>[LessonMode.matching],
      qualifyingClasses: <EvidenceClass>{EvidenceClass.recognition},
      permittedClasses: <EvidenceClass>{
        EvidenceClass.recognition,
        EvidenceClass.guidedPractice,
      },
    ),
    _RecallLadderStep(
      modes: <LessonMode>[LessonMode.cloze],
      qualifyingClasses: <EvidenceClass>{
        EvidenceClass.recognition,
        EvidenceClass.independentRecall,
      },
      permittedClasses: <EvidenceClass>{
        EvidenceClass.recognition,
        EvidenceClass.independentRecall,
        EvidenceClass.guidedPractice,
      },
    ),
    _RecallLadderStep(
      modes: <LessonMode>[LessonMode.typedRecall],
      qualifyingClasses: <EvidenceClass>{EvidenceClass.independentRecall},
      permittedClasses: <EvidenceClass>{
        EvidenceClass.independentRecall,
        EvidenceClass.guidedPractice,
      },
    ),
    _RecallLadderStep(
      modes: <LessonMode>[LessonMode.dictation],
      qualifyingClasses: <EvidenceClass>{EvidenceClass.independentRecall},
      permittedClasses: <EvidenceClass>{
        EvidenceClass.independentRecall,
        EvidenceClass.guidedPractice,
      },
    ),
    _RecallLadderStep(
      modes: <LessonMode>[LessonMode.speaking],
      qualifyingClasses: <EvidenceClass>{EvidenceClass.pronunciation},
      permittedClasses: <EvidenceClass>{EvidenceClass.pronunciation},
    ),
  ];

  static Set<LessonMode> get canonicalModes =>
      Set.unmodifiable(_steps.expand((step) => step.modes));

  RecommendationDecision recommend(ActiveRecallLadderInput input) {
    final request = input.request;
    final snapshot = input.snapshot;
    final evidence = _canonicalEvidence(snapshot.evidence);
    if (request.ladderVersion != policyVersion) {
      return _noRecommendation(
        evidence,
        RecommendationReasonCode.unsupportedLadderVersion,
      );
    }
    if (snapshot.authorityVersion !=
        CanonicalRecallLadderSnapshot.currentVersion) {
      return _noRecommendation(
        evidence,
        RecommendationReasonCode.unsupportedAuthorityVersion,
      );
    }
    if (!_validCanonicalIdentifier(request.ownerId) ||
        !_validCanonicalIdentifier(request.contentId)) {
      return _noRecommendation(
        evidence,
        RecommendationReasonCode.invalidLadderEvidence,
      );
    }
    if (evidence.ownerId != request.ownerId ||
        evidence.contentOwnerId != request.ownerId ||
        evidence.contentId != request.contentId ||
        snapshot.protocol.ownerId != request.ownerId) {
      return _noRecommendation(
        evidence,
        RecommendationReasonCode.crossOwnerEvidence,
      );
    }
    if (snapshot.protocol.version !=
        RecallLadderProtocolLimits.currentVersion) {
      return _noRecommendation(
        evidence,
        RecommendationReasonCode.unsupportedProtocolVersion,
      );
    }
    if (!_validProtocol(snapshot.protocol, evidence.evaluatedAtUtc)) {
      return _noRecommendation(
        evidence,
        RecommendationReasonCode.invalidLadderEvidence,
      );
    }
    final referenceFailure = _validateReadReferences(evidence);
    if (referenceFailure != null) {
      return _noRecommendation(evidence, referenceFailure);
    }

    final baseDecision = flashcardFirstPolicy.recommend(evidence);
    if (_isInvalidBaseDecision(baseDecision.reasonCode)) {
      return _noRecommendation(evidence, baseDecision.reasonCode);
    }

    final validation = _validateAndResolveProgress(
      evidence: evidence,
      observations: snapshot.observations,
    );
    if (validation.failureReason != null) {
      return _noRecommendation(evidence, validation.failureReason!);
    }
    if (evidence.isMastered) {
      return _noRecommendation(evidence, RecommendationReasonCode.masteredItem);
    }
    if (validation.completedStepCount == _steps.length) {
      return _noRecommendation(
        evidence,
        RecommendationReasonCode.recallLadderComplete,
      );
    }

    final stepIndex = validation.completedStepCount;
    final step = _steps[stepIndex];
    final protocolCandidates = step.modes
        .where(snapshot.protocol.allows)
        .toList(growable: false);
    if (protocolCandidates.isEmpty) {
      return _learnerChoice(
        input,
        evidence: evidence,
        reason: RecommendationReasonCode.protocolLockedStep,
        maximumStepIndex: stepIndex,
        excludedModes: step.modes.toSet(),
      );
    }

    if (step.modes.contains(LessonMode.speaking) &&
        !request.accessibility.speechInputAvailable) {
      final alternatives =
          <LessonMode>[
                LessonMode.typedRecall,
                if (request.accessibility.audioPlaybackAvailable)
                  LessonMode.dictation,
              ]
              .where(snapshot.protocol.allows)
              .where((mode) => _isAvailable(input, mode))
              .toList(growable: false);
      if (alternatives.isEmpty) {
        return _learnerChoice(
          input,
          evidence: evidence,
          reason: RecommendationReasonCode.accessibilityAlternativeRequired,
          maximumStepIndex: stepIndex - 1,
          excludedModes: const <LessonMode>{LessonMode.speaking},
        );
      }
      return _choiceOrNeutral(
        evidence,
        alternatives,
        RecommendationReasonCode.accessibilityAlternativeRequired,
      );
    }

    final accessibleCandidates = protocolCandidates
        .where(request.accessibility.allows)
        .toList(growable: false);
    final availableCandidates = accessibleCandidates
        .where((mode) => _isAvailable(input, mode))
        .toList(growable: false);
    if (availableCandidates.isEmpty) {
      return _learnerChoice(
        input,
        evidence: evidence,
        reason: RecommendationReasonCode.modeUnavailable,
        maximumStepIndex: stepIndex,
        excludedModes: step.modes.toSet(),
      );
    }

    final recommendedMode = availableCandidates.first;
    if (validation.lastObservedStepIndex == stepIndex) {
      return _learnerChoice(
        input,
        evidence: evidence,
        reason: RecommendationReasonCode.circularRecommendationPrevented,
        maximumStepIndex: stepIndex,
        excludedModes: step.modes.toSet(),
      );
    }
    return RecommendationDecision(
      policyVersion: policyVersion,
      ownerId: evidence.ownerId,
      contentId: evidence.contentId,
      action: RecommendationAction.lessonMode,
      reasonCode: RecommendationReasonCode.recallLadderNextStep,
      evidenceReferences: evidence.evidenceReferences,
      recommendedMode: recommendedMode,
    );
  }

  _RecallLadderProgress _validateAndResolveProgress({
    required RecommendationEvidence evidence,
    required List<RecallLadderObservation> observations,
  }) {
    if (evidence.isUnseen && observations.isNotEmpty) {
      return const _RecallLadderProgress.failed(
        RecommendationReasonCode.invalidLadderEvidence,
      );
    }
    final responseReferences = evidence.evidenceReferences
        .where(
          (reference) =>
              reference.source ==
              RecommendationEvidenceSource.responseEvidenceReadModel,
        )
        .toList(growable: false);
    if (responseReferences.length != observations.length) {
      return const _RecallLadderProgress.failed(
        RecommendationReasonCode.invalidEvidenceReference,
      );
    }

    final ordered = observations.toList(growable: false)
      ..sort((left, right) {
        final timeOrder = left.observedAtUtc.compareTo(right.observedAtUtc);
        if (timeOrder != 0) return timeOrder;
        final identityOrder = left.sourceEvidenceId.compareTo(
          right.sourceEvidenceId,
        );
        if (identityOrder != 0) return identityOrder;
        return left.evidenceReference.referenceId.compareTo(
          right.evidenceReference.referenceId,
        );
      });
    final seenReferenceIds = <String>{};
    final seenSourceEvidenceIds = <String>{};
    final completedSteps = List<bool>.filled(_steps.length, false);
    int? lastObservedStepIndex;
    for (final observation in ordered) {
      final reference = observation.evidenceReference;
      final referenceFailure = _validateResponseReference(
        evidence: evidence,
        observation: observation,
      );
      if (referenceFailure != null) {
        return _RecallLadderProgress.failed(referenceFailure);
      }
      if (!seenReferenceIds.add(reference.referenceId) ||
          !seenSourceEvidenceIds.add(observation.sourceEvidenceId) ||
          !responseReferences.any(
            (candidate) => _sameReference(candidate, reference),
          )) {
        return const _RecallLadderProgress.failed(
          RecommendationReasonCode.invalidEvidenceReference,
        );
      }

      final stepIndex = _steps.indexWhere(
        (step) => step.modes.contains(observation.mode),
      );
      if (stepIndex < 0 ||
          !_steps[stepIndex].permittedClasses.contains(
            observation.evidenceClass,
          )) {
        return const _RecallLadderProgress.failed(
          RecommendationReasonCode.invalidLadderEvidence,
        );
      }
      lastObservedStepIndex = stepIndex;
      final qualifies =
          observation.successful &&
          _steps[stepIndex].qualifyingClasses.contains(
            observation.evidenceClass,
          );
      if (qualifies) completedSteps[stepIndex] = true;
    }
    final firstIncomplete = completedSteps.indexOf(false);
    return _RecallLadderProgress(
      completedStepCount: firstIncomplete < 0 ? _steps.length : firstIncomplete,
      lastObservedStepIndex: lastObservedStepIndex,
    );
  }

  RecommendationReasonCode? _validateResponseReference({
    required RecommendationEvidence evidence,
    required RecallLadderObservation observation,
  }) {
    final reference = observation.evidenceReference;
    if (reference.ownerId != evidence.ownerId ||
        reference.contentId != evidence.contentId) {
      return RecommendationReasonCode.crossOwnerEvidence;
    }
    final sourceIdValid = LearningEvidenceContract.validSourceEvidenceId(
      observation.sourceEvidenceId,
    );
    final expectedReferenceId =
        'response:${observation.sourceEvidenceId}:${observation.mode.id}:'
        '${observation.evidenceClass.name}:'
        '${observation.successful ? 'success' : 'failure'}';
    final expectedVersion = 'response-v${observation.recordVersion}';
    if (reference.source !=
            RecommendationEvidenceSource.responseEvidenceReadModel ||
        !sourceIdValid ||
        observation.recordVersion < 1 ||
        reference.referenceId != expectedReferenceId ||
        reference.version != expectedVersion ||
        reference.capturedAtUtc != observation.observedAtUtc) {
      return RecommendationReasonCode.invalidEvidenceReference;
    }
    if (!observation.observedAtUtc.isUtc ||
        reference.capturedAtUtc.isAfter(evidence.evaluatedAtUtc)) {
      return RecommendationReasonCode.invalidEvidenceTime;
    }
    if (evidence.evaluatedAtUtc.difference(reference.capturedAtUtc) >
        maximumEvidenceAge) {
      return RecommendationReasonCode.staleEvidence;
    }
    return null;
  }

  bool _sameReference(
    RecommendationEvidenceReference left,
    RecommendationEvidenceReference right,
  ) =>
      left.source == right.source &&
      left.ownerId == right.ownerId &&
      left.contentId == right.contentId &&
      left.referenceId == right.referenceId &&
      left.version == right.version &&
      left.capturedAtUtc == right.capturedAtUtc;

  bool _isInvalidBaseDecision(RecommendationReasonCode reason) =>
      switch (reason) {
        RecommendationReasonCode.unseenItem ||
        RecommendationReasonCode.lowConfidence ||
        RecommendationReasonCode.masteredItem ||
        RecommendationReasonCode.confidenceSufficient => false,
        _ => true,
      };

  bool _isAvailable(ActiveRecallLadderInput input, LessonMode mode) =>
      input.modeAvailability[mode] == RecallLadderModeAvailability.available;

  RecommendationDecision _learnerChoice(
    ActiveRecallLadderInput input, {
    required RecommendationEvidence evidence,
    required RecommendationReasonCode reason,
    required int maximumStepIndex,
    required Set<LessonMode> excludedModes,
  }) {
    final choices = _steps
        .take(maximumStepIndex + 1)
        .expand((step) => step.modes)
        .where((mode) => !excludedModes.contains(mode))
        .where(input.snapshot.protocol.allows)
        .where(input.request.accessibility.allows)
        .where((mode) => _isAvailable(input, mode))
        .toList(growable: false);
    return _choiceOrNeutral(evidence, choices, reason);
  }

  bool _validProtocol(
    RecallLadderProtocolLimits protocol,
    DateTime evaluatedAtUtc,
  ) =>
      _validCanonicalIdentifier(protocol.ownerId) &&
      _validCanonicalIdentifier(protocol.assignmentId) &&
      protocol.capturedAtUtc.isUtc &&
      !protocol.capturedAtUtc.isAfter(evaluatedAtUtc);

  bool _validCanonicalIdentifier(String value) =>
      value.isNotEmpty && value == value.trim() && value.runes.length <= 256;

  RecommendationReasonCode? _validateReadReferences(
    RecommendationEvidence evidence,
  ) {
    final identities = <String>{};
    for (final reference in evidence.evidenceReferences) {
      if (!identities.add(
        '${reference.source.name}:${reference.referenceId}',
      )) {
        return RecommendationReasonCode.invalidEvidenceReference;
      }
      final validFormat = switch (reference.source) {
        RecommendationEvidenceSource.progressReadModel =>
          RegExp(r'^progress:\S+$').hasMatch(reference.referenceId) &&
              RegExp(r'^progress-v[1-9][0-9]*$').hasMatch(reference.version),
        RecommendationEvidenceSource.srsReadModel =>
          RegExp(r'^srs:\S+$').hasMatch(reference.referenceId) &&
              RegExp(r'^srs-v[1-9][0-9]*$').hasMatch(reference.version),
        RecommendationEvidenceSource.responseEvidenceReadModel =>
          reference.referenceId.startsWith('response:') &&
              RegExp(r'^response-v[1-9][0-9]*$').hasMatch(reference.version),
      };
      if (!validFormat) {
        return RecommendationReasonCode.invalidEvidenceReference;
      }
    }
    return null;
  }

  RecommendationEvidence _canonicalEvidence(RecommendationEvidence evidence) {
    final references = evidence.evidenceReferences.toList(growable: false)
      ..sort((left, right) {
        final timeOrder = left.capturedAtUtc.compareTo(right.capturedAtUtc);
        if (timeOrder != 0) return timeOrder;
        return left.referenceId.compareTo(right.referenceId);
      });
    return RecommendationEvidence(
      policyVersion: evidence.policyVersion,
      ownerId: evidence.ownerId,
      contentOwnerId: evidence.contentOwnerId,
      contentId: evidence.contentId,
      confidence: evidence.confidence,
      isUnseen: evidence.isUnseen,
      isMastered: evidence.isMastered,
      observedAtUtc: evidence.observedAtUtc,
      evaluatedAtUtc: evidence.evaluatedAtUtc,
      evidenceReferences: references,
    );
  }

  RecommendationDecision _choiceOrNeutral(
    RecommendationEvidence evidence,
    List<LessonMode> choices,
    RecommendationReasonCode reason,
  ) => RecommendationDecision(
    policyVersion: policyVersion,
    ownerId: evidence.ownerId,
    contentId: evidence.contentId,
    action: choices.isEmpty
        ? RecommendationAction.noRecommendation
        : RecommendationAction.learnerChoice,
    reasonCode: reason,
    evidenceReferences: evidence.evidenceReferences,
    learnerChoiceModes: choices,
  );

  RecommendationDecision _noRecommendation(
    RecommendationEvidence evidence,
    RecommendationReasonCode reason,
  ) => RecommendationDecision(
    policyVersion: policyVersion,
    ownerId: evidence.ownerId,
    contentId: evidence.contentId,
    action: RecommendationAction.noRecommendation,
    reasonCode: reason,
    evidenceReferences: evidence.evidenceReferences,
  );
}

final class _RecallLadderStep {
  const _RecallLadderStep({
    required this.modes,
    required this.qualifyingClasses,
    required this.permittedClasses,
  });

  final List<LessonMode> modes;
  final Set<EvidenceClass> qualifyingClasses;
  final Set<EvidenceClass> permittedClasses;
}

final class _RecallLadderProgress {
  const _RecallLadderProgress({
    required this.completedStepCount,
    required this.lastObservedStepIndex,
  }) : failureReason = null;

  const _RecallLadderProgress.failed(this.failureReason)
    : completedStepCount = 0,
      lastObservedStepIndex = null;

  final int completedStepCount;
  final int? lastObservedStepIndex;
  final RecommendationReasonCode? failureReason;
}
