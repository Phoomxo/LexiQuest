import '../../learning/domain/lesson_mode.dart';
import '../../preferences/domain/learner_preferences.dart';
import '../data/drift_recommendation_reader.dart';
import '../domain/active_recall_ladder.dart';
import '../domain/recommendation_models.dart';
import '../domain/recommendation_policy.dart';

typedef RecommendationUtcNow = DateTime Function();
typedef RecommendationActiveOwnerId = Future<String?> Function();

enum RecommendationEvidenceFreshness { current, stale, missing, corrupt }

enum RecommendationResultAvailability {
  recommended,
  neutralAlternatives,
  unavailable,
}

enum RecommendationProtocolConstraint { open, constrained, overrideDenied }

enum RecommendationPanelReason {
  weakEvidence,
  learnerPreference,
  learnerOverride,
  staleEvidence,
  missingEvidence,
  corruptEvidence,
  modeUnavailable,
  protocolLocked,
  canonicalAuthorityUnavailable,
  noEligibleActivity,
}

/// Typed f37 output consumed by the future f42 parent.
final class RecommendationPanelResult {
  RecommendationPanelResult._({
    required this.ownerId,
    required this.availability,
    required this.reason,
    required this.freshness,
    required this.protocolConstraint,
    required this.recommendedMode,
    required this.contentId,
    required List<LessonMode> alternatives,
    required this.learnerOverrideApplied,
  }) : alternatives = List<LessonMode>.unmodifiable(alternatives);

  factory RecommendationPanelResult.recommended({
    required String ownerId,
    required LessonMode mode,
    required RecommendationPanelReason reason,
    required RecommendationEvidenceFreshness freshness,
    required RecommendationProtocolConstraint protocolConstraint,
    required List<LessonMode> alternatives,
    String? contentId,
    bool learnerOverrideApplied = false,
  }) => RecommendationPanelResult._(
    ownerId: _canonicalIdentifier(ownerId, 'ownerId'),
    availability: RecommendationResultAvailability.recommended,
    reason: reason,
    freshness: freshness,
    protocolConstraint: protocolConstraint,
    recommendedMode: mode,
    contentId: contentId,
    alternatives: alternatives.where((candidate) => candidate != mode).toList(),
    learnerOverrideApplied: learnerOverrideApplied,
  );

  factory RecommendationPanelResult.neutral({
    required String ownerId,
    required RecommendationPanelReason reason,
    required RecommendationEvidenceFreshness freshness,
    required RecommendationProtocolConstraint protocolConstraint,
    required List<LessonMode> alternatives,
  }) => RecommendationPanelResult._(
    ownerId: _canonicalIdentifier(ownerId, 'ownerId'),
    availability: RecommendationResultAvailability.neutralAlternatives,
    reason: reason,
    freshness: freshness,
    protocolConstraint: protocolConstraint,
    recommendedMode: null,
    contentId: null,
    alternatives: alternatives,
    learnerOverrideApplied: false,
  );

  factory RecommendationPanelResult.unavailable({
    required String? ownerId,
    required RecommendationPanelReason reason,
    required RecommendationEvidenceFreshness freshness,
    required RecommendationProtocolConstraint protocolConstraint,
  }) => RecommendationPanelResult._(
    ownerId: ownerId == null ? null : _canonicalIdentifier(ownerId, 'ownerId'),
    availability: RecommendationResultAvailability.unavailable,
    reason: reason,
    freshness: freshness,
    protocolConstraint: protocolConstraint,
    recommendedMode: null,
    contentId: null,
    alternatives: const <LessonMode>[],
    learnerOverrideApplied: false,
  );

  final String? ownerId;
  final RecommendationResultAvailability availability;
  final RecommendationPanelReason reason;
  final RecommendationEvidenceFreshness freshness;
  final RecommendationProtocolConstraint protocolConstraint;
  final LessonMode? recommendedMode;
  final String? contentId;
  final List<LessonMode> alternatives;
  final bool learnerOverrideApplied;
}

final class RecommendationUseCases {
  RecommendationUseCases({
    required this.reader,
    required this.nowUtc,
    required this.timezoneId,
    required this.activeOwnerId,
    required Map<LessonMode, RecallLadderModeAvailability> modeAvailability,
  }) : _modeAvailability =
           Map<LessonMode, RecallLadderModeAvailability>.unmodifiable(
             modeAvailability,
           );

  final DriftRecommendationReader reader;
  final RecommendationUtcNow nowUtc;
  final String timezoneId;
  final RecommendationActiveOwnerId activeOwnerId;
  final Map<LessonMode, RecallLadderModeAvailability> _modeAvailability;

  Future<RecommendationPanelResult> load({
    RecallLadderProtocolLimits? protocol,
    LessonMode? learnerOverride,
  }) async {
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    _canonicalIdentifier(timezoneId, 'timezoneId');
    String? suppliedOwnerId;
    try {
      suppliedOwnerId = await activeOwnerId();
    } catch (_) {
      return RecommendationPanelResult.unavailable(
        ownerId: null,
        reason: RecommendationPanelReason.canonicalAuthorityUnavailable,
        freshness: RecommendationEvidenceFreshness.corrupt,
        protocolConstraint: RecommendationProtocolConstraint.open,
      );
    }
    if (suppliedOwnerId == null) {
      return RecommendationPanelResult.unavailable(
        ownerId: null,
        reason: RecommendationPanelReason.canonicalAuthorityUnavailable,
        freshness: RecommendationEvidenceFreshness.missing,
        protocolConstraint: RecommendationProtocolConstraint.open,
      );
    }
    String ownerId;
    try {
      ownerId = _canonicalIdentifier(suppliedOwnerId, 'activeOwnerId');
      if (!await reader.hasActiveOwner(ownerId)) {
        return RecommendationPanelResult.unavailable(
          ownerId: ownerId,
          reason: RecommendationPanelReason.canonicalAuthorityUnavailable,
          freshness: RecommendationEvidenceFreshness.missing,
          protocolConstraint: RecommendationProtocolConstraint.open,
        );
      }
    } catch (_) {
      return RecommendationPanelResult.unavailable(
        ownerId: null,
        reason: RecommendationPanelReason.canonicalAuthorityUnavailable,
        freshness: RecommendationEvidenceFreshness.corrupt,
        protocolConstraint: RecommendationProtocolConstraint.open,
      );
    }
    if (protocol != null &&
        (protocol.ownerId != ownerId ||
            protocol.version != RecallLadderProtocolLimits.currentVersion ||
            protocol.assignmentId.isEmpty ||
            protocol.assignmentId.trim() != protocol.assignmentId ||
            protocol.assignmentId.runes.length > 256 ||
            !protocol.capturedAtUtc.isUtc ||
            protocol.capturedAtUtc.millisecondsSinceEpoch < 0 ||
            protocol.capturedAtUtc.isAfter(now))) {
      return RecommendationPanelResult.unavailable(
        ownerId: ownerId,
        reason: RecommendationPanelReason.protocolLocked,
        freshness: RecommendationEvidenceFreshness.corrupt,
        protocolConstraint: RecommendationProtocolConstraint.overrideDenied,
      );
    }

    final safeModes = _safeModes(protocol: protocol);
    if (!_canonicalModeOrder.any(_isAvailable)) {
      return RecommendationPanelResult.unavailable(
        ownerId: ownerId,
        reason: RecommendationPanelReason.noEligibleActivity,
        freshness: RecommendationEvidenceFreshness.missing,
        protocolConstraint: _protocolState(protocol),
      );
    }
    if (safeModes.isEmpty) {
      return RecommendationPanelResult.unavailable(
        ownerId: ownerId,
        reason: protocol != null
            ? RecommendationPanelReason.protocolLocked
            : RecommendationPanelReason.noEligibleActivity,
        freshness: RecommendationEvidenceFreshness.missing,
        protocolConstraint: _protocolState(protocol),
      );
    }

    RecommendationReadModel snapshot;
    try {
      snapshot = await reader.load(
        ownerId: ownerId,
        nowUtc: now,
        timezoneId: timezoneId,
      );
    } on FormatException {
      return _neutral(
        ownerId: ownerId,
        reason: RecommendationPanelReason.corruptEvidence,
        freshness: RecommendationEvidenceFreshness.corrupt,
        protocol: protocol,
        alternatives: safeModes,
      );
    } on LearnerPreferencesValidationFailure {
      return _neutral(
        ownerId: ownerId,
        reason: RecommendationPanelReason.corruptEvidence,
        freshness: RecommendationEvidenceFreshness.corrupt,
        protocol: protocol,
        alternatives: safeModes,
      );
    } catch (_) {
      return RecommendationPanelResult.unavailable(
        ownerId: ownerId,
        reason: RecommendationPanelReason.canonicalAuthorityUnavailable,
        freshness: RecommendationEvidenceFreshness.corrupt,
        protocolConstraint: _protocolState(protocol),
      );
    }
    if (snapshot.ownerId != ownerId ||
        snapshot.profile.ownerId != ownerId ||
        snapshot.preferences.ownerId != ownerId) {
      return _neutral(
        ownerId: ownerId,
        reason: RecommendationPanelReason.corruptEvidence,
        freshness: RecommendationEvidenceFreshness.corrupt,
        protocol: protocol,
        alternatives: safeModes,
      );
    }

    final orderedSafeModes = _orderedModes(
      safeModes,
      snapshot.preferences.activityPreference,
    );
    final freshness = _freshness(snapshot, now);

    if (learnerOverride != null) {
      if (protocol != null && !protocol.allows(learnerOverride)) {
        return _neutral(
          ownerId: ownerId,
          reason: RecommendationPanelReason.protocolLocked,
          freshness: freshness,
          protocol: protocol,
          alternatives: orderedSafeModes,
          overrideDenied: true,
        );
      }
      if (!_isAvailable(learnerOverride)) {
        return _neutral(
          ownerId: ownerId,
          reason: RecommendationPanelReason.modeUnavailable,
          freshness: freshness,
          protocol: protocol,
          alternatives: orderedSafeModes,
        );
      }
      return RecommendationPanelResult.recommended(
        ownerId: ownerId,
        mode: learnerOverride,
        reason: RecommendationPanelReason.learnerOverride,
        freshness: freshness,
        protocolConstraint: _protocolState(protocol),
        alternatives: orderedSafeModes,
        learnerOverrideApplied: true,
      );
    }

    if (freshness == RecommendationEvidenceFreshness.corrupt) {
      return _neutral(
        ownerId: ownerId,
        reason: RecommendationPanelReason.corruptEvidence,
        freshness: freshness,
        protocol: protocol,
        alternatives: orderedSafeModes,
      );
    }
    if (freshness == RecommendationEvidenceFreshness.stale) {
      return _neutral(
        ownerId: ownerId,
        reason: RecommendationPanelReason.staleEvidence,
        freshness: freshness,
        protocol: protocol,
        alternatives: orderedSafeModes,
      );
    }
    if (freshness == RecommendationEvidenceFreshness.missing) {
      return _neutral(
        ownerId: ownerId,
        reason: RecommendationPanelReason.missingEvidence,
        freshness: freshness,
        protocol: protocol,
        alternatives: orderedSafeModes,
      );
    }

    final candidate = snapshot.decisions
        .where(
          (decision) =>
              decision.action == RecommendationAction.flashcardPreparation &&
              (decision.reasonCode == RecommendationReasonCode.unseenItem ||
                  decision.reasonCode ==
                      RecommendationReasonCode.lowConfidence),
        )
        .firstOrNull;
    if (candidate != null) {
      if (!_isAvailable(LessonMode.flashcard)) {
        return _neutral(
          ownerId: ownerId,
          reason: RecommendationPanelReason.modeUnavailable,
          freshness: freshness,
          protocol: protocol,
          alternatives: orderedSafeModes,
        );
      }
      if (protocol != null && !protocol.allows(LessonMode.flashcard)) {
        return _neutral(
          ownerId: ownerId,
          reason: RecommendationPanelReason.protocolLocked,
          freshness: freshness,
          protocol: protocol,
          alternatives: orderedSafeModes,
        );
      }
      return RecommendationPanelResult.recommended(
        ownerId: ownerId,
        mode: LessonMode.flashcard,
        contentId: candidate.contentId,
        reason: RecommendationPanelReason.weakEvidence,
        freshness: freshness,
        protocolConstraint: _protocolState(protocol),
        alternatives: orderedSafeModes,
      );
    }

    return RecommendationPanelResult.recommended(
      ownerId: ownerId,
      mode: orderedSafeModes.first,
      reason: RecommendationPanelReason.learnerPreference,
      freshness: freshness,
      protocolConstraint: _protocolState(protocol),
      alternatives: orderedSafeModes,
    );
  }

  RecommendationEvidenceFreshness _freshness(
    RecommendationReadModel snapshot,
    DateTime now,
  ) {
    for (final decision in snapshot.decisions) {
      switch (decision.reasonCode) {
        case RecommendationReasonCode.staleEvidence:
          return RecommendationEvidenceFreshness.stale;
        case RecommendationReasonCode.invalidEvidenceTime:
        case RecommendationReasonCode.invalidEvidenceReference:
        case RecommendationReasonCode.invalidMasteryEvidence:
        case RecommendationReasonCode.crossOwnerEvidence:
        case RecommendationReasonCode.invalidConfidence:
        case RecommendationReasonCode.missingConfidence:
        case RecommendationReasonCode.unsupportedPolicyVersion:
          return RecommendationEvidenceFreshness.corrupt;
        default:
          break;
      }
    }
    final latest = snapshot.latestPracticeEvidenceAtUtc;
    if (latest == null) return RecommendationEvidenceFreshness.missing;
    if (!latest.isUtc || latest.isAfter(now)) {
      return RecommendationEvidenceFreshness.corrupt;
    }
    if (now.difference(latest) >
        FlashcardFirstRecommendationPolicy.maximumEvidenceAge) {
      return RecommendationEvidenceFreshness.stale;
    }
    return RecommendationEvidenceFreshness.current;
  }

  List<LessonMode> _safeModes({
    required RecallLadderProtocolLimits? protocol,
  }) => _canonicalModeOrder
      .where(_isAvailable)
      .where((mode) => protocol?.allows(mode) ?? true)
      .toList(growable: false);

  bool _isAvailable(LessonMode mode) =>
      _modeAvailability[mode] == RecallLadderModeAvailability.available;

  List<LessonMode> _orderedModes(
    List<LessonMode> safeModes,
    LearnerActivityPreference preference,
  ) {
    final preferred = switch (preference) {
      LearnerActivityPreference.mixedPractice => const <LessonMode>[],
      LearnerActivityPreference.quiz => const <LessonMode>[
        LessonMode.meaningQuiz,
        LessonMode.definitionQuiz,
      ],
      LearnerActivityPreference.speaking => const <LessonMode>[
        LessonMode.speaking,
      ],
      LearnerActivityPreference.reading => const <LessonMode>[
        LessonMode.cefrReading,
        LessonMode.associativeReading,
      ],
      LearnerActivityPreference.vocabulary => const <LessonMode>[
        LessonMode.flashcard,
        LessonMode.typedRecall,
      ],
    };
    return <LessonMode>[
      ...preferred.where(safeModes.contains),
      ...safeModes.where((mode) => !preferred.contains(mode)),
    ];
  }

  RecommendationPanelResult _neutral({
    required String ownerId,
    required RecommendationPanelReason reason,
    required RecommendationEvidenceFreshness freshness,
    required RecallLadderProtocolLimits? protocol,
    required List<LessonMode> alternatives,
    bool overrideDenied = false,
  }) => alternatives.isEmpty
      ? RecommendationPanelResult.unavailable(
          ownerId: ownerId,
          reason: RecommendationPanelReason.noEligibleActivity,
          freshness: freshness,
          protocolConstraint: _protocolState(protocol),
        )
      : RecommendationPanelResult.neutral(
          ownerId: ownerId,
          reason: reason,
          freshness: freshness,
          protocolConstraint: overrideDenied
              ? RecommendationProtocolConstraint.overrideDenied
              : _protocolState(protocol),
          alternatives: alternatives,
        );

  RecommendationProtocolConstraint _protocolState(
    RecallLadderProtocolLimits? protocol,
  ) => protocol != null
      ? RecommendationProtocolConstraint.constrained
      : RecommendationProtocolConstraint.open;
}

const List<LessonMode> _canonicalModeOrder = <LessonMode>[
  LessonMode.flashcard,
  LessonMode.meaningQuiz,
  LessonMode.typedRecall,
  LessonMode.definitionQuiz,
  LessonMode.cloze,
  LessonMode.matching,
  LessonMode.dictation,
  LessonMode.speaking,
  LessonMode.shadowing,
  LessonMode.cefrReading,
  LessonMode.associativeReading,
  LessonMode.sentenceScramble,
  LessonMode.wordScramble,
  LessonMode.handwritingScratchpad,
];

String _canonicalIdentifier(String value, String name) {
  if (value.isEmpty || value.trim() != value || value.runes.length > 256) {
    throw ArgumentError.value(value, name, 'must be canonical bounded text');
  }
  return value;
}
