import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/models/srs_item.dart';
import 'package:vocab_learning_app/services/adaptive_decay_scheduler.dart';

void main() {
  const scheduler = AdaptiveDecayScheduler();

  test('calculateRetentionProbability computes decay over time', () {
    final now = DateTime.now();
    final item = SrsItem(
      word: 'test',
      boxLevel: 1,
      easeFactor: 2.5,
      intervalDays: 1,
      lastReviewedAt: now.subtract(const Duration(days: 5)),
      nextReviewAt: now,
    );

    final retention = scheduler.calculateRetentionProbability(item, now: now);
    expect(retention < 1.0, true);
    expect(retention >= 0.0, true);
    expect(scheduler.needsImmediateReview(item, now: now), true);
  });
}
