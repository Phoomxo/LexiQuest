import '../../learning/application/lesson_mode_registry.dart';
import '../../learning/domain/lesson_mode.dart';
import '../domain/active_recall_ladder.dart';
import '../domain/recommendation_models.dart';

/// Read-only join over canonical response evidence, mastery/SRS projections,
/// and the persisted protocol assignment for one owner/content pair.
abstract interface class RecallLadderCanonicalAuthority {
  Future<CanonicalRecallLadderSnapshot?> load({
    required String ownerId,
    required String contentId,
  });
}

/// Read-only composition boundary for f15.
///
/// Runtime state and the typed adapter registry are resolved into immutable
/// availability facts before the pure ladder policy runs. This class exposes
/// no progress, SRS, assignment, cohort, or reward writer.
final class RecallLadderUseCases {
  RecallLadderUseCases({
    required this.authority,
    required this.registry,
    required Set<LessonMode> liveEnabledModes,
    this.policy = const ActiveRecallLadder(),
  }) : _liveEnabledModes = Set.unmodifiable(liveEnabledModes);

  final RecallLadderCanonicalAuthority authority;
  final LessonModeRegistry registry;
  final Set<LessonMode> _liveEnabledModes;
  final ActiveRecallLadder policy;

  Future<RecommendationDecision> recommend(RecallLadderRequest request) async {
    CanonicalRecallLadderSnapshot? snapshot;
    try {
      snapshot = await authority.load(
        ownerId: request.ownerId,
        contentId: request.contentId,
      );
    } catch (_) {
      return _authorityUnavailable(request);
    }
    if (snapshot == null) return _authorityUnavailable(request);

    final availability = <LessonMode, RecallLadderModeAvailability>{};
    for (final mode in ActiveRecallLadder.canonicalModes) {
      final registration = registry.find(mode);
      availability[mode] = registration == null
          ? RecallLadderModeAvailability.missing
          : !registration.isDeliverable
          ? RecallLadderModeAvailability.implementedOff
          : !_liveEnabledModes.contains(mode)
          ? RecallLadderModeAvailability.liveOff
          : RecallLadderModeAvailability.available;
    }
    return policy.recommend(
      ActiveRecallLadderInput(
        request: request,
        snapshot: snapshot,
        modeAvailability: availability,
      ),
    );
  }

  RecommendationDecision _authorityUnavailable(RecallLadderRequest request) =>
      RecommendationDecision(
        policyVersion: ActiveRecallLadder.policyVersion,
        ownerId: request.ownerId,
        contentId: request.contentId,
        action: RecommendationAction.noRecommendation,
        reasonCode: RecommendationReasonCode.canonicalAuthorityUnavailable,
        evidenceReferences: const <RecommendationEvidenceReference>[],
      );
}
