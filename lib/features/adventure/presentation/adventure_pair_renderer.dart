import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../learning/pair_matching/presentation/pair_board_view.dart';
import '../../learning/pair_matching/presentation/pair_matching_experience_host.dart';
import '../application/adventure_diagnostics.dart';

/// A route-local, payload-free report from optional decoration resources.
/// This does not intercept arbitrary descendant Flutter build exceptions.
final class AdventurePairDecorationHealth extends ChangeNotifier {
  PairDecorationFailure? _failure;
  PairDecorationFailure? get failure => _failure;

  void reportFailure(PairDecorationFailure failure) {
    if (_failure != null) return;
    _failure = failure;
    notifyListeners();
  }
}

/// Playful Quest chrome around the exact canonical board. It owns no commands,
/// clock, audio, answers, research events or economy state. The supplied board
/// keeps its own focus, keyboard, semantics and scrolling hierarchy.
final class AdventurePairRenderer extends StatefulWidget {
  const AdventurePairRenderer({
    super.key,
    required this.model,
    required this.standardBoard,
    required this.reportFailure,
    required this.diagnostics,
    this.health,
  });

  final PairBoardModel model;
  final Widget standardBoard;
  final ValueChanged<PairDecorationFailure> reportFailure;
  final AdventureDiagnostics diagnostics;
  final AdventurePairDecorationHealth? health;

  @override
  State<AdventurePairRenderer> createState() => _AdventurePairRendererState();
}

final class _AdventurePairRendererState extends State<AdventurePairRenderer> {
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    widget.health?.addListener(_healthChanged);
    _checkInitialHealth();
  }

  @override
  void didUpdateWidget(AdventurePairRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.health, widget.health)) {
      oldWidget.health?.removeListener(_healthChanged);
      widget.health?.addListener(_healthChanged);
      _checkInitialHealth();
    }
  }

  void _checkInitialHealth() {
    if (widget.health?.failure == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _healthChanged();
    });
  }

  void _healthChanged() {
    final failure = widget.health?.failure;
    if (_reported || failure == null) return;
    _reported = true;
    widget.diagnostics.record(
      AdventureDiagnosticReasonCode.entryFallbackDependencyUnavailable,
    );
    widget.reportFailure(failure);
  }

  @override
  void dispose() {
    widget.health?.removeListener(_healthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 2;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Large text can scroll this decorative header independently, leaving
        // the canonical board a usable viewport even on a short narrow screen.
        final headerMaximum = constraints.maxHeight.isFinite
            ? math.min(168.0, constraints.maxHeight * .28)
            : 168.0;
        return Column(
          key: const ValueKey('adventure-pair-chrome'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: headerMaximum),
              child: ColoredBox(
                color: scheme.secondaryContainer,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.explore_outlined,
                          color: scheme.onSecondaryContainer,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              english ? 'Pair quest' : 'ภารกิจจับคู่',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: scheme.onSecondaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            if (!largeText && headerMaximum >= 128) ...[
                              const SizedBox(height: 4),
                              Text(
                                english
                                    ? 'Explore each pair at your own pace.'
                                    : 'ค่อย ๆ สำรวจคำแต่ละคู่ในจังหวะของคุณ',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: scheme.onSecondaryContainer,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: widget.standardBoard),
          ],
        );
      },
    );
  }
}
