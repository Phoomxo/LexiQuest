import 'dart:async';

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
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets('Library resumes the same paused Quiz in its original set only', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 11, 14);
    var nextId = 0;
    String generateId() =>
        'synthetic-quiz-${(++nextId).toString().padLeft(2, '0')}';
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-quiz-owner',
      nowUtc: () => now,
    );
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: generateId,
      nowUtc: () => now,
    );
    final repository = DriftLearningRepository(database);
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      vocabulary: vocabulary,
      learning: LearningUseCases(
        owners: owners,
        repository: repository,
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
      await tester.runAsync(() async {
        for (final (name, first, second) in [
          ('ชุด A', ('station', 'สถานี'), ('ticket', 'ตั๋ว')),
          ('ชุด B', ('apple', 'แอปเปิล'), ('banana', 'กล้วย')),
        ]) {
          final category = await vocabulary.createCategory(name);
          for (final (spelling, meaning) in [first, second]) {
            await vocabulary.createWord(
              CreateWordCommand(
                categoryId: category.id,
                spelling: spelling,
                meaning: meaning,
                partOfSpeech: 'noun',
              ),
            );
          }
        }
      });
      await _openLibrary(tester, dependencies);
      await _enterQuiz(tester, 'ชุด A', 'station');
      await _tap(tester, 'สถานี');
      await _tap(tester, 'คำถามถัดไป');
      await _wait(tester, () => _quizText('ticket').evaluate().isNotEmpty);
      expect(_quizText('คำถาม 2 จาก 2'), findsOneWidget);
      final secondQuestionOptions = _quizChoices(tester);

      await _tap(tester, 'พักรอบนี้');
      await _wait(tester, () => find.byType(QuizScreen).evaluate().isEmpty);
      expect(find.byType(VocabListScreen), findsOneWidget);
      expect(find.text('ชุด A'), findsOneWidget);

      final paused = (await tester.runAsync(
        () => database.select(database.learningSessions).getSingle(),
      ))!;
      expect(paused.state, 'paused');
      expect(paused.correctCount, 1);
      final first = (await tester.runAsync(
        () => database.select(database.answerAttempts).getSingle(),
      ))!;
      expect(first.sessionId, paused.id);
      final plan = decodeQuizPlan(paused.questionPlanJson!);
      expect(decodeQuizCursor(paused.continuationJson!, plan: plan).slot, 1);

      // Remount the library so the resumed route cannot reuse any widget state.
      await tester.pumpWidget(const SizedBox.shrink());
      await _openLibrary(tester, dependencies);
      await _enterQuiz(tester, 'ชุด B', 'apple');
      expect(_quizText('คำถาม 1 จาก 2'), findsOneWidget);
      expect(_quizText('พักที่คำถาม 2 จาก 2'), findsNothing);
      expect(_quizText('ticket'), findsNothing);
      await _back(tester, QuizScreen);
      await _back(tester, VocabListScreen);

      await _tap(tester, 'ชุด A');
      await _wait(tester, () => find.text('station').evaluate().isNotEmpty);
      await _tap(tester, 'ฝึกจากชุดนี้');
      await _wait(
        tester,
        () => _quizText('พักที่คำถาม 2 จาก 2').evaluate().isNotEmpty,
      );
      await _tap(tester, 'ฝึกต่อ');
      await _wait(tester, () => _quizText('ticket').evaluate().isNotEmpty);
      expect(_quizText('คำถาม 2 จาก 2'), findsOneWidget);
      expect(_quizChoices(tester), secondQuestionOptions);

      await _tap(tester, 'ตั๋ว');
      await _tap(tester, 'ดูผลการเรียน');
      await _wait(tester, () => find.byType(ScoreScreen).evaluate().isNotEmpty);
      expect(find.text('100%'), findsOneWidget);
      final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
      expect(score.sessionId, paused.id);
      expect(score.correctAnswers, 2);
      await _tap(tester, 'กลับไปที่ชุดคำ');
      await _wait(tester, () => find.byType(ScoreScreen).evaluate().isEmpty);
      await _wait(
        tester,
        () => find.text('ฝึกจากชุดนี้').evaluate().isNotEmpty,
      );
      expect(find.text('ชุด A'), findsOneWidget);
      expect(find.text('ticket'), findsOneWidget);
      expect(find.text('apple'), findsNothing);

      final sessions = (await tester.runAsync(
        () => database.select(database.learningSessions).get(),
      ))!;
      expect(sessions, hasLength(2));
      final stored = sessions.singleWhere((s) => s.id == paused.id);
      expect(
        (stored.state, stored.correctCount, stored.score),
        ('completed', 2, 100),
      );
      expect(stored.questionPlanJson, paused.questionPlanJson);
      final attempts = (await tester.runAsync(
        () => database.select(database.answerAttempts).get(),
      ))!;
      expect(attempts, hasLength(2));
      expect(attempts, contains(first));
      expect(attempts.map((a) => a.sessionId).toSet(), {paused.id});
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      var closed = false;
      final closing = database.close().whenComplete(() => closed = true);
      unawaited(closing.then<void>((_) {}, onError: (Object _) {}));
      await _wait(tester, () => closed, description: 'database close');
      await closing;
      await tester.pump();
    }
  });
}

Finder _quizText(String text) =>
    find.descendant(of: find.byType(QuizScreen), matching: find.text(text));

List<String> _quizChoices(WidgetTester tester) => tester
    .widgetList<FilledButton>(
      find.descendant(
        of: find.byType(QuizScreen),
        matching: find.byType(FilledButton),
      ),
    )
    .map((button) => (button.child as Text).data!)
    .toList();

Future<void> _openLibrary(WidgetTester tester, AppDependencies dependencies) =>
    tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: const MaterialApp(home: CategoriesPage()),
      ),
    );

Future<void> _enterQuiz(
  WidgetTester tester,
  String category,
  String prompt,
) async {
  await _tap(tester, category);
  await _wait(tester, () => find.text(prompt).evaluate().isNotEmpty);
  await _tap(tester, 'ฝึกจากชุดนี้');
  await _wait(tester, () => _quizText(prompt).evaluate().isNotEmpty);
}

Future<void> _tap(WidgetTester tester, String text) async {
  final target = find.text(text);
  await _wait(tester, () => target.evaluate().isNotEmpty, description: text);
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _back(WidgetTester tester, Type screen) async {
  final route = find.byType(screen);
  final button = find
      .descendant(of: route, matching: find.byType(BackButton))
      .hitTestable();
  await _wait(
    tester,
    () => button.evaluate().length == 1,
    description: '$screen Back',
  );
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _wait(
    tester,
    () => route.evaluate().isEmpty,
    description: '$screen exit',
  );
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready, {
  String description = 'route or stored state',
}) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('Timed out waiting for $description in the durable Quiz journey');
}

final class _GuestSession extends Fake implements GuestSessionService {}
