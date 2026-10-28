import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/models/user_rank.dart';
import 'package:vocab_learning_app/services/rank_service.dart';

void main() {
  const service = RankService();

  test('calculateRank assigns correct tier based on XP thresholds', () {
    expect(service.calculateRank(100).tier, RankTier.bronze);
    expect(service.calculateRank(600).tier, RankTier.silver);
    expect(service.calculateRank(2000).tier, RankTier.gold);
    expect(service.calculateRank(4000).tier, RankTier.platinum);
    expect(service.calculateRank(8000).tier, RankTier.diamond);
  });

  test('calculateXpGain awards bonus for fast latency and boss battle', () {
    expect(
      service.calculateXpGain(
        isCorrect: true,
        latencyMs: 1000,
        isBossBattle: false,
      ),
      30,
    );
    expect(
      service.calculateXpGain(
        isCorrect: true,
        latencyMs: 1000,
        isBossBattle: true,
      ),
      60,
    );
    expect(
      service.calculateXpGain(
        isCorrect: false,
        latencyMs: 500,
        isBossBattle: true,
      ),
      0,
    );
  });
}
