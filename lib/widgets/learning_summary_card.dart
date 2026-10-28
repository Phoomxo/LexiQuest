import 'package:flutter/material.dart';

/// Presentation only: callers supply already-authoritative facts and labels.
/// Short primary values are centered; longer explanations belong below the card.
class LearningSummaryCard extends StatelessWidget {
  const LearningSummaryCard({
    super.key,
    required this.title,
    this.value,
    this.caption,
    this.icon,
  });

  final String title;
  final String? value;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final symbol?) ...[
              ExcludeSemantics(
                child: Icon(symbol, size: 28, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (value case final primary?) ...[
              const SizedBox(height: 8),
              Text(
                primary,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineLarge,
              ),
            ],
            if (caption case final supporting?) ...[
              const SizedBox(height: 8),
              Text(
                supporting,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
