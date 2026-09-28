import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';
import 'native_today_cases.dart' show todayAwait, settleToday, tapToday;
import 'native_terminal_fixture.dart';

void onlyTerminalAcknowledgement(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  final first = before['tableDigests'] as Map;
  final second = after['tableDigests'] as Map;
  expect(second.keys, first.keys);
  for (final table in first.keys) {
    if (table != 'events_v2') {
      expect(second[table], first[table], reason: '$table must not change');
    }
  }
  expect(
    after['nonCheckpointEventsDigest'],
    before['nonCheckpointEventsDigest'],
  );
  expect(after['answerRows'], before['answerRows']);
  final oldRows = before['checkpointRows'] as List;
  final newRows = after['checkpointRows'] as List;
  expect(newRows.length, oldRows.length + 1);
  for (final row in oldRows) {
    expect(newRows, contains(equals(row)));
  }
  expect(after['ownerId'], before['ownerId']);
  expect(after['sessionId'], before['sessionId']);
  expect(after['planDigest'], before['planDigest']);
  expect(after['terminalAcknowledged'], isTrue);
}

Future<Map<String, Object?>> runTerminalPhase(
  WidgetTester tester,
  NativeTerminalFixture fixture,
  String phase,
) async {
  expect(['seed', 'resume', 'closed'], contains(phase));
  final deps = fixture.dependencies;
  expect(
    const BuildFeatureRegistry.fieldDefaults().isEnabled(
      Feature.dailyContinuity,
    ),
    isFalse,
  );
  expect(deps.features.isEnabled(Feature.dailyContinuity), isTrue);
  expect(deps.features.isEnabled(Feature.researchAssessment), isFalse);
  if (phase == 'seed') {
    final session = await todayAwait(tester, fixture.seed);
    var observedCommittedClose = false;
    final controller = const MeaningQuizModeAdapter().createReview(
      session: session,
      learning: fixture.learning,
      evidence: deps.currentActivityEvidence!,
      completeSession: (close) async {
        final summary = await close.finish();
        if (summary.state != 'completed') {
          throw StateError('Canonical close did not complete');
        }
        await fixture.proveCommittedClose();
        observedCommittedClose = true;
        throw StateError(
          'CA synthetic close acknowledgement lost AFTER durable commit',
        );
      },
    );
    await todayAwait(
      tester,
      () => controller.answer(
        option: controller.currentQuestion.correctOption,
        responseTimeMs: 12,
      ),
    );
    Object? failure;
    await todayAwait(tester, () async {
      try {
        await controller.advance();
      } catch (error) {
        failure = error;
      }
    });
    expect(failure, isA<StateError>());
    expect(observedCommittedClose, isTrue);
    expect(controller.phase, MeaningQuizReviewPhase.completionRetryRequired);
    controller.dispose();
    final closing = await todayAwait(tester, fixture.snapshot);
    expect(closing['progressPhase'], 'closing');
    expect(closing['terminalAcknowledged'], isFalse);
    expect(closing['index'], 0);
    return {'after': closing, 'lostAcknowledgementAfterCommit': true};
  }
  await todayAwait(
    tester,
    () => fixture.verifySealed(seal: phase == 'resume' ? 'sealed' : 'closed'),
  );
  final before = await todayAwait(tester, fixture.snapshot);
  if (phase == 'closed') {
    expect(before['terminalAcknowledged'], isTrue);
    final today = await todayAwait(tester, deps.todayHub!.load);
    expect(today.resumableSession, isNull);
    await tester.pumpWidget(MyApp(dependencies: deps, ownsDependencies: false));
    await settleToday(tester);
    await tapToday(tester, 'home/today');
    expect(find.byType(TodayHubScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('today-hub-resume-action')), findsNothing);
    expect(await todayAwait(tester, fixture.snapshot), before);
    return {'before': before, 'after': before};
  }
  final recovery = await todayAwait(tester, fixture.recover);
  expect(recovery.progress.phase, 'closing');
  expect(recovery.progress.index, 0);
  await tester.pumpWidget(MyApp(dependencies: deps, ownsDependencies: false));
  await settleToday(tester);
  await tapToday(tester, 'home/today');
  expect(find.byType(TodayHubScreen), findsOneWidget);
  final today = await todayAwait(tester, deps.todayHub!.load);
  expect(today.resumableSession!.id, fixture.sessionId);
  await tapToday(tester, 'today-hub-resume-action');
  expect(find.byType(QuizScreen), findsOneWidget);
  final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
  expect(screen.attachedSession!.id, fixture.sessionId);
  expect(screen.attachedSession!.ownerId, fixture.ownerId);
  expect(
    screen.attachedSession!.ordinaryMeaningPlan!.toJson(),
    recovery.progress.plan.toJson(),
  );
  expect(
    tester
        .widget<NavigationBar>(find.byType(NavigationBar, skipOffstage: false))
        .selectedIndex,
    1,
  );
  expect(
    find.text(recovery.progress.plan.questions.first.prompt),
    findsOneWidget,
  );
  expect(
    await todayAwait(tester, fixture.snapshot),
    before,
    reason: 'Bootstrap and navigation must preserve all tables',
  );
  expect(find.byKey(const ValueKey('current-evidence-retry')), findsOneWidget);
  await tapToday(tester, 'current-evidence-retry');
  expect(find.byType(ScoreScreen), findsOneWidget);
  final after = await todayAwait(tester, fixture.snapshot);
  onlyTerminalAcknowledgement(before, after);
  expect(
    (await todayAwait(tester, deps.todayHub!.load)).resumableSession,
    isNull,
  );
  return {'before': before, 'after': after};
}
