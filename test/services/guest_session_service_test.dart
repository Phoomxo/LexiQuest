import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _FakeAnonymousAuthGateway implements AnonymousAuthGateway {
  _FakeAnonymousAuthGateway({this.uid, this.error});

  final String? uid;
  final Object? error;

  @override
  Future<String?> signInAnonymously() async {
    final captured = error;
    if (captured != null) throw captured;
    return uid;
  }
}

void main() {
  group('FirebaseGuestSessionService.start', () {
    test('starts a guest session with the exact gateway uid', () async {
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(uid: 'guest-uid-123'),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionStarted>().having(
          (started) => started.uid,
          'uid',
          'guest-uid-123',
        ),
      );
    });

    for (final invalidUid in <String?>[null, '', '   ']) {
      test('maps invalid uid "$invalidUid" to unknown', () async {
        final service = FirebaseGuestSessionService(
          _FakeAnonymousAuthGateway(uid: invalidUid),
        );

        final result = await service.start();

        expect(
          result,
          isA<GuestSessionFailed>().having(
            (failed) => failed.reason,
            'reason',
            GuestSessionFailure.unknown,
          ),
        );
      });
    }

    test('maps operation-not-allowed to providerDisabled', () async {
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(
          error: FirebaseAuthException(
            code: 'operation-not-allowed',
            message: 'Anonymous sign-in is disabled.',
          ),
        ),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionFailed>().having(
          (failed) => failed.reason,
          'reason',
          GuestSessionFailure.providerDisabled,
        ),
      );
    });

    test('maps network-request-failed to network', () async {
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(
          error: FirebaseAuthException(
            code: 'network-request-failed',
            message: 'Network unavailable.',
          ),
        ),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionFailed>().having(
          (failed) => failed.reason,
          'reason',
          GuestSessionFailure.network,
        ),
      );
    });

    test('maps a missing Firebase app to firebaseUnavailable', () async {
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(
          error: FirebaseException(
            plugin: 'core',
            code: 'no-app',
            message: 'No Firebase app.',
          ),
        ),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionFailed>().having(
          (failed) => failed.reason,
          'reason',
          GuestSessionFailure.firebaseUnavailable,
        ),
      );
    });

    test('maps an unexpected exception to unknown', () async {
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(error: StateError('unexpected failure')),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionFailed>().having(
          (failed) => failed.reason,
          'reason',
          GuestSessionFailure.unknown,
        ),
      );
    });

    test('failure exposes only the enum and never provider messages', () async {
      const sentinel = 'SECRET_PROVIDER_RESPONSE_42';
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(
          error: FirebaseAuthException(
            code: 'operation-not-allowed',
            message: sentinel,
          ),
        ),
      );

      final result = await service.start();
      final failed = result as GuestSessionFailed;

      expect(failed.reason, GuestSessionFailure.providerDisabled);
      expect(result.toString(), isNot(contains(sentinel)));
      expect(failed.reason.toString(), isNot(contains(sentinel)));
    });
  });
}
