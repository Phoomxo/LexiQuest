import 'package:flutter/material.dart';

import '../domain/hint_policy.dart';

final class HintPanel extends StatelessWidget {
  const HintPanel({
    super.key,
    required this.state,
    required this.onRevealNext,
    this.enabled = true,
  });

  final HintState state;
  final VoidCallback onRevealNext;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final buttonLabel = switch (state.availability) {
      HintAvailability.unavailable => 'Hint unavailable',
      HintAvailability.unknown => 'Hint status unavailable',
      HintAvailability.available when state.isExhausted =>
        'Hint budget exhausted',
      HintAvailability.available when state.hintLevel == 0 => 'Show strategy',
      HintAvailability.available => 'Reveal context',
    };
    final canReveal =
        enabled &&
        state.availability == HintAvailability.available &&
        !state.isExhausted;

    return Semantics(
      container: true,
      liveRegion: state.revealedHints.isNotEmpty,
      label: 'Hint level ${state.hintLevel}. $buttonLabel.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final hint in state.revealedHints)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(hint.content),
            ),
          FilledButton(
            onPressed: canReveal ? onRevealNext : null,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
