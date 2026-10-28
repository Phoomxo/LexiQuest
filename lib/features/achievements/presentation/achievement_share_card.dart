import 'package:flutter/material.dart';

import '../application/achievement_share_card_use_cases.dart';

/// Static, local preview of the exact allowlisted metadata in an artifact.
/// It never renders a destination, owner, or evidence identifier.
final class AchievementShareCard extends StatelessWidget {
  const AchievementShareCard({super.key, required this.artifact});

  final AchievementShareCardArtifact artifact;

  @override
  Widget build(BuildContext context) {
    final unlockedAt = artifact.unlockedAtUtc.toUtc();
    final date =
        '${unlockedAt.day.toString().padLeft(2, '0')}/'
        '${unlockedAt.month.toString().padLeft(2, '0')}/'
        '${unlockedAt.year}';
    return Semantics(
      label: 'การ์ดความสำเร็จ: ${artifact.title}',
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.workspace_premium_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                artifact.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text('นิยาม v${artifact.definitionVersion}'),
              Text('ปลดล็อกเมื่อ $date'),
            ],
          ),
        ),
      ),
    );
  }
}
