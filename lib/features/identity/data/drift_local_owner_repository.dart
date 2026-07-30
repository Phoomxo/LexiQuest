import 'dart:async';

import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../domain/local_owner.dart';
import '../domain/local_owner_repository.dart';

typedef LocalOwnerIdGenerator = String Function();
typedef UtcNow = DateTime Function();

final class DriftLocalOwnerRepository implements LocalOwnerRepository {
  DriftLocalOwnerRepository(
    this._database, {
    required this.generateId,
    required this.nowUtc,
  });

  final db.AppDatabase _database;
  final LocalOwnerIdGenerator generateId;
  final UtcNow nowUtc;
  Future<void> _writeGate = Future<void>.value();

  @override
  Future<LocalOwner> getOrCreateActiveOwner() {
    return _serialized(() {
      return _database.transaction(() async {
        final existing =
            await (_database.select(_database.localOwners)
                  ..where((row) => row.isActive.equals(true))
                  ..limit(1))
                .getSingleOrNull();
        if (existing != null) {
          return _toDomain(existing);
        }

        final now = _requireUtc(nowUtc());
        final ownerId = 'local:${generateId().trim()}';
        if (ownerId == 'local:') {
          throw StateError('local owner id generator returned a blank id');
        }
        await _database
            .into(_database.localOwners)
            .insert(
              db.LocalOwnersCompanion.insert(
                id: ownerId,
                createdAtUtcMs: now.millisecondsSinceEpoch,
              ),
            );
        return LocalOwner(id: ownerId, createdAtUtc: now);
      });
    });
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) async {
    final canonicalOwnerId = ownerId.trim();
    final canonicalUid = firebaseUid.trim();
    if (canonicalOwnerId.isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'must not be blank');
    }
    if (canonicalUid.isEmpty) {
      throw ArgumentError.value(
        firebaseUid,
        'firebaseUid',
        'must not be blank',
      );
    }

    return _serialized(() {
      return _database.transaction(() async {
        final row =
            await (_database.select(_database.localOwners)
                  ..where((candidate) => candidate.id.equals(canonicalOwnerId)))
                .getSingleOrNull();
        if (row == null || !row.isActive) {
          throw StateError('active local owner was not found');
        }
        if (row.firebaseUid == canonicalUid) {
          return _toDomain(row);
        }

        final upgradedAt = _requireUtc(nowUtc());
        await (_database.update(
          _database.localOwners,
        )..where((candidate) => candidate.id.equals(canonicalOwnerId))).write(
          db.LocalOwnersCompanion(
            firebaseUid: Value(canonicalUid),
            accountState: const Value('firebaseBound'),
            upgradedAtUtcMs: Value(upgradedAt.millisecondsSinceEpoch),
          ),
        );

        return LocalOwner(
          id: row.id,
          firebaseUid: canonicalUid,
          createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.createdAtUtcMs,
            isUtc: true,
          ),
          upgradedAtUtc: upgradedAt,
        );
      });
    });
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

  LocalOwner _toDomain(db.LocalOwner row) {
    return LocalOwner(
      id: row.id,
      firebaseUid: row.firebaseUid,
      createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.createdAtUtcMs,
        isUtc: true,
      ),
      upgradedAtUtc: row.upgradedAtUtcMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row.upgradedAtUtcMs!,
              isUtc: true,
            ),
    );
  }

  DateTime _requireUtc(DateTime value) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
    return value;
  }
}
