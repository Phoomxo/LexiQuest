import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_associative_learning_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
  });
  late AppDatabase database;
  late LearningUseCases learning;
  var id = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    id = 0;
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => DateTime.utc(2026, 7, 30, 10),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: owner.id,
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-1',
            ownerId: owner.id,
            categoryId: 'category-1',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'สถานี',
            normalizedMeaning: 'สถานี',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++id}',
      nowUtc: () => DateTime.utc(2026, 7, 30, 10, 1),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
  });

  tearDown(() => database.close());

  testWidgets('associative reading persists recall, cue, and completion', (
    tester,
  ) async {
    final setup = await tester.runAsync(() async {
      final words = await learning.prepareReading(limit: 1);
      final owner = await learning.owners.getOrCreateActiveOwner();
      return (words: words, owner: owner);
    });
    final words = setup!.words;
    final owner = setup.owner;
    final associations = DriftAssociativeLearningAdapter(database);
    final word = words.single;
    await tester.pumpWidget(
      MaterialApp(
        home: AssociativeReadingSessionScreen(
          cefrLevel: 'B1',
          targetWords: [word.spelling],
          passageText: 'The station is near the city center.',
          documentId: 'reading-test',
          learning: learning,
          associativeLearning: associations,
          targetWordIds: {word.spelling: word.id},
          ownerId: owner.id,
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'));
    expect(
      await tester.runAsync(
        () => database.select(database.learningSessions).get(),
      ),
      isEmpty,
    );

    await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
    await _pumpUntilFound(tester, find.text('ขั้นที่ 2: อ่านโดยลดตัวช่วย'));
    await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
    await _pumpUntilFound(tester, find.text('ขั้นที่ 3: ทดสอบจากความจำ'));
    await tester.enterText(find.byType(TextField).first, word.spelling);
    final recallContinue = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'เสร็จแล้ว ไปขั้นถัดไป'),
    );
    recallContinue.onPressed!();
    recallContinue.onPressed!();
    await _pumpUntilFound(tester, find.text('ขั้นที่ 4: สร้างตัวช่วยจำ'));
    await tester.enterText(find.byType(TextField).first, 'train stop');
    await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
    await _pumpUntilFound(tester, find.text('ขั้นที่ 5: แต่งประโยคใหม่'));
    await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
    await _pumpUntilFound(tester, find.text('ขั้นที่ 6: สรุปผล'));
    await tester.tap(find.text('บันทึกและจบการฝึก'));
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final state = await tester.runAsync(
        () async =>
            (await database.select(database.learningSessions).getSingle())
                .state,
      );
      if (state == 'completed') break;
    }

    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    expect(
      await associations.getAssociationsForWord(owner.id, word.spelling),
      hasLength(1),
    );
    final storedSession = await database
        .select(database.learningSessions)
        .getSingle();
    expect(storedSession.state, 'completed');
  });

  testWidgets(
    'associative recall retries without completing partial evidence',
    (tester) async {
      final owner = await tester.runAsync(
        () => learning.owners.getOrCreateActiveOwner(),
      );
      await tester.runAsync(
        () => database
            .into(database.vocabularyWords)
            .insert(
              VocabularyWordsCompanion.insert(
                id: 'word-2',
                ownerId: owner!.id,
                categoryId: 'category-1',
                spelling: 'ticket',
                normalizedSpelling: 'ticket',
                meaning: 'ตั๋ว',
                normalizedMeaning: 'ตั๋ว',
                partOfSpeech: 'noun',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            ),
      );
      final failingLearning = LearningUseCases(
        owners: learning.owners,
        repository: _FailOnceRepository(
          DriftLearningRepository(database),
          false,
          failOnCall: 2,
        ),
        generateId: () => '${++id}',
        nowUtc: () => DateTime.utc(2026, 7, 30, 10, 1),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      final setup = await tester.runAsync(() async {
        final words = await failingLearning.prepareReading(limit: 2);
        final owner = await failingLearning.owners.getOrCreateActiveOwner();
        return (words: words, owner: owner);
      });
      final words = setup!.words;
      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'B1',
            targetWords: words.map((word) => word.spelling).toList(),
            passageText: 'The station sells a ticket for the train.',
            documentId: 'reading-retry-test',
            learning: failingLearning,
            targetWordIds: {for (final word in words) word.spelling: word.id},
            ownerId: setup.owner.id,
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'));
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _pumpUntilFound(tester, find.text('ขั้นที่ 2: อ่านโดยลดตัวช่วย'));
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _pumpUntilFound(tester, find.text('ขั้นที่ 3: ทดสอบจากความจำ'));
      await tester.enterText(find.byType(TextField).at(0), words[0].spelling);
      await tester.enterText(find.byType(TextField).at(1), words[1].spelling);

      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _pumpUntilFound(
        tester,
        find.text('บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง'),
      );
      expect(find.text('ขั้นที่ 3: ทดสอบจากความจำ'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).at(0),
        'edited after commit',
      );

      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _pumpUntilFound(tester, find.text('ขั้นที่ 4: สร้างตัวช่วยจำ'));
      final evidence = await tester.runAsync(() async {
        final attempts = await database.select(database.answerAttempts).get();
        final session = await database
            .select(database.learningSessions)
            .getSingle();
        return (attempts: attempts, session: session);
      });
      expect(evidence!.attempts, hasLength(2));
      expect(evidence.session.state, 'completed');
    },
  );

  testWidgets('answer is durable before score screen is shown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(categoryId: 'category-1', learning: learning),
      ),
    );
    await _pumpUntilFound(tester, find.text('station'));

    expect(find.text('station'), findsOneWidget);
    await tester.tap(find.text('สถานี'));
    await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
    await tester.tap(find.text('ดูผลการเรียน'));
    await _pumpUntilFound(tester, find.byType(ScoreScreen));

    expect(find.byType(ScoreScreen), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    final session = await database
        .select(database.learningSessions)
        .getSingle();
    expect(session.state, 'completed');
  });

  testWidgets('source-selected quiz uses source semantics and title', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: QuizScreen(
          wordIds: const ['word-1'],
          selectionMode: QuizWordSelectionMode.sourcePractice,
          learning: learning,
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('แบบทดสอบจากเนื้อหานี้'));
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('แบบทดสอบจากเนื้อหานี้'))
          .didExceedMaxLines,
      isFalse,
    );
    expect(find.text('station'), findsOneWidget);
    final session = await tester.runAsync(
      () => database.select(database.learningSessions).getSingle(),
    );
    expect(session!.activityType, 'sourcePractice');
  });

  testWidgets('quiz route title fits compact 200 percent text with Back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: M3Theme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QuizScreen(learning: learning),
                ),
              ),
              child: const Text('เปิดแบบทดสอบ'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดแบบทดสอบ'));
    await _pumpUntilFound(tester, find.text('station'));

    expect(find.byType(BackButton), findsOneWidget);
    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('แบบทดสอบคำศัพท์'),
    );
    expect(title, findsOneWidget);
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 96);
    expect(tester.widget<Text>(title).maxLines, 2);
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('clinic starts a real targeted session even with no due words', (
    tester,
  ) async {
    final progress = (await tester.runAsync(() async {
      final session = await learning.startQuiz(limit: 1);
      var quiz = session.configured!;
      quiz = await learning.prepareQuizAnswer(
        sessionId: quiz.sessionId,
        expectedOwnerId: quiz.ownerId,
        expectedRevision: quiz.checkpointRevision,
        revealed: true,
      );
      quiz = (await learning.commitQuizAnswer(
        sessionId: quiz.sessionId,
        expectedOwnerId: quiz.ownerId,
        expectedRevision: quiz.checkpointRevision,
      )).state;
      quiz = await learning.prepareQuizFinish(
        sessionId: quiz.sessionId,
        expectedOwnerId: quiz.ownerId,
        expectedRevision: quiz.checkpointRevision,
      );
      await learning.finishConfiguredQuiz(
        sessionId: quiz.sessionId,
        expectedOwnerId: quiz.ownerId,
        expectedRevision: quiz.checkpointRevision,
      );
      final owner = await database.select(database.localOwners).getSingle();
      return DriftProgressQueries(
        database,
      ).load(ownerId: owner.id, nowUtc: learning.nowUtc());
    }))!;
    expect(progress.dueReviewCount, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(
          learning: learning,
          loader: () async => progress,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ฝึกคำที่ผิด (1)'));
    await _pumpUntilFound(tester, find.text('คำถาม 1 จาก 1'));
    await tester.pumpAndSettle();
    expect(find.text('station'), findsOneWidget);
    final sessions = await database.select(database.learningSessions).get();
    expect(sessions.last.activityType, 'weaknessPractice');
  });

  for (final afterCommit in [false, true]) {
    testWidgets(
      'reveal retries one incorrect intent afterCommit=$afterCommit',
      (tester) async {
        final repository = _FailOnceRepository(
          learning.repository,
          afterCommit,
        );
        final failing = LearningUseCases(
          owners: learning.owners,
          repository: repository,
          generateId: () => '${++id}',
          nowUtc: learning.nowUtc,
          buildInfo: learning.buildInfo,
        );
        await tester.pumpWidget(
          MaterialApp(home: QuizScreen(learning: failing)),
        );
        await _pumpUntilFound(tester, find.text('station'));
        await tester.tap(find.text('เฉลยคำตอบ'));
        await _pumpUntilFound(tester, find.text('ลองบันทึกอีกครั้ง'));
        expect(find.text('station — สถานี'), findsNothing);
        await tester.tap(find.text('ลองบันทึกอีกครั้ง'));
        await _pumpUntilFound(tester, find.text('station — สถานี'));
        expect(find.text('คำตอบของคุณ: ไม่ได้ตอบ (ขอเฉลย)'), findsOneWidget);
        expect(repository.commands, hasLength(2));
        expect(
          _evidence(repository.commands.last),
          _evidence(repository.commands.first),
        );
        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(1));
        expect(attempts.single.isCorrect, isFalse);
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          isEmpty,
        );
        expect(
          await database.select(database.rewardTransactions).get(),
          isEmpty,
        );
      },
    );

    testWidgets(
      'answer retry preserves one attempt when afterCommit=$afterCommit',
      (tester) async {
        final repository = _FailOnceRepository(
          learning.repository,
          afterCommit,
        );
        final failing = LearningUseCases(
          owners: learning.owners,
          repository: repository,
          generateId: () => '${++id}',
          nowUtc: learning.nowUtc,
          buildInfo: learning.buildInfo,
        );
        await tester.pumpWidget(
          MaterialApp(home: QuizScreen(learning: failing)),
        );
        await _pumpUntilFound(tester, find.text('station'));
        await tester.tap(find.text('สถานี'));
        await _pumpUntilFound(
          tester,
          find.text('บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง'),
        );
        expect(find.text('ถูกต้อง'), findsNothing);
        expect(find.text('ลองบันทึกอีกครั้ง'), findsOneWidget);
        await tester.tap(find.text('ลองบันทึกอีกครั้ง'));
        await _pumpUntilFound(tester, find.text('ถูกต้อง'));
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          hasLength(1),
        );
        final coins = await database.select(database.rewardTransactions).get();
        expect(coins, hasLength(1));
        expect(coins.single.transactionType, 'creditQuizCorrectV1');
        expect(coins.single.amount, 1);
        expect(
          _evidence(repository.commands.last),
          _evidence(repository.commands.first),
        );
      },
    );
  }

  testWidgets(
    'reveal double tap waits for acknowledgement then practices the mistake',
    (tester) async {
      final acknowledgement = Completer<void>();
      addTearDown(() {
        if (!acknowledgement.isCompleted) acknowledgement.complete();
      });
      final repository = _FailOnceRepository(
        learning.repository,
        false,
        failOnCall: 0,
        acknowledgement: acknowledgement.future,
      );
      final pending = LearningUseCases(
        owners: learning.owners,
        repository: repository,
        generateId: () => '${++id}',
        nowUtc: learning.nowUtc,
        buildInfo: learning.buildInfo,
      );
      await tester.pumpWidget(MaterialApp(home: QuizScreen(learning: pending)));
      await _pumpUntilFound(tester, find.text('station'));
      await tester.tap(find.text('เฉลยคำตอบ'));
      await tester.tap(find.text('เฉลยคำตอบ'));
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator).last,
            )
            .semanticsLabel,
        'กำลังบันทึกคำตอบ',
      );
      expect(repository.commands, hasLength(1));
      expect(find.text('station — สถานี'), findsNothing);
      expect(find.text('ดูผลการเรียน'), findsNothing);
      acknowledgement.complete();
      await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
      expect(repository.commands.single.isCorrect, isFalse);
      await tester.tap(find.text('ดูผลการเรียน'));
      await _pumpUntilFound(tester, find.byType(ScoreScreen));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ฝึกคำที่ผิด (1)'));
      await _pumpUntilFound(tester, find.text('ฝึกคำที่ผิด'));
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(await database.select(database.rewardTransactions).get(), isEmpty);
    },
  );

  testWidgets('hint uses existing part of speech without writing evidence', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: QuizScreen(learning: learning)));
    await _pumpUntilFound(tester, find.text('station'));
    final before = (await database.select(database.outboxOperations).get())
        .map((r) => r.toJson())
        .toList();
    expect(find.text('noun'), findsNothing);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('ดูคำใบ้'));
      await _pumpUntilFound(tester, find.text('noun'));
      expect(find.text('noun'), findsOneWidget);
      await tester.tap(find.text('ซ่อนคำใบ้'));
      await _pumpUntilFound(tester, find.text('ดูคำใบ้'));
    }
    expect(await database.select(database.answerAttempts).get(), isEmpty);
    expect(await database.select(database.pointsLedgerEntries).get(), isEmpty);
    expect(await database.select(database.rewardTransactions).get(), isEmpty);
    expect(
      (await database.select(database.outboxOperations).get()).map(
        (r) => r.toJson(),
      ),
      before,
    );
  });

  testWidgets('hiding a seen hint retains the captured answer receipt', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: QuizScreen(learning: learning)));
    await _pumpUntilFound(tester, find.text('station'));
    await tester.tap(find.text('ดูคำใบ้'));
    await _pumpUntilFound(tester, find.text('noun'));
    await tester.tap(find.text('ซ่อนคำใบ้'));
    await _pumpUntilFound(tester, find.text('ดูคำใบ้'));
    expect(find.text('noun'), findsNothing);
    await tester.tap(find.text('สถานี'));
    await _pumpUntilFound(tester, find.text('ถูกต้อง'));

    final answer = await database.select(database.answerAttempts).getSingle();
    final context =
        jsonDecode(answer.evidenceContextJson) as Map<String, dynamic>;
    expect(answer.evidenceClass, 'guidedPractice');
    expect(context['hintLevel'], 1);
    expect(context['contentRevision'], 'local-vocabulary-v1:1');
    expect(context['researchConsentVersion'], isNull);
  });

  testWidgets('quiz hint reveal and failed save remain reachable at 2x', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      await database.customUpdate(
        "UPDATE vocabulary_words SET meaning = 'คำแปลสังเคราะห์ที่ยาวเพื่อทดสอบการเลื่อนและการขยายตัวอักษร', part_of_speech = 'ชนิดคำสังเคราะห์สำหรับใช้ทดสอบคำใบ้ที่มีข้อความยาว'",
      );
      final failing = LearningUseCases(
        owners: learning.owners,
        repository: _FailOnceRepository(learning.repository, false),
        generateId: () => '${++id}',
        nowUtc: learning.nowUtc,
        buildInfo: learning.buildInfo,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: QuizScreen(learning: failing),
        ),
      );
      await _pumpUntilFound(tester, find.text('station'));
      await tester.ensureVisible(find.text('ดูคำใบ้'));
      await tester.tap(find.text('ดูคำใบ้'));
      await _pumpUntilFound(
        tester,
        find.text('ชนิดคำสังเคราะห์สำหรับใช้ทดสอบคำใบ้ที่มีข้อความยาว'),
      );
      expect(
        find.text('ชนิดคำสังเคราะห์สำหรับใช้ทดสอบคำใบ้ที่มีข้อความยาว'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('เฉลยคำตอบ'));
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'เฉลยคำตอบ')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('เฉลยคำตอบ'));
      await _pumpUntilFound(tester, find.text('ลองบันทึกอีกครั้ง'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ลองบันทึกอีกครั้ง'));
      await tester.tap(find.text('ลองบันทึกอีกครั้ง'));
      await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
        findsWidgets,
      );
      await tester.ensureVisible(find.text('ดูผลการเรียน'));
      expect(find.text('ดูผลการเรียน').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('quiz feedback and next action fit large Thai text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: 'NotoSansThai'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: QuizScreen(learning: learning),
      ),
    );
    await _pumpUntilFound(tester, find.text('station'));
    await tester.tap(find.text('สถานี'));
    await _pumpUntilFound(tester, find.text('ถูกต้อง'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/quiz_feedback_large_text.png'),
    );
    await tester.scrollUntilVisible(find.text('ดูผลการเรียน'), 150);
    expect(find.text('ดูผลการเรียน').hitTestable(), findsOneWidget);
  });

  testWidgets('answer feedback uses accessible dark semantic color pairs', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final owner = await database.select(database.localOwners).getSingle();
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-color-pair',
            ownerId: owner.id,
            categoryId: 'category-1',
            spelling: 'ticket',
            normalizedSpelling: 'ticket',
            meaning: 'ตั๋ว',
            normalizedMeaning: 'ตั๋ว',
            partOfSpeech: 'noun',
            createdAtUtcMs: 2,
            updatedAtUtcMs: 2,
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: M3Theme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: QuizScreen(learning: learning),
      ),
    );
    await _pumpUntilFound(tester, find.text('station'));
    final wrongAnswer = tester
        .widgetList<FilledButton>(find.byType(FilledButton))
        .map((button) => (button.child as Text).data!)
        .firstWhere((label) => label != 'สถานี');
    await tester.tap(find.widgetWithText(FilledButton, wrongAnswer));
    await _pumpUntilFound(tester, find.text('ยังไม่ถูก ลองดูคำแปลอีกครั้ง'));

    final correctAnswer = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'สถานี'),
    );
    final selectedWrongAnswer = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, wrongAnswer),
    );
    final scheme = M3Theme.darkTheme.colorScheme;
    expect(
      correctAnswer.style?.backgroundColor?.resolve({}),
      scheme.tertiaryContainer,
    );
    expect(
      correctAnswer.style?.foregroundColor?.resolve({}),
      scheme.onTertiaryContainer,
    );
    expect(
      selectedWrongAnswer.style?.backgroundColor?.resolve({}),
      scheme.errorContainer,
    );
    expect(
      selectedWrongAnswer.style?.foregroundColor?.resolve({}),
      scheme.onErrorContainer,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing category shows honest empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(categoryId: 'missing', learning: learning),
      ),
    );
    final emptyState = find.textContaining('ยังไม่มีคำศัพท์สำหรับแบบทดสอบ');
    await _pumpUntilFound(tester, emptyState);

    expect(emptyState, findsOneWidget);
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  testWidgets('load failure is announced as a live region', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: QuizScreen()));
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังเตรียมแบบทดสอบ',
    );
    await tester.pumpAndSettle();

    final message = find.text(
      'เปิดแบบทดสอบไม่สำเร็จ กรุณาลองอีกครั้งหรือกลับไปเลือกกิจกรรม',
    );
    expect(message, findsOneWidget);
    expect(
      tester
          .widgetList<Semantics>(
            find.ancestor(of: message, matching: find.byType(Semantics)),
          )
          .any((widget) => widget.properties.liveRegion == true),
      isTrue,
    );
  });

  testWidgets(
    'wrong answer is explained then practiced from the score screen',
    (tester) async {
      final owner = await database.select(database.localOwners).getSingle();
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'word-2',
              ownerId: owner.id,
              categoryId: 'category-1',
              spelling: 'ticket',
              normalizedSpelling: 'ticket',
              meaning: 'ตั๋ว',
              normalizedMeaning: 'ตั๋ว',
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      var hubLoads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            learning: learning,
            loader: () {
              hubLoads++;
              return DriftProgressQueries(
                database,
              ).load(ownerId: owner.id, nowUtc: learning.nowUtc());
            },
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('เริ่มฝึกคำศัพท์'));
      await tester.tap(find.text('เริ่มฝึกคำศัพท์'));
      await _pumpUntilFound(tester, find.text('station'));
      await tester.tap(find.text('ตั๋ว'));
      await _pumpUntilFound(tester, find.text('คำถามถัดไป'));
      expect(find.text('ยังไม่ถูก ลองดูคำแปลอีกครั้ง'), findsOneWidget);
      expect(find.text('station — สถานี'), findsOneWidget);
      await tester.tap(find.text('คำถามถัดไป'));
      await _pumpUntilFound(tester, find.text('คำถาม 2 จาก 2'));
      await tester.tap(find.text('ตั๋ว'));
      await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
      await tester.tap(find.text('ดูผลการเรียน'));
      await _pumpUntilFound(tester, find.byType(ScoreScreen));
      await tester.pumpAndSettle();
      expect(find.text('ฝึกคำที่ผิด (1)'), findsOneWidget);
      expect(
        hubLoads,
        1,
        reason: 'refresh must wait for the complete learning flow',
      );
      await tester.tap(find.text('ฝึกคำที่ผิด (1)'));
      await _pumpUntilFound(tester, find.text('ฝึกคำที่ผิด'));
      await _pumpUntilFound(tester, find.text('station'));
      expect(find.text('ฝึกคำที่ผิด'), findsOneWidget);
      expect(find.text('คำถาม 1 จาก 1'), findsOneWidget);
      final sessions = await database.select(database.learningSessions).get();
      expect(sessions.map((s) => s.activityType), ['quiz', 'weaknessPractice']);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(2),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('สถานี'));
      await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
      await tester.tap(find.text('ดูผลการเรียน'));
      await _pumpUntilFound(tester, find.text('100%'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await _pumpUntilFound(tester, find.text('วันนี้อยากฝึกอะไร'));
      await _pumpUntilFound(tester, find.text('คำที่ควรฝึก 1 คำ'));
      expect(hubLoads, 2);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(3),
      );
    },
  );

  testWidgets(
    'start retry keeps one accepted identity after lost acknowledgement',
    (tester) async {
      final repository = _FailOnceRepository(
        learning.repository,
        false,
        failOnCall: 0,
        failStartAfterCommit: true,
      );
      final failing = LearningUseCases(
        owners: learning.owners,
        repository: repository,
        generateId: () => (++id).toString(),
        nowUtc: learning.nowUtc,
        buildInfo: learning.buildInfo,
      );
      await tester.pumpWidget(MaterialApp(home: QuizScreen(learning: failing)));
      await _pumpUntilFound(
        tester,
        find.textContaining('เปิดแบบทดสอบไม่สำเร็จ'),
      );
      final before = (await tester.runAsync(
        () => database.select(database.learningSessions).getSingle(),
      ))!;
      expect(find.text('station'), findsNothing);
      await tester.tap(find.text('ลองอีกครั้ง'));
      await _pumpUntilFound(tester, find.text('station'));
      final sessions = (await tester.runAsync(
        () => database.select(database.learningSessions).get(),
      ))!;
      expect(sessions, hasLength(1));
      expect(sessions.single.toJson(), before.toJson());
      expect(id, 1);
    },
  );

  testWidgets(
    'failed durable hint remains hidden until exact retry acknowledges',
    (tester) async {
      final repository = _FailOnceRepository(
        learning.repository,
        true,
        failOnCall: 0,
        failCheckpointPhase: 'awaitingAnswer',
      );
      final failing = LearningUseCases(
        owners: learning.owners,
        repository: repository,
        generateId: () => (++id).toString(),
        nowUtc: learning.nowUtc,
        buildInfo: learning.buildInfo,
      );
      await tester.pumpWidget(MaterialApp(home: QuizScreen(learning: failing)));
      await _pumpUntilFound(tester, find.text('station'));
      await tester.tap(find.text('ดูคำใบ้'));
      await _pumpUntilFound(
        tester,
        find.text('บันทึกคำใบ้ไม่สำเร็จ กรุณาลองอีกครั้ง'),
      );
      expect(find.text('noun'), findsNothing);
      final saved = (await tester.runAsync(
        () => database.select(database.learningSessions).getSingle(),
      ))!;
      final checkpoint = jsonDecode(saved.checkpointJson!) as Map;
      expect((checkpoint['assistance'] as Map)['hintVisible'], isTrue);
      await tester.tap(find.text('ลองบันทึกอีกครั้ง'));
      await _pumpUntilFound(tester, find.text('noun'));
      final retried = (await tester.runAsync(
        () => database.select(database.learningSessions).getSingle(),
      ))!;
      expect(retried.checkpointRevision, saved.checkpointRevision);
      expect(retried.checkpointJson, saved.checkpointJson);
      expect(
        await tester.runAsync(
          () => database.select(database.answerAttempts).get(),
        ),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => database.select(database.outboxOperations).get(),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'owner switch hides private items and ignores late answer acknowledgement',
    (tester) async {
      final acknowledgement = Completer<void>();
      final owners = StreamController<String?>.broadcast();
      addTearDown(() async {
        if (!acknowledgement.isCompleted) acknowledgement.complete();
        await owners.close();
      });
      final repository = _FailOnceRepository(
        learning.repository,
        false,
        failOnCall: 0,
        acknowledgement: acknowledgement.future,
      );
      final pending = LearningUseCases(
        owners: learning.owners,
        repository: repository,
        generateId: () => (++id).toString(),
        nowUtc: learning.nowUtc,
        buildInfo: learning.buildInfo,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(learning: pending, ownerChanges: owners.stream),
        ),
      );
      await _pumpUntilFound(tester, find.text('station'));
      await tester.tap(find.text('สถานี'));
      for (var i = 0; i < 60 && repository.commands.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(repository.commands, hasLength(1));
      owners.add('synthetic-different-owner');
      await _pumpUntilFound(
        tester,
        find.text('บัญชีเปลี่ยนแล้ว กรุณากลับไปเลือกกิจกรรม'),
      );
      expect(find.text('station', skipOffstage: false), findsNothing);
      acknowledgement.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(find.text('ถูกต้อง'), findsNothing);
      expect(find.byType(ScoreScreen), findsNothing);
      final attempts = (await tester.runAsync(
        () => database.select(database.answerAttempts).get(),
      ))!;
      expect(attempts, hasLength(1));
      expect(attempts.single.ownerId, repository.commands.single.ownerId);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'covered route clears private items and reloads committed answer on return',
    (tester) async {
      final acknowledgement = Completer<void>();
      addTearDown(() {
        if (!acknowledgement.isCompleted) acknowledgement.complete();
      });
      final repository = _FailOnceRepository(
        learning.repository,
        false,
        failOnCall: 0,
        acknowledgement: acknowledgement.future,
      );
      final pending = LearningUseCases(
        owners: learning.owners,
        repository: repository,
        generateId: () => (++id).toString(),
        nowUtc: learning.nowUtc,
        buildInfo: learning.buildInfo,
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: QuizScreen(learning: pending),
        ),
      );
      await _pumpUntilFound(tester, find.text('station'));
      await tester.tap(find.text('สถานี'));
      for (var i = 0; i < 60 && repository.commands.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(repository.commands, hasLength(1));
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Synthetic cover')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('station', skipOffstage: false), findsNothing);
      acknowledgement.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(find.text('ถูกต้อง', skipOffstage: false), findsNothing);
      navigator.currentState!.pop();
      await _pumpUntilFound(tester, find.text('ถูกต้อง'));
      expect(repository.commands, hasLength(1));
      expect(
        await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ),
        hasLength(1),
      );
      expect(
        await tester.runAsync(
          () => database.select(database.answerAttempts).get(),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('disposed quiz ignores late answer acknowledgement', (
    tester,
  ) async {
    final acknowledgement = Completer<void>();
    addTearDown(() {
      if (!acknowledgement.isCompleted) acknowledgement.complete();
    });
    final repository = _FailOnceRepository(
      learning.repository,
      false,
      failOnCall: 0,
      acknowledgement: acknowledgement.future,
    );
    final pending = LearningUseCases(
      owners: learning.owners,
      repository: repository,
      generateId: () => (++id).toString(),
      nowUtc: learning.nowUtc,
      buildInfo: learning.buildInfo,
    );
    await tester.pumpWidget(MaterialApp(home: QuizScreen(learning: pending)));
    await _pumpUntilFound(tester, find.text('station'));
    await tester.tap(find.text('สถานี'));
    for (var i = 0; i < 60 && repository.commands.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(repository.commands, hasLength(1));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Different screen'))),
    );
    acknowledgement.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(find.text('ถูกต้อง'), findsNothing);
    expect(find.byType(ScoreScreen), findsNothing);
    expect(find.text('Different screen'), findsOneWidget);
    expect(
      await tester.runAsync(
        () => database.select(database.answerAttempts).get(),
      ),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('slow optional haptics cannot hold a committed answer or score', (
    tester,
  ) async {
    final feedback = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') return feedback.future;
          return null;
        });
    addTearDown(() {
      if (!feedback.isCompleted) feedback.complete();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(MaterialApp(home: QuizScreen(learning: learning)));
    await _pumpUntilFound(tester, find.text('station'));
    await tester.tap(find.text('สถานี'));
    await _pumpUntilFound(tester, find.text('ถูกต้อง'));
    expect(feedback.isCompleted, isFalse);
    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'ดูผลการเรียน'),
    );
    expect(next.onPressed, isNotNull);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is LinearProgressIndicator &&
            widget.semanticsLabel == 'กำลังบันทึกคำตอบ',
      ),
      findsNothing,
    );
    await tester.tap(find.text('ดูผลการเรียน'));
    await _pumpUntilFound(tester, find.byType(ScoreScreen));
    expect(feedback.isCompleted, isFalse);
    expect(
      await tester.runAsync(
        () => database.select(database.answerAttempts).get(),
      ),
      hasLength(1),
    );
    final session = (await tester.runAsync(
      () => database.select(database.learningSessions).getSingle(),
    ))!;
    expect(session.state, 'completed');
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

class _FailOnceRepository
    implements LearningRepository, ConfiguredQuizRepository {
  _FailOnceRepository(
    this.delegate,
    this.afterCommit, {
    this.failOnCall = 1,
    this.acknowledgement,
    this.failStartAfterCommit = false,
    this.failCheckpointPhase,
  });
  final LearningRepository delegate;
  final bool afterCommit;
  final int failOnCall;
  final Future<void>? acknowledgement;
  final bool failStartAfterCommit;
  final String? failCheckpointPhase;
  var _startFailed = false;
  var _checkpointFailed = false;
  bool first = true;
  var calls = 0;
  final commands = <RecordAnswerCommand>[];

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) =>
      _intercept(command, () => delegate.recordAnswer(command));

  Future<T> _intercept<T>(
    RecordAnswerCommand command,
    Future<T> Function() write,
  ) async {
    commands.add(command);
    calls++;
    if (first && calls == failOnCall) {
      first = false;
      if (afterCommit) await write();
      throw StateError('synthetic storage/acknowledgement failure');
    }
    final result = await write();
    await acknowledgement;
    return result;
  }

  ConfiguredQuizRepository get _configured =>
      delegate as ConfiguredQuizRepository;

  @override
  Future<ConfiguredQuizState?> findConfiguredQuizStart(
    ConfiguredQuizLaunch launch,
  ) => _configured.findConfiguredQuizStart(launch);

  @override
  Future<ConfiguredQuizState> startConfiguredQuiz({
    required LearningSessionDraft session,
    required AcceptedQuizPlan plan,
  }) async {
    final saved = await _configured.startConfiguredQuiz(
      session: session,
      plan: plan,
    );
    if (failStartAfterCommit && !_startFailed) {
      _startFailed = true;
      throw StateError('synthetic lost start acknowledgement');
    }
    return saved;
  }

  @override
  Future<ConfiguredQuizState> resumeQuiz({
    required String sessionId,
    required String expectedOwnerId,
  }) => _configured.resumeQuiz(
    sessionId: sessionId,
    expectedOwnerId: expectedOwnerId,
  );

  @override
  Future<ConfiguredQuizState> saveQuizCheckpoint({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
    required QuizCheckpoint checkpoint,
  }) async {
    if (!_checkpointFailed && checkpoint.phase == failCheckpointPhase) {
      _checkpointFailed = true;
      if (afterCommit) {
        await _configured.saveQuizCheckpoint(
          sessionId: sessionId,
          expectedOwnerId: expectedOwnerId,
          expectedRevision: expectedRevision,
          checkpoint: checkpoint,
        );
      }
      throw StateError('synthetic checkpoint failure');
    }
    return _configured.saveQuizCheckpoint(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
      expectedRevision: expectedRevision,
      checkpoint: checkpoint,
    );
  }

  @override
  Future<ConfiguredQuizAnswerResult> commitQuizAnswer({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  }) async {
    final saved = await _configured.resumeQuiz(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
    );
    return _intercept(
      saved.checkpoint.answer!.toCommand(sessionId: sessionId),
      () => _configured.commitQuizAnswer(
        sessionId: sessionId,
        expectedOwnerId: expectedOwnerId,
        expectedRevision: expectedRevision,
      ),
    );
  }

  @override
  Future<ConfiguredQuizFinishResult> finishConfiguredQuiz({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  }) => _configured.finishConfiguredQuiz(
    sessionId: sessionId,
    expectedOwnerId: expectedOwnerId,
    expectedRevision: expectedRevision,
  );

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    limit: limit,
  );
  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);
  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => delegate.finishSession(
    ownerId: ownerId,
    sessionId: sessionId,
    endedAtUtc: endedAtUtc,
  );
  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) => delegate.listDueWords(ownerId: ownerId, nowUtc: nowUtc, limit: limit);
  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => delegate.readReadingProgress(
    ownerId: ownerId,
    documentId: documentId,
    documentRevision: documentRevision,
  );
  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => delegate.saveReadingProgress(command);
}

Object _evidence(RecordAnswerCommand command) => (
  command.id,
  command.ownerId,
  command.sessionId,
  command.wordId,
  command.promptMode,
  command.isCorrect,
  command.responseTimeMs,
  command.attemptNumber,
  command.occurredAtUtc,
  command.providerProvenance,
  jsonEncode(command.evidenceContext.toJson()),
);
