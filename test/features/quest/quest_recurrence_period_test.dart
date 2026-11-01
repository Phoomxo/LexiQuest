import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';

import 'support/quest_repository_harness.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  late QuestHarness h;
  late DriftRewardRepository rewards;
  late QuestDefinition definition;
  setUp(() async {
    h = await QuestHarness.open();
    h.now = DateTime.utc(2026, 10, 29, 16, 58);
    rewards = DriftRewardRepository(h.database);
    definition = questDefinition(
      id: 'synthetic-daily-recurrence',
      target: 1,
      expiry: const Duration(days: 1),
    );
  });
  tearDown(() => h.close());

  test('an active daily period is not assigned twice', () async {
    final first = (await h.useCases.startQuest(definition))!;
    final coins = (await rewards.load(configuredOwnerId)).balance;
    final before = await h.storage.snapshot();
    h.now = h.now.add(const Duration(seconds: 30));

    expect(await h.useCases.startQuest(definition), isNull);
    final stored = await h.repository.getAllInstances(configuredOwnerId);
    expect(stored, hasLength(1));
    expect(stored.single.instanceId, first.instanceId);
    expect(stored.single.state, QuestInstanceState.active);
    expect(stored.single.progress.single.currentCount, 0);
    expect((await rewards.load(configuredOwnerId)).balance, coins);
    expect(await h.storage.snapshot(), before);
    await _expectNoResearch(h);
  });

  test(
    'a completed daily period stays completed until its next civil day',
    () async {
      final first = await _complete(
        h,
        definition,
        'synthetic-recurrence-first',
      );
      final coins = (await rewards.load(configuredOwnerId)).balance;
      final before = await h.storage.snapshot();
      h.now = h.now.add(const Duration(seconds: 30));

      expect(await h.useCases.startQuest(definition), isNull);
      final stored = await h.repository.getAllInstances(configuredOwnerId);
      expect(stored, hasLength(1));
      expect(stored.single.instanceId, first.instanceId);
      expect(stored.single.state, QuestInstanceState.completed);
      expect(stored.single.completedAtUtc, first.completedAtUtc);
      expect(stored.single.progress.single.sourceEventIds, [
        'synthetic-recurrence-first',
      ]);
      expect((await rewards.load(configuredOwnerId)).balance, coins);
      expect(await h.storage.snapshot(), before);
      await _expectNoResearch(h);
    },
  );

  test(
    'the next Bangkok civil day admits a new daily period on the same UTC date',
    () async {
      final first = await _complete(
        h,
        definition,
        'synthetic-recurrence-first',
      );
      final completed = (await h.repository.getAllInstances(
        configuredOwnerId,
      )).single;
      final coins = (await rewards.load(configuredOwnerId)).balance;
      final protected = await h.protectedSnapshot();
      h.now = DateTime.utc(2026, 10, 29, 17);

      final next = await h.useCases.startQuest(definition);
      expect(next, isNotNull);
      expect(next!.instanceId, isNot(first.instanceId));
      expect(next.ownerId, configuredOwnerId);
      expect(next.assignedAtUtc, h.now);
      expect(next.state, QuestInstanceState.active);
      expect(next.progress.single.currentCount, 0);
      expect((await rewards.load(configuredOwnerId)).balance, coins);
      expect(await h.protectedSnapshot(), protected);

      final history = await h.repository.getAllInstances(configuredOwnerId);
      expect(history, hasLength(2));
      final previous = history.singleWhere(
        (item) => item.instanceId == first.instanceId,
      );
      expect(previous.state, QuestInstanceState.completed);
      expect(previous.assignedAtUtc, completed.assignedAtUtc);
      expect(previous.completedAtUtc, completed.completedAtUtc);
      expect(previous.progress.single.sourceEventIds, [
        'synthetic-recurrence-first',
      ]);
      expect(await h.useCases.startQuest(definition), isNull);

      h.now = h.now.add(const Duration(seconds: 1));
      final answer = await h.answer(
        id: 'synthetic-recurrence-second',
        sessionId: 'synthetic-recurrence-second-session',
      );
      final coinsBeforeCompletion = (await rewards.load(
        configuredOwnerId,
      )).balance;
      final completions = await h.useCases.processEvent(answer, [definition]);
      expect(completions, hasLength(1));
      expect(completions.single.questInstanceId, next.instanceId);
      expect(completions.single.objectiveEventIds, [
        'synthetic-recurrence-second',
      ]);
      expect(completions.single.completedAtUtc, answer.occurredAtUtc);
      expect(
        (await rewards.load(configuredOwnerId)).balance,
        coinsBeforeCompletion,
      );
      expect(await h.useCases.processEvent(answer, [definition]), isEmpty);
      await _expectNoResearch(h);
    },
  );
}

Future<QuestInstance> _complete(
  QuestHarness h,
  QuestDefinition definition,
  String answerId,
) async {
  final first = (await h.useCases.startQuest(definition))!;
  h.now = h.now.add(const Duration(seconds: 1));
  final answer = await h.answer(
    id: answerId,
    sessionId: 'synthetic-recurrence-first-session',
  );
  final completions = await h.useCases.processEvent(answer, [definition]);
  expect(completions, hasLength(1));
  expect(completions.single.questInstanceId, first.instanceId);
  expect(completions.single.objectiveEventIds, [answerId]);
  expect(completions.single.completedAtUtc, answer.occurredAtUtc);
  expect(await h.useCases.processEvent(answer, [definition]), isEmpty);
  return (await h.repository.getAllInstances(configuredOwnerId)).single;
}

Future<void> _expectNoResearch(QuestHarness h) async {
  expect((await h.storage.researchCounts()).values, everyElement(0));
}
