import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../sync/data/drift_owner_operation_gate.dart';
import '../../sync/domain/owner_operation_gate.dart';
import '../domain/local_owner.dart';
import '../domain/local_owner_repository.dart';

typedef LocalOwnerIdGenerator = String Function();
typedef UtcNow = DateTime Function();
typedef LocalOwnerGateDelay = Future<void> Function(Duration delay);

final class DriftLocalOwnerRepository implements LocalOwnerRepository {
  DriftLocalOwnerRepository(
    this._database, {
    required this.generateId,
    required this.nowUtc,
    OwnerOperationGate? ownerOperationGate,
    this.generateOwnerOperationToken = _defaultOwnerOperationToken,
    this.ownerGateDelay = _defaultOwnerGateDelay,
    this.ownerGateLeaseDuration = const Duration(minutes: 10),
    this.ownerGateHeartbeatInterval = const Duration(minutes: 3),
    this.ownerGateRetryInterval = const Duration(milliseconds: 50),
    this.ownerGateWaitTimeout = const Duration(seconds: 30),
  }) : ownerOperationGate =
           ownerOperationGate ?? DriftOwnerOperationGate(_database);

  final db.AppDatabase _database;
  final LocalOwnerIdGenerator generateId;
  final UtcNow nowUtc;
  final OwnerOperationGate ownerOperationGate;
  final LocalOwnerIdGenerator generateOwnerOperationToken;
  final LocalOwnerGateDelay ownerGateDelay;
  final Duration ownerGateLeaseDuration;
  final Duration ownerGateHeartbeatInterval;
  final Duration ownerGateRetryInterval;
  final Duration ownerGateWaitTimeout;
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

    return _serialized(
      () => _withOwnerOperationGate((operationToken) {
        return _database.transaction(() async {
          if (!await _fenceOwnerTransition(operationToken)) {
            throw StateError('owner-operation gate was lost');
          }
          final row =
              await (_database.select(_database.localOwners)..where(
                    (candidate) => candidate.id.equals(canonicalOwnerId),
                  ))
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
      }),
    );
  }

  Future<T> _withOwnerOperationGate<T>(
    Future<T> Function(String operationToken) operation,
  ) async {
    final operationToken = generateOwnerOperationToken().trim();
    if (operationToken.isEmpty) {
      throw StateError('owner-operation token generator returned a blank id');
    }
    final deadline = _requireUtc(nowUtc()).add(ownerGateWaitTimeout);
    while (!await ownerOperationGate.tryAcquire(
      token: operationToken,
      nowUtc: _requireUtc(nowUtc()),
      leaseDuration: ownerGateLeaseDuration,
    )) {
      if (!_requireUtc(nowUtc()).isBefore(deadline)) {
        throw TimeoutException('owner-operation gate wait timed out');
      }
      await ownerGateDelay(ownerGateRetryInterval);
    }

    final stopHeartbeat = Completer<void>();
    final heartbeat = _runOwnerGateHeartbeat(operationToken, stopHeartbeat);
    try {
      return await operation(operationToken);
    } finally {
      if (!stopHeartbeat.isCompleted) stopHeartbeat.complete();
      await heartbeat;
      await ownerOperationGate.release(token: operationToken);
    }
  }

  Future<void> _runOwnerGateHeartbeat(
    String operationToken,
    Completer<void> stop,
  ) async {
    while (true) {
      await Future.any<void>(<Future<void>>[
        ownerGateDelay(ownerGateHeartbeatInterval),
        stop.future,
      ]);
      if (stop.isCompleted) return;
      final renewed = await ownerOperationGate.renew(
        token: operationToken,
        nowUtc: _requireUtc(nowUtc()),
        leaseDuration: ownerGateLeaseDuration,
      );
      if (!renewed) return;
    }
  }

  Future<bool> _fenceOwnerTransition(String operationToken) async {
    final changed = await _database.customUpdate(
      '''
      UPDATE runtime_flags
      SET updated_at_utc_ms = updated_at_utc_ms
      WHERE "key" = ?
        AND bool_value = 1
        AND source = ?
        AND expires_at_utc_ms IS NOT NULL
        AND expires_at_utc_ms > ?
      ''',
      variables: [
        const Variable<String>(DriftOwnerOperationGate.gateKey),
        Variable<String>(operationToken),
        Variable<int>(_requireUtc(nowUtc()).millisecondsSinceEpoch),
      ],
      updates: {_database.runtimeFlags},
    );
    return changed == 1;
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

String _defaultOwnerOperationToken() => const Uuid().v4();

Future<void> _defaultOwnerGateDelay(Duration delay) =>
    Future<void>.delayed(delay);
