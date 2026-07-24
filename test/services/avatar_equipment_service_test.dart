import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/avatar_equipment_service.dart';

void main() {
  test('calculateStats aggregates equipped item buff bonuses correctly', () {
    final equipped = [
      AvatarEquipmentService.availableItems[0], // Crown (+1.5s latency)
      AvatarEquipmentService.availableItems[1], // Sword (+25% damage)
      AvatarEquipmentService.availableItems[3], // Ring (+50% XP)
    ];

    final stats = AvatarEquipmentService.calculateStats(equipped);

    expect(stats.totalDamageBonus, 25);
    expect(stats.bonusLatencySeconds, 1.5);
    expect(stats.totalXpBonusPercent, 50.0);
  });

  test('calculateStats returns zero bonuses for empty equipment', () {
    final stats = AvatarEquipmentService.calculateStats([]);

    expect(stats.totalDamageBonus, 0);
    expect(stats.bonusLatencySeconds, 0.0);
    expect(stats.totalXpBonusPercent, 0.0);
  });
}
