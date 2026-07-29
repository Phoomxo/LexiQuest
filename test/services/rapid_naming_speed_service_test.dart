import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/rapid_naming_speed_service.dart';

void main() {
  test('evaluateSpeed rates ultra-fast responses correctly', () {
    final report = RapidNamingSpeedService.evaluateSpeed(
      targetWord: 'apple',
      responseTimeMs: 350,
    );

    expect(report.targetWord, 'apple');
    expect(report.responseTimeMs, 350);
    expect(report.fluencyRating, contains('Ultra-Fast'));
    expect(report.automaticityScore, 100);
  });

  test('evaluateSpeed rates hesitant responses correctly', () {
    final report = RapidNamingSpeedService.evaluateSpeed(
      targetWord: 'sophisticated',
      responseTimeMs: 1800,
    );

    expect(report.fluencyRating, contains('Hesitant'));
    expect(report.automaticityScore, 40);
  });
}
