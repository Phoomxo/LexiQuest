import 'package:flutter/material.dart';

import '../domain/companion_reaction.dart';

/// Passive, local-only companion presentation for an already resolved reaction.
final class ContextualCompanionWidget extends StatelessWidget {
  const ContextualCompanionWidget({super.key, required this.reaction});

  final CompanionReaction? reaction;

  @override
  Widget build(BuildContext context) {
    final current = reaction;
    if (current == null) return const SizedBox.shrink();
    final content = Semantics(
      key: ValueKey<CompanionReaction>(current),
      container: true,
      liveRegion: true,
      label: 'Companion reaction: ${current.copy}',
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(current.copy),
          ),
        ),
      ),
    );
    if (MediaQuery.of(context).disableAnimations) return content;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: content,
    );
  }
}
