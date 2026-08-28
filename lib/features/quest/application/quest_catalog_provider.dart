import '../domain/quest_models.dart';
import 'quest_use_cases.dart';

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
    objectives: List<QuestObjective>.unmodifiable(const [
      QuestObjective(
        objectiveId: 'obj-daily-correct',
        description: 'Correct answers',
        targetCount: 5,
        criteria: ObjectiveCriteria(
          eventType: 'QuizCompleted',
          filters: {'correct': true},
        ),
      ),
    ]),
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
    objectives: List<QuestObjective>.unmodifiable(const [
      QuestObjective(
        objectiveId: 'obj-weekly-correct',
        description: 'Correct answers this week',
        targetCount: 20,
        criteria: ObjectiveCriteria(
          eventType: 'QuizCompleted',
          filters: {'correct': true},
        ),
      ),
    ]),
    reward: const RewardSpec(xpAmount: 200),
    expiresIn: const Duration(days: 7),
  );

  // ── Combined lists ─────────────────────────────────────────────────────────

  static final List<QuestDefinition> _dailyQuests =
      List<QuestDefinition>.unmodifiable([dailyCorrectAnswers]);
  static final List<QuestDefinition> _weeklyQuests =
      List<QuestDefinition>.unmodifiable([weeklyCorrectAnswers]);
  static final List<QuestDefinition> _allQuests =
      List<QuestDefinition>.unmodifiable([
        dailyCorrectAnswers,
        weeklyCorrectAnswers,
      ]);

  static List<QuestDefinition> get dailyQuests => _dailyQuests;
  static List<QuestDefinition> get weeklyQuests => _weeklyQuests;

  /// All built-in quests — daily first, then weekly.
  static List<QuestDefinition> get allQuests => _allQuests;

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
