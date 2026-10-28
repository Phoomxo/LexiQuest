import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/app_database.dart' as db;
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../account_deletion/domain/owner_write_coordinator.dart';
import '../domain/owner_upgrade.dart';

final class DriftOwnerWriteCoordinator implements OwnerWriteCoordinator {
  DriftOwnerWriteCoordinator(
    this._database, {
    required this.nowUtc,
    String Function()? nonceGenerator,
  }) : _nonceGenerator = nonceGenerator ?? (() => const Uuid().v4());

  static const _intentKey = 'accountDeletion.ownerWriteIntent';
  static final _hashPattern = RegExp(r'^sha256:[0-9a-f]{64}$');

  final db.AppDatabase _database;
  final DateTime Function() nowUtc;
  final String Function() _nonceGenerator;

  @override
  Future<T> writeForActiveOwner<T>({
    required String expectedOwnerId,
    required Future<T> Function() write,
  }) async {
    _requireText(expectedOwnerId);
    return _write(() async {
      await _requireActiveOwner(expectedOwnerId);
      _requireUnfenced(await _load(), expectedOwnerId);
      return write();
    });
  }

  @override
  Future<void> requireOwnerUnfenced(String ownerId) async {
    _requireText(ownerId);
    return _write(() async => _requireUnfenced(await _load(), ownerId));
  }

  @override
  Future<DeletionIntentSnapshot?> inspect() => _load();

  @override
  Future<DeletionIntentSnapshot> adoptRecovery(
    AccountDeletionJournalEntry entry,
  ) => _write(() async {
    _requireText(entry.ownerId);
    _requireText(entry.firebaseUid);
    _requireText(entry.idempotencyKey);
    if (!_hashPattern.hasMatch(
      durableAccountDeletionBinding(entry.idempotencyKey),
    )) {
      _invalidTransition();
    }
    final existing = await _load();
    if (existing != null &&
        existing.casToken?.matchesOperation(
              ownerId: entry.ownerId,
              firebaseUid: entry.firebaseUid,
              idempotencyKey: entry.idempotencyKey,
            ) !=
            true) {
      _invalidTransition();
    }
    final nonce = existing == null ? _nonceGenerator() : null;
    if (nonce != null) _requireText(nonce);
    final token =
        existing?.casToken ??
        DeletionIntentToken.bind(
          ownerId: entry.ownerId,
          firebaseUid: entry.firebaseUid,
          idempotencyKey: entry.idempotencyKey,
          nonce: nonce!,
        );
    final suppliedCloud = entry.cloudReceipt;
    final cloud = suppliedCloud == null
        ? existing?.cloudReceipt
        : _validateCloud(token, suppliedCloud);
    if (existing?.cloudReceipt case final saved?) {
      if (cloud == null || !_sameCloud(saved, cloud)) _invalidCloud();
    }
    final suppliedLocal = entry.localReceipt;
    if (suppliedLocal != null && cloud == null) _invalidLocal();
    final local = suppliedLocal ?? existing?.localReceipt;
    if (local != null) {
      _validateLocal(cloud!, local);
      if (existing?.localReceipt case final saved?) {
        if (!_sameLocal(saved, local)) _invalidLocal();
      }
      await _requirePurgeProof(cloud, local);
    } else {
      await _requireRecoveryOwner(entry, cloud);
    }
    final recovered = DeletionIntentSnapshot(
      phase: local != null
          ? DeletionIntentPhase.localCompleted
          : cloud != null
          ? DeletionIntentPhase.cloudConfirmed
          : DeletionIntentPhase.pendingCloud,
      casToken: token,
      cloudReceipt: cloud,
      localReceipt: local,
    );
    await _save(recovered);
    return recovered;
  });

  Future<void> _requireRecoveryOwner(
    AccountDeletionJournalEntry entry,
    CloudDeletionReceipt? cloud,
  ) async {
    final original = await (_database.select(
      _database.localOwners,
    )..where((row) => row.id.equals(entry.ownerId))).getSingleOrNull();
    if (original != null) {
      final active = await _requireActiveOwner(entry.ownerId);
      if (active.firebaseUid != entry.firebaseUid) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.invalidIdentity,
        );
      }
      return;
    }
    if (cloud == null) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.ownerChanged,
      );
    }
    // SQL may have committed before the secure-key purge acknowledged success.
    final guest = await _requireActiveOwner(
      accountDeletionReplacementGuestOwnerId(cloud),
    );
    await _requirePurgeProof(
      cloud,
      LocalDeletionReceipt(
        deletedOwnerId: cloud.ownerId,
        newGuestOwnerId: guest.id,
        completedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          guest.createdAtUtcMs,
          isUtc: true,
        ),
      ),
    );
  }

  @override
  Future<DeletionIntentToken> beginDeletion({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
  }) async {
    _requireText(ownerId);
    _requireText(firebaseUid);
    _requireText(idempotencyKey);
    if (!_hashPattern.hasMatch(durableAccountDeletionBinding(idempotencyKey))) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.invalidRequest,
      );
    }
    return _write(() async {
      final owner = await _requireActiveOwner(ownerId);
      if (owner.firebaseUid != firebaseUid) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.invalidIdentity,
        );
      }
      final existing = await _load();
      if (existing != null) {
        final token = existing.casToken;
        if (token != null &&
            token.matchesOperation(
              ownerId: ownerId,
              firebaseUid: firebaseUid,
              idempotencyKey: idempotencyKey,
            )) {
          return token;
        }
        throw const AccountDeletionException(
          AccountDeletionFailureCode.invalidRequest,
        );
      }
      final nonce = _nonceGenerator();
      _requireText(nonce);
      final token = DeletionIntentToken.bind(
        ownerId: ownerId,
        firebaseUid: firebaseUid,
        idempotencyKey: idempotencyKey,
        nonce: nonce,
      );
      await _save(
        DeletionIntentSnapshot(
          phase: DeletionIntentPhase.preparing,
          casToken: token,
        ),
      );
      return token;
    });
  }

  @override
  Future<void> markPending(DeletionIntentToken token) => _write(() async {
    final state = await _requireAttempt(token);
    if (state.phase == DeletionIntentPhase.pendingCloud) return;
    if (state.phase != DeletionIntentPhase.preparing) _invalidTransition();
    await _save(
      DeletionIntentSnapshot(
        phase: DeletionIntentPhase.pendingCloud,
        casToken: state.casToken,
      ),
    );
  });

  @override
  Future<void> markCloud(
    DeletionIntentToken token,
    CloudDeletionReceipt cloud,
  ) async {
    final durable = _validateCloud(token, cloud);
    return _write(() async {
      final state = await _requireAttempt(token);
      if (state.phase == DeletionIntentPhase.cloudConfirmed ||
          state.phase == DeletionIntentPhase.localCompleted) {
        if (!_sameCloud(state.cloudReceipt!, durable)) _invalidCloud();
        return;
      }
      if (state.phase != DeletionIntentPhase.pendingCloud) _invalidTransition();
      await _save(
        DeletionIntentSnapshot(
          phase: DeletionIntentPhase.cloudConfirmed,
          casToken: state.casToken,
          cloudReceipt: durable,
        ),
      );
    });
  }

  @override
  Future<void> markLocal(
    DeletionIntentToken token,
    CloudDeletionReceipt cloud,
    LocalDeletionReceipt local,
  ) async {
    final durable = _validateCloud(token, cloud);
    _validateLocal(durable, local);
    return _write(() async {
      final state = await _requireAttempt(token);
      if (state.cloudReceipt == null ||
          !_sameCloud(state.cloudReceipt!, durable)) {
        _invalidCloud();
      }
      if (state.phase != DeletionIntentPhase.cloudConfirmed &&
          state.phase != DeletionIntentPhase.localCompleted) {
        _invalidTransition();
      }
      await _requirePurgeProof(durable, local);
      if (state.phase == DeletionIntentPhase.localCompleted) {
        if (!_sameLocal(state.localReceipt!, local)) _invalidLocal();
        return;
      }
      await _save(
        DeletionIntentSnapshot(
          phase: DeletionIntentPhase.localCompleted,
          casToken: state.casToken,
          cloudReceipt: durable,
          localReceipt: local,
        ),
      );
    });
  }

  @override
  Future<bool> abortPreparing(DeletionIntentToken token) => _write(() async {
    final state = await _load();
    if (state?.phase != DeletionIntentPhase.preparing ||
        state?.casToken?.sameAttempt(token) != true) {
      return false;
    }
    await _delete();
    return true;
  });

  @override
  Future<void> clearCompleted(DeletionIntentToken token) => _write(() async {
    final state = await _requireAttempt(token);
    if (state.phase != DeletionIntentPhase.localCompleted) _invalidTransition();
    await _requirePurgeProof(state.cloudReceipt!, state.localReceipt!);
    await _delete();
  });

  @override
  Future<void> preserveRecoveryUncertainty() => _write(() async {
    final state = await _load();
    if (state == null) {
      await _save(const DeletionIntentSnapshot.uncertain());
    } else if (state.phase == DeletionIntentPhase.preparing) {
      await _save(
        DeletionIntentSnapshot(
          phase: DeletionIntentPhase.pendingCloud,
          casToken: state.casToken,
        ),
      );
    }
  });

  Future<T> _write<T>(Future<T> Function() operation) =>
      _database.transaction(() async {
        // Acquire SQLite's writer before reading an owner or intent snapshot.
        await _database.customUpdate(
          'UPDATE local_owners SET is_active = is_active WHERE is_active = 1',
        );
        return operation();
      });

  Future<db.LocalOwner> _requireActiveOwner(String expectedOwnerId) async {
    final owners =
        await (_database.select(_database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .get();
    if (owners.length != 1 || owners.single.id != expectedOwnerId) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.ownerChanged,
      );
    }
    return owners.single;
  }

  void _requireUnfenced(DeletionIntentSnapshot? state, String ownerId) {
    if (state == null) return;
    if (state.casToken == null ||
        state.casToken!.matchesOwner(ownerId) ||
        (state.cloudReceipt != null &&
            ownerId ==
                accountDeletionReplacementGuestOwnerId(state.cloudReceipt!))) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
      );
    }
  }

  Future<DeletionIntentSnapshot> _requireAttempt(
    DeletionIntentToken token,
  ) async {
    final state = await _load();
    if (state == null || state.casToken?.sameAttempt(token) != true) {
      _invalidTransition();
    }
    return state;
  }

  Future<void> _requirePurgeProof(
    CloudDeletionReceipt cloud,
    LocalDeletionReceipt local,
  ) async {
    final original = await (_database.select(
      _database.localOwners,
    )..where((row) => row.id.equals(cloud.ownerId))).getSingleOrNull();
    if (original != null) _invalidLocal();
    final guest = await _requireActiveOwner(local.newGuestOwnerId);
    if (guest.firebaseUid != null ||
        guest.accountState != 'localGuest' ||
        guest.createdAtUtcMs != local.completedAtUtc.millisecondsSinceEpoch) {
      _invalidLocal();
    }
    for (final table in ownerUpgradeInventory) {
      final remaining = await _database
          .customSelect(
            'SELECT 1 FROM $table WHERE owner_id = ? LIMIT 1',
            variables: [Variable<String>(cloud.ownerId)],
          )
          .getSingleOrNull();
      if (remaining != null) _invalidLocal();
    }
  }

  Future<DeletionIntentSnapshot?> _load() async {
    final row = await (_database.select(
      _database.runtimeFlags,
    )..where((row) => row.key.equals(_intentKey))).getSingleOrNull();
    if (row == null) return null;
    try {
      if (!row.boolValue ||
          row.expiresAtUtcMs != null ||
          row.source.length > 16384) {
        throw const FormatException('invalid intent marker');
      }
      final json = _object(jsonDecode(row.source));
      if (json['version'] != 1 || json['phase'] is! String) {
        throw const FormatException('unsupported intent format');
      }
      final phase = DeletionIntentPhase.values.singleWhere(
        (phase) => phase.name == json['phase'],
      );
      if (phase == DeletionIntentPhase.recoveryUncertain) {
        _requireKeys(json, {'version', 'phase'});
        return const DeletionIntentSnapshot.uncertain();
      }
      final token = DeletionIntentToken.fromBindings(
        ownerBinding: _binding(json['ownerBinding']),
        firebaseUidBinding: _binding(json['firebaseUidBinding']),
        operationBinding: _binding(json['operationBinding']),
        nonceBinding: _binding(json['nonceBinding']),
      );
      final hasCloud =
          phase == DeletionIntentPhase.cloudConfirmed ||
          phase == DeletionIntentPhase.localCompleted;
      final hasLocal = phase == DeletionIntentPhase.localCompleted;
      _requireKeys(json, {
        'version',
        'phase',
        'ownerBinding',
        'firebaseUidBinding',
        'operationBinding',
        'nonceBinding',
        if (hasCloud) 'cloudReceipt',
        if (hasLocal) 'localReceipt',
      });
      CloudDeletionReceipt? cloud;
      if (hasCloud) {
        final value = _object(json['cloudReceipt']);
        _requireKeys(value, {
          'receiptId',
          'ownerId',
          'firebaseUid',
          'idempotencyKey',
          'completedAtUtc',
        });
        cloud = CloudDeletionReceipt(
          receiptId: _text(value['receiptId']),
          ownerId: _text(value['ownerId']),
          firebaseUid: _text(value['firebaseUid']),
          idempotencyKey: _binding(value['idempotencyKey']),
          completedAtUtc: _date(value['completedAtUtc']),
        );
        _validateCloud(token, cloud);
      }
      LocalDeletionReceipt? local;
      if (hasLocal) {
        final value = _object(json['localReceipt']);
        _requireKeys(value, {
          'deletedOwnerId',
          'newGuestOwnerId',
          'completedAtUtc',
        });
        local = LocalDeletionReceipt(
          deletedOwnerId: _text(value['deletedOwnerId']),
          newGuestOwnerId: _text(value['newGuestOwnerId']),
          completedAtUtc: _date(value['completedAtUtc']),
        );
        _validateLocal(cloud!, local);
      }
      return DeletionIntentSnapshot(
        phase: phase,
        casToken: token,
        cloudReceipt: cloud,
        localReceipt: local,
      );
    } catch (_) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.unavailable,
      );
    }
  }

  Future<void> _save(DeletionIntentSnapshot state) async {
    final token = state.casToken;
    final cloud = state.cloudReceipt;
    final local = state.localReceipt;
    final source = jsonEncode({
      'version': 1,
      'phase': state.phase.name,
      if (token != null) ...{
        'ownerBinding': token.ownerBinding,
        'firebaseUidBinding': token.firebaseUidBinding,
        'operationBinding': token.operationBinding,
        'nonceBinding': token.nonceBinding,
      },
      if (cloud != null)
        'cloudReceipt': {
          'receiptId': cloud.receiptId,
          'ownerId': cloud.ownerId,
          'firebaseUid': cloud.firebaseUid,
          'idempotencyKey': cloud.idempotencyKey,
          'completedAtUtc': cloud.completedAtUtc.toIso8601String(),
        },
      if (local != null)
        'localReceipt': {
          'deletedOwnerId': local.deletedOwnerId,
          'newGuestOwnerId': local.newGuestOwnerId,
          'completedAtUtc': local.completedAtUtc.toIso8601String(),
        },
    });
    if (source.length > 16384) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.invalidRequest,
      );
    }
    final now = nowUtc();
    if (!_validDate(now)) throw ArgumentError.value(now, 'nowUtc');
    await _database
        .into(_database.runtimeFlags)
        .insertOnConflictUpdate(
          db.RuntimeFlagsCompanion.insert(
            key: _intentKey,
            boolValue: true,
            source: Value(source),
            updatedAtUtcMs: now.millisecondsSinceEpoch,
            expiresAtUtcMs: const Value(null),
          ),
        );
  }

  Future<void> _delete() async {
    await (_database.delete(
      _database.runtimeFlags,
    )..where((row) => row.key.equals(_intentKey))).go();
  }

  CloudDeletionReceipt _validateCloud(
    DeletionIntentToken token,
    CloudDeletionReceipt cloud,
  ) {
    if (cloud.receiptId.trim().isEmpty ||
        cloud.ownerId.trim().isEmpty ||
        cloud.firebaseUid.trim().isEmpty ||
        cloud.idempotencyKey.trim().isEmpty ||
        !_validDate(cloud.completedAtUtc) ||
        !token.matchesOperation(
          ownerId: cloud.ownerId,
          firebaseUid: cloud.firebaseUid,
          idempotencyKey: cloud.idempotencyKey,
        )) {
      _invalidCloud();
    }
    return cloud.durableMarker();
  }

  void _validateLocal(CloudDeletionReceipt cloud, LocalDeletionReceipt local) {
    if (local.deletedOwnerId != cloud.ownerId ||
        local.newGuestOwnerId !=
            accountDeletionReplacementGuestOwnerId(cloud) ||
        !_validDate(local.completedAtUtc)) {
      _invalidLocal();
    }
  }

  static bool _sameCloud(CloudDeletionReceipt a, CloudDeletionReceipt b) =>
      a.receiptId == b.receiptId &&
      a.ownerId == b.ownerId &&
      a.firebaseUid == b.firebaseUid &&
      a.idempotencyKey == b.idempotencyKey &&
      a.completedAtUtc == b.completedAtUtc;

  static bool _sameLocal(LocalDeletionReceipt a, LocalDeletionReceipt b) =>
      a.deletedOwnerId == b.deletedOwnerId &&
      a.newGuestOwnerId == b.newGuestOwnerId &&
      a.completedAtUtc == b.completedAtUtc;

  static void _requireText(String value) {
    if (value.trim().isEmpty) _invalidTransition();
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty) throw const FormatException();
    return value;
  }

  static String _binding(Object? value) {
    if (value is! String || !_hashPattern.hasMatch(value)) {
      throw const FormatException('invalid binding');
    }
    return value;
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    return value;
  }

  static void _requireKeys(Map<String, dynamic> value, Set<String> keys) {
    if (value.length != keys.length || !value.keys.every(keys.contains)) {
      throw const FormatException('invalid intent fields');
    }
  }

  static DateTime _date(Object? value) {
    final text = _text(value);
    final date = DateTime.parse(text);
    if (!text.endsWith('Z') || !_validDate(date)) throw const FormatException();
    return date;
  }

  static bool _validDate(DateTime date) =>
      date.isUtc && date.microsecondsSinceEpoch >= 0;

  static Never _invalidTransition() => throw const AccountDeletionException(
    AccountDeletionFailureCode.invalidRequest,
  );

  static Never _invalidCloud() => throw const AccountDeletionException(
    AccountDeletionFailureCode.invalidCloudReceipt,
  );

  static Never _invalidLocal() => throw const AccountDeletionException(
    AccountDeletionFailureCode.invalidLocalReceipt,
  );
}
