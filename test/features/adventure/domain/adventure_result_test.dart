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

AdventureResult _result() => const AdventureResult(
  ownerId: 'owner:one',
  sessionId: 'session:one',
  learning: AdventureLearningResult(
    correctCount: 3,
    incorrectCount: 1,
    reviewDueCount: 1,
  ),
  effort: AdventureEffortResult(
    activeDuration: Duration(minutes: 5),
    completedItems: 4,
  ),
  engagement: AdventureEngagementResult(
    completedMission: true,
    returnedAfterBreak: false,
  ),
  reward: AdventureRewardReceiptView(
    state: AdventureCanonicalRewardState.pending,
  ),
  nextAction: AdventureNextAction.reviewCenter,
);
