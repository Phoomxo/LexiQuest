import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
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
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
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

  testWidgets('one add menu preserves the set when file selection is cancelled', (
    tester,
  ) async {
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
        await tester.runAsync(() => database.select(database.vocabularyWords).get()),
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await disposeLibrary(tester);
    }
  });

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
