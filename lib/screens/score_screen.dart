import 'package:flutter/material.dart';

class ScoreScreen extends StatelessWidget {
  const ScoreScreen({
    super.key,
    required this.correctAnswers,
    required this.wrongAnswers,
    this.score,
    this.isFromFirestore = false,
    this.selectedCategoryId,
  });

  final int correctAnswers;
  final int wrongAnswers;
  final int? score;

  /// Retained for source compatibility; score data is always local-first.
  final bool isFromFirestore;
  final String? selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final total = correctAnswers + wrongAnswers;
    final resolvedScore =
        score ?? (total == 0 ? 0 : ((correctAnswers * 100) / total).round());
    return Scaffold(
      appBar: AppBar(title: const Text('ผลการเรียน')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$resolvedScore%',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 20),
              _ResultRow(
                label: 'ตอบถูก',
                value: correctAnswers,
                icon: Icons.check_circle_outline,
              ),
              _ResultRow(
                label: 'ตอบผิด',
                value: wrongAnswers,
                icon: Icons.cancel_outlined,
              ),
              _ResultRow(
                label: 'จำนวนตัวอย่าง',
                value: total,
                icon: Icons.dataset_outlined,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('กลับไปเลือกกิจกรรม'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text('$value'),
    );
  }
}
