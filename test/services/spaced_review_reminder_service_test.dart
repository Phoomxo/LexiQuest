import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/models/srs_item.dart';
import 'package:vocab_learning_app/services/spaced_review_reminder_service.dart';

void main() {
  const service = SpacedReviewReminderService();

  test('isDueForEbbinghausReview flags due items or low box levels', () {
    final item = SrsItem(
      word: 'test',
      boxLevel: 1,
      intervalDays: 1,
      lastReviewedAt: DateTime.now().subtract(const Duration(days: 2)),
      nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
    );

    expect(service.isDueForEbbinghausReview(item), true);
  });
}
