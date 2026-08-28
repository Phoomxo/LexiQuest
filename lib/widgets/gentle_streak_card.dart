import 'package:flutter/material.dart';

import '../features/motivation/domain/streak_policy.dart';

enum _GentleStreakCardMode { data, loading, error, paused }

/// Calm, read-only streak content owned by the future f42 Today parent.
class GentleStreakCard extends StatelessWidget {
  const GentleStreakCard({
    super.key,
    required this.snapshot,
    this.enabled = true,
    this.onRecovery,
  }) : _mode = _GentleStreakCardMode.data;

  const GentleStreakCard.loading({super.key, this.enabled = true})
    : snapshot = null,
      onRecovery = null,
      _mode = _GentleStreakCardMode.loading;

  const GentleStreakCard.error({super.key, this.enabled = true})
    : snapshot = null,
      onRecovery = null,
      _mode = _GentleStreakCardMode.error;

  const GentleStreakCard.paused({
    super.key,
    required GentleStreakSnapshot this.snapshot,
    this.enabled = true,
  }) : onRecovery = null,
       _mode = _GentleStreakCardMode.paused;

  final GentleStreakSnapshot? snapshot;
  final bool enabled;
  final VoidCallback? onRecovery;
  final _GentleStreakCardMode _mode;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final content = _content();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: content.semanticLabel,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.local_fire_department_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          content.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(content.message),
                        if (content.supportingText case final text?) ...[
                          const SizedBox(height: 6),
                          Text(
                            text,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_mode == _GentleStreakCardMode.loading) ...[
                    const SizedBox(width: 12),
                    const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
              if (content.showRecoveryAction && onRecovery != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonal(
                    onPressed: onRecovery,
                    child: const Text('Continue gently'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _GentleStreakContent _content() {
    if (_mode == _GentleStreakCardMode.loading) {
      return const _GentleStreakContent(
        title: 'Your learning rhythm',
        message: 'Checking in…',
        semanticLabel: 'Gentle streak is loading.',
      );
    }
    if (_mode == _GentleStreakCardMode.error) {
      return const _GentleStreakContent(
        title: 'Your learning rhythm',
        message: 'We cannot show it right now. You can keep learning as usual.',
        semanticLabel:
            'Gentle streak is unavailable. You can keep learning as usual.',
      );
    }
    final value = snapshot!;
    if (_mode == _GentleStreakCardMode.paused) {
      return const _GentleStreakContent(
        title: 'Your learning rhythm is resting.',
        message: 'Continue whenever you feel ready.',
        semanticLabel:
            'Gentle streak paused. Continue whenever you feel ready.',
      );
    }
    if (value.phase == GentleStreakPhase.empty) {
      return const _GentleStreakContent(
        title: 'Start whenever you are ready',
        message: 'One learning day is a lovely beginning.',
        semanticLabel: 'Gentle streak is empty. Start whenever you are ready.',
      );
    }
    if (value.phase == GentleStreakPhase.recovery) {
      return _GentleStreakContent(
        title: 'Welcome back',
        message: 'A fresh learning day is ready when you are.',
        supportingText: 'Your best is ${value.longestStreakDays} days.',
        semanticLabel:
            'Gentle streak recovery. A fresh learning day is ready when you '
            'are. Your best is ${value.longestStreakDays} days.',
        showRecoveryAction: true,
      );
    }
    final freezeText = value.freezeCount == 1
        ? '1 gentle freeze available.'
        : '${value.freezeCount} gentle freezes available.';
    final graceText = value.phase == GentleStreakPhase.grace
        ? ' There is still room for today.'
        : '';
    return _GentleStreakContent(
      title: '${value.currentStreakDays} learning days',
      message: 'Your best is ${value.longestStreakDays} days.',
      supportingText: freezeText,
      semanticLabel:
          'Gentle streak, ${value.currentStreakDays} learning days. '
          'Your best is ${value.longestStreakDays} days. $freezeText$graceText',
    );
  }
}

final class _GentleStreakContent {
  const _GentleStreakContent({
    required this.title,
    required this.message,
    required this.semanticLabel,
    this.supportingText,
    this.showRecoveryAction = false,
  });

  final String title;
  final String message;
  final String? supportingText;
  final String semanticLabel;
  final bool showRecoveryAction;
}
