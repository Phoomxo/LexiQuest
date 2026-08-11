import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_repository.dart';
import 'package:vocab_learning_app/screens/quest_status_screen.dart';

void main() {
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

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Abandoned'), findsOneWidget);
    expect(find.text('1 / 2'), findsNWidgets(4));

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
  });

  testWidgets('renders typed failure without a mutation or retry affordance', (
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
    expect(find.text('Active'), findsOneWidget);
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

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
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

QuestInstance _instance(QuestInstanceState state, String instanceId) {
  return QuestInstance(
    instanceId: instanceId,
    questId: 'quest-secret',
    ownerId: 'owner-secret',
    catalogVersion: 1,
    assignedAtUtc: DateTime.utc(2026, 8, 10),
    state: state,
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
  Future<QuestDefinition?> getDefinition(String questId) async => null;

  @override
  Future<void> markAbandoned(String instanceId) async {}

  @override
  Future<void> markCompleted(
    String instanceId,
    DateTime completedAtUtc,
  ) async {}

  @override
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc) async {}

  @override
  Future<void> saveProgress(
    String instanceId,
    List<ObjectiveProgress> progress,
  ) async {}

  @override
  Future<void> startInstance(QuestInstance instance) async {}

  @override
  Future<void> upsertDefinition(QuestDefinition def) async {}
}
