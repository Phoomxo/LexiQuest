import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/ari_preview_feature_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

void main() {
  test(
    'Ari preview admits planning and offline only, preserving other gates',
    () {
      const base = BuildFeatureRegistry.fieldDefaults();
      const preview = AriPreviewFeatureRegistry(base);
      for (final feature in Feature.values) {
        final expected =
            {Feature.studyPlanning, Feature.offlineContent}.contains(feature)
            ? FeatureState.enabled
            : base.stateOf(feature);
        expect(preview.stateOf(feature), expected, reason: feature.name);
      }
      expect(base.stateOf(Feature.studyPlanning), FeatureState.hidden);
      expect(base.stateOf(Feature.offlineContent), FeatureState.hidden);
      expect(preview.isEnabled(Feature.researchAssessment), false);
    },
  );
}
