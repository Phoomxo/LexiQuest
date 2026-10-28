import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';

void main() {
  test('stable scramble is deterministic and preserves every character', () {
    final first = createStableScramble('learning');
    final second = createStableScramble('learning');

    expect(first, second);
    expect(first.join(), isNot('learning'));
    expect(first.toList()..sort(), 'learning'.split('')..sort());
  });

  test('stable scramble handles one-character and repeated words', () {
    expect(createStableScramble('a'), ['a']);
    expect(createStableScramble('aaa'), ['a', 'a', 'a']);
  });
}
