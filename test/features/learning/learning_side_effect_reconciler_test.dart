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
    final occurredAt = DateTime.utc(2026, 8, 9, 6);
    await database
        .into(database.eventsV2)
        .insert(
          EventsV2Companion.insert(
            eventId: 'learning-event:attempt-1',
            eventType: 'QuizCompleted',
            eventVersion: 1,
            occurredAtUtc: occurredAt,
            recordedAtUtc: occurredAt,
            actorIdentity: 'owner-reconcile',
            ownerId: 'owner-reconcile',
            aggregateType: 'LearningSession',
            aggregateId: 'session-1',
            idempotencyKey: 'learning-attempt:attempt-1:v1',
            consentContextJson: '{}',
            appVersion: '1.0.0',
            buildId: 'test-build',
            privacyClassification: 'anonymized',
            payloadJson: jsonEncode({
              'attemptId': 'attempt-1',
              'wordId': 'word-1',
              'correct': true,
            }),
          ),
        );
  });

  tearDown(() => database.close());

  test(
    'retries only failed projections and records independent applied versions',
    () async {
      var questCalls = 0;
      var streakCalls = 0;
      var rewardCalls = 0;
      final reconciler = LearningSideEffectReconciler(
        database,
        questSink: (event) async {
          questCalls++;
          expect(event.idempotencyKey, 'learning-attempt:attempt-1:v1');
          if (questCalls == 1) throw StateError('quest unavailable');
        },
        streakSink: (event) async {
          streakCalls++;
          expect(event.eventId, 'learning-event:attempt-1');
        },
        rewardSink: (event) async {
          rewardCalls++;
          expect(event.eventId, 'learning-event:attempt-1');
        },
      );

      await reconciler.reconcileOwner('owner-reconcile');

      expect((questCalls, streakCalls, rewardCalls), (1, 1, 1));
      var receipts =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventType.equals('LearningProjectionApplied'),
              ))
              .get();
      expect(receipts, hasLength(2));
      expect(
        receipts
            .map(
              (row) =>
                  (jsonDecode(row.payloadJson)
                          as Map<String, dynamic>)['projection']
                      as String,
            )
            .toSet(),
        {'streak', 'reward'},
      );

      await reconciler.reconcileOwner('owner-reconcile');

      expect((questCalls, streakCalls, rewardCalls), (2, 1, 1));
      receipts =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventType.equals('LearningProjectionApplied'),
              ))
              .get();
      expect(receipts, hasLength(3));
      for (final receipt in receipts) {
        final payload = jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
        expect(payload['sourceEventId'], 'learning-event:attempt-1');
        expect(payload['appliedVersion'], 1);
      }

      await reconciler.reconcileOwner('owner-reconcile');

      expect((questCalls, streakCalls, rewardCalls), (2, 1, 1));
      expect(
        await (database.select(database.eventsV2)..where(
              (row) => row.eventType.equals('LearningProjectionApplied'),
            ))
            .get(),
        hasLength(3),
      );
    },
  );
}
