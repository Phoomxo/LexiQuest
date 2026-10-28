import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/first_answer_accuracy.dart';

void main() {
  test(
    'first identity preserves six items with global ordinals and owner/revision boundaries',
    () {
      final context = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'meaning',
        hintLevel: 0,
        contentRevision: 'old-1',
        engagementAllowed: false,
      );
      final rows =
          <({String owner, String word, String revision, bool correct})>[
            for (var i = 0; i < 6; i++)
              (owner: 'A', word: 'word-$i', revision: 'old-1', correct: i < 5),
            (owner: 'A', word: 'word-5', revision: 'old-1', correct: true),
            (owner: 'B', word: 'word-5', revision: 'old-1', correct: true),
            (owner: 'A', word: 'word-5', revision: 'new-2', correct: true),
          ];
      final selected = FirstAnswerAccuracy.select(
        rows,
        contextOf: (_) => context,
        identityOf: (row, _) => (row.owner, 'session', row.word, row.revision),
      );
      expect(selected, hasLength(8));
      final original = selected.where(
        (row) => row.owner == 'A' && row.revision == 'old-1',
      );
      expect(original, hasLength(6));
      expect(original.where((row) => row.correct), hasLength(5));
      expect(rows, hasLength(9));
    },
  );

  for (final evidenceClass in EvidenceClass.values.where(
    (value) => value != EvidenceClass.assessment,
  )) {
    test('${evidenceClass.name} first/repair/support classification', () {
      EvidenceContext context(int hint) => EvidenceContext.legacyCompatibility(
        evidenceClass: evidenceClass,
        skillId: 'meaning',
        hintLevel: hint,
        contentRevision: 'historic-1',
        engagementAllowed: false,
      );
      final eligible = {
        EvidenceClass.independentRecall,
        EvidenceClass.recognition,
        EvidenceClass.pronunciation,
      }.contains(evidenceClass);
      expect(FirstAnswerAccuracy.includes(context(0)), eligible);
      expect(FirstAnswerAccuracy.includes(context(1)), isFalse);
    });
  }
}
