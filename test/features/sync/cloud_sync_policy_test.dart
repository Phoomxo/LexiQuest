import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';
import 'package:vocab_learning_app/features/sync/data/drift_cloud_policy_cache.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  late AppDatabase database;
  late DriftCloudPolicyCache cache;
  final now = DateTime.utc(2026, 7, 30, 13);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    cache = DriftCloudPolicyCache(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('build kill switch never contacts cloud', () async {
    final gateway = _PolicyGateway(policy: _policy(enabled: true, now: now));
    final provider = CloudSyncPolicyProvider(
      buildEnabled: false,
      cache: cache,
      gateway: gateway,
      nowUtc: () => now,
    );

    final policy = await provider();

    expect(policy.enabled, isFalse);
    expect(policy.source, CloudSyncPolicySource.build);
    expect(gateway.fetches, 0);
  });

  test('fresh cached remote off switch stops work without a refresh', () async {
    await cache.write(_policy(enabled: false, now: now));
    final gateway = _PolicyGateway(policy: _policy(enabled: true, now: now));
    final provider = CloudSyncPolicyProvider(
      buildEnabled: true,
      cache: cache,
      gateway: gateway,
      nowUtc: () => now.add(const Duration(minutes: 5)),
    );

    final policy = await provider();

    expect(policy.enabled, isFalse);
    expect(policy.source, CloudSyncPolicySource.cache);
    expect(gateway.fetches, 0);
  });

  test('expired policy refreshes and persists the remote value', () async {
    await cache.write(_policy(enabled: false, now: now));
    final refreshedAt = now.add(const Duration(minutes: 20));
    final gateway = _PolicyGateway(
      policy: _policy(enabled: true, now: refreshedAt),
    );
    final provider = CloudSyncPolicyProvider(
      buildEnabled: true,
      cache: cache,
      gateway: gateway,
      nowUtc: () => refreshedAt,
    );

    final policy = await provider();
    final persisted = await cache.read();

    expect(policy.enabled, isTrue);
    expect(gateway.fetches, 1);
    expect(persisted?.enabled, isTrue);
    expect(persisted?.source, CloudSyncPolicySource.cache);
  });

  test('refresh failure fails closed without blocking local code', () async {
    final gateway = _PolicyGateway(error: const OfflineSyncFailure());
    final provider = CloudSyncPolicyProvider(
      buildEnabled: true,
      cache: cache,
      gateway: gateway,
      nowUtc: () => now,
    );

    final policy = await provider();

    expect(policy.enabled, isFalse);
    expect(policy.source, CloudSyncPolicySource.remote);
    expect(gateway.fetches, 1);
  });

  test(
    'trigger coalesces concurrent requests into one bounded follow-up',
    () async {
      final first = Completer<SyncRunResult>();
      final second = Completer<SyncRunResult>();
      var runs = 0;
      final trigger = SyncTrigger(() {
        runs += 1;
        return runs == 1 ? first.future : second.future;
      });

      final a = trigger.request(SyncTriggerReason.localMutation);
      final b = trigger.request(SyncTriggerReason.appResume);
      final c = trigger.request(SyncTriggerReason.manualRetry);
      expect(runs, 1);

      first.complete(
        const SyncRunResult(status: SyncRunStatus.completed, pushed: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runs, 2);
      second.complete(
        const SyncRunResult(status: SyncRunStatus.completed, pulled: 1),
      );

      expect((await a).pulled, 1);
      expect(identical(a, b), isTrue);
      expect(identical(b, c), isTrue);
      expect(runs, 2);
    },
  );
}

CloudSyncPolicy _policy({required bool enabled, required DateTime now}) =>
    CloudSyncPolicy(
      enabled: enabled,
      source: CloudSyncPolicySource.remote,
      fetchedAtUtc: now,
      expiresAtUtc: now.add(const Duration(minutes: 15)),
    );

final class _PolicyGateway implements SyncGateway {
  _PolicyGateway({this.policy, this.error});

  final CloudSyncPolicy? policy;
  final SyncFailure? error;
  int fetches = 0;

  @override
  Future<CloudSyncPolicy> fetchPolicy() async {
    fetches += 1;
    final captured = error;
    if (captured != null) throw captured;
    return policy!;
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PushResult> push(PushMutation mutation) {
    throw UnimplementedError();
  }
}
