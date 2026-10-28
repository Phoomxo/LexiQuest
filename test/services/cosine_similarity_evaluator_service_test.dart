import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/cosine_similarity_evaluator_service.dart';

void main() {
  test('evaluateSimilarity evaluates identical sentences as 1.0 score', () {
    final result = CosineSimilarityEvaluatorService.evaluateSimilarity(
      studentSentence: 'The dog chases the cat in the garden',
      modelSentence: 'The dog chases the cat in the garden',
    );

    expect(result.similarityScore, 1.0);
    expect(result.isSemanticallyEquivalent, isTrue);
  });

  test(
    'evaluateSimilarity evaluates semantically overlapping sentence above threshold',
    () {
      final result = CosineSimilarityEvaluatorService.evaluateSimilarity(
        studentSentence: 'The dog chases cat in garden',
        modelSentence: 'The dog chases the cat in the garden',
      );

      expect(result.similarityScore > 0.70, isTrue);
      expect(result.isSemanticallyEquivalent, isTrue);
    },
  );

  test('evaluateSimilarity rejects completely different sentences', () {
    final result = CosineSimilarityEvaluatorService.evaluateSimilarity(
      studentSentence: 'Bananas are yellow fruits',
      modelSentence: 'Computers build complex software algorithms',
    );

    expect(result.similarityScore, 0.0);
    expect(result.isSemanticallyEquivalent, isFalse);
  });
}
