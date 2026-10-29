import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/presentation/motivation_measurement_form.dart';
import 'package:vocab_learning_app/features/research/presentation/study_host.dart';
import 'package:vocab_learning_app/screens/pre_post_assessment_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';

import '../../support/assessment_study_harness.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  setUpAll(() async {
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
  });

  for (final assessmentFirst in [true, false]) {
    testWidgets(
      '${assessmentFirst ? 'Assessment' : 'Motivation'} can be chosen first and opening waits for both',
      (tester) async {
        final f = (await tester.runAsync(AssessmentStudyFixture.open))!;
        try {
          f.attach();
          await _mount(tester, f);
          final choose = find.byKey(
            ValueKey(
              assessmentFirst
                  ? 'study-choose-assessment'
                  : 'study-choose-motivation',
            ),
          );
          await _waitButton(tester, choose);
          await tester.tap(choose);
          if (assessmentFirst) {
            await _finishAssessment(tester);
            await _until(
              tester,
              () =>
                  find.byType(MotivationMeasurementForm).evaluate().isNotEmpty,
              'remaining Motivation baseline',
            );
            expect(
              await tester.runAsync(
                () => f.authorities.study.rows('measurement_opportunities'),
              ),
              isEmpty,
            );
            await _finishMotivation(tester, MotivationTimepoint.baseline);
          } else {
            await _finishMotivation(tester, MotivationTimepoint.baseline);
            await _until(
              tester,
              () => find.byType(PrePostAssessmentScreen).evaluate().isNotEmpty,
              'remaining Assessment pre',
            );
            expect(
              await tester.runAsync(
                () => f.authorities.study.rows('measurement_opportunities'),
              ),
              isEmpty,
            );
            await _finishAssessment(tester);
          }
          await _until(
            tester,
            () => find
                .byKey(const ValueKey('study-standard-mission'))
                .evaluate()
                .isNotEmpty,
            'first actual presentation',
          );
          await _waitButton(
            tester,
            find.byKey(const ValueKey('study-mission-start')),
          );
          final runs = (await tester.runAsync(
            () => f.authorities.study.rows('assessment_runs'),
          ))!;
          expect(runs, hasLength(1));
          expect(runs.single['id'], f.command(AssessmentPhase.pre).runId);
          expect(runs.single['state'], 'completed');
          expect(
            await tester.runAsync(
              () => f.authorities.study.rows('measurement_opportunities'),
            ),
            hasLength(1),
          );
          expect(
            await tester.runAsync(() => f.authorities.study.rows('srs_states')),
            isEmpty,
          );
          expect(
            await tester.runAsync(
              () => f.authorities.study.rows('points_ledger_entries'),
            ),
            isEmpty,
          );
          expect(
            await tester.runAsync(
              () => f.authorities.study.rows('outbox_operations'),
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await _close(tester, f);
        }
      },
    );
  }

  testWidgets(
    'actual Host canonical-finish callback returns without offering Assessment-only post',
    (tester) async {
      final f = (await tester.runAsync(AssessmentStudyFixture.open))!;
      final routes = _Routes();
      try {
        f.attach();
        await tester.runAsync(() => f.completeAssessment(AssessmentPhase.pre));
        await tester.runAsync(
          () => f.recordMotivation(MotivationTimepoint.baseline),
        );
        await tester.runAsync(f.openPresentation);
        await _mount(tester, f, observer: routes);
        final start = find.byKey(const ValueKey('study-mission-start'));
        await _waitButton(tester, start);
        await tester.ensureVisible(start);
        await tester.tap(start);
        await _until(
          tester,
          () => find.byType(QuizScreen).evaluate().isNotEmpty,
          'actual canonical Quiz route',
        );
        final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
        final result = (await tester.runAsync(() async {
          final study = f.authorities.study;
          final active = await study.runtime.resumeIndex(study.ownerId);
          f.authorities.advance(const Duration(minutes: 2));
          final completed = await study.finish(active);
          await f.recordMotivation(MotivationTimepoint.post);
          return study.learning.finishConfiguredQuiz(
            sessionId: completed.sessionId,
            expectedOwnerId: study.ownerId,
            expectedRevision: completed.checkpointRevision,
          );
        }))!;
        final before = (await tester.runAsync(
          () => f.authorities.study.rows('outbox_operations'),
        ))!;
        var returned = false;
        await tester.runAsync(() async {
          final pending = quiz.onCanonicalFinished!(result).then(
            (_) => returned = true,
          );
          pending.ignore();
        });
        await _until(
          tester,
          () => returned,
          'Motivation-only post callback return',
        );
        expect(routes.names.where((name) => name == 'study/post'), isEmpty);
        expect(find.byType(PrePostAssessmentScreen), findsNothing);
        expect(find.byType(MotivationMeasurementForm), findsNothing);
        expect(find.byType(QuizScreen), findsOneWidget);
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('outbox_operations'),
          ),
          before,
        );

        // Assessment post remains explicit in the Study route, after returning
        // from the canonical quiz. No form is inserted into its Score callback.
        final quizContext = tester.element(find.byType(QuizScreen));
        Navigator.of(quizContext).pop();
        await _until(
          tester,
          () => find.byType(PrePostAssessmentScreen).evaluate().isNotEmpty,
          'explicit Study Assessment post',
        );
        await _finishAssessment(tester);
        final compare = find.byKey(const ValueKey('study-assessment-compare'));
        await _waitButton(tester, compare);
        await tester.ensureVisible(compare);
        await tester.tap(compare);
        await _until(
          tester,
          () =>
              find.textContaining('ผลต่างจำนวนคำตอบถูก').evaluate().isNotEmpty,
          'descriptive actual pair comparison',
        );
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('assessment_runs'),
          ),
          hasLength(2),
        );
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('learning_sessions'),
          ),
          hasLength(3),
        );
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('outbox_operations'),
          ),
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, f);
      }
    },
  );

  testWidgets(
    'hidden ready form is replaced by a fresh guarded form after resume',
    (tester) async {
      final f = (await tester.runAsync(AssessmentStudyFixture.open))!;
      try {
        f.attach();
        await _mount(tester, f);
        final choose = find.byKey(const ValueKey('study-choose-assessment'));
        await _waitButton(tester, choose);
        await tester.tap(choose);
        final option = find.byKey(
          const ValueKey(
            'assessment-option-synthetic-assessment-item-synthetic yes',
          ),
        );
        await _until(
          tester,
          () => option.evaluate().isNotEmpty,
          'first ready Assessment form',
        );
        final original = tester.element(find.byType(PrePostAssessmentScreen));
        final beforePause = (await tester.runAsync(
          f.authorities.study.researchRows,
        ))!;
        final runsBeforePause = (await tester.runAsync(
          () => f.authorities.study.rows('assessment_runs'),
        ))!;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(binding.lifecycleState, AppLifecycleState.paused);
        expect(binding.framesEnabled, isFalse);
        binding.scheduleForcedFrame();
        await tester.pump();
        expect(option, findsNothing);
        expect(find.byKey(const ValueKey('assessment-submit')), findsNothing);
        expect(
          find.text(f.authorities.definition.items.single.prompt),
          findsNothing,
        );
        expect(
          await tester.runAsync(f.authorities.study.researchRows),
          beforePause,
        );
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('assessment_runs'),
          ),
          runsBeforePause,
        );
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('answer_attempts'),
          ),
          isEmpty,
        );
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await _waitButton(tester, choose);
        await tester.tap(choose);
        await _until(
          tester,
          () => option.evaluate().isNotEmpty,
          'fresh ready Assessment form',
        );
        expect(
          identical(
            tester.element(find.byType(PrePostAssessmentScreen)),
            original,
          ),
          isFalse,
        );
        await _finishAssessment(tester);
        await _until(
          tester,
          () => find.byType(MotivationMeasurementForm).evaluate().isNotEmpty,
          'remaining form after confirmed completion',
        );
        final rows = (await tester.runAsync(
          () => f.authorities.study.rows('assessment_runs'),
        ))!;
        expect(rows, hasLength(1));
        expect(rows.single['state'], 'completed');
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('answer_attempts'),
          ),
          hasLength(1),
        );
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('measurement_opportunities'),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, f);
      }
    },
  );

  testWidgets(
    'owner transition during actual Assessment content read hides form and creates no answer',
    (tester) async {
      final f = (await tester.runAsync(AssessmentStudyFixture.open))!;
      final release = Completer<void>();
      var entered = false;
      try {
        f.attach();
        f.content.onRead = () async {
          entered = true;
          await release.future;
        };
        await _mount(tester, f);
        final choose = find.byKey(const ValueKey('study-choose-assessment'));
        await _waitButton(tester, choose);
        await tester.tap(choose);
        await _until(tester, () => entered, 'actual Assessment form read');
        await tester.runAsync(
          () => f.authorities.study.database.customUpdate(
            "UPDATE local_owners SET is_active = CASE WHEN id = 'owner-b' THEN 1 ELSE 0 END",
            updates: {f.authorities.study.database.localOwners},
          ),
        );
        await _until(
          tester,
          () =>
              (find
                      .byKey(const ValueKey('assessment-submit'))
                      .evaluate()
                      .isEmpty &&
                  find
                      .byKey(const ValueKey('assessment-exit'))
                      .evaluate()
                      .isNotEmpty) ||
              find.textContaining('บัญชีเปลี่ยนแล้ว').evaluate().isNotEmpty,
          'old owner private controls unavailable',
        );
        expect(
          find.text(f.authorities.definition.items.single.prompt),
          findsNothing,
        );
        release.complete();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('assessment_runs'),
          ),
          isEmpty,
        );
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('answer_attempts'),
          ),
          isEmpty,
        );
        expect(
          await tester.runAsync(
            () => f.authorities.study.rows('measurement_opportunities'),
          ),
          isEmpty,
        );
        expect(
          find.byKey(const ValueKey('study-ordinary-exit')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!release.isCompleted) release.complete();
        await _close(tester, f);
      }
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  AssessmentStudyFixture f, {
  _Routes? observer,
}) async {
  final study = f.authorities.study;
  final progress = ProgressUseCases(
    owners: study.owners,
    queries: DriftProgressQueries(study.database),
    nowUtc: () => study.participation.clock.now,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: M3Theme.lightTheme,
      navigatorObservers: [?observer],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: StudyHost(
        runtime: study.runtime,
        ownerId: study.ownerId,
        ownerChanges: progress.watchActiveOwnerId(),
      ),
    ),
  );
}

Future<void> _finishAssessment(WidgetTester tester) async {
  final option = find.byKey(
    const ValueKey('assessment-option-synthetic-assessment-item-synthetic yes'),
  );
  await _until(
    tester,
    () => option.evaluate().isNotEmpty,
    'supplied controlled Assessment option',
  );
  await tester.ensureVisible(option);
  await _until(
    tester,
    () =>
        option.hitTestable().evaluate().isNotEmpty &&
        tester.widget<RadioListTile<String>>(option).enabled == true,
    'controlled Assessment option receives actual taps',
  );
  await tester.tap(option);
  await tester.pump();
  final submit = find.byKey(const ValueKey('assessment-submit'));
  await _waitButton(tester, submit);
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  final finish = find.byKey(const ValueKey('assessment-finish'));
  await _waitButton(tester, finish);
  await tester.ensureVisible(finish);
  await tester.tap(finish);
}

Future<void> _finishMotivation(
  WidgetTester tester,
  MotivationTimepoint point,
) async {
  final option = find.byKey(
    ValueKey('measurement-synthetic-${point.name}-high'),
  );
  await _until(
    tester,
    () => option.evaluate().isNotEmpty,
    'supplied Motivation option',
  );
  await tester.ensureVisible(option);
  await tester.tap(option);
  final finish = find.byKey(const ValueKey('measurement-finish'));
  await _waitButton(tester, finish);
  await tester.ensureVisible(finish);
  await tester.tap(finish);
}

Future<void> _waitButton(WidgetTester tester, Finder finder) => _until(
  tester,
  () =>
      finder.evaluate().isNotEmpty &&
      tester.widget<ButtonStyleButton>(finder).onPressed != null,
  '$finder enabled',
);
Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  for (var count = 0; count < 250; count++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('Timed out waiting for $description');
}

Future<void> _close(WidgetTester tester, AssessmentStudyFixture f) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(f.close);
}

final class _Routes extends NavigatorObserver {
  final names = <String?>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    names.add(route.settings.name);
    super.didPush(route, previousRoute);
  }
}
