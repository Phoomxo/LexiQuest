import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';

import '../quest/support/quest_repository_harness.dart';

void main() {
  test(
    'Progress uses canonical protected days and non-coin Quest XP without read writes',
    () async {
      final h = await QuestHarness.open();
      addTearDown(h.close);
      h.now = DateTime.utc(2026, 10, 29, 12);
      final base = questDefinition(id: 'synthetic-progress-week', target: 2);
      final weekly = QuestDefinition(
        questId: base.questId,
        catalogVersion: base.catalogVersion,
        title: base.title,
        description: base.description,
        type: QuestType.weekly,
        objectives: base.objectives,
        reward: const RewardSpec(xpAmount: 200),
      );
      await h.useCases.startQuest(weekly);
      final first = await h.answer(
        id: 'synthetic-progress-first',
        sessionId: 'synthetic-progress-day-one',
      );
      expect(await h.apply(first, weekly), isEmpty);
      h.now = DateTime.utc(2026, 10, 31, 12);
      final second = await h.answer(
        id: 'synthetic-progress-second',
        sessionId: 'synthetic-progress-day-two',
      );
      expect(await h.apply(second, weekly), hasLength(1));
      final progress = DriftProgressQueries(h.database);
      final beforeGrant = await progress.load(
        ownerId: configuredOwnerId,
        nowUtc: h.now,
      );
      final coins = (await DriftRewardRepository(
        h.database,
      ).load(configuredOwnerId)).balance;
      final streak = StreakUseCases(
        repository: DriftStreakRepository(
          h.database,
          ownerWrites: h.storage.ownerWrites,
          quests: h.repository,
          nowUtc: () => h.now,
        ),
        nowUtc: () => h.now,
        generateId: () => 'synthetic-progress-protect',
      );
      await streak.reconcileRewards(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      final snapshot = await streak.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      final current = await streak.protect(
        streak.prepareProtection(
          snapshot: snapshot,
          protectedDay: '2026-10-30',
          stillCurrent: () => true,
        ),
      );
      expect(current.state.currentStreakDays, 2);
      expect(current.questXp, 200);
      final beforeRead = await h.storage.snapshot();
      final displayed = await progress.load(
        ownerId: configuredOwnerId,
        nowUtc: h.now,
      );
      expect(
        {'streak': displayed.streakDays, 'xp': displayed.totalXp},
        {
          'streak': current.state.currentStreakDays,
          'xp': beforeGrant.totalXp + current.questXp,
        },
      );
      expect(await h.storage.snapshot(), beforeRead);
      expect(
        (await DriftRewardRepository(
          h.database,
        ).load(configuredOwnerId)).balance,
        coins,
      );
      expect((await h.storage.researchCounts()).values, everyElement(0));
    },
  );
}
