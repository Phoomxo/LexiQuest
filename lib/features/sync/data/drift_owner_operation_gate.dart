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
