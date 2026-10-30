import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../application/progress_use_cases.dart';
import '../domain/progress_models.dart';

typedef ProgressLoader = Future<ProgressSnapshot> Function();

/// Transient host reads; learning children keep their own canonical write scope.
final class ProgressHostBinding extends ChangeNotifier {
  ProgressHostBinding({
    required this.progress,
    required this.loader,
    required this.ownerChanges,
    required this.visible,
  }) {
    _owners = ownerChanges?.listen(
      _ownerChanged,
      onError: (Object _, StackTrace _) => _ownerChanged(null),
      onDone: () => _ownerChanged(null),
    );
  }

  final ProgressUseCases? progress;
  final ProgressLoader? loader;
  final Stream<String?>? ownerChanges;
  final bool Function() visible;
  StreamSubscription<String?>? _owners;
  bool _closed = false;
  bool _wasVisible = false;
  bool _notificationScheduled = false;
  String? ownerId;
  bool ownerObserved = false;
  int readEpoch = 0;
  int launchGeneration = 0;
  ProgressSnapshot? snapshot;
  bool loading = false;
  bool readFailed = false;

  bool get current => !_closed && ownerId != null && visible();
  bool isReadCurrent(int epoch) => current && epoch == readEpoch;
  bool isLaunchCurrent(int generation, String owner) =>
      !_closed && generation == launchGeneration && ownerId == owner;

  void _ownerChanged(String? owner) {
    if (_closed) return;
    ownerObserved = true;
    launchGeneration++;
    _clearRead();
    ownerId = owner == null || owner.trim().isEmpty ? null : owner;
    _wasVisible = current;
    if (current) _load();
    _notify();
  }

  void _clearRead() {
    readEpoch++;
    snapshot = null;
    loading = false;
    readFailed = false;
  }

  void invalidateLaunch() {
    if (_closed) return;
    launchGeneration++;
    _clearRead();
    _notify();
  }

  void syncVisibility({required bool ownedCover}) {
    if (_closed) return;
    final nowVisible = current;
    if (!nowVisible) {
      if (_wasVisible) _clearRead();
      if (!ownedCover) launchGeneration++;
    }
    _wasVisible = nowVisible;
    if (nowVisible && snapshot == null && !loading && !readFailed) _load();
    _notify();
  }

  int? beginLaunch(int epoch, {bool requireSnapshot = true}) {
    if (!isReadCurrent(epoch) || (requireSnapshot && snapshot == null)) {
      return null;
    }
    final generation = launchGeneration;
    _clearRead();
    _wasVisible = false;
    _notify();
    return generation;
  }

  void refresh() {
    if (!current) return;
    _clearRead();
    _load();
    _notify();
  }

  Future<void> _load() async {
    final epoch = readEpoch;
    final owner = ownerId!;
    loading = true;
    try {
      if (!isReadCurrent(epoch)) return;
      final ProgressSnapshot value;
      if (loader != null) {
        value = await loader!();
      } else if (progress != null) {
        value = await progress!.loadForOwner(
          expectedOwnerId: owner,
          stillCurrent: () => isReadCurrent(epoch),
        );
      } else {
        throw StateError('progress dependency unavailable');
      }
      if (!isReadCurrent(epoch) || ownerId != owner) return;
      snapshot = value;
      loading = false;
    } on Object {
      if (!isReadCurrent(epoch) || ownerId != owner) return;
      snapshot = null;
      loading = false;
      readFailed = true;
    }
    _notify();
  }

  void _notify() {
    if (_closed || _notificationScheduled) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _notificationScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notificationScheduled = false;
        if (!_closed) notifyListeners();
      });
      SchedulerBinding.instance.ensureVisualUpdate();
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    launchGeneration++;
    _clearRead();
    unawaited(_owners?.cancel());
    super.dispose();
  }
}
