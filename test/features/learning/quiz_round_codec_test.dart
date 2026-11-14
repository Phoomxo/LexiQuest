import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/quiz_round.dart';

void main() {
  test(
    'plan freezes exact question order, lexical pins and source feedback',
    () {
      final meaningOptions = ['สถานี', 'ชานชาลา'];
      final plan = QuizPlan(
        origin: QuizOrigin(
          route: 'category',
          promptKind: QuizPromptKind.meaningChoice,
        ),
        questions: [
          QuizQuestion(word: _platform, options: meaningOptions),
          const QuizQuestion(word: _station, options: ['ชานชาลา', 'สถานี']),
        ],
        categoryName: 'การเดินทาง',
        returnLabel: 'กลับไปที่ชุดคำ',
      );
      meaningOptions[0] = 'เปลี่ยนคำ';

      final stored = encodeQuizPlan(plan);
      final loaded = decodeQuizPlan(stored);
      expect(encodeQuizPlan(loaded), stored);
      expect(loaded.origin, plan.origin);
      expect(loaded.categoryName, 'การเดินทาง');
      expect(loaded.returnLabel, 'กลับไปที่ชุดคำ');
      expect(loaded.questions.map((q) => q.word.id), ['platform', 'station']);
      expect(loaded.questions.first.options, ['สถานี', 'ชานชาลา']);
      expect(loaded.questions.first.word.localRevision, 7);
      expect(loaded.questions.first.correctAnswer, 'ชานชาลา');

      final source = decodeQuizPlan(encodeQuizPlan(_definitionPlan()));
      final question = source.questions.single;
      expect(question.promptText, 'Where passengers wait for a train.');
      expect(question.options, ['station', 'platform']);
      expect(question.correctAnswer, 'platform');
      expect(question.sourcePin, 'synthetic-source@4');
      expect(question.optionWords!['station']!.localRevision, 2);
      expect(question.optionExplanations!['station'], 'อาคารสถานี');
    },
  );

  test(
    'origin compares route, parent and ordered selection separately from display',
    () {
      QuizOrigin origin(List<String> ids, {String? parent = 'result-a'}) =>
          QuizOrigin(
            route: 'history-repair',
            promptKind: QuizPromptKind.spellingChoice,
            categoryId: 'travel',
            wordIds: ids,
            parentId: parent,
          );
      final selectedIds = ['one', 'two'];
      final original = origin(selectedIds);
      selectedIds.clear();
      expect(original, origin(['one', 'two']));
      expect(original.hashCode, origin(['one', 'two']).hashCode);
      expect(original, isNot(origin(['two', 'one'])));
      expect(original, isNot(origin(['one', 'two'], parent: 'result-b')));
    },
  );

  test(
    'cursor and response distinguish awaiting, selection, reveal and finish',
    () {
      final plan = _definitionPlan();
      const feedback = (
        revision: 1,
        slot: 0,
        phase: QuizPhase.feedback,
        lastAttemptId: 'attempt-1',
        activeResponseMs: 50,
      );
      for (final cursor in <QuizCursor>[
        initialQuizCursor,
        feedback,
        (
          revision: 2,
          slot: 0,
          phase: QuizPhase.finished,
          lastAttemptId: 'attempt-1',
          activeResponseMs: 50,
        ),
      ]) {
        expect(
          decodeQuizCursor(encodeQuizCursor(cursor, plan: plan), plan: plan),
          cursor,
        );
      }
      for (final response in <QuizResponse>[
        (slot: 0, selectedOption: 0),
        (slot: 0, selectedOption: null),
      ]) {
        expect(
          decodeQuizResponse(
            encodeQuizResponse(response, plan: plan),
            plan: plan,
          ),
          response,
        );
      }
    },
  );

  test('untrusted persisted data cannot invent a plan, cursor or answer', () {
    final plan = _definitionPlan();
    final stored = jsonDecode(encodeQuizPlan(plan)) as Map<String, dynamic>;
    expect(
      () => decodeQuizPlan(jsonEncode({...stored, 'v': 2})),
      throwsFormatException,
    );
    final questions = stored['questions'] as List<dynamic>;
    final question = questions.single as Map<String, dynamic>;
    expect(
      () => decodeQuizPlan(
        jsonEncode({
          ...stored,
          'questions': [
            {...question, 'correctOption': 0},
          ],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => decodeQuizPlan(
        jsonEncode({
          ...stored,
          'questions': [
            {
              ...question,
              'options': ['platform', 'platform'],
            },
          ],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => decodeQuizCursor(
        '{"v":1,"revision":1,"slot":0,"phase":"feedback",'
        '"lastAttemptId":null,"activeResponseMs":50}',
        plan: plan,
      ),
      throwsFormatException,
    );
    for (final raw in [
      '{"v":1,"slot":1,"selectedOption":0}',
      '{"v":1,"slot":0,"selectedOption":2}',
      '{"v":1,"slot":0}',
      '{"v":1,"slot":0,"selectedOption":0,"rawText":"anything"}',
    ]) {
      expect(() => decodeQuizResponse(raw, plan: plan), throwsFormatException);
    }
  });
}

const _platform = QuizWord(
  id: 'platform',
  categoryId: 'travel',
  spelling: 'platform',
  meaning: 'ชานชาลา',
  partOfSpeech: 'noun',
  localRevision: 7,
);
const _station = QuizWord(
  id: 'station',
  categoryId: 'travel',
  spelling: 'station',
  meaning: 'สถานี',
  partOfSpeech: 'noun',
  localRevision: 2,
);

QuizPlan _definitionPlan() => QuizPlan(
  origin: QuizOrigin(
    route: 'source',
    promptKind: QuizPromptKind.definitionChoice,
    categoryId: 'travel',
    wordIds: ['platform'],
    parentId: 'source-4',
  ),
  questions: [
    QuizQuestion.definitionChoice(
      word: _platform,
      options: ['station', 'platform'],
      definition: 'Where passengers wait for a train.',
      optionWords: {'station': _station, 'platform': _platform},
      optionExplanations: {'station': 'อาคารสถานี', 'platform': 'บริเวณรอรถไฟ'},
      sourcePin: 'synthetic-source@4',
    ),
  ],
);
