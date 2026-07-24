import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/ghost_shadow_duel_service.dart';

void main() {
  final sampleSnapshot = GhostSnapshot(
    recordedAt: DateTime(2026, 7, 20),
    accuracyRate: 0.85,
    avgResponseTimeMs: 2500,
    weakWords: ['ancient', 'analyze'],
  );

  test('generateShadowOpponent creates GhostOpponent with correct stats', () {
    final opponent = GhostShadowDuelService.generateShadowOpponent(
      sampleSnapshot,
    );

    expect(opponent.name, contains('Shadow Self'));
    expect(opponent.maxHp, 85);
    expect(opponent.attackIntervalSeconds, 2.5);
    expect(opponent.battleWords, contains('ancient'));
  });

  test('evaluateTurn triggers selfMasteryBonus when beating past speed', () {
    final result = GhostShadowDuelService.evaluateTurn(
      playerResponseTimeMs: 1800,
      isCorrect: true,
      snapshot: sampleSnapshot,
    );

    expect(result.playerHitGhost, isTrue);
    expect(result.selfMasteryBonusTriggered, isTrue);
    expect(result.damageDealt, 25);
    expect(result.message, contains('ไวกว่าร่างเงา'));
  });

  test('evaluateTurn handles incorrect answer gracefully', () {
    final result = GhostShadowDuelService.evaluateTurn(
      playerResponseTimeMs: 1200,
      isCorrect: false,
      snapshot: sampleSnapshot,
    );

    expect(result.playerHitGhost, isFalse);
    expect(result.selfMasteryBonusTriggered, isFalse);
    expect(result.damageDealt, 0);
  });
}
