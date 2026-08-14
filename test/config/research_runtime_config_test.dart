import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/research_runtime_config.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';

void main() {
  group('ResearchRuntimeConfig', () {
    test(
      'production environment defaults are explicit Legacy/v1 safe values',
      () {
        final config = ResearchRuntimeConfig.fromEnvironment();

        expect(config.evidenceRollout, EvidencePolicyRolloutMode.legacy);
        expect(config.answerAttemptWriteVersion, 1);
        expect(config.firestoreRulesRevision, legacyFirestoreRulesRevision);
        expect(
          config.syncPayloadRollout.writeVersionFor(SyncCollection.attempts),
          1,
        );
      },
    );

    test('parses an explicitly reviewed research combination', () {
      final config = ResearchRuntimeConfig.fromEnvironment(
        evidenceRollout: 'shadow',
        answerAttemptWriteVersion: '2',
        firestoreRulesRevision: answerAttemptV2RulesRevision,
      );

      expect(config.evidenceRollout, EvidencePolicyRolloutMode.shadow);
      expect(config.answerAttemptWriteVersion, 2);
      expect(config.firestoreRulesRevision, answerAttemptV2RulesRevision);
      expect(
        config.syncPayloadRollout.writeVersionFor(SyncCollection.attempts),
        2,
      );
    });

    test('accepts Enforced only with v2 and the reviewed rules revision', () {
      final config = ResearchRuntimeConfig.fromValues(
        evidenceRollout: 'enforced',
        answerAttemptWriteVersion: '2',
        firestoreRulesRevision: answerAttemptV2RulesRevision,
      );

      expect(config.evidenceRollout, EvidencePolicyRolloutMode.enforced);
    });

    test('rejects malformed values and every unsafe rollout combination', () {
      final invalid = <({String rollout, String version, String rules})>[
        (rollout: 'Legacy', version: '1', rules: legacyFirestoreRulesRevision),
        (rollout: 'unknown', version: '1', rules: legacyFirestoreRulesRevision),
        (rollout: 'legacy', version: '02', rules: legacyFirestoreRulesRevision),
        (rollout: 'legacy', version: '2', rules: legacyFirestoreRulesRevision),
        (rollout: 'legacy', version: '1', rules: answerAttemptV2RulesRevision),
        (rollout: 'shadow', version: '1', rules: answerAttemptV2RulesRevision),
        (rollout: 'shadow', version: '2', rules: legacyFirestoreRulesRevision),
        (
          rollout: 'enforced',
          version: '1',
          rules: answerAttemptV2RulesRevision,
        ),
        (
          rollout: 'enforced',
          version: '2',
          rules: legacyFirestoreRulesRevision,
        ),
        (rollout: 'shadow', version: '2', rules: ''),
      ];

      for (final values in invalid) {
        expect(
          () => ResearchRuntimeConfig.fromValues(
            evidenceRollout: values.rollout,
            answerAttemptWriteVersion: values.version,
            firestoreRulesRevision: values.rules,
          ),
          throwsA(isA<ResearchRuntimeConfigException>()),
          reason: values.toString(),
        );
      }
    });

    test('configuration failures do not echo supplied values', () {
      const sensitiveLookingValue = 'do-not-echo-this-value';

      try {
        ResearchRuntimeConfig.fromValues(
          evidenceRollout: sensitiveLookingValue,
          answerAttemptWriteVersion: '2',
          firestoreRulesRevision: answerAttemptV2RulesRevision,
        );
        fail('expected configuration failure');
      } on ResearchRuntimeConfigException catch (error) {
        expect(error.toString(), isNot(contains(sensitiveLookingValue)));
      }
    });
  });
}
