import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/utils/pronunciation_evaluator.dart';

void main() {
  test('PronunciationEvaluator evaluates exact matches as 100%', () {
    final diff = PronunciationEvaluator.evaluate('apple', 'apple');
    expect(diff.scorePercentage, 100);
    expect(diff.isExactMatch, true);
  });

  test(
    'PronunciationEvaluator evaluates case-insensitive exact matches as 100%',
    () {
      final diff = PronunciationEvaluator.evaluate('Apple', '  apple ');
      expect(diff.scorePercentage, 100);
      expect(diff.isExactMatch, true);
    },
  );

  test(
    'PronunciationEvaluator evaluates minor typos with proportional score',
    () {
      final diff = PronunciationEvaluator.evaluate('scramble', 'scrambl');
      expect(diff.scorePercentage, 88); // 7/8 = 87.5% -> 88%
      expect(diff.isExactMatch, false);
    },
  );

  test('PronunciationEvaluator handles completely different words', () {
    final diff = PronunciationEvaluator.evaluate('apple', 'xyz');
    expect(diff.scorePercentage, lessThan(30));
    expect(diff.isExactMatch, false);
  });
}
