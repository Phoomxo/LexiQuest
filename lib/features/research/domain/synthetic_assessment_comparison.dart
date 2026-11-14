typedef SyntheticAssessmentPins = ({
  String ownerId,
  String cycleId,
  String assignmentId,
  int assignmentRevision,
  String protocolId,
  int protocolRevision,
  String instrumentId,
  int instrumentRevision,
  String formId,
  int formRevision,
});

typedef SyntheticAssessmentItem = ({String id, String word, String answerKey});

typedef SyntheticAssessmentRound = ({
  SyntheticAssessmentPins pins,
  DateTime submittedAtUtc,
  Map<String, String> responses,
});

typedef ComparedAssessmentAnswer = ({
  SyntheticAssessmentItem item,
  String before,
  String after,
});

final class SyntheticAssessmentComparison {
  const SyntheticAssessmentComparison._(this.pins, this.answers);

  final SyntheticAssessmentPins pins;
  final List<ComparedAssessmentAnswer> answers;

  int get beforeCorrect =>
      answers.where((answer) => answer.before == answer.item.answerKey).length;
  int get afterCorrect =>
      answers.where((answer) => answer.after == answer.item.answerKey).length;

  static SyntheticAssessmentComparison? match({
    required SyntheticAssessmentPins expected,
    required List<SyntheticAssessmentItem> items,
    required SyntheticAssessmentRound before,
    required SyntheticAssessmentRound after,
  }) {
    if (before.pins != expected ||
        after.pins != expected ||
        !before.submittedAtUtc.isUtc ||
        !after.submittedAtUtc.isUtc ||
        !before.submittedAtUtc.isBefore(after.submittedAtUtc) ||
        items.isEmpty ||
        items.map((item) => item.id).toSet().length != items.length ||
        before.responses.length != items.length ||
        after.responses.length != items.length) {
      return null;
    }

    final answers = <ComparedAssessmentAnswer>[];
    for (final item in items) {
      final first = before.responses[item.id];
      final second = after.responses[item.id];
      if (first == null ||
          first.trim().isEmpty ||
          second == null ||
          second.trim().isEmpty) {
        return null;
      }
      answers.add((item: item, before: first, after: second));
    }
    return SyntheticAssessmentComparison._(
      expected,
      List.unmodifiable(answers),
    );
  }

  static const _examplePins = (
    ownerId: 'synthetic-learner-01',
    cycleId: 'synthetic-cycle-01',
    assignmentId: 'synthetic-paired-travel',
    assignmentRevision: 1,
    protocolId: 'synthetic-word-pair',
    protocolRevision: 1,
    instrumentId: 'synthetic-meaning-recall',
    instrumentRevision: 1,
    formId: 'synthetic-travel',
    formRevision: 1,
  );

  static final example = match(
    expected: _examplePins,
    items: const [
      (id: 'travel-station', word: 'station', answerKey: 'สถานี'),
      (id: 'travel-platform', word: 'platform', answerKey: 'ชานชาลา'),
    ],
    before: (
      pins: _examplePins,
      submittedAtUtc: DateTime.utc(2026, 10, 24, 9),
      responses: const {'travel-station': 'สถานี', 'travel-platform': 'สถานี'},
    ),
    after: (
      pins: _examplePins,
      submittedAtUtc: DateTime.utc(2026, 10, 24, 10),
      responses: const {
        'travel-station': 'สถานี',
        'travel-platform': 'ชานชาลา',
      },
    ),
  )!;
}
