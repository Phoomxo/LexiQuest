import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../../runtime/runtime_flag_namespaces.dart';
import '../domain/owner_operation_gate.dart';

final class DriftOwnerOperationGate implements OwnerOperationGate {
  const DriftOwnerOperationGate(this.database);

  static const String gateKey = RuntimeFlagNamespaces.ownerOperationGate;

  final db.AppDatabase database;

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    final canonicalToken = _requiredToken(token);
    _requireUtc(nowUtc);
    _requirePositive(leaseDuration);
    final nowMs = nowUtc.millisecondsSinceEpoch;
    final changed = await database.customUpdate(
      '''
      INSERT INTO runtime_flags
        ("key", bool_value, source, updated_at_utc_ms, expires_at_utc_ms)
      VALUES (?, 1, ?, ?, ?)
      ON CONFLICT("key") DO UPDATE SET
        bool_value = 1,
        source = excluded.source,
        updated_at_utc_ms = excluded.updated_at_utc_ms,
        expires_at_utc_ms = excluded.expires_at_utc_ms
      WHERE runtime_flags.bool_value = 0
         OR runtime_flags.expires_at_utc_ms IS NULL
         OR runtime_flags.expires_at_utc_ms <= ?
      ''',
      variables: [
        const Variable<String>(gateKey),
        Variable<String>(canonicalToken),
        Variable<int>(nowMs),
        Variable<int>(nowUtc.add(leaseDuration).millisecondsSinceEpoch),
        Variable<int>(nowMs),
      ],
      updates: {database.runtimeFlags},
    );
    return changed == 1;
  }

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    final canonicalToken = _requiredToken(token);
    _requireUtc(nowUtc);
    _requirePositive(leaseDuration);
    final nowMs = nowUtc.millisecondsSinceEpoch;
    final changed = await database.customUpdate(
      '''
      UPDATE runtime_flags
      SET updated_at_utc_ms = ?, expires_at_utc_ms = ?
      WHERE "key" = ?
        AND bool_value = 1
        AND source = ?
        AND expires_at_utc_ms IS NOT NULL
        AND expires_at_utc_ms > ?
      ''',
      variables: [
        Variable<int>(nowMs),
        Variable<int>(nowUtc.add(leaseDuration).millisecondsSinceEpoch),
        const Variable<String>(gateKey),
        Variable<String>(canonicalToken),
        Variable<int>(nowMs),
      ],
      updates: {database.runtimeFlags},
    );
    return changed == 1;
  }

  @override
  Future<bool> isOwned({
    required String token,
    required DateTime nowUtc,
  }) async {
    final canonicalToken = _requiredToken(token);
    _requireUtc(nowUtc);
    final row = await database
        .customSelect(
          '''
      SELECT 1 AS owned
      FROM runtime_flags
      WHERE "key" = ?
        AND bool_value = 1
        AND source = ?
        AND expires_at_utc_ms IS NOT NULL
        AND expires_at_utc_ms > ?
      LIMIT 1
      ''',
          variables: [
            const Variable<String>(gateKey),
            Variable<String>(canonicalToken),
            Variable<int>(nowUtc.millisecondsSinceEpoch),
          ],
          readsFrom: {database.runtimeFlags},
        )
        .getSingleOrNull();
    return row != null;
  }

  /// Performs a write fence suitable as the first statement of a larger
  /// owner-scoped transaction.
  Future<void> requireOwned({
    required String token,
    required DateTime nowUtc,
  }) async {
    final canonicalToken = _requiredToken(token);
    _requireUtc(nowUtc);
    final changed = await database.customUpdate(
      '''
      UPDATE runtime_flags
      SET updated_at_utc_ms = updated_at_utc_ms
      WHERE "key" = ?
        AND bool_value = 1
        AND source = ?
        AND expires_at_utc_ms IS NOT NULL
        AND expires_at_utc_ms > ?
      ''',
      variables: <Variable<Object>>[
        const Variable<String>(gateKey),
        Variable<String>(canonicalToken),
        Variable<int>(nowUtc.millisecondsSinceEpoch),
      ],
      updates: <TableInfo<Table, Object?>>{database.runtimeFlags},
    );
    if (changed != 1) {
      throw StateError('Owner-operation lease was lost.');
    }
  }

  /// Associates an exact owner with the canonical process-wide lease.
  ///
  /// The marker is not a second lease: readers only honor it while the
  /// matching [gateKey] row is still owned and unexpired by [token]. A stale
  /// marker therefore becomes inert as soon as the canonical lease expires.
  Future<void> beginOwnerFence({
    required String ownerId,
    required String token,
    required DateTime nowUtc,
  }) async {
    final canonicalToken = _requiredToken(token);
    final fenceKey = _ownerFenceKey(ownerId);
    _requireUtc(nowUtc);
    await database.transaction(() async {
      await requireOwned(token: canonicalToken, nowUtc: nowUtc);
      await database
          .into(database.runtimeFlags)
          .insert(
            db.RuntimeFlagsCompanion.insert(
              key: fenceKey,
              boolValue: true,
              source: Value(canonicalToken),
              updatedAtUtcMs: nowUtc.millisecondsSinceEpoch,
              expiresAtUtcMs: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
    });
  }

  Future<bool> isOwnerFenced({
    required String ownerId,
    required DateTime nowUtc,
  }) async {
    final fenceKey = _ownerFenceKey(ownerId);
    _requireUtc(nowUtc);
    final row = await database
        .customSelect(
          '''
      SELECT 1 AS fenced
      FROM runtime_flags AS fence
      JOIN runtime_flags AS owner_gate
        ON owner_gate."key" = ?
       AND owner_gate.bool_value = 1
       AND owner_gate.source = fence.source
       AND owner_gate.expires_at_utc_ms IS NOT NULL
       AND owner_gate.expires_at_utc_ms > ?
      WHERE fence."key" = ?
        AND fence.bool_value = 1
      LIMIT 1
      ''',
          variables: <Variable<Object>>[
            const Variable<String>(gateKey),
            Variable<int>(nowUtc.millisecondsSinceEpoch),
            Variable<String>(fenceKey),
          ],
          readsFrom: <TableInfo<Table, Object?>>{database.runtimeFlags},
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<void> endOwnerFence({
    required String ownerId,
    required String token,
  }) async {
    final canonicalToken = _requiredToken(token);
    final fenceKey = _ownerFenceKey(ownerId);
    await (database.delete(database.runtimeFlags)..where(
          (row) => row.key.equals(fenceKey) & row.source.equals(canonicalToken),
        ))
        .go();
  }

  @override
  Future<void> release({required String token}) async {
    final canonicalToken = _requiredToken(token);
    await (database.delete(database.runtimeFlags)..where(
          (row) => row.key.equals(gateKey) & row.source.equals(canonicalToken),
        ))
        .go();
  }
}

String _requiredToken(String value) {
  final canonical = value.trim();
  if (canonical.isEmpty || canonical.length > 256) {
    throw ArgumentError.value(value, 'token', 'must contain 1-256 characters');
  }
  return canonical;
}

String _ownerFenceKey(String ownerId) {
  final canonicalOwnerId = ownerId.trim();
  if (canonicalOwnerId.isEmpty || canonicalOwnerId.length > 256) {
    throw ArgumentError.value(
      ownerId,
      'ownerId',
      'must contain 1-256 characters',
    );
  }
  final ownerDigest = sha256.convert(utf8.encode(canonicalOwnerId));
  return '${RuntimeFlagNamespaces.ownerOperationFencePrefix}$ownerDigest';
}

void _requireUtc(DateTime value) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
  }
}

void _requirePositive(Duration value) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, 'leaseDuration', 'must be positive');
  }
}
