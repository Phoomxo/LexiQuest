import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/word_games_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

const _categoryName = 'ชุดการเดินทาง';

void main() {
  testWidgets('Home opens the Word Games chooser', (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.openHome(tester);
      await _openGames(tester);
      await _wait(tester, find.text('เรียงตัวอักษร'));
      expect(find.text('เรียงประโยค'), findsOneWidget);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets('a set without an authored sentence stays in context', (
    tester,
  ) async {
    final fixture = _Fixture();
    try {
      await fixture.openHome(tester, spelling: 'apple', meaning: 'แอปเปิล');
      await _openGames(tester);
      await _tap(tester, 'เรียงประโยค');
      await _tap(tester, _categoryName);
      await _wait(tester, find.text('ชุดนี้ยังไม่มีคำที่มีประโยคฝึกที่รองรับ'));
      expect(find.text('ตรวจคำตอบ'), findsNothing);
      final sessions = await _withFrames(
        tester,
        'empty set session readback',
        () => fixture.database.select(fixture.database.learningSessions).get(),
      );
      expect(sessions, isEmpty);
      await _tap(tester, 'เลือกเกมอื่น');
      await _wait(tester, find.byType(WordGamesScreen));
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets('sentence practice returns to the exact cloze feedback', (
    tester,
  ) async {
    final fixture = _Fixture();
    try {
      await fixture.openHome(tester, includePlatform: true);
      await _tap(tester, 'ดูแบบฝึกทั้งหมด');
      await _tap(tester, 'เติมคำในประโยคแบบเลือก');
      await _tap(tester, _categoryName);
      await _wait(tester, find.text('The train is at ____ two.'));
      await _tap(tester, 'platform');
      final solvedSentence = find.text('The train is at platform two.');
      await _wait(tester, solvedSentence);

      Future<List<AnswerAttempt>> attempts() =>
          fixture.database.select(fixture.database.answerAttempts).get();
      final before = await _withFrames(tester, 'stored cloze answer', attempts);
      expect(before.single.promptMode, 'clozeChoice');
      expect(before.single.isCorrect, isTrue);
      await _tap(tester, 'ลองเรียงประโยค');
      final child = find.byWidgetPredicate(
        (widget) =>
            widget is QuizScreen &&
            widget.promptKind == QuizPromptKind.sentenceScramble,
      );
      await _wait(tester, find.text('รถไฟจอดอยู่ที่ชานชาลาสอง'));
      await _wait(tester, find.text('ตรวจคำตอบ'));
      final screen = tester.widget<QuizScreen>(child);
      expect(screen.originParentId, before.single.sessionId);
      expect(screen.wordIds, [before.single.wordId]);
      expect(screen.returnLabel, 'กลับไปดูผลเติมคำ');
      await _tapTile(tester, 'The');
      await tester.binding.handlePopRoute();
      await _waitFor(
        tester,
        () => child.evaluate().isEmpty && solvedSentence.evaluate().length == 1,
        'return to original cloze feedback after Android Back',
      );
      expect(find.text('เติมคำได้ถูกต้อง'), findsOneWidget);
      expect(
        await _withFrames(tester, 'answers after closing sentence', attempts),
        before,
      );
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'word and sentence games retry, save real results and return to choices at 200%',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.openHome(tester);
        await _openGames(tester);
        for (final (mode, kind, wrongTiles, rightTiles, wrongCopy, rightCopy)
            in [
              (
                'เรียงตัวอักษร',
                QuizPromptKind.wordScramble,
                ['t', 't', 'i', 'c', 'k', 'e'],
                ['t', 'i', 'c', 'k', 'e', 't'],
                'ลองอีกตัวหนึ่ง',
                'สะกดถูกแล้ว',
              ),
              (
                'เรียงประโยค',
                QuizPromptKind.sentenceScramble,
                ['I', 'have', 'ticket.', 'a'],
                ['I', 'have', 'a', 'ticket.'],
                'ลองสลับตำแหน่งคำ',
                'เรียงได้ถูกต้อง',
              ),
            ]) {
          await _openGame(tester, mode);
          for (final token in wrongTiles) {
            await _tapTile(tester, token);
          }
          await _tap(tester, 'ตรวจคำตอบ');
          await _wait(tester, find.text(wrongCopy));
          await _tap(tester, 'ลองข้อเดิม');

          for (final token in rightTiles.take(rightTiles.length - 1)) {
            await _tapTile(tester, token);
          }
          final lastPlaced = rightTiles[rightTiles.length - 2];
          await _tap(
            tester,
            kind == QuizPromptKind.wordScramble
                ? 'เอาตัวล่าสุดออก'
                : 'เอาคำล่าสุดออก',
          );
          await _tapTile(tester, lastPlaced);
          await _tapTile(tester, rightTiles.last);
          await _tap(tester, 'ตรวจคำตอบ');
          await _wait(tester, find.text(rightCopy));
          await _tap(tester, 'ดูผลการฝึก');
          await _wait(tester, find.byType(ScoreScreen));
          final result = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
          expect(result.correctAnswers, 1);
          expect(result.wrongAnswers, 1);
          final history = await _withFrames(
            tester,
            '$mode original result',
            () => fixture.progress.loadSession(result.sessionId!),
          );
          expect(history?.categoryId, fixture.categoryId);
          expect(history?.summary.correctCount, 1);
          expect(history?.summary.wrongCount, 1);
          expect(
            history?.originalAnswers?.map((answer) => answer.question.kind),
            [kind, kind],
          );
          expect(
            history?.originalAnswers?.map((answer) => answer.question.word.id),
            [fixture.wordId, fixture.wordId],
          );
          expect(history?.originalAnswers?.map((answer) => answer.isCorrect), [
            false,
            true,
          ]);
          final separator = kind == QuizPromptKind.wordScramble ? '' : ' ';
          expect(
            history?.originalAnswers?.map((answer) => answer.chosenAnswer),
            [wrongTiles.join(separator), rightTiles.join(separator)],
          );
          if (kind == QuizPromptKind.wordScramble) {
            await _tap(tester, 'ลองเรียงประโยค');
            await _wait(tester, find.text('ฉันมีตั๋วหนึ่งใบ'));
            await _wait(tester, find.text('ตรวจคำตอบ'));
            await _tapTile(tester, 'I');
            await tester.binding.handlePopRoute();
            await _waitFor(
              tester,
              () =>
                  find.byType(QuizScreen).evaluate().isEmpty &&
                  find.byType(ScoreScreen).evaluate().length == 1,
              'return to spelling result after closing sentence exercise',
            );
            final reopened = tester.widget<ScoreScreen>(
              find.byType(ScoreScreen),
            );
            expect(reopened.sessionId, result.sessionId);
          }
          await _tap(tester, 'เลือกเกมอื่น');
          await _waitFor(
            tester,
            () =>
                find.byType(WordGamesScreen).evaluate().length == 1 &&
                find.byType(ScoreScreen).evaluate().isEmpty &&
                find.byType(QuizScreen).evaluate().isEmpty,
            '$mode result and round to close before choosing another game',
          );
        }

        await tester.scrollUntilVisible(
          find.text('เรียงตัวอักษร'),
          -160,
          scrollable: find.byType(Scrollable).hitTestable().last,
        );
        await _openGame(tester, 'เรียงตัวอักษร');
        await _tapTile(tester, 't');
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await _wait(tester, find.byType(WordGamesScreen));
        final attempts = await _withFrames(
          tester,
          'attempts after Android Back',
          () => fixture.database.select(fixture.database.answerAttempts).get(),
        );
        expect(attempts, hasLength(4));
        final sessions = await _withFrames(
          tester,
          'completed sessions after Android Back',
          () =>
              fixture.database.select(fixture.database.learningSessions).get(),
        );
        expect(
          sessions.where((session) => session.state == 'completed'),
          hasLength(2),
        );
        await _tap(tester, 'กลับไปเลือกแบบฝึก');
        await _wait(tester, find.text('เลือกวิธีฝึก'));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}

final class _Fixture {
  final database = AppDatabase(NativeDatabase.memory());
  DateTime get now => DateTime.now().toUtc();
  int _sequence = 0;
  String _id() => 'synthetic-word-games-${++_sequence}';

  late final owners = DriftLocalOwnerRepository(
    database,
    generateId: _id,
    nowUtc: () => now,
  );
  late final vocabulary = VocabularyUseCases(
    owners: owners,
    vocabulary: DriftVocabularyRepository(database),
    generateId: _id,
    nowUtc: () => now,
  );
  late final learning = LearningUseCases(
    owners: owners,
    repository: DriftLearningRepository(database),
    generateId: _id,
    nowUtc: () => now,
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
  );
  late final progress = ProgressUseCases(
    owners: owners,
    queries: DriftProgressQueries(database),
    nowUtc: () => now,
  );
  late final dependencies = AppDependencies(
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
    learning: learning,
    progress: progress,
  );
  late final String categoryId;
  late final String wordId;

  Future<void> openHome(
    WidgetTester tester, {
    String spelling = 'ticket',
    String meaning = 'ตั๋ว',
    bool includePlatform = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(() async {
      final category = await vocabulary.createCategory(_categoryName);
      categoryId = category.id;
      final word = await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: spelling,
          meaning: meaning,
          partOfSpeech: 'noun',
        ),
      );
      wordId = word.id;
      if (includePlatform) {
        await vocabulary.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'platform',
            meaning: 'ชานชาลา',
            partOfSpeech: 'noun',
          ),
        );
      }
    });
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
          home: const ChooseModeScreen(),
        ),
      ),
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _withFrames(tester, 'database close', database.close);
    await tester.pump();
  }
}

Future<void> _openGames(WidgetTester tester) async {
  await _tap(tester, 'ดูแบบฝึกทั้งหมด');
  await _tap(tester, 'เกมฝึกคำ');
}

Future<void> _openGame(WidgetTester tester, String mode) async {
  await _tap(tester, mode);
  await _tap(tester, _categoryName);
  await _wait(tester, find.text('ตรวจคำตอบ'));
}

Future<void> _tapTile(WidgetTester tester, String value) async {
  final token = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('scramble-token-') &&
        widget is ButtonStyleButton &&
        widget.onPressed != null &&
        widget.child is Text &&
        (widget.child! as Text).data == value,
  );
  await _tapVisible(tester, token);
}

Future<void> _tap(WidgetTester tester, String label) async {
  await _tapVisible(tester, find.text(label));
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await _wait(tester, target);
  await tester.ensureVisible(target.first);
  await tester.pump();
  await tester.tap(target.hitTestable().first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _wait(WidgetTester tester, Finder target) => _waitFor(
  tester,
  () => target.evaluate().isNotEmpty,
  '$target',
  scroll: true,
);

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready,
  String description, {
  bool scroll = false,
}) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
    if (!scroll) continue;
    final scrollables = find.byType(Scrollable).hitTestable();
    if (scrollables.evaluate().isEmpty) continue;
    await tester.drag(scrollables.last, const Offset(0, -160));
    await tester.pump();
  }
  fail('Timed out waiting for $description in Word Games');
}

Future<T> _withFrames<T>(
  WidgetTester tester,
  String description,
  Future<T> Function() operation,
) async {
  var done = false;
  final pending = operation().whenComplete(() => done = true);
  unawaited(pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  for (var i = 0; i < 80 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!done) fail('Timed out waiting for $description in Word Games');
  return pending;
}

final class _GuestSession extends Fake implements GuestSessionService {}
