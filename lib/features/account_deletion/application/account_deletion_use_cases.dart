import '../../account/domain/account_contracts.dart';
import '../../identity/domain/local_owner.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../domain/account_deletion_contracts.dart';
import '../domain/owner_write_coordinator.dart';

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
    required this.ownerWrites,
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
  final OwnerWriteCoordinator ownerWrites;
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

    final pending = await _loadJournal();
    if (pending != null) {
      await _adoptJournal(pending);
      throw const AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
      );
    }

    final identity = await _requireIdentity();
    final previous = await ownerWrites.inspect();
    if (previous != null &&
        previous.phase == DeletionIntentPhase.preparing &&
        previous.casToken!.matchesOwner(identity.owner.id)) {
      if (!await ownerWrites.abortPreparing(previous.casToken!)) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.unavailable,
        );
      }
    }
    final intent = await ownerWrites.beginDeletion(
      ownerId: identity.owner.id,
      firebaseUid: identity.session.uid,
      idempotencyKey: key,
    );
    late final FullAccountExportReceipt exportReceipt;
    late final RecentAuthenticationReceipt authenticationReceipt;
    try {
      if ((await ownerWrites.inspect())?.phase !=
          DeletionIntentPhase.preparing) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.unavailable,
        );
      }
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
      // The durable fence must precede any uncertain journal/cloud write.
      await ownerWrites.markPending(intent);
      await _savePendingOperation(
        ownerId: identity.owner.id,
        firebaseUid: identity.session.uid,
        idempotencyKey: key,
        exportReceipt: exportReceipt,
        authenticationReceipt: authenticationReceipt,
      );
    } catch (_) {
      await ownerWrites.abortPreparing(intent);
      rethrow;
    }
    late final CloudDeletionReceipt serverReceipt;
    try {
      serverReceipt = await cloud.deleteRecursively(
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
      serverReceipt,
      ownerId: identity.owner.id,
      firebaseUid: identity.session.uid,
      idempotencyKey: key,
    );
    final cloudReceipt = serverReceipt.durableMarker();
    await ownerWrites.markCloud(intent, cloudReceipt);
    await _saveCloudReceipt(cloudReceipt);

    await _requireOwner(
      ownerId: identity.owner.id,
      firebaseUid: identity.session.uid,
      cloudReceipt: cloudReceipt,
    );
    final localReceipt = await _deleteLocalAndJournal(
      intent: intent,
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
    cloudReceipt = cloudReceipt.durableMarker();
    _validateCloud(
      cloudReceipt,
      ownerId: cloudReceipt.ownerId,
      firebaseUid: cloudReceipt.firebaseUid,
      idempotencyKey: cloudReceipt.idempotencyKey,
    );
    final snapshot = await ownerWrites.inspect();
    final entry = await _loadJournal();
    if (entry == null) {
      if (snapshot == null) {
        await _requireOwner(
          ownerId: cloudReceipt.ownerId,
          firebaseUid: cloudReceipt.firebaseUid,
          cloudReceipt: cloudReceipt,
        );
      }
    } else if (entry.ownerId != cloudReceipt.ownerId ||
        entry.firebaseUid != cloudReceipt.firebaseUid ||
        durableAccountDeletionBinding(entry.idempotencyKey) !=
            cloudReceipt.idempotencyKey ||
        (entry.cloudReceipt != null &&
            !_sameCloudReceipt(entry.cloudReceipt!, cloudReceipt))) {
      await ownerWrites.preserveRecoveryUncertainty();
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidCloudReceipt,
        cloudReceipt: entry.cloudReceipt,
      );
    }
    final recovered = await _adoptJournal(
      AccountDeletionJournalEntry(
        cloudReceipt: cloudReceipt,
        localReceipt: entry?.localReceipt,
      ),
    );
    return _resumeConfirmed(recovered, journalPresent: entry != null);
  }

  Future<LocalDeletionReceipt?> resumePendingDeletion() async {
    final snapshot = await ownerWrites.inspect();
    final entry = await _loadJournal();
    if (entry == null) {
      if (snapshot == null) return null;
      if (snapshot.cloudReceipt != null) {
        return _resumeConfirmed(snapshot, journalPresent: false);
      }
      throw const AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
      );
    }

    var recovered = await _adoptJournal(entry);
    if (recovered.cloudReceipt == null) {
      late final CloudDeletionReceipt serverReceipt;
      try {
        serverReceipt = await cloud.deleteRecursively(
          ownerId: entry.ownerId,
          firebaseUid: entry.firebaseUid,
          idempotencyKey: entry.idempotencyKey,
          exportReceipt: entry.exportReceipt!,
          authenticationReceipt: entry.authenticationReceipt!,
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
        serverReceipt,
        ownerId: entry.ownerId,
        firebaseUid: entry.firebaseUid,
        idempotencyKey: entry.idempotencyKey,
      );
      final cloudReceipt = serverReceipt.durableMarker();
      await ownerWrites.markCloud(recovered.casToken!, cloudReceipt);
      await _saveCloudReceipt(cloudReceipt);
      recovered = (await ownerWrites.inspect())!;
    }
    return _resumeConfirmed(recovered, journalPresent: true);
  }

  Future<DeletionIntentSnapshot> _adoptJournal(
    AccountDeletionJournalEntry entry,
  ) async {
    try {
      if (entry.cloudReceipt case final receipt?) {
        _validateCloud(
          receipt.durableMarker(),
          ownerId: entry.ownerId,
          firebaseUid: entry.firebaseUid,
          idempotencyKey: durableAccountDeletionBinding(entry.idempotencyKey),
        );
        if (entry.localReceipt case final local?) {
          _validateLocal(local, entry.ownerId, receipt);
        }
      } else {
        final exportReceipt = entry.exportReceipt;
        final authenticationReceipt = entry.authenticationReceipt;
        if (entry.ownerId.isEmpty ||
            entry.firebaseUid.isEmpty ||
            !RegExp(
              r'^[A-Za-z0-9._:-]{16,128}$',
            ).hasMatch(entry.idempotencyKey) ||
            exportReceipt == null ||
            authenticationReceipt == null) {
          throw const AccountDeletionException(
            AccountDeletionFailureCode.unavailable,
          );
        }
        _validateExport(exportReceipt, entry.ownerId);
        _validatePersistedAuthentication(
          authenticationReceipt,
          entry.firebaseUid,
        );
      }
      return await ownerWrites.adoptRecovery(entry);
    } catch (_) {
      await ownerWrites.preserveRecoveryUncertainty();
      rethrow;
    }
  }

  Future<AccountDeletionJournalEntry?> _loadJournal() async {
    try {
      return await journal.load();
    } catch (error) {
      await ownerWrites.preserveRecoveryUncertainty();
      if (error is AccountDeletionException) rethrow;
      throw AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
        cause: error,
      );
    }
  }

  Future<LocalDeletionReceipt> _resumeConfirmed(
    DeletionIntentSnapshot snapshot, {
    required bool journalPresent,
  }) async {
    final cloud = snapshot.cloudReceipt!;
    _validateCloud(
      cloud,
      ownerId: cloud.ownerId,
      firebaseUid: cloud.firebaseUid,
      idempotencyKey: cloud.idempotencyKey,
    );
    final completed = snapshot.localReceipt;
    if (completed != null) {
      _validateLocal(completed, cloud.ownerId, cloud);
      if (journalPresent) {
        await _saveCloudReceipt(cloud);
        await _saveLocalReceipt(cloud, completed);
      }
      await ownerWrites.clearCompleted(snapshot.casToken!);
      return completed;
    }
    await _saveCloudReceipt(cloud);
    return _deleteLocalAndJournal(
      intent: snapshot.casToken!,
      ownerId: cloud.ownerId,
      cloudReceipt: cloud,
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
      durableAccountDeletionBinding(left.idempotencyKey) ==
          durableAccountDeletionBinding(right.idempotencyKey) &&
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

  void _validatePersistedAuthentication(
    RecentAuthenticationReceipt receipt,
    String firebaseUid,
  ) {
    if (receipt.firebaseUid != firebaseUid ||
        !receipt.authenticatedAtUtc.isUtc ||
        receipt.authenticatedAtUtc.isAfter(_now().add(serverClockSkew))) {
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
    required DeletionIntentToken intent,
    required String ownerId,
    required CloudDeletionReceipt cloudReceipt,
  }) async {
    final localReceipt = await _deleteLocal(
      ownerId: ownerId,
      cloudReceipt: cloudReceipt,
    );
    await ownerWrites.markLocal(intent, cloudReceipt, localReceipt);
    await _saveLocalReceipt(cloudReceipt, localReceipt);
    await ownerWrites.clearCompleted(intent);
    return localReceipt;
  }

  Future<void> _saveLocalReceipt(
    CloudDeletionReceipt cloudReceipt,
    LocalDeletionReceipt localReceipt,
  ) async {
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

  Future<void> _savePendingOperation({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  }) async {
    try {
      await journal.savePendingOperation(
        ownerId: ownerId,
        firebaseUid: firebaseUid,
        idempotencyKey: idempotencyKey,
        exportReceipt: exportReceipt,
        authenticationReceipt: authenticationReceipt,
      );
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
        cause: error,
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
