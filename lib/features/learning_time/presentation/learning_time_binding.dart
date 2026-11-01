import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../learning/domain/learning_time_admission.dart';
import '../application/learning_time_use_cases.dart';

/// Presentation permission only. Canonical/AI operation completion owns its
/// separate permission; hiding this binding never cancels those operations.
final class LearningTimeBinding extends ChangeNotifier
    with WidgetsBindingObserver {
  LearningTimeBinding({
    required LearningTimeUseCases? time,
    required this.expectedOwnerId,
    required this._visible,
  }) : _time = time,
       _ownerGeneration = time?.ownerGeneration,
       _captureGeneration = time?.captureGeneration {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _subscription = time?.changes.listen((_) => _timeChanged());
    syncVisibility();
  }

  final LearningTimeUseCases? _time;
  final String expectedOwnerId;
  final bool Function() _visible;
  final int? _ownerGeneration;
  int? _captureGeneration;
  late final StreamSubscription<void>? _subscription;
  bool _foreground = false;
  bool _lastVisible = false;
  bool _retired = false;
  bool _dependenciesRetired = false;
  bool _disposed = false;
  int _visibilityGeneration = 0;
  LiveTimeLease? _lease;
  TimeSource? _wantedSource;
  bool _resumeAfterPending = false;
  int _readyInFlight = 0;
  int _readyRequest = 0;

  LiveTimeLease? get lease => _lease;
  int get visibilityGeneration => _visibilityGeneration;
  bool get _ownerCurrent =>
      !_retired &&
      _time != null &&
      _time.ownerId == expectedOwnerId &&
      _time.ownerGeneration == _ownerGeneration;
  bool get hostVisible => !_disposed && _foreground && _safeVisible();
  bool get current => hostVisible && _ownerCurrent;

  bool _safeVisible() {
    try {
      return _visible();
    } on Object {
      return false;
    }
  }

  void _timeChanged() {
    if (_disposed) return;
    if (!_ownerCurrent && !_retired) {
      _retired = true;
      close();
    }
    if (_ownerCurrent && _captureGeneration != _time!.captureGeneration) {
      _captureGeneration = _time.captureGeneration;
      close();
      _lease = null;
    }
    syncVisibility();
    if (_readyInFlight == 0 &&
        _lease != null &&
        !identical(_time?.liveLease, _lease)) {
      _wantedSource = null;
      _resumeAfterPending = false;
    }
    if (current && _wantedSource != null) {
      if (_time!.hasPending) {
        _resumeAfterPending = true;
      } else {
        _resumeDeferred();
      }
    }
    notifyListeners();
  }

  void _resumeDeferred() {
    if (_resumeAfterPending &&
        _readyInFlight == 0 &&
        current &&
        !_time!.hasPending &&
        _wantedSource != null) {
      _resumeAfterPending = false;
      unawaited(ready(_wantedSource!));
    }
  }

  /// The host calls this on route/pane/TickerMode changes. A visible return
  /// never arms time; only an actual explicit ready source can do that.
  void syncVisibility() {
    if (_disposed) return;
    final next = hostVisible;
    if (next == _lastVisible) return;
    _lastVisible = next;
    _visibilityGeneration++;
    if (!next) suspend();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    syncVisibility();
  }

  Future<bool> ready(TimeSource source) async {
    syncVisibility();
    if (!current) return false;
    final time = _time!;
    _wantedSource = source;
    _resumeAfterPending = false;
    final request = ++_readyRequest;
    final visibility = _visibilityGeneration;
    final capture = time.captureGeneration;
    _readyInFlight++;
    try {
      var active = _lease;
      if (active == null || !identical(time.liveLease, active)) {
        active = await time.attach(source, stillCurrent: () => current);
        if (active == null) return false;
        if (request != _readyRequest ||
            !current ||
            visibility != _visibilityGeneration ||
            capture != time.captureGeneration) {
          time.detach(active);
          return false;
        }
        _lease = active;
      }
      var accepted = await time.ready(active, source: source);
      if (request != _readyRequest) return false;
      // A fast ACK may finish between sealing the previous context and the
      // failed ready result. One fresh LIVE admission resolves that race.
      if (!accepted &&
          !time.hasPending &&
          current &&
          visibility == _visibilityGeneration &&
          capture == time.captureGeneration) {
        accepted = await time.ready(active, source: source);
      }
      if (request != _readyRequest) return false;
      if (!current ||
          visibility != _visibilityGeneration ||
          capture != time.captureGeneration) {
        time.suspend(active);
        return false;
      }
      _resumeAfterPending = !accepted && time.hasPending;
      return accepted;
    } finally {
      _readyInFlight--;
      _resumeDeferred();
    }
  }

  void interacted() {
    syncVisibility();
    final active = _lease;
    if (current && active != null) _time!.interacted(active);
  }

  void suspend() {
    _readyRequest++;
    _wantedSource = null;
    _resumeAfterPending = false;
    final active = _lease;
    if (active != null) _time?.suspend(active);
  }

  /// Retain the detached lease for a legitimate later same-owner start ACK.
  void close() {
    suspend();
    final active = _lease;
    if (active != null) _time?.detach(active);
  }

  void retireDependencies() {
    if (_dependenciesRetired) return;
    _dependenciesRetired = true;
    _retired = true;
    final active = _lease;
    if (active != null) _time?.retireLeaseDependencies(active);
    close();
    if (!_disposed) notifyListeners();
  }

  Future<TimeSessionLinkAdmission?> prepareSessionLink(
    CanonicalLearningTimeSessionLinkReceipt receipt,
  ) async {
    final active = _lease;
    if (!_ownerCurrent || active == null) return null;
    return _time!.prepareSessionLink(active, receipt);
  }

  bool acknowledgeSessionLink(TimeSessionLinkAdmission admission) {
    final active = _lease;
    return _ownerCurrent &&
        active != null &&
        _time!.acknowledgeSessionLink(active, admission);
  }

  @override
  void dispose() {
    if (_disposed) return;
    close();
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }
}
