import '../domain/companion_reaction.dart';
import '../domain/companion_reaction_catalog.dart';

/// Pure local resolver. It has no repository, IO, network, or AI dependency.
final class CompanionReactionUseCases {
  const CompanionReactionUseCases({required this.catalog});

  final CompanionReactionCatalog catalog;

  CompanionReaction? resolve(CompanionReactionEvent event) =>
      catalog.resolve(event);
}
