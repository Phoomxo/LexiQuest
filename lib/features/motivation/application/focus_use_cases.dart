import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_focus_repository.dart';
import '../domain/focus_models.dart';

final class FocusUseCases {
  FocusUseCases({
    required this.repository,
    required this.owners,
    required this.clock,
    required this.generateId,
    this.onChanged,
  });

  final DriftFocusRepository repository;
  final LocalOwnerRepository owners;
  final FocusClock clock;
  final String Function() generateId;
  final void Function()? onChanged;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;
  ({String ownerId, String? id, FocusSample sample, bool deviceGap})?
  _suspendedAt;
  ({String ownerId, String id, int targetMs, FocusSample sample})?
  _startCommand;
  ({
    String ownerId,
    String id,
    int revision,
    FocusStep step,
    FocusSample sample,
    bool suspendClock,
  })?
  _lastCommand;

  Future<FocusSnapshot> start({
    required String expectedOwnerId,
    required int targetMs,
  }) async {
    final sample = clock.sample();
    return _enqueue(() async {
      await _requireOwner(expectedOwnerId);
      final open = await repository.findOpen(ownerId: expectedOwnerId);
      if (open != null) {
        if (open.targetMs != targetMs ||
            (open.state == FocusState.running &&
                open.openSample?.continuityId != sample.continuityId)) {
          throw StateError('Recover or finish the existing focus round first');
        }
        await _requireOwner(expectedOwnerId);
        return open;
      }
      var command = _startCommand;
      if (command == null ||
          command.ownerId != expectedOwnerId ||
          command.targetMs != targetMs) {
        command = (
          ownerId: expectedOwnerId,
          id: generateId(),
          targetMs: targetMs,
          sample: sample,
        );
        _startCommand = command;
      }
      final before = await repository.load(
        ownerId: expectedOwnerId,
        id: command.id,
      );
      final result = await repository.start(
        expectedOwnerId: expectedOwnerId,
        id: command.id,
        targetMs: targetMs,
        sample: command.sample,
      );
      await _requireOwner(expectedOwnerId);
      _startCommand = null;
      _suspendedAt = null;
      _notify(before, result);
      return result;
    });
  }

  Future<FocusSnapshot?> loadOpen({required String expectedOwnerId}) =>
      _enqueue(() async {
        await _requireOwner(expectedOwnerId);
        final result = await repository.findOpen(ownerId: expectedOwnerId);
        await _requireOwner(expectedOwnerId);
        return result;
      });

  Future<FocusSnapshot?> recover({required String expectedOwnerId}) async {
    final sample = clock.sample();
    return _enqueue(() async {
      await _requireOwner(expectedOwnerId);
      final current = await repository.findOpen(ownerId: expectedOwnerId);
      if (current == null || current.state != FocusState.running) {
        await _requireOwner(expectedOwnerId);
        return current;
      }
      if (current.openSample?.continuityId != sample.continuityId) {
        return _perform(current, FocusStep.recoverInterrupted, sample);
      }
      final suspended = _suspendedAt;
      if (suspended != null &&
          suspended.ownerId == expectedOwnerId &&
          (suspended.id == null || suspended.id == current.id)) {
        return _perform(
          current,
          FocusStep.pause,
          suspended.sample,
          suspendClock: suspended.deviceGap,
        );
      }
      await _requireOwner(expectedOwnerId);
      return current;
    });
  }

  Future<FocusSnapshot> pause({
    required String expectedOwnerId,
    required String id,
    required int expectedRevision,
  }) => _transition(expectedOwnerId, id, expectedRevision, FocusStep.pause);

  Future<FocusSnapshot> resume({
    required String expectedOwnerId,
    required String id,
    required int expectedRevision,
  }) => _transition(expectedOwnerId, id, expectedRevision, FocusStep.resume);

  Future<FocusSnapshot> finish({
    required String expectedOwnerId,
    required String id,
    required int expectedRevision,
  }) => _transition(expectedOwnerId, id, expectedRevision, FocusStep.finish);

  Future<FocusSnapshot?> background({
    required String expectedOwnerId,
    FocusSample? sample,
  }) async {
    final existing = _suspendedAt;
    final observed =
        existing != null &&
            existing.ownerId == expectedOwnerId &&
            existing.deviceGap
        ? existing.sample
        : sample ?? clock.sample();
    observed.validate();
    _suspendedAt = (
      ownerId: expectedOwnerId,
      id: existing?.ownerId == expectedOwnerId ? existing?.id : null,
      sample: observed,
      deviceGap: true,
    );
    return _enqueue(() async {
      await _requireOwner(expectedOwnerId);
      final current = await repository.findOpen(ownerId: expectedOwnerId);
      if (current == null ||
          (current.state == FocusState.paused && current.openSample == null)) {
        await _requireOwner(expectedOwnerId);
        return current;
      }
      _suspendedAt = (
        ownerId: expectedOwnerId,
        id: current.id,
        sample: observed,
        deviceGap: true,
      );
      final step =
          current.state == FocusState.paused ||
              current.openSample?.continuityId == observed.continuityId
          ? FocusStep.pause
          : FocusStep.recoverInterrupted;
      return _perform(
        current,
        step,
        observed,
        suspendClock: step == FocusStep.pause,
      );
    });
  }

  Future<FocusWeek> week({
    required String expectedOwnerId,
    required DateTime civilMonday,
  }) => _enqueue(() async {
    await _requireOwner(expectedOwnerId);
    final result = await repository.week(
      ownerId: expectedOwnerId,
      civilMonday: civilMonday,
    );
    await _requireOwner(expectedOwnerId);
    return result;
  });

  int remainingMs(FocusSnapshot snapshot) {
    if (_disposed) {
      throw StateError('Focus scope is disposed');
    }
    var activeUs = snapshot.spans
        .where((span) => span.kind == FocusSpanKind.active)
        .fold<int>(0, (total, span) => total + (span.elapsedUs ?? 0));
    if (snapshot.state == FocusState.running) {
      final suspended = _suspendedAt;
      final sample =
          suspended != null &&
              suspended.ownerId == snapshot.ownerId &&
              (suspended.id == null || suspended.id == snapshot.id)
          ? suspended.sample
          : clock.sample();
      sample.validate();
      final open = snapshot.openSample;
      if (open == null ||
          open.continuityId != sample.continuityId ||
          sample.monotonicUs < open.monotonicUs) {
        throw StateError(
          'Recover the focus clock before displaying a countdown',
        );
      }
      activeUs += sample.monotonicUs - open.monotonicUs;
    }
    final remaining = snapshot.targetMs - activeUs ~/ 1000;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _tail;
  }

  Future<FocusSnapshot> _transition(
    String ownerId,
    String id,
    int revision,
    FocusStep step,
  ) async {
    final sample = _freeze(ownerId, id, revision, step, clock.sample());
    return _enqueue(() async {
      await _requireOwner(ownerId);
      final before = await repository.load(ownerId: ownerId, id: id);
      if (before?.revision == revision &&
          (step == FocusStep.pause || step == FocusStep.finish)) {
        _suspendedAt = (
          ownerId: ownerId,
          id: id,
          sample: sample,
          deviceGap: false,
        );
      }
      final result = await repository.transition(
        expectedOwnerId: ownerId,
        id: id,
        expectedRevision: revision,
        step: step,
        sample: sample,
      );
      await _requireOwner(ownerId);
      if (step == FocusStep.resume || result.state == FocusState.completed) {
        _suspendedAt = null;
      }
      _notify(before, result);
      return result;
    });
  }

  Future<FocusSnapshot> _perform(
    FocusSnapshot before,
    FocusStep step,
    FocusSample sample, {
    bool suspendClock = false,
  }) async {
    final frozen = _freeze(
      before.ownerId,
      before.id,
      before.revision,
      step,
      sample,
      suspendClock: suspendClock,
    );
    final result = await repository.transition(
      expectedOwnerId: before.ownerId,
      id: before.id,
      expectedRevision: before.revision,
      step: step,
      sample: frozen,
      suspendClock: suspendClock,
    );
    await _requireOwner(before.ownerId);
    _notify(before, result);
    return result;
  }

  FocusSample _freeze(
    String ownerId,
    String id,
    int revision,
    FocusStep step,
    FocusSample proposed, {
    bool suspendClock = false,
  }) {
    final previous = _lastCommand;
    if (previous != null &&
        previous.ownerId == ownerId &&
        previous.id == id &&
        previous.revision == revision &&
        previous.step == step &&
        previous.suspendClock == suspendClock) {
      return previous.sample;
    }
    proposed.validate();
    _lastCommand = (
      ownerId: ownerId,
      id: id,
      revision: revision,
      step: step,
      sample: proposed,
      suspendClock: suspendClock,
    );
    return proposed;
  }

  void _notify(FocusSnapshot? before, FocusSnapshot after) {
    if (!_disposed &&
        (before == null ||
            before.revision != after.revision ||
            before.state != after.state)) {
      onChanged?.call();
    }
  }

  Future<void> _requireOwner(String expectedOwnerId) async {
    if (_disposed || expectedOwnerId.trim().isEmpty) {
      throw StateError('Focus scope is unavailable');
    }
    final owner = await owners.getOrCreateActiveOwner();
    if (_disposed || owner.id != expectedOwnerId) {
      throw StateError('Focus owner changed');
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_disposed) {
      return Future<T>.error(StateError('Focus scope is disposed'));
    }
    final result = _tail.then((_) async {
      if (_disposed) {
        throw StateError('Focus scope is disposed');
      }
      return operation();
    });
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }
}
