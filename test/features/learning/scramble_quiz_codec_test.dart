import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/quiz_round.dart';

const _ticket = QuizWord(
  id: 'ticket',
  categoryId: 'travel',
  spelling: 'ticket',
  meaning: 'ตั๋ว',
  partOfSpeech: 'noun',
  localRevision: 2,
);

QuizQuestion _spelling() => QuizQuestion.scramble(
  word: _ticket,
  kind: QuizPromptKind.wordScramble,
  prompt: _ticket.meaning,
  tokens: ['e', 't', 'i', 't', 'c', 'k'],
  correctAnswer: 'ticket',
  sourcePin: 'synthetic-word@2',
);

QuizQuestion _sentence() => QuizQuestion.scramble(
  word: _ticket,
  kind: QuizPromptKind.sentenceScramble,
  prompt: 'ตั๋วหนึ่งใบสำหรับฉัน และตั๋วหนึ่งใบสำหรับคุณ',
  tokens: ['ticket', 'you.', 'a', 'for', 'me,', 'a', 'and', 'ticket', 'for'],
  correctAnswer: 'a ticket for me, and a ticket for you.',
  sourcePin: 'synthetic-authored-example@1',
);

QuizPlan _plan(QuizQuestion question) => QuizPlan(
  origin: QuizOrigin(
    route: 'word-games',
    promptKind: question.kind,
    categoryId: _ticket.categoryId,
    wordIds: [_ticket.id],
  ),
  questions: [question],
  categoryName: 'Travel',
  returnLabel: 'เลือกเกมอื่น',
);

void main() {
  test('word order uses each tile once and scores either duplicate t', () {
    final question = _spelling();
    final firstT = QuizOrderResponse(slot: 0, indexes: [1, 2, 4, 5, 0, 3]);
    final otherT = QuizOrderResponse(slot: 0, indexes: [3, 2, 4, 5, 0, 1]);
    final wrong = QuizOrderResponse(slot: 0, indexes: [1, 2, 5, 4, 0, 3]);

    expect(firstT.answerFor(question), 'ticket');
    expect(firstT.isCorrectFor(question), isTrue);
    expect(otherT.isCorrectFor(question), isTrue);
    expect(wrong.answerFor(question), 'tikcet');
    expect(wrong.isCorrectFor(question), isFalse);
    expect(firstT, isNot(otherT));
  });

  test(
    'sentence plan preserves authored text, repeated tokens and revision',
    () {
      final wordPlan = _plan(_spelling());
      final plan = _plan(_sentence());
      for (final original in [wordPlan, plan]) {
        final raw = encodeQuizPlan(original);
        final decoded = decodeQuizPlan(raw);
        final question = decoded.questions.single;
        expect(jsonDecode(raw)['v'], 4);
        expect(encodeQuizPlan(decoded), raw);
        expect(decoded.origin, original.origin);
        expect(question.word.localRevision, 2);
        expect(question.options, isEmpty);
        expect(
          question.scrambleTokens,
          original.questions.single.scrambleTokens,
        );
        expect(question.sourcePin, original.questions.single.sourcePin);
        expect(question.correctAnswer, original.questions.single.correctAnswer);
      }

      final indexes = [2, 0, 3, 4, 6, 5, 7, 8, 1];
      final response = QuizOrderResponse(slot: 0, indexes: indexes);
      indexes.clear();
      final raw = encodeQuizResponse(response, plan: plan);
      expect(raw, '{"v":3,"slot":0,"indexes":[2,0,3,4,6,5,7,8,1]}');
      final decoded = decodeQuizResponse(raw, plan: plan);
      expect(decoded, response);
      expect(decoded.hashCode, response.hashCode);
      expect(
        decoded.answerFor(plan.questions.single),
        plan.questions.single.correctAnswer,
      );
      expect(decoded.isCorrectFor(plan.questions.single), isTrue);
    },
  );

  test(
    'partial, repeated or out-of-range indexes and other formats refuse',
    () {
      final plan = _plan(_spelling());
      for (final raw in [
        '{"v":3,"slot":0,"indexes":[1,2]}',
        '{"v":3,"slot":0,"indexes":[1,2,4,5,0,1]}',
        '{"v":3,"slot":0,"indexes":[1,2,4,5,0,6]}',
        '{"v":3,"slot":0,"indexes":[1,2,4,5,0,-1]}',
        '{"v":3,"slot":0,"indexes":[1,2,4,5,0,3.0]}',
        '{"v":3,"slot":0,"indexes":[1,2,4,5,0,3],"extra":true}',
        '{"v":3,"slot":1,"indexes":[1,2,4,5,0,3]}',
        '{"v":1,"slot":0,"selectedOption":null}',
        '{"v":2,"slot":0,"text":"ticket"}',
      ]) {
        expect(
          () => decodeQuizResponse(raw, plan: plan),
          throwsFormatException,
          reason: raw,
        );
      }
      expect(
        () => QuizOrderResponse(slot: 0, indexes: [0, 1]).answerFor(
          const QuizQuestion(word: _ticket, options: ['ตั๋ว', 'ชานชาลา']),
        ),
        throwsFormatException,
      );
    },
  );

  test('incompatible plan versions and altered scramble tokens refuse', () {
    final original =
        jsonDecode(encodeQuizPlan(_plan(_spelling()))) as Map<String, dynamic>;
    for (final version in [1, 2, 3, 5]) {
      expect(
        () => decodeQuizPlan(jsonEncode({...original, 'v': version})),
        throwsFormatException,
      );
    }
    expect(
      () => QuizQuestion.scramble(
        word: _ticket,
        kind: QuizPromptKind.wordScramble,
        prompt: _ticket.meaning,
        tokens: ['et', 'tic', 'k'],
        correctAnswer: _ticket.spelling,
        sourcePin: 'synthetic-word@2',
      ),
      throwsFormatException,
    );
    expect(
      () => QuizQuestion.scramble(
        word: _ticket,
        kind: QuizPromptKind.sentenceScramble,
        prompt: 'ฉันมีตั๋วหนึ่งใบ',
        tokens: ['I', 'have', 'a', 'ticket.'],
        correctAnswer: 'I have a ticket.',
        sourcePin: '',
      ),
      throwsFormatException,
    );
  });
}
