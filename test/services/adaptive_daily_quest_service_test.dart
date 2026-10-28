import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/adaptive_daily_quest_service.dart';
import 'package:vocab_learning_app/services/kmeans_learner_profiler_service.dart';

void main() {
  test(
    'generateQuests produces Master Performer quests for masterPerformer persona',
    () {
      final quests = AdaptiveDailyQuestService.generateQuests(
        LearnerPersona.masterPerformer,
      );

      expect(quests, isNotEmpty);
      expect(quests.first.title, contains('ร่างเงา'));
      expect(quests.first.rewardXp, 200);
    },
  );

  test(
    'generateQuests produces At-Risk remediation quests for atRiskLearner persona',
    () {
      final quests = AdaptiveDailyQuestService.generateQuests(
        LearnerPersona.atRiskLearner,
      );

      expect(quests, isNotEmpty);
      expect(quests.first.title, contains('จุดอ่อน'));
      expect(quests.first.rewardXp, 250);
    },
  );
}
