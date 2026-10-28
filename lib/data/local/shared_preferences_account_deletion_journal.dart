import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/account_deletion/domain/account_deletion_contracts.dart';
import '../../features/account_deletion/domain/owner_write_coordinator.dart';

typedef _OperationJournal = ({
  String key,
  AccountDeletionJournalEntry? entry,
  bool legacyMatched,
});

final class SharedPreferencesAccountDeletionJournal
    implements AccountDeletionJournal {
  SharedPreferencesAccountDeletionJournal(
    this._preferences, {
    required this.nowUtc,
    required this.recoveryRetention,
    this.ownerWrites,
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
  static const operationStoragePrefix = 'account_deletion_journal_v2.';
  static const maximumRecoveryRetention = Duration(days: 30);

  final SharedPreferences _preferences;
  final DateTime Function() nowUtc;
  final Duration recoveryRetention;
  final OwnerWriteCoordinator? ownerWrites;
  Future<void> _writeGate = Future<void>.value();

  @override
  Future<AccountDeletionJournalEntry?> load() async {
    try {
      await _preferences.reload();
      final keys = _preferences
          .getKeys()
          .where(
            (key) =>
                key == storageKey || key.startsWith(operationStoragePrefix),
          )
          .toList();
      if (keys.isEmpty) return null;
      final intent = await ownerWrites?.inspect();
      final token = intent?.casToken;
      if (token != null) {
        final selectedKey = _storageKeyFromBindings(
          token.ownerBinding,
          token.firebaseUidBinding,
          token.operationBinding,
        );
        if (_preferences.containsKey(selectedKey)) {
          return await _read(selectedKey);
        }
        final legacy = _preferences.getString(storageKey);
        if (legacy != null) {
          final entry = _decode(legacy);
          if (token.matchesOperation(
            ownerId: entry.ownerId,
            firebaseUid: entry.firebaseUid,
            idempotencyKey: entry.idempotencyKey,
          )) {
            return await _read(storageKey);
          }
        }
        return null;
      }
      if (keys.length != 1 || intent != null) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.unavailable,
        );
      }
      return await _read(keys.single);
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
        cause: error,
      );
    }
  }

  AccountDeletionJournalEntry _decode(String encoded) {
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
    return AccountDeletionJournalEntry(
      ownerId: json['ownerId'] as String?,
      firebaseUid: json['firebaseUid'] as String?,
      idempotencyKey: json['idempotencyKey'] as String?,
      exportReceipt: exportJson == null
          ? null
          : _exportFromJson(exportJson as Map<String, Object?>),
      authenticationReceipt: authenticationJson == null
          ? null
          : _authenticationFromJson(authenticationJson as Map<String, Object?>),
      cloudReceipt: cloud,
      localReceipt: localJson == null
          ? null
          : _localFromJson(localJson as Map<String, Object?>),
      recoveryExpiresAtUtc: recoveryExpiresAtUtc,
    );
  }

  Future<AccountDeletionJournalEntry?> _read(String key) async {
    final encoded = _preferences.getString(key);
    if (encoded == null) return null;
    final entry = _decode(encoded);
    if (key != storageKey &&
        key !=
            _operationKey(
              entry.ownerId,
              entry.firebaseUid,
              entry.idempotencyKey,
            )) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
      );
    }
    final expiry = entry.recoveryExpiresAtUtc;
    if (entry.cloudReceipt == null &&
        (expiry == null || !expiry.isUtc || _now().isAfter(expiry))) {
      await _clear(key);
      throw const AccountDeletionException(
        AccountDeletionFailureCode.recoveryExpired,
      );
    }
    return entry;
  }

  Future<_OperationJournal> _loadOperation(
    String ownerId,
    String firebaseUid,
    String idempotencyKey,
  ) async {
    await _preferences.reload();
    final key = _operationKey(ownerId, firebaseUid, idempotencyKey);
    final legacyEncoded = _preferences.getString(storageKey);
    final legacy = legacyEncoded == null ? null : _decode(legacyEncoded);
    final legacyMatched =
        legacy != null &&
        _sameTuple(legacy, ownerId, firebaseUid, idempotencyKey);
    final current = await _read(key);
    final entry = current ?? (legacyMatched ? await _read(storageKey) : null);
    final currentCloud = current?.cloudReceipt;
    if (currentCloud != null &&
        legacyMatched &&
        legacy.cloudReceipt != null &&
        !_sameOperation(currentCloud, legacy.cloudReceipt!.durableMarker())) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.invalidCloudReceipt,
      );
    }
    return (key: key, entry: entry, legacyMatched: legacyMatched);
  }

  static String _operationKey(String ownerId, String firebaseUid, String key) =>
      _storageKeyFromBindings(
        _hash(ownerId),
        _hash(firebaseUid),
        durableAccountDeletionBinding(key),
      );

  static String _storageKeyFromBindings(
    String owner,
    String uid,
    String operation,
  ) =>
      '$operationStoragePrefix${sha256.convert(utf8.encode(jsonEncode([owner, uid, operation])))}';

  static String _hash(String value) =>
      'sha256:${sha256.convert(utf8.encode(value))}';

  static bool _sameTuple(
    AccountDeletionJournalEntry entry,
    String ownerId,
    String uid,
    String key,
  ) =>
      entry.ownerId == ownerId &&
      entry.firebaseUid == uid &&
      durableAccountDeletionBinding(entry.idempotencyKey) ==
          durableAccountDeletionBinding(key);

  Future<void> _clearLegacy(_OperationJournal operation) async {
    if (operation.legacyMatched) await _clear(storageKey);
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
    final operation = await _loadOperation(
      ownerId,
      firebaseUid,
      idempotencyKey,
    );
    final current = operation.entry;
    if (current != null) {
      if (_sameTuple(current, ownerId, firebaseUid, idempotencyKey)) {
        return;
      }
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidRequest,
        cloudReceipt: current.cloudReceipt,
      );
    }
    await _write(
      operation.key,
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
  Future<void> saveCloudReceipt(CloudDeletionReceipt receipt) =>
      _serialized(() async {
        final durableReceipt = receipt.durableMarker();
        final operation = await _loadOperation(
          receipt.ownerId,
          receipt.firebaseUid,
          receipt.idempotencyKey,
        );
        final current = operation.entry;
        if (current != null) {
          final savedCloud = current.cloudReceipt;
          if (savedCloud != null &&
              _sameOperation(savedCloud.durableMarker(), durableReceipt) &&
              !operation.legacyMatched) {
            return;
          }
          if (savedCloud != null &&
              !_sameOperation(savedCloud.durableMarker(), durableReceipt)) {
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
          operation.key,
          AccountDeletionJournalEntry(
            ownerId: durableReceipt.ownerId,
            firebaseUid: durableReceipt.firebaseUid,
            idempotencyKey: durableReceipt.idempotencyKey,
            cloudReceipt: durableReceipt,
            localReceipt: current?.localReceipt,
          ),
        );
        await _clearLegacy(operation);
      });

  @override
  Future<void> saveLocalReceipt({
    required CloudDeletionReceipt cloudReceipt,
    required LocalDeletionReceipt localReceipt,
  }) => _serialized(() async {
    final durableReceipt = cloudReceipt.durableMarker();
    final operation = await _loadOperation(
      cloudReceipt.ownerId,
      cloudReceipt.firebaseUid,
      cloudReceipt.idempotencyKey,
    );
    final current = operation.entry;
    final savedCloud = current?.cloudReceipt;
    if (current == null ||
        savedCloud == null ||
        !_sameOperation(savedCloud.durableMarker(), durableReceipt)) {
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
      await _clear(operation.key);
      await _clearLegacy(operation);
      return;
    }
    await _write(
      operation.key,
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
    await _clear(operation.key);
    await _clearLegacy(operation);
  });

  Future<void> _clear(String key) async {
    final removed = await _preferences.remove(key);
    if (!removed) throw StateError('account deletion journal clear failed');
  }

  Future<void> _write(String key, AccountDeletionJournalEntry entry) async {
    final written = await _preferences.setString(
      key,
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
