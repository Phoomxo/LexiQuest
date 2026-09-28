import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';
import 'native_today_cases.dart' show todayAwait, settleToday, tapToday;
import 'native_recovery_fixture.dart';

void onlyCheckpointAppend(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  final first = before['tableDigests'] as Map;
  final second = after['tableDigests'] as Map;
  expect(second.keys, first.keys);
  for (final table in first.keys) {
    if (table != 'events_v2') {
      expect(
        second[table],
        first[table],
        reason: '$table must not change on replay/advance',
      );
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
}

Future<Map<String, Object?>> runRecoveryPhase(
  WidgetTester tester,
  NativeRecoveryFixture fixture,
  String phase,
) async {
  expect(['seed', 'pending', 'next'], contains(phase));
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
    var lostAfterCommit = false;
    final controller = const MeaningQuizModeAdapter().createReview(
      session: session,
      learning: fixture.learning,
      evidence: deps.currentActivityEvidence!,
      runEvidenceOperation: (operation) async {
        final result =
            await operation(); // Includes durable outer transaction commit.
        if (!result.inserted || !result.isCorrect) {
          throw StateError('BZ canonical result mismatch');
        }
        // Separate disk connection proves persistence outside the writer transaction.
        await fixture.proveCommittedAnswer();
        lostAfterCommit = true;
        throw StateError(
          'BZ synthetic acknowledgement lost AFTER durable outer commit',
        );
      },
    );
    Object? failure;
    await todayAwait(tester, () async {
      try {
        await controller.answer(
          option: controller.currentQuestion.correctOption,
          responseTimeMs: 12,
        );
      } catch (error) {
        failure = error;
      }
    });
    expect(failure, isA<StateError>());
    expect(lostAfterCommit, isTrue);
    expect(controller.phase, MeaningQuizReviewPhase.evidenceRetryRequired);
    controller.dispose();
    final pending = await todayAwait(tester, fixture.snapshot);
    expect(pending['progressPhase'], 'pending');
    expect(pending['index'], 0);
    return {'after': pending, 'lostAcknowledgementAfterCommit': true};
  }
  await todayAwait(
    tester,
    () => fixture.verifySealed(seal: phase == 'pending' ? 'sealed' : 'next'),
  );
  final before = await todayAwait(tester, fixture.snapshot);
  final recovery = await todayAwait(tester, fixture.recover);
  final session = recovery.progress.session;
  expect(
    recovery.progress.phase,
    phase == 'pending' ? 'pending' : 'awaitingAnswer',
  );
  expect(recovery.progress.index, phase == 'pending' ? 0 : 1);
  await tester.pumpWidget(MyApp(dependencies: deps, ownsDependencies: false));
  await settleToday(tester);
  await tapToday(tester, 'home/today');
  expect(find.byType(TodayHubScreen), findsOneWidget);
  final today = await todayAwait(tester, deps.todayHub!.load);
  expect(today.resumableSession!.id, fixture.sessionId);
  await tapToday(tester, 'today-hub-resume-action');
  expect(find.byType(QuizScreen), findsOneWidget);
  final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
  expect(screen.attachedSession!.id, session.id);
  expect(screen.attachedSession!.ownerId, fixture.ownerId);
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
  expect(
    find.text(
      session.ordinaryMeaningPlan!.questions[recovery.progress.index].prompt,
    ),
    findsOneWidget,
  );
  expect(
    await todayAwait(tester, fixture.snapshot),
    before,
    reason: 'Bootstrap and navigation must preserve every row',
  );
  if (phase == 'next') {
    expect(find.byType(AnswerFeedbackPanel), findsNothing);
    expect(find.byKey(const ValueKey('current-evidence-retry')), findsNothing);
    return {'before': before, 'after': before};
  }
  expect(find.byKey(const ValueKey('current-evidence-retry')), findsOneWidget);
  await tapToday(tester, 'current-evidence-retry');
  expect(find.byType(AnswerFeedbackPanel), findsOneWidget);
  final feedback = tester
      .widget<AnswerFeedbackPanel>(find.byType(AnswerFeedbackPanel))
      .feedback;
  expect(feedback.isCorrect, isTrue);
  expect(
    feedback.canonicalCorrectAnswer,
    session.ordinaryMeaningPlan!.questions.first.correctOption,
  );
  final replayed = await todayAwait(tester, fixture.snapshot);
  expect(replayed['progressPhase'], 'answered');
  expect(replayed['operation'], before['operation']);
  onlyCheckpointAppend(before, replayed);
  await tapToday(tester, 'meaning-quiz-next');
  final next = await todayAwait(tester, fixture.snapshot);
  expect(next['index'], 1);
  expect(next['progressPhase'], 'awaitingAnswer');
  expect(find.byType(AnswerFeedbackPanel), findsNothing);
  expect(
    find.text(session.ordinaryMeaningPlan!.questions[1].prompt),
    findsOneWidget,
  );
  onlyCheckpointAppend(replayed, next);
  return {'before': before, 'replayed': replayed, 'after': next};
}
