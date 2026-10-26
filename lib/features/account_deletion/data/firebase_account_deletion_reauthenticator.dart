import 'package:firebase_auth/firebase_auth.dart';

import '../domain/account_deletion_contracts.dart';

final class FirebaseDeletionIdentity {
  const FirebaseDeletionIdentity({
    required this.uid,
    required this.authenticatedAtUtc,
  });

  final String uid;
  final DateTime authenticatedAtUtc;
}

typedef FirebaseDeletionIdentityReader =
    Future<FirebaseDeletionIdentity?> Function({required bool forceRefresh});

final class FirebaseAccountDeletionReauthenticator
    implements AccountDeletionReauthenticator {
  const FirebaseAccountDeletionReauthenticator({required this.readIdentity});

  factory FirebaseAccountDeletionReauthenticator.production(
    FirebaseAuth auth,
  ) => FirebaseAccountDeletionReauthenticator(
    readIdentity: ({required forceRefresh}) async {
      final user = auth.currentUser;
      if (user == null) return null;
      final result = await user.getIdTokenResult(forceRefresh);
      final authenticatedAt = result.authTime;
      if (authenticatedAt == null) return null;
      return FirebaseDeletionIdentity(
        uid: user.uid,
        authenticatedAtUtc: authenticatedAt.toUtc(),
      );
    },
  );

  final FirebaseDeletionIdentityReader readIdentity;

  @override
  Future<RecentAuthenticationReceipt> reauthenticate({
    required String firebaseUid,
  }) async {
    try {
      final identity = await readIdentity(forceRefresh: true);
      if (identity == null ||
          identity.uid != firebaseUid ||
          !identity.authenticatedAtUtc.isUtc) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.reauthenticationRequired,
        );
      }
      return RecentAuthenticationReceipt(
        firebaseUid: identity.uid,
        authenticatedAtUtc: identity.authenticatedAtUtc,
      );
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.reauthenticationRequired,
        cause: error,
      );
    }
  }
}
