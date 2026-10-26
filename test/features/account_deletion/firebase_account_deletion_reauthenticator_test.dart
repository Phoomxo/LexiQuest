import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/data/firebase_account_deletion_reauthenticator.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';

void main() {
  test('forces a refreshed token and returns its verified auth time', () async {
    bool? forced;
    final authenticatedAt = DateTime.utc(2026, 10, 26, 9);
    final reauthenticator = FirebaseAccountDeletionReauthenticator(
      readIdentity: ({required forceRefresh}) async {
        forced = forceRefresh;
        return FirebaseDeletionIdentity(
          uid: 'firebase-user',
          authenticatedAtUtc: authenticatedAt,
        );
      },
    );

    final receipt = await reauthenticator.reauthenticate(
      firebaseUid: 'firebase-user',
    );

    expect(forced, isTrue);
    expect(receipt.firebaseUid, 'firebase-user');
    expect(receipt.authenticatedAtUtc, authenticatedAt);
  });

  test('fails closed for absent, mismatched, or malformed identity', () async {
    for (final identity in <FirebaseDeletionIdentity?>[
      null,
      FirebaseDeletionIdentity(
        uid: 'other-user',
        authenticatedAtUtc: DateTime.utc(2026, 10, 26, 9),
      ),
      FirebaseDeletionIdentity(
        uid: 'firebase-user',
        authenticatedAtUtc: DateTime(2026, 10, 26, 9),
      ),
    ]) {
      final reauthenticator = FirebaseAccountDeletionReauthenticator(
        readIdentity: ({required forceRefresh}) async => identity,
      );

      await expectLater(
        reauthenticator.reauthenticate(firebaseUid: 'firebase-user'),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.reauthenticationRequired,
          ),
        ),
      );
    }
  });
}
