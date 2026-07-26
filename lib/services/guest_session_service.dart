import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

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
