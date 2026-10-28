class DailyQuest {
  final String id;
  final String title;
  final String description;
  final int targetCount;
  int currentProgress;
  final int rewardCoins;
  final int rewardXp;
  bool isClaimed;

  DailyQuest({
    required this.id,
    required this.title,
    required this.description,
    required this.targetCount,
    this.currentProgress = 0,
    required this.rewardCoins,
    required this.rewardXp,
    this.isClaimed = false,
  });

  bool get isCompleted => currentProgress >= targetCount;
}

/// @deprecated Use [QuestUseCases] from `lib/features/quest/application/`.
/// Quarantined: in-memory state resets on restart, incompatible [DailyQuest]
/// model.  Removal target: Phase 0 gate (Week 16).
@Deprecated(
  'Use QuestUseCases (lib/features/quest/application/quest_use_cases.dart). '
  'Removal target: Phase 0 gate.',
)
class StreakAndDailyQuestService {
  int _currentStreakDays = 1;
  int _streakFreezeCount = 1;
  final List<DailyQuest> _quests = [
    DailyQuest(
      id: 'review_words',
      title: 'ทบทวนคำศัพท์ประจำวัน',
      description: 'ทบทวนศัพท์อย่างน้อย 10 คำ',
      targetCount: 10,
      rewardCoins: 50,
      rewardXp: 100,
    ),
    DailyQuest(
      id: 'boss_battle',
      title: 'ผู้กล้าสู้บอสประจำวัน',
      description: 'เข้าเล่นโหมด Boss Battle 1 ครั้ง',
      targetCount: 1,
      rewardCoins: 100,
      rewardXp: 200,
    ),
    DailyQuest(
      id: 'scan_object',
      title: 'นักสแกนโลกกว้าง',
      description: 'สแกนวัตถุคำศัพท์อย่างน้อย 2 ชิ้น',
      targetCount: 2,
      rewardCoins: 80,
      rewardXp: 150,
    ),
  ];

  int get currentStreakDays => _currentStreakDays;
  int get streakFreezeCount => _streakFreezeCount;
  List<DailyQuest> get quests => List.unmodifiable(_quests);

  void incrementProgress(String questId, [int amount = 1]) {
    for (final quest in _quests) {
      if (quest.id == questId && !quest.isCompleted) {
        quest.currentProgress += amount;
        if (quest.currentProgress > quest.targetCount) {
          quest.currentProgress = quest.targetCount;
        }
      }
    }
  }

  bool claimReward(String questId) {
    for (final quest in _quests) {
      if (quest.id == questId && quest.isCompleted && !quest.isClaimed) {
        quest.isClaimed = true;
        return true;
      }
    }
    return false;
  }

  void addStreakDay() {
    _currentStreakDays += 1;
  }

  bool useStreakFreeze() {
    if (_streakFreezeCount > 0) {
      _streakFreezeCount -= 1;
      return true;
    }
    return false;
  }
}
