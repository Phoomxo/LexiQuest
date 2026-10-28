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

  const thaiCopy = <CompanionReactionSignal, String>{
    CompanionReactionSignal.sessionStarted: 'ค่อย ๆ เรียนไปทีละขั้น',
    CompanionReactionSignal.retryAfterIncorrectCommit:
        'บันทึกคำตอบแล้ว พร้อมเมื่อไรลองอีกครั้งได้',
    CompanionReactionSignal.sessionCompleted: 'จบการฝึกรอบนี้แล้ว',
  };

  for (final entry in thaiCopy.entries) {
    testWidgets('${entry.key.name} uses reviewed Thai presentation copy', (
      tester,
    ) async {
      final localized = _reactionFor(entry.key);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ContextualCompanionWidget(reaction: localized),
            ),
          ),
        );

        expect(find.text(entry.value), findsOneWidget);
        expect(
          find.bySemanticsLabel('เพื่อนร่วมเรียน: ${entry.value}'),
          findsOneWidget,
        );
        expect(find.text(localized.copy), findsNothing);
        expect(
          tester
              .widget<Semantics>(
                find.byKey(ValueKey<CompanionReaction>(localized)),
              )
              .properties
              .liveRegion,
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets(
    'explicit English keeps reviewed catalog copy and semantic prefix',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          home: Scaffold(
            body: ContextualCompanionWidget(
              reaction: reaction,
              languageCode: 'en',
            ),
          ),
        ),
      );

      expect(find.text(reaction.copy), findsOneWidget);
      expect(
        find.bySemanticsLabel('Companion reaction: ${reaction.copy}'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'language change updates copy without changing reaction identity',
    (tester) async {
      final language = ValueNotifier<String>('th');
      addTearDown(language.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: language,
            builder: (context, code, _) => ContextualCompanionWidget(
              reaction: reaction,
              languageCode: code,
            ),
          ),
        ),
      );
      const thai = 'บันทึกคำตอบแล้ว พร้อมเมื่อไรลองอีกครั้งได้';
      expect(find.text(thai), findsOneWidget);

      language.value = 'en';
      await tester.pump();

      expect(find.text(reaction.copy), findsOneWidget);
      expect(
        find.byKey(const ValueKey<CompanionReaction>(reaction)),
        findsOneWidget,
      );
    },
  );

  testWidgets('unsupported language falls back to reviewed Thai copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ContextualCompanionWidget(
            reaction: reaction,
            languageCode: 'ja',
          ),
        ),
      ),
    );

    const copy = 'บันทึกคำตอบแล้ว พร้อมเมื่อไรลองอีกครั้งได้';
    expect(find.text(copy), findsOneWidget);
    expect(find.bySemanticsLabel('เพื่อนร่วมเรียน: $copy'), findsOneWidget);
  });

  testWidgets('unknown signal and catalog version fail closed', (tester) async {
    for (final invalid in <CompanionReaction>[
      _reactionFor(CompanionReactionSignal.unknown),
      CompanionReaction(
        catalogVersion: 99,
        event: const CompanionReactionEvent(
          catalogVersion: 99,
          signal: CompanionReactionSignal.sessionStarted,
          sessionId: 'session:future',
          committedResponseCount: 0,
        ),
        copy: 'Future unreviewed copy',
      ),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ContextualCompanionWidget(reaction: invalid)),
        ),
      );
      expect(find.text(invalid.copy), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('เพื่อนร่วมเรียน|Companion reaction')),
        findsNothing,
      );
    }
  });

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
                  const ContextualCompanionWidget(
                    reaction: reaction,
                    languageCode: 'en',
                  ),
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
              body: ContextualCompanionWidget(
                reaction: reaction,
                languageCode: 'en',
              ),
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

CompanionReaction _reactionFor(CompanionReactionSignal signal) =>
    CompanionReaction(
      catalogVersion: 1,
      event: CompanionReactionEvent(
        catalogVersion: 1,
        signal: signal,
        sessionId: 'session:${signal.name}',
        committedResponseCount: signal == CompanionReactionSignal.sessionStarted
            ? 0
            : 1,
      ),
      copy: switch (signal) {
        CompanionReactionSignal.sessionStarted =>
          'Welcome back. Let\'s take one step at a time.',
        CompanionReactionSignal.retryAfterIncorrectCommit =>
          'That attempt is saved. Try once more when you\'re ready.',
        CompanionReactionSignal.sessionCompleted =>
          'Session complete. You showed up for your learning.',
        CompanionReactionSignal.unknown => 'Unknown unreviewed copy',
      },
    );
