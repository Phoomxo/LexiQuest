import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/companion/domain/companion_reaction.dart';
import 'package:vocab_learning_app/features/companion/presentation/contextual_companion_widget.dart';

void main() {
  const reaction = CompanionReaction(
    catalogVersion: 1,
    event: CompanionReactionEvent(
      catalogVersion: 1,
      signal: CompanionReactionSignal.retryAfterIncorrectCommit,
      sessionId: 'session:companion',
      committedResponseCount: 1,
    ),
    copy: 'That attempt is saved. Try once more when you\'re ready.',
  );

  testWidgets(
    'renders reviewed copy as a live semantic without blocking lesson input',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var inputPressed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  const ContextualCompanionWidget(reaction: reaction),
                  FilledButton(
                    onPressed: () => inputPressed = true,
                    child: const Text('Answer control'),
                  ),
                ],
              ),
            ),
          ),
        );

        expect(
          find.bySemanticsLabel(
            'Companion reaction: That attempt is saved. Try once more when you\'re ready.',
          ),
          findsOneWidget,
        );
        final companion = find.byType(ContextualCompanionWidget);
        expect(
          find.descendant(of: companion, matching: find.byType(ModalBarrier)),
          findsNothing,
        );
        expect(
          find.descendant(of: companion, matching: find.byType(AbsorbPointer)),
          findsNothing,
        );

        final answerControl = find.text('Answer control').hitTestable();
        expect(answerControl, findsOneWidget);
        await tester.tap(answerControl);
        expect(inputPressed, isTrue);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'reduced motion renders the same readable reaction without animation',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: const Scaffold(
              body: ContextualCompanionWidget(reaction: reaction),
            ),
          ),
        ),
      );

      expect(find.text(reaction.copy), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(
        find.bySemanticsLabel('Companion reaction: ${reaction.copy}'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a missing reaction hides the companion safely', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ContextualCompanionWidget(reaction: null)),
      ),
    );

    expect(find.byType(ContextualCompanionWidget), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Companion reaction:')), findsNothing);
  });
}
