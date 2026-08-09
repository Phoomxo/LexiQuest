import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

final class _DeliveryContractEntry {
  const _DeliveryContractEntry({
    required this.isVisible,
    required this.productionEntryId,
    required this.dependencyId,
  });

  final bool isVisible;
  final String productionEntryId;
  final String dependencyId;
}

void _enforceProductionFeatureContract(
  Map<Feature, _DeliveryContractEntry> deliveryContract,
) {
  expect(Feature.values.toSet(), equals(deliveryContract.keys.toSet()));
  for (final entry in deliveryContract.entries) {
    if (entry.value.isVisible) {
      expect(entry.value.productionEntryId, isNotEmpty);
      expect(entry.value.dependencyId, isNotEmpty);
    }
  }
}

List<String> _contractViolations(
  Map<Feature, _DeliveryContractEntry> deliveryContract,
) {
  final violations = <String>[];
  final expectedFeatures = Feature.values.toSet();
  final actualFeatures = deliveryContract.keys.toSet();

  for (final feature in expectedFeatures.difference(actualFeatures)) {
    violations.add('${feature.name}.missingContractEntry');
  }
  for (final feature in actualFeatures.difference(expectedFeatures)) {
    violations.add('${feature.name}.unexpectedContractEntry');
  }
  for (final feature in Feature.values) {
    final delivery = deliveryContract[feature];
    if (delivery == null || !delivery.isVisible) continue;
    if (delivery.productionEntryId.isEmpty) {
      violations.add('${feature.name}.productionEntryId');
    }
    if (delivery.dependencyId.isEmpty) {
      violations.add('${feature.name}.dependencyId');
    }
  }

  return violations;
}

void main() {
  test('baseline records every visible production delivery gap', () {
    const registry = BuildFeatureRegistry.fieldDefaults();
    final deliveryContract = <Feature, _DeliveryContractEntry>{
      Feature.vocabulary: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.vocabulary),
        productionEntryId: 'home/vocabulary',
        dependencyId: 'VocabularyUseCases',
      ),
      Feature.quiz: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.quiz),
        productionEntryId: 'home/learn/quiz',
        dependencyId: 'LearningUseCases',
      ),
      Feature.srs: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.srs),
        productionEntryId: 'home/learn/srs',
        dependencyId: 'LearningUseCases',
      ),
      Feature.reading: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.reading),
        productionEntryId: '',
        dependencyId: '',
      ),
      Feature.mastery: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.mastery),
        productionEntryId: 'home/mastery',
        dependencyId: 'ProgressUseCases',
      ),
      Feature.weakness: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.weakness),
        productionEntryId: 'home/weakness',
        dependencyId: 'ProgressUseCases',
      ),
      Feature.ghostDuel: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.ghostDuel),
        productionEntryId: 'drawer/learning/ghost-duel',
        dependencyId: 'LearningUseCases',
      ),
      Feature.achievements: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.achievements),
        productionEntryId: 'home/achievements',
        dependencyId: 'ProgressUseCases',
      ),
      Feature.shop: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.shop),
        productionEntryId: 'drawer/rewards/shop',
        dependencyId: 'RewardUseCases',
      ),
      Feature.objectScanner: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.objectScanner),
        productionEntryId: 'drawer/practice/object-scanner',
        dependencyId: 'ObjectScannerController',
      ),
      Feature.speechPractice: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.speechPractice),
        productionEntryId: 'drawer/practice/shadowing',
        dependencyId: 'SpeechPracticeUseCases',
      ),
      Feature.aiTutor: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.aiTutor),
        productionEntryId: 'drawer/ai-tutor/chat',
        dependencyId: 'AiTutorController',
      ),
      Feature.export: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.export),
        productionEntryId: 'drawer/export/center',
        dependencyId: 'ExportUseCases',
      ),
      Feature.shadowRewardV2: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.shadowRewardV2),
        productionEntryId: '',
        dependencyId: '',
      ),
      Feature.questV2: _DeliveryContractEntry(
        isVisible: registry.isVisible(Feature.questV2),
        productionEntryId: '',
        dependencyId: '',
      ),
    };

    expect(_contractViolations(deliveryContract), <String>[
      'reading.productionEntryId',
      'reading.dependencyId',
      'questV2.productionEntryId',
      'questV2.dependencyId',
    ]);

    expect(
      () => _enforceProductionFeatureContract(deliveryContract),
      throwsA(isA<TestFailure>()),
      reason:
          'Task 6 must switch this expected failure to direct enforcement '
          'after every visible feature has a truthful production path.',
    );
  });
}
