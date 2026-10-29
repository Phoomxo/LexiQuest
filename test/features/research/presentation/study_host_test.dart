import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/learning_session_lifecycle_observer.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/presentation/motivation_measurement_form.dart';
import 'package:vocab_learning_app/features/research/presentation/study_host.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

import '../../../support/measurement_opportunity_harness.dart';

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

  testWidgets('loading an explicit host does not begin or expose a study', (
    tester,
  ) async {
    final runtime = await _runtime(tester);
    try {
      await _mount(tester, runtime);
      await _untilFound(tester, find.byKey(const ValueKey('study-begin')));
      expect(runtime.begins, 0);
      expect(runtime.opens, isEmpty);
      expect(runtime.presents, 0);
      final counts = await tester.runAsync(
        () async => [
          await runtime.count('motivation_measurement_runs'),
          await runtime.count('motivation_responses'),
          await runtime.count('measurement_opportunities'),
          await runtime.count('events_v2'),
          await runtime.count('learning_sessions'),
        ],
      );
      expect(counts, [0, 0, 0, 0, 0]);
    } finally {
      await _cleanup(tester, runtime);
    }
  });

  for (final treatment in TodayExperiencePresentation.values) {
    testWidgets(
      '${treatment.name} uses real baseline, exact quiz and post before score',
      (tester) async {
        final runtime = await _runtime(tester, treatment: treatment);
        try {
          await _mount(tester, runtime);
          await _untilFound(tester, find.byKey(const ValueKey('study-begin')));
          await tester.tap(find.byKey(const ValueKey('study-begin')));
          await _answerForm(tester, 'baseline');
          await _until(
            tester,
            () => runtime.presents == 1 && _startEnabled(tester, treatment),
          );
          expect(
            await tester.runAsync(
              () => runtime.events(measurementPresentedEventType),
            ),
            hasLength(1),
          );
          expect(
            await tester.runAsync(() => runtime.count('learning_sessions')),
            0,
          );
          if (treatment == TodayExperiencePresentation.adventure) {
            expect(
              find.byKey(const ValueKey('study-standard-mission')),
              findsNothing,
            );
            await tester.tap(
              find.byKey(const ValueKey('study-adventure-node')),
            );
            await tester.pumpAndSettle();
          } else {
            expect(
              find.byKey(const ValueKey('study-standard-mission')),
              findsOneWidget,
            );
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('study-mission-start')),
          );
          await tester.tap(find.byKey(const ValueKey('study-mission-start')));
          await _untilFound(tester, find.byType(QuizScreen));
          await _untilFound(tester, find.text('station'));
          final index = (await tester.runAsync(() => runtime.index()))!;
          expect(
            index.plan.configuration.stableSerialization,
            runtime.catalog.configuration.stableSerialization,
          );
          expect(index.plan.mode, 'meaning-quiz');
          await tester.tap(find.text(index.plan.questions.first.correctAnswer));
          await _untilFound(tester, find.text('ดูผลการเรียน'));
          await tester.tap(find.text('ดูผลการเรียน'));
          await _until(
            tester,
            () => find
                .byKey(const ValueKey('measurement-synthetic-post-high'))
                .evaluate()
                .isNotEmpty,
            details: () => runtime.diagnostics(tester),
          );
          expect(find.byType(ScoreScreen), findsNothing);
          await _answerForm(tester, 'post');
          await _until(
            tester,
            () => find.byType(ScoreScreen).evaluate().isNotEmpty,
            details: () => runtime.diagnostics(tester),
          );
          final facts = (await tester.runAsync(() async {
            final run = await runtime.fixture.measurements.load(
              'owner-a',
              runtime.fixture.runId,
            );
            final session = await runtime.fixture.storedSession(
              index.sessionId,
            );
            final attempts = await runtime.fixture.database
                .select(runtime.fixture.database.answerAttempts)
                .get();
            final outbox = await runtime.fixture.database
                .select(runtime.fixture.database.outboxOperations)
                .get();
            final srs = await runtime.fixture.database
                .select(runtime.fixture.database.srsStates)
                .get();
            final unlocks = await runtime.fixture.database
                .select(runtime.fixture.database.achievementUnlocks)
                .get();
            return (
              run: run!,
              session: session,
              attempts: attempts,
              outbox: outbox,
              srs: srs,
              unlocks: unlocks,
            );
          }))!;
          expect(facts.run.state, MotivationMeasurementRunState.completed);
          expect(facts.run.responses, hasLength(2));
          expect(facts.session['id'], index.sessionId);
          expect(facts.session['state'], 'completed');
          expect(facts.attempts, hasLength(1));
          expect(facts.attempts.single.ownerId, 'owner-a');
          expect(facts.srs, hasLength(1));
          expect(facts.srs.single.ownerId, 'owner-a');
          expect(facts.srs.single.wordId, index.plan.questions.single.word.id);
          final sessionUnlocks = facts.unlocks
              .where(
                (row) =>
                    row.achievementId == 'first_session' ||
                    row.achievementId == 'perfect_session',
              )
              .toList();
          expect(sessionUnlocks, hasLength(2));
          for (final unlock in sessionUnlocks) {
            expect(unlock.ownerId, 'owner-a');
            expect(unlock.sourceEventId, index.sessionId);
          }
          expect(
            facts.outbox.map(
              (row) => (
                row.ownerId,
                row.entityType,
                row.entityId,
                row.payloadVersion,
                row.operationKind,
              ),
            ),
            unorderedEquals([
              ('owner-a', 'attempt', facts.attempts.single.id, 2, 'upsert'),
              ('owner-a', 'srsState', facts.srs.single.wordId, 1, 'upsert'),
              for (final unlock in sessionUnlocks)
                ('owner-a', 'achievementUnlock', unlock.id, 1, 'upsert'),
            ]),
            reason:
                'Only these four canonical learning references may enter '
                'the outbox; research rows have no matching type or entity ID. '
                'Actual types: ${facts.outbox.map((row) => row.entityType).toList()}',
          );
          final started = (await tester.runAsync(
            () => runtime.events(measurementMissionStartedEventType),
          ))!;
          final completed = (await tester.runAsync(
            () => runtime.events(measurementMissionCompletedEventType),
          ))!;
          expect(started, hasLength(1));
          expect(completed, hasLength(1));
          expect(
            (jsonDecode(started.single['payload_json']! as String)
                as Map)['planId'],
            index.plan.id,
          );
          expect(
            (jsonDecode(completed.single['payload_json']! as String)
                as Map)['planId'],
            index.plan.id,
          );
          expect(runtime.opens, hasLength(1));
        } finally {
          await _cleanup(tester, runtime);
        }
      },
    );
  }

  for (final change in ['cover', 'pause', 'owner', 'done', 'dispose']) {
    testWidgets('real Presented transaction rolls back after $change', (
      tester,
    ) async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final queries = OpportunityQueries()
        ..afterEventWrite = () async {
          entered.complete();
          await release.future;
        };
      final runtime = await _runtime(tester, queries: queries);
      try {
        await tester.runAsync(runtime.fixture.baseline);
        await _mount(tester, runtime);
        await _until(tester, () => entered.isCompleted);
        expect(runtime.presents, 1);
        if (change == 'cover') {
          unawaited(
            runtime.navigator.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Synthetic cover')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        } else if (change == 'pause') {
          binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pump();
        } else if (change == 'owner') {
          runtime.ownerSignals.add('owner-b');
          await tester.pump();
        } else if (change == 'done') {
          await runtime.ownerSignals.close();
          await tester.pump();
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
        expect(
          find.byKey(
            const ValueKey('study-standard-mission'),
            skipOffstage: false,
          ),
          findsNothing,
        );
        release.complete();
        await _until(tester, () => runtime.presentationFinished.isCompleted);
        await tester.pump();
        final stored = await tester.runAsync(
          () async => (
            events: await runtime.events(measurementPresentedEventType),
            opportunity: await runtime.firstOpportunity(),
            sessions: await runtime.count('learning_sessions'),
          ),
        );
        expect(stored!.events, isEmpty);
        expect(stored.opportunity!.presentation, isNull);
        expect(stored.sessions, 0);
      } finally {
        if (!release.isCompleted) release.complete();
        await _cleanup(tester, runtime);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    });
  }

  testWidgets('closing the owner watch hides an already rendered baseline', (
    tester,
  ) async {
    final runtime = await _runtime(tester);
    try {
      await tester.runAsync(runtime.fixture.startRun);
      await _mount(tester, runtime);
      final answer = find.byKey(
        const ValueKey('measurement-synthetic-baseline-high'),
      );
      await _untilFound(tester, answer);
      expect(find.byType(MotivationMeasurementForm), findsOneWidget);
      await runtime.ownerSignals.close();
      await tester.pump();
      expect(answer, findsNothing);
      expect(find.byType(MotivationMeasurementForm), findsNothing);
      expect(
        await tester.runAsync(() => runtime.count('motivation_responses')),
        0,
      );
      expect(runtime.opens, isEmpty);
      expect(runtime.presents, 0);
    } finally {
      await _cleanup(tester, runtime);
    }
  });

  testWidgets('closing the owner watch rejects a late canonical start ACK', (
    tester,
  ) async {
    final runtime = await _runtime(tester);
    final release = Completer<void>();
    runtime.startAcknowledgement = release;
    try {
      await tester.runAsync(runtime.fixture.baseline);
      await _mount(tester, runtime);
      await _until(
        tester,
        () => _startEnabled(tester, TodayExperiencePresentation.standard),
      );
      await tester.tap(find.byKey(const ValueKey('study-mission-start')));
      await _until(tester, () => runtime.startCommitted);
      await runtime.ownerSignals.close();
      await tester.pump();
      release.complete();
      await _until(tester, () => runtime.startAcknowledged);
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsNothing);
      expect(find.text('station'), findsNothing);
      expect(
        find.byKey(const ValueKey('study-standard-mission')),
        findsNothing,
      );
      expect(
        await tester.runAsync(() => runtime.count('learning_sessions')),
        1,
      );
      expect(await tester.runAsync(() => runtime.count('answer_attempts')), 0);
      expect((await tester.runAsync(runtime.index))!.state, 'active');
    } finally {
      if (!release.isCompleted) release.complete();
      await _cleanup(tester, runtime);
    }
  });

  testWidgets('a host outside a current route cannot collect or load', (
    tester,
  ) async {
    final runtime = await _runtime(tester);
    try {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => Stack(
            children: [
              child!,
              StudyHost(
                runtime: runtime,
                ownerId: 'owner-a',
                ownerChanges: runtime.ownerSignals.stream,
              ),
            ],
          ),
          home: const SizedBox.shrink(),
        ),
      );
      runtime.ownerSignals.add('owner-a');
      await tester.pumpAndSettle();
      expect(runtime.loads, 0);
      expect(find.byKey(const ValueKey('study-begin')), findsNothing);
      expect(runtime.begins, 0);
      expect(runtime.opens, isEmpty);
      expect(runtime.presents, 0);
    } finally {
      await _cleanup(tester, runtime);
    }
  });

  for (final afterOpen in [true, false]) {
    testWidgets(
      'lost ${afterOpen ? 'open' : 'Presented'} acknowledgement reuses one opportunity',
      (tester) async {
        final runtime = await _runtime(tester);
        runtime.failOpenAcknowledgement = afterOpen;
        runtime.failPresentedAcknowledgement = !afterOpen;
        try {
          await tester.runAsync(runtime.fixture.baseline);
          await _mount(tester, runtime);
          await _untilFound(tester, find.text('ลองอีกครั้ง'));
          await tester.tap(find.text('ลองอีกครั้ง'));
          await _until(
            tester,
            () => _startEnabled(tester, TodayExperiencePresentation.standard),
          );
          final stored = (await tester.runAsync(
            () async => (
              opportunities: await runtime.count('measurement_opportunities'),
              events: await runtime.events(measurementPresentedEventType),
              sessions: await runtime.count('learning_sessions'),
            ),
          ))!;
          expect(runtime.opens, hasLength(1));
          requireMeasurementEntryId(runtime.opens.single);
          expect(stored.opportunities, 1);
          expect(stored.events, hasLength(1));
          expect(stored.sessions, 0);
          expect(runtime.presents, 1);
        } finally {
          await _cleanup(tester, runtime);
        }
      },
    );
  }

  testWidgets(
    'reentry resumes the exact active first index and pinned options',
    (tester) async {
      final runtime = await _runtime(tester);
      try {
        await tester.runAsync(runtime.fixture.ready);
        final first = (await tester.runAsync(
          () => runtime.fixture.accept(id: 'synthetic-recovered-index'),
        ))!;
        await _mount(tester, runtime);
        await _untilFound(tester, find.text('ฝึกต่อรอบเดิม'));
        await tester.tap(find.text('ฝึกต่อรอบเดิม'));
        await _untilFound(tester, find.byType(QuizScreen));
        await _untilFound(tester, find.text('station'));
        expect(runtime.starts, 0);
        expect(runtime.resumes, 1);
        final saved = (await tester.runAsync(runtime.index))!;
        expect(saved.sessionId, first.sessionId);
        expect(saved.plan.id, first.plan.id);
        expect(
          saved.plan.questions.single.options,
          first.plan.questions.single.options,
        );
        expect(
          await tester.runAsync(() => runtime.count('learning_sessions')),
          1,
        );
        expect(
          await tester.runAsync(() => runtime.count('answer_attempts')),
          0,
        );
        expect(
          await tester.runAsync(
            () => runtime.events(measurementPresentedEventType),
          ),
          hasLength(1),
        );
      } finally {
        await _cleanup(tester, runtime);
      }
    },
  );

  for (final repairFails in [false, true]) {
    testWidgets(
      'completion sidecar repair failure=$repairFails preserves canonical learning',
      (tester) async {
        final queries = OpportunityQueries();
        final runtime = await _runtime(tester, queries: queries);
        runtime.failResume = repairFails;
        try {
          await tester.runAsync(runtime.fixture.baseline);
          await _mount(tester, runtime);
          await _until(
            tester,
            () => _startEnabled(tester, TodayExperiencePresentation.standard),
          );
          await tester.tap(find.byKey(const ValueKey('study-mission-start')));
          await _untilFound(tester, find.byType(QuizScreen));
          await _untilFound(tester, find.text('station'));
          final first = (await tester.runAsync(runtime.index))!;
          await tester.tap(find.text(first.plan.questions.first.correctAnswer));
          await _untilFound(tester, find.text('ดูผลการเรียน'));
          queries.afterEventWrite = () async {
            throw StateError('synthetic one-shot Completed sidecar failure');
          };
          await tester.tap(find.text('ดูผลการเรียน'));
          if (repairFails) {
            await _untilFound(tester, find.byType(ScoreScreen));
            expect(
              find.byKey(const ValueKey('measurement-synthetic-post-high')),
              findsNothing,
            );
            expect(
              await tester.runAsync(
                () => runtime.events(measurementMissionCompletedEventType),
              ),
              isEmpty,
            );
          } else {
            await _untilFound(
              tester,
              find.byKey(const ValueKey('measurement-synthetic-post-high')),
            );
            expect(find.byType(ScoreScreen), findsNothing);
            expect(
              await tester.runAsync(
                () => runtime.events(measurementMissionCompletedEventType),
              ),
              hasLength(1),
            );
          }
          final stored = (await tester.runAsync(
            () async => (
              session: await runtime.fixture.storedSession(first.sessionId),
              attempts: await runtime.count('answer_attempts'),
              rewards: await runtime.count('reward_transactions'),
              sessions: await runtime.count('learning_sessions'),
            ),
          ))!;
          expect(stored.session['state'], 'completed');
          expect(stored.session['id'], first.sessionId);
          expect(stored.attempts, 1);
          expect(stored.rewards, 1);
          expect(stored.sessions, 1);
          expect(runtime.resumes, 1);
        } finally {
          await _cleanup(tester, runtime);
        }
      },
    );
  }

  testWidgets(
    'delayed authority acknowledgement cannot extend a prompt lease',
    (tester) async {
      final runtime = await _runtime(tester);
      try {
        final run = (await tester.runAsync(runtime.fixture.startRun))!;
        final started = Completer<void>();
        final release = Completer<StudyView>();
        runtime.loadOverride = () {
          if (!started.isCompleted) started.complete();
          return release.future;
        };
        await _mount(tester, runtime);
        await _until(tester, () => started.isCompleted);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        release.complete(
          StudyView(
            ownerId: 'owner-a',
            catalog: runtime.catalog,
            phase: StudyPhase.baseline,
            run: run,
            evaluatedAtUtc: participationStart,
            promptExpiresAtUtc: participationStart.add(
              const Duration(milliseconds: 1),
            ),
          ),
        );
        await _untilFound(tester, find.text('ลองอีกครั้ง'));
        expect(find.byType(MotivationMeasurementForm), findsNothing);
        expect(runtime.begins, 0);
        expect(runtime.opens, isEmpty);
        expect(runtime.presents, 0);
        expect(
          await tester.runAsync(() => runtime.count('motivation_responses')),
          0,
        );
        expect(await tester.runAsync(() => runtime.count('events_v2')), 0);
      } finally {
        await _cleanup(tester, runtime);
      }
    },
  );

  for (final language in ['th', 'en']) {
    testWidgets(
      '$language host keeps the ordinary escape reachable at 200 percent',
      (tester) async {
        tester.view
          ..physicalSize = const Size(360, 800)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final runtime = await _runtime(tester);
        try {
          await _mount(
            tester,
            runtime,
            language: language,
            scale: 2,
            dark: true,
          );
          await _untilFound(tester, find.byKey(const ValueKey('study-begin')));
          final escape = find.byKey(const ValueKey('study-ordinary-exit'));
          expect(escape.hitTestable(), findsOneWidget);
          expect(tester.getSize(escape).height, greaterThanOrEqualTo(48));
          expect(
            find.text(
              language == 'th'
                  ? 'กลับไปเรียนตามปกติ'
                  : 'Back to ordinary learning',
            ),
            findsOneWidget,
          );
          expect(runtime.begins, 0);
          expect(runtime.presents, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await _cleanup(tester, runtime);
        }
      },
    );
  }
}

Future<_UiRuntime> _runtime(
  WidgetTester tester, {
  TodayExperiencePresentation treatment = TodayExperiencePresentation.standard,
  OpportunityQueries? queries,
}) async {
  final fixture = (await tester.runAsync(
    () => OpportunityFixture.open(
      queries: queries,
      treatment: treatment,
      longLived: true,
    ),
  ))!;
  return _UiRuntime(fixture);
}

Future<void> _mount(
  WidgetTester tester,
  _UiRuntime runtime, {
  String language = 'th',
  double scale = 1,
  bool dark = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: runtime.navigator,
      theme: dark ? M3Theme.darkTheme : M3Theme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: StudyHost(
        runtime: runtime,
        ownerId: 'owner-a',
        languageCode: language,
        ownerChanges: runtime.ownerSignals.stream,
      ),
    ),
  );
  runtime.ownerSignals.add('owner-a');
  await tester.pump();
}

Future<void> _cleanup(WidgetTester tester, _UiRuntime runtime) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(runtime.fixture.database.close);
  if (!runtime.ownerSignals.isClosed) await runtime.ownerSignals.close();
}

bool _startEnabled(WidgetTester tester, TodayExperiencePresentation treatment) {
  final finder = find.byKey(
    ValueKey(
      treatment == TodayExperiencePresentation.adventure
          ? 'study-adventure-node'
          : 'study-mission-start',
    ),
  );
  return finder.evaluate().isNotEmpty &&
      tester.widget<FilledButton>(finder).onPressed != null;
}

Future<void> _answerForm(WidgetTester tester, String point) async {
  final choice = find.byKey(ValueKey('measurement-synthetic-$point-high'));
  await _untilFound(tester, choice);
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  final finish = find.byKey(const ValueKey('measurement-finish'));
  await _until(
    tester,
    () =>
        finish.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(finish).onPressed != null,
  );
  await tester.ensureVisible(finish);
  await tester.tap(finish);
}

Future<void> _untilFound(WidgetTester tester, Finder finder) =>
    _until(tester, () => finder.evaluate().isNotEmpty);

Future<void> _until(
  WidgetTester tester,
  bool Function() ready, {
  String Function()? details,
}) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail(
    'Timed out waiting for the study UI${details == null ? '' : ': ${details()}'}',
  );
}

// UI orchestration uses real signed synthetic repositories; runtime port policy has separate tests.
final class _UiRuntime implements StudyRuntime {
  _UiRuntime(this.fixture) {
    final study = fixture.participation.assignments.binding.study;
    final owners = DriftLocalOwnerRepository(
      fixture.database,
      generateId: () => 'synthetic-unexpected-owner',
      nowUtc: () => fixture.participation.clock.now,
    );
    catalog = StudyPresentationCatalog(
      version: study.catalogVersion,
      missionId: 'synthetic-ui-mission',
      titles: const {
        'th': 'ภารกิจคำศัพท์สังเคราะห์',
        'en': 'Synthetic vocabulary mission',
      },
      descriptions: const {
        'th': 'ภารกิจข้อมูลสังเคราะห์สำหรับทดสอบ',
        'en': 'Synthetic mission for testing',
      },
      configuration: QuizConfiguration.category(
        categoryId: opportunityCategoryId,
        limit: 1,
      ),
    );
    consent = ResearchConsentUseCases(
      owners: owners,
      repository: fixture.participation.consent,
      nowUtc: () => fixture.privacyNow,
      version: study.consentVersion,
    );
    learning = LearningUseCases(
      owners: owners,
      repository: fixture.learning,
      generateId: () => 'synthetic-ui-${++_nextId}',
      nowUtc: () => fixture.participation.clock.now,
      buildInfo: AppBuildInfo(
        version: study.appVersion,
        buildId: study.buildId,
      ),
    );
  }

  final OpportunityFixture fixture;
  final navigator = GlobalKey<NavigatorState>();
  final ownerSignals = StreamController<String?>.broadcast();
  final presentationFinished = Completer<void>();
  @override
  late final StudyPresentationCatalog catalog;
  @override
  late final ResearchConsentUseCases consent;
  @override
  late final LearningUseCases learning;
  @override
  LearningSessionLifecycleObserver get lifecycleObserver => fixture.repository;
  int _nextId = 0;
  int begins = 0;
  int loads = 0;
  final opens = <String>[];
  final _potentialOpenings = <String>{};
  final _invalidOpenings = <String>{};
  int presents = 0;
  int starts = 0;
  int resumes = 0;
  bool failOpenAcknowledgement = false;
  bool failPresentedAcknowledgement = false;
  bool failResume = false;
  Completer<void>? startAcknowledgement;
  bool startCommitted = false;
  bool startAcknowledged = false;
  final phases = <StudyPhase>[];
  String? resumeFailure;
  ConfiguredQuizLaunch? _launch;
  Future<StudyView> Function()? loadOverride;

  String diagnostics(WidgetTester tester) =>
      'loads=$loads phases=$phases starts=$starts resumes=$resumes '
      'resumeFailure=$resumeFailure score=${find.byType(ScoreScreen).evaluate().length} '
      'form=${find.byType(MotivationMeasurementForm).evaluate().length}';

  @override
  MotivationMeasurementRepository measurementsFor(String ownerId) =>
      fixture.measurements;

  Future<int> count(String table) async =>
      (await fixture.database
              .customSelect('SELECT COUNT(*) AS n FROM $table')
              .getSingle())
          .read<int>('n');

  Future<List<Map<String, Object?>>> events(String type) async =>
      (await fixture.database
              .customSelect(
                'SELECT * FROM events_v2 WHERE event_type = ?',
                variables: [drift.Variable<String>(type)],
              )
              .get())
          .map((row) => row.data)
          .toList();

  Future<MeasurementOpportunity?> firstOpportunity() async {
    final rows = await fixture.database
        .customSelect(
          'SELECT id FROM measurement_opportunities WHERE owner_id = ? AND measurement_run_id = ?',
          variables: [
            const drift.Variable<String>('owner-a'),
            drift.Variable<String>(fixture.runId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    if (rows.length != 1) throw StateError('ambiguous synthetic opportunity');
    return fixture.repository.load('owner-a', rows.single.read<String>('id'));
  }

  Future<ConfiguredQuizState?> index() async {
    final opportunity = await firstOpportunity();
    final link = opportunity?.indexLink;
    if (link == null) return null;
    return learning.resumeQuiz(
      sessionId: link.sessionId,
      expectedOwnerId: 'owner-a',
    );
  }

  @override
  Future<StudyView> load(String ownerId) => _load(ownerId);

  Future<StudyView> _load(String ownerId, {bool prepared = false}) async {
    loads++;
    final override = loadOverride;
    if (override != null) return override();
    final run = await fixture.measurements.load(ownerId, fixture.runId);
    final opportunity = await firstOpportunity();
    final current = await index();
    final StudyPhase phase;
    if (opportunity != null && opportunity.presentation == null && !prepared) {
      phase = StudyPhase.unavailable;
    } else if (run == null || run.score(MotivationTimepoint.baseline) == null) {
      phase = StudyPhase.baseline;
    } else if (run.state == MotivationMeasurementRunState.completed) {
      phase = StudyPhase.completed;
    } else if (run.state != MotivationMeasurementRunState.started) {
      phase = StudyPhase.stopped;
    } else if (current?.state == 'abandoned') {
      phase = StudyPhase.stopped;
    } else if (current?.state == 'completed') {
      phase = (await events(measurementMissionCompletedEventType)).isEmpty
          ? StudyPhase.unavailable
          : StudyPhase.post;
    } else {
      phase = current == null ? StudyPhase.ready : StudyPhase.activeIndex;
    }
    final evaluated = fixture.participation.clock.now;
    phases.add(phase);
    return StudyView(
      ownerId: ownerId,
      catalog: catalog,
      phase: phase,
      run: run,
      opportunity: opportunity,
      index: current,
      evaluatedAtUtc: evaluated,
      promptExpiresAtUtc: evaluated.add(const Duration(minutes: 1)),
    );
  }

  @override
  Future<StudyView> begin(String ownerId) async {
    begins++;
    await fixture.startRun();
    return load(ownerId);
  }

  @override
  Future<StudyView> openPresentation(
    String ownerId, {
    required String entryAttemptId,
    required bool Function() stillCurrent,
  }) async {
    if (_invalidOpenings.contains(entryAttemptId) ||
        _potentialOpenings.contains(entryAttemptId)) {
      throw StateError('synthetic opening may already have rendered');
    }
    if (!opens.contains(entryAttemptId)) {
      if (await firstOpportunity() != null) {
        throw StateError('synthetic unknown opening');
      }
      opens.add(entryAttemptId);
    }
    await fixture.openOpportunity(entryId: entryAttemptId);
    if (!stillCurrent()) {
      throw StateError('synthetic opening no longer current');
    }
    if (failOpenAcknowledgement) {
      failOpenAcknowledgement = false;
      throw StateError('synthetic lost open acknowledgement');
    }
    return _load(ownerId, prepared: true);
  }

  @override
  void markPresentationMayRender(
    String ownerId,
    String opportunityId, {
    required String entryAttemptId,
  }) {
    if (!opens.contains(entryAttemptId) ||
        _invalidOpenings.contains(entryAttemptId)) {
      throw StateError('synthetic opening was not prepared');
    }
    _potentialOpenings.add(entryAttemptId);
  }

  @override
  void invalidatePresentationOpening(
    String ownerId, {
    required String entryAttemptId,
  }) {
    if (opens.contains(entryAttemptId)) _invalidOpenings.add(entryAttemptId);
  }

  @override
  Future<StudyView> recordPresented(
    String ownerId,
    String opportunityId, {
    required String entryAttemptId,
    required bool Function() stillVisible,
  }) async {
    if (!_potentialOpenings.contains(entryAttemptId) ||
        _invalidOpenings.contains(entryAttemptId)) {
      throw StateError('synthetic opening cannot backfill');
    }
    presents++;
    try {
      await fixture.repository.recordPresented(
        ownerId,
        opportunityId,
        stillVisible: stillVisible,
      );
      if (failPresentedAcknowledgement) {
        failPresentedAcknowledgement = false;
        throw StateError('synthetic lost Presented acknowledgement');
      }
      return load(ownerId);
    } finally {
      if (!presentationFinished.isCompleted) presentationFinished.complete();
    }
  }

  @override
  Future<ConfiguredQuizState> startIndex(
    String ownerId,
    String opportunityId, {
    required bool Function() stillVisible,
  }) async {
    starts++;
    if (!stillVisible()) {
      throw StateError('synthetic presentation no longer visible');
    }
    final existing = await index();
    if (existing != null) return existing;
    _launch ??= await learning.prepareConfiguredQuiz(
      configuration: catalog.configuration,
      expectedOwnerId: ownerId,
    );
    final started = await learning.startConfiguredQuiz(_launch!);
    startCommitted = true;
    await startAcknowledgement?.future;
    startAcknowledged = true;
    return started;
  }

  @override
  Future<ConfiguredQuizState> resumeIndex(String ownerId) async {
    resumes++;
    try {
      if (failResume) throw StateError('synthetic sidecar repair unavailable');
      final current = await index();
      if (current == null) throw StateError('synthetic index unavailable');
      if (current.state == 'completed') {
        return (await learning.finishConfiguredQuiz(
          sessionId: current.sessionId,
          expectedOwnerId: ownerId,
          expectedRevision: current.checkpointRevision,
        )).state;
      }
      return current;
    } on Object catch (error) {
      resumeFailure = error is StateError
          ? error.message
          : error.runtimeType.toString();
      rethrow;
    }
  }
}
