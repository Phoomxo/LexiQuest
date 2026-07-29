enum EquipmentSlot { headgear, weapon, armor, relic }

class EquipmentItem {
  final String id;
  final String name;
  final EquipmentSlot slot;
  final String description;
  final double damageBuffPercent;
  final double latencyTimeBuffSeconds;
  final double xpGainBuffPercent;

  const EquipmentItem({
    required this.id,
    required this.name,
    required this.slot,
    required this.description,
    this.damageBuffPercent = 0.0,
    this.latencyTimeBuffSeconds = 0.0,
    this.xpGainBuffPercent = 0.0,
  });
}

class PlayerAvatarStats {
  final int totalDamageBonus;
  final double bonusLatencySeconds;
  final double totalXpBonusPercent;

  const PlayerAvatarStats({
    required this.totalDamageBonus,
    required this.bonusLatencySeconds,
    required this.totalXpBonusPercent,
  });
}

/// RPG Avatar Gear & Equipment Buff Engine for LexiQuest.
class AvatarEquipmentService {
  const AvatarEquipmentService();

  static const List<EquipmentItem> availableItems = [
    EquipmentItem(
      id: 'head_ipa_crown',
      name: '👑 IPA Crown of Phonetics',
      slot: EquipmentSlot.headgear,
      description: 'เพิ่มเวลาคิดตอบคำถาม +1.5 วินาทีในโหมด Ghost Battle',
      latencyTimeBuffSeconds: 1.5,
    ),
    EquipmentItem(
      id: 'weapon_cefr_sword',
      name: '⚔️ CEFR Excalibur Sword',
      slot: EquipmentSlot.weapon,
      description: 'เพิ่มพลังโจมตีใส่ร่างเงา Ghost Boss +25%',
      damageBuffPercent: 25.0,
    ),
    EquipmentItem(
      id: 'armor_srs_aegis',
      name: '🛡️ Spaced Repetition Aegis',
      slot: EquipmentSlot.armor,
      description: 'ป้องกันความเสียหายเมื่อตอบผิด และเพิ่มเวลาตอบ +0.5 วินาที',
      latencyTimeBuffSeconds: 0.5,
      damageBuffPercent: 10.0,
    ),
    EquipmentItem(
      id: 'relic_collocation_ring',
      name: '💍 Collocation Crystal Ring',
      slot: EquipmentSlot.relic,
      description: 'เพิ่มโบนัส XP & Gold Coins +50%',
      xpGainBuffPercent: 50.0,
    ),
  ];

  /// Calculates total buff stats from a list of equipped items
  static PlayerAvatarStats calculateStats(List<EquipmentItem> equippedItems) {
    double damageBuffSum = 0.0;
    double latencyBuffSum = 0.0;
    double xpBuffSum = 0.0;

    for (final item in equippedItems) {
      damageBuffSum += item.damageBuffPercent;
      latencyBuffSum += item.latencyTimeBuffSeconds;
      xpBuffSum += item.xpGainBuffPercent;
    }

    return PlayerAvatarStats(
      totalDamageBonus: damageBuffSum.round(),
      bonusLatencySeconds: double.parse(latencyBuffSum.toStringAsFixed(1)),
      totalXpBonusPercent: double.parse(xpBuffSum.toStringAsFixed(1)),
    );
  }
}
