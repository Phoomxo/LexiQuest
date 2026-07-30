import 'dart:async';

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
  }) => OwnerBindingGuestSessionService._(
    delegate,
    localOwners,
    upgradeGuestOwner,
    onOwnerBound,
  );

  const OwnerBindingGuestSessionService._(
    this._delegate,
    this._localOwners,
    this._upgradeGuestOwner,
    this._onOwnerBound,
  );

  final GuestSessionService _delegate;
  final LocalOwnerRepository _localOwners;
  final UpgradeGuestOwner _upgradeGuestOwner;
  final void Function()? _onOwnerBound;

  @override
  Future<GuestSessionResult> start() async {
    try {
      final owner = await _localOwners.getOrCreateActiveOwner();
      if (owner.firebaseUid == null) {
        unawaited(_bindAnonymousOwner(owner.id));
      }
      return GuestSessionStarted(uid: owner.firebaseUid ?? owner.id);
    } catch (_) {
      return const GuestSessionFailed(GuestSessionFailure.unknown);
    }
  }

  Future<void> _bindAnonymousOwner(String ownerId) async {
    try {
      final result = await _delegate.start();
      if (result case GuestSessionStarted(:final uid)) {
        await _upgradeGuestOwner(activeOwnerId: ownerId, firebaseUid: uid);
        _onOwnerBound?.call();
      }
    } catch (_) {
      // Guest learning is local-first. Anonymous cloud binding is retried by a
      // later online session and must never prevent or terminate offline use.
    }
  }
}
