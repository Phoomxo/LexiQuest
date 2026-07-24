import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/zpd_recommender_service.dart';

void main() {
  final service = ZpdRecommenderService();

  test('recommendZpdWords recommends B1 words when A2 accuracy >= 80%', () {
    final words = service.recommendZpdWords(
      currentLevel: 'A2',
      currentAccuracyPercent: 85.0,
    );
    expect(words.isNotEmpty, true);
    expect(words.every((w) => w.cefrLevel == 'B1'), true);
  });

  test('recommendZpdWords stays at A2 when accuracy < 80%', () {
    final words = service.recommendZpdWords(
      currentLevel: 'A2',
      currentAccuracyPercent: 75.0,
    );
    expect(words.isNotEmpty, true);
    expect(words.every((w) => w.cefrLevel == 'A2'), true);
  });
}
