import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/quest/application/quest_catalog_provider.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_period.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_definition_codec.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';

// ── Fake owner repository ─────────────────────────────────────────────────────

class _FakeOwners implements LocalOwnerRepository {
  final LocalOwner owner;
  LocalOwner? ownerAfterFirstRead;
  _FakeOwners(this.owner);
  int getCalls = 0;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    getCalls += 1;
    return getCalls > 1 ? ownerAfterFirstRead ?? owner : owner;
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) async => owner;
}

final class _ThrowAfterProgressRepository implements QuestRepository {
  @override
  Future<bool> assignForPeriod({
    required QuestDefinition definition,
    required QuestInstance instance,
    required DateTime nowUtc,
  }) => delegate.assignForPeriod(
    definition: definition,
    instance: instance,
    nowUtc: nowUtc,
  );
  @override
  Future<void> expireStaleInstances({
    required String ownerId,
    required DateTime nowUtc,
  }) => delegate.expireStaleInstances(ownerId: ownerId, nowUtc: nowUtc);
  @override
  Future<List<QuestInstance>> getProjectionCandidates({
    required String ownerId,
    required DateTime occurredAtUtc,
    required Iterable<String> questIds,
  }) => delegate.getProjectionCandidates(
    ownerId: ownerId,
    occurredAtUtc: occurredAtUtc,
    questIds: questIds,
  );
  _ThrowAfterProgressRepository(this.delegate);

  final QuestRepository delegate;
  bool throwAfterNextProgress = true;
  String? allInstancesOwnerId;
  int? allInstancesLimit;
  int allInstancesCalls = 0;
  List<QuestInstance>? allInstancesOverride;
  QuestDefinition? definitionOverride;
  bool metadataMissing = false;

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
  Future<QuestDefinition?> getDefinition(String questId) => metadataMissing
      ? Future.value(null)
      : definitionOverride != null
      ? Future.value(definitionOverride)
      : delegate.getDefinition(questId);
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
    return allInstancesOverride != null
        ? Future.value(allInstancesOverride)
        : delegate.getAllInstances(ownerId, limit: limit);
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
  @override
  Future<bool> assignForPeriod({
    required QuestDefinition definition,
    required QuestInstance instance,
    required DateTime nowUtc,
  }) => delegate.assignForPeriod(
    definition: definition,
    instance: instance,
    nowUtc: nowUtc,
  );
  @override
  Future<void> expireStaleInstances({
    required String ownerId,
    required DateTime nowUtc,
  }) => delegate.expireStaleInstances(ownerId: ownerId, nowUtc: nowUtc);
  @override
  Future<List<QuestInstance>> getProjectionCandidates({
    required String ownerId,
    required DateTime occurredAtUtc,
    required Iterable<String> questIds,
  }) => delegate.getProjectionCandidates(
    ownerId: ownerId,
    occurredAtUtc: occurredAtUtc,
    questIds: questIds,
  );
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
  @override
  Future<bool> assignForPeriod({
    required QuestDefinition definition,
    required QuestInstance instance,
    required DateTime nowUtc,
  }) => delegate.assignForPeriod(
    definition: definition,
    instance: instance,
    nowUtc: nowUtc,
  );
  @override
  Future<void> expireStaleInstances({
    required String ownerId,
    required DateTime nowUtc,
  }) => delegate.expireStaleInstances(ownerId: ownerId, nowUtc: nowUtc);
  @override
  Future<List<QuestInstance>> getProjectionCandidates({
    required String ownerId,
    required DateTime occurredAtUtc,
    required Iterable<String> questIds,
  }) => delegate.getProjectionCandidates(
    ownerId: ownerId,
    occurredAtUtc: occurredAtUtc,
    questIds: questIds,
  );
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
  int catalogVersion = 1,
  Duration? expiresIn,
}) => QuestDefinition(
  questId: questId,
  catalogVersion: catalogVersion,
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
  expiresIn: expiresIn,
);

QuestDefinition _orderedDefinition({
  String questId = 'q-ordered',
  int catalogVersion = 1,
  bool reversed = false,
}) {
  const first = QuestObjective(
    objectiveId: 'objective-a',
    description: 'First objective',
    targetCount: 2,
    criteria: ObjectiveCriteria(
      eventType: 'QuizCompleted',
      filters: {'correct': true},
    ),
  );
  const second = QuestObjective(
    objectiveId: 'objective-b',
    description: 'Second objective',
    targetCount: 3,
    criteria: ObjectiveCriteria(eventType: 'SrsReviewCompleted'),
  );
  return QuestDefinition(
    questId: questId,
    catalogVersion: catalogVersion,
    title: 'Ordered quest',
    description: 'A definition whose objective order is pinned',
    type: QuestType.daily,
    objectives: reversed ? const [second, first] : const [first, second],
    reward: const RewardSpec(xpAmount: 50),
  );
}

QuestDefinition _historicalDefinition(
  int version, {
  int? targetCount,
  String? eventType,
}) => QuestDefinition(
  questId: 'versioned-daily',
  catalogVersion: version,
  title: version == 1 ? 'Original title' : 'Replacement title',
  description: 'Synthetic version $version',
  type: QuestType.daily,
  objectives: [
    QuestObjective(
      objectiveId: 'history-answer',
      description: 'Version $version criterion',
      targetCount: targetCount ?? (version == 1 ? 1 : 2),
      criteria: ObjectiveCriteria(
        eventType:
            eventType ??
            (version == 1 ? 'QuizCompleted' : 'SrsReviewCompleted'),
        filters: const {'correct': true},
      ),
    ),
  ],
  reward: RewardSpec(xpAmount: version == 1 ? 25 : 900),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(timezone_data.initializeTimeZones);

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
    group('daily refresh boundary', () {
      late DateTime clock;
      QuestUseCases refreshSubject({Future<void> Function(String)? guard}) =>
          QuestUseCases(
            repository: repo,
            owners: _FakeOwners(testOwner),
            generateId: () => 'refresh-${++idCounter}',
            nowUtc: () => clock,
            timezoneId: 'Asia/Bangkok',
            authorityGuard: guard,
          );
      setUp(() {
        clock = DateTime.utc(2026, 8, 4, 10);
      });

      test(
        'same-day repeat and next-day refresh seed only enabled daily catalog',
        () async {
          final subject = refreshSubject();
          var signals = 0;
          subject.addStatusListener(() {
            signals++;
          });
          expect(
            await subject.refreshDaily(expectedOwnerId: testOwner.id),
            QuestRefreshOutcome.refreshed,
          );
          final original = (await repo.getActiveInstances(testOwner.id)).single;
          expect(
            await subject.refreshDaily(expectedOwnerId: testOwner.id),
            QuestRefreshOutcome.unchanged,
          );
          clock = clock.add(const Duration(days: 1));
          expect(
            await subject.refreshDaily(expectedOwnerId: testOwner.id),
            QuestRefreshOutcome.refreshed,
          );
          final rows = await repo.getAllInstances(testOwner.id);
          expect(rows, hasLength(2));
          expect(
            rows.map((row) => row.questId).toSet(),
            QuestCatalogProvider.dailyQuests.map((def) => def.questId).toSet(),
          );
          expect(
            rows
                .singleWhere((row) => row.instanceId == original.instanceId)
                .state,
            QuestInstanceState.expired,
          );
          expect(
            rows.where((row) => row.state == QuestInstanceState.active),
            hasLength(1),
          );
          expect(signals, 3);
          expect(
            await database.select(database.pointsLedgerEntries).get(),
            isEmpty,
          );
        },
      );

      for (final loseAuthority in [false, true]) {
        test(
          'scheduling failure still performs authority postcheck loseAuthority=$loseAuthority',
          () async {
            await database.customStatement(
              "CREATE TEMP TRIGGER fail_daily_assignment BEFORE INSERT ON quest_instances BEGIN SELECT RAISE(ABORT, 'synthetic scheduling outage'); END",
            );
            var guards = 0;
            var signals = 0;
            final subject = refreshSubject(
              guard: (ownerId) async {
                expect(ownerId, testOwner.id);
                guards++;
                if (loseAuthority && guards == 2) {
                  throw StateError('synthetic same-owner lease lost');
                }
              },
            );
            subject.addStatusListener(() {
              signals++;
            });
            if (loseAuthority) {
              await expectLater(
                subject.refreshDaily(expectedOwnerId: testOwner.id),
                throwsStateError,
              );
            } else {
              expect(
                await subject.refreshDaily(expectedOwnerId: testOwner.id),
                QuestRefreshOutcome.unavailable,
              );
            }
            expect(guards, 2);
            expect(signals, 0);
            expect(
              await database.select(database.questInstances).get(),
              isEmpty,
            );
            expect(
              await database.select(database.questObjectiveProgress).get(),
              isEmpty,
            );
            expect(
              await database.select(database.pointsLedgerEntries).get(),
              isEmpty,
            );
          },
        );
      }

      test('initial authority failure prevents scheduling', () async {
        final subject = refreshSubject(
          guard: (_) async => throw StateError('synthetic owner fence'),
        );
        await expectLater(
          subject.refreshDaily(expectedOwnerId: testOwner.id),
          throwsStateError,
        );
        expect(await database.select(database.questInstances).get(), isEmpty);
      });

      test(
        'expected owner is retained when guard await observes an owner transition',
        () async {
          var guards = 0;
          final subject = refreshSubject(
            guard: (_) async {
              if (++guards != 1) return;
              await database.customStatement(
                'UPDATE local_owners SET is_active = 0',
              );
              await database.customStatement(
                "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('new-active','localGuest',1,1)",
              );
            },
          );
          await expectLater(
            subject.refreshDaily(expectedOwnerId: testOwner.id),
            throwsStateError,
          );
          expect(await database.select(database.questInstances).get(), isEmpty);
        },
      );

      test(
        'disposed pending refresh cannot continue guards or notify retired listeners',
        () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          var guards = 0;
          var signals = 0;
          final subject = refreshSubject(
            guard: (_) async {
              guards++;
              entered.complete();
              await release.future;
            },
          );
          subject.addStatusListener(() {
            signals++;
          });
          final pending = subject.refreshDaily(expectedOwnerId: testOwner.id);
          final drained = pending.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          );
          try {
            await entered.future.timeout(const Duration(seconds: 3));
            subject.dispose();
            release.complete();
            await expectLater(pending, throwsStateError);
            expect(guards, 1);
            expect(signals, 0);
            expect(
              await database.select(database.questInstances).get(),
              isEmpty,
            );
          } finally {
            subject.dispose();
            if (!release.isCompleted) release.complete();
            await drained.timeout(const Duration(seconds: 3));
          }
        },
      );

      test(
        'removed status listener remains detached on later refresh',
        () async {
          var signals = 0;
          void listener() {
            signals++;
          }

          final subject = refreshSubject();
          subject.addStatusListener(listener);
          await subject.refreshDaily(expectedOwnerId: testOwner.id);
          subject.removeStatusListener(listener);
          clock = clock.add(const Duration(days: 1));
          await subject.refreshDaily(expectedOwnerId: testOwner.id);
          expect(signals, 1);
          subject.dispose();
          await expectLater(
            subject.refreshDaily(expectedOwnerId: testOwner.id),
            throwsStateError,
          );
        },
      );
    });

    test(
      'presentation reads pinned metadata and preserves durable objective evidence',
      () async {
        final definition = _orderedDefinition();
        final instance = (await useCases.startQuest(definition))!;
        await repo.saveProgress(instance.instanceId, [
          const ObjectiveProgress(
            objectiveId: 'objective-a',
            currentCount: 1,
            targetCount: 2,
            sourceEventIds: ['synthetic-answer'],
          ),
          const ObjectiveProgress(
            objectiveId: 'objective-b',
            currentCount: 0,
            targetCount: 3,
          ),
        ]);
        final entries = await useCases.loadStatusForCurrentOwner(limit: 1);
        expect(entries.single.definition!.title, definition.title);
        expect(entries.single.instance.ownerId, testOwner.id);
        expect(entries.single.instance.progress.first.currentCount, 1);
        expect(entries.single.instance.progress.first.sourceEventIds, [
          'synthetic-answer',
        ]);
        expect(
          (await repo.getAllInstances(testOwner.id)).single.state,
          QuestInstanceState.active,
        );
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          isEmpty,
        );
        expect(() => entries.clear(), throwsUnsupportedError);
      },
    );

    for (final missing in [true, false]) {
      test(
        'presentation does not substitute missing=$missing pinned metadata',
        () async {
          final instance = (await useCases.startQuest(_singleObjectiveDef()))!;
          final repository = _ThrowAfterProgressRepository(repo)
            ..metadataMissing = missing
            ..definitionOverride = _singleObjectiveDef(catalogVersion: 2);
          final reader = QuestUseCases(
            repository: repository,
            owners: _FakeOwners(testOwner),
            generateId: () => throw StateError('read must not generate IDs'),
            nowUtc: () => DateTime.utc(2026, 9, 8),
            timezoneId: 'Asia/Bangkok',
          );
          final entry = (await reader.loadStatusForCurrentOwner()).single;
          expect(entry.definition, isNull);
          expect(entry.instance.instanceId, instance.instanceId);
          expect(entry.instance.catalogVersion, 1);
        },
      );
    }

    test(
      'presentation rejects objective drift and owner changes during read',
      () async {
        await useCases.startQuest(_singleObjectiveDef());
        final repository = _ThrowAfterProgressRepository(repo)
          ..definitionOverride = _singleObjectiveDef(targetCount: 9);
        final owners = _FakeOwners(testOwner);
        final reader = QuestUseCases(
          repository: repository,
          owners: owners,
          generateId: () => 'unused',
          nowUtc: () => DateTime.utc(2026, 9, 8),
          timezoneId: 'Asia/Bangkok',
        );
        await expectLater(reader.loadStatusForCurrentOwner(), throwsStateError);
        repository.definitionOverride = null;
        owners.getCalls = 0;
        owners.ownerAfterFirstRead = LocalOwner(
          id: 'different-owner',
          createdAtUtc: DateTime.utc(2026),
        );
        await expectLater(reader.loadStatusForCurrentOwner(), throwsStateError);
        expect(
          (await repo.getAllInstances(
            testOwner.id,
          )).single.progress.single.targetCount,
          2,
        );
      },
    );

    test(
      'presentation rejects foreign owner rows and invalid bounds',
      () async {
        final original = (await useCases.startQuest(_singleObjectiveDef()))!;
        final repository = _ThrowAfterProgressRepository(repo)
          ..allInstancesOverride = [
            QuestInstance(
              instanceId: original.instanceId,
              questId: original.questId,
              ownerId: 'different-owner',
              catalogVersion: original.catalogVersion,
              assignedAtUtc: original.assignedAtUtc,
              state: original.state,
              progress: original.progress,
            ),
          ];
        final owners = _FakeOwners(testOwner);
        final reader = QuestUseCases(
          repository: repository,
          owners: owners,
          generateId: () => 'unused',
          nowUtc: () => DateTime.utc(2026, 9, 8),
          timezoneId: 'Asia/Bangkok',
        );
        for (final limit in [0, 51]) {
          await expectLater(
            reader.loadStatusForCurrentOwner(limit: limit),
            throwsRangeError,
          );
        }
        expect(owners.getCalls, 0);
        expect(repository.allInstancesCalls, 0);
        await expectLater(reader.loadStatusForCurrentOwner(), throwsStateError);
      },
    );
    // ── startQuest ───────────────────────────────────────────────────────────

    group('definition history', () {
      late DateTime clock;

      QuestUseCases historyUseCases({
        QuestRepository? repository,
        QuestRewardSink? rewardSink,
      }) => QuestUseCases(
        repository: repository ?? repo,
        owners: _FakeOwners(testOwner),
        generateId: () => 'history-${++idCounter}',
        nowUtc: () => clock,
        timezoneId: 'Asia/Bangkok',
        rewardSink: rewardSink,
      );

      setUp(() {
        clock = DateTime.utc(2026, 8, 4, 10);
        useCases = historyUseCases();
      });

      test(
        'D1 receipt gap replays the original grant after D2 catalog replacement',
        () async {
          final v1 = _historicalDefinition(1);
          final v2 = _historicalDefinition(2);
          final d1 = (await useCases.startQuest(v1))!;
          final source = _makeEvent(occurredAtUtc: clock);
          final completedAt = clock;
          final crashing = historyUseCases(
            repository: _ThrowAfterCompletionRepository(repo),
          );
          await expectLater(
            crashing.projectEvent(source, [v1]),
            throwsStateError,
          );
          expect(
            (await repo.getAllInstances(testOwner.id)).single.state,
            QuestInstanceState.completed,
          );
          clock = DateTime.utc(2026, 8, 5, 10);
          final d2 = (await useCases.startQuest(v2))!;
          final rewards = DriftRewardRepository(database);
          final recovery = historyUseCases(
            rewardSink:
                ({
                  required ownerId,
                  required idempotencyKey,
                  required xpAmount,
                  required sourceEventId,
                  required occurredAtUtc,
                  rewardItemId,
                }) async {
                  expect(xpAmount, 25);
                  expect(occurredAtUtc, completedAt);
                  expect(
                    sourceEventId,
                    'quest_complete_${d1.instanceId}_${v1.questId}',
                  );
                  await rewards.grantQuestXp(
                    ownerId: ownerId,
                    idempotencyKey: idempotencyKey,
                    xpAmount: xpAmount,
                  );
                },
          );

          for (var replay = 0; replay < 2; replay++) {
            final evaluation = await recovery.projectEvent(source, [v2]);
            final payload = recovery.projectionPayload(evaluation, [v2]);
            expect((payload['rewardGrants'] as List).single, {
              'ownerId': testOwner.id,
              'idempotencyKey': 'quest_complete_${d1.instanceId}_${v1.questId}',
              'xpAmount': 25,
              'sourceEventId': 'quest_complete_${d1.instanceId}_${v1.questId}',
              'occurredAtUtcMs': completedAt.millisecondsSinceEpoch,
            });
            await recovery.reconcileReward(source, payload);
          }
          final active = (await repo.getActiveInstances(testOwner.id)).single;
          expect(active.instanceId, d2.instanceId);
          expect(active.progress.single.currentCount, 0);
          expect(active.progress.single.sourceEventIds, isEmpty);
          final awards = await database
              .select(database.pointsLedgerEntries)
              .get();
          expect(awards, hasLength(1));
          expect(awards.single.amount, 25);
        },
      );

      for (final removedCatalog in ['empty', 'other-quest']) {
        test(
          'completed receipt gap recovers original grant with $removedCatalog catalog',
          () async {
            final definition = _historicalDefinition(1);
            final original = (await useCases.startQuest(definition))!;
            final source = _makeEvent(occurredAtUtc: clock);
            await expectLater(
              historyUseCases(
                repository: _ThrowAfterCompletionRepository(repo),
              ).projectEvent(source, [definition]),
              throwsStateError,
            );
            final remaining = removedCatalog == 'empty'
                ? <QuestDefinition>[]
                : [_singleObjectiveDef(questId: 'unrelated')];
            final recovered = await useCases.projectEvent(source, remaining);
            expect(recovered.eligible, isTrue);
            expect(
              recovered.completed.single.questInstanceId,
              original.instanceId,
            );
            expect(
              (useCases.projectionPayload(recovered, remaining)['rewardGrants']
                      as List)
                  .single,
              {
                'ownerId': testOwner.id,
                'idempotencyKey':
                    'quest_complete_${original.instanceId}_${definition.questId}',
                'xpAmount': 25,
                'sourceEventId':
                    'quest_complete_${original.instanceId}_${definition.questId}',
                'occurredAtUtcMs': clock.millisecondsSinceEpoch,
              },
            );
          },
        );
      }

      test(
        'evaluated payload retains its grant when caller catalog changes',
        () async {
          final v1 = _historicalDefinition(1);
          await useCases.startQuest(v1);
          final evaluation = await useCases.projectEvent(
            _makeEvent(occurredAtUtc: clock),
            [v1],
          );

          final payload = useCases.projectionPayload(evaluation, [
            _historicalDefinition(2),
          ]);

          expect(
            ((payload['rewardGrants'] as List).single as Map)['xpAmount'],
            25,
          );
        },
      );

      test(
        'expired D1 uses its pinned criteria and grant after D2 replacement',
        () async {
          final v1 = _historicalDefinition(1);
          final v2 = _historicalDefinition(2);
          final d1 = (await useCases.startQuest(v1))!;
          final oldSource = _makeEvent(
            occurredAtUtc: clock.add(const Duration(minutes: 30)),
          );
          clock = DateTime.utc(2026, 8, 5, 10);
          final d2 = (await useCases.startQuest(v2))!;

          final evaluation = await useCases.projectEvent(oldSource, [v2]);

          expect(evaluation.completed.single.questInstanceId, d1.instanceId);
          final grant =
              (useCases.projectionPayload(evaluation, [v2])['rewardGrants']
                          as List)
                      .single
                  as Map;
          expect(grant['xpAmount'], 25);
          final active = (await repo.getActiveInstances(testOwner.id)).single;
          expect(active.instanceId, d2.instanceId);
          expect(active.progress.single.currentCount, 0);
        },
      );

      test(
        'same-version live catalog mutation cannot bypass the immutable snapshot',
        () async {
          final original = _historicalDefinition(1);
          await useCases.startQuest(original);
          final changed = QuestDefinition(
            questId: original.questId,
            catalogVersion: 1,
            title: 'Mutated same version',
            description: original.description,
            type: original.type,
            objectives: original.objectives,
            reward: const RewardSpec(xpAmount: 999),
          );
          await repo.upsertDefinition(changed);

          await expectLater(
            useCases.projectEvent(_makeEvent(occurredAtUtc: clock), [changed]),
            throwsStateError,
          );

          expect(
            (await repo.getActiveInstances(
              testOwner.id,
            )).single.progress.single.currentCount,
            0,
          );
        },
      );

      test(
        'history keeps D1 title criteria and reward after catalog replacement',
        () async {
          final v1 = _historicalDefinition(1);
          final d1 = (await useCases.startQuest(v1))!;
          await useCases.projectEvent(_makeEvent(occurredAtUtc: clock), [v1]);
          clock = DateTime.utc(2026, 8, 5, 10);
          await useCases.startQuest(_historicalDefinition(2));

          final history = await useCases.loadStatusForCurrentOwner();
          final old = history.singleWhere(
            (entry) => entry.instance.instanceId == d1.instanceId,
          );

          expect(old.definition?.title, 'Original title');
          expect(old.definition?.reward.xpAmount, 25);
          expect(
            old.definition?.objectives.single.criteria.eventType,
            'QuizCompleted',
          );
        },
      );

      test(
        'valid failed-sink receipt remains authoritative after a catalog change',
        () async {
          final v1 = _historicalDefinition(1);
          final source = _makeEvent(occurredAtUtc: clock);
          var failSink = true;
          final granted = <String>{};
          final subject = historyUseCases(
            rewardSink:
                ({
                  required ownerId,
                  required idempotencyKey,
                  required xpAmount,
                  required sourceEventId,
                  required occurredAtUtc,
                  rewardItemId,
                }) async {
                  if (failSink) throw StateError('synthetic unavailable sink');
                  expect(xpAmount, 25);
                  granted.add(idempotencyKey);
                },
          );
          await subject.startQuest(v1);
          final receipt = subject.projectionPayload(
            await subject.projectEvent(source, [v1]),
            [v1],
          );
          await expectLater(
            subject.reconcileReward(source, receipt),
            throwsStateError,
          );
          clock = DateTime.utc(2026, 8, 5, 10);
          await subject.startQuest(_historicalDefinition(2));
          failSink = false;

          await subject.reconcileReward(source, receipt);
          await subject.reconcileReward(source, receipt);

          expect(granted, hasLength(1));
        },
      );

      test(
        'unknown legacy metadata cannot reconstruct a missing grant from live catalog',
        () async {
          final definition = _historicalDefinition(1);
          final source = _makeEvent(occurredAtUtc: clock);
          await repo.upsertDefinition(definition);
          await repo.startInstance(
            QuestInstance(
              instanceId: 'unknown-legacy',
              questId: definition.questId,
              ownerId: testOwner.id,
              catalogVersion: 1,
              assignedAtUtc: clock,
              state: QuestInstanceState.completed,
              completedAtUtc: clock,
              progress: [
                ObjectiveProgress(
                  objectiveId: 'history-answer',
                  currentCount: 1,
                  targetCount: 1,
                  sourceEventIds: [source.eventId],
                ),
              ],
            ),
          );

          await expectLater(
            useCases.projectEvent(source, [definition]),
            throwsStateError,
          );

          expect(
            (await repo.getAllInstances(testOwner.id)).single.instanceId,
            'unknown-legacy',
          );
          expect(
            await database.select(database.pointsLedgerEntries).get(),
            isEmpty,
          );
        },
      );

      test(
        'more than 100 versioned histories recover earliest and latest exact sources',
        () async {
          final sources = <EventEnvelopeV2>[];
          final instances = <QuestInstance>[];
          for (var index = 0; index < 105; index++) {
            clock = DateTime.utc(2026, 1, 1 + index, 10);
            final version = index + 1;
            final definition = _historicalDefinition(
              version,
              targetCount: 1,
              eventType: 'QuizCompleted',
            );
            instances.add((await useCases.startQuest(definition))!);
            final source = _makeEvent(occurredAtUtc: clock);
            sources.add(source);
            await useCases.projectEvent(source, [definition]);
          }
          for (final index in [0, 104]) {
            final evaluation = await useCases.projectEvent(sources[index], []);
            expect(
              evaluation.completed.single.questInstanceId,
              instances[index].instanceId,
            );
            final grant =
                (useCases.projectionPayload(evaluation, [])['rewardGrants']
                            as List)
                        .single
                    as Map;
            expect(grant['xpAmount'], index == 0 ? 25 : 900);
          }
          final absent = await repo.getCompletedInstancesForSourceEvent(
            ownerId: testOwner.id,
            sourceEventId: '${sources.first.eventId}-suffix',
            questIds: [],
          );
          expect(absent, isEmpty);
          expect(
            await repo.getCompletedInstancesForSourceEvent(
              ownerId: 'other-owner',
              sourceEventId: sources.first.eventId,
              questIds: [],
            ),
            isEmpty,
          );
          expect(
            (await database.select(database.questInstances).get()),
            hasLength(105),
          );
        },
      );
    });

    test(
      'assignment transaction rejects a stale expected owner before any quest write',
      () async {
        await database.customStatement('UPDATE local_owners SET is_active = 0');
        await database.customStatement(
          "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('replacement-owner','localGuest',1,1)",
        );
        await expectLater(
          useCases.startQuest(_singleObjectiveDef()),
          throwsStateError,
        );
        expect(await database.select(database.questInstances).get(), isEmpty);
        expect(
          await database.select(database.questObjectiveProgress).get(),
          isEmpty,
        );
        expect(await database.select(database.questDefinitions).get(), isEmpty);
      },
    );

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

    group('durable periods', () {
      late DateTime clock;

      setUp(() {
        clock = DateTime.utc(2026, 8, 4, 10);
        useCases = QuestUseCases(
          repository: repo,
          owners: _FakeOwners(testOwner),
          generateId: () => 'period-${++idCounter}',
          nowUtc: () => clock,
          timezoneId: 'Asia/Bangkok',
        );
      });

      for (final kind in [
        'incomplete-json',
        'incomplete-daily',
        'wrong-identity',
      ]) {
        test(
          'terminal legacy $kind snapshot cannot establish permanent occupancy',
          () async {
            final definition = _singleObjectiveDef(targetCount: 1);
            await repo.upsertDefinition(definition);
            final snapshotJson = kind.startsWith('incomplete-')
                ? '{"definition":{"type":"${kind == 'incomplete-json' ? 'milestone' : 'daily'}"}}'
                : QuestDefinitionCodec.encode(
                    QuestDefinitionSnapshot(
                      definition: _singleObjectiveDef(
                        questId: 'different-quest',
                        catalogVersion: 9,
                        type: QuestType.milestone,
                        targetCount: 1,
                      ),
                      origin: QuestDefinitionSnapshotOrigin.migrationCatalog,
                    ),
                  );
            await database.customStatement(
              '''INSERT INTO quest_instances
            (instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,
             period_policy,period_key,deadline_at_utc_ms,definition_snapshot_json)
            VALUES ('corrupt-terminal',?,?,1,?,'completed','legacyDuration','legacy:corrupt',?,?)''',
              [
                definition.questId,
                testOwner.id,
                clock.millisecondsSinceEpoch,
                clock.add(const Duration(hours: 1)).millisecondsSinceEpoch,
                snapshotJson,
              ],
            );
            await repo.saveProgress('corrupt-terminal', const [
              ObjectiveProgress(
                objectiveId: 'obj-uc',
                currentCount: 1,
                targetCount: 1,
                sourceEventIds: ['synthetic-source'],
              ),
            ]);
            clock = clock.add(const Duration(hours: 2));

            await expectLater(
              useCases.startQuest(definition),
              throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
            );

            final rows = await database.select(database.questInstances).get();
            expect(rows.single.instanceId, 'corrupt-terminal');
            expect(rows.single.definitionSnapshotJson, snapshotJson);
          },
        );
      }

      for (final type in [QuestType.milestone, QuestType.story]) {
        test(
          'completed legacy ${type.name} remains occupied after its finite deadline',
          () async {
            final definition = _singleObjectiveDef(
              type: type,
              targetCount: 1,
              expiresIn: const Duration(hours: 1),
            );
            await repo.upsertDefinition(definition);
            final legacy = QuestInstance(
              instanceId: 'legacy:once',
              questId: definition.questId,
              ownerId: testOwner.id,
              catalogVersion: 1,
              assignedAtUtc: clock,
              state: QuestInstanceState.completed,
              completedAtUtc: clock.add(const Duration(minutes: 1)),
              progress: const [
                ObjectiveProgress(
                  objectiveId: 'obj-uc',
                  currentCount: 1,
                  targetCount: 1,
                  sourceEventIds: ['legacy-source'],
                ),
              ],
              period: QuestPeriod(
                policy: QuestPeriodPolicy.legacyDuration,
                key: 'legacy:once',
                startAtUtc: clock,
                endAtUtc: clock.add(const Duration(hours: 1)),
                deadlineAtUtc: clock.add(const Duration(hours: 1)),
              ),
              definitionSnapshot: QuestDefinitionSnapshot(
                definition: definition,
                origin: QuestDefinitionSnapshotOrigin.migrationCatalog,
              ),
            );
            await repo.startInstance(legacy);
            clock = clock.add(const Duration(hours: 2));

            expect(await useCases.startQuest(definition), isNull);

            final history = await repo.getAllInstances(testOwner.id);
            expect(history.single.instanceId, legacy.instanceId);
            expect(history.single.period!.key, 'legacy:once');
            expect(history.single.progress.single.sourceEventIds, [
              'legacy-source',
            ]);
          },
        );
      }

      test('completed daily quest occupies its whole original day', () async {
        final definition = _singleObjectiveDef(targetCount: 1);
        final first = (await useCases.startQuest(definition))!;
        final source = _makeEvent(occurredAtUtc: clock);
        final completed = await useCases.projectEvent(source, [definition]);
        final grantBefore = useCases.projectionPayload(completed, [definition]);

        clock = clock.add(const Duration(hours: 1));
        expect(await useCases.startQuest(definition), isNull);
        final replay = await useCases.projectEvent(source, [definition]);

        expect(useCases.projectionPayload(replay, [definition]), grantBefore);
        final history = await repo.getAllInstances(testOwner.id);
        expect(history.single.instanceId, first.instanceId);
        expect(history.single.state, QuestInstanceState.completed);
        expect(history.single.progress.single.sourceEventIds, [source.eventId]);
      });

      test(
        'next local day renews completed quest and retains its identity',
        () async {
          final definition = _singleObjectiveDef(targetCount: 1);
          final first = (await useCases.startQuest(definition))!;
          final source = _makeEvent(occurredAtUtc: clock);
          final completed = await useCases.projectEvent(source, [definition]);
          final oldKey = completed.completed.single.idempotencyKey;

          clock = DateTime.utc(2026, 8, 4, 17); // Bangkok midnight, August 5.
          final next = await useCases.startQuest(definition);

          expect(next, isNotNull);
          expect(next!.instanceId, isNot(first.instanceId));
          expect(next.progress.single.currentCount, 0);
          final history = await repo.getAllInstances(testOwner.id);
          expect(history, hasLength(2));
          final old = history.singleWhere(
            (row) => row.instanceId == first.instanceId,
          );
          expect(old.state, QuestInstanceState.completed);
          expect(old.progress.single.sourceEventIds, [source.eventId]);
          expect(old.complete().idempotencyKey, oldKey);
          expect(
            await database.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
        },
      );

      test(
        'renewal expires prior daily window without an explicit duration',
        () async {
          final definition = _singleObjectiveDef();
          final first = (await useCases.startQuest(definition))!;
          clock = DateTime.utc(2026, 8, 4, 17);

          final next = await useCases.startQuest(definition);

          expect(next, isNotNull);
          final history = await repo.getAllInstances(testOwner.id);
          final old = history.singleWhere(
            (row) => row.instanceId == first.instanceId,
          );
          expect(old.state, QuestInstanceState.expired);
          expect(old.expiredAtUtc, clock);
          expect(
            (await repo.getActiveInstances(testOwner.id)).single.instanceId,
            next!.instanceId,
          );
        },
      );

      test(
        'explicit deadline expires at equality and keeps same-day occupancy',
        () async {
          final definition = _singleObjectiveDef(
            expiresIn: const Duration(hours: 1),
          );
          final first = (await useCases.startQuest(definition))!;
          clock = clock.add(const Duration(hours: 1));

          await useCases.expireStale();

          expect(await repo.getActiveInstances(testOwner.id), isEmpty);
          final expired = (await repo.getAllInstances(testOwner.id)).single;
          expect(expired.instanceId, first.instanceId);
          expect(expired.state, QuestInstanceState.expired);
          expect(expired.expiredAtUtc, clock);
          expect(await useCases.startQuest(definition), isNull);
        },
      );

      test(
        'delayed in-window evidence completes an expired canonical quest',
        () async {
          final definition = _singleObjectiveDef(
            targetCount: 1,
            expiresIn: const Duration(hours: 1),
          );
          final first = (await useCases.startQuest(definition))!;
          final source = _makeEvent(
            occurredAtUtc: clock.add(const Duration(minutes: 30)),
          );
          clock = clock.add(const Duration(hours: 2));
          await useCases.expireStale();
          expect(
            (await repo.getAllInstances(testOwner.id)).single.state,
            QuestInstanceState.expired,
          );

          final result = await useCases.projectEvent(source, [definition]);

          expect(result.eligible, isTrue);
          expect(result.completed.single.questInstanceId, first.instanceId);
          final history = (await repo.getAllInstances(testOwner.id)).single;
          expect(history.state, QuestInstanceState.completed);
          expect(history.progress.single.sourceEventIds, [source.eventId]);
        },
      );

      test(
        'event at the deadline never advances or grants the old window',
        () async {
          final definition = _singleObjectiveDef(
            targetCount: 1,
            expiresIn: const Duration(hours: 1),
          );
          await useCases.startQuest(definition);
          clock = clock.add(const Duration(hours: 1));
          final source = _makeEvent(occurredAtUtc: clock);

          final result = await useCases.projectEvent(source, [definition]);

          expect(result.eligible, isFalse);
          expect(result.completed, isEmpty);
          expect(
            (await repo.getAllInstances(
              testOwner.id,
            )).single.progress.single.currentCount,
            0,
          );
        },
      );

      test(
        'parallel daily assignments produce one instance and no orphan progress',
        () async {
          final definition = _singleObjectiveDef();

          final results = await Future.wait(
            List.generate(8, (_) => useCases.startQuest(definition)),
          );

          expect(results.whereType<QuestInstance>(), hasLength(1));
          final history = await repo.getAllInstances(testOwner.id);
          expect(history, hasLength(1));
          final progress = await database
              .select(database.questObjectiveProgress)
              .get();
          expect(progress, hasLength(1));
          expect(progress.single.instanceId, history.single.instanceId);
          expect(
            await database.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
        },
      );
    });

    test('built-in catalog lists are immutable version-pinned snapshots', () {
      expect(QuestCatalogProvider.allQuests, hasLength(2));
      expect(
        QuestCatalogProvider.allQuests,
        everyElement(
          isA<QuestDefinition>().having(
            (definition) => definition.catalogVersion,
            'catalogVersion',
            QuestCatalogProvider.version,
          ),
        ),
      );
      expect(
        () => QuestCatalogProvider.allQuests.add(_singleObjectiveDef()),
        throwsUnsupportedError,
      );
    });

    test(
      'startQuest rejects a changed active definition without mutating the pin',
      () async {
        final pinned = _orderedDefinition();
        final instance = await useCases.startQuest(pinned);
        final storedBefore = await repo.getDefinition(pinned.questId);

        await expectLater(
          useCases.startQuest(
            _orderedDefinition(catalogVersion: 2, reversed: true),
          ),
          throwsStateError,
        );

        final storedAfter = await repo.getDefinition(pinned.questId);
        final active = await repo.getActiveInstances(testOwner.id);
        expect(storedAfter?.catalogVersion, storedBefore?.catalogVersion);
        expect(
          storedAfter?.objectives.map((objective) => objective.objectiveId),
          storedBefore?.objectives.map((objective) => objective.objectiveId),
        );
        expect(active.single.instanceId, instance?.instanceId);
        expect(active.single.catalogVersion, pinned.catalogVersion);
        expect(active.single.progress, everyElement(isA<ObjectiveProgress>()));
        expect(
          active.single.progress.map((objective) => objective.currentCount),
          everyElement(0),
        );
      },
    );

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

    // ── evidence projection ──────────────────────────────────────────────────

    test(
      'deprecated processEvent cannot bypass durable reconciliation',
      () async {
        final def = _singleObjectiveDef(targetCount: 3);
        await useCases.startQuest(def);

        await expectLater(
          useCases.processEvent(_makeEvent(), [def]),
          throwsUnsupportedError,
        );

        final instances = await useCases.getActiveInstances();
        expect(instances.first.progress.first.currentCount, 0);
        expect(instances.first.progress.first.sourceEventIds, isEmpty);
      },
    );

    test('projectEvent ignores non-matching events', () async {
      final def = _singleObjectiveDef();
      await useCases.startQuest(def);

      await useCases.projectEvent(_makeEvent(eventType: 'SrsReviewCompleted'), [
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
      'projectEvent preflights every pinned definition before any progress',
      () async {
        final first = _singleObjectiveDef(questId: 'q-first', targetCount: 3);
        final second = _singleObjectiveDef(questId: 'q-second', targetCount: 3);
        await useCases.startQuest(first);
        await useCases.startQuest(second);

        await expectLater(
          useCases.projectEvent(_makeEvent(), [
            first,
            _singleObjectiveDef(
              questId: second.questId,
              targetCount: 3,
              catalogVersion: 2,
            ),
          ]),
          throwsStateError,
        );

        final active = await repo.getActiveInstances(testOwner.id);
        expect(active, hasLength(2));
        expect(
          active
              .expand((instance) => instance.progress)
              .map((objective) => objective.currentCount),
          everyElement(0),
          reason: 'catalog rejection must happen before the first write',
        );
      },
    );

    test(
      'projectEvent fails closed for removed or reordered quest definitions',
      () async {
        final definition = _orderedDefinition();
        await useCases.startQuest(definition);

        for (final invalidCatalog in <List<QuestDefinition>>[
          const <QuestDefinition>[],
          [_orderedDefinition(reversed: true)],
        ]) {
          await expectLater(
            useCases.projectEvent(_makeEvent(), invalidCatalog),
            throwsStateError,
          );
          expect(
            (await repo.getActiveInstances(
              testOwner.id,
            )).single.progress.map((objective) => objective.currentCount),
            everyElement(0),
          );
        }
      },
    );

    test('concurrent duplicate evidence advances exactly once', () async {
      final definition = _singleObjectiveDef(targetCount: 3);
      await useCases.startQuest(definition);
      final event = _makeEvent();

      await Future.wait<QuestProjectionEvaluation>(
        List<Future<QuestProjectionEvaluation>>.generate(
          12,
          (_) => useCases.projectEvent(event, [definition]),
        ),
      );

      final progress = (await repo.getActiveInstances(
        testOwner.id,
      )).single.progress.single;
      expect(progress.currentCount, 1);
      expect(progress.sourceEventIds, [event.eventId]);
    });

    test(
      'projectEvent returns QuestCompletedEvent when all objectives met',
      () async {
        final def = _singleObjectiveDef(targetCount: 2);
        await useCases.startQuest(def);

        await useCases.projectEvent(_makeEvent(), [def]); // count=1
        final completed = (await useCases.projectEvent(_makeEvent(), [
          def,
        ])).completed; // count=2→complete

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
        await useCases.projectEvent(_makeEvent(), [def]);

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

      await expectLater(crashing.projectEvent(event, [def]), throwsStateError);
      expect(
        (await repo.getActiveInstances(
          testOwner.id,
        )).single.progress.single.currentCount,
        1,
      );

      final completed = (await useCases.projectEvent(event, [def])).completed;
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
          'rewardItemId': ?rewardItemId,
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
