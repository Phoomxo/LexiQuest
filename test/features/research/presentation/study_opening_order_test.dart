import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/presentation/study_presentations.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_timing_reader.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/presentation/study_host.dart';

import '../../../support/study_runtime_harness.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  for (final treatment in TodayExperiencePresentation.values) {
    testWidgets('$treatment cannot render before durable opening commits', (
      tester,
    ) async {
      final queries = StudyReadQueries();
      final fixture = (await tester.runAsync(
        () => StudyRuntimeFixture.open(
          treatment: treatment,
          database: AppDatabase(NativeDatabase.memory().interceptWith(queries)),
        ),
      ))!;
      final reached = Completer<void>();
      final release = Completer<void>();
      try {
        await tester.runAsync(fixture.baseline);
        queries.afterOpportunityInsert = () async {
          if (!reached.isCompleted) reached.complete();
          await release.future;
        };
        await tester.pumpWidget(
          MaterialApp(
            home: StudyHost(runtime: fixture.runtime, ownerId: fixture.ownerId),
          ),
        );
        await _until(tester, () => reached.isCompleted);
        expect(
          find.byType(StudyPresentations),
          findsNothing,
          reason: 'The actual opportunity INSERT has not committed yet',
        );
        release.complete();
        await _until(
          tester,
          () => find.byType(StudyPresentations).evaluate().isNotEmpty,
        );
        for (var attempt = 0; attempt < 100; attempt++) {
          final events = await tester.runAsync(() => fixture.rows('events_v2'));
          if (events!.length == 1) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        final rows = await tester.runAsync(fixture.researchRows);
        expect(rows!['measurement_opportunities'], hasLength(1));
        expect(rows['events_v2'], hasLength(1));
        expect(rows['learning_sessions'], isEmpty);
      } finally {
        if (!release.isCompleted) release.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(fixture.database.close);
      }
    });
  }

  for (final restart in [false, true]) {
    test(
      'unresolved raw opening is unavailable on ordinary load, restart=$restart',
      () async {
        final fixture = await StudyRuntimeFixture.open();
        try {
          final baseline = await fixture.baseline();
          final measurements =
              fixture.runtime.measurementsFor(fixture.ownerId)
                  as DriftMotivationMeasurementRepository;
          await DriftMeasurementOpportunityRepository(
            fixture.database,
            measurements: measurements,
            timing:
                measurements.timing as DriftMotivationMeasurementTimingReader,
          ).open(
            ownerId: fixture.ownerId,
            measurementRunId: baseline.run!.id,
            entryAttemptId: studyEntryId,
            effectivePresentation: TodayExperiencePresentation.standard,
          );
          final before = await fixture.researchRows();
          if (restart) fixture.restartRuntime();
          expect(
            (await fixture.runtime.load(fixture.ownerId)).phase,
            StudyPhase.unavailable,
          );
          expect(await fixture.researchRows(), before);
        } finally {
          await fixture.database.close();
        }
      },
    );
  }

  testWidgets(
    'real prepare authority denial renders no target and leaves no opening',
    (tester) async {
      final fixture = (await tester.runAsync(StudyRuntimeFixture.open))!;
      try {
        await tester.runAsync(fixture.baseline);
        fixture.participation.states.onRead = (_) async {
          if ((await fixture.rows('measurement_opportunities')).isNotEmpty) {
            fixture.participation.states.revoked = true;
          }
        };
        await tester.pumpWidget(
          MaterialApp(
            home: StudyHost(runtime: fixture.runtime, ownerId: fixture.ownerId),
          ),
        );
        await _until(
          tester,
          () => find.text('ลองอีกครั้ง').evaluate().isNotEmpty,
        );
        expect(find.byType(StudyPresentations), findsNothing);
        final rows = await tester.runAsync(fixture.researchRows);
        expect(rows!['measurement_opportunities'], isEmpty);
        expect(rows['events_v2'], isEmpty);
        expect(rows['learning_sessions'], isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(fixture.database.close);
      }
    },
  );

  testWidgets(
    'actual target frame then hidden failed capture cannot backfill on a new Host',
    (tester) async {
      final fixture = (await tester.runAsync(StudyRuntimeFixture.open))!;
      final reached = Completer<void>();
      final release = Completer<void>();
      var held = false;
      try {
        await tester.runAsync(fixture.baseline);
        fixture.participation.states.onRead = (_) async {
          if (!held && (await fixture.rows('events_v2')).isNotEmpty) {
            held = true;
            reached.complete();
            await release.future;
          }
        };
        await tester.pumpWidget(
          MaterialApp(
            home: StudyHost(runtime: fixture.runtime, ownerId: fixture.ownerId),
          ),
        );
        await _until(tester, () => reached.isCompleted);
        expect(find.byType(StudyPresentations), findsOneWidget);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(find.byType(StudyPresentations), findsNothing);
        release.complete();
        final afterFailure = await tester.runAsync(fixture.researchRows);
        expect(afterFailure!['measurement_opportunities'], hasLength(1));
        expect(
          afterFailure['measurement_opportunities']!
              .single['presented_event_id'],
          isNull,
        );
        expect(afterFailure['events_v2'], isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(
          MaterialApp(
            home: StudyHost(runtime: fixture.runtime, ownerId: fixture.ownerId),
          ),
        );
        await _until(
          tester,
          () => find
              .textContaining('กิจกรรมเสริมยังไม่พร้อม')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.byType(StudyPresentations), findsNothing);
        expect(await tester.runAsync(fixture.researchRows), afterFailure);
      } finally {
        if (!release.isCompleted) release.complete();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(fixture.database.close);
      }
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('Timed out waiting for the real opening operation');
}
