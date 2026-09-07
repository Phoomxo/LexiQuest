import '../../application/current_activity_evidence.dart';
import '../../application/learning_use_cases.dart';
import '../../domain/learning_repository.dart';
import '../../../review/application/pair_review_deferral.dart';
import '../../../review/domain/review_queue_item.dart';
import 'pair_matching_atomic_start.dart';
import 'pair_matching_session_coordinator.dart';

/// A route-owned disposition of an accepted configured Pair that cannot attach
/// for ordinary interaction. It exposes no commands, capture or running clock.
/// Existing committed work uses the same coordinator and canonical receipts.
final class PairMatchingUnavailableSession {
  PairMatchingUnavailableSession({
    required this.operation,
    required this.learning,
    required this.requireOwner,
  });

  final PairMatchingStartOperation operation;
  final LearningUseCases learning;
  final Future<String> Function() requireOwner;
  PairMatchingSessionCoordinator? _coordinator;
  DateTime? _cutoff;
  String? _owner;
  bool _busy = false, _disposed = false, _retiring = false;

  Future<void> _checkOwner() async {
    if (_disposed) throw StateError('Pair disposition is disposed');
    final owner = await requireOwner();
    _owner ??= owner;
    if (_owner != owner) throw StateError('Pair disposition owner changed');
  }

  Future<PairAcceptedDispositionSnapshot> _inspect() async {
    await _checkOwner();
    final result = await learning.inspectPairDisposition(
      ownerId: _owner!,
      startOperation: operation.stableSerialization,
    );
    await _checkOwner();
    return result;
  }

  Future<PairMatchingSessionCoordinator> _coordinatorForRecovery() async {
    return _coordinator ??= await PairMatchingSessionCoordinator.restore(
      operation: operation,
      learning: learning,
      evidence: CurrentActivityEvidenceAdapter(learning: learning),
      activeOwnerId: () => _disposed ? null : _owner,
      monotonicMicros: () => 0,
      runAdmittedOperation: (_) async =>
          throw StateError('Unavailable Pair is read only'),
      runRecoveryOperation: (action) async {
        await _checkOwner();
        await action();
        await _checkOwner();
      },
      completeSession: (close) => learning.completeUnavailablePairSession(
        ownerId: _owner!,
        startOperation: operation.stableSerialization,
        completedAtUtc: close.completedAtUtc,
      ),
    );
  }

  Future<PairAcceptedDispositionSnapshot> resolve({
    required bool abandonIncomplete,
  }) async {
    if (_busy || _disposed || _retiring) {
      throw StateError('Pair disposition is unavailable');
    }
    _busy = true;
    try {
      if (abandonIncomplete) _cutoff ??= learning.nowUtc();
      var loaded = await _inspect();
      if (loaded.kind == PairAcceptedDispositionKind.stopped) return loaded;
      if (loaded.kind == PairAcceptedDispositionKind.pendingCommitted) {
        final c = await _coordinatorForRecovery();
        await c.retryCommittedPending();
        loaded = await _inspect();
      }
      if (loaded.kind == PairAcceptedDispositionKind.complete) {
        if (!loaded.recovery.checkpoint!.terminalAcknowledged) {
          final c = await _coordinatorForRecovery();
          await c.finish();
          loaded = await _inspect();
        }
        return loaded;
      }
      if (!abandonIncomplete) return loaded;
      await learning.abandonUnavailablePairSession(
        ownerId: _owner!,
        startOperation: operation.stableSerialization,
        expectedCheckpoint: loaded.recovery.checkpoint!,
        abandonedAtUtc: _cutoff!,
      );
      return await _inspect();
    } finally {
      _busy = false;
      if (_retiring) dispose();
    }
  }

  Future<void> markPresented() async {
    if (_busy || _disposed || _retiring) {
      throw StateError('Pair disposition is unavailable');
    }
    _busy = true;
    try {
      final loaded = await _inspect();
      if (loaded.kind != PairAcceptedDispositionKind.complete ||
          !loaded.recovery.checkpoint!.terminalAcknowledged) {
        throw StateError('Pair acknowledged result is required');
      }
      final c = await _coordinatorForRecovery();
      await c.markSummaryPresented();
      await _checkOwner();
    } finally {
      _busy = false;
      if (_retiring) dispose();
    }
  }

  Future<List<ReviewQueueItem>> deferredReview(
    PairReviewDeferral adapter,
  ) async {
    final loaded = await _inspect();
    if (loaded.kind != PairAcceptedDispositionKind.complete ||
        !loaded.recovery.checkpoint!.terminalAcknowledged) {
      throw StateError('Pair acknowledged result is required');
    }
    final c = await _coordinatorForRecovery();
    final result = await c.deferredReview(adapter);
    await _checkOwner();
    return result;
  }

  void dispose() {
    _retiring = true;
    if (_busy) return;
    _disposed = true;
    _coordinator?.dispose();
  }
}
