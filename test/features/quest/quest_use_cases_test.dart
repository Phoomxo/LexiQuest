import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

import 'support/quest_repository_harness.dart';

void main() {
  late QuestHarness h;
  setUp(() async => h = await QuestHarness.open());
  tearDown(() => h.close());

  group('QuestUseCases', () {
    test('startQuest creates active instance', () async {
      final definition = questDefinition();
      final instance = await h.useCases.startQuest(definition);
      expect(instance, isNotNull);
      expect(instance!.state, QuestInstanceState.active);
      expect(instance.questId, definition.questId);
      expect(instance.ownerId, configuredOwnerId);
      expect(instance.progress, hasLength(1));
      expect(instance.progress.single.currentCount, 0);
    });

    test('startQuest returns null if quest is already active', () async {
      final definition = questDefinition();
      await h.useCases.startQuest(definition);
      expect(await h.useCases.startQuest(definition), isNull);
    });

    test('startQuest persists catalog definition', () async {
      final definition = questDefinition();
      await h.useCases.startQuest(definition);
      expect(
        (await h.repository.getDefinition(definition.questId))!.title,
        definition.title,
      );
    });

    test('processEvent advances matching objective', () async {
      final definition = questDefinition();
      await h.useCases.startQuest(definition);
      expect(
        await h.useCases.processEvent(await h.answer(), [definition]),
        isEmpty,
      );
      expect(
        (await h.useCases.getActiveInstances())
            .single
            .progress
            .single
            .currentCount,
        1,
      );
    });

    test('processEvent ignores a canonical non-matching answer', () async {
      final definition = questDefinition();
      await h.useCases.startQuest(definition);
      await h.useCases.processEvent(await h.answer(correct: false), [
        definition,
      ]);
      expect(
        (await h.useCases.getActiveInstances())
            .single
            .progress
            .single
            .currentCount,
        0,
      );
    });

    test(
      'processEvent returns QuestCompletedEvent when all objectives met',
      () async {
        final definition = questDefinition(target: 2);
        final instance = (await h.useCases.startQuest(definition))!;
        await h.useCases.processEvent(await h.answer(), [definition]);
        final completed = await h.useCases.processEvent(
          await h.answer(id: 'synthetic-answer-2'),
          [definition],
        );
        expect(completed, hasLength(1));
        expect(completed.single.questInstanceId, instance.instanceId);
        expect(completed.single.idempotencyKey, startsWith('quest_complete_'));
        expect(completed.single.objectiveEventIds, hasLength(2));
        expect(
          (await h.repository.getAllInstances(configuredOwnerId)).single.state,
          QuestInstanceState.completed,
        );
      },
    );

    test(
      'completed instance no longer appears in getActiveInstances',
      () async {
        final definition = questDefinition(target: 1);
        await h.useCases.startQuest(definition);
        await h.useCases.processEvent(await h.answer(), [definition]);
        expect(await h.useCases.getActiveInstances(), isEmpty);
      },
    );

    test(
      'expireStale marks expired instances whose deadline has passed',
      () async {
        final definition = questDefinition(
          target: 99,
          expiry: const Duration(hours: 1),
        );
        await h.useCases.startQuest(definition);
        h.now = h.now.add(const Duration(hours: 2));
        await h.useCases.expireStale();
        expect(
          await h.repository.getActiveInstances(configuredOwnerId),
          isEmpty,
        );
        expect(
          (await h.repository.getAllInstances(configuredOwnerId)).single.state,
          QuestInstanceState.expired,
        );
      },
    );

    test('expireStale ignores instances without expiry', () async {
      await h.useCases.startQuest(questDefinition());
      await h.useCases.expireStale();
      expect(await h.useCases.getActiveInstances(), hasLength(1));
    });
  });
}
