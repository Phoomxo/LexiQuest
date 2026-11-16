import '../../account/domain/account_contracts.dart';
import '../../identity/domain/local_owner.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../domain/account_deletion_contracts.dart';

typedef AccountDeletionUtcNow = DateTime Function();
typedef AccountDeletionSessionReader = AccountSession? Function();

final class AccountDeletionUseCases {
  const AccountDeletionUseCases({
    this.enabled = false,
    required this.owners,
    required this.currentSession,
    required this.exporter,
    required this.reauthenticator,
    required this.cloud,
    required this.local,
    required this.journal,
    required this.nowUtc,
  });

  static const recentAuthenticationWindow = Duration(minutes: 5);
  static const serverClockSkew = Duration(minutes: 5);

  final bool enabled;
  final LocalOwnerRepository owners;
  final AccountDeletionSessionReader currentSession;
  final FullAccountExporter exporter;
  final AccountDeletionReauthenticator reauthenticator;
  final PrivilegedAccountDeletionGateway cloud;
  final LocalAccountDeletionGateway local;
  final AccountDeletionJournal journal;
  final AccountDeletionUtcNow nowUtc;

  Future<AccountDeletionReceipt> deleteAccount({
    required String idempotencyKey,
  }) async {
    if (!enabled) {
      throw const AccountDeletionException(AccountDeletionFailureCode.disabled);
    }
    final key = idempotencyKey.trim();
    if (!RegExp(r'^[A-Za-z0-9._:-]{16,128}$').hasMatch(key)) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.invalidRequest,
      );
    }

    final identity = await _requireIdentity();
    late final FullAccountExportReceipt exportReceipt;
    try {
      exportReceipt = await exporter.export(ownerId: identity.owner.id);
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.fullExportFailed,
        cause: error,
      );
    }
    _validateExport(exportReceipt, identity.owner.id);

    await _requireIdentity(
      ownerId: identity.owner.id,
      firebaseUid: identity.session.uid,
    );
    late final RecentAuthenticationReceipt authenticationReceipt;
    try {
      authenticationReceipt = await reauthenticator.reauthenticate(
        firebaseUid: identity.session.uid,
      );
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.reauthenticationRequired,
        cause: error,
      );
    }
    _validateAuthentication(authenticationReceipt, identity.session.uid);

    await _requireIdentity(
      ownerId: identity.owner.id,
      firebaseUid: identity.session.uid,
    );
    late final CloudDeletionReceipt cloudReceipt;
    try {
      cloudReceipt = await cloud.deleteRecursively(
        ownerId: identity.owner.id,
        firebaseUid: identity.session.uid,
        idempotencyKey: key,
        exportReceipt: exportReceipt,
        authenticationReceipt: authenticationReceipt,
      );
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.cloudDeleteFailed,
        cause: error,
      );
    }
    _validateCloud(
      cloudReceipt,
      ownerId: identity.owner.id,
      firebaseUid: identity.session.uid,
      idempotencyKey: key,
    );
    await _saveCloudReceipt(cloudReceipt);

    await _requireOwner(
      ownerId: identity.owner.id,
      firebaseUid: identity.session.uid,
      cloudReceipt: cloudReceipt,
    );
    final localReceipt = await _deleteLocalAndJournal(
      ownerId: identity.owner.id,
      cloudReceipt: cloudReceipt,
    );

    return AccountDeletionReceipt(
      ownerId: identity.owner.id,
      firebaseUid: identity.session.uid,
      idempotencyKey: key,
      exportReceipt: exportReceipt,
      cloudReceipt: cloudReceipt,
      localReceipt: localReceipt,
    );
  }

  Future<LocalDeletionReceipt> resumeLocalDeletion(
    CloudDeletionReceipt cloudReceipt,
  ) async {
    if (!enabled) {
      throw const AccountDeletionException(AccountDeletionFailureCode.disabled);
    }
    _validateCloud(
      cloudReceipt,
      ownerId: cloudReceipt.ownerId,
      firebaseUid: cloudReceipt.firebaseUid,
      idempotencyKey: cloudReceipt.idempotencyKey,
    );
    late final AccountDeletionJournalEntry? entry;
    try {
      entry = await journal.load();
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
        cause: error,
        cloudReceipt: cloudReceipt,
      );
    }
    if (entry == null) {
      await _requireOwner(
        ownerId: cloudReceipt.ownerId,
        firebaseUid: cloudReceipt.firebaseUid,
        cloudReceipt: cloudReceipt,
      );
      await _saveCloudReceipt(cloudReceipt);
    } else if (!_sameCloudReceipt(entry.cloudReceipt, cloudReceipt)) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidCloudReceipt,
        cloudReceipt: entry.cloudReceipt,
      );
    } else if (entry.localReceipt case final completed?) {
      _validateLocal(completed, cloudReceipt.ownerId, cloudReceipt);
      return completed;
    }
    return _deleteLocalAndJournal(
      ownerId: cloudReceipt.ownerId,
      cloudReceipt: cloudReceipt,
    );
  }

  Future<LocalDeletionReceipt?> resumePendingDeletion() async {
    if (!enabled) {
      throw const AccountDeletionException(AccountDeletionFailureCode.disabled);
    }
    late final AccountDeletionJournalEntry? entry;
    try {
      entry = await journal.load();
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
        cause: error,
      );
    }
    if (entry == null) return null;

    final cloudReceipt = entry.cloudReceipt;
    _validateCloud(
      cloudReceipt,
      ownerId: cloudReceipt.ownerId,
      firebaseUid: cloudReceipt.firebaseUid,
      idempotencyKey: cloudReceipt.idempotencyKey,
    );
    final completed = entry.localReceipt;
    if (completed != null) {
      _validateLocal(completed, cloudReceipt.ownerId, cloudReceipt);
      return completed;
    }

    return _deleteLocalAndJournal(
      ownerId: cloudReceipt.ownerId,
      cloudReceipt: cloudReceipt,
    );
  }

  Future<({LocalOwner owner, AccountSession session})> _requireIdentity({
    String? ownerId,
    String? firebaseUid,
  }) async {
    final owner = await _activeOwner();
    final session = currentSession();
    if (ownerId != null && owner.id != ownerId) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.ownerChanged,
      );
    }
    if (session == null ||
        session.isAnonymous ||
        owner.firebaseUid == null ||
        owner.firebaseUid != session.uid) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.invalidIdentity,
      );
    }
    if (firebaseUid != null && session.uid != firebaseUid) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.ownerChanged,
      );
    }
    return (owner: owner, session: session);
  }

  Future<void> _requireOwner({
    required String ownerId,
    required String firebaseUid,
    required CloudDeletionReceipt cloudReceipt,
  }) async {
    final owner = await _activeOwner();
    if (owner.id != ownerId || owner.firebaseUid != firebaseUid) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.ownerChanged,
        cloudReceipt: cloudReceipt,
      );
    }
  }

  Future<LocalOwner> _activeOwner() async {
    try {
      return await owners.getOrCreateActiveOwner();
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
        cause: error,
      );
    }
  }

  void _validateExport(FullAccountExportReceipt receipt, String ownerId) {
    final now = _now();
    if (receipt.ownerId != ownerId ||
        receipt.artifactId.trim().isEmpty ||
        !RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(receipt.artifactSha256) ||
        receipt.bytesWritten <= 0 ||
        receipt.schemaVersion <= 0 ||
        receipt.coveredScopes.length !=
            requiredFullAccountExportScopes.length ||
        !receipt.coveredScopes.containsAll(requiredFullAccountExportScopes) ||
        !receipt.completedAtUtc.isUtc ||
        receipt.completedAtUtc.isAfter(now)) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.fullExportRequired,
      );
    }
  }

  bool _sameCloudReceipt(
    CloudDeletionReceipt left,
    CloudDeletionReceipt right,
  ) =>
      left.receiptId == right.receiptId &&
      left.ownerId == right.ownerId &&
      left.firebaseUid == right.firebaseUid &&
      left.idempotencyKey == right.idempotencyKey &&
      left.completedAtUtc == right.completedAtUtc;

  void _validateAuthentication(
    RecentAuthenticationReceipt receipt,
    String firebaseUid,
  ) {
    final now = _now();
    if (receipt.firebaseUid != firebaseUid ||
        !receipt.authenticatedAtUtc.isUtc ||
        receipt.authenticatedAtUtc.isAfter(now.add(serverClockSkew)) ||
        now.difference(receipt.authenticatedAtUtc) >
            recentAuthenticationWindow) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.reauthenticationRequired,
      );
    }
  }

  void _validateCloud(
    CloudDeletionReceipt receipt, {
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
  }) {
    if (receipt.receiptId.trim().isEmpty ||
        receipt.ownerId != ownerId ||
        receipt.firebaseUid != firebaseUid ||
        receipt.idempotencyKey != idempotencyKey ||
        !RegExp(
          r'^[A-Za-z0-9._:-]{16,128}$',
        ).hasMatch(receipt.idempotencyKey) ||
        !receipt.completedAtUtc.isUtc ||
        receipt.completedAtUtc.isAfter(_now().add(serverClockSkew))) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.invalidCloudReceipt,
      );
    }
  }

  Future<LocalDeletionReceipt> _deleteLocal({
    required String ownerId,
    required CloudDeletionReceipt cloudReceipt,
  }) async {
    late final LocalDeletionReceipt localReceipt;
    try {
      localReceipt = await local.deleteAfterCloud(
        ownerId: ownerId,
        cloudReceipt: cloudReceipt,
      );
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.localDeleteFailed,
        cause: error,
        cloudReceipt: cloudReceipt,
      );
    }
    _validateLocal(localReceipt, ownerId, cloudReceipt);
    return localReceipt;
  }

  Future<LocalDeletionReceipt> _deleteLocalAndJournal({
    required String ownerId,
    required CloudDeletionReceipt cloudReceipt,
  }) async {
    final localReceipt = await _deleteLocal(
      ownerId: ownerId,
      cloudReceipt: cloudReceipt,
    );
    try {
      await journal.saveLocalReceipt(
        cloudReceipt: cloudReceipt,
        localReceipt: localReceipt,
      );
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.localDeleteFailed,
        cause: error,
        cloudReceipt: cloudReceipt,
      );
    }
    return localReceipt;
  }

  Future<void> _saveCloudReceipt(CloudDeletionReceipt receipt) async {
    try {
      await journal.saveCloudReceipt(receipt);
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.localDeleteFailed,
        cause: error,
        cloudReceipt: receipt,
      );
    }
  }

  void _validateLocal(
    LocalDeletionReceipt receipt,
    String ownerId,
    CloudDeletionReceipt cloudReceipt,
  ) {
    if (receipt.deletedOwnerId != ownerId ||
        receipt.newGuestOwnerId.trim().isEmpty ||
        receipt.newGuestOwnerId == ownerId ||
        !receipt.completedAtUtc.isUtc ||
        receipt.completedAtUtc
            .add(serverClockSkew)
            .isBefore(cloudReceipt.completedAtUtc) ||
        receipt.completedAtUtc.isAfter(_now())) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidLocalReceipt,
        cloudReceipt: cloudReceipt,
      );
    }
  }

  DateTime _now() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
    return value;
  }
}
