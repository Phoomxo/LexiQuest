import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

import 'support/quest_repository_harness.dart';

void main() {
  late QuestHarness h;
  setUp(() async => h = await QuestHarness.open());
  tearDown(() => h.close());

  QuestInstance instance({String id = 'inst-001', String? questId}) =>
      QuestInstance(
        instanceId: id,
        questId: questId ?? questDefinition().questId,
        ownerId: configuredOwnerId,
        catalogVersion: 1,
        assignedAtUtc: h.now,
        state: QuestInstanceState.active,
        progress: [
          ObjectiveProgress(
            objectiveId: 'synthetic-objective',
            currentCount: 0,
            targetCount: 3,
          ),
        ],
      );

  group('DriftQuestRepository', () {
    test('upsertDefinition persists catalog row', () async {
      await h.repository.upsertDefinition(questDefinition());
      final definition = await h.repository.getDefinition(
        questDefinition().questId,
      );
      expect(definition, isNotNull);
      expect(definition!.title, 'Synthetic Quest');
      expect(definition.type, QuestType.daily);
      expect(definition.objectives, hasLength(1));
      expect(definition.objectives.single.targetCount, 3);
      expect(definition.reward.xpAmount, 50);
    });

    test('upsertDefinition with higher catalogVersion overwrites', () async {
      await h.repository.upsertDefinition(questDefinition());
      await h.repository.upsertDefinition(questDefinition(version: 2));
      expect(
        (await h.repository.getDefinition(
          questDefinition().questId,
        ))!.catalogVersion,
        2,
      );
    });

    test('getDefinition returns null for unknown questId', () async {
      expect(await h.repository.getDefinition('does-not-exist'), isNull);
    });

    test('startInstance persists instance with initial progress', () async {
      await h.repository.upsertDefinition(questDefinition());
      await h.repository.startInstance(instance());
      final active = await h.repository.getActiveInstances(configuredOwnerId);
      expect(active, hasLength(1));
      expect(active.single.instanceId, 'inst-001');
      expect(active.single.state, QuestInstanceState.active);
      expect(active.single.progress, hasLength(1));
      expect(active.single.progress.single.currentCount, 0);
      expect(active.single.progress.single.targetCount, 3);
    });

    test('startInstance is idempotent - duplicate call is ignored', () async {
      await h.repository.upsertDefinition(questDefinition());
      await h.repository.startInstance(instance());
      final before = await h.storage.snapshot();
      await h.repository.startInstance(instance());
      expect(
        await h.repository.getActiveInstances(configuredOwnerId),
        hasLength(1),
      );
      expect(await h.storage.snapshot(), before);
    });

    test('getActiveInstances excludes completed instances', () async {
      final activeDefinition = questDefinition(id: 'quest-active');
      final completedDefinition = questDefinition(
        id: 'quest-completed',
        target: 1,
      );
      await h.useCases.startQuest(activeDefinition);
      await h.useCases.startQuest(completedDefinition);
      final answer = await h.answer();
      await h.repository.applyCanonicalAnswer(
        ownerId: configuredOwnerId,
        event: answer,
        catalog: [activeDefinition, completedDefinition],
      );
      final active = await h.repository.getActiveInstances(configuredOwnerId);
      expect(active, hasLength(1));
      expect(active.single.questId, activeDefinition.questId);
    });

    test('getAllInstances returns all states', () async {
      await h.repository.upsertDefinition(questDefinition());
      await h.repository.upsertDefinition(questDefinition(id: 'quest-b'));
      await h.repository.startInstance(instance(id: 'inst-a'));
      await h.repository.startInstance(
        instance(id: 'inst-b', questId: 'quest-b'),
      );
      await h.repository.markExpired(
        'inst-b',
        h.now.add(const Duration(days: 1)),
      );
      expect(
        await h.repository.getAllInstances(configuredOwnerId),
        hasLength(2),
      );
    });

    test(
      'canonical answers persist objective counters and complete source chain',
      () async {
        final definition = questDefinition();
        await h.useCases.startQuest(definition);
        final a = await h.answer(id: 'evt-a');
        final b = await h.answer(id: 'evt-b');
        await h.apply(a, definition);
        await h.apply(b, definition);
        final progress = (await h.repository.getActiveInstances(
          configuredOwnerId,
        )).single.progress.single;
        expect(progress.currentCount, 2);
        expect(progress.sourceEventIds, ['evt-a', 'evt-b']);
      },
    );

    test(
      'canonical completion persists state and completedAtUtc atomically',
      () async {
        final definition = questDefinition(target: 1);
        await h.useCases.startQuest(definition);
        await h.apply(await h.answer(), definition);
        final completed = (await h.repository.getAllInstances(
          configuredOwnerId,
        )).single;
        expect(completed.state, QuestInstanceState.completed);
        expect(completed.completedAtUtc, h.now);
        expect(completed.progress.single.currentCount, 1);
        expect(completed.progress.single.sourceEventIds, [
          'synthetic-answer-1',
        ]);
      },
    );

    test('markExpired sets state and expiredAtUtc', () async {
      final started = (await h.useCases.startQuest(questDefinition()))!;
      final expired = h.now.add(const Duration(days: 1));
      await h.repository.markExpired(started.instanceId, expired);
      final all = await h.repository.getAllInstances(configuredOwnerId);
      expect(all.single.state, QuestInstanceState.expired);
      expect(all.single.expiredAtUtc, expired);
    });

    test('markAbandoned sets state to abandoned', () async {
      final started = (await h.useCases.startQuest(questDefinition()))!;
      await h.repository.markAbandoned(started.instanceId);
      expect(
        (await h.repository.getAllInstances(configuredOwnerId)).single.state,
        QuestInstanceState.abandoned,
      );
    });
  });
}
