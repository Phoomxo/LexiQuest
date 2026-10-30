import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as domain_owner;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/saved_words_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_saved_words_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart'
    as domain_vocabulary;
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart'
    as domain_word;
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/add_vocab_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/saved_words_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/saved_words_data_harness.dart' as saved_data;

class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'offline-vocabulary-guest');
}

class _DialogOwnerRepository extends Fake implements LocalOwnerRepository {
  @override
  Future<domain_owner.LocalOwner> getOrCreateActiveOwner() async =>
      domain_owner.LocalOwner(
        id: 'dialog-owner',
        createdAtUtc: DateTime.utc(2026, 10, 24),
      );
}

class _DialogVocabularyRepository extends Fake implements VocabularyRepository {
  var createCalls = 0;
  var wordCreateCalls = 0;
  Completer<void>? createPending;
  Completer<void>? wordCreatePending;

  @override
  Stream<List<domain_vocabulary.VocabularyCategory>> watchCategories(
    String ownerId,
  ) => Stream.value(const []);

  @override
  Future<domain_vocabulary.VocabularyCategory> createCategory(
    domain_vocabulary.VocabularyCategory category,
  ) async {
    createCalls++;
    await createPending?.future;
    return category;
  }

  @override
  Future<domain_word.VocabularyWord> createWord(
    domain_word.VocabularyWord word,
  ) async {
    wordCreateCalls++;
    await wordCreatePending?.future;
    return word;
  }
}

class _RetryVocabularyRepository extends Fake implements VocabularyRepository {
  var watchCalls = 0;

  @override
  Stream<List<domain_vocabulary.VocabularyCategory>> watchCategories(
    String ownerId,
  ) {
    watchCalls++;
    if (watchCalls == 1) {
      return Stream.error(StateError('synthetic category read failure'));
    }
    final now = DateTime.utc(2026, 10, 24);
    return Stream.value([
      domain_vocabulary.VocabularyCategory(
        id: 'recovered-category',
        ownerId: ownerId,
        name: 'กู้คืนแล้ว',
        normalizedName: 'กู้คืนแล้ว',
        sortOrder: 0,
        localRevision: 1,
        isDeleted: false,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    ]);
  }
}

void main() {
  late AppDatabase database;
  late AppDependencies dependencies;
  late DateTime nowUtc;
  late int idCounter;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    nowUtc = DateTime.utc(2026, 7, 30, 13);
    idCounter = 0;
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => nowUtc,
    );
    await owners.getOrCreateActiveOwner();
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'id-${++idCounter}',
      nowUtc: () => nowUtc,
    );
    dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSessionService(),
      database: database,
      localOwners: owners,
      progress: ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => nowUtc,
      ),
      savedWords: SavedWordsUseCases(
        repository: DriftSavedWordsRepository(
          database,
          ownerWrites: DriftOwnerWriteCoordinator(
            database,
            nowUtc: () => nowUtc,
          ),
        ),
        generateId: () => 'saved-${++idCounter}',
        nowUtc: () => nowUtc,
      ),
      vocabulary: vocabulary,
      vocabularyImporter: ImportVocabulary(
        owners: owners,
        repository: DriftVocabularyImportRepository(database),
        generateId: () => 'import-${++idCounter}',
        nowUtc: () => nowUtc,
      ),
      learning: LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'learning-${++idCounter}',
        nowUtc: () => nowUtc,
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      ),
      sourcePracticeFilePicker: () async => null,
    );
  });

  Future<void> pumpCategories(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    return tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: MaterialApp(home: CategoriesPage()),
      ),
    );
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 50,
  }) async {
    for (var index = 0; index < maxPumps; index++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList(growable: false);
    fail(
      'Widget did not appear after $maxPumps bounded pumps: $finder. '
      'Visible text: $visibleText',
    );
  }

  Future<void> finishRouteTransition(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
    'dismissing add category while its field is focused keeps the tree valid',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CategoriesPage(
            vocabulary: VocabularyUseCases(
              owners: _DialogOwnerRepository(),
              vocabulary: _DialogVocabularyRepository(),
              generateId: () => 'unused',
              nowUtc: () => DateTime.utc(2026, 10, 24),
            ),
          ),
        ),
      );
      await pumpUntilFound(tester, find.textContaining('ยังไม่มีหมวดหมู่'));

      await tester.tap(find.byKey(const ValueKey('add-category')));
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('category-name-field')),
      );
      await tester.showKeyboard(
        find.byKey(const ValueKey('category-name-field')),
      );
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tapAt(const Offset(790, 10));
      await tester.pump(const Duration(milliseconds: 16));
      final exception = tester.takeException();
      await finishRouteTransition(tester);

      expect(find.byKey(const ValueKey('category-name-field')), findsNothing);

      expect(exception, isNull);
    },
  );

  testWidgets('add category validates inside the dialog before persistence', (
    tester,
  ) async {
    final repository = _DialogVocabularyRepository();
    final vocabulary = VocabularyUseCases(
      owners: _DialogOwnerRepository(),
      vocabulary: repository,
      generateId: () => 'category-id',
      nowUtc: () => DateTime.utc(2026, 10, 24),
    );
    await tester.pumpWidget(
      MaterialApp(home: CategoriesPage(vocabulary: vocabulary)),
    );
    await pumpUntilFound(tester, find.textContaining('ยังไม่มีหมวดหมู่'));

    await tester.tap(find.byKey(const ValueKey('add-category')));
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('category-name-field')),
    );
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('category-name-field')))
          .decoration
          ?.errorText,
      'กรอกชื่อหมวดหมู่',
    );
    expect(repository.createCalls, 0);

    repository.createPending = Completer<void>();
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Travel',
    );
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.createCalls, 1);

    repository.createPending!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.createCalls, 1);
  });

  testWidgets('add word validates every field and guards pending navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _DialogVocabularyRepository();
    final vocabulary = VocabularyUseCases(
      owners: _DialogOwnerRepository(),
      vocabulary: repository,
      generateId: () => 'word-id',
      nowUtc: () => DateTime.utc(2026, 10, 24),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AddWordScreen(
                  categoryId: 'category-id',
                  vocabulary: vocabulary,
                ),
              ),
            ),
            child: const Text('เปิดเพิ่มคำศัพท์'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดเพิ่มคำศัพท์'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('save-word')));
    await tester.tap(find.byKey(const ValueKey('save-word')));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('word-field')))
          .decoration
          ?.errorText,
      'กรอกคำศัพท์',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('meaning-field')))
          .decoration
          ?.errorText,
      'กรอกความหมาย',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('part-of-speech-field')))
          .decoration
          ?.errorText,
      'กรอกชนิดของคำ',
    );
    expect(repository.wordCreateCalls, 0);

    repository.wordCreatePending = Completer<void>();
    await tester.enterText(find.byKey(const ValueKey('word-field')), 'station');
    await tester.enterText(
      find.byKey(const ValueKey('meaning-field')),
      'สถานี',
    );
    await tester.enterText(
      find.byKey(const ValueKey('part-of-speech-field')),
      'noun',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-word')));
    await tester.tap(find.byKey(const ValueKey('save-word')));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byKey(const ValueKey('word-field')), findsOneWidget);
    expect(repository.wordCreateCalls, 1);

    repository.wordCreatePending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('เปิดเพิ่มคำศัพท์'), findsOneWidget);
  });

  testWidgets('category retry creates one fresh subscription and recovers', (
    tester,
  ) async {
    final repository = _RetryVocabularyRepository();
    final vocabulary = VocabularyUseCases(
      owners: _DialogOwnerRepository(),
      vocabulary: repository,
      generateId: () => 'unused',
      nowUtc: () => DateTime.utc(2026, 10, 24),
    );

    await tester.pumpWidget(
      MaterialApp(home: CategoriesPage(vocabulary: vocabulary)),
    );
    await pumpUntilFound(tester, find.text('อ่านหมวดหมู่ไม่สำเร็จ'));
    expect(repository.watchCalls, 1);

    await tester.tap(find.text('ลองใหม่'));
    await pumpUntilFound(tester, find.text('กู้คืนแล้ว'));

    expect(repository.watchCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'guest vocabulary survives widget reconstruction without cloud',
    (tester) async {
      await pumpCategories(tester);
      await pumpUntilFound(tester, find.textContaining('ยังไม่มีหมวดหมู่'));

      await tester.tap(find.byKey(const ValueKey('add-category')));
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('category-name-field')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('category-name-field')),
        'Travel',
      );
      await tester.tap(find.byKey(const ValueKey('save-category')));
      await pumpUntilFound(tester, find.text('Travel'));

      expect(find.text('Travel'), findsOneWidget);
      expect(find.byTooltip('ลบหมวดหมู่ Travel'), findsOneWidget);
      await tester.tap(find.text('Travel'));
      await pumpUntilFound(tester, find.byKey(const ValueKey('add-word')));
      await finishRouteTransition(tester);
      expect(find.byKey(const ValueKey('source-practice')), findsOneWidget);
      expect(find.text('ฝึกจากไฟล์'), findsOneWidget);
      expect(find.text('นำเข้าคำศัพท์'), findsOneWidget);
      expect(find.text('เพิ่มคำศัพท์'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('source-practice')),
          matching: find.byType(Wrap),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('import-words')),
          matching: find.byType(Wrap),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('source-practice')));
      await pumpUntilFound(tester, find.text('ฝึกจากไฟล์ในเครื่อง'));
      await tester.tap(find.byTooltip('Back').last);
      await pumpUntilFound(tester, find.byKey(const ValueKey('add-word')));
      await finishRouteTransition(tester);

      final enabledAdd = find
          .byWidgetPredicate(
            (widget) =>
                widget is FloatingActionButton &&
                widget.key == const ValueKey('add-word') &&
                widget.onPressed != null,
          )
          .hitTestable();
      await pumpUntilFound(tester, enabledAdd);
      await tester.tap(enabledAdd);
      await pumpUntilFound(tester, find.byKey(const ValueKey('word-field')));
      await finishRouteTransition(tester);
      await tester.enterText(
        find.byKey(const ValueKey('word-field')),
        'station',
      );
      await tester.enterText(
        find.byKey(const ValueKey('meaning-field')),
        'สถานี',
      );
      await tester.enterText(
        find.byKey(const ValueKey('part-of-speech-field')),
        'noun',
      );
      await tester.tap(find.byKey(const ValueKey('save-word')));
      await pumpUntilFound(tester, find.text('ค้นหาคำศัพท์'));
      await finishRouteTransition(tester);
      await pumpUntilFound(tester, find.text('station'));

      expect(find.text('station'), findsOneWidget);
      expect(find.textContaining('สถานี'), findsOneWidget);
      expect(find.byTooltip('ลบคำศัพท์ station'), findsOneWidget);

      final word = await tester.runAsync(
        () => database.select(database.vocabularyWords).getSingle(),
      );
      await tester.tap(find.byKey(ValueKey('vocab-save:${word!.id}')));
      await tester.pump();
      final saved = await tester.runAsync(
        () => dependencies.savedWords!.watchOwner(word.ownerId).first,
      );
      expect(saved!.savedItems.single.wordId, word.id);
      expect(
        await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ),
        isEmpty,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpCategories(tester);
      await pumpUntilFound(tester, find.text('Travel'));

      expect(find.text('Travel'), findsOneWidget);
      await tester.tap(find.text('Travel'));
      await pumpUntilFound(tester, find.text('station'));

      await tester.tap(find.byKey(const ValueKey('saved-words')));
      await pumpUntilFound(tester, find.byType(SavedWordsScreen));
      await finishRouteTransition(tester);
      await pumpUntilFound(tester, find.text('station'));
      await tester.tap(find.byKey(const ValueKey('saved-practice')));
      await pumpUntilFound(tester, find.byType(QuizScreen));
      final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
      expect(quiz.selectionMode, QuizWordSelectionMode.sourcePractice);
      expect(quiz.wordIds, [word.id]);
      expect(quiz.expectedOwnerId, word.ownerId);
      await pumpUntilFound(tester, find.text('เลือกคำแปลที่ตรงกับคำศัพท์'));
      final option = find.widgetWithText(FilledButton, 'สถานี');
      await tester.ensureVisible(option);
      await tester.tap(option);
      await pumpUntilFound(tester, find.text('ดูผลการเรียน'));
      await tester.ensureVisible(find.text('ดูผลการเรียน'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ดูผลการเรียน').hitTestable());
      await pumpUntilFound(tester, find.byType(ScoreScreen));
      final sessions = await tester.runAsync(
        () => database.select(database.learningSessions).get(),
      );
      expect(sessions!.single.activityType, 'sourcePractice');
      expect(sessions.single.state, 'completed');
      expect(
        (await tester.runAsync(
          () => database.select(database.answerAttempts).get(),
        ))!,
        hasLength(1),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(database.close);
      await tester.pump(const Duration(milliseconds: 1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'offline saved UI survives actual database restart and finishes canonical practice',
    (tester) async {
      final tempRoot = (await tester.runAsync(
        Directory.systemTemp.resolveSymbolicLinks,
      ))!;
      final directory = (await tester.runAsync(
        () => Directory(tempRoot).createTemp('lexiquest-saved-ui-'),
      ))!;
      final file = File(
        '${directory.path}${Platform.pathSeparator}saved.sqlite',
      );
      var saved = (await tester.runAsync(
        () => saved_data.SavedWordsDataHarness.open(file: file),
      ))!;
      var ids = 0;
      AppDependencies compose(saved_data.SavedWordsDataHarness h) {
        final owners = h.storage.owners;
        return AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.ready,
            firebase: RuntimeAvailability.unavailable,
            supabase: RuntimeAvailability.unavailable,
            backends: RuntimeAvailability.unavailable,
          ),
          config: null,
          guestSessionService: _GuestSessionService(),
          database: h.database,
          localOwners: owners,
          savedWords: h.useCases,
          progress: ProgressUseCases(
            owners: owners,
            queries: DriftProgressQueries(h.database),
            nowUtc: () => h.now,
          ),
          vocabulary: VocabularyUseCases(
            owners: owners,
            vocabulary: DriftVocabularyRepository(h.database),
            generateId: () => 'synthetic-restart-word-${++ids}',
            nowUtc: () => h.now,
          ),
          learning: LearningUseCases(
            owners: owners,
            repository: DriftLearningRepository(
              h.database,
              ownerWrites: h.storage.ownerWrites,
            ),
            generateId: () => 'synthetic-restart-learning-${++ids}',
            nowUtc: () => h.now,
            buildInfo: const AppBuildInfo(
              version: 'synthetic',
              buildId: 'saved-restart-ui',
            ),
          ),
        );
      }

      Widget app(AppDependencies deps, Widget home) => AppDependenciesScope(
        dependencies: deps,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: home,
        ),
      );
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final before = (await tester.runAsync(saved.storage.snapshot))!
          ..remove('saved_words');
        final first = compose(saved);
        await tester.pumpWidget(
          app(
            first,
            const VocabListScreen(
              categoryId: saved_data.configuredCategoryId,
              categoryName: 'Synthetic category',
            ),
          ),
        );
        await pumpUntilFound(tester, find.text('station'));
        await tester.tap(
          find.byKey(
            ValueKey('vocab-save:${saved_data.configuredWordIds.first}'),
          ),
        );
        final committed = await tester.runAsync(
          () => saved.useCases
              .watchOwner(saved_data.configuredOwnerId)
              .firstWhere((value) => value.savedItems.isNotEmpty)
              .timeout(const Duration(seconds: 3)),
        );
        expect(
          committed!.savedItems.single.wordId,
          saved_data.configuredWordIds.first,
        );
        final afterSave = (await tester.runAsync(saved.storage.snapshot))!
          ..remove('saved_words');
        expect(afterSave, before);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(saved.close);

        saved = (await tester.runAsync(
          () => saved_data.SavedWordsDataHarness.open(file: file, seed: false),
        ))!;
        final restarted = compose(saved);
        await tester.pumpWidget(
          app(
            restarted,
            const SavedWordsScreen(
              expectedOwnerId: saved_data.configuredOwnerId,
            ),
          ),
        );
        await pumpUntilFound(tester, find.text('station'));
        expect(
          (await tester.runAsync(saved.snapshot))!.savedItems,
          hasLength(1),
        );
        expect(
          await tester.runAsync(() => saved.storage.count('learning_sessions')),
          0,
        );
        await tester.tap(find.byKey(const ValueKey('saved-practice')));
        await pumpUntilFound(tester, find.byType(QuizScreen));
        final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
        expect(quiz.wordIds, [saved_data.configuredWordIds.first]);
        expect(quiz.selectionMode, QuizWordSelectionMode.sourcePractice);
        expect(quiz.expectedOwnerId, saved_data.configuredOwnerId);
        expect(quiz.learning, same(restarted.learning));
        await pumpUntilFound(tester, find.text('เลือกคำแปลที่ตรงกับคำศัพท์'));
        final option = find.widgetWithText(FilledButton, 'สถานี');
        await tester.ensureVisible(option);
        await tester.tap(option);
        await pumpUntilFound(tester, find.text('ดูผลการเรียน'));
        await tester.ensureVisible(find.text('ดูผลการเรียน'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ดูผลการเรียน').hitTestable());
        await pumpUntilFound(tester, find.byType(ScoreScreen));
        final sessions = (await tester.runAsync(
          () => saved.database.select(saved.database.learningSessions).get(),
        ))!;
        expect(sessions.single.activityType, 'sourcePractice');
        expect(sessions.single.ownerId, saved_data.configuredOwnerId);
        expect(sessions.single.state, 'completed');
        expect(
          await tester.runAsync(() => saved.storage.count('answer_attempts')),
          1,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(saved.close);
        await tester.runAsync(() async {
          final resolved = await directory.resolveSymbolicLinks();
          expect(
            resolved,
            startsWith('$tempRoot${Platform.pathSeparator}lexiquest-saved-ui-'),
          );
          expect(resolved, directory.absolute.path);
          await Directory(resolved).delete(recursive: true);
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
