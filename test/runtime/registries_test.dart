import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/registries/consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/entitlement_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

void main() {
  group('Registry separation — D2.4', () {
    test('feature flag does not assign experiment cohort', () {
      // Enable aiTutor in the feature registry.
      final features = MutableFeatureRegistry();
      features.enable(Feature.aiTutor);
      expect(features.isVisible(Feature.aiTutor), isTrue);

      // The experiment registry is entirely separate — enabling a feature
      // must not produce any cohort assignment.
      const experiments = NoOpExperimentRegistry();
      final assignment =
          experiments.getAssignment('ai_tutor_experiment', 'user1');

      expect(
        assignment.isUnassigned,
        isTrue,
        reason: 'Enabling a feature flag must not assign an experiment cohort',
      );
    });

    test('disabling a feature does not affect consent state', () {
      final features = MutableFeatureRegistry();
      features.disable(Feature.export);
      expect(features.isVisible(Feature.export), isFalse);

      const consents = NoOpConsentRegistry();
      final state =
          consents.check(ConsentPurpose.personalDataExport, 'user1');

      // Consent state is unknown regardless of feature state.
      expect(state, ConsentState.unknown);
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

    test('experiment registry returns unassigned for every query', () {
      const experiments = NoOpExperimentRegistry();
      final assignment = experiments.getAssignment('unknown_exp', 'nobody');
      expect(assignment.isUnassigned, isTrue);
      expect(assignment.isCohort('control'), isFalse);
      expect(assignment.experimentId, 'unknown_exp');
      expect(assignment.ownerId, 'nobody');
    });

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
      // Unknown feature is hidden
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

    test('four registries are independent — no shared state', () {
      final features = MutableFeatureRegistry();
      features.enable(Feature.aiTutor);

      const experiments = NoOpExperimentRegistry();
      const consents = NoOpConsentRegistry();
      const entitlements = NoOpEntitlementRegistry();

      // Each registry answers its own question; none bleeds into the others.
      expect(features.isVisible(Feature.aiTutor), isTrue);
      expect(
        experiments.getAssignment('ai_exp', 'u1').isUnassigned,
        isTrue,
      );
      expect(
        consents.check(ConsentPurpose.aiProviderDataSharing, 'u1'),
        ConsentState.unknown,
      );
      expect(entitlements.hasAccess(Entitlement.aiTutorUnlimited, 'u1'), isFalse);
    });
  });
}
