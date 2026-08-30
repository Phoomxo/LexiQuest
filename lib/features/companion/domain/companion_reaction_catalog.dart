import 'companion_reaction.dart';

/// Compile-time reviewed local scripts for the contextual companion.
final class CompanionReactionCatalog {
  const CompanionReactionCatalog._(this.version);

  static const CompanionReactionCatalog v1 = CompanionReactionCatalog._(1);

  final int version;

  CompanionReaction? resolve(CompanionReactionEvent event) {
    if (version != 1 ||
        event.catalogVersion != version ||
        !event.isCanonicalV1) {
      return null;
    }
    final copy = switch (event.signal) {
      CompanionReactionSignal.sessionStarted =>
        'Welcome back. Let\'s take one step at a time.',
      CompanionReactionSignal.retryAfterIncorrectCommit =>
        'That attempt is saved. Try once more when you\'re ready.',
      CompanionReactionSignal.sessionCompleted =>
        'Session complete. You showed up for your learning.',
      CompanionReactionSignal.unknown => null,
    };
    if (copy == null) return null;
    return CompanionReaction(catalogVersion: version, event: event, copy: copy);
  }
}
