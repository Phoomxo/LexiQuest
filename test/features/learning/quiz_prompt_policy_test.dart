import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/quiz_prompt_policy.dart';

const platform = QuizWord(
  id: 'p',
  categoryId: 'travel',
  spelling: 'platform',
  meaning: 'ชานชาลา',
  partOfSpeech: 'noun',
);
const ticket = QuizWord(
  id: 't',
  categoryId: 'travel',
  spelling: 'ticket',
  meaning: 'ตั๋ว',
  partOfSpeech: 'noun',
);

List<QuizQuestion> build(
  List<QuizWord> words,
  QuizPromptKind kind, {
  int limit = 10,
}) => QuizPromptPolicy.build(words: words, kind: kind, limit: limit);

void main() {
  test('legacy const meaning question and empty SRS options remain valid', () {
    const question = QuizQuestion(word: platform, options: []);
    expect(question.kind, QuizPromptKind.meaningChoice);
    expect(question.promptText, 'platform');
    expect(question.correctAnswer, 'ชานชาลา');
    expect(question.options, isEmpty);
  });

  test(
    'reverse uses meaning prompt and spelling answer with immutable provenance',
    () {
      final questions = build([
        platform,
        ticket,
      ], QuizPromptKind.spellingChoice);
      final q = questions.singleWhere((q) => q.word.id == 'p');
      expect(q.kind, QuizPromptKind.spellingChoice);
      expect(q.promptText, 'ชานชาลา');
      expect(q.correctAnswer, 'platform');
      expect(q.options.toSet(), {'platform', 'ticket'});
      expect(q.optionWords!['ticket']!.id, 't');
      expect(() => q.optionWords!['x'] = platform, throwsUnsupportedError);
    },
  );

  test(
    'pinned definition uses English source and exact local word identities',
    () {
      final q = build([
        platform,
        ticket,
      ], QuizPromptKind.definitionChoice).single;
      expect(q.kind, QuizPromptKind.definitionChoice);
      expect(
        q.promptText,
        'The place at a train station where you wait to get on a train.',
      );
      expect(q.correctAnswer, 'platform');
      expect(q.word.id, 'p');
      expect(q.options.toSet(), {'platform', 'ticket'});
      expect(q.optionWords!['ticket']!.id, 't');
      expect(
        q.optionExplanations!['platform'],
        'บริเวณที่ผู้โดยสารยืนรอขึ้นรถไฟ',
      );
      expect(q.optionExplanations!['ticket'], 'หลักฐานที่ใช้โดยสาร');
      expect(q.sourcePin, contains('21b34eaa'));
    },
  );

  test('ambiguous spelling or meaning is excluded from reverse questions', () {
    const duplicateMeaning = QuizWord(
      id: 'x',
      categoryId: 'travel',
      spelling: 'stage',
      meaning: 'ชานชาลา',
      partOfSpeech: 'noun',
    );
    const duplicateSpelling = QuizWord(
      id: 'y',
      categoryId: 'travel',
      spelling: 'platform',
      meaning: 'เวที',
      partOfSpeech: 'noun',
    );
    expect(
      build([
        platform,
        ticket,
        duplicateMeaning,
      ], QuizPromptKind.spellingChoice).where((q) => q.word.id == 'p'),
      isEmpty,
    );
    expect(
      build([
        platform,
        ticket,
        duplicateSpelling,
      ], QuizPromptKind.spellingChoice).where((q) => q.word.id == 'p'),
      isEmpty,
    );
  });

  test(
    'definition rejects missing, duplicate, cross-category, wrong sense or POS',
    () {
      const otherCategory = QuizWord(
        id: 't',
        categoryId: 'other',
        spelling: 'ticket',
        meaning: 'ตั๋ว',
        partOfSpeech: 'noun',
      );
      const wrongSense = QuizWord(
        id: 'p',
        categoryId: 'travel',
        spelling: 'platform',
        meaning: 'เวที',
        partOfSpeech: 'noun',
      );
      const wrongPos = QuizWord(
        id: 'p',
        categoryId: 'travel',
        spelling: 'platform',
        meaning: 'ชานชาลา',
        partOfSpeech: 'verb',
      );
      const duplicate = QuizWord(
        id: 'p2',
        categoryId: 'travel',
        spelling: 'platform',
        meaning: 'ชานชาลา',
        partOfSpeech: 'noun',
      );
      for (final words in [
        [platform],
        [platform, otherCategory],
        [wrongSense, ticket],
        [wrongPos, ticket],
        [platform, ticket, duplicate],
      ]) {
        expect(build(words, QuizPromptKind.definitionChoice), isEmpty);
      }
    },
  );

  test('definition eligibility is evaluated before limiting target count', () {
    const unrelated = QuizWord(
      id: 'z',
      categoryId: 'travel',
      spelling: 'station',
      meaning: 'สถานี',
      partOfSpeech: 'noun',
    );
    final questions = build(
      [unrelated, ticket, platform],
      QuizPromptKind.definitionChoice,
      limit: 1,
    );
    expect(questions.single.word.id, 'p');
  });
}
