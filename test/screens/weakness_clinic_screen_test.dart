import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/features/content_reports/data/drift_content_report_queue.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_button.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/widgets/word_report_sheet.dart';

import '../support/content_report_ui_io.dart';
import '../support/motivation_presentation_io.dart';
import '../support/progress_owner_fixture.dart';
import '../support/review_center_harness.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  for (final foreignCover in [false, true]) {
    testWidgets(
      'Clinic owned word report ${foreignCover ? 'rejects a foreign cover' : 'keeps its draft and ordinary return'}',
      (tester) async {
        final h = (await tester.runAsync(ReviewCenterHarness.open))!;
        try {
          await tester.runAsync(() async {
            for (var i = 0; i < 3; i++) {
              await h.seedWrong(wordId: configuredWordIds.first);
            }
          });
          await tester.pumpWidget(
            _clinicReportApp(
              h,
              WeaknessClinicScreen(
                ownerChanges: h.ownerChanges,
                learning: h.learning,
              ),
            ),
          );
          await _hostReadUntil(
            tester,
            () => find.text('ฝึกคำที่ผิด (1)').evaluate().isNotEmpty,
          );
          await reportUiTap(
            tester,
            find.text('ฝึกคำที่ผิด (1)'),
            'clinic-report-practice',
          );
          final answer = find.widgetWithText(FilledButton, 'สถานี');
          await reportUiWait(
            tester,
            'clinic-report-answer',
            () => answer.evaluate().isNotEmpty,
          );
          await reportUiTap(tester, answer, 'clinic-report-answer');
          final practice = ModalRoute.of(
            tester.element(find.byType(QuizScreen)),
          )!;
          final before = await motivationPresentationIo(
            tester,
            h.snapshotAllTables,
          );
          final report = find.descendant(
            of: find.byType(ContentReportButton),
            matching: find.byType(TextButton),
          );
          await reportUiReveal(
            tester,
            report,
            'clinic-report-open',
            scrollable: find.byType(SingleChildScrollView),
          );
          await reportUiTap(tester, report, 'clinic-report-open');
          await reportUiWait(
            tester,
            'clinic-report-sheet',
            () => find.byType(WordReportSheet).evaluate().isNotEmpty,
          );
          await reportUiTapKey(tester, 'word-report-reason:spelling');
          final comment = find.byKey(const ValueKey('word-report-comment'));
          const draft = 'Synthetic Clinic report draft';
          await tester.ensureVisible(comment);
          await tester.enterText(comment, draft);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          final sheet = ModalRoute.of(
            tester.element(find.byType(WordReportSheet)),
          )!;
          sheet.changedExternalState();
          practice.changedExternalState();
          await tester.pump();
          expect(tester.widget<TextField>(comment).controller!.text, draft);
          expect(
            find.text('รายงานนี้ไม่พร้อมใช้งาน กรุณากลับแล้วเปิดใหม่'),
            findsNothing,
          );
          expect(
            await motivationPresentationIo(tester, h.snapshotAllTables),
            before,
          );
          if (foreignCover) {
            final navigator = Navigator.of(tester.element(comment));
            final foreign = MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Text('Synthetic Clinic report cover')),
            );
            unawaited(navigator.push<void>(foreign));
            await reportUiWait(
              tester,
              'clinic-report-covered',
              () => foreign.isCurrent,
            );
            practice.changedExternalState();
            await tester.pump();
            navigator.removeRoute(sheet);
            await tester.pump();
            expect(foreign.isCurrent, isTrue);
            navigator.pop();
            await tester.pump(const Duration(milliseconds: 350));
            practice.changedExternalState();
            await tester.pump();
            expect(find.byType(QuizScreen, skipOffstage: false), findsNothing);
            expect(
              await motivationPresentationIo(tester, h.snapshotAllTables),
              before,
            );
            return;
          }
          Navigator.of(tester.element(comment)).pop();
          await reportUiWait(
            tester,
            'clinic-report-dismissed',
            () => find.byType(WordReportSheet).evaluate().isEmpty,
          );
          expect(find.byType(QuizScreen), findsOneWidget);
          expect(find.text('ถูกต้อง'), findsOneWidget);
          expect(
            await motivationPresentationIo(tester, h.snapshotAllTables),
            before,
          );
          await reportUiTap(
            tester,
            find.text('ดูผลการเรียน'),
            'clinic-report-score',
          );
          await reportUiWait(
            tester,
            'clinic-report-score',
            () => find.byType(ScoreScreen).evaluate().isNotEmpty,
          );
          final finished = await motivationPresentationIo(
            tester,
            h.snapshotAllTables,
          );
          await reportUiTap(
            tester,
            find.text('กลับไปเลือกกิจกรรม'),
            'clinic-report-return',
          );
          await reportUiWait(
            tester,
            'clinic-report-returned',
            () =>
                find
                    .byType(QuizScreen, skipOffstage: false)
                    .evaluate()
                    .isEmpty &&
                find
                    .byType(ScoreScreen, skipOffstage: false)
                    .evaluate()
                    .isEmpty,
          );
          await _hostReadUntil(
            tester,
            () => find.text('ฝึกคำที่ผิด (1)').evaluate().isNotEmpty,
          );
          expect(
            await motivationPresentationIo(tester, h.snapshotAllTables),
            finished,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await closeMotivationPresentation(tester, h.close);
        }
      },
    );
  }

  testWidgets(
    'owner ABA clears private host data before its fresh read completes',
    (tester) async {
      final owners = StreamController<String?>.broadcast(sync: true);
      final pending = Completer<ProgressSnapshot>();
      var reads = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: WeaknessClinicScreen(
              ownerChanges: owners.stream,
              loader: () => reads++ == 0
                  ? Future.value(_hostReadSnapshot(91))
                  : pending.future,
            ),
          ),
        );
        owners.add('synthetic-host-owner-a');
        await _hostReadUntil(
          tester,
          () => find.text('synthetic-owner-private-91').evaluate().isNotEmpty,
        );
        owners
          ..add(null)
          ..add('synthetic-host-owner-a');
        await tester.pump();
        expect(
          find.text('synthetic-owner-private-91'),
          findsNothing,
          reason:
              'A/null/A must synchronously discard the original private rows',
        );
        await _hostReadUntil(tester, () => reads >= 2);
        pending.complete(_hostReadSnapshot(7));
        await _hostReadUntil(
          tester,
          () => find.text('synthetic-owner-private-7').evaluate().isNotEmpty,
        );
        expect(find.text('synthetic-owner-private-91'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!pending.isCompleted) pending.complete(_hostReadSnapshot(7));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(owners.close);
      }
    },
  );

  testWidgets('loading analysis has a contextual accessible label', (
    tester,
  ) async {
    final pending = Completer<ProgressSnapshot>();
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(
          ownerChanges: _displayProgressOwners,
          loader: () => pending.future,
        ),
      ),
    );

    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังวิเคราะห์คำที่ควรฝึก',
    );
    pending.complete(_emptySnapshot);
    await tester.pumpAndSettle();
  });

  testWidgets('practice batch keeps the top 20 weakness ranks', (tester) async {
    final h = (await tester.runAsync(ReviewCenterHarness.open))!;
    final owners = h.ownerChanges;
    final ranked = List.generate(
      21,
      (i) => WeaknessEvidence(
        wordId: 'word-${21 - i}',
        spelling: 'synthetic$i',
        meaning: 'คำสังเคราะห์',
        sampleSize: 100,
        incorrectCount: 99 - i,
        errorRate: (99 - i) / 100,
        dueAtUtc: null,
      ),
    );
    try {
      await tester.runAsync(() async {
        for (final item in ranked) {
          await h.addWord(
            id: item.wordId,
            spelling: item.spelling,
            meaning: item.meaning,
          );
        }
      });
      final before = await tester.runAsync(h.snapshotAllTables);
      await tester.pumpWidget(
        MaterialApp(
          home: WeaknessClinicScreen(
            ownerChanges: owners,
            learning: h.learning,
            loader: () async => ProgressSnapshot(
              sampleSize: 100,
              correctCount: 1,
              wrongCount: 99,
              accuracy: 0.01,
              totalXp: 0,
              completedSessions: 1,
              streakDays: 0,
              dueReviewCount: 0,
              masteredWordCount: 0,
              achievementCount: 0,
              gameLevel: 1,
              skills: [],
              weaknesses: ranked,
              recommendations: [],
            ),
          ),
        ),
      );
      await _hostReadUntil(
        tester,
        () => find.text('ฝึกคำที่ผิด (20)').evaluate().isNotEmpty,
      );
      expect(find.text('ฝึกคำที่ผิด (20)'), findsOneWidget);
      expect(await tester.runAsync(() => _clinicSessionCount(h)), 0);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      await tester.tap(find.text('ฝึกคำที่ผิด (20)'));
      await _clinicCanonicalStart(tester, h);
      expect(
        tester.widget<QuizScreen>(find.byType(QuizScreen)).wordIds,
        ranked.take(20).map((item) => item.wordId).toList(),
      );
      final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
      expect(quiz.expectedOwnerId, configuredOwnerId);
      expect(identical(quiz.ownerChanges, owners), isTrue);
      expect(identical(quiz.learning, h.learning), isTrue);
      expect(quiz.selectionMode, QuizWordSelectionMode.weakness);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(h.close);
    }
  });

  testWidgets(
    'weakness practice stays available before the next SRS due date',
    (tester) async {
      final h = (await tester.runAsync(ReviewCenterHarness.open))!;
      final owners = h.ownerChanges;
      try {
        await tester.runAsync(() async {
          for (final item in _snapshot.weaknesses) {
            await h.addWord(
              id: item.wordId,
              spelling: item.spelling,
              meaning: item.meaning,
            );
          }
        });
        final before = await tester.runAsync(h.snapshotAllTables);
        await tester.pumpWidget(
          MaterialApp(
            home: WeaknessClinicScreen(
              ownerChanges: owners,
              learning: h.learning,
              loader: () async => ProgressSnapshot(
                sampleSize: 3,
                correctCount: 1,
                wrongCount: 2,
                accuracy: 1 / 3,
                totalXp: 1,
                completedSessions: 1,
                streakDays: 1,
                dueReviewCount: 0,
                masteredWordCount: 0,
                achievementCount: 0,
                gameLevel: 1,
                skills: [],
                weaknesses: _snapshot.weaknesses,
                recommendations: [],
              ),
            ),
          ),
        );
        await _hostReadUntil(
          tester,
          () => find.text('ฝึกคำที่ผิด (1)').evaluate().isNotEmpty,
        );
        expect(find.text('ฝึกคำที่ผิด (1)'), findsOneWidget);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ฝึกคำที่ผิด (1)'),
        );
        expect(button.onPressed, isNotNull);
        expect(find.text('ยังไม่มีคำที่ถึงกำหนดทบทวน'), findsOneWidget);
        expect(await tester.runAsync(() => _clinicSessionCount(h)), 0);
        expect(await tester.runAsync(h.snapshotAllTables), before);
        await tester.tap(find.text('ฝึกคำที่ผิด (1)'));
        await _clinicCanonicalStart(tester, h);
        final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
        expect(quiz.expectedOwnerId, configuredOwnerId);
        expect(identical(quiz.ownerChanges, owners), isTrue);
        expect(identical(quiz.learning, h.learning), isTrue);
        expect(
          quiz.wordIds,
          _snapshot.weaknesses.map((item) => item.wordId).toList(),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(h.close);
      }
    },
  );

  testWidgets('displays weaknesses derived from attempt evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(
          ownerChanges: _displayProgressOwners,
          loader: () async => _snapshot,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ฝึกจุดอ่อน'), findsOneWidget);
    expect(
      find.text('จัดอันดับจากสัดส่วนคำตอบผิด จาก 3 คำตอบที่บันทึกไว้'),
      findsOneWidget,
    );
    expect(find.textContaining('วิธีคำนวณรุ่น'), findsNothing);
    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.textContaining('ตอบผิด 2/3 ครั้ง'), findsOneWidget);
    expect(find.text('ทบทวนคำที่ถึงกำหนด (1)'), findsOneWidget);
  });

  testWidgets('does not bypass hidden quiz and review features', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(
          ownerChanges: _displayProgressOwners,
          loader: () async => _snapshot,
          featureRegistry: const BuildFieldFeatureRegistry({
            FieldFeature.weakness: FieldFeatureState.enabled,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ฝึกคำที่ผิด (1)'), findsNothing);
    expect(find.text('ทบทวนคำที่ถึงกำหนด (1)'), findsNothing);
    expect(find.text('เปิดแบบฝึกที่รองรับจากหน้าเรียน'), findsOneWidget);
  });

  testWidgets('new account shows sample size zero instead of sample words', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(
          ownerChanges: _displayProgressOwners,
          loader: () async => _emptySnapshot,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('คำนวณจาก 0 คำตอบ'), findsOneWidget);
    expect(find.text('ephemeral'), findsNothing);
  });

  testWidgets('retry recovers one failed progress read', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(
          ownerChanges: _displayProgressOwners,
          loader: () async {
            if (calls++ == 0) throw StateError('synthetic failure');
            return _snapshot;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(
      tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.text('อ่านข้อมูลจุดอ่อนไม่สำเร็จ'),
              matching: find.byType(Semantics),
            ),
          )
          .any((widget) => widget.properties.liveRegion == true),
      isTrue,
    );

    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('ephemeral'), findsOneWidget);
  });

  testWidgets('keeps one primary action and reflows at 200 percent text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: WeaknessClinicScreen(
          ownerChanges: _displayProgressOwners,
          loader: () async => _snapshot,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'ฝึกคำที่ผิด (1)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'ทบทวนคำที่ถึงกำหนด (1)'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsOneWidget);
    final title = tester.renderObject<RenderParagraph>(find.text('ฝึกจุดอ่อน'));
    expect(title.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Widget _clinicReportApp(ReviewCenterHarness h, Widget screen) {
  final queue = DriftContentReportQueue(
    database: h.database,
    ownerWrites: h.ownerWrites,
  );
  return AppDependenciesScope(
    dependencies: AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _ClinicReportGuest(),
      database: h.database,
      progress: h.progress,
      learning: h.learning,
      wordReports: h.wordReports,
      vocabulary: VocabularyUseCases(
        owners: h.owners,
        vocabulary: DriftVocabularyRepository(h.database),
        generateId: () => 'synthetic-clinic-vocabulary',
        nowUtc: () => h.now,
      ),
      contentReports: ContentReportUseCases(
        queue: queue,
        generateId: () => 'synthetic-clinic-report',
        nowUtc: () => h.now,
        ordinarySessionGuard: queue.requireOrdinarySession,
      ),
    ),
    child: MaterialApp(home: screen),
  );
}

final class _ClinicReportGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('The report cannot create a guest');
}

const _snapshot = ProgressSnapshot(
  sampleSize: 3,
  correctCount: 1,
  wrongCount: 2,
  accuracy: 1 / 3,
  totalXp: 1,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: 1,
  masteredWordCount: 0,
  achievementCount: 1,
  gameLevel: 1,
  skills: [],
  weaknesses: [
    WeaknessEvidence(
      wordId: 'word-1',
      spelling: 'ephemeral',
      meaning: 'ชั่วคราว',
      sampleSize: 3,
      incorrectCount: 2,
      errorRate: 2 / 3,
      dueAtUtc: null,
    ),
  ],
  recommendations: [],
);

const _emptySnapshot = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);

ProgressSnapshot _hostReadSnapshot(int marker) => ProgressSnapshot(
  sampleSize: 3,
  correctCount: 1,
  wrongCount: 2,
  accuracy: 1 / 3,
  totalXp: marker,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: marker,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: const [],
  weaknesses: [
    WeaknessEvidence(
      wordId: 'synthetic-owner-private-word',
      spelling: 'synthetic-owner-private-$marker',
      meaning: 'synthetic private meaning',
      sampleSize: 3,
      incorrectCount: 2,
      errorRate: 2 / 3,
      dueAtUtc: null,
    ),
  ],
  recommendations: const [],
);

Future<void> _hostReadUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(condition(), isTrue, reason: 'Owner-bound host read did not settle');
}

final _displayProgressOwners = persistentProgressOwnerFixture(
  'synthetic-weakness-clinic-display-owner',
);

Future<int> _clinicSessionCount(ReviewCenterHarness h) async =>
    (await h.database.select(h.database.learningSessions).get()).length;

Future<void> _clinicCanonicalStart(
  WidgetTester tester,
  ReviewCenterHarness h,
) async {
  var count = 0;
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    count = (await tester.runAsync(() => _clinicSessionCount(h)))!;
    if (count == 1) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(
    count,
    1,
    reason: 'The owned Quiz must acknowledge one canonical start',
  );
  final session = (await tester.runAsync(
    () => h.database.select(h.database.learningSessions).getSingle(),
  ))!;
  expect(session.ownerId, configuredOwnerId);
  expect(session.activityType, 'weaknessPractice');
  expect(session.state, 'active');
  expect(
    await tester.runAsync(
      () => h.database.select(h.database.answerAttempts).get(),
    ),
    isEmpty,
  );
}
