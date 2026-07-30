import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';

void main() {
  group('BuildFieldFeatureRegistry', () {
    test('field defaults expose only the local vocabulary foundation', () {
      const registry = BuildFieldFeatureRegistry.fieldDefaults();

      expect(
        registry.stateOf(FieldFeature.vocabulary),
        FieldFeatureState.enabled,
      );
      expect(registry.stateOf(FieldFeature.quiz), FieldFeatureState.hidden);
      expect(registry.stateOf(FieldFeature.reading), FieldFeatureState.hidden);
      expect(registry.stateOf(FieldFeature.srs), FieldFeatureState.hidden);
      expect(registry.stateOf(FieldFeature.shop), FieldFeatureState.hidden);
      expect(
        registry.stateOf(FieldFeature.objectScanner),
        FieldFeatureState.hidden,
      );
      expect(registry.stateOf(FieldFeature.aiTutor), FieldFeatureState.hidden);
    });

    test('isVisible excludes hidden features and admits limited features', () {
      const registry = BuildFieldFeatureRegistry({
        FieldFeature.shop: FieldFeatureState.hidden,
        FieldFeature.objectScanner: FieldFeatureState.limited,
        FieldFeature.vocabulary: FieldFeatureState.enabled,
      });

      expect(registry.isVisible(FieldFeature.shop), isFalse);
      expect(registry.isVisible(FieldFeature.objectScanner), isTrue);
      expect(registry.isVisible(FieldFeature.vocabulary), isTrue);
    });

    test('missing feature entries fail closed', () {
      const registry = BuildFieldFeatureRegistry({});

      expect(registry.stateOf(FieldFeature.export), FieldFeatureState.hidden);
      expect(registry.isVisible(FieldFeature.export), isFalse);
    });

    test(
      'all-enabled registry is available only for legacy test composition',
      () {
        const registry = BuildFieldFeatureRegistry.allEnabled();

        for (final feature in FieldFeature.values) {
          expect(registry.stateOf(feature), FieldFeatureState.enabled);
        }
      },
    );
  });
}
