import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/cloud_sync_policy.dart';
import '../domain/sync_gateway.dart';

final class DriftCloudPolicyCache {
  const DriftCloudPolicyCache(this._database);

  static const String flagKey = 'cloudSyncEnabled';

  final db.AppDatabase _database;

  Future<CloudSyncPolicy?> read() async {
    final row = await (_database.select(
      _database.runtimeFlags,
    )..where((candidate) => candidate.key.equals(flagKey))).getSingleOrNull();
    final expiresAt = row?.expiresAtUtcMs;
    if (row == null || expiresAt == null) return null;
    return CloudSyncPolicy(
      enabled: row.boolValue,
      source: CloudSyncPolicySource.cache,
      fetchedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.updatedAtUtcMs,
        isUtc: true,
      ),
      expiresAtUtc: DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
    );
  }

  Future<void> write(CloudSyncPolicy policy) {
    return _database
        .into(_database.runtimeFlags)
        .insert(
          db.RuntimeFlagsCompanion.insert(
            key: flagKey,
            boolValue: policy.enabled,
            source: const Value('remote'),
            updatedAtUtcMs: policy.fetchedAtUtc.millisecondsSinceEpoch,
            expiresAtUtcMs: Value(policy.expiresAtUtc.millisecondsSinceEpoch),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }
}

final class CloudSyncPolicyProvider {
  factory CloudSyncPolicyProvider({
    required bool buildEnabled,
    required DriftCloudPolicyCache cache,
    required SyncGateway gateway,
    required DateTime Function() nowUtc,
  }) => CloudSyncPolicyProvider._(buildEnabled, cache, gateway, nowUtc);

  const CloudSyncPolicyProvider._(
    this.buildEnabled,
    this._cache,
    this._gateway,
    this._nowUtc,
  );

  final bool buildEnabled;
  final DriftCloudPolicyCache _cache;
  final SyncGateway _gateway;
  final DateTime Function() _nowUtc;

  Future<CloudSyncPolicy> call() async {
    final now = _requiredUtc(_nowUtc());
    if (!buildEnabled) {
      return CloudSyncPolicy(
        enabled: false,
        source: CloudSyncPolicySource.build,
        fetchedAtUtc: now,
        expiresAtUtc: now.add(const Duration(days: 36500)),
      );
    }

    final cached = await _cache.read();
    if (cached != null && !cached.isExpiredAt(now)) return cached;

    try {
      final remote = await _gateway.fetchPolicy();
      await _cache.write(remote);
      return remote;
    } catch (_) {
      return CloudSyncPolicy(
        enabled: false,
        source: CloudSyncPolicySource.remote,
        fetchedAtUtc: now,
        expiresAtUtc: now,
      );
    }
  }
}

DateTime _requiredUtc(DateTime value) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
  }
  return value;
}
