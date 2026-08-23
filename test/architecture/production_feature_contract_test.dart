import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/production_feature_contract.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

void main() {
  test('production delivery contract is the exact frozen 19-row contract', () {
    expect(productionFeatureContract.keys.toSet(), Feature.values.toSet());
    expect(productionFeatureContract, hasLength(19));

    const expected =
        <
          Feature,
          ({String productionEntryId, String dependencyId, bool durable})
        >{
          Feature.vocabulary: (
            productionEntryId: 'home/vocabulary',
            dependencyId: 'VocabularyUseCases',
            durable: true,
          ),
          Feature.quiz: (
            productionEntryId: 'home/learn/quiz',
            dependencyId: 'LearningUseCases',
            durable: true,
          ),
          Feature.srs: (
            productionEntryId: 'home/learn/srs',
            dependencyId: 'LearningUseCases',
            durable: true,
          ),
          Feature.reading: (
            productionEntryId: 'home/learn/associative-reading',
            dependencyId:
                'VocabularyUseCases+LearningUseCases+AssociativeLearningPort',
            durable: true,
          ),
          Feature.mastery: (
            productionEntryId: 'home/mastery',
            dependencyId: 'ProgressUseCases',
            durable: true,
          ),
          Feature.weakness: (
            productionEntryId: 'home/weakness',
            dependencyId: 'ProgressUseCases',
            durable: true,
          ),
          Feature.ghostDuel: (
            productionEntryId: 'drawer/learning/ghost-duel',
            dependencyId: 'LearningUseCases',
            durable: true,
          ),
          Feature.achievements: (
            productionEntryId: 'home/achievements',
            dependencyId: 'ProgressUseCases',
            durable: true,
          ),
          Feature.shop: (
            productionEntryId: 'drawer/rewards/shop',
            dependencyId: 'RewardUseCases',
            durable: true,
          ),
          Feature.objectScanner: (
            productionEntryId: 'drawer/practice/object-scanner',
            dependencyId: 'ObjectScannerController',
            durable: true,
          ),
          Feature.speechPractice: (
            productionEntryId: 'drawer/practice/shadowing',
            dependencyId: 'SpeechPracticeUseCases',
            durable: true,
          ),
          Feature.aiTutor: (
            productionEntryId: 'drawer/ai-tutor/chat',
            dependencyId: 'AiTutorController',
            durable: true,
          ),
          Feature.export: (
            productionEntryId: 'drawer/export/center',
            dependencyId: 'ExportUseCases',
            durable: true,
          ),
          Feature.shadowRewardV2: (
            productionEntryId: '',
            dependencyId: '',
            durable: false,
          ),
          Feature.questV2: (
            productionEntryId: 'drawer/rewards/quests',
            dependencyId: 'QuestUseCases',
            durable: true,
          ),
          Feature.studyPlanning: (
            productionEntryId: 'home/study-planning',
            dependencyId: 'StudyPlanningUseCases',
            durable: true,
          ),
          Feature.researchAssessment: (
            productionEntryId: 'research/assessment',
            dependencyId: 'AssessmentUseCases',
            durable: true,
          ),
          Feature.dailyContinuity: (
            productionEntryId: 'home/today',
            dependencyId: 'TodayHubUseCases',
            durable: true,
          ),
          Feature.offlineContent: (
            productionEntryId: 'settings/offline-content',
            dependencyId: 'OfflineContentManager',
            durable: true,
          ),
        };

    for (final entry in expected.entries) {
      final delivery = productionFeatureContract[entry.key];
      expect(delivery, isNotNull, reason: entry.key.name);
      expect(delivery!.feature, entry.key);
      expect(delivery.productionEntryId, entry.value.productionEntryId);
      expect(delivery.dependencyId, entry.value.dependencyId);
      expect(delivery.durable, entry.value.durable);
    }
  });

  test('field defaults explicitly enumerate every feature and fail closed', () {
    const registry = BuildFeatureRegistry.fieldDefaults();

    expect(registry.configuredFeatures.toSet(), Feature.values.toSet());
    expect(registry.stateOf(Feature.shadowRewardV2), FeatureState.hidden);
    expect(registry.stateOf(Feature.questV2), FeatureState.limited);
    expect(registry.stateOf(Feature.studyPlanning), FeatureState.hidden);
    expect(registry.stateOf(Feature.researchAssessment), FeatureState.hidden);
    expect(registry.stateOf(Feature.dailyContinuity), FeatureState.hidden);
    expect(registry.stateOf(Feature.offlineContent), FeatureState.hidden);

    for (final delivery in productionFeatureContract.values) {
      final state = registry.stateOf(delivery.feature);
      if (state == FeatureState.enabled || state == FeatureState.limited) {
        expect(delivery.productionEntryId, isNotEmpty);
        expect(delivery.dependencyId, isNotEmpty);
      }
    }
  });
}
