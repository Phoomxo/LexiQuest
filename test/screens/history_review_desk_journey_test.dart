import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/quiz_round.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/review_desk_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets('History Review Desk practices only the original missed word', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final now = DateTime.utc(2026, 11, 15);
    const secondOwnerId = 'local:history-test-other-owner';
    var nextId = 0;
    String generateId() =>
        'history-test-${(++nextId).toString().padLeft(2, '0')}';
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'history-test-owner',
      nowUtc: () => now,
    );
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: generateId,
      nowUtc: () => now,
    );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      database: database,
      localOwners: owners,
      vocabulary: vocabulary,
      learning: LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: generateId,
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      ),
      progress: ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => now,
      ),
    );

    try {
      final stationId = (await tester.runAsync(() async {
        final category = await vocabulary.createCategory('การเดินทางทดสอบ');
        final station = await vocabulary.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'station',
            meaning: 'สถานี',
            partOfSpeech: 'noun',
          ),
        );
        await vocabulary.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'platform',
            meaning: 'ชานชาลา',
            partOfSpeech: 'noun',
          ),
        );
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: secondOwnerId,
                createdAtUtcMs: now.millisecondsSinceEpoch,
                isActive: const Value(false),
              ),
            );
        return station.id;
      }))!;

      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const MainNavigationScreen(initialIndex: 1),
          ),
        ),
      );

      await _tap(tester, find.text('การเดินทางทดสอบ'));
      await _tap(tester, find.text('ฝึกจากชุดนี้'));
      await _waitFor(tester, find.text('ตั้งค่าก่อนฝึก'));
      await _reveal(
        tester,
        find.text('เริ่มฝึก'),
        within: find.byType(QuizScreen),
      );
      await _tap(tester, find.text('เริ่มฝึก'));
      await _waitFor(tester, find.text('คำถาม 1 จาก 2'));
      expect(find.text('station'), findsOneWidget);
      await _tap(tester, find.text('ชานชาลา'));
      await _tap(tester, find.text('คำถามถัดไป'));
      await _waitFor(tester, find.text('platform'));
      await _tap(tester, find.text('ชานชาลา'));
      await _tap(tester, find.text('ดูผลการเรียน'));
      await _waitFor(tester, find.text('50%'));

      final original = (await tester.runAsync(
        () => database.select(database.learningSessions).getSingle(),
      ))!;
      final originalAttempts = (await tester.runAsync(
        () => database.select(database.answerAttempts).get(),
      ))!;
      expect(originalAttempts, hasLength(2));
      expect(
        originalAttempts.where((attempt) => !attempt.isCorrect).single.wordId,
        stationId,
      );

      await _tap(tester, find.text('กลับไปที่ชุดคำ'));
      final listBack = find.descendant(
        of: find.byType(VocabListScreen),
        matching: find.byType(BackButton),
      );
      await _tap(tester, listBack);
      await _tap(tester, find.text('ความก้าวหน้า'));
      final dashboard = find.byType(MasteryDashboardScreen);
      final historyRow = find.byKey(ValueKey('history-session:${original.id}'));
      await _reveal(tester, historyRow, within: dashboard);
      expect(find.text('ประวัติการฝึก'), findsOneWidget);
      expect(
        find.descendant(of: historyRow, matching: find.text('เลือกความหมาย')),
        findsOneWidget,
      );
      await _tap(tester, historyRow);

      final originalScore = find.descendant(
        of: _currentScreen<ScoreScreen>(),
        matching: find.byKey(ValueKey('score-session:${original.id}')),
      );
      final originalAnswers = _currentText<ScoreScreen>('คำตอบจากรอบเดิม');
      final deskTitle = _currentText<ReviewDeskScreen>('เลือกสิ่งที่จะทบทวน');
      await _waitFor(tester, originalScore);
      expect(_currentText<ScoreScreen>('50%'), findsOneWidget);
      expect(originalAnswers, findsOneWidget);
      await _tap(tester, _currentText<ScoreScreen>('เปิดศูนย์ทบทวน'));
      await _waitFor(tester, deskTitle);
      await _tap(
        tester,
        _currentText<ReviewDeskScreen>('ฝึกคำที่ผิดจากรอบนี้ (1)'),
      );
      await _waitFor(tester, _currentText<QuizScreen>('คำถาม 1 จาก 1'));
      expect(_currentText<QuizScreen>('station'), findsOneWidget);
      await _tap(tester, _currentText<QuizScreen>('สถานี'));
      await _tap(tester, _currentText<QuizScreen>('ดูผลการเรียน'));
      await _waitFor(tester, _currentText<ScoreScreen>('100%'));

      await _tap(tester, _currentText<ScoreScreen>('กลับศูนย์ทบทวน'));
      await _waitFor(tester, deskTitle);
      await _tap(tester, _currentText<ReviewDeskScreen>('กลับไปดูผลเดิม'));
      await _waitFor(tester, originalScore);
      expect(_currentText<ScoreScreen>('50%'), findsOneWidget);
      expect(originalAnswers, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        final sessions = await database.select(database.learningSessions).get();
        expect(sessions, hasLength(2));
        expect(
          sessions.singleWhere((session) => session.id == original.id),
          original,
        );
        final child = sessions.singleWhere(
          (session) => session.id != original.id,
        );
        expect(child.ownerId, original.ownerId);
        expect(child.score, 100);
        final plan = decodeQuizPlan(child.questionPlanJson!);
        expect(plan.origin.parentId, original.id);
        expect(plan.questions.map((question) => question.word.id), [stationId]);

        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(3));
        expect(
          attempts.where((attempt) => attempt.sessionId == original.id),
          unorderedEquals(originalAttempts),
        );
        final retry = attempts.singleWhere(
          (attempt) => attempt.sessionId == child.id,
        );
        expect(retry.wordId, stationId);
        expect(retry.isCorrect, isTrue);
        expect(await database.select(database.researchConsents).get(), isEmpty);
        expect(await database.select(database.eventsV2).get(), isEmpty);
      });

      await _tap(tester, _currentText<ScoreScreen>('ฝึกคำที่ผิด (1)'));
      final directQuestion = _currentText<QuizScreen>('คำถาม 1 จาก 1');
      final directWord = _currentText<QuizScreen>('station');
      await _waitFor(tester, directQuestion);
      expect(directWord, findsOneWidget);
      final switchOwners = database.transaction(() async {
        Future<void> setActive(String ownerId, bool active) async {
          await (database.update(database.localOwners)
                ..where((row) => row.id.equals(ownerId)))
              .write(LocalOwnersCompanion(isActive: Value(active)));
        }

        await setActive(original.ownerId, false);
        await setActive(secondOwnerId, true);
        await setActive(secondOwnerId, false);
        await setActive(original.ownerId, true);
      });
      var switchCompleted = false;
      unawaited(
        switchOwners.then<void>(
          (_) {
            switchCompleted = true;
          },
          onError: (Object _, StackTrace _) {
            switchCompleted = true;
          },
        ),
      );
      for (var frame = 0; frame < 40 && !switchCompleted; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (!switchCompleted) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
      }
      expect(
        switchCompleted,
        isTrue,
        reason: 'Owner transaction did not finish',
      );
      await switchOwners;
      final active = await (database.select(
        database.localOwners,
      )..where((row) => row.isActive.equals(true))).getSingle();
      expect(active.id, original.ownerId);
      await _waitFor(
        tester,
        _currentText<QuizScreen>('บัญชีผู้เรียนเปลี่ยนแล้ว'),
      );
      expect(directQuestion, findsNothing);
      expect(directWord, findsNothing);
      await _tap(tester, _currentText<QuizScreen>('กลับไปที่ผลการฝึก'));
      await _waitFor(
        tester,
        _currentText<ScoreScreen>('กรุณากลับไปเปิดผลการฝึกอีกครั้ง'),
      );
      expect(originalScore, findsNothing);
      expect(originalAnswers, findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => database.close().timeout(const Duration(seconds: 5)),
      );
    }
  });
}

Finder _currentScreen<T extends Widget>() => find.byElementPredicate(
  (element) => element.widget is T && ModalRoute.isCurrentOf(element) == true,
);

Finder _currentText<T extends Widget>(String label) =>
    find.descendant(of: _currentScreen<T>(), matching: find.text(label));

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  required Finder within,
}) async {
  final viewport = find
      .descendant(
        of: within,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .hitTestable();
  await _waitFor(tester, viewport);
  await tester.scrollUntilVisible(target, 180, scrollable: viewport.first);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _waitFor(tester, target);
  await tester.ensureVisible(target.first);
  final tappable = target.hitTestable();
  await _waitFor(tester, tappable);
  await tester.tap(tappable.first);
  await tester.pump();
}

Future<void> _waitFor(WidgetTester tester, Finder target) async {
  for (var frame = 0; frame < 80; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (target.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  final screenText = find.byType(Text).evaluate().map((element) {
    final text = element.widget as Text;
    return text.data ?? text.textSpan?.toPlainText();
  }).whereType<String>();
  fail(
    'Timed out waiting for $target. Screen text: ${screenText.take(28).join(' | ')}',
  );
}

final class _GuestSession extends Fake implements GuestSessionService {}
