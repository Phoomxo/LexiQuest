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
      if (pending.prerequisiteApplied == null) {
        // The prerequisite projection owns the same contiguous source prefix.
        // Do not let a later joined receipt advance reward beyond a gap.
        break;
      }
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
