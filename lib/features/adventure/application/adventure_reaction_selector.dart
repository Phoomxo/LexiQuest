import '../domain/adventure_reaction.dart';

/// Pure selector over a closed local catalog and committed state code.
final class AdventureReactionSelector {
  const AdventureReactionSelector();

  AdventureReaction? select({
    required String catalogVersion,
    required AdventureReactionTrigger trigger,
    required int variantSeed,
  }) {
    if (variantSeed < 0) return null;
    final catalog = AdventureReactionCatalog.forVersion(catalogVersion);
    if (catalog == null) return null;
    final candidates = catalog.reactions
        .where((reaction) => reaction.trigger == trigger)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    final selected = candidates[variantSeed % candidates.length];
    return AdventureReactionContentReview.isApprovedReaction(selected)
        ? selected
        : null;
  }
}
