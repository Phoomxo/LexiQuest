import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/companion/application/companion_reaction_use_cases.dart';
import 'package:vocab_learning_app/features/companion/domain/companion_reaction.dart';
import 'package:vocab_learning_app/features/companion/domain/companion_reaction_catalog.dart';

void main() {
  const catalog = CompanionReactionCatalog.v1;
  const useCases = CompanionReactionUseCases(catalog: catalog);

  test(
    'v1 resolves the reviewed reaction for each canonical session signal',
    () {
      final reactions = <CompanionReaction?>[
        useCases.resolve(
          const CompanionReactionEvent(
            catalogVersion: 1,
            signal: CompanionReactionSignal.sessionStarted,
            sessionId: 'session:companion',
            committedResponseCount: 0,
          ),
        ),
        useCases.resolve(
          const CompanionReactionEvent(
            catalogVersion: 1,
            signal: CompanionReactionSignal.retryAfterIncorrectCommit,
            sessionId: 'session:companion',
            committedResponseCount: 1,
          ),
        ),
        useCases.resolve(
          const CompanionReactionEvent(
            catalogVersion: 1,
            signal: CompanionReactionSignal.sessionCompleted,
            sessionId: 'session:companion',
            committedResponseCount: 2,
          ),
        ),
      ];

      expect(reactions.map((reaction) => reaction?.copy), <String?>[
        'Welcome back. Let\'s take one step at a time.',
        'That attempt is saved. Try once more when you\'re ready.',
        'Session complete. You showed up for your learning.',
      ]);
      expect(
        reactions.map((reaction) => reaction?.catalogVersion).toSet(),
        <int?>{1},
      );
    },
  );

  test('unknown signal or catalog version fails closed with no reaction', () {
    expect(
      useCases.resolve(
        const CompanionReactionEvent(
          catalogVersion: 1,
          signal: CompanionReactionSignal.unknown,
          sessionId: 'session:companion',
          committedResponseCount: 1,
        ),
      ),
      isNull,
    );
    expect(
      useCases.resolve(
        const CompanionReactionEvent(
          catalogVersion: 99,
          signal: CompanionReactionSignal.sessionStarted,
          sessionId: 'session:companion',
          committedResponseCount: 0,
        ),
      ),
      isNull,
    );
  });

  test('resolution is a synchronous consumer of immutable event context', () {
    const event = CompanionReactionEvent(
      catalogVersion: 1,
      signal: CompanionReactionSignal.retryAfterIncorrectCommit,
      sessionId: 'session:companion',
      committedResponseCount: 3,
    );

    final resolved = useCases.resolve(event);

    expect(resolved, isNotNull);
    expect(event.sessionId, 'session:companion');
    expect(event.committedResponseCount, 3);
    expect(resolved!.event, event);
  });
}
