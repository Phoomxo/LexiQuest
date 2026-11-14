import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';

import 'screen_golden.dart';

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
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++id}',
      nowUtc: () => DateTime.utc(2026, 7, 30, 10, 1),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
  });

  tearDown(() => database.close().timeout(const Duration(seconds: 30)));

  Future<void> addDefinitionWord() => database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'definition-platform',
          ownerId: 'local:guest',
          categoryId: 'category-1',
          spelling: 'platform',
          normalizedSpelling: 'platform',
          meaning: 'ชานชาลา',
          normalizedMeaning: 'ชานชาลา',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      )
      .then((_) {});

  Future<void> openPromptMode(WidgetTester tester, QuizPromptKind kind) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => QuizScreen(
                  learning: learning,
                  categoryId: 'category-1',
                  categoryName: 'Travel',
                  promptKind: kind,
                  expectedOwnerId: 'local:guest',
                ),
              ),
            ),
            child: const Text('เลือกรูปแบบโจทย์'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เลือกรูปแบบโจทย์'));
    await tester.pump();
  }

  Future<void> tapPrompt(WidgetTester tester, String text) async {
    await tester.pump();
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      target.hitTestable(),
      findsOneWidget,
      reason: 'the real control must accept a tap',
    );
    await tester.tap(target);
    await tester.pump();
  }

  for (final mode in [
    ('เลือกคำอังกฤษจากความหมายไทย', QuizPromptKind.spellingChoice),
    ('อ่านนิยามแล้วหาคำ', QuizPromptKind.definitionChoice),
  ]) {
    testWidgets(
      'prompt mode actual menu binds category and owner for ${mode.$2.name}',
      (tester) async {
        await tester.runAsync(addDefinitionWord);
        final progress = (await tester.runAsync(
          () => DriftProgressQueries(
            database,
          ).load(ownerId: 'local:guest', nowUtc: learning.nowUtc()),
        ))!;
        final vocabulary = VocabularyUseCases(
          owners: learning.owners,
          vocabulary: DriftVocabularyRepository(database),
          generateId: () => 'unused-${++id}',
          nowUtc: learning.nowUtc,
        );
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: AppDependencies(
              runtimeStatus: const AppRuntimeStatus(
                localData: RuntimeAvailability.ready,
                firebase: RuntimeAvailability.unavailable,
                supabase: RuntimeAvailability.unavailable,
                backends: RuntimeAvailability.unavailable,
              ),
              config: null,
              guestSessionService: _UnusedGuestSession(),
              database: database,
              learning: learning,
              localOwners: learning.owners,
              vocabulary: vocabulary,
            ),
            child: MaterialApp(
              home: ChooseModeScreen(loader: () async => progress),
            ),
          ),
        );
        await tapPrompt(tester, 'ดูแบบฝึกทั้งหมด');
        await tapPrompt(tester, mode.$1);
        await _pumpUntilFound(tester, find.text('Travel'));
        expect(
          (await tester.runAsync(
            () => database.select(database.learningSessions).get(),
          ))!,
          isEmpty,
        );
        await tapPrompt(tester, 'Travel');
        await _pumpUntilFound(tester, find.byType(QuizScreen));
        final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
        expect(
          (screen.categoryId, screen.expectedOwnerId, screen.promptKind),
          ('category-1', 'local:guest', mode.$2),
        );
        await _pumpUntilFound(
          tester,
          find.text(
            mode.$2 == QuizPromptKind.spellingChoice
                ? 'เลือกคำอังกฤษที่ตรงกับความหมาย'
                : 'โจทย์นิยามภาษาอังกฤษ',
          ),
        );
        expect(
          (await tester.runAsync(
            () => database.select(database.answerAttempts).get(),
          ))!,
          isEmpty,
        );
        await tester.tap(
          find
              .descendant(
                of: find.byType(QuizScreen),
                matching: find.byType(BackButton),
              )
              .hitTestable(),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await _pumpUntilFound(tester, find.text('เลือกวิธีฝึก'));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'prompt mode reverse keeps the same real word through wrong then intentional retry',
    (tester) async {
      await tester.runAsync(addDefinitionWord);
      await openPromptMode(tester, QuizPromptKind.spellingChoice);
      await _pumpUntilFound(
        tester,
        find.text('เลือกคำอังกฤษที่ตรงกับความหมาย'),
      );
      expect(find.text('ชานชาลา'), findsOneWidget);
      await tapPrompt(tester, 'station');
      await _pumpUntilFound(tester, find.text('ลองข้อเดิม'));
      expect(find.text('station — สถานี'), findsOneWidget);
      await tapPrompt(tester, 'ลองข้อเดิม');
      await tapPrompt(tester, 'platform');
      await _pumpUntilFound(tester, find.text('คำถามถัดไป'));
      final facts = (await tester.runAsync(
        () => database.select(database.answerAttempts).get(),
      ))!;
      expect(facts.map((r) => (r.wordId, r.promptMode, r.isCorrect)), [
        ('definition-platform', 'spellingChoice', false),
        ('definition-platform', 'spellingChoice', true),
      ]);
      expect(facts.map((r) => r.id).toSet(), hasLength(2));
      expect(facts.map((r) => r.attemptNumber).toSet(), hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'prompt mode definition keeps Thai200percent feedback and retry reachable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        await tester.runAsync(addDefinitionWord);
        await tester.pumpWidget(
          MaterialApp(
            theme: M3Theme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: const ValueKey('prompt-capture'),
              child: QuizScreen(
                learning: learning,
                categoryId: 'category-1',
                categoryName: 'Travel',
                promptKind: QuizPromptKind.definitionChoice,
                expectedOwnerId: 'local:guest',
              ),
            ),
          ),
        );
        await _pumpUntilFound(tester, find.text('โจทย์นิยามภาษาอังกฤษ'));
        await tester.pump();
        await _capturePrompt(tester, 's7-definition-200.png');
        await tapPrompt(tester, 'ticket');
        await _pumpUntilFound(tester, find.text('ลองข้อเดิม'));
        await tester.ensureVisible(find.text('ลองข้อเดิม'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('ลองข้อเดิม').hitTestable(), findsOneWidget);
        final button = find.ancestor(
          of: find.text('ลองข้อเดิม'),
          matching: find.byType(OutlinedButton),
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        await _capturePrompt(tester, 's7-definition-feedback-200.png');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      }
    },
  );

  for (final afterCommit in [false, true]) {
    testWidgets(
      'prompt mode definition separates transport retry from a new answer afterCommit=$afterCommit',
      (tester) async {
        await tester.runAsync(addDefinitionWord);
        final base = learning;
        final repository = _FailOnceRepository(base.repository, afterCommit);
        learning = LearningUseCases(
          owners: base.owners,
          repository: repository,
          generateId: () => 'prompt-${++id}',
          nowUtc: base.nowUtc,
          buildInfo: base.buildInfo,
        );
        await openPromptMode(tester, QuizPromptKind.definitionChoice);
        const definition =
            'The place at a train station where you wait to get on a train.';
        await _pumpUntilFound(tester, find.text(definition));
        expect(find.text('โจทย์นิยามภาษาอังกฤษ'), findsOneWidget);
        await tapPrompt(tester, 'ticket');
        await _pumpUntilFound(tester, find.text('ลองบันทึกอีกครั้ง'));
        expect(find.text('ลองข้อเดิม'), findsNothing);
        await tapPrompt(tester, 'ลองบันทึกอีกครั้ง');
        await _pumpUntilFound(tester, find.text('ลองข้อเดิม'));
        expect(find.text('ticket — ตั๋ว'), findsOneWidget);
        expect(find.text('หลักฐานที่ใช้โดยสาร'), findsOneWidget);
        expect(
          repository.commands.take(2).map((c) => c.id).toSet(),
          hasLength(1),
        );
        await tapPrompt(tester, 'ลองข้อเดิม');
        expect(find.text(definition), findsOneWidget);
        await tapPrompt(tester, 'platform');
        await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
        await tapPrompt(tester, 'ดูผลการเรียน');
        await _pumpUntilFound(tester, find.byType(ScoreScreen));
        final facts = (await tester.runAsync(
          () => database.select(database.answerAttempts).get(),
        ))!;
        expect(facts.map((r) => (r.wordId, r.promptMode, r.isCorrect)), [
          ('definition-platform', 'definitionChoice', false),
          ('definition-platform', 'definitionChoice', true),
        ]);
        final session = (await tester.runAsync(
          () => database.select(database.learningSessions).getSingle(),
        ))!;
        expect(
          (
            session.correctCount,
            session.wrongCount,
            session.score,
            session.state,
          ),
          (1, 1, 50, 'completed'),
        );
        expect(
          (await tester.runAsync(
            () => database.select(database.pointsLedgerEntries).get(),
          ))!.single.amount,
          1,
        );
        expect(
          (await tester.runAsync(
            () => database.select(database.rewardTransactions).get(),
          ))!.single.amount,
          1,
        );
        await tester.tap(
          find
              .descendant(
                of: find.byType(ScoreScreen),
                matching: find.byType(BackButton),
              )
              .hitTestable(),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await _pumpUntilFound(tester, find.text('เลือกรูปแบบโจทย์'));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'prompt mode unsupported definition shows honest availability and creates no session',
    (tester) async {
      await openPromptMode(tester, QuizPromptKind.definitionChoice);
      await _pumpUntilFound(
        tester,
        find.textContaining('ยังไม่มีคู่นิยามที่รองรับ'),
      );
      expect(
        (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  for (final hiddenFeature in [FieldFeature.quiz, FieldFeature.weakness]) {
    testWidgets('live score hides repair when $hiddenFeature is hidden', (
      tester,
    ) async {
      final owner = await database.select(database.localOwners).getSingle();
      await database
          .into(database.vocabularyWords)
          .insertOnConflictUpdate(
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
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: AppDependencies(
            runtimeStatus: const AppRuntimeStatus(
              localData: RuntimeAvailability.ready,
              firebase: RuntimeAvailability.unavailable,
              supabase: RuntimeAvailability.unavailable,
              backends: RuntimeAvailability.unavailable,
            ),
            config: null,
            guestSessionService: _UnusedGuestSession(),
            learning: learning,
            fieldFeatures: BuildFieldFeatureRegistry({
              FieldFeature.quiz: hiddenFeature == FieldFeature.quiz
                  ? FieldFeatureState.hidden
                  : FieldFeatureState.enabled,
              FieldFeature.weakness: hiddenFeature == FieldFeature.weakness
                  ? FieldFeatureState.hidden
                  : FieldFeatureState.enabled,
            }),
          ),
          child: MaterialApp(
            home: QuizScreen(categoryId: 'category-1', learning: learning),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('station'));
      await tester.tap(find.text('ตั๋ว'));
      await _pumpUntilFound(tester, find.text('คำถามถัดไป'));
      await tester.tap(find.text('คำถามถัดไป'));
      await tester.pump();
      await tester.tap(find.text('ตั๋ว'));
      await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
      await tester.tap(find.text('ดูผลการเรียน'));
      await _pumpUntilFound(tester, find.byType(ScoreScreen));
      await tester.pumpAndSettle();

      expect(find.text('50%'), findsOneWidget);
      expect(find.text('station'), findsOneWidget);
      expect(find.text('ฝึกคำที่ผิด (1)'), findsNothing);
      final session = await database
          .select(database.learningSessions)
          .getSingle();
      expect(session.state, 'completed');
      expect(session.wrongCount, 1);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(2),
      );
    });
  }

  testWidgets('selected set name and return context survive the saved result', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QuizScreen(
                    categoryId: 'category-1',
                    categoryName: 'ชุดการเดินทาง',
                    learning: learning,
                  ),
                ),
              ),
              child: const Text('เปิดชุดเดิม'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดชุดเดิม'));
    await _pumpUntilFound(tester, find.text('station'));
    expect(find.text('ชุดการเดินทาง'), findsOneWidget);
    await tester.tap(find.text('สถานี'));
    await _pumpUntilFound(tester, find.text('คำถามถัดไป'));
    await tester.tap(find.text('คำถามถัดไป'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'ตั๋ว'));
    await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
    await tester.tap(find.text('ดูผลการเรียน'));
    await _pumpUntilFound(tester, find.byType(ScoreScreen));
    await tester.pumpAndSettle();

    expect(find.text('ชุดการเดินทาง'), findsOneWidget);
    expect(find.text('กลับไปที่ชุดคำ'), findsOneWidget);
    await tester.tap(find.text('กลับไปที่ชุดคำ'));
    await tester.pumpAndSettle();
    expect(find.text('เปิดชุดเดิม'), findsOneWidget);
    expect(find.byType(QuizScreen), findsNothing);
    final saved = await database.select(database.learningSessions).getSingle();
    expect(saved.state, 'completed');
    expect(saved.correctCount, 2);
  });

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
            .insertOnConflictUpdate(
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
    await _pumpUntilFound(tester, find.text('คำถามถัดไป'));
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    expect(find.byType(ScoreScreen), findsNothing);
    await tester.tap(find.text('คำถามถัดไป'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'ตั๋ว'));
    await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
    await tester.tap(find.text('ดูผลการเรียน'));
    await _pumpUntilFound(tester, find.byType(ScoreScreen));

    expect(find.byType(ScoreScreen), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(await database.select(database.answerAttempts).get(), hasLength(2));
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
      await learning.recordAnswer(
        sessionId: session.id,
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 500,
        attemptNumber: 1,
      );
      await learning.finishSession(session.id);
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
      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(
            learning: pending,
            categoryName: 'ชุดการเดินทาง',
            returnLabel: 'กลับไปเลือกกิจกรรม',
          ),
        ),
      );
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
      await _pumpUntilFound(tester, find.text('คำถามถัดไป'));
      expect(repository.commands.single.isCorrect, isFalse);
      await tester.tap(find.text('คำถามถัดไป'));
      await tester.pump();
      await tester.tap(find.text('เฉลยคำตอบ'));
      await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
      expect(repository.commands, hasLength(2));
      expect(
        repository.commands.every((command) => !command.isCorrect),
        isTrue,
      );
      await tester.tap(find.text('ดูผลการเรียน'));
      await _pumpUntilFound(tester, find.byType(ScoreScreen));
      await tester.pumpAndSettle();
      expect(find.text('กลับไปเลือกกิจกรรม'), findsOneWidget);
      expect(find.text('กลับไปที่ชุดคำ'), findsNothing);
      await tester.tap(find.text('ฝึกคำที่ผิด (2)'));
      await _pumpUntilFound(tester, find.text('ฝึกคำที่ผิด'));
      expect(
        tester.widget<QuizScreen>(find.byType(QuizScreen)).returnLabel,
        'กลับไปเลือกกิจกรรม',
      );
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(2),
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
      await tester.pump();
      expect(find.text('noun'), findsOneWidget);
      await tester.tap(find.text('ซ่อนคำใบ้'));
      await tester.pump();
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
        "UPDATE vocabulary_words SET meaning = 'คำแปลสังเคราะห์ที่ยาวเพื่อทดสอบการเลื่อนและการขยายตัวอักษร', part_of_speech = 'ชนิดคำสังเคราะห์สำหรับใช้ทดสอบคำใบ้ที่มีข้อความยาว' WHERE id = 'word-1'",
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
      await tester.pump();
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
      await _pumpUntilFound(tester, find.text('คำถามถัดไป'));
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
        findsWidgets,
      );
      await tester.ensureVisible(find.text('คำถามถัดไป'));
      expect(find.text('คำถามถัดไป').hitTestable(), findsOneWidget);
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
      matchesGoldenFile(screenGolden('quiz_feedback_large_text.png')),
    );
    await tester.scrollUntilVisible(find.text('คำถามถัดไป'), 150);
    expect(find.text('คำถามถัดไป').hitTestable(), findsOneWidget);
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
        .insertOnConflictUpdate(
          VocabularyWordsCompanion.insert(
            id: 'word-2',
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
      'เปิดแบบทดสอบไม่สำเร็จ ข้อมูลในเครื่องยังไม่ถูกเปลี่ยนแปลง',
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
          .insertOnConflictUpdate(
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
      await _pumpUntilFound(tester, find.text('ทบทวนครบแล้ว'));
      await tester.ensureVisible(find.text('ดูแบบฝึกทั้งหมด'));
      await tester.tap(find.text('ดูแบบฝึกทั้งหมด'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ฝึกคำศัพท์'));
      await _pumpUntilFound(tester, find.text('station'));
      await tester.tap(find.text('ตั๋ว'));
      await _pumpUntilFound(tester, find.text('คำถามถัดไป'));
      expect(find.text('ยังไม่ถูก ลองดูคำแปลอีกครั้ง'), findsOneWidget);
      expect(find.text('station — สถานี'), findsOneWidget);
      await tester.tap(find.text('คำถามถัดไป'));
      await tester.pump();
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
      await _pumpUntilFound(tester, find.text('เลือกวิธีฝึก'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await _pumpUntilFound(tester, find.text('ทบทวนครบแล้ว'));
      expect(find.text('ฝึกภาษา'), findsOneWidget);
      expect(hubLoads, 3);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(3),
      );
      final completed = await database.select(database.learningSessions).get();
      expect(completed, hasLength(2));
      expect(
        completed.every((session) => session.state == 'completed'),
        isTrue,
      );
      expect(completed.first.score, 50);
      expect(completed.last.score, 100);
    },
  );
}

Future<void> _capturePrompt(WidgetTester tester, String filename) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('prompt-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('build/$filename').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

final class _UnusedGuestSession extends Fake implements GuestSessionService {}

class _FailOnceRepository implements LearningRepository {
  _FailOnceRepository(
    this.delegate,
    this.afterCommit, {
    this.failOnCall = 1,
    this.acknowledgement,
  });
  final LearningRepository delegate;
  final bool afterCommit;
  final int failOnCall;
  final Future<void>? acknowledgement;
  bool first = true;
  var calls = 0;
  final commands = <RecordAnswerCommand>[];

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    calls++;
    if (first && calls == failOnCall) {
      first = false;
      if (afterCommit) await delegate.recordAnswer(command);
      throw StateError('synthetic storage/acknowledgement failure');
    }
    final result = await delegate.recordAnswer(command);
    await acknowledgement;
    return result;
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    Iterable<String>? normalizedSpellings,
    Iterable<String>? normalizedMeanings,
    required int? limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    normalizedSpellings: normalizedSpellings,
    normalizedMeanings: normalizedMeanings,
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
);
