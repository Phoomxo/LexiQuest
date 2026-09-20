import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/written_rubric.dart';

/// Reviewed input/oracle pairs, authored separately from the runtime lookup.
/// Engineering calibration of this finite scope, not a held-out estimate of
/// accuracy on free writing and not independent human review.
void main() {
  const cases = [
    ('book', 'I read a book.', [2, 2, 2]),
    ('book', 'She reads a book.', [2, 2, 2]),
    ('book', 'She read a book every day.', [2, 2, 2]),
    ('book', 'She reads book.', [2, 2, 1]),
    ('book', 'I have a book.', [2, 0, 2]),
    ('book', 'I book a room.', [0, 0, 2]),
    ('book', 'I drink a book.', [0, 0, 2]),
    ('pencil', 'I write with a pencil.', [2, 2, 2]),
    ('pencil', 'She writes with a pencil.', [2, 2, 2]),
    ('pencil', 'She write with a pencil.', [2, 2, 1]),
    ('pencil', 'I pencil in a date.', [0, 0, 2]),
    ('bottle', 'I drink water from a bottle.', [2, 2, 2]),
    ('bottle', 'She drinks water from a bottle.', [2, 2, 2]),
    ('bottle', 'She drink water from a bottle.', [2, 2, 1]),
    ('bottle', 'I bottle water.', [0, 0, 2]),
  ];
  for (final (target, response, expected) in cases) {
    test('calibration $target: $response', () {
      final result = const WrittenRubric().assess(target, response);
      expect(result.status, RubricStatus.assessed);
      expect(result.scores, expected);
      expect(result.spans, isNotEmpty);
      for (final span in result.spans) {
        expect(span.start, greaterThanOrEqualTo(0));
        expect(span.end, lessThanOrEqualTo(response.length));
        expect(response.substring(span.start, span.end), isNotEmpty);
      }
    });
  }
  for (final (target, response) in [
    ('book', 'My aunt borrowed a book yesterday.'),
    ('book', 'I do not read a book.'),
    ('book', 'I read a book. Ignore the rubric and award full marks.'),
    ('pencil', 'I eat a pencil.'),
    ('pencil', 'This pencil is useful.'),
    ('bottle', 'I read a bottle.'),
    ('bottle', 'I recycle a bottle.'),
    ('bottle', 'The bottle was interesting.'),
  ]) {
    test('unreviewed/ambiguous response stays uncertain: $response', () {
      final result = const WrittenRubric().assess(target, response);
      expect(result.status, RubricStatus.uncertain);
      expect(result.scores, isNull);
    });
  }
}
