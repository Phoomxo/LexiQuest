import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/lexical_diversity_evaluator_service.dart';

void main() {
  test('evaluateText calculates TTR = 1.0 when all words are unique', () {
    final report = LexicalDiversityEvaluatorService.evaluateText(
      'Sustainable technology brings incredible opportunities',
    );

    expect(report.totalTokens, 5);
    expect(report.uniqueTypes, 5);
    expect(report.ttrScore, 1.0);
    expect(report.diversityLevel, contains('Highly Diverse'));
  });

  test('evaluateText detects repetitive words correctly', () {
    final report = LexicalDiversityEvaluatorService.evaluateText(
      'go go go go go',
    );

    expect(report.totalTokens, 5);
    expect(report.uniqueTypes, 1);
    expect(report.ttrScore, 0.20);
    expect(report.diversityLevel, contains('Repetitive'));
  });
}
