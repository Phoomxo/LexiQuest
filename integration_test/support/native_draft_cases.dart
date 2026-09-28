import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/ordinary_meaning_recovery.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';
import 'native_today_cases.dart' show todayAwait, settleToday, tapToday;
import 'native_draft_fixture.dart';

Future<Map<String, Object?>> runDraftPhase(
  WidgetTester tester,
  NativeDraftFixture fixture,
  String phase,
) async {
  expect(['seed', 'resume'], contains(phase));
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
    final controller = const MeaningQuizModeAdapter().createReview(
      session: session,
      learning: fixture.learning,
      evidence: CurrentActivityEvidenceAdapter(
        learning: fixture.learning,
        rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
      ),
    );
    final selected = controller.currentQuestion.correctOption;
    Object? failure;
    await todayAwait(tester, () async {
      try {
        await controller.answer(option: selected, responseTimeMs: 12);
      } catch (error) {
        failure = error;
      }
    });
    expect(failure, isA<StateError>());
    controller.dispose();
    final draft = await todayAwait(tester, fixture.snapshot);
    expect(draft['progressPhase'], 'awaitingAnswer');
    expect(draft['selected'], selected);
    expect(draft['answerRows'], isEmpty);
    expect((draft['checkpointRows'] as List).length, 2);
    return {'after': draft, 'syntheticPreCommitFailure': true};
  }
  await todayAwait(tester, fixture.verifySealed);
  final before = await todayAwait(tester, fixture.snapshot);
  final recovery = await todayAwait(tester, fixture.recover);
  expect(recovery.progress.phase, 'awaitingAnswer');
  expect(recovery.progress.index, 0);
  expect(recovery.progress.selected, before['selected']);
  Object? wrongOwner;
  Object? wrongSession;
  await todayAwait(tester, () async {
    try {
      await OrdinaryMeaningRecovery.load(
        learning: fixture.learning,
        ownerId: 'local:synthetic-other-owner',
        sessionId: fixture.sessionId,
      );
    } catch (error) {
      wrongOwner = error;
    }
    try {
      await OrdinaryMeaningRecovery.load(
        learning: fixture.learning,
        ownerId: fixture.ownerId,
        sessionId: 'session:synthetic-stale-session',
      );
    } catch (error) {
      wrongSession = error;
    }
  });
  expect(wrongOwner, isA<StateError>());
  expect(wrongSession, isA<StateError>());
  expect(await todayAwait(tester, fixture.snapshot), before);
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
  final question = recovery.progress.plan.questions.first;
  expect(find.text(question.prompt), findsOneWidget);
  expect(find.byKey(const ValueKey('current-evidence-retry')), findsNothing);
  expect(find.byKey(const ValueKey('meaning-quiz-next')), findsNothing);
  final option = tester.widget<FilledButton>(
    find.byKey(
      ValueKey('meaning-quiz-option-${question.word.id}-${before['selected']}'),
    ),
  );
  expect(option.onPressed, isNotNull);
  expect(
    option.style!.backgroundColor!.resolve(<WidgetState>{}),
    Theme.of(
      tester.element(find.byType(QuizScreen)),
    ).colorScheme.primaryContainer,
  );
  final after = await todayAwait(tester, fixture.snapshot);
  expect(
    after,
    before,
    reason: 'Bootstrap and Today draft restore must preserve all 58 tables',
  );
  return {
    'before': before,
    'after': after,
    'wrongOwnerRejected': true,
    'wrongSessionRejected': true,
  };
}
