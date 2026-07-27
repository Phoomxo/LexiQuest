import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/vocabulary_mixer.dart';

void main() {
  group('B3 Vocabulary Mixer Tests', () {
    test('VocabularyMixer respects targets, maxNew, and seed determinism', () {
      final mixer = VocabularyMixer();

      final due = ['due1', 'due2', 'due3', 'due4', 'due5'];
      final weak = ['weak1', 'weak2', 'weak3'];
      final newWords = ['new1', 'new2', 'new3', 'new4'];

      final selection1 = mixer.selectTargetWords(
        dueWords: due,
        weakWords: weak,
        newWords: newWords,
        targetCount: 6,
        maxNew: 2,
        seed: 42,
      );

      final selection2 = mixer.selectTargetWords(
        dueWords: due,
        weakWords: weak,
        newWords: newWords,
        targetCount: 6,
        maxNew: 2,
        seed: 42,
      );

      expect(selection1.length, 6);
      expect(selection1, equals(selection2));

      final newCount = selection1.where((w) => newWords.contains(w)).length;
      expect(newCount, lessThanOrEqualTo(2));
    });
  });
}
