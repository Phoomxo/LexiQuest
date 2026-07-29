import 'package:flutter/material.dart';
import '../services/avatar_equipment_service.dart';

/// RPG Avatar Equipment & Stat Buff Screen (Vertical Portrait Layout).
class AvatarEquipmentScreen extends StatefulWidget {
  const AvatarEquipmentScreen({super.key});

  @override
  State<AvatarEquipmentScreen> createState() => _AvatarEquipmentScreenState();
}

class _AvatarEquipmentScreenState extends State<AvatarEquipmentScreen> {
  final List<EquipmentItem> _equippedItems = List.from(
    AvatarEquipmentService.availableItems,
  );

  @override
  Widget build(BuildContext context) {
    final stats = AvatarEquipmentService.calculateStats(_equippedItems);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '🛡️ อุปกรณ์ตัวละคร & บัฟพลัง RPG',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.deepPurple.shade900,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Character Avatar Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepPurple.shade900, Colors.indigo.shade900],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10),
                ],
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.amber,
                    child: Icon(Icons.person, size: 60, color: Colors.indigo),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Vocabulary Warrior',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.flash_on, color: Colors.red),
                        label: Text(
                          'Damage: +${stats.totalDamageBonus}%',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Chip(
                        avatar: const Icon(Icons.timer, color: Colors.cyan),
                        label: Text(
                          'Time: +${stats.bonusLatencySeconds}s',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Chip(
                        avatar: const Icon(Icons.star, color: Colors.amber),
                        label: Text(
                          'XP: +${stats.totalXpBonusPercent}%',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'รายการอุปกรณ์ที่สวมใส่ (Equipped Items):',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._equippedItems.map((item) {
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(item.description),
                  trailing: const Icon(Icons.check_circle, color: Colors.green),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
