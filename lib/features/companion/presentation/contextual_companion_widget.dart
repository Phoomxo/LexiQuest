import 'package:flutter/material.dart';

import '../../../config/m3_theme.dart';
import '../domain/companion_reaction.dart';

/// Passive, local-only companion presentation for an already resolved reaction.
final class ContextualCompanionWidget extends StatelessWidget {
  const ContextualCompanionWidget({
    super.key,
    required this.reaction,
    this.languageCode = 'th',
  });

  final CompanionReaction? reaction;
  final String languageCode;

  @override
  Widget build(BuildContext context) {
    final current = reaction;
    if (current == null) return const SizedBox.shrink();
    final copy = _copyFor(current, languageCode);
    if (copy == null) return const SizedBox.shrink();
    final thai = languageCode != 'en';
    final content = Semantics(
      key: ValueKey<CompanionReaction>(current),
      container: true,
      liveRegion: true,
      label: thai ? 'เพื่อนร่วมเรียน: $copy' : 'Companion reaction: $copy',
      child: ExcludeSemantics(
        child: Card(
          child: Padding(padding: const EdgeInsets.all(12), child: Text(copy)),
        ),
      ),
    );
    final duration = M3Theme.motionDuration(
      Durations.short2,
      mediaQuery: MediaQuery.maybeOf(context) ?? const MediaQueryData(),
    );
    if (duration == Duration.zero) return content;
    return AnimatedSwitcher(duration: duration, child: content);
  }
}

String? _copyFor(CompanionReaction reaction, String languageCode) {
  final event = reaction.event;
  if (reaction.catalogVersion != 1 ||
      event.catalogVersion != reaction.catalogVersion ||
      !event.isCanonicalV1) {
    return null;
  }
  final thai = languageCode != 'en';
  return switch (event.signal) {
    CompanionReactionSignal.sessionStarted =>
      thai
          ? 'ค่อย ๆ เรียนไปทีละขั้น'
          : 'Welcome back. Let\'s take one step at a time.',
    CompanionReactionSignal.retryAfterIncorrectCommit =>
      thai
          ? 'บันทึกคำตอบแล้ว พร้อมเมื่อไรลองอีกครั้งได้'
          : 'That attempt is saved. Try once more when you\'re ready.',
    CompanionReactionSignal.sessionCompleted =>
      thai
          ? 'จบการฝึกรอบนี้แล้ว'
          : 'Session complete. You showed up for your learning.',
    CompanionReactionSignal.unknown => null,
  };
}
