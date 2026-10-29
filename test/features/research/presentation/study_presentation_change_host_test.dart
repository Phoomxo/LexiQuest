import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/presentation/study_host.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';

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

  for (final assigned in TodayExperiencePresentation.values) {
    testWidgets(
      '${assigned.name} switches actual renderer and resumes the same canonical index',
      (tester) async {
        final f = (await tester.runAsync(
          () => StudyRuntimeFixture.open(treatment: assigned, longLived: true),
        ))!;
        try {
          final index = (await tester.runAsync(f.start))!;
          final started = (await tester.runAsync(() => f.rows('events_v2')))!
              .singleWhere(
                (r) => r['event_type'] == measurementMissionStartedEventType,
              );
          await _mount(tester, f);
          final switcher = find.byKey(
            const ValueKey('study-presentation-switch'),
          );
          await _until(
            tester,
            () => _enabled(tester, switcher),
            'switch action',
          );
          await tester.ensureVisible(switcher);
          await tester.tap(switcher);
          final target = oppositePresentation(assigned);
          final renderer = _renderer(target);
          await _until(
            tester,
            () => renderer.evaluate().isNotEmpty && _enabled(tester, switcher),
            'committed target renderer',
          );
          final opportunity = (await tester.runAsync(
            () => f.rows('measurement_opportunities'),
          ))!.single;
          expect(opportunity['pending_presentation_change_json'], isNull);
          expect(opportunity['last_switch_ordinal'], 1);
          expect(opportunity['learning_session_id'], index.sessionId);
          expect(opportunity['assigned_treatment'], assigned.wireName);
          expect(opportunity['effective_presentation'], assigned.wireName);
          final events = (await tester.runAsync(() => f.rows('events_v2')))!;
          expect(
            events.singleWhere(
              (r) => r['event_type'] == measurementMissionStartedEventType,
            ),
            started,
          );
          expect(
            events.where(
              (r) => r['event_type'] == measurementPresentationChangedEventType,
            ),
            hasLength(1),
          );
          if (target == TodayExperiencePresentation.adventure) {
            final node = find.byKey(const ValueKey('study-adventure-node'));
            await tester.ensureVisible(node);
            await tester.tap(node);
            await tester.pump();
          }
          final start = find.byKey(const ValueKey('study-mission-start'));
          await _until(
            tester,
            () => _enabled(tester, start),
            'same index resume',
          );
          await tester.ensureVisible(start);
          await tester.tap(start);
          await _until(
            tester,
            () => find.byType(QuizScreen).evaluate().isNotEmpty,
            'canonical QuizScreen',
          );
          final sessions = (await tester.runAsync(
            () => f.rows('learning_sessions'),
          ))!;
          expect(sessions, hasLength(1));
          expect(sessions.single['id'], index.sessionId);
          expect(tester.takeException(), isNull);
        } finally {
          await _close(tester, f);
        }
      },
    );
  }

  testWidgets(
    'held prepare acknowledgement creates zero target frames and disables another switch',
    (tester) async {
      final queries = _FrameQueries();
      final f = (await tester.runAsync(
        () => StudyRuntimeFixture.open(
          database: AppDatabase(NativeDatabase.memory().interceptWith(queries)),
          longLived: true,
        ),
      ))!;
      final release = Completer<void>();
      var entered = false;
      try {
        await tester.runAsync(f.ready);
        await _mount(tester, f);
        final switcher = find.byKey(
          const ValueKey('study-presentation-switch'),
        );
        await _until(tester, () => _enabled(tester, switcher), 'switch action');
        queries.holdPrepare = () async {
          entered = true;
          await release.future;
        };
        await tester.ensureVisible(switcher);
        await tester.tap(switcher);
        await _until(tester, () => entered, 'actual pending transaction');
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          expect(
            _renderer(TodayExperiencePresentation.adventure),
            findsNothing,
          );
          expect(
            _renderer(TodayExperiencePresentation.standard),
            findsOneWidget,
          );
          expect(_enabled(tester, switcher), isFalse);
        }
        release.complete();
        await _until(
          tester,
          () =>
              _renderer(
                TodayExperiencePresentation.adventure,
              ).evaluate().isNotEmpty &&
              _enabled(tester, switcher),
          'target frame capture',
        );
        expect(
          (await tester.runAsync(
            () => f.rows('measurement_opportunities'),
          ))!.single['last_switch_ordinal'],
          1,
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await _close(tester, f);
      }
    },
  );

  testWidgets(
    'post-frame capture failure hides collection while ordinary exit remains available',
    (tester) async {
      final queries = _FrameQueries();
      final f = (await tester.runAsync(
        () => StudyRuntimeFixture.open(
          database: AppDatabase(NativeDatabase.memory().interceptWith(queries)),
          longLived: true,
        ),
      ))!;
      try {
        await tester.runAsync(f.ready);
        await _mount(tester, f);
        final switcher = find.byKey(
          const ValueKey('study-presentation-switch'),
        );
        await _until(tester, () => _enabled(tester, switcher), 'switch action');
        queries.failChanged = true;
        await tester.ensureVisible(switcher);
        await tester.tap(switcher);
        await _until(
          tester,
          () =>
              queries.changedAttempts > 0 &&
              _renderer(
                TodayExperiencePresentation.standard,
              ).evaluate().isEmpty &&
              _renderer(
                TodayExperiencePresentation.adventure,
              ).evaluate().isEmpty,
          'unavailable after real target frame',
        );
        expect(
          find.byKey(const ValueKey('study-ordinary-exit')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('study-mission-start')), findsNothing);
        final opportunity = (await tester.runAsync(
          () => f.rows('measurement_opportunities'),
        ))!.single;
        expect(opportunity['pending_presentation_change_json'], isNotNull);
        expect(opportunity['last_switch_ordinal'], 0);
        expect(
          (await tester.runAsync(() => f.rows('events_v2')))!.where(
            (r) => r['event_type'] == measurementPresentationChangedEventType,
          ),
          isEmpty,
        );
        expect(
          (await tester.runAsync(() => f.runtime.load(f.ownerId)))!.phase.name,
          'unavailable',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, f);
      }
    },
  );
}

Finder _renderer(TodayExperiencePresentation value) => find.byKey(
  ValueKey(
    value == TodayExperiencePresentation.standard
        ? 'study-standard-mission'
        : 'study-adventure-node',
  ),
);
bool _enabled(WidgetTester tester, Finder finder) =>
    finder.evaluate().isNotEmpty &&
    tester.widget<ButtonStyleButton>(finder).onPressed != null;
Future<void> _mount(WidgetTester tester, StudyRuntimeFixture f) async {
  final progress = ProgressUseCases(
    owners: f.owners,
    queries: DriftProgressQueries(f.database),
    nowUtc: () => f.participation.clock.now,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: M3Theme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: StudyHost(
        runtime: f.runtime,
        ownerId: f.ownerId,
        ownerChanges: progress.watchActiveOwnerId(),
      ),
    ),
  );
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String label,
) async {
  for (var count = 0; count < 180; count++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('Timed out waiting for $label');
}

Future<void> _close(WidgetTester tester, StudyRuntimeFixture f) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(f.database.close);
}

final class _FrameQueries extends drift.QueryInterceptor {
  Future<void> Function()? holdPrepare;
  bool failChanged = false;
  int changedAttempts = 0;
  @override
  Future<void> runCustom(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    if (statement.contains('pending_presentation_change_json') &&
        args.any((value) => value is String && value.contains('"attemptId"'))) {
      await holdPrepare?.call();
    }
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (statement.contains('events_v2') &&
        args.contains(measurementPresentationChangedEventType)) {
      changedAttempts++;
      if (failChanged) {
        throw StateError('synthetic Changed persistence failure');
      }
    }
    return executor.runInsert(statement, args);
  }
}
