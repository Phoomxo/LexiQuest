import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/account_deletion/domain/account_deletion_contracts.dart';

final class SharedPreferencesAccountDeletionJournal
    implements AccountDeletionJournal {
  SharedPreferencesAccountDeletionJournal(
    this._preferences, {
    required this.nowUtc,
    required this.recoveryRetention,
  }) {
    if (recoveryRetention < Duration.zero ||
        recoveryRetention > maximumRecoveryRetention) {
      throw ArgumentError.value(
        recoveryRetention,
        'recoveryRetention',
        'must be non-negative and at most 30 days',
      );
    }
  }

  static const storageKey = 'account_deletion_journal_v1';
  static const maximumRecoveryRetention = Duration(days: 30);

  final SharedPreferences _preferences;
  final DateTime Function() nowUtc;
  final Duration recoveryRetention;
  Future<void> _writeGate = Future<void>.value();

  @override
  Future<AccountDeletionJournalEntry?> load() async {
    final encoded = _preferences.getString(storageKey);
    if (encoded == null) return null;
    try {
      final json = jsonDecode(encoded) as Map<String, Object?>;
      final cloudJson = json['cloudReceipt'];
      final exportJson = json['exportReceipt'];
      final authenticationJson = json['authenticationReceipt'];
      final cloud = cloudJson == null
          ? null
          : _cloudFromJson(cloudJson as Map<String, Object?>);
      final localJson = json['localReceipt'];
      final expiryJson = json['recoveryExpiresAtUtc'];
      final recoveryExpiresAtUtc = expiryJson == null
          ? null
          : DateTime.parse(expiryJson as String);
      if (cloud == null &&
          (recoveryExpiresAtUtc == null ||
              !recoveryExpiresAtUtc.isUtc ||
              _now().isAfter(recoveryExpiresAtUtc))) {
        await _clear();
        throw const AccountDeletionException(
          AccountDeletionFailureCode.recoveryExpired,
        );
      }
      return AccountDeletionJournalEntry(
        ownerId: json['ownerId'] as String?,
        firebaseUid: json['firebaseUid'] as String?,
        idempotencyKey: json['idempotencyKey'] as String?,
        exportReceipt: exportJson == null
            ? null
            : _exportFromJson(exportJson as Map<String, Object?>),
        authenticationReceipt: authenticationJson == null
            ? null
            : _authenticationFromJson(
                authenticationJson as Map<String, Object?>,
              ),
        cloudReceipt: cloud,
        localReceipt: localJson == null
            ? null
            : _localFromJson(localJson as Map<String, Object?>),
        recoveryExpiresAtUtc: recoveryExpiresAtUtc,
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

  @override
  Future<void> savePendingOperation({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  }) => _serialized(() async {
    if (recoveryRetention == Duration.zero) {
      throw const AccountDeletionException(AccountDeletionFailureCode.disabled);
    }
    final current = await load();
    if (current != null) {
      if (current.ownerId == ownerId &&
          current.firebaseUid == firebaseUid &&
          current.idempotencyKey == idempotencyKey) {
        return;
      }
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidRequest,
        cloudReceipt: current.cloudReceipt,
      );
    }
    await _write(
      AccountDeletionJournalEntry(
        ownerId: ownerId,
        firebaseUid: firebaseUid,
        idempotencyKey: idempotencyKey,
        exportReceipt: exportReceipt,
        authenticationReceipt: authenticationReceipt,
        recoveryExpiresAtUtc: _now().add(recoveryRetention),
      ),
    );
  });

  @override
  Future<void> saveCloudReceipt(CloudDeletionReceipt receipt) => _serialized(
    () async {
      final durableReceipt = receipt.durableMarker();
      final current = await load();
      if (current != null) {
        final savedCloud = current.cloudReceipt;
        if (savedCloud != null && _sameOperation(savedCloud, durableReceipt)) {
          return;
        }
        if (savedCloud != null) {
          throw AccountDeletionException(
            AccountDeletionFailureCode.invalidCloudReceipt,
            cloudReceipt: savedCloud,
          );
        }
        if (current.ownerId != receipt.ownerId ||
            current.firebaseUid != receipt.firebaseUid ||
            durableAccountDeletionBinding(current.idempotencyKey) !=
                durableReceipt.idempotencyKey) {
          throw AccountDeletionException(
            AccountDeletionFailureCode.invalidCloudReceipt,
            cloudReceipt: savedCloud,
          );
        }
      }
      await _write(
        AccountDeletionJournalEntry(
          ownerId: durableReceipt.ownerId,
          firebaseUid: durableReceipt.firebaseUid,
          idempotencyKey: durableReceipt.idempotencyKey,
          cloudReceipt: durableReceipt,
        ),
      );
    },
  );

  @override
  Future<void> saveLocalReceipt({
    required CloudDeletionReceipt cloudReceipt,
    required LocalDeletionReceipt localReceipt,
  }) => _serialized(() async {
    final durableReceipt = cloudReceipt.durableMarker();
    final current = await load();
    final savedCloud = current?.cloudReceipt;
    if (current == null ||
        savedCloud == null ||
        !_sameOperation(savedCloud, durableReceipt)) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidCloudReceipt,
        cloudReceipt: durableReceipt,
      );
    }
    if (current.localReceipt case final saved?) {
      if (!_sameLocalReceipt(saved, localReceipt)) {
        throw AccountDeletionException(
          AccountDeletionFailureCode.invalidLocalReceipt,
          cloudReceipt: durableReceipt,
        );
      }
      await _clear();
      return;
    }
    await _write(
      AccountDeletionJournalEntry(
        ownerId: current.ownerId,
        firebaseUid: current.firebaseUid,
        idempotencyKey: current.idempotencyKey,
        exportReceipt: current.exportReceipt,
        authenticationReceipt: current.authenticationReceipt,
        cloudReceipt: durableReceipt,
        localReceipt: localReceipt,
        recoveryExpiresAtUtc: current.recoveryExpiresAtUtc,
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
        'ownerId': entry.ownerId,
        'firebaseUid': entry.firebaseUid,
        'idempotencyKey': entry.idempotencyKey,
        'exportReceipt': switch (entry.exportReceipt) {
          final receipt? => _exportToJson(receipt),
          null => null,
        },
        'authenticationReceipt': switch (entry.authenticationReceipt) {
          final receipt? => _authenticationToJson(receipt),
          null => null,
        },
        'cloudReceipt': switch (entry.cloudReceipt) {
          final receipt? => _cloudToJson(receipt),
          null => null,
        },
        'localReceipt': switch (entry.localReceipt) {
          final receipt? => _localToJson(receipt),
          null => null,
        },
        'recoveryExpiresAtUtc': entry.recoveryExpiresAtUtc?.toIso8601String(),
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

  DateTime _now() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
    return value;
  }
}

Map<String, Object?> _exportToJson(FullAccountExportReceipt receipt) => {
  'ownerId': receipt.ownerId,
  'artifactId': receipt.artifactId,
  'artifactSha256': receipt.artifactSha256,
  'bytesWritten': receipt.bytesWritten,
  'schemaVersion': receipt.schemaVersion,
  'coveredScopes': receipt.coveredScopes.toList()..sort(),
  'completedAtUtc': receipt.completedAtUtc.toIso8601String(),
};

FullAccountExportReceipt _exportFromJson(Map<String, Object?> json) =>
    FullAccountExportReceipt(
      ownerId: json['ownerId'] as String,
      artifactId: json['artifactId'] as String,
      artifactSha256: json['artifactSha256'] as String,
      bytesWritten: json['bytesWritten'] as int,
      schemaVersion: json['schemaVersion'] as int,
      coveredScopes: (json['coveredScopes'] as List<Object?>)
          .cast<String>()
          .toSet(),
      completedAtUtc: DateTime.parse(json['completedAtUtc'] as String),
    );

Map<String, Object?> _authenticationToJson(
  RecentAuthenticationReceipt receipt,
) => {
  'firebaseUid': receipt.firebaseUid,
  'authenticatedAtUtc': receipt.authenticatedAtUtc.toIso8601String(),
};

RecentAuthenticationReceipt _authenticationFromJson(
  Map<String, Object?> json,
) => RecentAuthenticationReceipt(
  firebaseUid: json['firebaseUid'] as String,
  authenticatedAtUtc: DateTime.parse(json['authenticatedAtUtc'] as String),
);

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
