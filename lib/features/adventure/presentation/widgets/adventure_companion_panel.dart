import 'package:flutter/material.dart';

import '../../../rewards/domain/reward_models.dart';
import '../../domain/adventure_reaction.dart';

/// Passive companion presentation for an already selected scripted reaction.
final class AdventureCompanionPanel extends StatelessWidget {
  const AdventureCompanionPanel({
    super.key,
    required this.reaction,
    required this.rewardOwnership,
    this.language,
  });

  final AdventureReaction? reaction;
  final RewardAccount rewardOwnership;
  final AdventureReactionLanguage? language;

  @override
  Widget build(BuildContext context) {
    final current = reaction;
    if (current == null) return const SizedBox.shrink();
    final languageCode =
        language?.name ??
        Localizations.maybeLocaleOf(context)?.languageCode ??
        'en';
    final copy = current.copy.forLanguage(languageCode);
    final accessible = current.accessibilityText.forLanguage(languageCode);
    final cosmetics = _equippedCosmetics(rewardOwnership);
    final content = Semantics(
      key: ValueKey<String>(current.reactionId),
      container: true,
      liveRegion: true,
      explicitChildNodes: true,
      label: accessible,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const ExcludeSemantics(child: Icon(Icons.auto_awesome_outlined)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ExcludeSemantics(child: Text(copy)),
                    if (cosmetics.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      for (final cosmetic in cosmetics)
                        Semantics(
                          label: languageCode == 'th'
                              ? 'ของตกแต่งที่สวมใส่: ${cosmetic.name}'
                              : 'Equipped cosmetic: ${cosmetic.name}',
                          child: ExcludeSemantics(
                            child: Chip(label: Text(cosmetic.name)),
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
    );
    final mediaQuery = MediaQuery.maybeOf(context);
    final reduceMotion = mediaQuery?.disableAnimations ?? false;
    if (reduceMotion || current.motion == AdventureReactionMotion.none) {
      return content;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: content,
    );
  }
}

List<RewardCatalogItem> _equippedCosmetics(RewardAccount ownership) {
  final slots = ownership.equippedBySlot.keys.toList()..sort();
  return <RewardCatalogItem>[
    for (final slot in slots)
      ?RewardCatalog.byIdAtVersion(
        ownership.equippedBySlot[slot]!,
        ownership.catalogVersion,
      ),
  ];
}
