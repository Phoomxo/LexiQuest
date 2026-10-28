import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart' as feature;
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart'
    as registry;

void main() {
  test(
    'restored semantic catalog matches the current frozen 8/44 manifest',
    () {
      final manifest =
          jsonDecode(
                File(
                  'docs/design/feature-catalog-1.3.0.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final capabilities = manifest['capabilities'] as List<dynamic>;
      expect(currentFeatureContractIdentity.revision, manifest['revision']);
      expect(
        currentFeatureContractIdentity.semanticHash,
        manifest['contractHash'],
      );
      expect(allTcasIdeaIntegrationCatalog.records, hasLength(44));
      expect(
        allTcasIdeaIntegrationCatalog.records
            .map((record) => record.domain)
            .toSet(),
        hasLength(8),
      );
      expect(
        allTcasIdeaIntegrationCatalog.records.map((record) => record.id.name),
        capabilities.map((entry) => entry['id']),
      );
      expect(
        allTcasIdeaIntegrationCatalog.records.map((record) => record.name),
        capabilities.map((entry) => entry['capability']),
      );
    },
  );

  test('old registry imports expose the same feature enum identity', () {
    expect(registry.Feature.values, feature.Feature.values);
    expect(
      identical(registry.Feature.vocabulary, feature.Feature.vocabulary),
      isTrue,
    );
  });

  test(
    'new research foundation capabilities remain hidden in field defaults',
    () {
      const flags = registry.BuildFeatureRegistry.fieldDefaults();
      for (final capability in <feature.Feature>[
        feature.Feature.studyPlanning,
        feature.Feature.researchAssessment,
        feature.Feature.dailyContinuity,
        feature.Feature.offlineContent,
        feature.Feature.adventureMotivation,
      ]) {
        expect(flags.stateOf(capability), feature.FeatureState.hidden);
        expect(flags.isVisible(capability), isFalse);
      }
    },
  );

  test('hidden, disabled and emergency-off capabilities are never visible', () {
    for (final state in <feature.FeatureState>[
      feature.FeatureState.hidden,
      feature.FeatureState.disabled,
      feature.FeatureState.emergencyOff,
    ]) {
      final flags = registry.BuildFeatureRegistry({
        feature.Feature.researchAssessment: state,
      });
      expect(flags.isVisible(feature.Feature.researchAssessment), isFalse);
    }
    for (final state in <feature.FeatureState>[
      feature.FeatureState.enabled,
      feature.FeatureState.limited,
    ]) {
      final flags = registry.BuildFeatureRegistry({
        feature.Feature.researchAssessment: state,
      });
      expect(flags.isVisible(feature.Feature.researchAssessment), isTrue);
    }
  });
}
