import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/vocabulary_mixer.dart';

void main() {
  const mixer = VersionedVocabularyMixer();

  test('mixes due, weak, and at most two new words deterministically', () {
    const request = VocabularyMixRequest(
      dueWords: ['due-a', 'due-b', 'shared'],
      weakWords: ['weak-a', 'weak-b', 'shared'],
      newWords: ['new-a', 'new-b', 'new-c'],
      targetCount: 6,
      seed: 42,
    );

    final first = mixer.mix(request);
    final replay = mixer.mix(request);

    expect(first.algorithmVersion, 'mixer-v1');
    expect(first.words, replay.words);
    expect(first.words.toSet(), hasLength(first.words.length));
    expect(first.words, hasLength(6));
    expect(
      first.words.where(request.newWords.contains).length,
      lessThanOrEqualTo(2),
    );
  });

  test('returns all available unique words when the pool is undersized', () {
    final result = mixer.mix(
      const VocabularyMixRequest(
        dueWords: ['one'],
        weakWords: ['one', 'two'],
        newWords: [],
        targetCount: 6,
        seed: 1,
      ),
    );

    expect(result.words.toSet(), {'one', 'two'});
  });
}
