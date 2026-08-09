import '../../../data/local/app_database.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../data/drift_learning_event_store.dart';

enum LearningProjectionOutcome { applied, notApplicable }

typedef LearningProjectionSink =
    Future<LearningProjectionOutcome> Function(EventEnvelopeV2 event);

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
  final LearningProjectionSink? rewardSink;
  final int pendingBatchSize;

  Future<void> reconcileOwner(String ownerId) async {
    await _applyPending(ownerId, 'quest', questSink);
    await _applyPending(ownerId, 'streak', streakSink);
    await _applyPending(
      ownerId,
      'reward',
      rewardSink,
      requireQuestApplied: questSink != null,
    );
  }

  Future<void> _applyPending(
    String ownerId,
    String projection,
    LearningProjectionSink? sink, {
    bool requireQuestApplied = false,
  }) async {
    if (sink == null) return;
    final events = await _events.listPendingProjectionEvents(
      ownerId: ownerId,
      projection: projection,
      appliedVersion: appliedVersion,
      limit: pendingBatchSize,
      requireQuestApplied: requireQuestApplied,
    );
    for (final event in events) {
      try {
        final outcome = await sink(event);
        await _events.markProjectionOutcome(
          source: event,
          projection: projection,
          appliedVersion: appliedVersion,
          applied: outcome == LearningProjectionOutcome.applied,
        );
      } catch (_) {
        // Preserve chronological ordering: the next event cannot overtake it.
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
