import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/models/srs_item.dart';
import 'package:vocab_learning_app/services/weakness_clinic_service.dart';

void main() {
  test(
    'WeaknessClinicService curates items with lowest box level and ease factor',
    () {
      final now = DateTime.now();
      final items = [
        SrsItem(
          word: 'master',
          boxLevel: 5,
          intervalDays: 30,
          lastReviewedAt: now,
          nextReviewAt: now,
        ),
        SrsItem(
          word: 'weak',
          boxLevel: 1,
          intervalDays: 1,
          lastReviewedAt: now,
          nextReviewAt: now,
        ),
        SrsItem(
          word: 'medium',
          boxLevel: 3,
          intervalDays: 5,
          lastReviewedAt: now,
          nextReviewAt: now,
        ),
      ];

      final service = const WeaknessClinicService();
      final curated = service.curateWeaknessDeck(items, limit: 2);

      expect(curated.length, 2);
      expect(curated.first.word, 'weak');
      expect(curated[1].word, 'medium');
    },
  );
}
