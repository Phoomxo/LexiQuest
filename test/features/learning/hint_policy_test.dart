import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/hint_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/presentation/hint_panel.dart';

void main() {
  test('reveals strategy then context under one deterministic budget', () {
    final hints = HintUseCases(policy: _policy());

    expect(hints.state.hintLevel, 0);
    expect(hints.state.revealedHints, isEmpty);
    expect(hints.state.contextRevealed, isFalse);
    expect(hints.state.isExhausted, isFalse);

    final strategy = hints.revealNext();
    expect(strategy.changed, isTrue);
    expect(strategy.state.hintLevel, 1);
    expect(strategy.state.revealedHints.single.kind, HintKind.strategy);
    expect(strategy.state.contextRevealed, isFalse);

    final context = hints.revealNext();
    expect(context.changed, isTrue);
    expect(context.state.hintLevel, 2);
    expect(context.state.revealedHints.map((hint) => hint.kind), <HintKind>[
      HintKind.strategy,
      HintKind.context,
    ]);
    expect(context.state.contextRevealed, isTrue);
    expect(context.state.isExhausted, isTrue);

    final exhausted = hints.revealNext();
    expect(exhausted.changed, isFalse);
    expect(exhausted.state, same(context.state));
  });

  test('an unavailable hint leaves the attempt state unchanged', () {
    final hints = HintUseCases(policy: const HintPolicy.unavailable());
    final before = hints.state;

    final result = hints.revealNext();

    expect(result.changed, isFalse);
    expect(result.state, same(before));
    expect(result.state.availability, HintAvailability.unavailable);
    expect(result.state.hintLevel, 0);
  });

  testWidgets(
    'panel exposes staged support and disables itself when budget is exhausted',
    (tester) async {
      final hints = HintUseCases(policy: _policy());

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: HintPanel(
                state: hints.state,
                onRevealNext: () => setState(hints.revealNext),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Show strategy'), findsOneWidget);
      expect(find.text('Look for the familiar word family.'), findsNothing);
      expect(find.text('The sentence is about rail travel.'), findsNothing);

      await tester.tap(find.text('Show strategy'));
      await tester.pump();
      expect(find.text('Look for the familiar word family.'), findsOneWidget);
      expect(find.text('Reveal context'), findsOneWidget);
      expect(find.text('The sentence is about rail travel.'), findsNothing);

      await tester.tap(find.text('Reveal context'));
      await tester.pump();
      expect(find.text('The sentence is about rail travel.'), findsOneWidget);
      expect(find.text('Hint budget exhausted'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    },
  );
}

HintPolicy _policy() => HintPolicy.staged(
  strategy: 'Look for the familiar word family.',
  context: 'The sentence is about rail travel.',
);
