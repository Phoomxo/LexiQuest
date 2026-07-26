import 'package:vocab_learning_app/services/kmeans_learner_profiler_service.dart';

class DailyQuest {
  final String title;
  final String description;
  final int rewardXp;
  final int rewardCoins;
  final String targetMode;

  const DailyQuest({
    required this.title,
    required this.description,
    required this.rewardXp,
    required this.rewardCoins,
    required this.targetMode,
  });
}

/// Adaptive Daily Quest & Loot Generator Engine (Personalized Learning Standard).
class AdaptiveDailyQuestService {
  const AdaptiveDailyQuestService();

  /// Generates daily quests customized for a specific learner persona
  static List<DailyQuest> generateQuests(LearnerPersona persona) {
    switch (persona) {
      case LearnerPersona.masterPerformer:
        return const [
          DailyQuest(
            title: '🤺 พิชิตร่างเงาตนเอง',
            description: 'เอาชนะร่างเงาในอดีต Ghost Shadow Duel ให้ได้ 1 ครั้ง',
            rewardXp: 200,
            rewardCoins: 100,
            targetMode: 'GhostShadowDuel',
          ),
          DailyQuest(
            title: '⚔️ ลุยโหมดต่อสู้บอสคำศัพท์',
            description: 'ท้าทายบอสคำศัพท์ประจำวันด้วยความเร็วสูงสุด',
            rewardXp: 150,
            rewardCoins: 75,
            targetMode: 'BossBattle',
          ),
        ];
      case LearnerPersona.deepReader:
        return const [
          DailyQuest(
            title: '📖 อ่านนิทานสัทศาสตร์ CEFR',
            description: 'อ่านนิทาน Interactive Storybook จบ 1 บทเต็ม',
            rewardXp: 150,
            rewardCoins: 80,
            targetMode: 'InteractiveStorybook',
          ),
          DailyQuest(
            title: '🌳 สำรวจผังคำประสม Collocation',
            description: 'กดเรียนรู้กลุ่มคำประสม Mind Map อย่างน้อย 3 กลุ่ม',
            rewardXp: 120,
            rewardCoins: 60,
            targetMode: 'CollocationTree',
          ),
        ];
      case LearnerPersona.atRiskLearner:
        return const [
          DailyQuest(
            title: '🏥 ซ่อมเสริมคำศัพท์จุดอ่อน',
            description:
                'เข้าทบทวนคำศัพท์ที่สะกดคลาดเคลื่อนใน Weakness Clinic 5 คำ',
            rewardXp: 250,
            rewardCoins: 120,
            targetMode: 'WeaknessClinic',
          ),
          DailyQuest(
            title: '🃏 ทบทวนการ์ดศัพท์ SRS',
            description: 'เปิดทบทวน Flashcards อย่างน้อย 10 คำ',
            rewardXp: 180,
            rewardCoins: 90,
            targetMode: 'SrsFlashcards',
          ),
        ];
    }
  }
}
