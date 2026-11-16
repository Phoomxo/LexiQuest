import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/cloze_prompt_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

void main() {
  test('choice binds the authored gap and distractor to the same set', () {
    final question = ClozePromptPolicy.build(
      words: [_station, _ticket, _platform],
      kind: QuizPromptKind.clozeChoice,
      targetWordIds: {_platform.id},
    ).single;

    expect(question.word, same(_platform));
    expect(question.kind, QuizPromptKind.clozeChoice);
    expect(question.promptText, 'The train is at ____ two.');
    expect(question.clozeTranslation, 'รถไฟจอดอยู่ที่ชานชาลาสอง');
    expect(question.options, ['platform', 'ticket']);
    expect(question.correctAnswer, 'platform');
    expect(question.acceptedAnswers, unorderedEquals(['platform']));
    expect(
      question.sourcePin,
      '21b34eaa:docs/design/2026-11-13-design-reset/learn_frames.py:157-171',
    );
  });

  test(
    'typed cloze accepts the two authored forms without showing choices',
    () {
      final question = ClozePromptPolicy.build(
        words: [_platform, _ticket],
        kind: QuizPromptKind.clozeTyped,
        targetWordIds: {_platform.id},
      ).single;

      expect(question.word, same(_platform));
      expect(question.kind, QuizPromptKind.clozeTyped);
      expect(question.promptText, 'The train is at ____ two.');
      expect(question.options, isEmpty);
      expect(question.correctAnswer, 'platform');
      expect(
        question.acceptedAnswers,
        unorderedEquals(['platform', 'platform number']),
      );
    },
  );

  test(
    'unsupported targets, duplicate senses and mismatched sets are empty',
    () {
      const stage = QuizWord(
        id: 'stage',
        categoryId: 'travel',
        spelling: 'platform',
        meaning: 'เวที',
        partOfSpeech: 'noun',
      );
      const verbTicket = QuizWord(
        id: 'verb-ticket',
        categoryId: 'travel',
        spelling: 'ticket',
        meaning: 'ตั๋ว',
        partOfSpeech: 'verb',
      );
      const issuedTicket = QuizWord(
        id: 'other-ticket',
        categoryId: 'other-set',
        spelling: 'ticket',
        meaning: 'ตั๋ว',
        partOfSpeech: 'noun',
      );
      const ambiguousTranslation = QuizWord(
        id: 'stop',
        categoryId: 'travel',
        spelling: 'stop',
        meaning: 'ชานชาลา',
        partOfSpeech: 'noun',
      );
      const duplicateId = QuizWord(
        id: 'platform',
        categoryId: 'other-set',
        spelling: 'stair',
        meaning: 'บันได',
        partOfSpeech: 'noun',
      );

      for (final kind in [
        QuizPromptKind.clozeChoice,
        QuizPromptKind.clozeTyped,
      ]) {
        for (final words in [
          [_platform, issuedTicket],
          [_platform, verbTicket],
          [stage, _ticket],
          [_platform, stage, _ticket],
          [_platform, ambiguousTranslation, _ticket],
          [_platform, duplicateId, _ticket],
        ]) {
          expect(ClozePromptPolicy.build(words: words, kind: kind), isEmpty);
        }
        expect(
          ClozePromptPolicy.build(
            words: [_platform, _ticket, _station],
            kind: kind,
            targetWordIds: {_station.id},
          ),
          isEmpty,
        );
      }
    },
  );
}

const _platform = QuizWord(
  id: 'platform',
  categoryId: 'travel',
  spelling: 'platform',
  meaning: 'ชานชาลา',
  partOfSpeech: 'noun',
  localRevision: 2,
);

const _ticket = QuizWord(
  id: 'ticket',
  categoryId: 'travel',
  spelling: 'ticket',
  meaning: 'ตั๋ว',
  partOfSpeech: 'noun',
);

const _station = QuizWord(
  id: 'station',
  categoryId: 'travel',
  spelling: 'station',
  meaning: 'สถานี',
  partOfSpeech: 'noun',
);
