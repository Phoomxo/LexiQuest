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

  Future<void> addEvent(int number, {String owner = 'owner-reconcile'}) async {
    final at = DateTime.utc(2026, 8, number, 6);
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
        return LearningProjectionOutcome.applied;
      },
      rewardSink: (_) async {
        rewardCalls++;
        return LearningProjectionOutcome.applied;
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
        questSink: (_) async => LearningProjectionOutcome.applied,
        rewardSink: (_) async {
          if (++rewardCalls == 1) throw StateError('grant failed');
          return LearningProjectionOutcome.applied;
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
        questSink: (_) async => LearningProjectionOutcome.applied,
        rewardSink: (_) async {
          rewardCalls++;
          return LearningProjectionOutcome.notApplicable;
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
          return LearningProjectionOutcome.applied;
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
          return LearningProjectionOutcome.applied;
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
          return LearningProjectionOutcome.applied;
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
}
