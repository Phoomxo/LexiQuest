import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';

void main() {
  for (final (mode, evidenceClass, skill) in const [
    ('meaningChoice', EvidenceClass.recognition, 'meaning-recall'),
    ('srsRecall', EvidenceClass.independentRecall, 'srs-recall'),
    (
      'associativeRecall',
      EvidenceClass.independentRecall,
      'associative-recall',
    ),
    ('ghostSpelling', EvidenceClass.recreational, 'ghost-duel'),
    ('shadowing', EvidenceClass.pronunciation, 'shadowing-pronunciation'),
    (
      'pronunciationTranscript',
      EvidenceClass.pronunciation,
      'pronunciation-transcript',
    ),
  ]) {
    test('$mode captures its actual ordinary activity with a content pin', () {
      final context = captureCurrentActivityEvidence(
        promptMode: mode,
        contentRevision: 'local-vocabulary-v1:7',
      );

      expect(context.evidenceClass, evidenceClass);
      expect(context.skillId, skill);
      expect(context.contentRevision, 'local-vocabulary-v1:7');
      expect(context.hintLevel, 0);
      expect(
        context.classificationSource,
        EvidenceClassificationSource.declared,
      );
      expect(context.rolloutMode, EvidencePolicyRolloutMode.legacy);
      expect(context.protocolId, isNull);
      expect(context.assignmentId, isNull);
      expect(context.researchConsentVersion, isNull);
      expect(LearningEvidenceContract.isOrdinaryEvidence(context), isTrue);
    });
  }

  test('hints and reveal retain the guided activity declaration', () {
    for (final level in [1, 2]) {
      final context = captureCurrentActivityEvidence(
        promptMode: 'meaningChoice',
        contentRevision: 'local-vocabulary-v1:7',
        hintLevel: level,
      );
      expect(context.evidenceClass, EvidenceClass.guidedPractice);
      expect(context.hintLevel, level);
      expect(context.contentRevision, 'local-vocabulary-v1:7');
    }
  });

  test('uncaptured content and legacy modes use the exact frozen sentinel', () {
    final frozen = LearningEvidenceContract.frozenV13LegacyEvidenceContext();
    for (final context in [
      captureCurrentActivityEvidence(promptMode: 'meaningChoice'),
      captureCurrentActivityEvidence(
        promptMode: 'legacy-custom-mode',
        contentRevision: 'local-vocabulary-v1:7',
      ),
    ]) {
      expect(context.toJson(), frozen.toJson());
      expect(
        context.classificationSource,
        EvidenceClassificationSource.legacyInferred,
      );
    }
  });
}
