import 'package:flutter/material.dart';

import '../../domain/adventure_journey.dart';

final class AdventureStatusPanel extends StatelessWidget {
  const AdventureStatusPanel({super.key, required this.freshness});

  final AdventureSnapshotFreshness freshness;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (freshness) {
      AdventureSnapshotFreshness.current => (
        Icons.check_circle_outline,
        'เส้นทางพร้อมใช้งาน',
      ),
      AdventureSnapshotFreshness.stale => (
        Icons.schedule_outlined,
        'ข้อมูลเส้นทางล้าสมัย กรุณารีเฟรช',
      ),
      AdventureSnapshotFreshness.unavailable => (
        Icons.cloud_off_outlined,
        'เส้นทางยังไม่พร้อมใช้งาน',
      ),
      AdventureSnapshotFreshness.corrupt => (
        Icons.error_outline,
        'ข้อมูลเส้นทางไม่สมบูรณ์',
      ),
    };
    return Semantics(
      container: true,
      label: label,
      child: Card(
        key: ValueKey<String>('adventure-status-${freshness.name}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}
