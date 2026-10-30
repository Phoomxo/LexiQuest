import 'package:characters/characters.dart';

List<String> createStableScramble(String word) {
  final letters = word.characters.toList();
  if (letters.length < 2) return letters;
  var shift =
      word.runes.fold<int>(0, (sum, rune) => sum + rune) % letters.length;
  if (shift == 0) shift = 1;
  final result = <String>[...letters.skip(shift), ...letters.take(shift)];
  if (result.join() == word) {
    final different = result.indexWhere((letter) => letter != result.first);
    if (different > 0) {
      final first = result.first;
      result[0] = result[different];
      result[different] = first;
    }
  }
  return result;
}
