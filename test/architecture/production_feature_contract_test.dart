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

void main() {
  test('visible features declare a production entry and dependency', () {
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

    expect(Feature.values.toSet(), equals(deliveryContract.keys.toSet()));
    for (final entry in deliveryContract.entries) {
      if (entry.value.isVisible) {
        expect(
          entry.value.productionEntryId,
          isNotEmpty,
          reason: '${entry.key.name} has no declared production entry',
        );
        expect(
          entry.value.dependencyId,
          isNotEmpty,
          reason: '${entry.key.name} has no declared composed dependency',
        );
      }
    }
  });
}
