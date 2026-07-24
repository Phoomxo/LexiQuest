import 'dart:math';
import '../models/srs_item.dart';

class AdaptiveDecayScheduler {
  const AdaptiveDecayScheduler();

  /// Calculates memory retention probability (0.0 to 1.0) using exponential decay:
  /// R = e^(-t / h)
  /// where halfLife h = 2^(boxLevel * easeFactor)
  double calculateRetentionProbability(SrsItem item, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final elapsedDays = current.difference(item.lastReviewedAt).inHours / 24.0;
    if (elapsedDays <= 0) return 1.0;

    final halfLifeDays = pow(2.0, item.boxLevel * item.easeFactor).toDouble();
    final retention = exp(-elapsedDays / halfLifeDays);
    return retention.clamp(0.0, 1.0);
  }

  /// Recommends immediate review if retention probability falls below threshold (default 50%).
  bool needsImmediateReview(
    SrsItem item, {
    double threshold = 0.50,
    DateTime? now,
  }) {
    return calculateRetentionProbability(item, now: now) < threshold;
  }
}
