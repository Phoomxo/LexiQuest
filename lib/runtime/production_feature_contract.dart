import 'registries/feature.dart';

final class ProductionFeatureDelivery {
  const ProductionFeatureDelivery({
    required this.feature,
    required this.productionEntryId,
    required this.dependencyId,
    required this.durable,
    this.screenClassName = '',
  });

  final Feature feature;
  final String productionEntryId;
  final String dependencyId;
  final bool durable;
  final String screenClassName;
}

const productionFeatureContract = <Feature, ProductionFeatureDelivery>{
  Feature.vocabulary: ProductionFeatureDelivery(
    feature: Feature.vocabulary,
    productionEntryId: 'home/vocabulary',
    dependencyId: 'VocabularyUseCases',
    durable: true,
  ),
  Feature.quiz: ProductionFeatureDelivery(
    feature: Feature.quiz,
    productionEntryId: 'home/learn/quiz',
    dependencyId: 'LearningUseCases',
    durable: true,
  ),
  Feature.srs: ProductionFeatureDelivery(
    feature: Feature.srs,
    productionEntryId: 'home/learn/srs',
    dependencyId: 'LearningUseCases',
    durable: true,
  ),
  Feature.reading: ProductionFeatureDelivery(
    feature: Feature.reading,
    productionEntryId: 'home/learn/associative-reading',
    dependencyId: 'VocabularyUseCases+LearningUseCases+AssociativeLearningPort',
    durable: true,
  ),
  Feature.mastery: ProductionFeatureDelivery(
    feature: Feature.mastery,
    productionEntryId: 'home/mastery',
    dependencyId: 'ProgressUseCases',
    durable: true,
  ),
  Feature.weakness: ProductionFeatureDelivery(
    feature: Feature.weakness,
    productionEntryId: 'home/weakness',
    dependencyId: 'ProgressUseCases',
    durable: true,
  ),
  Feature.ghostDuel: ProductionFeatureDelivery(
    feature: Feature.ghostDuel,
    productionEntryId: 'drawer/learning/ghost-duel',
    dependencyId: 'LearningUseCases',
    durable: true,
  ),
  Feature.achievements: ProductionFeatureDelivery(
    feature: Feature.achievements,
    productionEntryId: 'home/achievements',
    dependencyId: 'ProgressUseCases',
    durable: true,
  ),
  Feature.shop: ProductionFeatureDelivery(
    feature: Feature.shop,
    productionEntryId: 'drawer/rewards/shop',
    dependencyId: 'RewardUseCases',
    durable: true,
  ),
  Feature.objectScanner: ProductionFeatureDelivery(
    feature: Feature.objectScanner,
    productionEntryId: 'drawer/practice/object-scanner',
    dependencyId: 'ObjectScannerController',
    durable: true,
  ),
  Feature.speechPractice: ProductionFeatureDelivery(
    feature: Feature.speechPractice,
    productionEntryId: 'drawer/practice/shadowing',
    dependencyId: 'SpeechPracticeUseCases',
    durable: true,
  ),
  Feature.aiTutor: ProductionFeatureDelivery(
    feature: Feature.aiTutor,
    productionEntryId: 'drawer/ai-tutor/chat',
    dependencyId: 'AiTutorController',
    durable: true,
  ),
  Feature.export: ProductionFeatureDelivery(
    feature: Feature.export,
    productionEntryId: 'drawer/export/center',
    dependencyId: 'ExportUseCases',
    durable: true,
  ),
  Feature.shadowRewardV2: ProductionFeatureDelivery(
    feature: Feature.shadowRewardV2,
    productionEntryId: '',
    dependencyId: '',
    durable: false,
  ),
  Feature.questV2: ProductionFeatureDelivery(
    feature: Feature.questV2,
    productionEntryId: 'drawer/rewards/quests',
    dependencyId: 'QuestUseCases',
    durable: true,
  ),
  Feature.studyPlanning: ProductionFeatureDelivery(
    feature: Feature.studyPlanning,
    productionEntryId: 'home/study-planning',
    dependencyId: 'StudyPlanningUseCases',
    durable: true,
    screenClassName: 'StudyPlanningHubScreen',
  ),
  Feature.researchAssessment: ProductionFeatureDelivery(
    feature: Feature.researchAssessment,
    productionEntryId: 'research/assessment',
    dependencyId: 'AssessmentUseCases',
    durable: true,
    screenClassName: 'PrePostAssessmentScreen',
  ),
  Feature.dailyContinuity: ProductionFeatureDelivery(
    feature: Feature.dailyContinuity,
    productionEntryId: 'home/today',
    dependencyId: 'TodayHubUseCases',
    durable: true,
    screenClassName: 'TodayHubScreen',
  ),
  Feature.offlineContent: ProductionFeatureDelivery(
    feature: Feature.offlineContent,
    productionEntryId: 'settings/offline-content',
    dependencyId: 'OfflineContentManager',
    durable: true,
    screenClassName: 'OfflineContentManagerScreen',
  ),
};
