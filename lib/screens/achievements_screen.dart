import 'package:flutter/material.dart';
import '../models/achievement_badge.dart';
import '../config/remote_economy_policy.dart';
import '../runtime/app_dependencies.dart';

class AchievementsScreen extends StatelessWidget {
  final List<AchievementBadge>? badges;
  final int? coins;

  const AchievementsScreen({
    super.key,
    this.badges,
    this.coins,
    this.remoteEconomyPolicy,
  });

  final RemoteEconomyPolicy? remoteEconomyPolicy;

  @override
  Widget build(BuildContext context) {
    final remoteEconomyEnabled =
        remoteEconomyPolicy ??
        AppDependenciesScope.maybeOf(context)?.remoteEconomyPolicy ??
        const RemoteEconomyPolicy();
    final displayBadges = badges ?? const <AchievementBadge>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          remoteEconomyEnabled.shopAndPurchasesEnabled
              ? 'ตราความสำเร็จ & รางวัล (Achievements)'
              : 'ความสำเร็จการฝึก (เฉพาะอุปกรณ์นี้)',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.amber.shade800,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!remoteEconomyEnabled.shopAndPurchasesEnabled)
              Card(
                elevation: 2,
                color: Colors.blueGrey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'ความคืบหน้าการฝึกเฉพาะอุปกรณ์นี้ • ใช้จ่ายไม่ได้',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else if (coins != null)
              Card(
                elevation: 4,
                color: Colors.amber.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.monetization_on,
                            color: Colors.amber.shade900,
                            size: 36,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$coins เหรียญสะสม',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'ร้านค้าปลดล็อกธีมวอลเปเปอร์กำลังเปิดให้บริการ!',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.shopping_bag),
                        label: const Text('ร้านค้า'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade900,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: displayBadges.isEmpty
                  ? const Center(
                      child: Text(
                        'ยังไม่มีความสำเร็จที่ยืนยันจากข้อมูลการฝึก',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.9,
                          ),
                      itemCount: displayBadges.length,
                      itemBuilder: (context, index) {
                        final badge = displayBadges[index];
                        return Card(
                          elevation: badge.isUnlocked ? 4 : 1,
                          color: badge.isUnlocked
                              ? Colors.amber.shade50
                              : Colors.grey.shade200,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: badge.isUnlocked
                                  ? Colors.amber
                                  : Colors.grey.shade400,
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  badge.isUnlocked ? Icons.stars : Icons.lock,
                                  size: 44,
                                  color: badge.isUnlocked
                                      ? Colors.amber.shade800
                                      : Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  badge.title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: badge.isUnlocked
                                        ? Colors.black87
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  badge.description,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
