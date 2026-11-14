import '../../learning/domain/answer_motivation_evidence.dart';
import '../../motivation/domain/timezone_policy.dart';
import '../domain/quest_models.dart';
import 'quest_use_cases.dart';

final class QuestCatalogRevision {
  const QuestCatalogRevision({
    required this.definition,
    required this.activeFromUtcMs,
  });

  final QuestDefinition definition;
  final int activeFromUtcMs;
}

/// Built-in quest catalog for LexiQuest V2.
///
/// Contains standard daily and weekly quests that are seeded at application
/// startup via [QuestUseCases.startQuest].  All quests are idempotent —
/// calling [QuestUseCases.startQuest] for an already-active quest is a no-op.
///
/// **Catalog version:** [version] must be incremented whenever objectives,
/// rewards, or titles change.  The [QuestUseCases] will
/// [QuestRepository.upsertDefinition] the new version on the next startup,
/// and the active instance will continue to completion before the new
/// definition takes effect.
abstract final class QuestCatalogProvider {
  static const int version = 1;

  // ── Daily Quests ───────────────────────────────────────────────────────────

  /// Answer 5 questions correctly in one day.
  static final QuestDefinition dailyCorrectAnswers = QuestDefinition(
    questId: 'daily-correct-5-v1',
    catalogVersion: version,
    title: 'Daily Vocabulary Practice',
    description: 'Answer 5 vocabulary questions correctly today.',
    type: QuestType.daily,
    objectives: const [
      QuestObjective(
        objectiveId: 'obj-daily-correct',
        description: 'Correct answers',
        targetCount: 5,
        criteria: ObjectiveCriteria(
          eventType: 'QuizCompleted',
          filters: {'correct': true},
        ),
      ),
    ],
    reward: const RewardSpec(xpAmount: 50),
    expiresIn: const Duration(hours: 24),
  );

  // ── Weekly Quests ──────────────────────────────────────────────────────────

  /// Answer 20 questions correctly in one week.
  static final QuestDefinition weeklyCorrectAnswers = QuestDefinition(
    questId: 'weekly-correct-20-v1',
    catalogVersion: version,
    title: 'Weekly Vocabulary Champion',
    description: 'Answer 20 vocabulary questions correctly this week.',
    type: QuestType.weekly,
    objectives: const [
      QuestObjective(
        objectiveId: 'obj-weekly-correct',
        description: 'Correct answers this week',
        targetCount: 20,
        criteria: ObjectiveCriteria(
          eventType: 'QuizCompleted',
          filters: {'correct': true},
        ),
      ),
    ],
    reward: const RewardSpec(xpAmount: 200),
    expiresIn: const Duration(days: 7),
  );

  // ── Combined lists ─────────────────────────────────────────────────────────

  static List<QuestDefinition> get dailyQuests => [dailyCorrectAnswers];
  static List<QuestDefinition> get weeklyQuests => [weeklyCorrectAnswers];

  /// All built-in quests — daily first, then weekly.
  static List<QuestDefinition> get allQuests => [
    ...dailyQuests,
    ...weeklyQuests,
  ];

  static List<QuestCatalogRevision> get authoredRevisions => List.unmodifiable(
    allQuests.map(
      (definition) =>
          QuestCatalogRevision(definition: definition, activeFromUtcMs: 0),
    ),
  );

  static String canonicalAnswerManifest(QuestCatalogRevision revision) {
    final def = revision.definition;
    if (def.questId.trim().isEmpty ||
        def.questId != def.questId.trim() ||
        def.questId.length > 256 ||
        def.catalogVersion <= 0 ||
        revision.activeFromUtcMs < 0 ||
        (def.type != QuestType.daily && def.type != QuestType.weekly) ||
        def.objectives.isEmpty ||
        def.reward.xpAmount <= 0 ||
        def.reward.rewardItemId != null ||
        def.objectives.any(
          (objective) =>
              objective.objectiveId.trim().isEmpty ||
              objective.targetCount <= 0 ||
              objective.criteria.eventType != 'QuizCompleted' ||
              objective.criteria.filters?.length != 1 ||
              objective.criteria.filters?['correct'] != true,
        )) {
      throw ArgumentError('Unsupported answer Quest revision');
    }
    return canonicalJson({
      'questId': def.questId,
      'catalogVersion': def.catalogVersion,
      'title': def.title,
      'description': def.description,
      'type': def.type.name,
      'objectives': [
        for (final objective in def.objectives)
          {
            'objectiveId': objective.objectiveId,
            'description': objective.description,
            'targetCount': objective.targetCount,
            'eventType': objective.criteria.eventType,
            'filters': objective.criteria.filters,
          },
      ],
      'reward': {
        'xpAmount': def.reward.xpAmount,
        'rewardItemId': def.reward.rewardItemId,
      },
      'expiresInMs': def.expiresIn?.inMilliseconds,
      'tags': def.tags,
      'definitionSchemaVersion': 1,
      'criteriaPolicyVersion': 1,
      'calendarPolicyVersion': TimezonePolicy.version,
      'occurrencePolicy': 'civil-segments-v1',
      'activeFromUtcMs': revision.activeFromUtcMs,
    });
  }

  // ── Startup helper ─────────────────────────────────────────────────────────

  /// Seed all built-in quests for the current owner and expire stale
  /// instances.
  ///
  /// Safe to call on every app launch — [QuestUseCases.startQuest] is
  /// idempotent (returns null when the quest is already active).
  static Future<void> seedOnStartup(QuestUseCases quest) async {
    await quest.expireStale();
    for (final def in allQuests) {
      await quest.startQuest(def);
    }
  }
}
