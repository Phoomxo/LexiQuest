import '../../../data/local/app_database.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../data/drift_learning_event_store.dart';

enum LearningProjectionOutcome { applied, notApplicable }

final class LearningProjectionResult {
  const LearningProjectionResult.applied({
    this.payload = const <String, dynamic>{},
  }) : outcome = LearningProjectionOutcome.applied;

  const LearningProjectionResult.notApplicable({
    this.payload = const <String, dynamic>{},
  }) : outcome = LearningProjectionOutcome.notApplicable;

  final LearningProjectionOutcome outcome;
  final Map<String, dynamic> payload;
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
  }) : _events = DriftLearningEventStore(database);

  static const int appliedVersion = 1;

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
      try {
        final outcome = await sink(pending.event);
        await _events.markProjectionOutcome(
          source: pending.event,
          projection: projection,
          appliedVersion: appliedVersion,
          applied: outcome.outcome == LearningProjectionOutcome.applied,
          result: outcome.payload,
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
      try {
        final outcome = pending.prerequisiteApplied == true
            ? await sink(pending.event, pending.prerequisitePayload)
            : const LearningProjectionResult.notApplicable();
        await _events.markProjectionOutcome(
          source: pending.event,
          projection: 'reward',
          appliedVersion: appliedVersion,
          applied: outcome.outcome == LearningProjectionOutcome.applied,
          result: outcome.payload,
        );
      } catch (_) {
        break;
      }
    }
  }
}

/// Coalesces fixed reconciliation batches without blocking answer/startup paths.
final class LearningReconciliationScheduler {
  LearningReconciliationScheduler(this._reconciler);

  final LearningSideEffectReconciler _reconciler;
  final Set<String> _pendingOwners = <String>{};
  Future<void>? _worker;
  bool _disposed = false;

  void request(String ownerId) {
    if (_disposed) return;
    _pendingOwners.add(ownerId);
    _worker ??= _run();
  }

  Future<void> drain() async {
    while (_worker != null) {
      await _worker;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _pendingOwners.clear();
    await drain();
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
