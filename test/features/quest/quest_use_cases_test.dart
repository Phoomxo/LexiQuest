import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_repository.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';

// ── Fake owner repository ─────────────────────────────────────────────────────

class _FakeOwners implements LocalOwnerRepository {
  final LocalOwner owner;
  _FakeOwners(this.owner);
  int getCalls = 0;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    getCalls += 1;
    return owner;
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) async => owner;
}

final class _ThrowAfterProgressRepository implements QuestRepository {
  _ThrowAfterProgressRepository(this.delegate);

  final QuestRepository delegate;
  bool throwAfterNextProgress = true;
  String? allInstancesOwnerId;
  int? allInstancesLimit;
  int allInstancesCalls = 0;

  @override
  Future<void> saveProgress(
    String instanceId,
    List<ObjectiveProgress> progress,
  ) async {
    await delegate.saveProgress(instanceId, progress);
    if (throwAfterNextProgress) {
      throwAfterNextProgress = false;
      throw StateError('crash after progress before completion');
    }
  }

  @override
  Future<QuestDefinition?> getDefinition(String questId) =>
      delegate.getDefinition(questId);
  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) =>
      delegate.getActiveInstances(ownerId);
  @override
  Future<List<QuestInstance>> getAllInstances(
    String ownerId, {
    int limit = 50,
  }) {
    allInstancesCalls += 1;
    allInstancesOwnerId = ownerId;
    allInstancesLimit = limit;
    return delegate.getAllInstances(ownerId, limit: limit);
  }

  @override
  Future<List<QuestInstance>> getCompletedInstancesForSourceEvent({
    required String ownerId,
    required String sourceEventId,
    required Iterable<String> questIds,
    int limit = 64,
  }) => delegate.getCompletedInstancesForSourceEvent(
    ownerId: ownerId,
    sourceEventId: sourceEventId,
    questIds: questIds,
    limit: limit,
  );
  @override
  Future<void> markAbandoned(String instanceId) =>
      delegate.markAbandoned(instanceId);
  @override
  Future<void> markCompleted(String instanceId, DateTime completedAtUtc) =>
      delegate.markCompleted(instanceId, completedAtUtc);
  @override
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc) =>
      delegate.markExpired(instanceId, expiredAtUtc);
  @override
  Future<void> startInstance(QuestInstance instance) =>
      delegate.startInstance(instance);
  @override
  Future<void> upsertDefinition(QuestDefinition def) =>
      delegate.upsertDefinition(def);
}

final class _ThrowAfterCompletionRepository implements QuestRepository {
  _ThrowAfterCompletionRepository(this.delegate);

  final QuestRepository delegate;
  bool throwAfterNextCompletion = true;

  @override
  Future<void> markCompleted(String instanceId, DateTime completedAtUtc) async {
    await delegate.markCompleted(instanceId, completedAtUtc);
    if (throwAfterNextCompletion) {
      throwAfterNextCompletion = false;
      throw StateError('crash after completion before projection result');
    }
  }

  @override
  Future<QuestDefinition?> getDefinition(String questId) =>
      delegate.getDefinition(questId);
  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) =>
      delegate.getActiveInstances(ownerId);
  @override
  Future<List<QuestInstance>> getAllInstances(
    String ownerId, {
    int limit = 50,
  }) => delegate.getAllInstances(ownerId, limit: limit);
  @override
  Future<List<QuestInstance>> getCompletedInstancesForSourceEvent({
    required String ownerId,
    required String sourceEventId,
    required Iterable<String> questIds,
    int limit = 64,
  }) => delegate.getCompletedInstancesForSourceEvent(
    ownerId: ownerId,
    sourceEventId: sourceEventId,
    questIds: questIds,
    limit: limit,
  );
  @override
  Future<void> markAbandoned(String instanceId) =>
      delegate.markAbandoned(instanceId);
  @override
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc) =>
      delegate.markExpired(instanceId, expiredAtUtc);
  @override
  Future<void> saveProgress(
    String instanceId,
    List<ObjectiveProgress> progress,
  ) => delegate.saveProgress(instanceId, progress);
  @override
  Future<void> startInstance(QuestInstance instance) =>
      delegate.startInstance(instance);
  @override
  Future<void> upsertDefinition(QuestDefinition def) =>
      delegate.upsertDefinition(def);
}

final class _RejectHistoryScanRepository implements QuestRepository {
  _RejectHistoryScanRepository(this.delegate);
  final QuestRepository delegate;

  @override
  Future<List<QuestInstance>> getAllInstances(
    String ownerId, {
    int limit = 50,
  }) => throw StateError('unbounded quest history scan');
  @override
  Future<List<QuestInstance>> getCompletedInstancesForSourceEvent({
    required String ownerId,
    required String sourceEventId,
    required Iterable<String> questIds,
    int limit = 64,
  }) => delegate.getCompletedInstancesForSourceEvent(
    ownerId: ownerId,
    sourceEventId: sourceEventId,
    questIds: questIds,
    limit: limit,
  );
  @override
  Future<QuestDefinition?> getDefinition(String id) =>
      delegate.getDefinition(id);
  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) =>
      delegate.getActiveInstances(ownerId);
  @override
  Future<void> markAbandoned(String id) => delegate.markAbandoned(id);
  @override
  Future<void> markCompleted(String id, DateTime at) =>
      delegate.markCompleted(id, at);
  @override
  Future<void> markExpired(String id, DateTime at) =>
      delegate.markExpired(id, at);
  @override
  Future<void> saveProgress(String id, List<ObjectiveProgress> progress) =>
      delegate.saveProgress(id, progress);
  @override
  Future<void> startInstance(QuestInstance instance) =>
      delegate.startInstance(instance);
  @override
  Future<void> upsertDefinition(QuestDefinition definition) =>
      delegate.upsertDefinition(definition);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

int _seq = 0;

EventEnvelopeV2 _makeEvent({
  String eventType = 'QuizCompleted',
  Map<String, dynamic> payload = const {'correct': true},
  String ownerId = 'owner-uc',
  DateTime? occurredAtUtc,
}) => EventEnvelopeV2(
  eventId: 'evt-uc-${++_seq}',
  eventType: eventType,
  eventVersion: 1,
  occurredAtUtc: occurredAtUtc ?? DateTime.utc(2026, 8, 4, 10, 0),
  recordedAtUtc: DateTime.utc(2026, 8, 4, 10, 0, 1),
  actorIdentity: ownerId,
  ownerIdentity: ownerId,
  aggregateType: 'LearningSession',
  aggregateId: 'sess-uc',
  idempotencyKey: 'idem-uc-$_seq',
  consentContext: const ConsentContext.none(),
  appVersion: '1.0',
  buildId: 'sha',
  privacyClassification: PrivacyClassification.anonymized,
  payload: payload,
);

QuestDefinition _singleObjectiveDef({
  String questId = 'q-uc-daily',
  int targetCount = 2,
  QuestType type = QuestType.daily,
}) => QuestDefinition(
  questId: questId,
  catalogVersion: 1,
  title: 'Test Quest',
  description: 'Complete $targetCount quiz questions',
  type: type,
  objectives: [
    QuestObjective(
      objectiveId: 'obj-uc',
      description: 'Answer correctly',
      targetCount: targetCount,
      criteria: const ObjectiveCriteria(
        eventType: 'QuizCompleted',
        filters: {'correct': true},
      ),
    ),
  ],
  reward: const RewardSpec(xpAmount: 50),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late db.AppDatabase database;
  late DriftQuestRepository repo;
  late QuestUseCases useCases;
  late LocalOwner testOwner;
  int idCounter = 0;

  setUp(() async {
    _seq = 0;
    idCounter = 0;
    database = db.AppDatabase(NativeDatabase.memory());
    repo = DriftQuestRepository(database);
    testOwner = LocalOwner(
      id: 'owner-uc',
      createdAtUtc: DateTime.utc(2026, 8, 4),
    );

    await database.customInsert(
      "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
      "VALUES ('owner-uc', 'localGuest', 1722758400000)",
    );

    useCases = QuestUseCases(
      repository: repo,
      owners: _FakeOwners(testOwner),
      generateId: () => 'id-${++idCounter}',
      nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
      timezoneId: 'Asia/Bangkok',
    );
  });

  tearDown(() async => database.close());

  group('QuestUseCases', () {
    // ── startQuest ───────────────────────────────────────────────────────────

    test('startQuest creates active instance', () async {
      final def = _singleObjectiveDef();
      final instance = await useCases.startQuest(def);
      expect(instance, isNotNull);
      expect(instance!.state, QuestInstanceState.active);
      expect(instance.questId, def.questId);
      expect(instance.ownerId, 'owner-uc');
      expect(instance.progress, hasLength(1));
      expect(instance.progress.first.currentCount, 0);
    });

    test('startQuest returns null if quest is already active', () async {
      final def = _singleObjectiveDef();
      await useCases.startQuest(def);
      final second = await useCases.startQuest(def);
      expect(second, isNull, reason: 'duplicate startQuest should be a no-op');
    });

    test('startQuest persists catalog definition', () async {
      final def = _singleObjectiveDef();
      await useCases.startQuest(def);
      final stored = await repo.getDefinition(def.questId);
      expect(stored, isNotNull);
      expect(stored!.title, def.title);
    });

    test('bounded status read forwards current owner and limit', () async {
      final capturingRepository = _ThrowAfterProgressRepository(repo);
      final statusUseCases = QuestUseCases(
        repository: capturingRepository,
        owners: _FakeOwners(testOwner),
        generateId: () => 'status-id',
        nowUtc: () => DateTime.utc(2026, 8, 4, 10),
        timezoneId: 'Asia/Bangkok',
      );

      expect(
        await statusUseCases.getAllInstancesForCurrentOwner(limit: 17),
        isEmpty,
      );
      expect(capturingRepository.allInstancesOwnerId, testOwner.id);
      expect(capturingRepository.allInstancesLimit, 17);
    });

    test(
      'invalid status limits fail before owner or repository lookup',
      () async {
        final capturingRepository = _ThrowAfterProgressRepository(repo);
        final owners = _FakeOwners(testOwner);
        final statusUseCases = QuestUseCases(
          repository: capturingRepository,
          owners: owners,
          generateId: () => 'status-id',
          nowUtc: () => DateTime.utc(2026, 8, 4, 10),
          timezoneId: 'Asia/Bangkok',
        );

        for (final invalidLimit in const [0, 51]) {
          await expectLater(
            statusUseCases.getAllInstancesForCurrentOwner(limit: invalidLimit),
            throwsRangeError,
          );
        }

        expect(owners.getCalls, 0);
        expect(capturingRepository.allInstancesCalls, 0);
      },
    );

    // ── processEvent ─────────────────────────────────────────────────────────

    test('processEvent advances matching objective', () async {
      final def = _singleObjectiveDef(targetCount: 3);
      await useCases.startQuest(def);

      final completed = await useCases.processEvent(_makeEvent(), [def]);

      expect(completed, isEmpty, reason: 'one event should not complete quest');
      final instances = await useCases.getActiveInstances();
      expect(instances.first.progress.first.currentCount, 1);
    });

    test('processEvent ignores non-matching events', () async {
      final def = _singleObjectiveDef();
      await useCases.startQuest(def);

      await useCases.processEvent(_makeEvent(eventType: 'SrsReviewCompleted'), [
        def,
      ]);

      final instances = await useCases.getActiveInstances();
      expect(
        instances.first.progress.first.currentCount,
        0,
        reason: 'non-matching event must not advance counter',
      );
    });

    test(
      'quest assignment boundary skips before and accepts equality',
      () async {
        final def = _singleObjectiveDef(targetCount: 2);
        await useCases.startQuest(def);

        final before = await useCases.projectEvent(
          _makeEvent(occurredAtUtc: DateTime.utc(2026, 8, 4, 9, 59, 59)),
          [def],
        );
        expect(before.eligible, isFalse);
        expect(
          (await repo.getActiveInstances(
            testOwner.id,
          )).single.progress.single.currentCount,
          0,
        );

        final equal = await useCases.projectEvent(
          _makeEvent(occurredAtUtc: DateTime.utc(2026, 8, 4, 10)),
          [def],
        );
        expect(
          equal.eligible,
          isTrue,
          reason: 'assignment equality is eligible',
        );
        expect(
          (await repo.getActiveInstances(
            testOwner.id,
          )).single.progress.single.currentCount,
          1,
        );

        final after = await useCases.projectEvent(
          _makeEvent(occurredAtUtc: DateTime.utc(2026, 8, 4, 10, 0, 1)),
          [def],
        );
        expect(after.eligible, isTrue);
        expect(after.completed, hasLength(1));
      },
    );

    test(
      'processEvent returns QuestCompletedEvent when all objectives met',
      () async {
        final def = _singleObjectiveDef(targetCount: 2);
        await useCases.startQuest(def);

        await useCases.processEvent(_makeEvent(), [def]); // count=1
        final completed = await useCases.processEvent(_makeEvent(), [
          def,
        ]); // count=2→complete

        expect(completed, hasLength(1));
        expect(completed.first.questInstanceId, isNotEmpty);
        expect(completed.first.idempotencyKey, startsWith('quest_complete_'));
        expect(completed.first.objectiveEventIds, hasLength(2));
      },
    );

    test(
      'completed instance no longer appears in getActiveInstances',
      () async {
        final def = _singleObjectiveDef(targetCount: 1);
        await useCases.startQuest(def);
        await useCases.processEvent(_makeEvent(), [def]);

        final active = await useCases.getActiveInstances();
        expect(
          active,
          isEmpty,
          reason: 'completed instance must leave active list',
        );
      },
    );

    test('replay finalizes progress saved before markCompleted', () async {
      final def = _singleObjectiveDef(targetCount: 1);
      await useCases.startQuest(def);
      final event = _makeEvent();
      final crashing = QuestUseCases(
        repository: _ThrowAfterProgressRepository(repo),
        owners: _FakeOwners(testOwner),
        generateId: () => 'unused',
        nowUtc: () => DateTime.utc(2026, 8, 4, 10),
        timezoneId: 'Asia/Bangkok',
      );

      await expectLater(crashing.processEvent(event, [def]), throwsStateError);
      expect(
        (await repo.getActiveInstances(
          testOwner.id,
        )).single.progress.single.currentCount,
        1,
      );

      final completed = await useCases.processEvent(event, [def]);
      expect(completed, hasLength(1));
      expect(await repo.getActiveInstances(testOwner.id), isEmpty);
    });

    test(
      'replay reconstructs completion marked before projection result',
      () async {
        final def = _singleObjectiveDef(targetCount: 1);
        await useCases.startQuest(def);
        final event = _makeEvent();
        final rewards = DriftRewardRepository(database);
        Future<void> grant({
          required String ownerId,
          required String idempotencyKey,
          required int xpAmount,
          required String sourceEventId,
          required DateTime occurredAtUtc,
          String? rewardItemId,
        }) => rewards.grantQuestXp(
          ownerId: ownerId,
          idempotencyKey: idempotencyKey,
          xpAmount: xpAmount,
        );
        final crashing = QuestUseCases(
          repository: _ThrowAfterCompletionRepository(repo),
          owners: _FakeOwners(testOwner),
          generateId: () => 'unused',
          nowUtc: () => DateTime.utc(2026, 8, 4, 10),
          timezoneId: 'Asia/Bangkok',
          rewardSink: grant,
        );

        await expectLater(
          crashing.projectEvent(event, [def]),
          throwsStateError,
        );
        expect(await repo.getActiveInstances(testOwner.id), isEmpty);

        final recovery = QuestUseCases(
          repository: repo,
          owners: _FakeOwners(testOwner),
          generateId: () => 'unused',
          nowUtc: () => DateTime.utc(2026, 8, 4, 10),
          timezoneId: 'Asia/Bangkok',
          rewardSink: grant,
        );
        final replay = await recovery.projectEvent(event, [def]);
        expect(replay.eligible, isTrue);
        expect(replay.completed, hasLength(1));
        expect(replay.completed.single.ownerId, testOwner.id);
        expect(
          replay.completed.single.objectiveEventIds,
          contains(event.eventId),
        );
        expect(
          recovery.projectionPayload(replay, [def])['rewardGrants'],
          hasLength(1),
        );
        final projectedGrant =
            (recovery.projectionPayload(replay, [def])['rewardGrants'] as List)
                    .single
                as Map<String, dynamic>;
        expect(
          projectedGrant['sourceEventId'],
          'quest_complete_quest:id-1_q-uc-daily',
        );
        expect(
          projectedGrant['sourceEventId'],
          projectedGrant['idempotencyKey'],
          reason: 'the deployed Quest XP source identity remains canonical',
        );
        expect(
          projectedGrant['occurredAtUtcMs'],
          DateTime.utc(2026, 8, 4, 10).millisecondsSinceEpoch,
        );
        expect(
          await (database.select(
            database.pointsLedgerEntries,
          )..where((row) => row.entryType.equals('questCompletion'))).get(),
          isEmpty,
          reason: 'projection alone cannot grant XP',
        );
        await recovery.reconcileReward(
          event,
          recovery.projectionPayload(replay, [def]),
        );
        final secondReplay = await recovery.projectEvent(event, [def]);
        await recovery.reconcileReward(
          event,
          recovery.projectionPayload(secondReplay, [def]),
        );
        expect(
          await (database.select(
            database.pointsLedgerEntries,
          )..where((row) => row.entryType.equals('questCompletion'))).get(),
          hasLength(1),
          reason: 'the deterministic completion key prevents a double grant',
        );
      },
    );

    test('reconcileReward retries a failed completed-quest grant', () async {
      final def = _singleObjectiveDef(targetCount: 1);
      final event = _makeEvent();
      var calls = 0;
      final keys = <String>[];
      final sourceEventIds = <String>[];
      final occurredAtValues = <DateTime>[];
      final rewardUseCases = QuestUseCases(
        repository: repo,
        owners: _FakeOwners(testOwner),
        generateId: () => 'reward-retry-instance',
        nowUtc: () => DateTime.utc(2026, 8, 4, 10),
        timezoneId: 'Asia/Bangkok',
        rewardSink:
            ({
              required ownerId,
              required idempotencyKey,
              required xpAmount,
              required sourceEventId,
              required occurredAtUtc,
              rewardItemId,
            }) async {
              calls++;
              keys.add(idempotencyKey);
              sourceEventIds.add(sourceEventId);
              occurredAtValues.add(occurredAtUtc);
              if (calls == 1) throw StateError('reward unavailable');
            },
      );
      await rewardUseCases.startQuest(def);
      final projection = await rewardUseCases.projectEvent(event, [def]);
      for (var i = 0; i < 200; i++) {
        final irrelevantQuestId = 'irrelevant-quest-$i';
        await repo.upsertDefinition(
          _singleObjectiveDef(questId: irrelevantQuestId, targetCount: 1),
        );
        await database
            .into(database.questInstances)
            .insert(
              db.QuestInstancesCompanion.insert(
                instanceId: 'irrelevant-completed-$i',
                questId: irrelevantQuestId,
                ownerId: testOwner.id,
                catalogVersion: def.catalogVersion,
                assignedAtUtcMs: DateTime.utc(2025).millisecondsSinceEpoch,
                state: 'completed',
                completedAtUtcMs: Value(
                  DateTime.utc(2025).millisecondsSinceEpoch,
                ),
              ),
            );
      }

      final retryOnly = QuestUseCases(
        repository: _RejectHistoryScanRepository(repo),
        owners: _FakeOwners(testOwner),
        generateId: () => 'unused',
        nowUtc: () => DateTime.utc(2026, 8, 4, 10),
        timezoneId: 'Asia/Bangkok',
        rewardSink: rewardUseCases.rewardSink,
      );
      await expectLater(
        rewardUseCases.reconcileReward(
          event,
          rewardUseCases.projectionPayload(projection, [def]),
        ),
        throwsStateError,
      );
      await retryOnly.reconcileReward(
        event,
        rewardUseCases.projectionPayload(projection, [def]),
      );

      expect(calls, 2);
      expect(keys.toSet(), hasLength(1));
      expect(sourceEventIds.toSet(), <String>{
        'quest_complete_quest:reward-retry-instance_q-uc-daily',
      });
      expect(sourceEventIds, keys);
      expect(occurredAtValues.toSet(), <DateTime>{
        DateTime.utc(2026, 8, 4, 10),
      });
    });

    test(
      'projectEvent is projection-only until reconcileReward runs',
      () async {
        final def = _singleObjectiveDef(targetCount: 1);
        final event = _makeEvent();
        var grants = 0;
        final projectionOnly = QuestUseCases(
          repository: repo,
          owners: _FakeOwners(testOwner),
          generateId: () => 'projection-only-instance',
          nowUtc: () => DateTime.utc(2026, 8, 4, 10),
          timezoneId: 'Asia/Bangkok',
          rewardSink:
              ({
                required ownerId,
                required idempotencyKey,
                required xpAmount,
                required sourceEventId,
                required occurredAtUtc,
                rewardItemId,
              }) async {
                grants++;
              },
        );
        await projectionOnly.startQuest(def);

        final projection = await projectionOnly.projectEvent(event, [def]);

        expect(projection.completed, hasLength(1));
        expect(grants, 0, reason: 'Quest projection cannot grant rewards');
        expect(
          await projectionOnly.reconcileReward(
            event,
            projectionOnly.projectionPayload(projection, [def]),
          ),
          isTrue,
        );
        expect(grants, 1);
      },
    );

    test(
      'reconcileReward fails closed for malformed or unbounded grants',
      () async {
        final event = _makeEvent();
        var grants = 0;
        final validating = QuestUseCases(
          repository: repo,
          owners: _FakeOwners(testOwner),
          generateId: () => 'unused',
          nowUtc: () => DateTime.utc(2026, 8, 4, 10),
          timezoneId: 'Asia/Bangkok',
          rewardSink:
              ({
                required ownerId,
                required idempotencyKey,
                required xpAmount,
                required sourceEventId,
                required occurredAtUtc,
                rewardItemId,
              }) async {
                grants++;
              },
        );
        Map<String, dynamic> grant({
          String ownerId = 'owner-uc',
          String idempotencyKey = 'quest-grant-1',
          Object xpAmount = 50,
          Object sourceEventId = 'quest-grant-1',
          Object? occurredAtUtcMs,
          Object? rewardItemId,
        }) => <String, dynamic>{
          'ownerId': ownerId,
          'idempotencyKey': idempotencyKey,
          'xpAmount': xpAmount,
          'sourceEventId': sourceEventId,
          'occurredAtUtcMs':
              occurredAtUtcMs ?? event.recordedAtUtc.millisecondsSinceEpoch,
          if (rewardItemId != null) 'rewardItemId': rewardItemId,
        };

        final invalid = <(String, Map<String, dynamic>)>[
          (
            'applied eligible false',
            <String, dynamic>{'eligible': false, 'rewardGrants': <Object>[]},
          ),
          (
            'wrong owner',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(ownerId: 'other-owner')],
            },
          ),
          (
            'malformed result key',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': <Object>[],
              'extra': true,
            },
          ),
          (
            'malformed grant key',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [
                <String, dynamic>{...grant(), 'extra': true},
              ],
            },
          ),
          (
            'duplicate idempotency key',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(), grant()],
            },
          ),
          (
            'oversized idempotency key',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(idempotencyKey: 'x' * 257)],
            },
          ),
          (
            'zero xp',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(xpAmount: 0)],
            },
          ),
          (
            'negative xp',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(xpAmount: -1)],
            },
          ),
          (
            'non-integer xp',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(xpAmount: 1.5)],
            },
          ),
          (
            'out-of-range xp',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [
                grant(xpAmount: jsonDecode('9223372036854775808')),
              ],
            },
          ),
          (
            'blank source event ID',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(sourceEventId: '')],
            },
          ),
          (
            'mismatched durable source identity',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(sourceEventId: 'different-source')],
            },
          ),
          (
            'negative occurrence time',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(occurredAtUtcMs: -1)],
            },
          ),
          (
            'unrepresentable occurrence time',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(occurredAtUtcMs: 8640000000000001)],
            },
          ),
          (
            'oversized reward item',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [grant(rewardItemId: 'x' * 257)],
            },
          ),
          (
            'null reward item',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': [
                <String, dynamic>{...grant(), 'rewardItemId': null},
              ],
            },
          ),
          (
            'oversized batch',
            <String, dynamic>{
              'eligible': true,
              'rewardGrants': List.generate(
                65,
                (index) => grant(idempotencyKey: 'quest-grant-$index'),
              ),
            },
          ),
        ];

        for (final (label, payload) in invalid) {
          await expectLater(
            validating.reconcileReward(event, payload),
            throwsStateError,
            reason: label,
          );
        }
        expect(
          grants,
          0,
          reason: 'validation must finish before the first sink',
        );
      },
    );

    // ── expireStale ──────────────────────────────────────────────────────────

    test(
      'expireStale marks expired instances whose deadline has passed',
      () async {
        // Create definition with 1-hour expiry.
        final def = QuestDefinition(
          questId: 'q-expire',
          catalogVersion: 1,
          title: 'Expiring Quest',
          description: 'Expires in 1 hour',
          type: QuestType.daily,
          objectives: const [
            QuestObjective(
              objectiveId: 'obj-expire',
              description: 'Never complete',
              targetCount: 99,
              criteria: ObjectiveCriteria(eventType: 'QuizCompleted'),
            ),
          ],
          reward: const RewardSpec(xpAmount: 10),
          expiresIn: const Duration(hours: 1),
        );
        await useCases.startQuest(def);

        // Override nowUtc to 2 hours after assignment.
        final lateUseCases = QuestUseCases(
          repository: repo,
          owners: _FakeOwners(testOwner),
          generateId: () => 'id-late',
          nowUtc: () => DateTime.utc(2026, 8, 4, 12, 0), // +2h
          timezoneId: 'Asia/Bangkok',
        );

        await lateUseCases.expireStale();

        final active = await repo.getActiveInstances('owner-uc');
        expect(active, isEmpty, reason: 'expired quest must leave active list');
      },
    );

    test('expireStale ignores instances without expiry', () async {
      final def = _singleObjectiveDef(); // no expiresIn
      await useCases.startQuest(def);
      await useCases.expireStale();

      final active = await useCases.getActiveInstances();
      expect(
        active,
        hasLength(1),
        reason: 'quest with no deadline must not be expired',
      );
    });
  });
}
