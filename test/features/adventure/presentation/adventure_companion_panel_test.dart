import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_reaction_selector.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_reaction.dart';
import 'package:vocab_learning_app/features/adventure/presentation/widgets/adventure_companion_panel.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

void main() {
  const selector = AdventureReactionSelector();
  final reaction = selector.select(
    catalogVersion: AdventureReactionCatalog.v1Version,
    trigger: AdventureReactionTrigger.incorrect,
    variantSeed: 0,
  )!;

  for (final language in AdventureReactionLanguage.values) {
    testWidgets('F03 original skip copy is truthful ${language.name}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final skipped = selector.select(
          catalogVersion: AdventureReactionCatalog.v1Version,
          trigger: AdventureReactionTrigger.skipped,
          variantSeed: 0,
        )!;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdventureCompanionPanel(
                reaction: skipped,
                rewardOwnership: _rewardAccount(const <String, String>{}),
                language: language,
              ),
            ),
          ),
        );
        final thai = language == AdventureReactionLanguage.th;
        expect(
          find.text(
            thai
                ? 'ข้ามข้อนี้แล้ว ไปต่อเมื่อพร้อมนะ'
                : 'This item was skipped. Continue when you are ready.',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            thai
                ? 'เพื่อนร่วมทางยืนยันว่าข้ามข้อนี้แล้ว และไปต่อได้เมื่อพร้อม'
                : 'Companion confirms that this item was skipped; continue when ready.',
          ),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    });
  }

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

  for (final trigger in <AdventureReactionTrigger>[
    AdventureReactionTrigger.guidedCorrect,
    AdventureReactionTrigger.skipped,
    AdventureReactionTrigger.resumed,
    AdventureReactionTrigger.completed,
  ]) {
    testWidgets(
      '${trigger.name} keeps semantics and copy with reduced motion and no audio',
      (tester) async {
        final reviewed = selector.select(
          catalogVersion: AdventureReactionCatalog.v1Version,
          trigger: trigger,
          variantSeed: 0,
        )!;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              home: Scaffold(
                body: AdventureCompanionPanel(
                  reaction: reviewed,
                  rewardOwnership: _rewardAccount(const <String, String>{}),
                ),
              ),
            ),
          ),
        );

        expect(find.text(reviewed.copy.en), findsOneWidget);
        expect(
          find.bySemanticsLabel(reviewed.accessibilityText.en),
          findsOneWidget,
        );
        expect(find.byType(AnimatedSwitcher), findsNothing);
        expect(find.byType(IconButton), findsNothing);
        expect(reviewed.audioAssetId, isNull);
      },
    );
  }

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
    expect(
      tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
      Durations.short2,
    );
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

  group('canonical lesson lifecycle mapping', () {
    test('canonical non-learning skip selects reviewed supportive copy', () {
      expect(
        resolveAdventureLessonReactionTrigger(
          status: LessonSessionStatus.active,
          previousStatus: LessonSessionStatus.active,
          committedAnswerCorrect: null,
          revealedHintLevel: 0,
          skippedItem: true,
        ),
        AdventureReactionTrigger.skipped,
      );
    });

    final cases =
        <
          ({
            LessonSessionStatus status,
            LessonSessionStatus? previousStatus,
            bool? answerCorrect,
            int hintLevel,
            AdventureReactionTrigger? expected,
          })
        >[
          (
            status: LessonSessionStatus.planned,
            previousStatus: null,
            answerCorrect: null,
            hintLevel: 0,
            expected: AdventureReactionTrigger.missionReady,
          ),
          (
            status: LessonSessionStatus.active,
            previousStatus: LessonSessionStatus.planned,
            answerCorrect: true,
            hintLevel: 0,
            expected: AdventureReactionTrigger.independentCorrect,
          ),
          (
            status: LessonSessionStatus.active,
            previousStatus: LessonSessionStatus.active,
            answerCorrect: true,
            hintLevel: 1,
            expected: AdventureReactionTrigger.guidedCorrect,
          ),
          (
            status: LessonSessionStatus.active,
            previousStatus: LessonSessionStatus.active,
            answerCorrect: false,
            hintLevel: 0,
            expected: AdventureReactionTrigger.incorrect,
          ),
          (
            status: LessonSessionStatus.active,
            previousStatus: LessonSessionStatus.active,
            answerCorrect: false,
            hintLevel: 1,
            expected: AdventureReactionTrigger.incorrect,
          ),
          (
            status: LessonSessionStatus.active,
            previousStatus: LessonSessionStatus.paused,
            answerCorrect: null,
            hintLevel: 0,
            expected: AdventureReactionTrigger.resumed,
          ),
          (
            status: LessonSessionStatus.completed,
            previousStatus: LessonSessionStatus.active,
            answerCorrect: true,
            hintLevel: 0,
            expected: AdventureReactionTrigger.completed,
          ),
          (
            status: LessonSessionStatus.paused,
            previousStatus: LessonSessionStatus.active,
            answerCorrect: null,
            hintLevel: 0,
            expected: null,
          ),
          (
            status: LessonSessionStatus.abandoned,
            previousStatus: LessonSessionStatus.active,
            answerCorrect: null,
            hintLevel: 0,
            expected: null,
          ),
        ];

    for (final value in cases) {
      test('${value.status.name} resolves ${value.expected?.name}', () {
        expect(
          resolveAdventureLessonReactionTrigger(
            status: value.status,
            previousStatus: value.previousStatus,
            committedAnswerCorrect: value.answerCorrect,
            revealedHintLevel: value.hintLevel,
          ),
          value.expected,
        );
      });
    }
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
