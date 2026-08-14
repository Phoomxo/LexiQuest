import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show InsertMode, Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(id: 'owner-reconcile', createdAtUtcMs: 1),
        );
    await database
        .into(database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: 'session-1',
            ownerId: 'owner-reconcile',
            activityType: 'quiz',
            state: 'active',
            startedAtUtcMs: 1,
            appVersion: '1.0.0',
            buildId: 'test-build',
          ),
        );
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-reconcile',
            name: 'Test',
            normalizedName: 'test',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-1',
            ownerId: 'owner-reconcile',
            categoryId: 'category-1',
            spelling: 'test',
            normalizedSpelling: 'test',
            meaning: 'test',
            normalizedMeaning: 'test',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
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
        .into(database.answerAttempts)
        .insert(
          AnswerAttemptsCompanion.insert(
            id: 'attempt-$number',
            ownerId: owner,
            sessionId: 'session-1',
            wordId: 'word-1',
            promptMode: 'meaningChoice',
            isCorrect: true,
            attemptNumber: number,
            occurredAtUtcMs: at.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await DriftLearningEventStore(database).append(
      EventEnvelopeV2(
        eventId: 'learning-event:attempt-$number',
        eventType: 'QuizCompleted',
        eventVersion: 1,
        occurredAtUtc: at,
        recordedAtUtc: at,
        actorIdentity: owner,
        ownerIdentity: owner,
        aggregateType: 'LearningSession',
        aggregateId: 'session-1',
        idempotencyKey: 'learning-attempt:attempt-$number:v1',
        consentContext: const ConsentContext.none(),
        appVersion: '1.0.0',
        buildId: 'test-build',
        privacyClassification: PrivacyClassification.anonymized,
        payload: {'attemptId': 'attempt-$number'},
      ),
    );
  }

  Future<void> addDeclaredAssessmentEvent(int number) async {
    final at = DateTime.utc(2026, 8, number, 7);
    final context = _declaredAssessmentContext();
    await database
        .into(database.answerAttempts)
        .insert(
          AnswerAttemptsCompanion.insert(
            id: 'attempt-$number',
            ownerId: 'owner-reconcile',
            sessionId: 'session-1',
            wordId: 'word-1',
            promptMode: 'assessmentResponse',
            isCorrect: true,
            attemptNumber: number,
            occurredAtUtcMs: at.millisecondsSinceEpoch,
            evidenceClass: Value(context.evidenceClass.name),
            evidenceContextJson: Value(jsonEncode(context.toJson())),
          ),
        );
    await DriftLearningEventStore(database).append(
      EventEnvelopeV2(
        eventId: 'learning-event:attempt-$number',
        eventType: 'QuizCompleted',
        eventVersion: 2,
        occurredAtUtc: at,
        recordedAtUtc: at,
        actorIdentity: 'owner-reconcile',
        ownerIdentity: 'owner-reconcile',
        aggregateType: 'LearningSession',
        aggregateId: 'session-1',
        idempotencyKey: 'learning-attempt:attempt-$number:v2',
        consentContext: const ConsentContext(
          researchConsentVersion: 1,
          aiConsentGranted: false,
          voiceConsentGranted: false,
          socialConsentGranted: false,
        ),
        experimentContext: ExperimentContext(
          experimentId: 'experiment-a',
          variantId: 'assessment',
          assignedAtUtc: DateTime.utc(2026, 8, 1),
        ),
        contentRevision: context.contentRevision,
        policyVersion: context.policyVersion,
        appVersion: '1.0.0',
        buildId: 'test-build',
        privacyClassification: PrivacyClassification.anonymized,
        payload: {
          'attemptId': 'attempt-$number',
          'evidenceContext': context.toJson(),
        },
      ),
    );
  }

  Future<void> addV1Receipt({
    required int number,
    required String projection,
    required bool applied,
  }) async {
    final at = DateTime.utc(2026, 8, number, 6);
    final sourceId = 'learning-event:attempt-$number';
    final receiptId = 'learning-projection:$projection:$sourceId:v1';
    await database
        .into(database.eventsV2)
        .insert(
          EventsV2Companion.insert(
            eventId: receiptId,
            eventType: applied
                ? 'LearningProjectionApplied'
                : 'LearningProjectionSkipped',
            eventVersion: 1,
            occurredAtUtc: at,
            recordedAtUtc: at,
            actorIdentity: 'owner-reconcile',
            ownerId: 'owner-reconcile',
            aggregateType: 'LearningProjection',
            aggregateId: sourceId,
            causationId: Value(sourceId),
            idempotencyKey: receiptId,
            consentContextJson: jsonEncode(
              const ConsentContext.none().toJson(),
            ),
            appVersion: '1.0.0',
            buildId: 'test-build',
            privacyClassification: 'anonymized',
            payloadJson: jsonEncode({
              'sourceEventId': sourceId,
              'projection': projection,
              'appliedVersion': 1,
              'outcome': applied ? 'applied' : 'notApplicable',
              'result': applied
                  ? <String, dynamic>{'eligible': true}
                  : <String, dynamic>{},
            }),
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
    'pre-v13 attempt-only payload materializes decisions before v2 apply',
    () async {
      await addEvent(1);
      var calls = 0;
      final reconciler = LearningSideEffectReconciler(
        database,
        streakSink: (_) async {
          calls++;
          return const LearningProjectionResult.applied();
        },
      );

      await reconciler.reconcileOwner('owner-reconcile');

      expect(calls, 1);
      expect(
        await (database.select(database.eventsV2)..where(
              (row) => row.eventId.equals(
                'learning-evidence-decisions:attempt-1:v1',
              ),
            ))
            .getSingle(),
        isNotNull,
      );
      expect(
        await (database.select(database.eventsV2)..where(
              (row) => row.eventId.equals(
                'learning-projection:streak:learning-event:attempt-1:v2',
              ),
            ))
            .getSingle()
            .then((row) => row.eventType),
        'LearningProjectionApplied',
      );
    },
  );

  test(
    'mixed v1 pending and declared events bridge exactly once at v2',
    () async {
      await addEvent(1);
      await addEvent(2);
      await addDeclaredAssessmentEvent(3);
      await addV1Receipt(number: 1, projection: 'quest', applied: true);
      final calls = <String>[];
      final reconciler = LearningSideEffectReconciler(
        database,
        questSink: (event) async {
          calls.add(event.eventId);
          return const LearningProjectionResult.applied(
            payload: <String, dynamic>{'eligible': true},
          );
        },
      );

      await reconciler.reconcileOwner('owner-reconcile');
      await reconciler.reconcileOwner('owner-reconcile');

      expect(calls, <String>['learning-event:attempt-2']);
      final receipts =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.isIn(<String>[
                  'learning-projection:quest:learning-event:attempt-1:v2',
                  'learning-projection:quest:learning-event:attempt-2:v2',
                  'learning-projection:quest:learning-event:attempt-3:v2',
                ]),
              ))
              .get();
      expect(receipts, hasLength(3));
      final byId = {for (final receipt in receipts) receipt.eventId: receipt};
      final bridged =
          jsonDecode(
                byId['learning-projection:quest:learning-event:attempt-1:v2']!
                    .payloadJson,
              )
              as Map<String, dynamic>;
      expect(bridged['bridgedFromVersion'], 1);
      expect(
        byId['learning-projection:quest:learning-event:attempt-3:v2']!
            .eventType,
        'LearningProjectionSkipped',
      );
    },
  );

  test(
    'contextless declared event blocks terminally without invoking sink',
    () async {
      await addDeclaredAssessmentEvent(1);
      await database.customUpdate(
        'UPDATE events_v2 SET payload_json = ? WHERE event_id = ?',
        variables: <Variable<Object>>[
          Variable<String>(
            jsonEncode(<String, dynamic>{'attemptId': 'attempt-1'}),
          ),
          const Variable<String>('learning-event:attempt-1'),
        ],
        updates: {database.eventsV2},
      );
      var calls = 0;
      final reconciler = LearningSideEffectReconciler(
        database,
        questSink: (_) async {
          calls++;
          return const LearningProjectionResult.applied();
        },
      );

      await reconciler.reconcileOwner('owner-reconcile');

      expect(calls, 0);
      final receipt =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.equals(
                  'learning-projection:quest:learning-event:attempt-1:v2',
                ),
              ))
              .getSingle();
      expect(receipt.eventType, 'LearningProjectionBlocked');
      final payload = jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
      expect(payload['outcome'], 'blocked');
      expect(payload['reasonCode'], 'contextlessNonLegacyAttempt');
    },
  );

  test(
    'missing quest prerequisite blocks reward cursor before later receipt',
    () async {
      await addEvent(1);
      await addEvent(2);
      await database
          .into(database.eventsV2)
          .insert(
            EventsV2Companion.insert(
              eventId: 'learning-projection:quest:learning-event:attempt-2:v1',
              eventType: 'LearningProjectionApplied',
              eventVersion: 1,
              occurredAtUtc: DateTime.utc(2026, 8, 2, 6),
              recordedAtUtc: DateTime.utc(2026, 8, 2, 6),
              actorIdentity: 'owner-reconcile',
              ownerId: 'owner-reconcile',
              aggregateType: 'LearningProjection',
              aggregateId: 'learning-event:attempt-2',
              idempotencyKey:
                  'learning-projection:quest:learning-event:attempt-2:v1',
              consentContextJson: '{}',
              appVersion: '1.0.0',
              buildId: 'test-build',
              privacyClassification: 'anonymized',
              payloadJson: jsonEncode({
                'projection': 'quest',
                'result': {'eligible': true},
              }),
            ),
          );
      final rewarded = <String>[];
      final reconciler = LearningSideEffectReconciler(
        database,
        rewardSink: (event, _) async {
          rewarded.add(event.eventId);
          return const LearningProjectionResult.applied();
        },
      );

      await reconciler.reconcileOwner('owner-reconcile');

      expect(rewarded, isEmpty);
      expect(await applied('reward'), isEmpty);
    },
  );

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
    'backward wall clock insertion remains after the durable cursor',
    () async {
      await addEvent(1, occurredAt: DateTime.utc(2026, 8, 9, 12));
      final calls = <String>[];
      final reconciler = LearningSideEffectReconciler(
        database,
        streakSink: (event) async {
          calls.add(event.eventId);
          return const LearningProjectionResult.applied();
        },
      );
      await reconciler.reconcileOwner('owner-reconcile');

      await addEvent(2, occurredAt: DateTime.utc(2026, 8, 9, 11));
      await reconciler.reconcileOwner('owner-reconcile');

      expect(calls, contains('learning-event:attempt-2'));
      expect(await applied('streak'), hasLength(2));
    },
  );

  test(
    'backdated insertion rewinds only the affected projection tail',
    () async {
      await addEvent(1, occurredAt: DateTime.utc(2026, 8, 9, 10));
      await addEvent(2, occurredAt: DateTime.utc(2026, 8, 9, 11));
      await addEvent(3, occurredAt: DateTime.utc(2026, 8, 9, 12));
      final calls = <String>[];
      final reconciler = LearningSideEffectReconciler(
        database,
        streakSink: (event) async {
          calls.add(event.eventId);
          return const LearningProjectionResult.applied();
        },
      );
      await reconciler.reconcileOwner('owner-reconcile');
      calls.clear();

      await addEvent(4, occurredAt: DateTime.utc(2026, 8, 9, 11, 30));
      await reconciler.reconcileOwner('owner-reconcile');

      expect(calls, ['learning-event:attempt-4', 'learning-event:attempt-3']);
    },
  );

  test(
    'cursor discovery stays on three primary keys with large later history',
    () async {
      await addEvent(1, occurredAt: DateTime.utc(2026, 8, 9, 12));
      final calls = <String>[];
      final reconciler = LearningSideEffectReconciler(
        database,
        streakSink: (event) async {
          calls.add(event.eventId);
          return const LearningProjectionResult.applied();
        },
      );
      await reconciler.reconcileOwner('owner-reconcile');
      final laterAt = DateTime.utc(2026, 8, 9, 13);
      await database.batch((batch) {
        for (var index = 0; index < 2000; index++) {
          batch.insert(
            database.eventsV2,
            EventsV2Companion.insert(
              eventId: 'later-history-$index',
              eventType: 'LaterHistoryNoise',
              eventVersion: 1,
              occurredAtUtc: laterAt.add(Duration(milliseconds: index)),
              recordedAtUtc: laterAt.add(Duration(milliseconds: index)),
              actorIdentity: 'owner-reconcile',
              ownerId: 'owner-reconcile',
              aggregateType: 'LaterHistoryNoise',
              aggregateId: 'later-history-$index',
              idempotencyKey: 'later-history:$index',
              consentContextJson: '{}',
              appVersion: '1.0.0',
              buildId: 'test-build',
              privacyClassification: 'anonymized',
              payloadJson: '{}',
            ),
          );
        }
      });

      final cursorIds = DriftLearningEventStore.projectionCursorIds(
        ownerId: 'owner-reconcile',
        appliedVersion: LearningSideEffectReconciler.appliedVersion,
      );
      expect(cursorIds, [
        'learning-projection-cursor:owner-reconcile:quest:v2',
        'learning-projection-cursor:owner-reconcile:streak:v2',
        'learning-projection-cursor:owner-reconcile:reward:v2',
      ]);
      final placeholders = List.filled(cursorIds.length, '?').join(', ');
      final plan = await database
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT event_id FROM events_v2 '
            'WHERE event_id IN ($placeholders)',
            variables: cursorIds.map(Variable<String>.new).toList(),
          )
          .get();
      expect(
        plan.map((row) => row.read<String>('detail')).join('\n'),
        contains('sqlite_autoindex_events_v2_1'),
        reason: 'cursor discovery must use the event_id primary-key index',
      );

      calls.clear();
      await addEvent(2, occurredAt: DateTime.utc(2026, 8, 9, 11));
      await (database.delete(
        database.eventsV2,
      )..where((row) => row.eventType.equals('LaterHistoryNoise'))).go();
      await reconciler.reconcileOwner('owner-reconcile');
      expect(calls, ['learning-event:attempt-2', 'learning-event:attempt-1']);
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
            "'LearningProjection' AND event_id LIKE '%:v2'",
          )
          .get();
      expect(
        rewardResults.single.read<String>('event_type'),
        'LearningProjectionSkipped',
      );
    },
  );

  test(
    'v1 skipped quest and reward bridge at v2 without invoking sinks',
    () async {
      await addEvent(1);
      await addV1Receipt(number: 1, projection: 'quest', applied: false);
      await addV1Receipt(number: 1, projection: 'reward', applied: false);
      var questCalls = 0;
      var rewardCalls = 0;
      final reconciler = LearningSideEffectReconciler(
        database,
        questSink: (_) async {
          questCalls++;
          return const LearningProjectionResult.applied();
        },
        rewardSink: (_, _) async {
          rewardCalls++;
          return const LearningProjectionResult.applied();
        },
      );

      await reconciler.reconcileOwner('owner-reconcile');

      expect((questCalls, rewardCalls), (0, 0));
      final questReceipt =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.equals(
                  'learning-projection:quest:learning-event:attempt-1:v2',
                ),
              ))
              .getSingle();
      final rewardReceipt =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.equals(
                  'learning-projection:reward:learning-event:attempt-1:v2',
                ),
              ))
              .getSingle();
      expect(questReceipt.eventType, 'LearningProjectionSkipped');
      expect(rewardReceipt.eventType, 'LearningProjectionSkipped');
      for (final receipt in <EventsV2Data>[questReceipt, rewardReceipt]) {
        final payload = jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
        expect(payload['bridgedFromVersion'], 1);
      }
    },
  );

  test('v1 applied reward with skipped quest fails closed at v2', () async {
    await addEvent(1);
    await addV1Receipt(number: 1, projection: 'quest', applied: false);
    await addV1Receipt(number: 1, projection: 'reward', applied: true);
    var questCalls = 0;
    var rewardCalls = 0;
    final reconciler = LearningSideEffectReconciler(
      database,
      questSink: (_) async {
        questCalls++;
        return const LearningProjectionResult.applied();
      },
      rewardSink: (_, _) async {
        rewardCalls++;
        return const LearningProjectionResult.applied();
      },
    );

    await reconciler.reconcileOwner('owner-reconcile');

    expect((questCalls, rewardCalls), (0, 0));
    final rewardReceipt =
        await (database.select(database.eventsV2)..where(
              (row) => row.eventId.equals(
                'learning-projection:reward:learning-event:attempt-1:v2',
              ),
            ))
            .getSingle();
    expect(rewardReceipt.eventType, 'LearningProjectionBlocked');
    final payload =
        jsonDecode(rewardReceipt.payloadJson) as Map<String, dynamic>;
    expect(payload['outcome'], 'blocked');
    expect(payload['reasonCode'], 'rewardV1AppliedWithoutQuestPrerequisite');
    expect(payload.containsKey('bridgedFromVersion'), isFalse);
  });
}

EvidenceContext _declaredAssessmentContext() => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.assessment,
  skillId: 'assessment-skill',
  hintLevel: 0,
  contentRevision: 'assessment-content-v1',
  rolloutMode: EvidencePolicyRolloutMode.enforced,
  protocolId: 'protocol-a',
  protocolVersion: 'protocol-v1',
  experimentId: 'experiment-a',
  experimentVersion: 1,
  assignmentId: 'assignment-a',
  cohort: 'assessment',
  researchConsentVersion: 1,
  instrumentId: 'instrument-a',
  instrumentVersion: 'instrument-v1',
  formId: 'form-a',
  formVersion: 'form-v1',
  assessmentItemId: 'item-a',
  assessmentResponseCode: 'correct',
  scoringRuleVersion: 'score-v1',
  engagementAllowed: false,
);
