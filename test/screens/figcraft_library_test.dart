import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as owner_domain;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_import_file_picker.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/add_multiple_words_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final class _GuestSession extends Fake implements GuestSessionService {}

const _bagItems = '''[
  {"word":"pencil","meaning":"ดินสอ","partOfSpeech":"noun"},
  {"word":"wallet","meaning":"กระเป๋าสตางค์","partOfSpeech":"noun"}
''';

VocabularyImportFile _jsonFile(String name, String content) =>
    VocabularyImportFile(
      name: name,
      mimeType: 'application/json',
      bytes: Uint8List.fromList(utf8.encode(content)),
    );

void main() {
  late AppDatabase database;
  late AppDependencies dependencies;
  late VocabularyUseCases vocabulary;
  late VocabularyImportFilePicker pickImportFile;
  var nextId = 0;

  setUp(() {
    database = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    nextId = 0;
    pickImportFile = () async => null;
    final now = DateTime.utc(2026, 11, 13);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-library-owner',
      nowUtc: () => now,
    );
    vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'synthetic-${++nextId}',
      nowUtc: () => now,
    );
    dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      database: database,
      vocabulary: vocabulary,
      progress: ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => now,
      ),
      learning: LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'synthetic-learning-${++nextId}',
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      ),
      vocabularyImporter: ImportVocabulary(
        owners: owners,
        repository: DriftVocabularyImportRepository(database),
        generateId: () => 'synthetic-import-${++nextId}',
        nowUtc: () => now,
      ),
      vocabularyImportFilePicker: () => pickImportFile(),
    );
  });

  Future<void> pumpLibrary(
    WidgetTester tester, {
    double scale = 1,
    bool travelContrast = false,
    bool withLevels = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(() async {
      for (final (name, spelling, meaning) in [
        ('การเดินทาง', 'station', 'สถานี'),
        ('อาหาร', 'apple', 'แอปเปิล'),
      ]) {
        final category = await vocabulary.createCategory(name);
        await vocabulary.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: spelling,
            meaning: meaning,
            partOfSpeech: 'noun',
            cefrLevel: withLevels ? (name == 'การเดินทาง' ? 'A2' : 'A1') : null,
          ),
        );
        if (travelContrast && name == 'การเดินทาง') {
          await vocabulary.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: 'ticket',
              meaning: 'ตั๋ว',
              partOfSpeech: 'noun',
            ),
          );
        }
      }
    });
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const CategoriesPage(),
        ),
      ),
    );
    await _pumpUntil(tester, find.text('การเดินทาง'));
  }

  Future<void> disposeLibrary(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'library filters existing sets by level and restores after clear',
    (tester) async {
      try {
        await pumpLibrary(tester, withLevels: true, scale: 2);
        final levelFilter = find.byKey(const ValueKey('library-level-filter'));
        await tester.tap(levelFilter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('A2'));
        await tester.pumpAndSettle();
        expect(find.text('ระดับภาษา · A2 · พบ 1 ชุด'), findsOneWidget);
        expect(find.text('อาหาร'), findsNothing);
        await _tapLabel(tester, 'การเดินทาง');
        await _pumpUntil(tester, find.text('station'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('ระดับภาษา · A2 · พบ 1 ชุด'), findsOneWidget);
        expect(find.text('อาหาร'), findsNothing);

        final search = find.byKey(const ValueKey('category-search'));
        await tester.scrollUntilVisible(
          search,
          -160,
          scrollable: find.byType(Scrollable).hitTestable().last,
        );
        await tester.enterText(search, 'apple');
        await _pumpUntil(tester, find.text('ไม่พบคำหรือชุดที่ค้นหา'));
        expect(find.text('เลือกระดับภาษา · A2'), findsOneWidget);
        await tester.enterText(search, '');
        await tester.pumpAndSettle();
        await tester.tap(levelFilter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('C2'));
        await tester.pumpAndSettle();
        expect(find.text('ไม่พบชุดที่มีคำระดับ C2'), findsOneWidget);
        expect(find.text('การเดินทาง'), findsNothing);
        await tester.tap(find.text('ล้างตัวกรอง'));
        await tester.pumpAndSettle();
        expect(find.text('การเดินทาง'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('อาหาร'),
          180,
          scrollable: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        expect(find.text('อาหาร'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeLibrary(tester);
      }
    },
  );

  testWidgets('set and word searches keep their context after returning', (
    tester,
  ) async {
    try {
      await pumpLibrary(tester);
      final setSearch = find.byKey(const ValueKey('category-search'));
      await tester.enterText(setSearch, 'การเดิน');
      await tester.pumpAndSettle();
      expect(find.text('อาหาร'), findsNothing);
      await tester.tap(find.text('การเดินทาง'));
      await _pumpUntil(tester, find.text('station'));
      await tester.pumpAndSettle();
      final wordSearch = find.descendant(
        of: find.byType(VocabListScreen),
        matching: find.byType(SearchBar),
      );
      await tester.enterText(wordSearch, 'stat');
      await tester.pumpAndSettle();
      await tester.tap(find.text('station'));
      await _pumpUntil(tester, find.byKey(const ValueKey('word-field')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await _pumpUntil(tester, find.text('station'));
      await tester.pumpAndSettle();
      expect(tester.widget<SearchBar>(wordSearch).controller!.text, 'stat');
      await tester.pageBack();
      await _pumpUntil(tester, setSearch);
      await tester.pumpAndSettle();
      expect(tester.widget<SearchBar>(setSearch).controller!.text, 'การเดิน');
      expect(find.text('อาหาร'), findsNothing);
      await tester.enterText(setSearch, 'อาหาร');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'อาหาร'));
      await _pumpUntil(tester, find.text('apple'));
      await tester.pumpAndSettle();
      expect(find.text('station'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeLibrary(tester);
    }
  });

  testWidgets('an open level picker cannot carry A results into owner B', (
    tester,
  ) async {
    try {
      await pumpLibrary(tester, withLevels: true);
      final levelFilter = find.byKey(const ValueKey('library-level-filter'));
      final openFromA = tester.widget<OutlinedButton>(levelFilter).onPressed!;
      final setA = (await tester.runAsync(
        () => vocabulary.watchCategories().first,
      ))!.singleWhere((category) => category.name == 'การเดินทาง');
      await tester.tap(levelFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('A2'));
      await tester.pumpAndSettle();
      expect(find.text('ระดับภาษา · A2 · พบ 1 ชุด'), findsOneWidget);
      await tester.tap(levelFilter);
      await tester.pumpAndSettle();

      var switched = false;
      final switching = (() async {
        await database.transaction(() async {
          await database
              .update(database.localOwners)
              .write(const LocalOwnersCompanion(isActive: Value(false)));
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'synthetic-b',
                  createdAtUtcMs: 0,
                ),
              );
        });
        await vocabulary.createCategory('ชุดของบัญชี B');
      })().whenComplete(() => switched = true);
      unawaited(switching.then<void>((_) {}, onError: (Object _) {}));
      for (var index = 0; index < 50 && !switched; index++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(switched, isTrue, reason: 'the active owner switch must finish');
      await switching;
      await tester.tap(find.text('A1'));
      await tester.pumpAndSettle();
      await _pumpUntil(tester, find.text('ชุดของบัญชี B'));
      expect(find.text('การเดินทาง'), findsNothing);
      expect(find.text('อาหาร'), findsNothing);
      expect(find.text('เลือกระดับภาษา'), findsOneWidget);
      expect(find.text('ล้างตัวกรอง'), findsNothing);
      openFromA();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(
            home: VocabListScreen(
              categoryId: setA.id,
              categoryName: setA.name,
              expectedOwnerId: setA.ownerId,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        find.text('ชุดคำนี้ไม่พร้อมใช้งาน กรุณากลับไปเลือกชุดใหม่'),
      );
      await tester.pumpAndSettle();
      expect(find.text('การเดินทาง'), findsNothing);
      expect(find.text('station'), findsNothing);
    } finally {
      await disposeLibrary(tester);
    }
  });

  testWidgets(
    'global add selects its destination before the existing manual form',
    (tester) async {
      try {
        await pumpLibrary(tester);
        await tester.tap(find.byKey(const ValueKey('library-add-word')));
        await _pumpUntil(tester, find.text('เลือกชุดที่จะเพิ่มคำ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('อาหาร').last);
        await _pumpUntil(tester, find.text('พิมพ์คำศัพท์'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('พิมพ์คำศัพท์'));
        await _pumpUntil(tester, find.byKey(const ValueKey('word-field')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('word-field')),
          'banana',
        );
        await tester.enterText(
          find.byKey(const ValueKey('meaning-field')),
          'กล้วย',
        );
        await tester.enterText(
          find.byKey(const ValueKey('part-of-speech-field')),
          'noun',
        );
        await tester.tap(find.byKey(const ValueKey('save-word')));
        await _pumpUntil(tester, find.text('banana'));
        await tester.pumpAndSettle();
        expect(find.text('อาหาร'), findsOneWidget);
        expect(find.text('station'), findsNothing);
        await tester.runAsync(() async {
          final categories = await database
              .select(database.vocabularyCategories)
              .get();
          final food = categories.singleWhere(
            (category) => category.name == 'อาหาร',
          );
          final word = (await database.select(database.vocabularyWords).get())
              .singleWhere((word) => word.spelling == 'banana');
          expect(word.categoryId, food.id);
        });
      } finally {
        await disposeLibrary(tester);
      }
    },
  );

  testWidgets(
    'global word search opens B and preserves its query on return to A',
    (tester) async {
      try {
        await pumpLibrary(tester);
        await tester.tap(find.text('การเดินทาง'));
        await _pumpUntil(tester, find.text('ฝึกจากชุดนี้'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('category-search'));
        await tester.enterText(search, 'apple');
        final hit = find.widgetWithText(ListTile, 'apple');
        await _pumpUntil(tester, hit);
        await tester.pumpAndSettle();
        expect(find.text('อาหาร'), findsOneWidget);
        await tester.tap(hit);
        await _pumpUntil(tester, find.text('ฝึกจากชุดนี้'));
        await tester.pumpAndSettle();
        expect(find.text('อาหาร'), findsOneWidget);
        expect(find.text('station'), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.widget<SearchBar>(search).controller!.text, 'apple');
        await tester.enterText(search, 'การเดินทาง');
        final setA = find.widgetWithText(ListTile, 'การเดินทาง');
        await _pumpUntil(tester, setA);
        await tester.pumpAndSettle();
        await tester.tap(setA);
        await _pumpUntil(tester, find.text('ฝึกจากชุดนี้'));
        await tester.pumpAndSettle();
        expect(find.text('station'), findsOneWidget);
        expect(find.text('apple'), findsNothing);
      } finally {
        await disposeLibrary(tester);
      }
    },
  );

  testWidgets(
    'global add can create a destination and cancel before adding a word',
    (tester) async {
      try {
        await pumpLibrary(tester);
        await tester.tap(find.byKey(const ValueKey('library-add-word')));
        await _pumpUntil(tester, find.text('เลือกชุดที่จะเพิ่มคำ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('สร้างชุดคำศัพท์ใหม่'));
        await _pumpUntil(
          tester,
          find.byKey(const ValueKey('category-name-field')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('category-name-field')),
          'ชุดใหม่สังเคราะห์',
        );
        await tester.tap(find.byKey(const ValueKey('save-category')));
        await _pumpUntil(tester, find.text('พิมพ์คำศัพท์'));
        await tester.pumpAndSettle();
        expect(find.text('เพิ่มคำใน ชุดใหม่สังเคราะห์'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('ชุดใหม่สังเคราะห์'), findsOneWidget);
        expect(
          await tester.runAsync(
            () => database.select(database.vocabularyWords).get(),
          ),
          hasLength(2),
        );
        expect(
          await tester.runAsync(
            () => database.select(database.vocabularyCategories).get(),
          ),
          hasLength(3),
        );
      } finally {
        await disposeLibrary(tester);
      }
    },
  );

  testWidgets('selected set reads and reopens its persisted latest result', (
    tester,
  ) async {
    try {
      await pumpLibrary(tester, travelContrast: true);
      await tester.tap(find.text('การเดินทาง'));
      await _pumpUntil(tester, find.text('ฝึกจากชุดนี้'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ฝึกจากชุดนี้'));
      await _pumpUntil(tester, find.text('เริ่มฝึก'));
      await tester.ensureVisible(find.text('เริ่มฝึก'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เริ่มฝึก'));
      await _pumpUntil(
        tester,
        find.descendant(
          of: find.byType(QuizScreen),
          matching: find.text('station'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'สถานี'));
      await _pumpUntil(tester, find.text('คำถามถัดไป'));
      await tester.ensureVisible(find.text('คำถามถัดไป'));
      await tester.tap(find.text('คำถามถัดไป'));
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'ตั๋ว'));
      await tester.tap(find.widgetWithText(FilledButton, 'ตั๋ว'));
      await _pumpUntil(tester, find.text('ดูผลการเรียน'));
      await tester.ensureVisible(find.text('ดูผลการเรียน'));
      await tester.tap(find.text('ดูผลการเรียน'));
      await _pumpUntil(tester, find.byType(ScoreScreen));
      await tester.pumpAndSettle();
      final firstScore = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
      final sessionId = firstScore.sessionId;
      expect(sessionId, isNotNull);
      expect(firstScore.correctAnswers, 2);
      expect(firstScore.wrongAnswers, 0);
      final savedSession = (await tester.runAsync(
        () => database.select(database.learningSessions).getSingle(),
      ))!;
      final savedAttempts = (await tester.runAsync(
        () => database.select(database.answerAttempts).get(),
      ))!;
      expect(savedSession.id, sessionId);
      expect(savedSession.state, 'completed');
      expect(savedSession.correctCount, 2);
      expect(savedSession.wrongCount, 0);
      expect(savedSession.score, 100);
      expect(savedAttempts, hasLength(2));
      await tester.ensureVisible(find.text('กลับไปที่ชุดคำ'));
      await tester.tap(find.text('กลับไปที่ชุดคำ'));
      await _pumpUntil(tester, find.text('ดูผลล่าสุด'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ดูผลล่าสุด'));
      await tester.tap(find.text('ดูผลล่าสุด'));
      await _pumpUntil(tester, find.byType(ScoreScreen));
      await tester.pumpAndSettle();
      final reopened = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
      expect(reopened.sessionId, sessionId);
      expect(reopened.correctAnswers, 2);
      expect(reopened.wrongAnswers, 0);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('การเดินทาง'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => database.select(database.answerAttempts).get(),
        ),
        savedAttempts,
      );
      expect(
        await tester.runAsync(
          () => database.select(database.learningSessions).getSingle(),
        ),
        savedSession,
      );
    } finally {
      await disposeLibrary(tester);
    }
  });

  for (final changeCategory in [false, true]) {
    testWidgets(
      'pending latest result rejects a changed ${changeCategory ? 'category' : 'progress scope'}',
      (tester) async {
        try {
          await pumpLibrary(tester);
          final ids = await tester.runAsync(() async {
            final categories = await database
                .select(database.vocabularyCategories)
                .get();
            final a = categories.singleWhere(
              (category) => category.name == 'การเดินทาง',
            );
            final b = categories.singleWhere(
              (category) => category.name == 'อาหาร',
            );
            final word = (await database.select(database.vocabularyWords).get())
                .singleWhere((word) => word.categoryId == a.id);
            final now = DateTime.utc(2026, 11, 13).millisecondsSinceEpoch;
            await database
                .into(database.learningSessions)
                .insert(
                  LearningSessionsCompanion.insert(
                    id: 'synthetic-held-session',
                    ownerId: a.ownerId,
                    activityType: 'quiz',
                    state: 'completed',
                    startedAtUtcMs: now,
                    endedAtUtcMs: Value(now),
                    correctCount: const Value(1),
                    score: const Value(100),
                    appVersion: 'test',
                    buildId: 'test',
                  ),
                );
            await database
                .into(database.answerAttempts)
                .insert(
                  AnswerAttemptsCompanion.insert(
                    id: 'synthetic-held-attempt',
                    ownerId: a.ownerId,
                    sessionId: 'synthetic-held-session',
                    wordId: word.id,
                    promptMode: 'meaningChoice',
                    isCorrect: true,
                    attemptNumber: 1,
                    occurredAtUtcMs: now,
                  ),
                );
            return (a: a.id, b: b.id);
          });
          final owners = dependencies.learning!.owners;
          final delayed = _DelayedOwners(owners);
          final first = ProgressUseCases(
            owners: delayed,
            queries: DriftProgressQueries(database),
            nowUtc: () => DateTime.utc(2026, 11, 14),
          );
          Widget app(
            String categoryId,
            String categoryName,
            ProgressUseCases progress,
          ) => AppDependenciesScope(
            dependencies: AppDependencies(
              runtimeStatus: dependencies.runtimeStatus,
              config: null,
              guestSessionService: _GuestSession(),
              vocabulary: vocabulary,
              learning: dependencies.learning,
              progress: progress,
            ),
            child: MaterialApp(
              home: VocabListScreen(
                categoryId: categoryId,
                categoryName: categoryName,
              ),
            ),
          );
          await tester.pumpWidget(app(ids!.a, 'การเดินทาง', first));
          await _pumpUntil(tester, find.text('ดูผลล่าสุด'));
          await tester.pumpAndSettle();
          delayed.gate = Completer<void>();
          await tester.tap(find.text('ดูผลล่าสุด'));
          await tester.pump();
          expect(delayed.waits, greaterThan(0));
          final replacement = changeCategory
              ? first
              : ProgressUseCases(
                  owners: owners,
                  queries: DriftProgressQueries(database),
                  nowUtc: () => DateTime.utc(2026, 11, 14),
                );
          await tester.pumpWidget(
            app(
              changeCategory ? ids.b : ids.a,
              changeCategory ? 'อาหาร' : 'การเดินทาง',
              replacement,
            ),
          );
          await tester.pump();
          if (changeCategory) {
            expect(find.textContaining('ผลล่าสุด ·'), findsNothing);
          }
          delayed.gate!.complete();
          await _pumpUntil(
            tester,
            find.text('อ่านผลล่าสุดไม่สำเร็จ กรุณาลองใหม่'),
          );
          expect(find.byType(ScoreScreen), findsNothing);
        } finally {
          await disposeLibrary(tester);
        }
      },
    );
  }

  testWidgets(
    'library corrects and practices a picked JSON file at 200% text',
    (tester) async {
      try {
        await pumpLibrary(tester, scale: 2);
        final before = await tester.runAsync(() => _localRecords(database));
        final search = find.byKey(const ValueKey('category-search'));
        await tester.ensureVisible(search);
        await tester.enterText(search, 'การเดิน');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await _tapLabel(tester, 'นำเข้าชุดคำ');

        var picks = 0;
        pickImportFile = () async =>
            ++picks == 1 ? null : _jsonFile('ของที่เลือก.json', _bagItems);
        await _tapLabel(tester, 'ฝึกจากรายการ JSON');
        expect(picks, 1);
        expect(find.text('ตรวจรายการจากไฟล์'), findsNothing);
        await _tapLabel(tester, 'ฝึกจากรายการ JSON');
        expect(picks, 2);
        expect(find.text('ตรวจรายการจากไฟล์'), findsOneWidget);
        final draft = find.byType(TextField);
        expect(
          tester.widget<TextField>(draft).controller!.text.trimRight(),
          _bagItems.trimRight(),
        );
        await _tapLabel(tester, 'อ่านรายการคำ');
        expect(find.text('ยังอ่านไฟล์นี้ไม่ได้'), findsOneWidget);
        expect(find.text('คำที่ยังอยู่ในร่าง'), findsOneWidget);
        await _tapLabel(tester, 'เติม ] ในร่าง');
        final corrected = tester.widget<TextField>(draft).controller!.text;
        expect(corrected.trimRight(), endsWith(']'));
        expect(
          corrected.trimRight().replaceFirst(RegExp(r'\]$'), '').trimRight(),
          _bagItems.trimRight(),
        );
        await _tapLabel(tester, 'อ่านรายการคำ');
        expect(find.text('พร้อมฝึก 2 คำ'), findsOneWidget);
        expect(find.text('pencil'), findsOneWidget);
        expect(find.text('wallet'), findsOneWidget);

        await _tapLabel(tester, 'ฝึกสองคำนี้');
        expect(find.text('pencil'), findsOneWidget);
        expect(find.text('ดินสอ'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('พร้อมฝึก 2 คำ'), findsOneWidget);
        await _tapLabel(tester, 'ฝึกสองคำนี้');
        await _tapLabel(tester, 'เปิดคำแปล');
        expect(find.text('ดินสอ'), findsOneWidget);
        await _tapLabel(tester, 'ลองนึกอีกครั้ง');
        expect(find.text('pencil'), findsOneWidget);
        expect(find.text('ดินสอ'), findsNothing);
        await _tapLabel(tester, 'เปิดคำแปล');
        await _tapLabel(tester, 'จำได้แล้ว');
        expect(find.text('wallet'), findsOneWidget);
        expect(find.text('กระเป๋าสตางค์'), findsNothing);
        await _tapLabel(tester, 'เปิดคำแปล');
        expect(find.text('กระเป๋าสตางค์'), findsOneWidget);
        await _tapLabel(tester, 'จำได้แล้ว');
        expect(find.text('ฝึกครบทั้งสองคำแล้ว'), findsOneWidget);
        await _tapLabel(tester, 'ทบทวนอีกครั้ง');
        expect(find.text('พร้อมฝึก 2 คำ'), findsOneWidget);
        await _tapLabel(tester, 'ฝึกสองคำนี้');
        expect(find.text('pencil'), findsOneWidget);
        for (var card = 0; card < 2; card++) {
          await _tapLabel(tester, 'เปิดคำแปล');
          await _tapLabel(tester, 'จำได้แล้ว');
        }
        await _tapLabel(tester, 'กลับคลังคำ');
        await _pumpUntil(tester, search);
        expect(tester.widget<SearchBar>(search).controller!.text, 'การเดิน');
        expect(find.text('อาหาร'), findsNothing);
        await _tapLabel(tester, 'นำเข้าชุดคำ');
        expect(find.text('ฝึกจากรายการ JSON'), findsOneWidget);
        expect(find.text('พร้อมฝึก 2 คำ'), findsNothing);
        expect(picks, 2);
        expect(await tester.runAsync(() => _localRecords(database)), before);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeLibrary(tester);
      }
    },
  );

  testWidgets('a pending JSON picker cannot show owner A data to owner B', (
    tester,
  ) async {
    try {
      await pumpLibrary(tester, scale: 2);
      final pending = Completer<VocabularyImportFile?>();
      var pickerOpened = false;
      pickImportFile = () {
        pickerOpened = true;
        return pending.future;
      };
      await _tapLabel(tester, 'นำเข้าชุดคำ');
      final chooseFile = find.text('ฝึกจากรายการ JSON');
      await tester.ensureVisible(chooseFile);
      await tester.tap(chooseFile);
      for (var frame = 0; frame < 50 && !pickerOpened; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(pickerOpened, isTrue);

      await _withFrames(tester, () async {
        await database.transaction(() async {
          await database
              .update(database.localOwners)
              .write(const LocalOwnersCompanion(isActive: Value(false)));
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'synthetic-b',
                  createdAtUtcMs: 0,
                ),
              );
        });
        await vocabulary.createCategory('ชุดของบัญชี B');
      });
      final beforeReturn = await _withFrames(
        tester,
        () => _localRecords(database),
      );
      pending.complete(_jsonFile('รายการส่วนตัว A.json', '$_bagItems]'));
      await tester.pumpAndSettle();
      expect(find.textContaining('รายการส่วนตัว A.json'), findsNothing);
      expect(find.text('ตรวจรายการจากไฟล์'), findsNothing);
      expect(find.text('พร้อมฝึก 2 คำ'), findsNothing);
      if (find.byType(CategoriesPage).evaluate().isEmpty) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      await _pumpUntil(tester, find.text('ชุดของบัญชี B'));
      expect(find.text('การเดินทาง'), findsNothing);
      expect(
        await _withFrames(tester, () => _localRecords(database)),
        beforeReturn,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await disposeLibrary(tester);
    }
  });

  testWidgets('library previews pasted table rows in the chosen set', (
    tester,
  ) async {
    try {
      await pumpLibrary(tester, scale: 2);
      final before = await tester.runAsync(() => _localRecords(database));
      await _tapLabel(tester, 'นำเข้าชุดคำ');
      await _tapLabel(tester, 'วางคำจากตาราง');
      final sheet = find.byType(BottomSheet);
      await _pumpUntil(tester, sheet);
      final destination = find.descendant(
        of: sheet,
        matching: find.text('การเดินทาง'),
      );
      await tester.ensureVisible(destination);
      await tester.pumpAndSettle();
      await tester.tap(destination.hitTestable());
      await tester.pumpAndSettle();
      final pasted = find.byKey(const ValueKey('paste-import-csv'));
      await _pumpUntil(tester, pasted);
      await tester.ensureVisible(pasted);
      await tester.enterText(
        pasted,
        'word,meaning,partOfSpeech\ncarriage,ตู้โดยสาร,noun',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await _tapLabel(tester, 'ตรวจคำจากตาราง');
      await _pumpUntil(tester, find.text('ผ่าน 1 · ต้องแก้ 0 · ซ้ำ 0'));
      await tester.scrollUntilVisible(
        find.text('carriage'),
        120,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await _pumpUntil(tester, find.text('carriage'));
      expect(await tester.runAsync(() => _localRecords(database)), before);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('วางคำจากตาราง'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _pumpUntil(tester, find.text('การเดินทาง'));
      expect(await tester.runAsync(() => _localRecords(database)), before);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeLibrary(tester);
    }
  });

  testWidgets(
    'one add menu preserves the set when file selection is cancelled',
    (tester) async {
      try {
        await pumpLibrary(tester, scale: 2);
        await tester.tap(find.text('การเดินทาง'));
        await _pumpUntil(tester, find.text('station'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('add-word')));
        await tester.pumpAndSettle();
        expect(find.text('พิมพ์คำศัพท์'), findsOneWidget);
        expect(find.text('ถ่ายภาพ'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('import-words')));
        await tester.tap(find.byKey(const ValueKey('import-words')));
        await _tapLabel(tester, 'เพิ่มคำจากตารางเข้าคลัง');
        await _pumpUntil(tester, find.byType(AddMultipleWordsScreen));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('choose-import-file')));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await _tapLabel(tester, 'กลับคลังคำ');
        await _pumpUntil(tester, find.text('station'));
        await tester.pumpAndSettle();
        expect(find.text('การเดินทาง'), findsOneWidget);
        expect(
          await tester.runAsync(
            () => database.select(database.vocabularyWords).get(),
          ),
          hasLength(2),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await disposeLibrary(tester);
      }
    },
  );

  testWidgets(
    'one-meaning practice offers Add in the selected set and returns to its words',
    (tester) async {
      try {
        await pumpLibrary(tester);
        await tester.tap(find.text('การเดินทาง'));
        await _pumpUntil(tester, find.text('station'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ฝึกจากชุดนี้'));
        await _pumpUntil(
          tester,
          find.descendant(
            of: find.byType(QuizScreen),
            matching: find.text('รอบนี้ยังไม่มีความหมายอื่นให้เลือก'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('quiz-add-word')), findsOneWidget);
        expect(find.text('การเดินทาง'), findsOneWidget);
        expect(find.text('apple'), findsNothing);
        expect(find.text('ดูผลการเรียน'), findsNothing);
        await tester.pageBack();
        await _pumpUntil(tester, find.text('ฝึกจากชุดนี้'));
        await tester.pumpAndSettle();
        expect(find.text('station'), findsOneWidget);
        expect(find.text('การเดินทาง'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeLibrary(tester);
      }
    },
  );
}

Future<void> _tapLabel(WidgetTester tester, String label) async {
  final item = find.text(label);
  await _pumpUntil(tester, item);
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  if (item.hitTestable().evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).hitTestable();
    await tester.scrollUntilVisible(
      item.hitTestable(),
      140,
      scrollable: scrollable.last,
    );
  }
  await tester.tap(item.hitTestable().first);
  await tester.pumpAndSettle();
}

Future<T> _withFrames<T>(
  WidgetTester tester,
  Future<T> Function() action,
) async {
  var complete = false;
  final future = action().whenComplete(() => complete = true);
  unawaited(future.then<void>((_) {}, onError: (Object _) {}));
  for (var frame = 0; frame < 80 && !complete; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(complete, isTrue, reason: 'local database operation must finish');
  return future;
}

Future<List<Object>> _localRecords(AppDatabase database) async => [
  await database.select(database.localOwners).get(),
  await database.select(database.vocabularyCategories).get(),
  await database.select(database.vocabularyWords).get(),
  await database.select(database.vocabularyImports).get(),
  await database.select(database.vocabularyImportRows).get(),
  await database.select(database.learningSessions).get(),
  await database.select(database.answerAttempts).get(),
  await database.select(database.srsStates).get(),
  await database.select(database.eventsV2).get(),
  await database.select(database.readingEvents).get(),
  await database.select(database.researchConsents).get(),
  await database.select(database.rewardTransactions).get(),
  await database.select(database.outboxOperations).get(),
];

final class _DelayedOwners extends Fake implements LocalOwnerRepository {
  _DelayedOwners(this.delegate);
  final LocalOwnerRepository delegate;
  Completer<void>? gate;
  var waits = 0;
  @override
  Future<owner_domain.LocalOwner> getOrCreateActiveOwner() async {
    final pending = gate;
    if (pending != null) {
      waits++;
      await pending.future;
    }
    return delegate.getOrCreateActiveOwner();
  }
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 80; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
