import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'native_baseline_cases.dart' show baselineAwait;
import 'native_today_fixture.dart';

Future<T> todayAwait<T>(WidgetTester tester, Future<T> Function() action) =>
    baselineAwait(tester, action);
Future<void> settleToday(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> tapToday(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await settleToday(tester);
  await tester.tap(target);
  await settleToday(tester);
}

Future<void> runTodayPhase(
  WidgetTester tester,
  NativeTodayFixture fixture, {
  required bool seedPhase,
}) async {
  final deps = fixture.dependencies;
  expect(
    const BuildFeatureRegistry.fieldDefaults().isEnabled(
      Feature.dailyContinuity,
    ),
    isFalse,
  );
  expect(deps.features.isEnabled(Feature.dailyContinuity), isTrue);
  expect(deps.features.isEnabled(Feature.researchAssessment), isFalse);
  final session = seedPhase
      ? await todayAwait(tester, fixture.seed)
      : (await todayAwait(tester, fixture.recover)).progress.session;
  expect(session.id, fixture.sessionId);
  expect(session.ownerId, fixture.ownerId);
  await tester.pumpWidget(MyApp(dependencies: deps, ownsDependencies: false));
  await settleToday(tester);
  await tapToday(tester, 'home/today');
  expect(find.byType(TodayHubScreen), findsOneWidget);
  final today = await todayAwait(tester, deps.todayHub!.load);
  expect(today.ownerId, fixture.ownerId);
  expect(today.resumableSession!.id, fixture.sessionId);
  await tapToday(tester, 'today-hub-resume-action');
  expect(find.byType(QuizScreen), findsOneWidget);
  final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
  expect(screen.attachedSession!.id, session.id);
  expect(screen.attachedSession!.ownerId, session.ownerId);
  expect(
    screen.attachedSession!.ordinaryMeaningPlan!.toJson(),
    session.ordinaryMeaningPlan!.toJson(),
  );
  expect(
    tester
        .widget<NavigationBar>(find.byType(NavigationBar, skipOffstage: false))
        .selectedIndex,
    1,
  );
  final first = session.ordinaryMeaningPlan!.questions.first;
  expect(find.text(first.prompt), findsOneWidget);
  if (seedPhase) {
    expect(find.byType(AnswerFeedbackPanel), findsNothing);
    await tapToday(
      tester,
      'meaning-quiz-option-${first.word.id}-${first.correctOption}',
    );
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
  if (!seedPhase) await todayAwait(tester, fixture.verifySealed);
}
