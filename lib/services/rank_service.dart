import '../models/user_rank.dart';

class RankService {
  const RankService();

  UserRank calculateRank(int xp) {
    RankTier currentTier = RankTier.bronze;
    for (final tier in RankTier.values.reversed) {
      if (xp >= tier.minXp) {
        currentTier = tier;
        break;
      }
    }
    return UserRank(totalXp: xp, tier: currentTier);
  }

  int calculateXpGain({
    required bool isCorrect,
    required int latencyMs,
    required bool isBossBattle,
  }) {
    if (!isCorrect) return 0;
    int base = isBossBattle ? 50 : 20;

    // Latency bonus for fast recall (< 1500 ms)
    if (latencyMs < 1500) {
      base += 10;
    }
    return base;
  }
}
