import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/apriori_error_miner_service.dart';

void main() {
  test('mineRules returns empty list when given empty input', () {
    expect(AprioriErrorMinerService.mineRules(errorSessions: []), isEmpty);
  });

  test('mineRules extracts X -> Y rules meeting support and confidence', () {
    final sessions = [
      ['analyze', 'hypothesis', 'data'],
      ['analyze', 'hypothesis'],
      ['analyze', 'hypothesis', 'experiment'],
      ['cat', 'dog'],
    ];

    final rules = AprioriErrorMinerService.mineRules(
      errorSessions: sessions,
      minSupport: 0.25,
      minConfidence: 0.60,
    );

    expect(rules, isNotEmpty);
    final topRule = rules.first;
    expect(topRule.antecedentWord, 'analyze');
    expect(topRule.consequentWord, 'hypothesis');
    expect(topRule.confidence, 1.0);
  });
}
