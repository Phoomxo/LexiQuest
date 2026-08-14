import '../../../data/local/app_database.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../data/drift_learning_event_store.dart';
import '../domain/evidence_eligibility_policy.dart';

final class LearningProjectionResult {
  const LearningProjectionResult.applied({
    this.payload = const <String, dynamic>{},
  }) : outcome = LearningProjectionOutcome.applied,
       reasonCode = null;

  const LearningProjectionResult.notApplicable({
    this.payload = const <String, dynamic>{},
  }) : outcome = LearningProjectionOutcome.notApplicable,
       reasonCode = null;

  const LearningProjectionResult.blocked({
    required this.reasonCode,
    this.payload = const <String, dynamic>{},
  }) : outcome = LearningProjectionOutcome.blocked;

  final LearningProjectionOutcome outcome;
  final Map<String, dynamic> payload;
  final String? reasonCode;
}

typedef LearningProjectionSink =
    Future<LearningProjectionResult> Function(EventEnvelopeV2 event);
typedef LearningRewardProjectionSink =
    Future<LearningProjectionResult> Function(
      EventEnvelopeV2 event,
      Map<String, dynamic> questResult,
    );

final class LearningSideEffectReconciler {
  LearningSideEffectReconciler(
    AppDatabase database, {
    this.questSink,
    this.streakSink,
    this.rewardSink,
    this.pendingBatchSize = 50,
    EvidenceEligibilityPolicy evidencePolicy =
        const EvidenceEligibilityPolicySet(),
    EvidencePolicyRolloutModeProvider rolloutModeProvider =
        const ContextEvidencePolicyRolloutModeProvider(),
  }) : _events = DriftLearningEventStore(
         database,
         evidencePolicy: evidencePolicy,
         rolloutModeProvider: rolloutModeProvider,
       );

  static const int appliedVersion =
      DriftLearningEventStore.appliedProjectionVersion;

  final DriftLearningEventStore _events;
  final LearningProjectionSink? questSink;
  final LearningProjectionSink? streakSink;
  final LearningRewardProjectionSink? rewardSink;
  final int pendingBatchSize;

  Future<void> reconcileOwner(String ownerId) async {
    await _applyPending(ownerId, 'quest', questSink);
    await _applyPending(ownerId, 'streak', streakSink);
    await _applyRewardPending(ownerId);
  }

  Future<void> _applyPending(
    String ownerId,
    String projection,
    LearningProjectionSink? sink,
  ) async {
    if (sink == null) return;
    final events = await _events.listPendingProjectionEvents(
      ownerId: ownerId,
      projection: projection,
      appliedVersion: appliedVersion,
      limit: pendingBatchSize,
    );
    for (final pending in events) {
      final resolution = await _events.resolveEvidenceForSource(pending.event);
      final evidence = resolution.evidence;
      if (evidence == null) {
        await _events.markProjectionOutcome(
          source: pending.event,
          projection: projection,
          appliedVersion: appliedVersion,
          outcome: LearningProjectionOutcome.blocked,
          reasonCode: resolution.reasonCode!,
        );
        continue;
      }
      final policyProjection = _policyProjection(projection);
      final decision = evidence.decisionSet.decisionFor(policyProjection);
      final decisionPayload = _decisionPayload(decision);
      late final LearningProjectionReceipt? v1Receipt;
      try {
        v1Receipt = await _events.readProjectionReceipt(
          sourceEventId: pending.event.eventId,
          projection: projection,
          appliedVersion: 1,
        );
      } on StateError {
        await _events.markProjectionOutcome(
          source: pending.event,
          projection: projection,
          appliedVersion: appliedVersion,
          outcome: LearningProjectionOutcome.blocked,
          reasonCode: 'invalidV1Receipt',
          decision: decisionPayload,
        );
        continue;
      }
      if (v1Receipt != null) {
        if (v1Receipt.outcome == LearningProjectionOutcome.blocked) {
          await _events.markProjectionOutcome(
            source: pending.event,
            projection: projection,
            appliedVersion: appliedVersion,
            outcome: LearningProjectionOutcome.blocked,
            reasonCode: 'invalidV1Receipt',
            decision: decisionPayload,
          );
        } else {
          await _events.markProjectionOutcome(
            source: pending.event,
            projection: projection,
            appliedVersion: appliedVersion,
            outcome: v1Receipt.outcome,
            result: v1Receipt.result,
            bridgedFromVersion: 1,
            decision: decisionPayload,
          );
        }
        continue;
      }
      if (!evidence.decisionSet.allows(policyProjection)) {
        await _events.markProjectionOutcome(
          source: pending.event,
          projection: projection,
          appliedVersion: appliedVersion,
          outcome: LearningProjectionOutcome.notApplicable,
          result: const <String, dynamic>{'reasonCode': 'evidenceIneligible'},
          decision: decisionPayload,
        );
        continue;
      }
      try {
        final outcome = await sink(pending.event);
        await _events.markProjectionOutcome(
          source: pending.event,
          projection: projection,
          appliedVersion: appliedVersion,
          outcome: outcome.outcome,
          result: outcome.payload,
          reasonCode: outcome.reasonCode,
          decision: decisionPayload,
        );
      } catch (_) {
        // Preserve chronological ordering: the next event cannot overtake it.
        break;
      }
    }
  }

  Future<void> _applyRewardPending(String ownerId) async {
    final sink = rewardSink;
    if (sink == null) return;
    final events = await _events.listPendingProjectionEvents(
      ownerId: ownerId,
      projection: 'reward',
      appliedVersion: appliedVersion,
      limit: pendingBatchSize,
      prerequisiteProjection: 'quest',
    );
    for (final pending in events) {
      final resolution = await _events.resolveEvidenceForSource(pending.event);
      final evidence = resolution.evidence;
      if (evidence == null) {
        await _events.markProjectionOutcome(
          source: pending.event,
          projection: 'reward',
          appliedVersion: appliedVersion,
          outcome: LearningProjectionOutcome.blocked,
          reasonCode: resolution.reasonCode!,
        );
        continue;
      }
      if (pending.prerequisiteApplied == null) {
        // The prerequisite projection owns the same contiguous source prefix.
        // Do not let a later joined receipt advance reward beyond a gap.
        break;
      }
      final decision = evidence.decisionSet.decisionFor(LearningProjection.xp);
      final decisionPayload = _decisionPayload(decision);
      late final LearningProjectionReceipt? v1Receipt;
      try {
        v1Receipt = await _events.readProjectionReceipt(
          sourceEventId: pending.event.eventId,
          projection: 'reward',
          appliedVersion: 1,
        );
      } on StateError {
        await _events.markProjectionOutcome(
          source: pending.event,
          projection: 'reward',
          appliedVersion: appliedVersion,
          outcome: LearningProjectionOutcome.blocked,
          reasonCode: 'invalidV1Receipt',
          decision: decisionPayload,
        );
        continue;
      }
      if (v1Receipt != null) {
        if (v1Receipt.outcome == LearningProjectionOutcome.blocked) {
          await _events.markProjectionOutcome(
            source: pending.event,
            projection: 'reward',
            appliedVersion: appliedVersion,
            outcome: LearningProjectionOutcome.blocked,
            reasonCode: 'invalidV1Receipt',
            decision: decisionPayload,
          );
        } else if (v1Receipt.outcome == LearningProjectionOutcome.applied &&
            pending.prerequisiteApplied != true) {
          await _events.markProjectionOutcome(
            source: pending.event,
            projection: 'reward',
            appliedVersion: appliedVersion,
            outcome: LearningProjectionOutcome.blocked,
            reasonCode: 'rewardV1AppliedWithoutQuestPrerequisite',
            decision: decisionPayload,
          );
        } else {
          await _events.markProjectionOutcome(
            source: pending.event,
            projection: 'reward',
            appliedVersion: appliedVersion,
            outcome: v1Receipt.outcome,
            result: v1Receipt.result,
            bridgedFromVersion: 1,
            decision: decisionPayload,
          );
        }
        continue;
      }
      if (!evidence.decisionSet.allows(LearningProjection.xp) ||
          pending.prerequisiteApplied == false) {
        await _events.markProjectionOutcome(
          source: pending.event,
          projection: 'reward',
          appliedVersion: appliedVersion,
          outcome: LearningProjectionOutcome.notApplicable,
          result: <String, dynamic>{
            'reasonCode': evidence.decisionSet.allows(LearningProjection.xp)
                ? 'questPrerequisiteNotApplied'
                : 'evidenceIneligible',
          },
          decision: decisionPayload,
        );
        continue;
      }
      try {
        final outcome = await sink(pending.event, pending.prerequisitePayload);
        await _events.markProjectionOutcome(
          source: pending.event,
          projection: 'reward',
          appliedVersion: appliedVersion,
          outcome: outcome.outcome,
          result: outcome.payload,
          reasonCode: outcome.reasonCode,
          decision: decisionPayload,
        );
      } catch (_) {
        break;
      }
    }
  }

  LearningProjection _policyProjection(String projection) =>
      switch (projection) {
        'quest' => LearningProjection.quest,
        'streak' => LearningProjection.streak,
        'reward' => LearningProjection.xp,
        _ => throw StateError('unsupported learning projection $projection'),
      };

  Map<String, dynamic> _decisionPayload(
    LearningEvidenceProjectionDecisionRecord decision,
  ) => decision.toJson().cast<String, dynamic>();
}

/// Coalesces fixed reconciliation batches without blocking answer/startup paths.
final class LearningReconciliationScheduler {
  LearningReconciliationScheduler(this._reconciler);

  final LearningSideEffectReconciler _reconciler;
  final Set<String> _pendingOwners = <String>{};
  final Set<String> _pausedOwners = <String>{};
  final Set<String> _bufferedPausedOwners = <String>{};
  final Map<String, String> _ownerRedirects = <String, String>{};
  Future<void>? _worker;
  bool _disposed = false;

  void request(String ownerId) {
    if (_disposed) return;
    final canonicalOwner = _redirectedOwner(ownerId);
    if (_pausedOwners.contains(ownerId)) {
      _bufferedPausedOwners.add(ownerId);
      return;
    }
    _pendingOwners.add(canonicalOwner);
    _worker ??= _run();
  }

  /// Serializes an owner identity transition with reconciliation. Existing
  /// source work drains first, requests arriving during the database move are
  /// buffered, and one target replay is always scheduled after a successful
  /// bind/merge.
  Future<T> coordinateOwnerChange<T>(
    String sourceOwnerId,
    Future<T> Function() operation,
    String Function(T result) targetOwnerId,
  ) async {
    if (_disposed) return operation();
    _pausedOwners.add(sourceOwnerId);
    await drain();
    try {
      final result = await operation();
      final target = targetOwnerId(result);
      if (target != sourceOwnerId) {
        _ownerRedirects[sourceOwnerId] = target;
      }
      _pausedOwners.remove(sourceOwnerId);
      _bufferedPausedOwners.remove(sourceOwnerId);
      _pendingOwners.remove(sourceOwnerId);
      request(target);
      return result;
    } catch (_) {
      _pausedOwners.remove(sourceOwnerId);
      final retrySource = _bufferedPausedOwners.remove(sourceOwnerId);
      if (retrySource) request(sourceOwnerId);
      rethrow;
    }
  }

  Future<void> drain() async {
    while (_worker != null) {
      await _worker;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _pendingOwners.clear();
    _bufferedPausedOwners.clear();
    await drain();
  }

  String _redirectedOwner(String ownerId) {
    var current = ownerId;
    final visited = <String>{};
    while (visited.add(current)) {
      final next = _ownerRedirects[current];
      if (next == null || next == current) return current;
      current = next;
    }
    return current;
  }

  Future<void> _run() async {
    try {
      while (_pendingOwners.isNotEmpty) {
        final owner = _pendingOwners.first;
        _pendingOwners.remove(owner);
        try {
          await _reconciler.reconcileOwner(owner);
        } catch (_) {
          // A later lifecycle/answer request retries the same durable batch.
        }
      }
    } finally {
      _worker = null;
      if (!_disposed && _pendingOwners.isNotEmpty) {
        _worker = _run();
      }
    }
  }
}
