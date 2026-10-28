import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../identity/domain/owner_upgrade.dart';

const Set<String> requiredFullAccountExportScopes = <String>{
  ...ownerUpgradeInventory,
  'vocabulary_import_rows',
  'quest_objective_progress',
  'local_owners',
};

String durableAccountDeletionBinding(String idempotencyKey) {
  if (idempotencyKey.startsWith('sha256:') && idempotencyKey.length == 71) {
    return idempotencyKey;
  }
  return 'sha256:${sha256.convert(utf8.encode(idempotencyKey))}';
}

String accountDeletionReplacementGuestOwnerId(CloudDeletionReceipt receipt) {
  final operation = jsonEncode([
    receipt.ownerId,
    receipt.firebaseUid,
    receipt.idempotencyKey,
    receipt.receiptId,
  ]);
  return 'local:deleted:${sha256.convert(utf8.encode(operation))}';
}

enum AccountDeletionFailureCode {
  disabled,
  invalidRequest,
  invalidIdentity,
  ownerChanged,
  fullExportRequired,
  fullExportFailed,
  reauthenticationRequired,
  cloudDeleteFailed,
  invalidCloudReceipt,
  localDeleteFailed,
  invalidLocalReceipt,
  recoveryExpired,
  unavailable,
}

final class AccountDeletionException implements Exception {
  const AccountDeletionException(this.code, {this.cause, this.cloudReceipt});

  final AccountDeletionFailureCode code;
  final Object? cause;
  final CloudDeletionReceipt? cloudReceipt;

  bool get retryable => switch (code) {
    AccountDeletionFailureCode.fullExportFailed ||
    AccountDeletionFailureCode.cloudDeleteFailed ||
    AccountDeletionFailureCode.localDeleteFailed ||
    AccountDeletionFailureCode.unavailable => true,
    _ => false,
  };
}

final class FullAccountExportReceipt {
  const FullAccountExportReceipt({
    required this.ownerId,
    required this.artifactId,
    required this.artifactSha256,
    required this.bytesWritten,
    required this.schemaVersion,
    required this.coveredScopes,
    required this.completedAtUtc,
  });

  final String ownerId;
  final String artifactId;
  final String artifactSha256;
  final int bytesWritten;
  final int schemaVersion;
  final Set<String> coveredScopes;
  final DateTime completedAtUtc;
}

final class RecentAuthenticationReceipt {
  const RecentAuthenticationReceipt({
    required this.firebaseUid,
    required this.authenticatedAtUtc,
  });

  final String firebaseUid;
  final DateTime authenticatedAtUtc;
}

final class CloudDeletionReceipt {
  const CloudDeletionReceipt({
    required this.receiptId,
    required this.ownerId,
    required this.firebaseUid,
    required this.idempotencyKey,
    required this.completedAtUtc,
  });

  final String receiptId;
  final String ownerId;
  final String firebaseUid;
  final String idempotencyKey;
  final DateTime completedAtUtc;

  CloudDeletionReceipt durableMarker() {
    final binding = durableAccountDeletionBinding(idempotencyKey);
    if (binding == idempotencyKey) {
      return this;
    }
    return CloudDeletionReceipt(
      receiptId: receiptId,
      ownerId: ownerId,
      firebaseUid: firebaseUid,
      idempotencyKey: binding,
      completedAtUtc: completedAtUtc,
    );
  }
}

final class LocalDeletionReceipt {
  const LocalDeletionReceipt({
    required this.deletedOwnerId,
    required this.newGuestOwnerId,
    required this.completedAtUtc,
  });

  final String deletedOwnerId;
  final String newGuestOwnerId;
  final DateTime completedAtUtc;
}

final class AccountDeletionJournalEntry {
  AccountDeletionJournalEntry({
    String? ownerId,
    String? firebaseUid,
    String? idempotencyKey,
    this.exportReceipt,
    this.authenticationReceipt,
    this.cloudReceipt,
    this.localReceipt,
    this.recoveryExpiresAtUtc,
  }) : ownerId = ownerId ?? cloudReceipt?.ownerId ?? '',
       firebaseUid = firebaseUid ?? cloudReceipt?.firebaseUid ?? '',
       idempotencyKey = idempotencyKey ?? cloudReceipt?.idempotencyKey ?? '';

  final String ownerId;
  final String firebaseUid;
  final String idempotencyKey;
  final FullAccountExportReceipt? exportReceipt;
  final RecentAuthenticationReceipt? authenticationReceipt;
  final CloudDeletionReceipt? cloudReceipt;
  final LocalDeletionReceipt? localReceipt;
  final DateTime? recoveryExpiresAtUtc;
}

final class AccountDeletionReceipt {
  const AccountDeletionReceipt({
    required this.ownerId,
    required this.firebaseUid,
    required this.idempotencyKey,
    required this.exportReceipt,
    required this.cloudReceipt,
    required this.localReceipt,
  });

  final String ownerId;
  final String firebaseUid;
  final String idempotencyKey;
  final FullAccountExportReceipt exportReceipt;
  final CloudDeletionReceipt cloudReceipt;
  final LocalDeletionReceipt localReceipt;
}

abstract interface class FullAccountExporter {
  Future<FullAccountExportReceipt> export({required String ownerId});
}

abstract interface class AccountDeletionReauthenticator {
  Future<RecentAuthenticationReceipt> reauthenticate({
    required String firebaseUid,
  });
}

/// Implementations must recursively delete the user's cloud namespace and
/// authentication identity, returning the same receipt for the same key.
abstract interface class PrivilegedAccountDeletionGateway {
  Future<CloudDeletionReceipt> deleteRecursively({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  });
}

abstract interface class LocalAccountDeletionGateway {
  Future<LocalDeletionReceipt> deleteAfterCloud({
    required String ownerId,
    required CloudDeletionReceipt cloudReceipt,
  });
}

abstract interface class AccountDeletionJournal {
  Future<AccountDeletionJournalEntry?> load();

  Future<void> savePendingOperation({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  });

  Future<void> saveCloudReceipt(CloudDeletionReceipt receipt);

  Future<void> saveLocalReceipt({
    required CloudDeletionReceipt cloudReceipt,
    required LocalDeletionReceipt localReceipt,
  });
}
