import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';

void main() {
  final ordinary = EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.recognition,
    skillId: 'meaning-recall',
    hintLevel: 0,
    contentRevision: 'local-vocabulary-v1:7',
    rolloutMode: EvidencePolicyRolloutMode.legacy,
    engagementAllowed: true,
  );

  bool accepts(String json, {String evidenceClass = 'recognition'}) =>
      LearningEvidenceContract.validEvidenceMetadata(
        evidenceClass: evidenceClass,
        evidenceContextJson: json,
      );

  test(
    'ordinary metadata accepts key reordering but rejects class mismatch',
    () {
      final values = ordinary.toJson();
      final reordered = {
        for (final key in values.keys.toList().reversed) key: values[key],
      };
      expect(accepts(jsonEncode(values)), isTrue);
      expect(accepts(jsonEncode(reordered)), isTrue);
      expect(
        accepts(jsonEncode(values), evidenceClass: 'independentRecall'),
        isFalse,
      );
    },
  );

  test('legacy metadata keeps the exact archived sentinel', () {
    final context = LearningEvidenceContract.frozenV13LegacyEvidenceContext();
    expect(
      jsonEncode(context.toJson()),
      LearningEvidenceContract.frozenV13LegacyEvidenceContextJson,
    );
    expect(
      accepts(jsonEncode(context.toJson()), evidenceClass: 'independentRecall'),
      isTrue,
    );
    expect(
      context.classificationSource,
      EvidenceClassificationSource.legacyInferred,
    );
    expect(context.assignmentId, isNull);
  });

  test(
    'legacy-inferred metadata cannot invent a different historical context',
    () {
      final changed = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'invented-legacy-skill',
        hintLevel: 0,
        contentRevision: 'legacy-unknown',
        engagementAllowed: true,
      );
      expect(LearningEvidenceContract.isOrdinaryEvidence(changed), isFalse);
      expect(
        accepts(
          jsonEncode(changed.toJson()),
          evidenceClass: 'independentRecall',
        ),
        isFalse,
      );
    },
  );

  test(
    'ordinary ingress rejects malformed, unknown and oversized metadata',
    () {
      for (final json in [
        '{',
        '[]',
        'null',
        '"unstructured"',
        jsonEncode({...ordinary.toJson(), 'extra': 1}),
      ]) {
        expect(accepts(json), isFalse);
      }
      final valid = jsonEncode(ordinary.toJson());
      expect(accepts(valid.padRight(16384)), isTrue);
      expect(accepts(valid.padRight(16385)), isFalse);
      expect(
        accepts(
          jsonEncode({...ordinary.toJson(), 'policyVersion': 'unknown-policy'}),
        ),
        isFalse,
      );
    },
  );
}
