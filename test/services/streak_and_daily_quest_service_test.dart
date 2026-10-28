import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/streak_and_daily_quest_service.dart';

void main() {
  final service = StreakAndDailyQuestService();

  test('StreakAndDailyQuestService tracks streak days and freeze count', () {
    expect(service.currentStreakDays, 1);
    service.addStreakDay();
    expect(service.currentStreakDays, 2);

    expect(service.streakFreezeCount, 1);
    expect(service.useStreakFreeze(), true);
    expect(service.streakFreezeCount, 0);
    expect(service.useStreakFreeze(), false);
  });

  test('StreakAndDailyQuestService increments progress and claims reward', () {
    final quest = service.quests.firstWhere((q) => q.id == 'review_words');
    expect(quest.isCompleted, false);

    service.incrementProgress('review_words', 10);
    expect(quest.isCompleted, true);

    expect(service.claimReward('review_words'), true);
    expect(quest.isClaimed, true);
    expect(service.claimReward('review_words'), false);
  });
}
