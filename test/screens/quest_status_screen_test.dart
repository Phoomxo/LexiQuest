import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_definition_codec.dart';
import 'package:vocab_learning_app/screens/quest_status_screen.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  testWidgets('visible quest page reloads Day2 after durable refresh completes', (
    tester,
  ) async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customStatement(
      "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('owner-secret','localGuest',1,1)",
    );
    var clock = DateTime.utc(2026, 8, 4, 10);
    var ids = 0;
    final subject = QuestUseCases(
      repository: DriftQuestRepository(database),
      owners: _OwnerFake(),
      generateId: () => 'visible-${++ids}',
      nowUtc: () => clock,
      timezoneId: 'Asia/Bangkok',
    );
    addTearDown(subject.dispose);
    await subject.refreshDaily(expectedOwnerId: 'owner-secret');
    await tester.pumpWidget(
      MaterialApp(home: QuestStatusScreen(quest: subject)),
    );
    await tester.pumpAndSettle();
    expect(find.text('กำลังทำ'), findsOneWidget);
    expect(find.text('ทำได้ในครั้งถัดไป'), findsNothing);
    clock = clock.add(const Duration(days: 1));
    await subject.refreshDaily(expectedOwnerId: 'owner-secret');
    await tester.pumpAndSettle();
    expect(find.text('กำลังทำ'), findsOneWidget);
    expect(find.text('ทำได้ในครั้งถัดไป'), findsOneWidget);
    expect(await database.select(database.questInstances).get(), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'refresh listeners detach on quest replacement and page disposal',
    (tester) async {
      final firstRepo = _QuestRepositoryFake();
      final secondRepo = _QuestRepositoryFake();
      final first = _useCases(firstRepo);
      final second = _useCases(secondRepo);
      await tester.pumpWidget(
        MaterialApp(
          home: QuestStatusScreen(
            key: const ValueKey('same-page'),
            quest: first,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: QuestStatusScreen(
            key: const ValueKey('same-page'),
            quest: second,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final oldReads = firstRepo.readCalls;
      final newReads = secondRepo.readCalls;
      await first.refreshDaily(expectedOwnerId: 'owner-secret');
      await tester.pumpAndSettle();
      expect(firstRepo.readCalls, oldReads);
      expect(secondRepo.readCalls, newReads);
      await second.refreshDaily(expectedOwnerId: 'owner-secret');
      await tester.pumpAndSettle();
      expect(secondRepo.readCalls, newReads + 1);
      await tester.pumpWidget(const SizedBox.shrink());
      final disposedReads = secondRepo.readCalls;
      await second.refreshDaily(expectedOwnerId: 'owner-secret');
      await tester.pumpAndSettle();
      expect(secondRepo.readCalls, disposedReads);
      expect(tester.takeException(), isNull);
      first.dispose();
      second.dispose();
    },
  );

  for (final disposePage in [false, true]) {
    testWidgets(
      'old pending status future cannot replace a retired view disposed=$disposePage',
      (tester) async {
        final pending = Completer<List<QuestInstance>>();
        final oldRepo = _QuestRepositoryFake()..pending = pending;
        final oldQuest = _useCases(oldRepo);
        final newRepo = _QuestRepositoryFake()
          ..instances = [
            _instance(QuestInstanceState.completed, 'new-owner-state'),
          ];
        final newQuest = _useCases(newRepo);
        await tester.pumpWidget(
          MaterialApp(
            home: QuestStatusScreen(
              key: const ValueKey('stable-status'),
              quest: oldQuest,
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(QuestStatusLoading), findsOneWidget);
        await tester.pumpWidget(
          disposePage
              ? const SizedBox.shrink()
              : MaterialApp(
                  home: QuestStatusScreen(
                    key: const ValueKey('stable-status'),
                    quest: newQuest,
                  ),
                ),
        );
        await tester.pumpAndSettle();
        pending.complete([
          _instance(QuestInstanceState.active, 'retired-owner-state'),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('กำลังทำ'), findsNothing);
        expect(
          find.text('สำเร็จแล้ว'),
          disposePage ? findsNothing : findsOneWidget,
        );
        expect(oldRepo.readCalls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        oldQuest.dispose();
        newQuest.dispose();
      },
    );
  }

  testWidgets('quest shows its pinned authored goal and objective progress', (
    tester,
  ) async {
    final repository = _QuestRepositoryFake()
      ..definition = QuestDefinition(
        questId: 'quest-secret',
        catalogVersion: 1,
        title: 'ภารกิจคำศัพท์ที่กำหนด',
        description: 'ตอบคำถามตามเป้าหมายที่บันทึกไว้',
        type: QuestType.daily,
        objectives: [
          QuestObjective(
            objectiveId: 'objective-secret',
            description: 'คำตอบถูก',
            targetCount: 2,
            criteria: ObjectiveCriteria(eventType: 'QuizCompleted'),
          ),
        ],
        reward: RewardSpec(xpAmount: 8),
      );
    repository.instances = [
      _instance(
        QuestInstanceState.active,
        'instance-one',
        definition: repository.definition,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: QuestStatusScreen(quest: _useCases(repository))),
    );
    await tester.pumpAndSettle();
    expect(find.text('ภารกิจคำศัพท์ที่กำหนด'), findsOneWidget);
    expect(find.text('ตอบคำถามตามเป้าหมายที่บันทึกไว้'), findsOneWidget);
    expect(find.textContaining('คำตอบถูก'), findsOneWidget);
    expect(find.textContaining('1 จาก 2'), findsOneWidget);
    expect(repository.mutations, 0);
  });

  testWidgets('failed quest load retries only the read', (tester) async {
    final repository = _QuestRepositoryFake()
      ..failure = StateError('synthetic');
    await tester.pumpWidget(
      MaterialApp(home: QuestStatusScreen(quest: _useCases(repository))),
    );
    await tester.pumpAndSettle();
    repository.failure = null;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestStatusEmpty), findsOneWidget);
    expect(repository.readCalls, 2);
    expect(repository.mutations, 0);
  });
  testWidgets(
    'loads exactly once with limit 50 and renders loading then empty',
    (tester) async {
      final repository = _QuestRepositoryFake();
      final pending = Completer<List<QuestInstance>>();
      repository.pending = pending;

      await tester.pumpWidget(
        MaterialApp(home: QuestStatusScreen(quest: _useCases(repository))),
      );
      await tester.pump();

      expect(find.byType(QuestStatusLoading), findsOneWidget);
      expect(repository.readCalls, 1);
      expect(repository.lastLimit, 50);

      await tester.pump();
      expect(repository.readCalls, 1);

      pending.complete(const []);
      await tester.pump();
      expect(find.byType(QuestStatusEmpty), findsOneWidget);
      expect(repository.readCalls, 1);
    },
  );

  testWidgets('renders all lifecycle states without internal identifiers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _QuestRepositoryFake()
      ..instances = [
        _instance(QuestInstanceState.active, 'instance-active-secret'),
        _instance(QuestInstanceState.completed, 'instance-done-secret'),
        _instance(QuestInstanceState.expired, 'instance-expired-secret'),
        _instance(QuestInstanceState.abandoned, 'instance-abandoned-secret'),
      ];

    await tester.pumpWidget(
      MaterialApp(home: QuestStatusScreen(quest: _useCases(repository))),
    );
    await tester.pumpAndSettle();

    expect(find.text('กำลังทำ'), findsOneWidget);
    expect(find.text('สำเร็จแล้ว'), findsOneWidget);
    expect(find.text('ทำได้ในครั้งถัดไป'), findsOneWidget);
    expect(find.text('พักไว้'), findsOneWidget);
    expect(find.text('ความคืบหน้าที่บันทึกไว้: 1 จาก 2'), findsNWidgets(4));

    final renderedText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .join('|');
    for (final internalValue in <String>[
      'owner-secret',
      'quest-secret',
      'instance-active-secret',
      'instance-done-secret',
      'instance-expired-secret',
      'instance-abandoned-secret',
      'objective-secret',
      'source-event-secret',
    ]) {
      expect(renderedText, isNot(contains(internalValue)));
    }
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.textContaining('lost'), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
    expect(find.textContaining('XP'), findsNothing);
    expect(find.textContaining('Coins'), findsNothing);
  });

  testWidgets('renders typed failure with a read-only retry affordance', (
    tester,
  ) async {
    final repository = _QuestRepositoryFake()
      ..failure = StateError('database-secret');

    await tester.pumpWidget(
      MaterialApp(home: QuestStatusScreen(quest: _useCases(repository))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuestStatusFailure), findsOneWidget);
    expect(find.textContaining('database-secret'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(repository.readCalls, 1);
  });

  testWidgets('missing quest dependency is a typed unavailable state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: QuestStatusScreen()));
    await tester.pump();

    expect(find.byType(QuestStatusUnavailable), findsOneWidget);
  });

  testWidgets('reloads once when the mounted quest dependency changes', (
    tester,
  ) async {
    final repositoryA = _QuestRepositoryFake()
      ..instances = [_instance(QuestInstanceState.active, 'owner-a-instance')];
    final repositoryB = _QuestRepositoryFake()
      ..instances = [
        _instance(QuestInstanceState.completed, 'owner-b-instance'),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: QuestStatusScreen(
          key: const ValueKey<String>('quest-status'),
          quest: _useCases(repositoryA),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('กำลังทำ'), findsOneWidget);
    expect(repositoryA.readCalls, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: QuestStatusScreen(
          key: const ValueKey<String>('quest-status'),
          quest: _useCases(repositoryB),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('สำเร็จแล้ว'), findsOneWidget);
    expect(find.text('กำลังทำ'), findsNothing);
    expect(repositoryA.readCalls, 1);
    expect(repositoryB.readCalls, 1);
    expect(repositoryB.lastLimit, 50);
  });
}

QuestUseCases _useCases(_QuestRepositoryFake repository) {
  return QuestUseCases(
    repository: repository,
    owners: _OwnerFake(),
    generateId: () => 'unused',
    nowUtc: () => DateTime.utc(2026, 8, 11),
    timezoneId: 'Asia/Bangkok',
  );
}

QuestInstance _instance(
  QuestInstanceState state,
  String instanceId, {
  QuestDefinition? definition,
}) {
  return QuestInstance(
    instanceId: instanceId,
    questId: 'quest-secret',
    ownerId: 'owner-secret',
    catalogVersion: 1,
    assignedAtUtc: DateTime.utc(2026, 8, 10),
    state: state,
    definitionSnapshot: definition == null
        ? null
        : QuestDefinitionSnapshot(
            definition: definition,
            origin: QuestDefinitionSnapshotOrigin.capturedAssignment,
          ),
    progress: const [
      ObjectiveProgress(
        objectiveId: 'objective-secret',
        currentCount: 1,
        targetCount: 2,
        sourceEventIds: ['source-event-secret'],
      ),
    ],
  );
}

final class _OwnerFake implements LocalOwnerRepository {
  static final owner = LocalOwner(
    id: 'owner-secret',
    createdAtUtc: DateTime.utc(2026, 8, 1),
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => owner;

  @override
  Future<LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async => owner;
}

final class _QuestRepositoryFake implements QuestRepository {
  @override
  Future<bool> assignForPeriod({
    required QuestDefinition definition,
    required QuestInstance instance,
    required DateTime nowUtc,
  }) async {
    mutations++;
    return false;
  }

  @override
  Future<void> expireStaleInstances({
    required String ownerId,
    required DateTime nowUtc,
  }) async {
    mutations++;
  }

  @override
  Future<List<QuestInstance>> getProjectionCandidates({
    required String ownerId,
    required DateTime occurredAtUtc,
    required Iterable<String> questIds,
  }) async => instances
      .where(
        (instance) =>
            instance.ownerId == ownerId &&
            instance.isCanonical &&
            questIds.contains(instance.questId) &&
            (instance.state == QuestInstanceState.active ||
                instance.state == QuestInstanceState.expired) &&
            !occurredAtUtc.isBefore(instance.assignedAtUtc) &&
            (instance.period?.deadlineAtUtc == null ||
                occurredAtUtc.isBefore(instance.period!.deadlineAtUtc!)),
      )
      .toList(growable: false);
  QuestDefinition? definition;
  int mutations = 0;
  List<QuestInstance> instances = const [];
  Completer<List<QuestInstance>>? pending;
  Object? failure;
  int readCalls = 0;
  int? lastLimit;

  @override
  Future<List<QuestInstance>> getAllInstances(
    String ownerId, {
    int limit = 50,
  }) async {
    readCalls += 1;
    lastLimit = limit;
    final error = failure;
    if (error != null) throw error;
    final wait = pending;
    if (wait != null) return wait.future;
    return instances;
  }

  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) async =>
      instances
          .where((instance) => instance.state == QuestInstanceState.active)
          .toList(growable: false);

  @override
  Future<List<QuestInstance>> getCompletedInstancesForSourceEvent({
    required String ownerId,
    required String sourceEventId,
    required Iterable<String> questIds,
    int limit = 64,
  }) async => const [];

  @override
  Future<QuestDefinition?> getDefinition(String questId) async => definition;

  @override
  Future<void> markAbandoned(String instanceId) async {
    mutations++;
  }

  @override
  Future<void> markCompleted(String instanceId, DateTime completedAtUtc) async {
    mutations++;
  }

  @override
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc) async {
    mutations++;
  }

  @override
  Future<void> saveProgress(
    String instanceId,
    List<ObjectiveProgress> progress,
  ) async {
    mutations++;
  }

  @override
  Future<void> startInstance(QuestInstance instance) async {
    mutations++;
  }

  @override
  Future<void> upsertDefinition(QuestDefinition def) async {
    mutations++;
  }
}
