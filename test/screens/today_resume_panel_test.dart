import 'dart:convert';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/presentation/today_resume_panel.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/configured_quiz_harness.dart';
import '../support/measurement_opportunity_harness.dart';
import '../support/motivation_presentation_io.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'actual recent resumable count and compact 200 percent History route are all-table pure reads',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await motivationPresentationIo(tester, _Fixture.open);
      try {
        final before = await motivationPresentationIo(tester, f.h.snapshot);
        await tester.pumpWidget(f.app(scale: 2));
        await _ready(tester);
        expect(
          find.text('พบกิจกรรมที่เล่นต่อได้ 1 รอบในประวัติ 50 รายการล่าสุด'),
          findsOneWidget,
        );
        expect(await motivationPresentationIo(tester, f.h.snapshot), before);
        final button = find.byKey(const ValueKey('today-resume-open-history'));
        await tester.ensureVisible(button);
        await tester.pump(const Duration(milliseconds: 16));
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button.hitTestable());
        await _historyReady(tester);
        expect(find.byType(LearningHistoryScreen), findsOneWidget);
        expect(await motivationPresentationIo(tester, f.h.snapshot), before);
        expect(tester.takeException(), isNull);
      } finally {
        await closeMotivationPresentation(tester, f.h.close);
      }
    },
  );

  testWidgets(
    'actual ChooseMode Today entry opens History and resumes its original canonical quiz',
    (tester) async {
      final f = await motivationPresentationIo(tester, _Fixture.open);
      try {
        final before = await motivationPresentationIo(tester, f.h.snapshot);
        await tester.pumpWidget(f.app(home: const ChooseModeScreen()));
        await _ready(tester);
        expect(find.byType(TodayResumePanel), findsOneWidget);
        expect(await motivationPresentationIo(tester, f.h.snapshot), before);
        final button = find.byKey(const ValueKey('today-resume-open-history'));
        await tester.ensureVisible(button);
        await tester.pump(const Duration(milliseconds: 16));
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button.hitTestable());
        await _historyReady(tester);
        expect(find.byType(LearningHistoryScreen), findsOneWidget);
        expect(await motivationPresentationIo(tester, f.h.snapshot), before);
        await tester.tap(find.text('เล่นต่อ').hitTestable());
        await _until(
          tester,
          () =>
              find.byType(QuizScreen).evaluate().isNotEmpty &&
              find.text('station').evaluate().isNotEmpty,
        );
        final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
        expect(quiz.resumeSessionId, f.activeSessionId);
        expect(quiz.expectedOwnerId, configuredOwnerId);
        expect(await motivationPresentationIo(tester, f.h.snapshot), before);
        expect(tester.takeException(), isNull);
      } finally {
        await closeMotivationPresentation(tester, f.h.close);
      }
    },
  );

  testWidgets('absent actual owner creates no owner or resume action', (
    tester,
  ) async {
    final f = await motivationPresentationIo(tester, _Fixture.open);
    try {
      await motivationPresentationIo(
        tester,
        () => f.switchOwner('synthetic-no-such-owner'),
      );
      final before = await motivationPresentationIo(tester, f.h.snapshot);
      await tester.pumpWidget(f.app(ownerId: null));
      await _flush(tester, 8);
      expect(find.byKey(const ValueKey('today-resume-count')), findsNothing);
      expect(
        find.byKey(const ValueKey('today-resume-open-history')),
        findsNothing,
      );
      expect(await motivationPresentationIo(tester, f.h.snapshot), before);
      expect(tester.takeException(), isNull);
    } finally {
      await closeMotivationPresentation(tester, f.h.close);
    }
  });

  testWidgets('actual owner A-B-A retires a retained Today history action', (
    tester,
  ) async {
    final f = await motivationPresentationIo(tester, _Fixture.open);
    try {
      await tester.pumpWidget(f.app());
      await _ready(tester);
      final retained = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('today-resume-open-history')),
          )
          .onPressed!;
      await motivationPresentationIo(
        tester,
        () => f.switchOwner(configuredOtherOwnerId),
      );
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('today-resume-open-history'))
            .evaluate()
            .isEmpty,
      );
      await motivationPresentationIo(
        tester,
        () => f.switchOwner(configuredOwnerId),
      );
      final before = await motivationPresentationIo(tester, f.h.snapshot);
      retained();
      await _flush(tester, 8);
      expect(find.byType(LearningHistoryScreen), findsNothing);
      expect(await motivationPresentationIo(tester, f.h.snapshot), before);
      expect(tester.takeException(), isNull);
    } finally {
      await closeMotivationPresentation(tester, f.h.close);
    }
  });

  testWidgets('actual deletion fence denies the summary and History action', (
    tester,
  ) async {
    final f = await motivationPresentationIo(tester, _Fixture.open);
    try {
      await motivationPresentationIo(
        tester,
        () => f.h.ownerWrites.beginDeletion(
          ownerId: configuredOwnerId,
          firebaseUid: configuredFirebaseUid,
          idempotencyKey: 'synthetic-today-resume-deletion',
        ),
      );
      final before = await motivationPresentationIo(tester, f.h.snapshot);
      await tester.pumpWidget(f.app());
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('today-resume-error'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byKey(const ValueKey('today-resume-count')), findsNothing);
      expect(
        find.byKey(const ValueKey('today-resume-open-history')),
        findsNothing,
      );
      expect(await motivationPresentationIo(tester, f.h.snapshot), before);
      expect(tester.takeException(), isNull);
    } finally {
      await closeMotivationPresentation(tester, f.h.close);
    }
  });

  testWidgets(
    'actual active Study quiz does not enter the ordinary resume count',
    (tester) async {
      final study = await motivationPresentationIo(tester, () async {
        final fixture = await OpportunityFixture.open();
        await fixture.ready();
        await fixture.accept();
        return fixture;
      });
      try {
        final session = await motivationPresentationIo(
          tester,
          study.storedSession,
        );
        expect(session['state'], 'active');
        expect(session['accepted_plan_id'], startsWith('quiz-plan:'));
        final opportunity = await motivationPresentationIo(
          tester,
          study.storedOpportunity,
        );
        expect(opportunity['learning_session_id'], session['id']);
        final progress = ProgressUseCases(
          owners: DriftLocalOwnerRepository(
            study.database,
            generateId: () => 'synthetic-today-must-not-create-owner',
            nowUtc: () => study.participation.clock.now,
          ),
          queries: DriftProgressQueries(study.database),
          nowUtc: () => study.participation.clock.now,
        );
        final owners = progress.watchActiveOwnerId();
        final before = await motivationPresentationIo(
          tester,
          () => _rows(study.database),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TodayResumePanel(
                progress: progress,
                ownerId: 'owner-a',
                ownerChanges: owners,
                onOpenHistory: () async {},
              ),
            ),
          ),
        );
        await _ready(tester);
        expect(
          find.text('พบกิจกรรมที่เล่นต่อได้ 0 รอบในประวัติ 50 รายการล่าสุด'),
          findsOneWidget,
        );
        expect(
          await motivationPresentationIo(tester, () => _rows(study.database)),
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await closeMotivationPresentation(tester, study.database.close);
      }
    },
  );
}

Future<void> _ready(WidgetTester tester) => _until(
  tester,
  () =>
      find.byKey(const ValueKey('today-resume-count')).evaluate().isNotEmpty &&
      tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('today-resume-open-history')),
              )
              .onPressed !=
          null,
);

Future<void> _historyReady(WidgetTester tester) async {
  await _until(
    tester,
    () =>
        find.byType(LearningHistoryScreen).evaluate().isNotEmpty &&
        find.text('คำตอบ 7 วันล่าสุด').evaluate().isNotEmpty,
  );
  final historyScroll = find
      .descendant(
        of: find.byType(LearningHistoryScreen),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.text('เล่นต่อ'),
    250,
    scrollable: historyScroll,
  );
  await tester.ensureVisible(find.text('เล่นต่อ'));
  await tester.pump(const Duration(milliseconds: 16));
  expect(find.text('เล่นต่อ').hitTestable(), findsOneWidget);
}

Future<void> _flush(WidgetTester tester, [int frames = 1]) async {
  for (var frame = 0; frame < frames; frame++) {
    await motivationPresentationDeadline(
      tester,
      'today-resume/frame',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    await motivationPresentationDeadline(
      tester,
      'today-resume/io',
      () => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      ),
    );
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 200; frame++) {
    await _flush(tester);
    if (ready()) {
      return;
    }
  }
  fail('The actual Today resume panel or History route did not become ready');
}

Future<Map<String, List<String>>> _rows(AppDatabase database) async => {
  for (final table in database.allTables)
    table.actualTableName:
        (await database
                .customSelect('SELECT * FROM ${table.actualTableName}')
                .get())
            .map((row) => jsonEncode(row.data))
            .toList()
          ..sort(),
};

final class _Fixture {
  _Fixture(this.h, this.progress, this.dependencies, this.activeSessionId)
    : owners = progress.watchActiveOwnerId();
  final ConfiguredQuizHarness h;
  final ProgressUseCases progress;
  final AppDependencies dependencies;
  final String activeSessionId;
  final Stream<String?> owners;
  final navigator = GlobalKey<NavigatorState>();

  static Future<_Fixture> open() async {
    final h = await ConfiguredQuizHarness.open();
    final repository = DriftLearningRepository(
      h.database,
      ownerWrites: h.ownerWrites,
    );
    var ids = 0;
    final learning = LearningUseCases(
      owners: h.owners,
      repository: repository,
      generateId: () => 'synthetic-today-resume-${++ids}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic',
        buildId: 'synthetic-today-resume',
      ),
    );
    Future<ConfiguredQuizState> start() async => learning.startConfiguredQuiz(
      await learning.prepareConfiguredQuiz(
        configuration: QuizConfiguration.sourcePractice(
          wordIds: [configuredWordIds.first],
          limit: 1,
        ),
        expectedOwnerId: configuredOwnerId,
      ),
    );
    final active = await start();
    final abandoned = await start();
    await learning.abandonQuiz(
      sessionId: abandoned.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: abandoned.checkpointRevision,
    );
    final progress = ProgressUseCases(
      owners: h.owners,
      queries: DriftProgressQueries(h.database),
      nowUtc: () => h.now,
    );
    return _Fixture(
      h,
      progress,
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
        learning: learning,
        progress: progress,
      ),
      active.sessionId,
    );
  }

  Future<void> switchOwner(String ownerId) async {
    await h.switchOwner(ownerId);
    h.database.notifyUpdates({TableUpdate.onTable(h.database.localOwners)});
  }

  Widget app({
    String? ownerId = configuredOwnerId,
    double scale = 1,
    Widget? home,
  }) => AppDependenciesScope(
    dependencies: dependencies,
    child: MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home:
          home ??
          Scaffold(
            body: SingleChildScrollView(
              child: TodayResumePanel(
                progress: progress,
                ownerId: ownerId,
                ownerChanges: owners,
                onOpenHistory: () async {
                  await navigator.currentState!.push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          LearningHistoryScreen(ownerChanges: owners),
                    ),
                  );
                },
              ),
            ),
          ),
    ),
  );
}

final class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('Synthetic Today resume must not authenticate');
}
