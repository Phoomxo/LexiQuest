import '../models/srs_item.dart';

class SpacedReviewReminderService {
  const SpacedReviewReminderService();

  /// Calculates whether an SRS item needs urgent review before memory retention drops below 60%.
  bool isDueForEbbinghausReview(SrsItem item) {
    final now = DateTime.now();
    return now.isAfter(item.nextReviewAt) || item.boxLevel <= 2;
  }
}
