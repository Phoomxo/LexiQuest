
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/matching_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';
import 'package:vocab_learning_app/screens/matching_quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/configured_quiz_harness.dart';
import '../support/motivation_presentation_io.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'ChooseMode starts actual Matching and completed History rereads canonical Score purely',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.open))!;
      try {
        await tester.pumpWidget(f.app(const ChooseModeScreen()));
        expect(
          await motivationPresentationIo(
            tester,
            () => f.h.count('learning_sessions'),
          ),
          0,
        );
        await _tap(tester, 'matching-entry');
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('matching-word-0'))
              .evaluate()
              .isNotEmpty,
        );
        for (var index = 0; index < 4; index++) {
          await _tap(tester, 'matching-word-$index');
          await _tap(tester, 'matching-meaning-$index');
          await _tap(tester, 'matching-check');
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('matching-continue'))
                .evaluate()
                .isNotEmpty,
          );
          await _tap(tester, 'matching-continue');
          if (index < 3) {
            await _wait(
              tester,
              () => find
                  .byKey(const ValueKey('matching-check'))
                  .evaluate()
                  .isNotEmpty,
            );
          }
        }
        await _wait(
          tester,
          () => find.byType(ScoreScreen).evaluate().isNotEmpty,
        );
        final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
        expect(
          (score.correctAnswers, score.wrongAnswers, score.score),
          (4, 0, 100),
        );
        Navigator.of(tester.element(find.byType(ScoreScreen))).pop();
        await tester.pumpAndSettle();
        final beforeHistory = await motivationPresentationIo(
          tester,
          f.h.snapshot,
        );
        await tester.pumpWidget(f.app(const LearningHistoryScreen()));
        await _wait(tester, () => find.text('ดูผล').evaluate().isNotEmpty);
        await tester.ensureVisible(find.text('ดูผล'));
        await tester.tap(find.text('ดูผล'));
        await _wait(
          tester,
          () => find.byType(ScoreScreen).evaluate().isNotEmpty,
        );
        expect(tester.widget<ScoreScreen>(find.byType(ScoreScreen)).score, 100);
        expect(
          await motivationPresentationIo(tester, f.h.snapshot),
          beforeHistory,
        );
        expect(
          await motivationPresentationIo(tester, f.h.researchCounts),
          valuesEveryElement(0),
        );
        for (final table in [
          'srs_states',
          'points_ledger_entries',
          'achievement_unlocks',
          'reward_transactions',
          'learning_day_log',
        ]) {
          expect(
            await motivationPresentationIo(tester, () => f.h.count(table)),
            0,
          );
        }
      } finally {
        await closeMotivationPresentation(tester, f.h.close);
      }
    },
  );

  testWidgets(
    'History resumes the exact acknowledged Matching selection without a second session',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.open))!;
      try {
        final sessionId = await motivationPresentationIo(tester, () async {
          final plan = (await f.matching.prepare(
            expectedOwnerId: configuredOwnerId,
            categoryId: configuredCategoryId,
            stillCurrent: () => true,
          ))!;
          final state = await f.matching.start(plan, stillCurrent: () => true);
          await f.matching.saveSelection(
            state,
            wordIndex: 2,
            meaningIndex: 1,
            stillCurrent: () => true,
          );
          return plan.session.id;
        });
        final before = await motivationPresentationIo(tester, f.h.snapshot);
        await tester.pumpWidget(f.app(const LearningHistoryScreen()));
        await _wait(tester, () => find.text('เล่นต่อ').evaluate().isNotEmpty);
        await tester.ensureVisible(find.text('เล่นต่อ'));
        await tester.tap(find.text('เล่นต่อ'));
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('matching-check'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.byType(MatchingQuizScreen), findsOneWidget);
        expect(
          tester
              .widget<MatchingQuizScreen>(find.byType(MatchingQuizScreen))
              .resumeSessionId,
          sessionId,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('matching-check')),
              )
              .onPressed,
          isNotNull,
        );
        expect(await motivationPresentationIo(tester, f.h.snapshot), before);
      } finally {
        await closeMotivationPresentation(tester, f.h.close);
      }
    },
  );
}

Matcher valuesEveryElement(Object expected) => predicate<Map<String, int>>(
  (rows) => rows.values.every((value) => value == expected),
  'all Research rows unchanged',
);

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target.hitTestable());
  await tester.pump();
}

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var frame = 0; frame < 200; frame++) {
    await motivationPresentationDeadline(
      tester,
      'matching-flow/frame',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (done()) return;
  }
  fail('Actual Matching entry or History did not become ready');
}

final class _Fixture {
  _Fixture(this.h, this.matching, this.dependencies);
  final ConfiguredQuizHarness h;
  final MatchingUseCases matching;
  final AppDependencies dependencies;
  static Future<_Fixture> open() async {
    final h = await ConfiguredQuizHarness.open();
    final canonical = DriftLearningRepository(
      h.database,
      ownerWrites: h.ownerWrites,
    );
    var ids = 0;
    String id() => 'synthetic-matching-entry-${++ids}';
    const build = AppBuildInfo(
      version: 'synthetic',
      buildId: 'synthetic-matching-entry',
    );
    final matching = MatchingUseCases(
      repository: DriftMatchingRepository(canonical),
      generateId: id,
      nowUtc: () => h.now,
      buildInfo: build,
    );
    final progress = ProgressUseCases(
      owners: h.owners,
      queries: DriftProgressQueries(h.database),
      nowUtc: () => h.now,
    );
    return _Fixture(
      h,
      matching,
      AppDependencies(
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _NoGuest(),
        database: h.database,
        localOwners: h.owners,
        matching: matching,
        progress: progress,
        learning: LearningUseCases(
          owners: h.owners,
          repository: canonical,
          generateId: id,
          nowUtc: () => h.now,
          buildInfo: build,
        ),
      ),
    );
  }

  Widget app(Widget home) => AppDependenciesScope(
    dependencies: dependencies,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    ),
  );
}

final class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('Synthetic Matching must not authenticate');
}
