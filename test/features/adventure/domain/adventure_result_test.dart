import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_result.dart';

void main() {
  test('keeps Learning, Effort and Engagement as separate typed sections', () {
    final result = _result();
    expect(result.learning, isA<AdventureLearningResult>());
    expect(result.effort, isA<AdventureEffortResult>());
    expect(result.engagement, isA<AdventureEngagementResult>());
    expect(result.toJson().keys, <String>[
      'ownerId',
      'sessionId',
      'learning',
      'effort',
      'engagement',
      'motivation',
      'reward',
      'nextAction',
      'technicalMessage',
    ]);
    expect(result.toJson().keys, isNot(contains('combinedScore')));
  });

  test('pending canonical reward is separate from accepted learning', () {
    final result = _result();
    expect(result.learning.correctCount, 3);
    expect(result.reward.state, AdventureCanonicalRewardState.pending);
    expect(result.reward.receiptId, isNull);
  });
}

AdventureResult _result() => AdventureResult(
  ownerId: 'owner:one',
  sessionId: 'session:one',
  learning: const AdventureLearningResult(
    correctCount: 3,
    incorrectCount: 1,
    reviewDueCount: 1,
  ),
  effort: const AdventureEffortResult(
    activeDuration: Duration(minutes: 5),
    completedItems: 4,
  ),
  engagement: const AdventureEngagementResult(
    completedMission: true,
    returnedAfterBreak: false,
  ),
  motivation: AdventureMotivationReceiptView(
    questState: AdventureCanonicalReceiptState.committed,
    streakState: AdventureCanonicalReceiptState.committed,
    achievementState: AdventureCanonicalReceiptState.notEligible,
    questCodes: <String>['daily-quest'],
    streakCodes: <String>['daily-streak'],
  ),
  reward: const AdventureRewardReceiptView(
    state: AdventureCanonicalRewardState.pending,
  ),
  nextAction: AdventureNextAction.reviewCenter,
);
