import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_reaction_selector.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_reaction.dart';
import 'package:vocab_learning_app/features/adventure/presentation/widgets/adventure_companion_panel.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

void main() {
  const selector = AdventureReactionSelector();
  final reaction = selector.select(
    catalogVersion: AdventureReactionCatalog.v1Version,
    trigger: AdventureReactionTrigger.incorrect,
    variantSeed: 0,
  )!;

  testWidgets(
    'renders Thai supportive copy semantic equivalent and equipped cosmetic',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final equipped = <String, String>{'headgear': 'headgear_ipa'};
      final rewards = _rewardAccount(equipped);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdventureCompanionPanel(
                reaction: reaction,
                rewardOwnership: rewards,
                language: AdventureReactionLanguage.th,
              ),
            ),
          ),
        );

        expect(find.text(reaction.copy.th), findsOneWidget);
        expect(
          find.bySemanticsLabel(reaction.accessibilityText.th),
          findsOneWidget,
        );
        expect(find.text('หมวก IPA'), findsOneWidget);
        expect(
          find.bySemanticsLabel('ของตกแต่งที่สวมใส่: หมวก IPA'),
          findsOneWidget,
        );
        expect(equipped, <String, String>{'headgear': 'headgear_ipa'});
        expect(rewards.transactionCount, 4);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('English locale uses the reviewed English copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: AdventureCompanionPanel(
            reaction: reaction,
            rewardOwnership: _rewardAccount(const <String, String>{}),
          ),
        ),
      ),
    );

    expect(find.text(reaction.copy.en), findsOneWidget);
    expect(
      find.bySemanticsLabel(reaction.accessibilityText.en),
      findsOneWidget,
    );
  });

  testWidgets(
    'reduced motion keeps the same text and semantics without animation',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            locale: const Locale('en'),
            home: Scaffold(
              body: AdventureCompanionPanel(
                reaction: reaction,
                rewardOwnership: _rewardAccount(const <String, String>{}),
              ),
            ),
          ),
        ),
      );

      expect(find.text(reaction.copy.en), findsOneWidget);
      expect(
        find.bySemanticsLabel(reaction.accessibilityText.en),
        findsOneWidget,
      );
      expect(find.byType(AnimatedSwitcher), findsNothing);
    },
  );

  testWidgets('normal motion is passive and audio is never required', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              AdventureCompanionPanel(
                reaction: reaction,
                rewardOwnership: _rewardAccount(const <String, String>{}),
              ),
              FilledButton(
                onPressed: () => pressed = true,
                child: const Text('Continue learning'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(AnimatedSwitcher), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    expect(find.text(reaction.copy.en), findsOneWidget);
    await tester.tap(find.text('Continue learning'));
    expect(pressed, isTrue);
  });

  testWidgets('missing reaction hides the panel safely', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdventureCompanionPanel(
            reaction: null,
            rewardOwnership: _rewardAccount(const <String, String>{}),
          ),
        ),
      ),
    );

    expect(find.byType(Card), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Companion|เพื่อนร่วมทาง')),
      findsNothing,
    );
  });
}

RewardAccount _rewardAccount(Map<String, String> equippedBySlot) =>
    RewardAccount(
      coinBalance: 120,
      catalogVersion: RewardCatalog.version,
      ownedItemIds: equippedBySlot.values.toSet(),
      equippedBySlot: equippedBySlot,
      transactionCount: 4,
    );
