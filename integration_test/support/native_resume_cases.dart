import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'native_baseline_cases.dart' show baselineAwait;
import 'native_resume_fixture.dart';

Future<T> resumeAwait<T>(WidgetTester tester, Future<T> Function() action) =>
    baselineAwait(tester, action);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> runResumePhase(
  WidgetTester tester,
  NativeResumeFixture fixture, {
  required bool seedPhase,
}) async {
  final session = seedPhase
      ? await resumeAwait(tester, fixture.seed)
      : (await resumeAwait(tester, fixture.recover)).progress.session;
  expect(session.ownerId, fixture.ownerId);
  expect(session.id, fixture.sessionId);
  await tester.pumpWidget(
    MaterialApp(
      home: QuizScreen(
        learning: fixture.learning,
        evidenceAdapter: CurrentActivityEvidenceAdapter(
          learning: fixture.learning,
        ),
        attachedSession: session,
        ordinaryAcceptance: () => true,
      ),
    ),
  );
  await _settle(tester);
  expect(find.byType(QuizScreen), findsOneWidget);
  final first = session.ordinaryMeaningPlan!.questions.first;
  expect(find.text(first.prompt), findsOneWidget);
  if (seedPhase) {
    expect(find.byType(AnswerFeedbackPanel), findsNothing);
    final option = find.byKey(
      ValueKey('meaning-quiz-option-${first.word.id}-${first.correctOption}'),
    );
    expect(option, findsOneWidget);
    await tester.ensureVisible(option);
    await tester.tap(option);
    await _settle(tester);
  }
  expect(find.byType(AnswerFeedbackPanel), findsOneWidget);
  expect(
    tester
        .widget<AnswerFeedbackPanel>(find.byType(AnswerFeedbackPanel))
        .feedback
        .isCorrect,
    isTrue,
  );
  expect(find.byKey(const ValueKey('meaning-quiz-next')), findsOneWidget);
  // Replayed committed feedback must not change any table, score, SRS or reward.
  if (!seedPhase) await resumeAwait(tester, fixture.verifySealed);
}
