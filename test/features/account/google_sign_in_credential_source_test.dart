import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:vocab_learning_app/features/account/data/google_sign_in_credential_source.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';

void main() {
  test(
    'initializes lazily once and requests one credential per sign in',
    () async {
      var initializeCalls = 0;
      var tokenCalls = 0;
      final source = GoogleSignInCredentialSource(
        initialize: () async => initializeCalls++,
        authenticateIdToken: () async {
          tokenCalls++;
          return 'synthetic-id-token';
        },
        signOut: () async {},
      );

      await source.credential();
      await source.credential();

      expect(initializeCalls, 1);
      expect(tokenCalls, 2);
    },
  );

  test('maps cancel and provider failures without leaking details', () async {
    for (final entry in <(Object, AccountFailureCode)>[
      (
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'secret-token-sentinel',
        ),
        AccountFailureCode.cancelled,
      ),
      (
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
          description: 'secret-token-sentinel',
        ),
        AccountFailureCode.unavailable,
      ),
      (StateError('secret-token-sentinel'), AccountFailureCode.unavailable),
    ]) {
      final source = GoogleSignInCredentialSource(
        initialize: () async {},
        authenticateIdToken: () async => throw entry.$1,
        signOut: () async {},
      );

      await expectLater(
        source.credential(),
        throwsA(
          isA<AccountException>()
              .having((error) => error.code, 'code', entry.$2)
              .having(
                (error) => error.toString(),
                'safe error',
                isNot(contains('secret-token-sentinel')),
              ),
        ),
      );
    }
  });

  test('missing ID token is unavailable', () async {
    final source = GoogleSignInCredentialSource(
      initialize: () async {},
      authenticateIdToken: () async => null,
      signOut: () async {},
    );

    await expectLater(
      source.credential(),
      throwsA(
        isA<AccountException>().having(
          (error) => error.code,
          'code',
          AccountFailureCode.unavailable,
        ),
      ),
    );
  });
}
