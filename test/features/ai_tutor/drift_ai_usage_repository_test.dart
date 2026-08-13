import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/drift_ai_usage_repository.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';

void main() {
  late AppDatabase database;
  late String activeOwner;
  late DriftAiUsageRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    activeOwner = 'owner-a';
    await _seedOwners(database);
    repository = DriftAiUsageRepository(
      database,
      activeOwnerId: () async => activeOwner,
    );
  });

  tearDown(() => database.close());

  test('strict begin precedes one CAS terminal transition', () async {
    final attempt = _attempt('event-a');
    await repository.beginForOwner('owner-a', attempt);
    final pending = await database.select(database.aiUsageEvents).getSingle();
    expect(pending.outcome, 'pending');
    expect(pending.latencyMs, 0);
    expect(pending.totalTokens, isNull);

    await expectLater(
      repository.beginForOwner('owner-a', attempt),
      throwsA(anything),
    );

    final completion = _success('event-a');
    expect(
      await repository.finalizeForOwner('owner-a', completion),
      AiUsageFinalizeResult.finalized,
    );
    expect(
      await repository.finalizeForOwner('owner-a', completion),
      AiUsageFinalizeResult.alreadyFinalized,
    );
    await expectLater(
      repository.finalizeForOwner(
        'owner-a',
        AiUsageCompletion(
          eventId: 'event-a',
          outcome: 'failure',
          errorCategory: 'offline',
          latencyMs: 20,
        ),
      ),
      throwsStateError,
    );
  });

  test('mixed reported and unknown provider costs fail closed', () async {
    for (final eventId in const ['known-cost', 'unknown-cost']) {
      await repository.beginForOwner('owner-a', _attempt(eventId));
    }
    await repository.finalizeForOwner(
      'owner-a',
      AiUsageCompletion(
        eventId: 'known-cost',
        outcome: 'success',
        latencyMs: 10,
        totalTokens: 7,
        providerReportedCostMicrosUsd: 100,
      ),
    );
    await repository.finalizeForOwner(
      'owner-a',
      AiUsageCompletion(
        eventId: 'unknown-cost',
        outcome: 'success',
        latencyMs: 10,
        totalTokens: 7,
      ),
    );

    final summary = (await repository.summarizeForOwner('owner-a')).single;
    expect(summary.requestCount, 2);
    expect(summary.providerReportedCostMicrosUsd, isNull);
  });

  test('pending rows are neither summarized, cleared, nor purged', () async {
    await repository.beginForOwner(
      'owner-a',
      _attempt('pending', at: DateTime.utc(2026, 1, 1)),
    );
    await repository.beginForOwner(
      'owner-a',
      _attempt('terminal', at: DateTime.utc(2026, 1, 1)),
    );
    await repository.finalizeForOwner('owner-a', _success('terminal'));

    expect((await repository.summarize()).single.requestCount, 1);
    await repository.clear();
    expect(await repository.summarize(), isEmpty);
    expect(await repository.purgeExpired(DateTime.utc(2026, 8, 2)), 0);
    final remaining = await database.select(database.aiUsageEvents).get();
    expect(remaining.map((row) => row.eventId), <String>['pending']);
  });

  test('clear and summaries remain active-owner-only', () async {
    for (final owner in <String>['owner-a', 'owner-b']) {
      await repository.beginForOwner(owner, _attempt('same-id'));
      await repository.finalizeForOwner(owner, _success('same-id'));
    }

    expect((await repository.summarize()).single.requestCount, 1);
    await repository.clear();
    expect(await repository.summarize(), isEmpty);
    activeOwner = 'owner-b';
    expect((await repository.summarize()).single.requestCount, 1);
  });

  test(
    'file reopen recovers stale pending for only the active owner',
    () async {
      await database.close();
      final root = await Directory.systemTemp.createTemp('ai-journal-');
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });
      final file = File('${root.path}${Platform.pathSeparator}usage.sqlite');
      database = AppDatabase(NativeDatabase(file));
      await _seedOwners(database);
      repository = DriftAiUsageRepository(
        database,
        activeOwnerId: () async => activeOwner,
      );
      await repository.beginForOwner(
        'owner-a',
        _attempt('old-a', at: DateTime.utc(2026, 8, 1, 10)),
      );
      await repository.beginForOwner(
        'owner-b',
        _attempt('old-b', at: DateTime.utc(2026, 8, 1, 10)),
      );
      await repository.beginForOwner(
        'owner-b',
        _attempt('recent-b', at: DateTime.utc(2026, 8, 1, 12)),
      );
      await database.close();

      database = AppDatabase(NativeDatabase(file));
      repository = DriftAiUsageRepository(
        database,
        activeOwnerId: () async => activeOwner,
      );
      expect(database.schemaVersion, 12);
      expect(
        await repository.recoverPendingStartedBefore(
          DateTime.utc(2026, 8, 1, 11),
          recoveredAtUtc: DateTime.utc(2026, 8, 1, 13),
        ),
        1,
      );
      expect(
        await repository.recoverPendingStartedBefore(
          DateTime.utc(2026, 8, 1, 11),
          recoveredAtUtc: DateTime.utc(2026, 8, 1, 13),
        ),
        0,
      );
      final rows = await database.select(database.aiUsageEvents).get();
      final byId = <String, AiUsageEventRow>{
        for (final row in rows) row.eventId: row,
      };
      expect(byId['old-a']!.outcome, 'indeterminate');
      expect(byId['old-a']!.errorCategory, 'processInterrupted');
      expect(byId['old-b']!.outcome, 'pending');
      expect(byId['recent-b']!.outcome, 'pending');
      final summary = (await repository.summarize()).single;
      expect(summary.failureCount, 0);
      expect(summary.indeterminateCount, 1);
    },
  );

  test('aggregate export is metadata-only and consent-gated', () async {
    await repository.beginForOwner('owner-a', _attempt('private-event-id'));
    await repository.finalizeForOwner(
      'owner-a',
      AiUsageCompletion(
        eventId: 'private-event-id',
        outcome: 'success',
        latencyMs: 10,
        totalTokens: 11,
      ),
    );
    await expectLater(
      repository.exportAggregateJson(researchConsent: false),
      throwsA(isA<AiTutorException>()),
    );
    final exported = await repository.exportAggregateJson(
      researchConsent: true,
    );
    expect(
      (jsonDecode(exported) as Map<String, dynamic>)['kind'],
      'ai_usage_aggregate',
    );
    expect(exported, isNot(contains('private-event-id')));
  });

  test(
    'production lease fence leaves stolen-token attempt pending for recovery',
    () async {
      final gate = DriftOwnerOperationGate(database);
      var now = DateTime.utc(2026, 8, 11, 4);
      var leaseToken = 'lease-a';
      await gate.tryAcquire(
        token: leaseToken,
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      );
      final fenced = DriftAiUsageRepository(
        database,
        activeOwnerId: () async => activeOwner,
        activeOwnerLeaseToken: () => leaseToken,
        nowUtc: () => now,
      );
      await fenced.beginForOwner('owner-a', _attempt('fenced-event', at: now));

      now = now.add(const Duration(minutes: 2));
      expect(
        await gate.tryAcquire(
          token: 'lease-b',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 1),
        ),
        isTrue,
      );
      await expectLater(
        fenced.finalizeForOwner('owner-a', _success('fenced-event')),
        throwsStateError,
      );
      expect(
        (await database.select(database.aiUsageEvents).getSingle()).outcome,
        'pending',
      );

      leaseToken = 'lease-b';
      expect(
        await fenced.recoverPendingStartedBefore(
          now.add(const Duration(seconds: 1)),
          recoveredAtUtc: now.add(const Duration(seconds: 2)),
        ),
        1,
      );
      expect(
        (await database.select(database.aiUsageEvents).getSingle()).outcome,
        'indeterminate',
      );
    },
  );

  test(
    'second database handle cannot turn a stale lease observation into a write',
    () async {
      final root = await Directory.systemTemp.createTemp('ai-fence-race-');
      final file = File('${root.path}${Platform.pathSeparator}usage.sqlite');
      final databaseA = AppDatabase(NativeDatabase(file));
      await _seedOwners(databaseA);
      final databaseB = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await databaseA.close();
        await databaseB.close();
        await root.delete(recursive: true);
      });
      var now = DateTime.utc(2026, 8, 11, 6);
      final gateA = DriftOwnerOperationGate(databaseA);
      final gateB = DriftOwnerOperationGate(databaseB);
      expect(
        await gateA.tryAcquire(
          token: 'lease-a',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 1),
        ),
        isTrue,
      );
      final repositoryA = DriftAiUsageRepository(
        databaseA,
        activeOwnerId: () async => 'owner-a',
        activeOwnerLeaseToken: () => 'lease-a',
        nowUtc: () => now,
      );
      await repositoryA.beginForOwner(
        'owner-a',
        _attempt('two-handle-event', at: now),
      );

      // A read-only observation is deliberately made stale before the
      // repository mutation. The repository must fence again with a write as
      // the first statement of its terminal transaction.
      expect(await gateA.isOwned(token: 'lease-a', nowUtc: now), isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(
        await gateB.tryAcquire(
          token: 'lease-b',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 1),
        ),
        isTrue,
      );

      await expectLater(
        repositoryA.finalizeForOwner('owner-a', _success('two-handle-event')),
        throwsStateError,
      );
      expect(
        (await databaseB.select(databaseB.aiUsageEvents).getSingle()).outcome,
        'pending',
      );
    },
  );
}

Future<void> _seedOwners(AppDatabase database) async {
  for (final owner in <String>['owner-a', 'owner-b']) {
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: owner, createdAtUtcMs: 1));
  }
}

AiUsageAttempt _attempt(String id, {DateTime? at}) => AiUsageAttempt(
  eventId: id,
  occurredAtUtc: at ?? DateTime.utc(2026, 8, 1),
  providerId: AiProviderId.openai,
  model: 'model-a',
  requestType: 'tutorReply',
);

AiUsageCompletion _success(String id) => AiUsageCompletion(
  eventId: id,
  outcome: 'success',
  latencyMs: 10,
  totalTokens: 7,
);
