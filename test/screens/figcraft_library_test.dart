import 'dart:async';

import 'package:drift/drift.dart' show Value;
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

void main() {
  late AppDatabase database;
  late AppDependencies dependencies;
  late VocabularyUseCases vocabulary;
  var nextId = 0;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    nextId = 0;
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
      vocabularyImportFilePicker: () async => null,
    );
  });

  Future<void> pumpLibrary(WidgetTester tester, {double scale = 1}) async {
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
      await pumpLibrary(tester);
      await tester.tap(find.text('การเดินทาง'));
      await _pumpUntil(tester, find.text('ฝึกจากชุดนี้'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ฝึกจากชุดนี้'));
      await _pumpUntil(
        tester,
        find.descendant(
          of: find.byType(QuizScreen),
          matching: find.text('station'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'สถานี'));
      await _pumpUntil(tester, find.text('ดูผลการเรียน'));
      await tester.ensureVisible(find.text('ดูผลการเรียน'));
      await tester.tap(find.text('ดูผลการเรียน'));
      await _pumpUntil(tester, find.byType(ScoreScreen));
      await tester.pumpAndSettle();
      final sessionId = tester
          .widget<ScoreScreen>(find.byType(ScoreScreen))
          .sessionId;
      await tester.ensureVisible(find.text('กลับไปที่ชุดคำ'));
      await tester.tap(find.text('กลับไปที่ชุดคำ'));
      await _pumpUntil(tester, find.text('ดูผลล่าสุด'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ดูผลล่าสุด'));
      await tester.tap(find.text('ดูผลล่าสุด'));
      await _pumpUntil(tester, find.byType(ScoreScreen));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ScoreScreen>(find.byType(ScoreScreen)).sessionId,
        sessionId,
      );
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('การเดินทาง'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => database.select(database.answerAttempts).get(),
        ),
        hasLength(1),
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
        await _pumpUntil(tester, find.byType(AddMultipleWordsScreen));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('choose-import-file')));
        await tester.pumpAndSettle();
        await tester.pageBack();
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

  testWidgets('practice uses only the selected set and returns to its words', (
    tester,
  ) async {
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
          matching: find.text('station'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('apple'), findsNothing);
      await tester.pageBack();
      await _pumpUntil(tester, find.text('ฝึกจากชุดนี้'));
      await tester.pumpAndSettle();
      expect(find.text('station'), findsOneWidget);
      expect(find.text('การเดินทาง'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeLibrary(tester);
    }
  });
}

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
