import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/production_feature_contract.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

const _persistedFeatureNamesBeforeAdventure = <String>[
  'vocabulary',
  'quiz',
  'srs',
  'reading',
  'mastery',
  'weakness',
  'ghostDuel',
  'achievements',
  'shop',
  'objectScanner',
  'speechPractice',
  'aiTutor',
  'export',
  'shadowRewardV2',
  'questV2',
  'studyPlanning',
  'researchAssessment',
  'dailyContinuity',
  'offlineContent',
];

void main() {
  test(
    'Adventure appends one stable runtime identity without renaming history',
    () {
      expect(Feature.values.map((feature) => feature.name), <String>[
        ..._persistedFeatureNamesBeforeAdventure,
        'adventureMotivation',
      ]);
    },
  );

  test('Adventure is a hidden durable delivery parent by default', () {
    const defaults = BuildFeatureRegistry.fieldDefaults();
    final delivery = productionFeatureContract[Feature.adventureMotivation];

    expect(defaults.configuredFeatures.toSet(), Feature.values.toSet());
    expect(defaults.stateOf(Feature.adventureMotivation), FeatureState.hidden);
    expect(defaults.isVisible(Feature.adventureMotivation), isFalse);
    expect(defaults.isEnabled(Feature.adventureMotivation), isFalse);
    expect(delivery, isNotNull);
    expect(delivery!.productionEntryId, 'home/learn/today-experience');
    expect(
      delivery.dependencyId,
      'AdventureEntryUseCases+AdventureJourneyReader+TodayHubUseCases',
    );
    expect(delivery.durable, isTrue);
    expect(delivery.screenClassName, 'TodayExperienceHost');
  });

  test('Adventure is not a forty-fifth 8/44 product capability', () {
    expect(FeatureContractId.values, hasLength(44));
    expect(FeatureContractId.values.last.name, 'f44');
    expect(
      productContractIdsByRuntimeFeature[Feature.adventureMotivation],
      isEmpty,
    );
  });
}
