import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(id: 'owner-reconcile', createdAtUtcMs: 1),
        );
  });

  tearDown(() => database.close());

  Future<void> addEvent(
    int number, {
    String owner = 'owner-reconcile',
    DateTime? occurredAt,
  }) async {
    final at = occurredAt ?? DateTime.utc(2026, 8, number, 6);
    await database
        .into(database.eventsV2)
        .insert(
          EventsV2Companion.insert(
            eventId: 'learning-event:attempt-$number',
            eventType: 'QuizCompleted',
            eventVersion: 1,
            occurredAtUtc: at,
            recordedAtUtc: at,
            actorIdentity: owner,
            ownerId: owner,
            aggregateType: 'LearningSession',
            aggregateId: 'session-1',
            idempotencyKey: 'learning-attempt:attempt-$number:v1',
            consentContextJson: '{}',
            appVersion: '1.0.0',
            buildId: 'test-build',
            privacyClassification: 'anonymized',
            payloadJson: jsonEncode({'correct': true}),
          ),
        );
  }

  Future<Set<String>> applied(String projection) async {
    final rows = await (database.select(
      database.eventsV2,
    )..where((row) => row.eventType.equals('LearningProjectionApplied'))).get();
    return rows
        .where(
          (row) =>
              (jsonDecode(row.payloadJson)
                  as Map<String, dynamic>)['projection'] ==
              projection,
        )
        .map((row) => row.aggregateId)
        .toSet();
  }

  test('quest failure blocks reward until quest recovers', () async {
    await addEvent(1);
    var questCalls = 0;
    var rewardCalls = 0;
    final reconciler = LearningSideEffectReconciler(
      database,
      questSink: (_) async {
        if (++questCalls == 1) throw StateError('quest unavailable');
        return const LearningProjectionResult.applied(
          payload: {'eligible': true},
        );
      },
      rewardSink: (_, questResult) async {
        expect(questResult['eligible'], isTrue);
        rewardCalls++;
        return const LearningProjectionResult.applied();
      },
    );

    await reconciler.reconcileOwner('owner-reconcile');
    expect(rewardCalls, 0);
    expect(await applied('reward'), isEmpty);

    await reconciler.reconcileOwner('owner-reconcile');
    expect((questCalls, rewardCalls), (2, 1));
    expect(await applied('reward'), {'learning-event:attempt-1'});
  });

  test(
    'reward failure leaves no applied receipt and successful retry records it',
    () async {
      await addEvent(1);
      var rewardCalls = 0;
      final reconciler = LearningSideEffectReconciler(
        database,
        questSink: (_) async =>
            const LearningProjectionResult.applied(payload: {'eligible': true}),
        rewardSink: (_, _) async {
          if (++rewardCalls == 1) throw StateError('grant failed');
          return const LearningProjectionResult.applied();
        },
      );

      await reconciler.reconcileOwner('owner-reconcile');
      expect(await applied('reward'), isEmpty);
      await reconciler.reconcileOwner('owner-reconcile');
      expect(rewardCalls, 2);
      expect(await applied('reward'), {'learning-event:attempt-1'});
    },
  );

  test(
    'a no-op reward is evaluated but never represented as applied',
    () async {
      await addEvent(1);
      var rewardCalls = 0;
      final reconciler = LearningSideEffectReconciler(
        database,
        questSink: (_) async => const LearningProjectionResult.applied(),
        rewardSink: (_, _) async {
          rewardCalls++;
          return const LearningProjectionResult.notApplicable();
        },
      );
      await reconciler.reconcileOwner('owner-reconcile');
      await reconciler.reconcileOwner('owner-reconcile');
      expect(rewardCalls, 1);
      expect(await applied('reward'), isEmpty);
    },
  );

  test(
    'streak projection stops at first failure and preserves chronology',
    () async {
      await addEvent(1);
      await addEvent(2);
      final calls = <String>[];
      var failOldest = true;
      final reconciler = LearningSideEffectReconciler(
        database,
        streakSink: (event) async {
          calls.add(event.eventId);
          if (failOldest && event.eventId.endsWith('1')) {
            throw StateError('oldest failed');
          }
          return const LearningProjectionResult.applied();
        },
      );

      await reconciler.reconcileOwner('owner-reconcile');
      expect(calls, ['learning-event:attempt-1']);
      expect(await applied('streak'), isEmpty);
      failOldest = false;
      await reconciler.reconcileOwner('owner-reconcile');
      expect(calls, [
        'learning-event:attempt-1',
        'learning-event:attempt-1',
        'learning-event:attempt-2',
      ]);
    },
  );

  test(
    'equal timestamps use source event ID as deterministic cursor tie-break',
    () async {
      final sameTime = DateTime.utc(2026, 8, 9, 12);
      await addEvent(2, occurredAt: sameTime);
      await addEvent(1, occurredAt: sameTime);
      final calls = <String>[];
      final reconciler = LearningSideEffectReconciler(
        database,
        streakSink: (event) async {
          calls.add(event.eventId);
          return const LearningProjectionResult.applied();
        },
      );
      await reconciler.reconcileOwner('owner-reconcile');
      expect(calls, ['learning-event:attempt-1', 'learning-event:attempt-2']);
      await reconciler.reconcileOwner('owner-reconcile');
      expect(calls, hasLength(2));
    },
  );

  test(
    'each projection processes at most its configured pending batch',
    () async {
      for (var i = 1; i <= 5; i++) {
        await addEvent(i);
      }
      var calls = 0;
      final reconciler = LearningSideEffectReconciler(
        database,
        pendingBatchSize: 2,
        streakSink: (_) async {
          calls++;
          return const LearningProjectionResult.applied();
        },
      );
      await reconciler.reconcileOwner('owner-reconcile');
      expect(calls, 2);
      expect(await applied('streak'), hasLength(2));
    },
  );

  test(
    'scheduler request is non-blocking and dispose drains in-flight work',
    () async {
      await addEvent(1);
      final entered = Completer<void>();
      final release = Completer<void>();
      final reconciler = LearningSideEffectReconciler(
        database,
        streakSink: (_) async {
          entered.complete();
          await release.future;
          return const LearningProjectionResult.applied();
        },
      );
      final scheduler = LearningReconciliationScheduler(reconciler);

      scheduler.request('owner-reconcile');
      await entered.future;
      var disposed = false;
      final disposal = scheduler.dispose().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);
      release.complete();
      await disposal;
      expect(await applied('streak'), {'learning-event:attempt-1'});
    },
  );

  test(
    'terminal prefix cursor avoids replay lookups over large history',
    () async {
      for (var i = 1; i <= 200; i++) {
        await addEvent(i);
      }
      var calls = 0;
      final reconciler = LearningSideEffectReconciler(
        database,
        pendingBatchSize: 250,
        streakSink: (_) async {
          calls++;
          return const LearningProjectionResult.applied();
        },
      );
      await reconciler.reconcileOwner('owner-reconcile');
      expect(calls, 200);
      expect(
        await (database.select(
              database.eventsV2,
            )..where((row) => row.eventType.equals('LearningProjectionCursor')))
            .get(),
        hasLength(1),
      );
      final plan = await database.customSelect('''
        EXPLAIN QUERY PLAN
        SELECT event_id FROM events_v2 INDEXED BY idx_events_v2_owner_occurred
        WHERE owner_id = 'owner-reconcile' AND occurred_at_utc > 0
        ORDER BY occurred_at_utc ASC, event_id ASC LIMIT 50
      ''').get();
      expect(
        plan.map((row) => row.read<String>('detail')).join('\n'),
        contains('idx_events_v2_owner_occurred'),
        reason: 'post-cursor reads must use the owner/time index',
      );

      calls = 0;
      await reconciler.reconcileOwner('owner-reconcile');
      expect(calls, 0);
      expect(await applied('streak'), hasLength(200));
    },
  );

  test(
    'quest skipped outcome advances reward without calling reward sink',
    () async {
      await addEvent(1);
      var rewardCalls = 0;
      final reconciler = LearningSideEffectReconciler(
        database,
        questSink: (_) async => const LearningProjectionResult.notApplicable(
          payload: {'eligible': false},
        ),
        rewardSink: (_, _) async {
          rewardCalls++;
          return const LearningProjectionResult.applied();
        },
      );
      await reconciler.reconcileOwner('owner-reconcile');
      expect(rewardCalls, 0);
      final rewardResults = await database
          .customSelect(
            "SELECT event_type FROM events_v2 WHERE aggregate_id = "
            "'learning-event:attempt-1' AND json_extract(payload_json, "
            "'\$.projection') = 'reward' AND aggregate_type = "
            "'LearningProjection'",
          )
          .get();
      expect(
        rewardResults.single.read<String>('event_type'),
        'LearningProjectionSkipped',
      );
    },
  );
}
