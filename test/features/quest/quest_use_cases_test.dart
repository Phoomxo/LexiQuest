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

// ── Fake owner repository ─────────────────────────────────────────────────────

class _FakeOwners implements LocalOwnerRepository {
  final LocalOwner owner;
  _FakeOwners(this.owner);

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => owner;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) async => owner;
}

final class _ThrowAfterProgressRepository implements QuestRepository {
  _ThrowAfterProgressRepository(this.delegate);

  final QuestRepository delegate;
  bool throwAfterNextProgress = true;

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
  Future<List<QuestInstance>> getAllInstances(String ownerId) =>
      delegate.getAllInstances(ownerId);
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

final class _RejectHistoryScanRepository implements QuestRepository {
  _RejectHistoryScanRepository(this.delegate);
  final QuestRepository delegate;

  @override
  Future<List<QuestInstance>> getAllInstances(String ownerId) =>
      throw StateError('unbounded quest history scan');
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

    test('reconcileReward retries a failed completed-quest grant', () async {
      final def = _singleObjectiveDef(targetCount: 1);
      final event = _makeEvent();
      var calls = 0;
      final keys = <String>[];
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
              rewardItemId,
            }) async {
              calls++;
              keys.add(idempotencyKey);
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
      await retryOnly.reconcileReward(
        event,
        rewardUseCases.projectionPayload(projection, [def]),
      );

      expect(calls, 2);
      expect(keys.toSet(), hasLength(1));
    });

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
