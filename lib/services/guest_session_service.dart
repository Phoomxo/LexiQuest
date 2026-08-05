import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';

import '../features/identity/application/upgrade_guest_owner.dart';
import '../features/identity/domain/local_owner_repository.dart';

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

/// Whether a [GuestSessionFailure] is worth retrying. Only [GuestSessionFailure.network]
/// is a genuinely transient condition (connectivity blip, transient DNS). All
/// other failures (`providerDisabled`, `firebaseUnavailable`, `unknown`) point
/// at configuration or backend-state problems that retrying will not fix —
/// retrying them just burns ~75s on startup and can mask a misconfiguration as
/// "transient".
bool _isTransient(GuestSessionFailure reason) =>
    reason == GuestSessionFailure.network;

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
    void Function()? onOwnerBound,
    GuestRetryDelay? retryDelay,
    int maxCloudBindingAttempts = 5,
  }) => OwnerBindingGuestSessionService._(
    delegate,
    localOwners,
    upgradeGuestOwner,
    onOwnerBound,
    retryDelay ?? ((delay) => Future<void>.delayed(_withJitter(delay))),
    maxCloudBindingAttempts,
  );

  OwnerBindingGuestSessionService._(
    this._delegate,
    this._localOwners,
    this._upgradeGuestOwner,
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
  final void Function()? _onOwnerBound;
  final GuestRetryDelay _retryDelay;
  final int _maxCloudBindingAttempts;
  Future<void>? _cloudBinding;

  @override
  Future<GuestSessionResult> start() async {
    try {
      final owner = await _localOwners.getOrCreateActiveOwner();
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

  Future<void> _bindAnonymousOwner(String ownerId) async {
    for (var attempt = 0; attempt < _maxCloudBindingAttempts; attempt++) {
      try {
        final result = await _delegate.start();
        if (result case GuestSessionStarted(:final uid)) {
          await _upgradeGuestOwner(activeOwnerId: ownerId, firebaseUid: uid);
          _onOwnerBound?.call();
          return;
        }
        if (result case GuestSessionFailed(:final reason)) {
          // Stop immediately on permanent failures. Retrying a misconfigured
          // backend (providerDisabled, firebaseUnavailable, unknown) only burns
          // ~75s of startup time and masks the real problem as "transient".
          // Only GuestSessionFailure.network is genuinely retryable.
          if (!_isTransient(reason)) {
            return;
          }
        }
      } catch (_) {
        // Treat unexpected provider failures as transient within the bounded
        // retry window. Local learning remains available throughout.
      }
      if (attempt + 1 < _maxCloudBindingAttempts) {
        await _retryDelay(const Duration(seconds: 15));
      }
    }
  }
}
