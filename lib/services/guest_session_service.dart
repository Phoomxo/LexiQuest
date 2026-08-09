import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';

import '../features/identity/application/upgrade_guest_owner.dart';
import '../features/identity/domain/local_owner_repository.dart';
import '../features/session/domain/app_entry_state.dart';

enum GuestSessionFailure {
  firebaseUnavailable,
  providerDisabled,
  network,
  unknown,
}

sealed class GuestSessionResult {
  const GuestSessionResult();
}

final class GuestSessionStarted extends GuestSessionResult {
  const GuestSessionStarted({required this.uid});

  final String uid;
}

final class GuestSessionFailed extends GuestSessionResult {
  const GuestSessionFailed(this.reason);

  final GuestSessionFailure reason;

  @override
  String toString() => 'GuestSessionFailed(${reason.name})';
}

abstract interface class GuestSessionService {
  Future<GuestSessionResult> start();
}

abstract interface class AnonymousAuthGateway {
  Future<String?> signInAnonymously();
}

typedef GuestRetryDelay = Future<void> Function(Duration delay);

/// Whether a [GuestSessionFailure] is worth retrying.
///
/// `network` is a genuine transient condition. `unknown` is also retried
/// because App Check / Play Integrity can need a few seconds to mint a token
/// on cold start — the first anonymous-sign-in attempt may surface as an
/// unmapped `FirebaseAuthException` (→ `unknown`) while the integrity service
/// is still binding, then succeed on a later attempt. Only `providerDisabled`
/// (Anonymous Auth turned off in the console) and `firebaseUnavailable`
/// (Firebase not initialized — a configuration error) are hard stops.
bool _isTransient(GuestSessionFailure reason) =>
    reason == GuestSessionFailure.network ||
    reason == GuestSessionFailure.unknown;

/// Applies a small bounded jitter (±15%) to a base backoff so that many devices
/// restarting in lockstep after a Firebase outage don't all retry on the exact
/// same beat (thundering-herd). The result is always strictly positive.
Duration _withJitter(Duration base, {Random? random}) {
  final factor = 0.85 + (random ?? Random()).nextDouble() * 0.3; // [0.85, 1.15]
  return Duration(microseconds: (base.inMicroseconds * factor).round());
}

final class FirebaseAnonymousAuthGateway implements AnonymousAuthGateway {
  const FirebaseAnonymousAuthGateway();

  @override
  Future<String?> signInAnonymously() async {
    final credential = await FirebaseAuth.instance.signInAnonymously();
    return credential.user?.uid;
  }
}

final class FirebaseGuestSessionService implements GuestSessionService {
  FirebaseGuestSessionService(this._gateway);

  factory FirebaseGuestSessionService.production() {
    return FirebaseGuestSessionService(const FirebaseAnonymousAuthGateway());
  }

  final AnonymousAuthGateway _gateway;

  @override
  Future<GuestSessionResult> start() async {
    try {
      final uid = (await _gateway.signInAnonymously())?.trim();
      if (uid == null || uid.isEmpty) {
        return const GuestSessionFailed(GuestSessionFailure.unknown);
      }
      return GuestSessionStarted(uid: uid);
    } on FirebaseAuthException catch (error) {
      return switch (error.code) {
        'operation-not-allowed' => const GuestSessionFailed(
          GuestSessionFailure.providerDisabled,
        ),
        'network-request-failed' => const GuestSessionFailed(
          GuestSessionFailure.network,
        ),
        _ => const GuestSessionFailed(GuestSessionFailure.unknown),
      };
    } on FirebaseException catch (error) {
      if (error.code == 'no-app' || error.code == 'core/no-app') {
        return const GuestSessionFailed(
          GuestSessionFailure.firebaseUnavailable,
        );
      }
      return const GuestSessionFailed(GuestSessionFailure.unknown);
    } catch (_) {
      return const GuestSessionFailed(GuestSessionFailure.unknown);
    }
  }
}

final class OwnerBindingGuestSessionService implements GuestSessionService {
  factory OwnerBindingGuestSessionService({
    required GuestSessionService delegate,
    required LocalOwnerRepository localOwners,
    required UpgradeGuestOwner upgradeGuestOwner,
    required AppEntryStateStore entryState,
    void Function()? onOwnerBound,
    GuestRetryDelay? retryDelay,
    int maxCloudBindingAttempts = 5,
  }) => OwnerBindingGuestSessionService._(
    delegate,
    localOwners,
    upgradeGuestOwner,
    entryState,
    onOwnerBound,
    retryDelay ?? ((delay) => Future<void>.delayed(_withJitter(delay))),
    maxCloudBindingAttempts,
  );

  OwnerBindingGuestSessionService._(
    this._delegate,
    this._localOwners,
    this._upgradeGuestOwner,
    this._entryState,
    this._onOwnerBound,
    this._retryDelay,
    this._maxCloudBindingAttempts,
  ) {
    if (_maxCloudBindingAttempts < 1) {
      throw ArgumentError.value(
        _maxCloudBindingAttempts,
        'maxCloudBindingAttempts',
        'must be positive',
      );
    }
  }

  final GuestSessionService _delegate;
  final LocalOwnerRepository _localOwners;
  final UpgradeGuestOwner _upgradeGuestOwner;
  final AppEntryStateStore _entryState;
  final void Function()? _onOwnerBound;
  final GuestRetryDelay _retryDelay;
  final int _maxCloudBindingAttempts;
  final Completer<void> _disposeSignal = Completer<void>();
  Future<void>? _cloudBinding;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  @override
  Future<GuestSessionResult> start() async {
    if (_disposed) {
      return const GuestSessionFailed(GuestSessionFailure.unknown);
    }
    try {
      final owner = await _localOwners.getOrCreateActiveOwner();
      if (_disposed) {
        return const GuestSessionFailed(GuestSessionFailure.unknown);
      }
      await _entryState.markGuest();
      if (_disposed) {
        return const GuestSessionFailed(GuestSessionFailure.unknown);
      }
      if (owner.firebaseUid == null) {
        final binding = _cloudBinding ??= _bindAnonymousOwner(owner.id);
        unawaited(
          binding.whenComplete(() {
            if (identical(_cloudBinding, binding)) {
              _cloudBinding = null;
            }
          }),
        );
      }
      return GuestSessionStarted(uid: owner.firebaseUid ?? owner.id);
    } catch (_) {
      return const GuestSessionFailed(GuestSessionFailure.unknown);
    }
  }

  /// Cancels pending provider waits/retries and drains any in-flight upgrade.
  Future<void> dispose() {
    return _disposeFuture ??= _disposeOnce();
  }

  Future<void> _disposeOnce() async {
    _disposed = true;
    if (!_disposeSignal.isCompleted) {
      _disposeSignal.complete();
    }
    final binding = _cloudBinding;
    if (binding != null) {
      await binding;
    }
  }

  Future<void> _bindAnonymousOwner(String ownerId) async {
    for (var attempt = 0; attempt < _maxCloudBindingAttempts; attempt++) {
      if (_disposed) return;
      try {
        final provider = await _unlessDisposed(_delegate.start());
        if (provider case _DisposedResult<GuestSessionResult>()) return;
        if (provider case _CompletedResult<GuestSessionResult>(:final value)) {
          final result = value;
          if (_disposed) return;
          if (result case GuestSessionStarted(:final uid)) {
            await _upgradeGuestOwner(activeOwnerId: ownerId, firebaseUid: uid);
            if (!_disposed) {
              _onOwnerBound?.call();
            }
            return;
          }
          if (result case GuestSessionFailed(:final reason)) {
            // Provider/configuration failures are permanent. Network and
            // integrity cold-start failures remain bounded transient cases.
            if (!_isTransient(reason)) {
              return;
            }
          }
        }
        if (provider case _FailedResult<GuestSessionResult>()) {
          // Treat unexpected provider failures as transient within the
          // bounded retry window. Local learning remains available.
        }
      } catch (_) {
        // Treat unexpected provider failures as transient within the bounded
        // retry window. Local learning remains available throughout.
      }
      if (attempt + 1 < _maxCloudBindingAttempts) {
        try {
          final delay = await _unlessDisposed(
            _retryDelay(const Duration(seconds: 15)),
          );
          if (delay case _DisposedResult<void>()) return;
        } catch (_) {
          // Keep the retry count bounded even when an injected delay fails.
        }
      }
    }
  }

  Future<_CancelableResult<T>> _unlessDisposed<T>(Future<T> operation) {
    return Future.any<_CancelableResult<T>>(<Future<_CancelableResult<T>>>[
      operation.then<_CancelableResult<T>>(
        _CompletedResult<T>.new,
        onError: (Object _, StackTrace _) => _FailedResult<T>(),
      ),
      _disposeSignal.future.then<_CancelableResult<T>>(
        (_) => _DisposedResult<T>(),
      ),
    ]);
  }
}

sealed class _CancelableResult<T> {}

final class _CompletedResult<T> extends _CancelableResult<T> {
  _CompletedResult(this.value);

  final T value;
}

final class _FailedResult<T> extends _CancelableResult<T> {
  _FailedResult();
}

final class _DisposedResult<T> extends _CancelableResult<T> {}
