import 'dart:async';
import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../identity/domain/owner_upgrade.dart';
import '../domain/account_deletion_contracts.dart';

typedef LocalDeletionUtcNow = DateTime Function();
typedef PurgeOwnerSecret =
    Future<void> Function({
      required String ownerId,
      required String firebaseUid,
    });

final class DriftLocalAccountDeletionGateway
    implements LocalAccountDeletionGateway {
  DriftLocalAccountDeletionGateway(
    this._database, {
    required this.nowUtc,
    required this.purgeOwnerSecret,
  });

  final db.AppDatabase _database;
  final LocalDeletionUtcNow nowUtc;
  final PurgeOwnerSecret purgeOwnerSecret;
  Future<void> _writeGate = Future<void>.value();

  @override
  Future<LocalDeletionReceipt> deleteAfterCloud({
    required String ownerId,
    required CloudDeletionReceipt cloudReceipt,
  }) async {
    final owner = ownerId.trim();
    if (owner.isEmpty ||
        cloudReceipt.receiptId.trim().isEmpty ||
        cloudReceipt.ownerId != owner ||
        cloudReceipt.firebaseUid.trim().isEmpty ||
        cloudReceipt.idempotencyKey.trim().isEmpty ||
        !cloudReceipt.completedAtUtc.isUtc) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidCloudReceipt,
        cloudReceipt: cloudReceipt,
      );
    }
    final newGuestOwnerId = accountDeletionReplacementGuestOwnerId(
      cloudReceipt,
    );
    if (newGuestOwnerId == owner) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidCloudReceipt,
        cloudReceipt: cloudReceipt,
      );
    }
    return _serialized(() async {
      try {
        final receipt = await _database.transaction(() async {
          final boundOwner = await _database
              .customSelect(
                'SELECT id FROM local_owners '
                'WHERE id = ? AND firebase_uid = ? AND is_active = 1',
                variables: [
                  Variable<String>(owner),
                  Variable<String>(cloudReceipt.firebaseUid),
                ],
              )
              .getSingleOrNull();
          if (boundOwner == null) {
            final originalOwner = await _database
                .customSelect(
                  'SELECT id FROM local_owners WHERE id = ?',
                  variables: [Variable<String>(owner)],
                )
                .getSingleOrNull();
            if (originalOwner != null) {
              throw AccountDeletionException(
                AccountDeletionFailureCode.ownerChanged,
                cloudReceipt: cloudReceipt,
              );
            }
            final completedGuest = await _database
                .customSelect(
                  'SELECT created_at_utc_ms FROM local_owners '
                  "WHERE id = ? AND firebase_uid IS NULL AND account_state = 'localGuest' "
                  'AND is_active = 1',
                  variables: [Variable<String>(newGuestOwnerId)],
                )
                .getSingleOrNull();
            if (completedGuest != null) {
              return LocalDeletionReceipt(
                deletedOwnerId: owner,
                newGuestOwnerId: newGuestOwnerId,
                completedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                  completedGuest.read<int>('created_at_utc_ms'),
                  isUtc: true,
                ),
              );
            }
            throw AccountDeletionException(
              AccountDeletionFailureCode.ownerChanged,
              cloudReceipt: cloudReceipt,
            );
          }
          final activeOwners = await _database
              .customSelect(
                'SELECT id FROM local_owners WHERE is_active = 1 LIMIT 2',
              )
              .get();
          if (activeOwners.length != 1 ||
              activeOwners.single.read<String>('id') != owner) {
            throw AccountDeletionException(
              AccountDeletionFailureCode.ownerChanged,
              cloudReceipt: cloudReceipt,
            );
          }
          final collision = await _database
              .customSelect(
                'SELECT id FROM local_owners WHERE id = ?',
                variables: [Variable<String>(newGuestOwnerId)],
              )
              .getSingleOrNull();
          if (collision != null) {
            throw StateError('replacement local owner id collision');
          }
          final completedAt = _now();

          final deactivated = await _database.customUpdate(
            'UPDATE local_owners SET is_active = 0 '
            'WHERE id = ? AND is_active = 1',
            variables: [Variable<String>(owner)],
            updates: {_database.localOwners},
          );
          if (deactivated != 1) {
            throw StateError('bound local owner was not deactivated');
          }
          await _database
              .into(_database.localOwners)
              .insert(
                db.LocalOwnersCompanion.insert(
                  id: newGuestOwnerId,
                  createdAtUtcMs: completedAt.millisecondsSinceEpoch,
                ),
              );

          for (final table in ownerUpgradeInventory.toList().reversed) {
            await _database.customUpdate(
              'DELETE FROM $table WHERE owner_id = ?',
              variables: [Variable<String>(owner)],
              updates: _database.allTables.toSet(),
            );
          }
          final deleted = await (_database.delete(
            _database.localOwners,
          )..where((row) => row.id.equals(owner))).go();
          if (deleted != 1) {
            throw StateError('bound local owner was not deleted');
          }

          return LocalDeletionReceipt(
            deletedOwnerId: owner,
            newGuestOwnerId: newGuestOwnerId,
            completedAtUtc: completedAt,
          );
        });
        await purgeOwnerSecret(
          ownerId: owner,
          firebaseUid: cloudReceipt.firebaseUid,
        );
        return receipt;
      } on AccountDeletionException {
        rethrow;
      } catch (error) {
        throw AccountDeletionException(
          AccountDeletionFailureCode.localDeleteFailed,
          cause: error,
          cloudReceipt: cloudReceipt,
        );
      }
    });
  }

  DateTime _now() {
    final value = nowUtc();
    if (!value.isUtc ||
        value.isBefore(DateTime.fromMillisecondsSinceEpoch(0))) {
      throw ArgumentError.value(value, 'nowUtc', 'must be non-negative UTC');
    }
    return value;
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
