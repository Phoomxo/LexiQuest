import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart'
    as research;
import 'package:vocab_learning_app/runtime/registries/consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/entitlement_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

void main() {
  group('Registry separation — D2.4', () {
    test('feature flag does not assign experiment cohort', () async {
      // Enable aiTutor in the feature registry.
      final features = MutableFeatureRegistry();
      features.enable(Feature.aiTutor);
      expect(features.isVisible(Feature.aiTutor), isTrue);

      // The experiment registry is entirely separate — enabling a feature
      // must not produce any cohort assignment.
      const experiments = NoOpExperimentRegistry();
      final research.ExperimentAssignment? assignment = await experiments
          .getAssignment(
            ownerId: 'user1',
            experimentId: 'ai_tutor_experiment',
            experimentVersion: 1,
          );

      expect(
        assignment,
        isNull,
        reason: 'Enabling a feature flag must not assign an experiment cohort',
      );
    });

    test('disabling a feature does not affect consent state', () async {
      final features = MutableFeatureRegistry();
      features.disable(Feature.export);
      expect(features.isVisible(Feature.export), isFalse);

      const consents = NoOpConsentRegistry();
      final snapshot = await consents.snapshot(
        purpose: ConsentPurpose.personalDataExport,
        ownerId: 'user1',
        consentVersion: 1,
      );

      // Consent state is unknown regardless of feature state.
      expect(snapshot.state, ConsentState.unknown);
    });

    test('entitlement registry denies all by default', () {
      const entitlements = NoOpEntitlementRegistry();
      for (final e in Entitlement.values) {
        expect(
          entitlements.hasAccess(e, 'owner-1'),
          isFalse,
          reason: 'NoOpEntitlementRegistry must deny $e',
        );
      }
    });

    test(
      'experiment registry re-exports the canonical nullable type',
      () async {
        const experiments = NoOpExperimentRegistry();
        final ExperimentAssignment? reExported = await experiments
            .getAssignment(
              ownerId: 'nobody',
              experimentId: 'unknown_exp',
              experimentVersion: 7,
            );
        final research.ExperimentAssignment? canonical = reExported;

        expect(canonical, isNull);
      },
    );

    test('BuildFeatureRegistry.fieldDefaults matches production defaults', () {
      const reg = BuildFeatureRegistry.fieldDefaults();
      // Tier-1 features always enabled
      expect(reg.stateOf(Feature.vocabulary), FeatureState.enabled);
      expect(reg.stateOf(Feature.quiz), FeatureState.enabled);
      expect(reg.stateOf(Feature.srs), FeatureState.enabled);
      // Sensor/AI features start limited
      expect(reg.stateOf(Feature.aiTutor), FeatureState.limited);
      expect(reg.stateOf(Feature.objectScanner), FeatureState.limited);
      expect(reg.stateOf(Feature.speechPractice), FeatureState.limited);
      // Broad 8/44 delivery parents are implemented-off until composed.
      expect(reg.stateOf(Feature.studyPlanning), FeatureState.hidden);
      expect(reg.stateOf(Feature.researchAssessment), FeatureState.hidden);
      expect(reg.stateOf(Feature.dailyContinuity), FeatureState.hidden);
      expect(reg.stateOf(Feature.offlineContent), FeatureState.hidden);
      expect(reg.isVisible(Feature.aiTutor), isTrue); // limited is visible
    });

    test('BuildFeatureRegistry.allEnabled makes every feature visible', () {
      const reg = BuildFeatureRegistry.allEnabled();
      for (final feature in Feature.values) {
        expect(
          reg.isVisible(feature),
          isTrue,
          reason: '$feature should be visible in allEnabled registry',
        );
      }
    });

    test('four registries are independent — no shared state', () async {
      final features = MutableFeatureRegistry();
      features.enable(Feature.aiTutor);

      const experiments = NoOpExperimentRegistry();
      const consents = NoOpConsentRegistry();
      const entitlements = NoOpEntitlementRegistry();

      // Each registry answers its own question; none bleeds into the others.
      expect(features.isVisible(Feature.aiTutor), isTrue);
      expect(
        await experiments.getAssignment(
          ownerId: 'u1',
          experimentId: 'ai_exp',
          experimentVersion: 1,
        ),
        isNull,
      );
      expect(
        (await consents.snapshot(
          purpose: ConsentPurpose.aiProviderDataSharing,
          ownerId: 'u1',
          consentVersion: 1,
        )).state,
        ConsentState.unknown,
      );
      expect(
        entitlements.hasAccess(Entitlement.aiTutorUnlimited, 'u1'),
        isFalse,
      );
    });
  });
}
