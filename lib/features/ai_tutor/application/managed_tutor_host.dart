import 'dart:async';
import 'package:flutter/foundation.dart';
import 'managed_tutor_controller.dart';

/// Non-secret local identity. Account transitions invalidate even the same owner.
final class ManagedTutorIdentity {
  const ManagedTutorIdentity(this.ownerId, this.accountId);
  final String ownerId;
  final String accountId;
}

/// Opt-in application composition; owns the controller and session cleanup.
/// Recovery is always explicit: foreground/network recovery never sends a turn.
final class ManagedTutorHost {
  ManagedTutorHost({
    required this.controller,
    required this.identity,
    required Stream<bool> network,
    required this.clearSession,
    this.enabled = false,
  }) {
    identity.addListener(_identityChanged);
    _network = network.listen(
      (online) {
        _online = online;
        if (!online) {
          controller.setOffline();
          _clear();
        }
      },
      onError: (Object _) {
        _online = false;
        controller.setOffline();
        _clear();
      },
    );
  }
  final ManagedTutorController controller;
  final ValueListenable<ManagedTutorIdentity?> identity;
  final Future<void> Function() clearSession;
  final bool enabled;
  late final StreamSubscription<bool> _network;
  bool _online = true, _visible = true, _foreground = true, _disposed = false;
  int _epoch = 0;
  bool _cleanupFailed = false;
  Future<void> _cleanup = Future.value();

  void _clear() {
    _epoch++;
    _cleanup = _cleanup
        .then((_) => clearSession())
        .then(
          (_) {
            _cleanupFailed = false;
          },
          onError: (Object _) {
            _cleanupFailed = true;
          },
        );
  }

  void _identityChanged() {
    controller.ownerChanged();
    _clear();
  }

  void disconnect() {
    controller.disconnect();
    _clear();
  }

  void setVisible(bool value) {
    if (_disposed || _visible == value) return;
    _visible = value;
    if (!value) disconnect();
  }

  void setForeground(bool value) {
    if (_disposed || _foreground == value) return;
    _foreground = value;
    if (!value) disconnect();
  }

  Future<void> connect() async {
    final epoch = _epoch;
    await _cleanup;
    final current = identity.value;
    if (_disposed ||
        !enabled ||
        !_online ||
        !_visible ||
        !_foreground ||
        _cleanupFailed ||
        epoch != _epoch ||
        current == null) {
      return;
    }
    await controller.connect(
      ownerId: current.ownerId,
      accountId: current.accountId,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    identity.removeListener(_identityChanged);
    unawaited(_network.cancel());
    controller.dispose();
    _clear();
  }
}
