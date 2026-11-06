import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_sheet.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

import '../support/motivation_presentation_io.dart';
import 'learning_pack_test_support.dart';

Future<void> _open(
  WidgetTester tester,
  LearningPackUiHarness h, {
  bool readingOnly = false,
  LearningUseCases? learning,
  bool waitForReading = true,
}) async {
  final base = (h.app() as AppDependenciesScope).dependencies;
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: AppDependencies(
        runtimeStatus: base.runtimeStatus,
        config: null,
        guestSessionService: base.guestSessionService,
        database: h.database,
        learningPacks: h.packs,
        learning: learning ?? h.learning,
        localOwners: h.learning.owners,
      ),
      child: MaterialApp(
        home: ChooseModeScreen(
          ownerChanges: h.packs.watchActiveOwnerId(),
          featureRegistry: readingOnly
              ? const BuildFieldFeatureRegistry({
                  FieldFeature.reading: FieldFeatureState.enabled,
                })
              : null,
        ),
      ),
    ),
  );
  await untilPackUi(
    tester,
    () => find.text('เลือกกิจกรรม').evaluate().isNotEmpty,
  );
  await tester.scrollUntilVisible(
    find.text('อ่านและทบทวนคำศัพท์'),
    200,
    scrollable: find
        .descendant(
          of: find.byType(ChooseModeScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(find.text('อ่านและทบทวนคำศัพท์'));
  await tester.pumpAndSettle();
  expect(find.text('อ่านและทบทวนคำศัพท์').hitTestable(), findsOneWidget);
  await tester.tap(find.text('อ่านและทบทวนคำศัพท์'));
  if (!waitForReading) return;
  await untilPackUi(
    tester,
    () => find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย').evaluate().isNotEmpty,
  );
}

Future<void> _next(WidgetTester tester, int stage) async {
  await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
  await untilPackUi(
    tester,
    () => find.textContaining('ขั้นที่ $stage:').evaluate().isNotEmpty,
  );
}

Future<void> _recall(WidgetTester tester, {required bool correct}) async {
  await _next(tester, 2);
  await _next(tester, 3);
  await tester.enterText(find.byType(TextField).first, correct ? 'cat' : 'dog');
  await _next(tester, 4);
  await _next(tester, 5);
  expect(
    find.text('ฝึกเสริม ข้ามได้ ไม่ตรวจคะแนนและไม่บันทึกประโยค'),
    findsOneWidget,
  );
  await tester.tap(find.text('ข้ามการแต่งประโยค'));
  await untilPackUi(
    tester,
    () => find.text('ขั้นที่ 6: สรุปผล').evaluate().isNotEmpty,
  );
  expect(find.text('บันทึกผลทดสอบจากความจำแล้ว'), findsOneWidget);
}

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'pending Reading launch stays cancelled after foreign cover returns',
    (tester) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'home-reading/pending',
        () => tester.runAsync(LearningPackUiHarness.open),
      ))!;
      final owners = _GatedOwners(h.learning.owners);
      try {
        await motivationPresentationIo(
          tester,
          () => h.seed(syntheticPackUiContent()),
        );
        final learning = LearningUseCases(
          owners: owners,
          repository: h.learning.repository,
          generateId: h.learning.generateId,
          nowUtc: h.learning.nowUtc,
          buildInfo: h.learning.buildInfo,
        );
        await _open(tester, h, learning: learning, waitForReading: false);
        await untilPackUi(tester, () => owners.started);
        final navigator = Navigator.of(
          tester.element(find.byType(ChooseModeScreen)),
        );
        unawaited(
          navigator.push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  const Scaffold(body: Text('Pending foreign cover')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();
        owners.release.complete();
        await untilPackUi(tester, () => owners.finished);
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(AssociativeReadingSessionScreen), findsNothing);
        expect(find.byType(ScoreScreen), findsNothing);
        expect(
          await motivationPresentationIo(
            tester,
            () => h.database.select(h.database.answerAttempts).get(),
          ),
          isEmpty,
        );
      } finally {
        if (!owners.release.isCompleted) owners.release.complete();
        await closeMotivationPresentation(tester, h.close);
      }
    },
  );

  for (final correct in [false, true]) {
    testWidgets(
      'Home Reading ${correct ? 'all correct' : 'wrong'} returns saved result once',
      (tester) async {
        final h = (await motivationPresentationDeadline(
          tester,
          'home-reading/open',
          () => tester.runAsync(LearningPackUiHarness.open),
        ))!;
        try {
          await motivationPresentationIo(
            tester,
            () => h.seed(syntheticPackUiContent()),
          );
          await _open(tester, h);
          await _recall(tester, correct: correct);
          final reading = tester.widget<AssociativeReadingSessionScreen>(
            find.byType(AssociativeReadingSessionScreen),
          );
          final checkpoint = await motivationPresentationIo(
            tester,
            () => h.learning.repository.readReadingProgress(
              ownerId: 'synthetic-actions-owner',
              documentId: reading.documentId!,
              documentRevision: reading.documentRevision,
            ),
          );
          expect(checkpoint?.lastPosition, 6);
          expect(checkpoint?.isCompleted, isFalse);
          await tester.tap(find.text('จบการฝึกและดูผล'));
          await untilPackUi(
            tester,
            () => find.byType(ScoreScreen).evaluate().isNotEmpty,
          );
          final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
          expect(score.correctAnswers, correct ? 1 : 0);
          expect(score.wrongAnswers, correct ? 0 : 1);
          expect(score.score, correct ? 100 : 0);
          expect(score.resultOwnerId, 'synthetic-actions-owner');
          expect(score.mistakes.length, correct ? 0 : 1);
          final sessions = await motivationPresentationIo(
            tester,
            () => h.database.select(h.database.learningSessions).get(),
          );
          final attempts = await motivationPresentationIo(
            tester,
            () => h.database.select(h.database.answerAttempts).get(),
          );
          expect(sessions, hasLength(1));
          expect(attempts, hasLength(1));
          expect(score.resultSessionId, sessions.single.id);
          if (correct) {
            expect(score.onPracticeMistakes, isNull);
          } else {
            final repair = find.text('ฝึกคำที่ผิด (1)');
            await tester.ensureVisible(repair);
            await tester.pumpAndSettle();
            await tester.tap(repair);
            await untilPackUi(
              tester,
              () => find.byType(QuizScreen).evaluate().isNotEmpty,
            );
            final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
            expect(quiz.wordIds, score.mistakes.map((word) => word.id));
            expect(quiz.expectedOwnerId, 'synthetic-actions-owner');
            expect(quiz.ownerChanges, isNotNull);
            expect(
              await motivationPresentationIo(
                tester,
                () => h.database.select(h.database.answerAttempts).get(),
              ),
              hasLength(1),
            );
            await untilPackUi(
              tester,
              () =>
                  find.text('เฉลยคำตอบ (นับเป็นข้อผิด)').evaluate().isNotEmpty,
            );
            await tester.ensureVisible(find.text('เฉลยคำตอบ (นับเป็นข้อผิด)'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('เฉลยคำตอบ (นับเป็นข้อผิด)'));
            await untilPackUi(
              tester,
              () => find.text('ดูผลการเรียน').evaluate().isNotEmpty,
            );
            await tester.ensureVisible(find.text('ดูผลการเรียน'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('ดูผลการเรียน'));
            await untilPackUi(
              tester,
              () => find.byType(ScoreScreen).evaluate().isNotEmpty,
            );
            expect(
              tester.widget<ScoreScreen>(find.byType(ScoreScreen)).wrongAnswers,
              1,
            );
            await tester.ensureVisible(find.text('ฝึกคำที่ผิด (1)'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('ฝึกคำที่ผิด (1)'));
            await untilPackUi(
              tester,
              () =>
                  find.text('เฉลยคำตอบ (นับเป็นข้อผิด)').evaluate().isNotEmpty,
            );
            final answer = find.widgetWithText(FilledButton, 'แมว');
            await tester.ensureVisible(answer);
            await tester.pumpAndSettle();
            await tester.tap(answer);
            await untilPackUi(
              tester,
              () => find.text('ดูผลการเรียน').evaluate().isNotEmpty,
            );
            await tester.ensureVisible(find.text('ดูผลการเรียน'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('ดูผลการเรียน'));
            await untilPackUi(
              tester,
              () => find.byType(ScoreScreen).evaluate().isNotEmpty,
            );
            expect(
              tester
                  .widget<ScoreScreen>(find.byType(ScoreScreen))
                  .correctAnswers,
              1,
            );
            await tester.ensureVisible(find.text('กลับหน้าเรียน'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('กลับหน้าเรียน'));
            await untilPackUi(
              tester,
              () =>
                  find.byType(ScoreScreen).evaluate().isEmpty &&
                  find.byType(QuizScreen).evaluate().isEmpty &&
                  find
                      .byType(ChooseModeScreen)
                      .hitTestable()
                      .evaluate()
                      .isNotEmpty,
            );
            await tester.pumpAndSettle();
            expect(find.byType(ScoreScreen), findsNothing);
            final repairedSessions = await motivationPresentationIo(
              tester,
              () => h.database.select(h.database.learningSessions).get(),
            );
            final repairedAttempts = await motivationPresentationIo(
              tester,
              () => h.database.select(h.database.answerAttempts).get(),
            );
            expect(repairedSessions, hasLength(3));
            expect(
              repairedSessions.every((session) => session.state == 'completed'),
              isTrue,
            );
            expect(repairedAttempts, hasLength(3));
            expect(
              repairedAttempts.where((answer) => answer.isCorrect),
              hasLength(1),
            );
          }
        } finally {
          await closeMotivationPresentation(tester, h.close);
        }
      },
    );
  }

  testWidgets('Reading-only Home opens result without quiz authority', (
    tester,
  ) async {
    final h = (await motivationPresentationDeadline(
      tester,
      'home-reading/only',
      () => tester.runAsync(LearningPackUiHarness.open),
    ))!;
    try {
      await motivationPresentationIo(
        tester,
        () => h.seed(syntheticPackUiContent()),
      );
      await _open(tester, h, readingOnly: true);
      await _recall(tester, correct: false);
      await tester.tap(find.text('จบการฝึกและดูผล'));
      await untilPackUi(
        tester,
        () => find.byType(ScoreScreen).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<ScoreScreen>(find.byType(ScoreScreen)).onPracticeMistakes,
        isNull,
      );
    } finally {
      await closeMotivationPresentation(tester, h.close);
    }
  });

  testWidgets('Home Reading cancel creates no result or answer', (
    tester,
  ) async {
    final h = (await motivationPresentationDeadline(
      tester,
      'home-reading/cancel',
      () => tester.runAsync(LearningPackUiHarness.open),
    ))!;
    try {
      await motivationPresentationIo(
        tester,
        () => h.seed(syntheticPackUiContent()),
      );
      await _open(tester, h);
      Navigator.of(
        tester.element(find.byType(AssociativeReadingSessionScreen)),
      ).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ScoreScreen), findsNothing);
      expect(
        await motivationPresentationIo(
          tester,
          () => h.database.select(h.database.answerAttempts).get(),
        ),
        isEmpty,
      );
    } finally {
      await closeMotivationPresentation(tester, h.close);
    }
  });

  testWidgets('Home Reading rejects changed content before showing result', (
    tester,
  ) async {
    final h = (await motivationPresentationDeadline(
      tester,
      'home-reading/content-before-result',
      () => tester.runAsync(LearningPackUiHarness.open),
    ))!;
    try {
      await motivationPresentationIo(
        tester,
        () => h.seed(syntheticPackUiContent()),
      );
      await _open(tester, h);
      await _recall(tester, correct: false);
      final reading = tester.widget<AssociativeReadingSessionScreen>(
        find.byType(AssociativeReadingSessionScreen),
      );
      await motivationPresentationIo(
        tester,
        () => h.database.customStatement(
          'UPDATE vocabulary_words SET meaning = ?, local_revision = local_revision + 1 WHERE id = ?',
          ['changed before result', reading.targetWords.single.id],
        ),
      );
      await tester.tap(find.text('จบการฝึกและดูผล'));
      await untilPackUi(
        tester,
        () => find.byType(ChooseModeScreen).hitTestable().evaluate().isNotEmpty,
      );
      expect(find.byType(ScoreScreen), findsNothing);
      expect(
        await motivationPresentationIo(
          tester,
          () => h.database.select(h.database.answerAttempts).get(),
        ),
        hasLength(1),
      );
    } finally {
      await closeMotivationPresentation(tester, h.close);
    }
  });

  for (final change in ['owner', 'content', 'foreign cover']) {
    testWidgets('Home Reading repair rejects $change after result', (
      tester,
    ) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'home-reading/stale',
        () => tester.runAsync(LearningPackUiHarness.open),
      ))!;
      try {
        await motivationPresentationIo(
          tester,
          () => h.seed(syntheticPackUiContent()),
        );
        await _open(tester, h);
        await _recall(tester, correct: false);
        await tester.tap(find.text('จบการฝึกและดูผล'));
        await untilPackUi(
          tester,
          () => find.byType(ScoreScreen).evaluate().isNotEmpty,
        );
        final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
        final retained = score.onPracticeMistakes!;
        if (change == 'owner') {
          await motivationPresentationIo(
            tester,
            () => h.switchOwner('synthetic-actions-other'),
          );
          await motivationPresentationIo(
            tester,
            () => h.switchOwner('synthetic-actions-owner'),
          );
        } else if (change == 'content') {
          await motivationPresentationIo(
            tester,
            () => h.database.customStatement(
              'UPDATE vocabulary_words SET meaning = ?, local_revision = local_revision + 1 WHERE id = ?',
              ['changed meaning', score.mistakes.single.id],
            ),
          );
        } else {
          Navigator.of(tester.element(find.byType(ScoreScreen))).push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Foreign cover')),
            ),
          );
          await tester.pumpAndSettle();
        }
        retained();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        expect(find.byType(QuizScreen), findsNothing);
        expect(
          await motivationPresentationIo(
            tester,
            () => h.database.select(h.database.answerAttempts).get(),
          ),
          hasLength(1),
        );
        if (change == 'foreign cover') {
          expect(find.text('Foreign cover'), findsOneWidget);
        }
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    });
  }

  testWidgets('report close restores repair route foreign-cover protection', (
    tester,
  ) async {
    final h = (await motivationPresentationDeadline(
      tester,
      'home-reading/report-cover',
      () => tester.runAsync(LearningPackUiHarness.open),
    ))!;
    try {
      await motivationPresentationIo(
        tester,
        () => h.seed(syntheticPackUiContent()),
      );
      await _open(tester, h);
      await _recall(tester, correct: false);
      await tester.tap(find.text('จบการฝึกและดูผล'));
      await untilPackUi(
        tester,
        () => find.byType(ScoreScreen).evaluate().isNotEmpty,
      );
      final retained = tester
          .widget<ScoreScreen>(find.byType(ScoreScreen))
          .onPracticeMistakes!;
      await tester.ensureVisible(find.text('ฝึกคำที่ผิด (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ฝึกคำที่ผิด (1)'));
      await untilPackUi(
        tester,
        () => find.text('เฉลยคำตอบ (นับเป็นข้อผิด)').evaluate().isNotEmpty,
      );
      final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
      final quizContext = tester.element(find.byType(QuizScreen));
      final navigator = Navigator.of(quizContext);
      unawaited(
        showContentReportModal(
          quizContext,
          builder: (_) =>
              const SizedBox(height: 200, child: Text('Synthetic report')),
          onRouteChanged: quiz.onOwnedRouteChanged,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic report'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsOneWidget);
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) =>
                const Scaffold(body: Text('Foreign cover after report')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsNothing);
      expect(
        find.text('ข้อมูลเปลี่ยนแล้ว กรุณากลับไปหน้าเรียน'),
        findsOneWidget,
      );
      retained();
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsNothing);
      expect(
        await motivationPresentationIo(
          tester,
          () => h.database.select(h.database.answerAttempts).get(),
        ),
        hasLength(1),
      );
    } finally {
      await closeMotivationPresentation(tester, h.close);
    }
  });

  for (final invalid in ['state', 'count', 'score', 'mistakes']) {
    testWidgets('Home Reading rejects invalid result $invalid', (tester) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'home-reading/invalid',
        () => tester.runAsync(LearningPackUiHarness.open),
      ))!;
      try {
        await motivationPresentationIo(
          tester,
          () => h.seed(syntheticPackUiContent()),
        );
        await _open(tester, h);
        final reading = tester.element(
          find.byType(AssociativeReadingSessionScreen),
        );
        Navigator.of(reading).removeRoute(
          ModalRoute.of(reading)!,
          LearningSessionResult(
            summary: LearningSessionSummary(
              id: 'synthetic-invalid-result',
              state: invalid == 'state' ? 'active' : 'completed',
              correctCount: invalid == 'count' ? 2 : 1,
              wrongCount: 0,
              score: invalid == 'score' ? 25 : 100,
            ),
            mistakeWordIds: invalid == 'mistakes' ? ['foreign-word'] : [],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ScoreScreen), findsNothing);
        expect(
          await motivationPresentationIo(
            tester,
            () => h.database.select(h.database.answerAttempts).get(),
          ),
          isEmpty,
        );
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    });
  }
}

final class _GatedOwners implements LocalOwnerRepository {
  _GatedOwners(this.delegate);
  final LocalOwnerRepository delegate;
  final release = Completer<void>();
  var started = false;
  var finished = false;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    started = true;
    await release.future;
    final owner = await delegate.getOrCreateActiveOwner();
    finished = true;
    return owner;
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      delegate.bindFirebaseUid(ownerId, firebaseUid);
}
