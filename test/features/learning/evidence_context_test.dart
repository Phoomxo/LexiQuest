import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';

void main() {
  group('EvidenceContext', () {
    test('serializes the exact immutable schema and round-trips it', () {
      final context = _newAssessmentContext();

      final json = context.toJson();

      expect(json, <String, Object?>{
        'schemaVersion': 1,
        'evidenceClass': 'assessment',
        'skillId': 'vocabulary.meaning',
        'hintLevel': 0,
        'policyVersion': 'learning-evidence-v1',
        'contentRevision': 'content-r1',
        'featureContractRevision': currentFeatureContractIdentity.revision,
        'featureContractHash': currentFeatureContractIdentity.semanticHash,
        'classificationSource': 'declared',
        'rolloutMode': 'shadow',
        'protocolId': 'protocol-1',
        'protocolVersion': 'protocol-v1',
        'experimentId': 'experiment-1',
        'experimentVersion': 1,
        'assignmentId': 'assignment-1',
        'cohort': 'shadow-a',
        'researchConsentVersion': 1,
        'instrumentId': 'instrument-1',
        'instrumentVersion': 'instrument-v1',
        'formId': 'form-1',
        'formVersion': 'form-v1',
        'assessmentItemId': 'item-1',
        'assessmentResponseCode': 'option-a',
        'scoringRuleVersion': 'scoring-v1',
        'engagementAllowed': true,
      });
      expect(json.keys, <String>[
        'schemaVersion',
        'evidenceClass',
        'skillId',
        'hintLevel',
        'policyVersion',
        'contentRevision',
        'featureContractRevision',
        'featureContractHash',
        'classificationSource',
        'rolloutMode',
        'protocolId',
        'protocolVersion',
        'experimentId',
        'experimentVersion',
        'assignmentId',
        'cohort',
        'researchConsentVersion',
        'instrumentId',
        'instrumentVersion',
        'formId',
        'formVersion',
        'assessmentItemId',
        'assessmentResponseCode',
        'scoringRuleVersion',
        'engagementAllowed',
      ]);
      expect(() => json['skillId'] = 'changed', throwsUnsupportedError);
      expect(EvidenceContext.fromJson(json).toJson(), json);
    });

    test('new evidence pins the current feature-contract identity', () {
      final context = _newAssessmentContext();

      expect(
        context.featureContractRevision,
        currentFeatureContractIdentity.revision,
      );
      expect(
        context.featureContractHash,
        currentFeatureContractIdentity.semanticHash,
      );
      expect(
        context.classificationSource,
        EvidenceClassificationSource.declared,
      );
    });

    test(
      'replay accepts every retained supported feature-contract identity',
      () {
        final baseline = _newAssessmentContext().toJson();

        for (final identity in supportedFeatureContractIdentities) {
          final replay = Map<String, Object?>.of(baseline)
            ..['featureContractRevision'] = identity.revision
            ..['featureContractHash'] = identity.semanticHash;

          final restored = EvidenceContext.fromJson(replay);

          expect(restored.featureContractRevision, identity.revision);
          expect(restored.featureContractHash, identity.semanticHash);
        }
      },
    );

    test('rejects missing and unknown schema keys', () {
      final baseline = _newAssessmentContext().toJson();
      final missing = Map<String, Object?>.of(baseline)..remove('rolloutMode');
      final unknown = Map<String, Object?>.of(baseline)..['extra'] = true;

      expect(() => EvidenceContext.fromJson(missing), throwsFormatException);
      expect(() => EvidenceContext.fromJson(unknown), throwsFormatException);
    });

    test('rejects unknown schema and policy versions without a fallback', () {
      final baseline = _newAssessmentContext().toJson();
      final wrongSchema = Map<String, Object?>.of(baseline)
        ..['schemaVersion'] = 2;
      final wrongPolicy = Map<String, Object?>.of(baseline)
        ..['policyVersion'] = 'learning-evidence-v2';

      expect(
        () => EvidenceContext.fromJson(wrongSchema),
        throwsFormatException,
      );
      expect(
        () => EvidenceContext.fromJson(wrongPolicy),
        throwsFormatException,
      );
    });

    test('rejects invalid serialized enum names', () {
      final baseline = _newAssessmentContext().toJson();

      for (final entry in <String, String>{
        'evidenceClass': 'unknown',
        'classificationSource': 'inferred',
        'rolloutMode': 'enabled',
      }.entries) {
        final invalid = Map<String, Object?>.of(baseline)
          ..[entry.key] = entry.value;

        expect(
          () => EvidenceContext.fromJson(invalid),
          throwsFormatException,
          reason: entry.key,
        );
      }
    });

    test('requires exact JSON value types and explicit booleans', () {
      final baseline = _newAssessmentContext().toJson();

      for (final entry in <String, Object?>{
        'hintLevel': '0',
        'experimentVersion': 1.0,
        'researchConsentVersion': true,
        'engagementAllowed': 1,
      }.entries) {
        final invalid = Map<String, Object?>.of(baseline)
          ..[entry.key] = entry.value;

        expect(
          () => EvidenceContext.fromJson(invalid),
          throwsFormatException,
          reason: entry.key,
        );
      }
    });

    test(
      'requires nonnegative hint levels and bounded canonical identifiers',
      () {
        final baseline = _newAssessmentContext().toJson();
        final negativeHint = Map<String, Object?>.of(baseline)
          ..['hintLevel'] = -1;
        final blankSkill = Map<String, Object?>.of(baseline)
          ..['skillId'] = '  ';
        final paddedRevision = Map<String, Object?>.of(baseline)
          ..['contentRevision'] = ' content-r1 ';
        final oversizedId = Map<String, Object?>.of(baseline)
          ..['assignmentId'] = 'x' * (EvidenceContext.maxIdentifierLength + 1);

        expect(
          () => EvidenceContext.fromJson(negativeHint),
          throwsFormatException,
        );
        expect(
          () => EvidenceContext.fromJson(blankSkill),
          throwsFormatException,
        );
        expect(
          () => EvidenceContext.fromJson(paddedRevision),
          throwsFormatException,
        );
        expect(
          () => EvidenceContext.fromJson(oversizedId),
          throwsFormatException,
        );
      },
    );

    test('requires a supported lowercase SHA-256 contract identity', () {
      final baseline = _newAssessmentContext().toJson();
      final uppercase = Map<String, Object?>.of(baseline)
        ..['featureContractHash'] = currentFeatureContractIdentity.semanticHash
            .toUpperCase();
      final unsupported = Map<String, Object?>.of(baseline)
        ..['featureContractRevision'] = '999.0.0'
        ..['featureContractHash'] = '1' * 64;

      expect(() => EvidenceContext.fromJson(uppercase), throwsFormatException);
      expect(
        () => EvidenceContext.fromJson(unsupported),
        throwsFormatException,
      );
    });

    test(
      'requires complete positive research metadata in shadow and enforced',
      () {
        final baseline = _newAssessmentContext().toJson();

        for (final rolloutMode in <String>['shadow', 'enforced']) {
          for (final field in <String>[
            'protocolId',
            'protocolVersion',
            'experimentId',
            'experimentVersion',
            'assignmentId',
            'cohort',
            'researchConsentVersion',
          ]) {
            final invalid = Map<String, Object?>.of(baseline)
              ..['rolloutMode'] = rolloutMode
              ..[field] = null;

            expect(
              () => EvidenceContext.fromJson(invalid),
              throwsFormatException,
              reason: '$rolloutMode $field',
            );
          }
        }

        final zeroExperiment = Map<String, Object?>.of(baseline)
          ..['experimentVersion'] = 0;
        final zeroConsent = Map<String, Object?>.of(baseline)
          ..['researchConsentVersion'] = 0;
        expect(
          () => EvidenceContext.fromJson(zeroExperiment),
          throwsFormatException,
        );
        expect(
          () => EvidenceContext.fromJson(zeroConsent),
          throwsFormatException,
        );
      },
    );

    test(
      'requires every bounded assessment field and a controlled response code',
      () {
        final baseline = _newAssessmentContext().toJson();
        const requiredFields = <String>[
          'instrumentId',
          'instrumentVersion',
          'formId',
          'formVersion',
          'assessmentItemId',
          'assessmentResponseCode',
          'scoringRuleVersion',
        ];

        for (final field in requiredFields) {
          final missing = Map<String, Object?>.of(baseline)..[field] = null;
          final oversized = Map<String, Object?>.of(baseline)
            ..[field] = 'a' * (EvidenceContext.maxIdentifierLength + 1);
          expect(
            () => EvidenceContext.fromJson(missing),
            throwsFormatException,
            reason: 'missing $field',
          );
          expect(
            () => EvidenceContext.fromJson(oversized),
            throwsFormatException,
            reason: 'oversized $field',
          );
        }

        final freeText = Map<String, Object?>.of(baseline)
          ..['assessmentResponseCode'] = 'Option A is my answer';
        expect(() => EvidenceContext.fromJson(freeText), throwsFormatException);
      },
    );

    test('allows non-assessment contexts to omit assessment metadata', () {
      final json = _newAssessmentContext(
        evidenceClass: EvidenceClass.recognition,
      ).toJson();
      final withoutAssessmentMetadata = Map<String, Object?>.of(json)
        ..['instrumentId'] = null
        ..['instrumentVersion'] = null
        ..['formId'] = null
        ..['formVersion'] = null
        ..['assessmentItemId'] = null
        ..['assessmentResponseCode'] = null
        ..['scoringRuleVersion'] = null;

      expect(
        EvidenceContext.fromJson(withoutAssessmentMetadata).evidenceClass,
        EvidenceClass.recognition,
      );
    });

    test(
      'rejects an uncontrolled response code on non-assessment evidence',
      () {
        final invalid = Map<String, Object?>.of(
          _newAssessmentContext(
            evidenceClass: EvidenceClass.recognition,
          ).toJson(),
        )..['assessmentResponseCode'] = 'unbounded free text';

        expect(() => EvidenceContext.fromJson(invalid), throwsFormatException);
      },
    );

    test('accepts only the frozen legacy-inferred compatibility identity', () {
      final legacy = _legacyContext.toJson();

      expect(EvidenceContext.fromJson(legacy).toJson(), legacy);

      final wrongMode = Map<String, Object?>.of(legacy)
        ..['rolloutMode'] = 'shadow';
      final wrongRevision = Map<String, Object?>.of(legacy)
        ..['featureContractRevision'] = currentFeatureContractIdentity.revision
        ..['featureContractHash'] = currentFeatureContractIdentity.semanticHash;
      final wrongPolicy = Map<String, Object?>.of(legacy)
        ..['policyVersion'] = 'learning-evidence-v1';
      expect(() => EvidenceContext.fromJson(wrongMode), throwsFormatException);
      expect(
        () => EvidenceContext.fromJson(wrongRevision),
        throwsFormatException,
      );
      expect(
        () => EvidenceContext.fromJson(wrongPolicy),
        throwsFormatException,
      );
    });

    test('declared evidence cannot select the legacy policy', () {
      final invalid = Map<String, Object?>.of(_newAssessmentContext().toJson())
        ..['policyVersion'] = 'legacy-v1';

      expect(() => EvidenceContext.fromJson(invalid), throwsFormatException);
    });

    test('toJson fails closed for an invalid directly constructed value', () {
      final valid = _newAssessmentContext();
      final invalid = EvidenceContext(
        evidenceClass: valid.evidenceClass,
        skillId: valid.skillId,
        hintLevel: valid.hintLevel,
        policyVersion: valid.policyVersion,
        contentRevision: valid.contentRevision,
        featureContractRevision: 'unsupported',
        featureContractHash: 'f' * 64,
        classificationSource: valid.classificationSource,
        rolloutMode: valid.rolloutMode,
        protocolId: valid.protocolId,
        protocolVersion: valid.protocolVersion,
        experimentId: valid.experimentId,
        experimentVersion: valid.experimentVersion,
        assignmentId: valid.assignmentId,
        cohort: valid.cohort,
        researchConsentVersion: valid.researchConsentVersion,
        instrumentId: valid.instrumentId,
        instrumentVersion: valid.instrumentVersion,
        formId: valid.formId,
        formVersion: valid.formVersion,
        assessmentItemId: valid.assessmentItemId,
        assessmentResponseCode: valid.assessmentResponseCode,
        scoringRuleVersion: valid.scoringRuleVersion,
        engagementAllowed: valid.engagementAllowed,
      );

      expect(invalid.toJson, throwsFormatException);
    });
  });
}

EvidenceContext _newAssessmentContext({
  EvidenceClass evidenceClass = EvidenceClass.assessment,
}) => EvidenceContext.forNewEvidence(
  evidenceClass: evidenceClass,
  skillId: 'vocabulary.meaning',
  hintLevel: 0,
  contentRevision: 'content-r1',
  rolloutMode: EvidencePolicyRolloutMode.shadow,
  protocolId: 'protocol-1',
  protocolVersion: 'protocol-v1',
  experimentId: 'experiment-1',
  experimentVersion: 1,
  assignmentId: 'assignment-1',
  cohort: 'shadow-a',
  researchConsentVersion: 1,
  instrumentId: 'instrument-1',
  instrumentVersion: 'instrument-v1',
  formId: 'form-1',
  formVersion: 'form-v1',
  assessmentItemId: 'item-1',
  assessmentResponseCode: 'option-a',
  scoringRuleVersion: 'scoring-v1',
  engagementAllowed: true,
);

const EvidenceContext _legacyContext = EvidenceContext(
  evidenceClass: EvidenceClass.independentRecall,
  skillId: 'legacy.practice',
  hintLevel: 0,
  policyVersion: 'legacy-v1',
  contentRevision: 'legacy-content',
  featureContractRevision: EvidenceContext.legacyFeatureContractRevision,
  featureContractHash: EvidenceContext.legacyFeatureContractHash,
  classificationSource: EvidenceClassificationSource.legacyInferred,
  rolloutMode: EvidencePolicyRolloutMode.legacy,
  engagementAllowed: false,
);
