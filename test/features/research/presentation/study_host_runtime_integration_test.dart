import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/presentation/study_presentations.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/research/application/local_study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/presentation/study_host.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

import '../../../support/study_runtime_harness.dart';

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

  for (final treatment in TodayExperiencePresentation.values) {
    testWidgets(
      '${treatment.name} real runtime captures baseline, one index and post before score',
      (tester) async {
        final fixture = (await tester.runAsync(
          () => StudyRuntimeFixture.open(treatment: treatment, longLived: true),
        ))!;
        try {
          expect(fixture.runtime, isA<LocalStudyRuntime>());
          expect(fixture.runtime.learning, same(fixture.learning));
          final progress = ProgressUseCases(
            owners: fixture.owners,
            queries: DriftProgressQueries(fixture.database),
            nowUtc: () => fixture.participation.clock.now,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: M3Theme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
              home: StudyHost(
                runtime: fixture.runtime,
                ownerId: fixture.ownerId,
                ownerChanges: progress.watchActiveOwnerId(),
              ),
            ),
          );

          final begin = find.byKey(const ValueKey('study-begin'));
          await _waitFor(tester, begin);
          final beforeBegin = (await tester.runAsync(
            () => fixture.researchRows(),
          ))!;
          for (final table in [
            'motivation_measurement_runs',
            'motivation_responses',
            'measurement_opportunities',
            'learning_sessions',
            'answer_attempts',
            'events_v2',
            'outbox_operations',
          ]) {
            expect(beforeBegin[table], isEmpty, reason: table);
          }

          final baselineAt = fixture.participation.clock.now;
          await tester.tap(begin);
          await _chooseResponse(tester, MotivationTimepoint.baseline);
          fixture.participation.clock.now = participationStart.add(
            const Duration(minutes: 1),
          );
          await _continueForm(tester);
          await _waitFor(tester, find.byType(StudyPresentations));
          expect(
            tester
                .widget<StudyPresentations>(find.byType(StudyPresentations))
                .presentation,
            treatment,
          );
          if (treatment == TodayExperiencePresentation.adventure) {
            final node = find.byKey(const ValueKey('study-adventure-node'));
            await _waitForButton(tester, node);
            await tester.ensureVisible(node);
            await tester.tap(node);
            expect(
              find.byKey(const ValueKey('study-standard-mission')),
              findsNothing,
            );
          } else {
            expect(
              find.byKey(const ValueKey('study-standard-mission')),
              findsOneWidget,
            );
          }
          final start = find.byKey(const ValueKey('study-mission-start'));
          await _waitForButton(tester, start);

          final presented = (await tester.runAsync(
            () => fixture.researchRows(),
          ))!;
          expect(presented['learning_sessions'], isEmpty);
          expect(presented['motivation_responses'], hasLength(1));
          expect(presented['measurement_opportunities'], hasLength(1));
          final opportunity = presented['measurement_opportunities']!.single;
          requireMeasurementEntryId(opportunity['entry_attempt_id']! as String);
          expect(opportunity['assigned_treatment'], treatment.wireName);
          expect(opportunity['effective_presentation'], treatment.wireName);
          expect(
            opportunity['presented_at_utc_ms'],
            fixture.participation.clock.now.millisecondsSinceEpoch,
          );
          expect(opportunity['learning_session_id'], isNull);
          expect(presented['events_v2'], hasLength(1));
          expect(
            presented['events_v2']!.single['event_type'],
            measurementPresentedEventType,
          );

          fixture.participation.clock.now = participationStart.add(
            const Duration(minutes: 2),
          );
          await tester.ensureVisible(start);
          await tester.tap(start);
          await _waitFor(tester, find.byType(QuizScreen));
          await _waitFor(tester, find.text('station'));
          final first = (await tester.runAsync(() async {
            final session = (await fixture.rows('learning_sessions')).single;
            return fixture.repository.inspectConfiguredQuiz(
              sessionId: session['id']! as String,
              expectedOwnerId: fixture.ownerId,
            );
          }))!;
          expect(first.plan.mode, 'meaning-quiz');
          expect(
            first.plan.configuration.stableSerialization,
            fixture.catalog.configuration.stableSerialization,
          );
          expect(first.plan.questions, hasLength(1));
          expect(first.startedAtUtc, fixture.participation.clock.now);
          final originalPlan = first.plan.stableSerialization;
          fixture.participation.clock.now = participationStart.add(
            const Duration(minutes: 3),
          );
          await tester.tap(
            find.text(first.plan.questions.single.correctAnswer),
          );
          await _waitFor(tester, find.text('ดูผลการเรียน'));
          final originalEnd = participationStart.add(
            const Duration(minutes: 4),
          );
          fixture.participation.clock.now = originalEnd;
          await tester.tap(find.text('ดูผลการเรียน'));

          final postChoice = find.byKey(
            const ValueKey('measurement-synthetic-post-high'),
          );
          await _waitFor(tester, postChoice);
          expect(find.byType(ScoreScreen, skipOffstage: false), findsNothing);
          final beforePost = (await tester.runAsync(
            () => fixture.researchRows(),
          ))!;
          expect(beforePost['learning_sessions'], hasLength(1));
          expect(beforePost['answer_attempts'], hasLength(1));
          expect(beforePost['motivation_responses'], hasLength(1));
          expect(beforePost['events_v2'], hasLength(3));
          expect(
            beforePost['measurement_opportunities']!.single['is_index_session'],
            1,
          );
          expect(
            beforePost['measurement_opportunities']!.single['closed_at_utc_ms'],
            originalEnd.millisecondsSinceEpoch,
          );
          expect(
            beforePost['learning_sessions']!.single['ended_at_utc_ms'],
            originalEnd.millisecondsSinceEpoch,
          );

          final postAt = participationStart.add(const Duration(minutes: 5));
          fixture.participation.clock.now = postAt;
          await _chooseResponse(tester, MotivationTimepoint.post);
          expect(find.byType(ScoreScreen, skipOffstage: false), findsNothing);
          await _continueForm(tester);
          await _waitFor(tester, find.byType(ScoreScreen));
          final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
          expect(score.correctAnswers, 1);
          expect(score.wrongAnswers, 0);
          expect(score.score, 100);

          final stored = (await tester.runAsync(() => fixture.researchRows()))!;
          expect(stored['learning_sessions'], hasLength(1));
          expect(stored['answer_attempts'], hasLength(1));
          final session = stored['learning_sessions']!.single;
          expect(session['id'], first.sessionId);
          expect(session['owner_id'], fixture.ownerId);
          expect(session['state'], 'completed');
          expect(
            session['ended_at_utc_ms'],
            originalEnd.millisecondsSinceEpoch,
          );
          expect(session['accepted_plan_id'], first.plan.id);
          expect(session['accepted_plan_json'], originalPlan);
          final linked = stored['measurement_opportunities']!.single;
          expect(linked['id'], opportunity['id']);
          expect(linked['entry_attempt_id'], opportunity['entry_attempt_id']);
          expect(linked['learning_session_id'], first.sessionId);
          expect(
            linked['learning_session_started_at_utc_ms'],
            first.startedAtUtc.millisecondsSinceEpoch,
          );
          expect(linked['is_index_session'], 1);
          expect(
            linked['closed_at_utc_ms'],
            originalEnd.millisecondsSinceEpoch,
          );
          expect(stored['motivation_measurement_runs'], hasLength(1));
          final run = stored['motivation_measurement_runs']!.single;
          expect(run['id'], linked['measurement_run_id']);
          expect(run['state'], 'completed');
          expect(run['closed_at_utc_ms'], postAt.millisecondsSinceEpoch);
          expect(stored['motivation_responses'], hasLength(2));
          for (final point in MotivationTimepoint.values) {
            final itemId = 'synthetic-${point.name}';
            final response = stored['motivation_responses']!.singleWhere(
              (row) => row['item_id'] == itemId,
            );
            expect(response['owner_id'], fixture.ownerId);
            expect(response['run_id'], run['id']);
            expect(response['response_code'], 'high');
            expect(
              response['ordinal_value'],
              fixture.authorities.binding.study.instrument
                  .response(itemId, 'high')
                  .ordinalValue,
            );
            expect(
              response['answered_at_utc_ms'],
              (point == MotivationTimepoint.baseline ? baselineAt : postAt)
                  .millisecondsSinceEpoch,
            );
          }
          final events = stored['events_v2']!;
          expect(events, hasLength(3));
          expect(events.map((row) => row['event_type']).toSet(), {
            measurementPresentedEventType,
            measurementMissionStartedEventType,
            measurementMissionCompletedEventType,
          });
          for (final event in events) {
            expect(event['owner_id'], fixture.ownerId);
            expect(event['correlation_id'], opportunity['id']);
            final payload = jsonDecode(event['payload_json']! as String) as Map;
            expect(payload['assignedTreatment'], treatment.wireName);
            expect(payload['effectivePresentation'], treatment.wireName);
            if (event['event_type'] != measurementPresentedEventType) {
              expect(event['aggregate_id'], first.sessionId);
              expect(payload['planId'], first.plan.id);
              expect(payload['opportunityId'], opportunity['id']);
            }
          }
          final ordinary = (await tester.runAsync(
            () async => (
              srs: await fixture.rows('srs_states'),
              unlocks: await fixture.rows('achievement_unlocks'),
            ),
          ))!;
          expect(ordinary.srs, hasLength(1));
          expect(ordinary.srs.single['owner_id'], fixture.ownerId);
          expect(
            ordinary.srs.single['word_id'],
            first.plan.questions.single.word.id,
          );
          expect(ordinary.unlocks, hasLength(4));
          final sessionUnlocks = ordinary.unlocks
              .where((row) => row['source_event_id'] == first.sessionId)
              .toList();
          final answerUnlocks = ordinary.unlocks
              .where(
                (row) =>
                    row['source_event_id'] ==
                    stored['answer_attempts']!.single['id'],
              )
              .toList();
          expect(
            sessionUnlocks.map((row) => row['achievement_id']),
            unorderedEquals(['first_session', 'perfect_session']),
          );
          expect(
            answerUnlocks.map((row) => row['achievement_id']),
            unorderedEquals(['first_answer', 'first_correct']),
          );
          for (final unlock in ordinary.unlocks) {
            expect(unlock['owner_id'], fixture.ownerId);
          }
          expect(
            stored['outbox_operations']!.map(
              (row) => (
                row['owner_id'],
                row['entity_type'],
                row['entity_id'],
                row['payload_version'],
                row['operation_kind'],
              ),
            ),
            unorderedEquals([
              (
                fixture.ownerId,
                'attempt',
                stored['answer_attempts']!.single['id'],
                2,
                'upsert',
              ),
              (
                fixture.ownerId,
                'srsState',
                first.plan.questions.single.word.id,
                1,
                'upsert',
              ),
              for (final unlock in sessionUnlocks)
                (
                  fixture.ownerId,
                  'achievementUnlock',
                  unlock['id'],
                  1,
                  'upsert',
                ),
            ]),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.runAsync(fixture.database.close);
        }
      },
    );
  }
}

Future<void> _chooseResponse(
  WidgetTester tester,
  MotivationTimepoint point,
) async {
  final choice = find.byKey(
    ValueKey('measurement-synthetic-${point.name}-high'),
  );
  await _waitFor(tester, choice);
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await _waitForButton(
    tester,
    find.byKey(const ValueKey('measurement-finish')),
  );
}

Future<void> _continueForm(WidgetTester tester) async {
  final finish = find.byKey(const ValueKey('measurement-finish'));
  await _waitForButton(tester, finish);
  await tester.ensureVisible(finish);
  await tester.tap(finish);
}

Future<void> _waitFor(WidgetTester tester, Finder finder) =>
    _until(tester, () => finder.evaluate().isNotEmpty, finder.toString());

Future<void> _waitForButton(WidgetTester tester, Finder finder) => _until(
  tester,
  () =>
      finder.evaluate().isNotEmpty &&
      tester.widget<FilledButton>(finder).onPressed != null,
  '$finder enabled',
);

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  for (var attempt = 0; attempt < 250; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('Timed out waiting for $description');
}
