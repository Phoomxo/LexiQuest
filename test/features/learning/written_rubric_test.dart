import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/written_rubric.dart';

void main() {
  const rubric = WrittenRubric();
  test(
    'alternate valid book responses retain separate dimensions and spans',
    () {
      for (final text in ['I read a book.', 'She reads a book.']) {
        final result = rubric.assess('book', text);
        expect(result.status, RubricStatus.assessed);
        expect(result.scores, [2, 2, 2]);
        expect(
          result.spans.any((s) => text.substring(s.start, s.end) == 'book'),
          isTrue,
        );
        expect(result.toJson().containsKey('isCorrect'), isFalse);
      }
    },
  );
  test('meaning use and form errors are not a binary aggregate', () {
    expect(rubric.assess('book', 'She reads book.').scores, [2, 2, 1]);
    expect(rubric.assess('book', 'She read a book every day.').scores, [
      2,
      2,
      2,
    ]);
    expect(rubric.assess('book', 'I drink a book.').scores, [0, 0, 2]);
    expect(rubric.assess('book', 'I book a room.').scores, [0, 0, 2]);
    expect(rubric.assess('book', 'I have a book.').scores, [2, 0, 2]);
  });
  test('unknown valid answer is uncertain, never automatically wrong', () {
    final result = rubric.assess('book', 'My aunt borrowed a book yesterday.');
    expect(result.status, RubricStatus.uncertain);
    expect(result.scores, isNull);
    expect(rubric.assess('book', '').status, RubricStatus.unassessable);
    expect(
      rubric.assess('unknown', 'I read a book.').status,
      RubricStatus.unassessable,
    );
  });
  test('case and punctuation affect form; extra negation is not stripped', () {
    expect(rubric.assess('book', 'i read a book').scores, [2, 2, 1]);
    expect(
      rubric.assess('book', 'I do not read a book.').status,
      RubricStatus.uncertain,
    );
  });
  test(
    'strict codec rejects invented confidence, dimensions and bad spans',
    () {
      final result = rubric.assess('book', 'I read a book.');
      expect(
        WrittenRubricResult.fromJson(result.toJson()).toJson(),
        result.toJson(),
      );
      expect(
        () => WrittenRubricResult.fromJson({
          ...result.toJson(),
          'scores': [9, 2, 2],
        }),
        throwsFormatException,
      );
      expect(
        () => WrittenRubricResult.fromJson({
          ...result.toJson(),
          'status': 'uncertain',
        }),
        throwsFormatException,
      );
    },
  );
}
