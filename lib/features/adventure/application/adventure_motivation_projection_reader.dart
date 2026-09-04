import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';

enum AdventureProjectionReceiptState { pending, committed, notEligible }

enum AdventureMotivationProjectionRoute { learningEvidence, map, story }

/// Typed routing prevents non-learning Adventure interactions from being
/// disguised as unknown learning evidence.
final class AdventureMotivationProjectionRequest {
  const AdventureMotivationProjectionRequest.learningEvidence({
    required String evidenceId,
  }) : route = AdventureMotivationProjectionRoute.learningEvidence,
       routeId = evidenceId;

  const AdventureMotivationProjectionRequest.map({required String nodeId})
    : route = AdventureMotivationProjectionRoute.map,
      routeId = nodeId;

  const AdventureMotivationProjectionRequest.story({
    required String storyBeatId,
  }) : route = AdventureMotivationProjectionRoute.story,
       routeId = storyBeatId;

  final AdventureMotivationProjectionRoute route;
  final String routeId;
}

final class AdventureProjectionOutcome {
  const AdventureProjectionOutcome({
    required this.state,
    this.receiptId,
    this.displayCode,
  }) : assert(
         state != AdventureProjectionReceiptState.committed ||
             receiptId != null,
       ),
       assert(
         state != AdventureProjectionReceiptState.pending || receiptId == null,
       );

  final AdventureProjectionReceiptState state;
  final String? receiptId;
  final String? displayCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.name,
    'receiptId': receiptId,
    'displayCode': displayCode,
  };
}

final class AdventureAchievementReceipt {
  const AdventureAchievementReceipt({
    required this.receiptId,
    required this.achievementId,
  });

  final String receiptId;
  final String achievementId;
}

abstract interface class AdventureAchievementReceiptReader {
  Future<List<AdventureAchievementReceipt>> readForSourceEvent({
    required String ownerId,
    required String sourceEventId,
  });
}

/// Passive synchronization barrier. Implementations may wait for canonical
/// work already scheduled by Learning, but cannot schedule projection work.
abstract interface class AdventureProjectionReceiptBarrier {
  Future<void> waitForCanonicalProjection(String ownerId);
}

final class CallbackAdventureProjectionReceiptBarrier
    implements AdventureProjectionReceiptBarrier {
  const CallbackAdventureProjectionReceiptBarrier(this._wait);

  final Future<void> Function(String ownerId) _wait;

  @override
  Future<void> waitForCanonicalProjection(String ownerId) => _wait(ownerId);
}

final class AdventureMotivationSnapshot {
  const AdventureMotivationSnapshot({
    required this.sourceEvidenceId,
    required this.questOutcome,
    required this.streakOutcome,
    required this.rewardOutcome,
    required this.pendingProjection,
    this.achievementOutcomes = const <AdventureProjectionOutcome>[],
  });

  final String? sourceEvidenceId;
  final AdventureProjectionOutcome questOutcome;
  final AdventureProjectionOutcome streakOutcome;
  final AdventureProjectionOutcome rewardOutcome;
  final List<AdventureProjectionOutcome> achievementOutcomes;
  final bool pendingProjection;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceEvidenceId': sourceEvidenceId,
    'questOutcome': questOutcome.toJson(),
    'streakOutcome': streakOutcome.toJson(),
    'achievementOutcomes': achievementOutcomes
        .map((outcome) => outcome.toJson())
        .toList(growable: false),
    'rewardOutcome': rewardOutcome.toJson(),
    'pendingProjection': pendingProjection,
  };
}

abstract interface class AdventureMotivationProjectionReader {
  Future<AdventureMotivationSnapshot> read(
    AdventureMotivationProjectionRequest request,
  );

  Future<AdventureMotivationSnapshot> readForEvidence(String evidenceId);

  Future<List<AdventureMotivationSnapshot>> readForSession({
    required String ownerId,
    required String sessionId,
  });
}

final class DriftAdventureMotivationProjectionReader
    implements AdventureMotivationProjectionReader {
  const DriftAdventureMotivationProjectionReader({
    required this.learningReceipts,
    required this.achievements,
  });

  static const AdventureProjectionOutcome _pending = AdventureProjectionOutcome(
    state: AdventureProjectionReceiptState.pending,
  );
  static const AdventureProjectionOutcome _notEligible =
      AdventureProjectionOutcome(
        state: AdventureProjectionReceiptState.notEligible,
      );

  final LearningProjectionReceiptReader learningReceipts;
  final AdventureAchievementReceiptReader achievements;

  @override
  Future<AdventureMotivationSnapshot> read(
    AdventureMotivationProjectionRequest request,
  ) async {
    _requireRouteId(request.routeId);
    return switch (request.route) {
      AdventureMotivationProjectionRoute.learningEvidence => readForEvidence(
        request.routeId,
      ),
      AdventureMotivationProjectionRoute.map ||
      AdventureMotivationProjectionRoute.story => _noOp(null),
    };
  }

  @override
  Future<AdventureMotivationSnapshot> readForEvidence(String evidenceId) async {
    _requireRouteId(evidenceId);
    final source = await learningReceipts.readValidatedSourceForEvidence(
      evidenceId,
    );
    if (source == null || _excluded(source.evidenceClass)) {
      return _noOp(evidenceId);
    }

    final quest = await _readProjection(source, 'quest');
    final streak = await _readProjection(source, 'streak');
    final reward = await _readProjection(source, 'reward');
    final achievements = await this.achievements.readForSourceEvent(
      ownerId: source.ownerId,
      sourceEventId: evidenceId,
    );
    return AdventureMotivationSnapshot(
      sourceEvidenceId: evidenceId,
      questOutcome: quest,
      streakOutcome: streak,
      achievementOutcomes: _achievementOutcomes(achievements),
      rewardOutcome: reward,
      pendingProjection: <AdventureProjectionOutcome>[quest, streak, reward]
          .any(
            (outcome) =>
                outcome.state == AdventureProjectionReceiptState.pending,
          ),
    );
  }

  @override
  Future<List<AdventureMotivationSnapshot>> readForSession({
    required String ownerId,
    required String sessionId,
  }) async {
    _requireRouteId(ownerId);
    _requireRouteId(sessionId);
    final evidenceIds = await learningReceipts.listSessionEvidenceIds(
      ownerId: ownerId,
      sessionId: sessionId,
    );
    final snapshots = <AdventureMotivationSnapshot>[];
    for (final evidenceId in evidenceIds) {
      snapshots.add(await readForEvidence(evidenceId));
    }
    final sessionAchievements = await achievements.readForSourceEvent(
      ownerId: ownerId,
      sourceEventId: sessionId,
    );
    if (sessionAchievements.isNotEmpty) {
      snapshots.add(
        _noOp(
          null,
          achievementOutcomes: _achievementOutcomes(sessionAchievements),
        ),
      );
    }
    return List<AdventureMotivationSnapshot>.unmodifiable(snapshots);
  }

  List<AdventureProjectionOutcome> _achievementOutcomes(
    List<AdventureAchievementReceipt> receipts,
  ) => List<AdventureProjectionOutcome>.unmodifiable(
    receipts.map(
      (receipt) => AdventureProjectionOutcome(
        state: AdventureProjectionReceiptState.committed,
        receiptId: receipt.receiptId,
        displayCode: receipt.achievementId,
      ),
    ),
  );

  Future<AdventureProjectionOutcome> _readProjection(
    CanonicalLearningEvidenceSource source,
    String projection,
  ) async {
    final receipt = await learningReceipts.readProjectionReceipt(
      source: source,
      projection: projection,
      appliedVersion: LearningEvidenceContract.currentProjectionAppliedVersion,
    );
    if (receipt == null) return _pending;

    return switch (receipt.outcome) {
      CanonicalLearningProjectionReceiptOutcome.applied =>
        AdventureProjectionOutcome(
          state: AdventureProjectionReceiptState.committed,
          receiptId: receipt.receiptId,
        ),
      CanonicalLearningProjectionReceiptOutcome.notApplicable ||
      CanonicalLearningProjectionReceiptOutcome.blocked =>
        AdventureProjectionOutcome(
          state: AdventureProjectionReceiptState.notEligible,
          receiptId: receipt.receiptId,
          displayCode:
              receipt.reasonCode ?? receipt.result['reasonCode'] as String?,
        ),
    };
  }

  AdventureMotivationSnapshot _noOp(
    String? evidenceId, {
    List<AdventureProjectionOutcome> achievementOutcomes =
        const <AdventureProjectionOutcome>[],
  }) => AdventureMotivationSnapshot(
    sourceEvidenceId: evidenceId,
    questOutcome: _notEligible,
    streakOutcome: _notEligible,
    achievementOutcomes: achievementOutcomes,
    rewardOutcome: _notEligible,
    pendingProjection: false,
  );

  bool _excluded(EvidenceClass evidenceClass) =>
      evidenceClass == EvidenceClass.assessment ||
      evidenceClass == EvidenceClass.recreational;

  void _requireRouteId(String value) {
    if (!LearningEvidenceContract.validIdentifier(value)) {
      throw ArgumentError.value(value, 'routeId');
    }
  }
}
