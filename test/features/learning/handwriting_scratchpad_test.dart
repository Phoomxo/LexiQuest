import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/handwriting_self_check_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/presentation/handwriting_scratchpad.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';

void main() {
  test(
    'self-check is guided practice with no default learning side effects',
    () {
      const adapter = HandwritingSelfCheckAdapter();

      final outcome = adapter.selfCheck(
        selection: HandwritingSelfCheckSelection.looksCorrect,
        hasHandwriting: true,
        hasTypedAlternative: false,
      );

      expect(outcome.evidenceClass, EvidenceClass.guidedPractice);
      expect(outcome.responseCode, 'handwriting-self-check');
      expect(outcome.inputMethod, HandwritingInputMethod.handwriting);
      expect(outcome.policy.writesSrs, isFalse);
      expect(outcome.policy.writesAssessment, isFalse);
      expect(outcome.policy.writesQuest, isFalse);
      expect(outcome.policy.writesStreak, isFalse);
      expect(outcome.policy.writesAchievement, isFalse);
      expect(outcome.policy.writesXp, isFalse);
      expect(outcome.policy.writesCoins, isFalse);
    },
  );

  test('adapter cannot turn a self-check into durable lesson evidence', () {
    const adapter = HandwritingSelfCheckAdapter();
    final response = LessonResponse(
      sourceEvidenceId: 'scratchpad-response',
      occurredAtUtc: DateTime.utc(2026, 8, 26),
      sessionId: 'scratchpad-session',
      wordId: 'scratchpad-word',
      promptMode: 'handwritingSelfCheck',
      isCorrect: true,
      responseTimeMs: null,
      attemptNumber: 1,
      feedbackContext: const AnswerFeedbackContext(
        canonicalCorrectAnswer: 'station',
      ),
    );
    final guided = EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.guidedPractice,
      skillId: 'handwriting-self-check',
      hintLevel: 1,
      contentRevision: 'handwriting-local-only',
      engagementAllowed: false,
    );

    expect(
      () => adapter.classify(response, LessonSupport(evidenceContext: guided)),
      throwsStateError,
    );
  });

  test('stroke memory is bounded, undoable, and clearable', () {
    final controller = HandwritingScratchpadController();

    for (
      var stroke = 0;
      stroke < HandwritingScratchpadController.maxStrokes + 2;
      stroke++
    ) {
      controller.beginStroke(Offset(stroke.toDouble(), 0));
      for (
        var point = 0;
        point < HandwritingScratchpadController.maxPointsPerStroke + 2;
        point++
      ) {
        controller.appendPoint(Offset(stroke.toDouble(), point.toDouble()));
      }
      controller.endStroke();
    }

    expect(controller.strokeCount, HandwritingScratchpadController.maxStrokes);
    expect(
      controller.strokes.every(
        (stroke) =>
            stroke.points.length <=
            HandwritingScratchpadController.maxPointsPerStroke,
      ),
      isTrue,
    );
    controller.undo();
    expect(
      controller.strokeCount,
      HandwritingScratchpadController.maxStrokes - 1,
    );
    controller.clear();
    expect(controller.strokeCount, 0);
    expect(controller.hasHandwriting, isFalse);
  });

  testWidgets(
    'typed alternative sends only a controlled self-check and duplicate submits are idempotent',
    (tester) async {
      final controller = HandwritingScratchpadController();
      final outcomes = <HandwritingSelfCheckOutcome>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingScratchpad(
              controller: controller,
              onSelfCheck: outcomes.add,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'station');
      await tester.ensureVisible(find.text('I checked it'));
      await tester.tap(find.text('I checked it'));
      await tester.pump();
      await tester.tap(find.text('I checked it'));
      await tester.pump();

      expect(outcomes, hasLength(1));
      expect(
        outcomes.single.inputMethod,
        HandwritingInputMethod.typedAlternative,
      );
      expect(outcomes.single.responseCode, 'typed-alternative-self-check');
      expect(outcomes.single.toString(), isNot(contains('station')));
      await tester.tap(find.text('I need more practice'));
      await tester.pump();
      expect(outcomes, hasLength(2));
      expect(
        outcomes.last.selection,
        HandwritingSelfCheckSelection.needsMorePractice,
      );
      expect(
        find.bySemanticsLabel(
          'Handwriting scratchpad. Draw locally; handwriting is not recognized.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shell clears local strokes and typed input on privacy background',
    (tester) async {
      final controller = HandwritingScratchpadController();
      controller.beginStroke(const Offset(1, 1));
      controller.appendPoint(const Offset(2, 2));
      controller.endStroke();

      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedLessonShell(
            builder: (_) =>
                Material(child: HandwritingScratchpad(controller: controller)),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'station');
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(controller.strokeCount, 0);
      expect(find.text('station'), findsNothing);
    },
  );

  testWidgets('route retirement clears externally owned local strokes', (
    tester,
  ) async {
    final controller = HandwritingScratchpadController();
    controller.beginStroke(const Offset(1, 1));
    controller.appendPoint(const Offset(2, 2));
    controller.endStroke();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HandwritingScratchpad(controller: controller)),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    expect(controller.strokeCount, 0);
  });

  testWidgets('controller replacement wipes old strokes and typed text', (
    tester,
  ) async {
    final first = HandwritingScratchpadController();
    final second = HandwritingScratchpadController();
    first.beginStroke(const Offset(1, 1));
    first.endStroke();

    Widget app(HandwritingScratchpadController controller) => MaterialApp(
      home: Scaffold(
        body: HandwritingScratchpad(
          key: const ValueKey('scratchpad'),
          controller: controller,
        ),
      ),
    );

    await tester.pumpWidget(app(first));
    await tester.enterText(find.byType(TextField), 'station');
    await tester.pumpWidget(app(second));
    await tester.pump();

    expect(first.strokeCount, 0);
    expect(second.strokeCount, 0);
    expect(find.text('station'), findsNothing);
  });

  testWidgets('undo becomes available after local handwriting changes', (
    tester,
  ) async {
    final controller = HandwritingScratchpadController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HandwritingScratchpad(controller: controller)),
      ),
    );

    controller.beginStroke(const Offset(1, 1));
    await tester.pump();

    final undo = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Undo stroke'),
    );
    expect(undo.onPressed, isNotNull);
  });

  testWidgets('scratchpad remains usable at narrow 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(body: HandwritingScratchpad()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
    expect(find.text('Type your answer instead'), findsOneWidget);
  });
}
