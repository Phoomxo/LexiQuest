import 'dart:math';

class GhostSnapshot {
  final DateTime recordedAt;
  final double accuracyRate;
  final double avgResponseTimeMs;
  final List<String> weakWords;

  const GhostSnapshot({
    required this.recordedAt,
    required this.accuracyRate,
    required this.avgResponseTimeMs,
    required this.weakWords,
  });
}

class GhostOpponent {
  final String name;
  final int maxHp;
  final int currentHp;
  final double attackIntervalSeconds;
  final List<String> battleWords;

  const GhostOpponent({
    required this.name,
    required this.maxHp,
    required this.currentHp,
    required this.attackIntervalSeconds,
    required this.battleWords,
  });
}

class DuelTurnResult {
  final bool playerHitGhost;
  final int damageDealt;
  final bool selfMasteryBonusTriggered;
  final String message;

  const DuelTurnResult({
    required this.playerHitGhost,
    required this.damageDealt,
    required this.selfMasteryBonusTriggered,
    required this.message,
  });
}

/// 'Your Next Opponent Is You' - Ghost Shadow Duel Core Engine.
/// Generates an adaptive Ghost Opponent from historic telemetry (Burgess 2012, Sailer 2017).
class GhostShadowDuelService {
  const GhostShadowDuelService();

  /// Generates a Ghost Opponent based on user's past snapshot
  static GhostOpponent generateShadowOpponent(GhostSnapshot snapshot) {
    final name =
        'Shadow Self (${snapshot.recordedAt.day}/${snapshot.recordedAt.month})';
    final baseHp = (snapshot.accuracyRate * 100).round().clamp(50, 150);
    final attackInterval = (snapshot.avgResponseTimeMs / 1000.0).clamp(1.5, 5.0);

    return GhostOpponent(
      name: name,
      maxHp: baseHp,
      currentHp: baseHp,
      attackIntervalSeconds: attackInterval,
      battleWords: snapshot.weakWords,
    );
  }

  /// Evaluates a combat turn when player answers a word prompt against their past ghost speed
  static DuelTurnResult evaluateTurn({
    required double playerResponseTimeMs,
    required bool isCorrect,
    required GhostSnapshot snapshot,
  }) {
    if (!isCorrect) {
      return const DuelTurnResult(
        playerHitGhost: false,
        damageDealt: 0,
        selfMasteryBonusTriggered: false,
        message: 'ตอบคลาดเคลื่อน! ร่างเงาเป็นฝ่ายได้เปรียบ',
      );
    }

    final beatPastSpeed = playerResponseTimeMs < snapshot.avgResponseTimeMs;
    final damage = beatPastSpeed ? 25 : 15;

    return DuelTurnResult(
      playerHitGhost: true,
      damageDealt: damage,
      selfMasteryBonusTriggered: beatPastSpeed,
      message:
          beatPastSpeed
              ? '⚡ ยอดเยี่ยม! คุณตอบไวกว่าร่างเงาในอดีต (โบนัสก้าวข้ามตนเอง)'
              : '👍 ตอบถูกต้อง! กำลังสร้างความเสียหายใส่ร่างเงา',
    );
  }
}
