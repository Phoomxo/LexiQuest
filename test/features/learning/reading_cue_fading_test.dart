import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/reading_cue_fading.dart';

void main() {
  const id =
      'associative-reading:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  String fade(String passage, List<String> words, {String? documentId = id}) =>
      cueFadedReadingPassage(
        passage: passage,
        targetWords: words,
        documentId: documentId,
      );

  test('generated inline cues fade with punctuation and regex characters', () {
    expect(
      fade('a+b means รวม. Mr. means นาย. e.g. ตัวอย่าง.', ['a+b', 'Mr.']),
      'a+b. Mr..',
    );
    expect(
      fade('bag means กระเป๋า. book means หนังสือ.', ['bag', 'book']),
      'bag. book.',
    );
  });

  test(
    'ordinary text, other document identities and partial matches stay exact',
    () {
      const ordinary = 'She carries a bag. He reads a book.';
      expect(fade(ordinary, ['bag', 'book']), ordinary);
      const glossary = 'bag means กระเป๋า. book means หนังสือ.';
      expect(
        fade(glossary, ['bag', 'book'], documentId: 'article:1'),
        glossary,
      );
      expect(fade(glossary, ['bag', 'book'], documentId: null), glossary);
      expect(fade(glossary, ['bag', 'chair']), glossary);
      expect(fade(glossary, []), glossary);
      expect(fade(glossary, ['']), glossary);
      expect(fade('Intro. $glossary', ['bag', 'book']), 'Intro. $glossary');
      expect(fade('$glossary\n', ['bag', 'book']), '$glossary\n');
    },
  );
}
