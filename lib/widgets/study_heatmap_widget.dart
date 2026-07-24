import 'package:flutter/material.dart';

class StudyHeatmapWidget extends StatelessWidget {
  final Map<DateTime, int> dailyActivity;

  const StudyHeatmapWidget({super.key, required this.dailyActivity});

  @override
  Widget build(BuildContext context) {
    final days = List.generate(28, (index) {
      final now = DateTime.now();
      return DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 27 - index));
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ปฏิทินความถี่การเรียนรู้ (28 วันล่าสุด)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: days.map((day) {
            final count = _getActivityCountForDay(day);
            return Tooltip(
              message: '${day.day}/${day.month}: $count คำศัพท์',
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _getColorForCount(count),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  int _getActivityCountForDay(DateTime day) {
    for (final entry in dailyActivity.entries) {
      if (entry.key.year == day.year &&
          entry.key.month == day.month &&
          entry.key.day == day.day) {
        return entry.value;
      }
    }
    return 0;
  }

  Color _getColorForCount(int count) {
    if (count <= 0) return Colors.grey.shade300;
    if (count <= 5) return Colors.green.shade200;
    if (count <= 15) return Colors.green.shade400;
    return Colors.green.shade700;
  }
}
