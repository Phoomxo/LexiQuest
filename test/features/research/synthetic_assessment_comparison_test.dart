import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/synthetic_assessment_comparison.dart';

void main() {
  final before = DateTime.utc(2026, 10, 24, 9);
  final after = DateTime.utc(2026, 10, 24, 10);

  SyntheticAssessmentComparison? compare({
    SyntheticAssessmentPins? afterPins,
    DateTime? afterTime,
    Map<String, String> afterResponses = const {'station-id': 'สถานี'},
  }) => SyntheticAssessmentComparison.match(
    expected: _pins(),
    items: const [(id: 'station-id', word: 'station', answerKey: 'สถานี')],
    before: (
      pins: _pins(),
      submittedAtUtc: before,
      responses: const {'station-id': 'ชานชาลา'},
    ),
    after: (
      pins: afterPins ?? _pins(),
      submittedAtUtc: afterTime ?? after,
      responses: afterResponses,
    ),
  );

  test('built-in paired scores come from the same two item responses', () {
    final sample = SyntheticAssessmentComparison.example;
    expect(sample.answers.map((answer) => answer.item.word), [
      'station',
      'platform',
    ]);
    expect(sample.beforeCorrect, 1);
    expect(sample.afterCorrect, 2);
    expect(sample.answers.last.before, 'สถานี');
    expect(sample.answers.last.after, 'ชานชาลา');
  });

  test('matching pins and ordered responses give one comparable item', () {
    final result = compare()!;
    expect(result.beforeCorrect, 0);
    expect(result.afterCorrect, 1);
    expect(result.answers.single.item.id, 'station-id');
  });

  test('rejects changed owner and assignment or assessment pins', () {
    for (final pins in [
      _pins(ownerId: 'synthetic-b'),
      _pins(cycleId: 'cycle-b'),
      _pins(assignmentRevision: 2),
      _pins(protocolRevision: 2),
      _pins(instrumentRevision: 2),
      _pins(formRevision: 2),
    ]) {
      expect(compare(afterPins: pins), isNull, reason: pins.toString());
    }
  });

  test('rejects misordered rounds and incomplete or mismatched items', () {
    expect(compare(afterTime: before), isNull);
    expect(
      compare(afterTime: before.subtract(const Duration(seconds: 1))),
      isNull,
    );
    expect(compare(afterTime: after.toLocal()), isNull);
    expect(compare(afterResponses: const {}), isNull);
    expect(compare(afterResponses: const {'other-id': 'สถานี'}), isNull);
    expect(compare(afterResponses: const {'station-id': ' '}), isNull);
  });
}

SyntheticAssessmentPins _pins({
  String ownerId = 'synthetic-a',
  String cycleId = 'cycle-a',
  int assignmentRevision = 1,
  int protocolRevision = 1,
  int instrumentRevision = 1,
  int formRevision = 1,
}) => (
  ownerId: ownerId,
  cycleId: cycleId,
  assignmentId: 'assignment-a',
  assignmentRevision: assignmentRevision,
  protocolId: 'protocol-a',
  protocolRevision: protocolRevision,
  instrumentId: 'instrument-a',
  instrumentRevision: instrumentRevision,
  formId: 'form-a',
  formRevision: formRevision,
);
