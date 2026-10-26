import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/account_deletion/domain/account_deletion_contracts.dart';

final class SharedPreferencesAccountDeletionJournal
    implements AccountDeletionJournal {
  SharedPreferencesAccountDeletionJournal(this._preferences);

  static const storageKey = 'account_deletion_journal_v1';

  final SharedPreferences _preferences;
  Future<void> _writeGate = Future<void>.value();

  @override
  Future<AccountDeletionJournalEntry?> load() async {
    final encoded = _preferences.getString(storageKey);
    if (encoded == null) return null;
    try {
      final json = jsonDecode(encoded) as Map<String, Object?>;
      final cloud = _cloudFromJson(
        json['cloudReceipt'] as Map<String, Object?>,
      );
      final localJson = json['localReceipt'];
      return AccountDeletionJournalEntry(
        cloudReceipt: cloud,
        localReceipt: localJson == null
            ? null
            : _localFromJson(localJson as Map<String, Object?>),
      );
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
        cause: error,
      );
    }
  }

  @override
  Future<void> saveCloudReceipt(CloudDeletionReceipt receipt) =>
      _serialized(() async {
        final current = await load();
        if (current != null) {
          if (_sameOperation(current.cloudReceipt, receipt)) return;
          if (current.localReceipt == null) {
            throw AccountDeletionException(
              AccountDeletionFailureCode.invalidCloudReceipt,
              cloudReceipt: current.cloudReceipt,
            );
          }
        }
        await _write(AccountDeletionJournalEntry(cloudReceipt: receipt));
      });

  @override
  Future<void> saveLocalReceipt({
    required CloudDeletionReceipt cloudReceipt,
    required LocalDeletionReceipt localReceipt,
  }) => _serialized(() async {
    final current = await load();
    if (current == null ||
        !_sameOperation(current.cloudReceipt, cloudReceipt)) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidCloudReceipt,
        cloudReceipt: cloudReceipt,
      );
    }
    if (current.localReceipt case final saved?) {
      if (!_sameLocalReceipt(saved, localReceipt)) {
        throw AccountDeletionException(
          AccountDeletionFailureCode.invalidLocalReceipt,
          cloudReceipt: cloudReceipt,
        );
      }
      await _clear();
      return;
    }
    await _write(
      AccountDeletionJournalEntry(
        cloudReceipt: cloudReceipt,
        localReceipt: localReceipt,
      ),
    );
    await _clear();
  });

  Future<void> _clear() async {
    final removed = await _preferences.remove(storageKey);
    if (!removed) throw StateError('account deletion journal clear failed');
  }

  Future<void> _write(AccountDeletionJournalEntry entry) async {
    final written = await _preferences.setString(
      storageKey,
      jsonEncode({
        'cloudReceipt': _cloudToJson(entry.cloudReceipt),
        'localReceipt': switch (entry.localReceipt) {
          final receipt? => _localToJson(receipt),
          null => null,
        },
      }),
    );
    if (!written) throw StateError('account deletion journal write failed');
  }

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _writeGate;
    final completer = Completer<void>();
    _writeGate = completer.future;
    try {
      await previous;
      return await operation();
    } finally {
      completer.complete();
    }
  }
}

Map<String, Object?> _cloudToJson(CloudDeletionReceipt receipt) => {
  'receiptId': receipt.receiptId,
  'ownerId': receipt.ownerId,
  'firebaseUid': receipt.firebaseUid,
  'idempotencyKey': receipt.idempotencyKey,
  'completedAtUtc': receipt.completedAtUtc.toIso8601String(),
};

CloudDeletionReceipt _cloudFromJson(Map<String, Object?> json) =>
    CloudDeletionReceipt(
      receiptId: json['receiptId'] as String,
      ownerId: json['ownerId'] as String,
      firebaseUid: json['firebaseUid'] as String,
      idempotencyKey: json['idempotencyKey'] as String,
      completedAtUtc: DateTime.parse(json['completedAtUtc'] as String),
    );

Map<String, Object?> _localToJson(LocalDeletionReceipt receipt) => {
  'deletedOwnerId': receipt.deletedOwnerId,
  'newGuestOwnerId': receipt.newGuestOwnerId,
  'completedAtUtc': receipt.completedAtUtc.toIso8601String(),
};

LocalDeletionReceipt _localFromJson(Map<String, Object?> json) =>
    LocalDeletionReceipt(
      deletedOwnerId: json['deletedOwnerId'] as String,
      newGuestOwnerId: json['newGuestOwnerId'] as String,
      completedAtUtc: DateTime.parse(json['completedAtUtc'] as String),
    );

bool _sameOperation(CloudDeletionReceipt left, CloudDeletionReceipt right) =>
    left.receiptId == right.receiptId &&
    left.ownerId == right.ownerId &&
    left.firebaseUid == right.firebaseUid &&
    left.idempotencyKey == right.idempotencyKey &&
    left.completedAtUtc == right.completedAtUtc;

bool _sameLocalReceipt(LocalDeletionReceipt left, LocalDeletionReceipt right) =>
    left.deletedOwnerId == right.deletedOwnerId &&
    left.newGuestOwnerId == right.newGuestOwnerId &&
    left.completedAtUtc == right.completedAtUtc;
