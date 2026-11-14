import 'dart:async';

import 'package:drift/drift.dart' show Value;
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
import 'package:vocab_learning_app/services/guest_session_service.dart';

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
  Stream<List<domain_vocabulary.VocabularyCategorySummary>> watchLibrary(
    String ownerId,
  ) => watchCategories(ownerId).map(
    (categories) => categories
        .map(
          (category) => domain_vocabulary.VocabularyCategorySummary(
            category: category,
            wordCount: 0,
            previewSpellings: const [],
          ),
        )
        .toList(),
  );

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
  Stream<List<domain_vocabulary.VocabularyCategorySummary>> watchLibrary(
    String ownerId,
  ) => watchCategories(ownerId).map(
    (categories) => categories
        .map(
          (category) => domain_vocabulary.VocabularyCategorySummary(
            category: category,
            wordCount: 0,
            previewSpellings: const [],
          ),
        )
        .toList(),
  );

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
    'saved words persist across pages and remain within their vocabulary set',
    (tester) async {
      final vocabulary = dependencies.vocabulary!;
      late domain_vocabulary.VocabularyCategory travel;
      late domain_word.VocabularyWord station;
      await tester.runAsync(() async {
        travel = await vocabulary.createCategory('Travel');
        station = await vocabulary.createWord(
          CreateWordCommand(
            categoryId: travel.id,
            spelling: 'station',
            meaning: 'สถานี',
            partOfSpeech: 'noun',
          ),
        );
        await vocabulary.createWord(
          CreateWordCommand(
            categoryId: travel.id,
            spelling: 'ticket',
            meaning: 'ตั๋ว',
            partOfSpeech: 'noun',
          ),
        );
        final nature = await vocabulary.createCategory('Nature');
        final ocean = await vocabulary.createWord(
          CreateWordCommand(
            categoryId: nature.id,
            spelling: 'ocean',
            meaning: 'มหาสมุทร',
            partOfSpeech: 'noun',
          ),
        );
        await vocabulary.setBookmarked(
          expectedOwnerId: ocean.ownerId,
          wordId: ocean.id,
          bookmarked: true,
        );
      });

      Future<void> expectStoredBookmark(bool expected) async {
        for (var index = 0; index < 50; index++) {
          final stored = await tester.runAsync(() async {
            final words = await database.select(database.vocabularyWords).get();
            return words.singleWhere((word) => word.id == station.id);
          });
          await tester.pump(const Duration(milliseconds: 20));
          if (stored?.isBookmarked == expected) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        await tester.runAsync(() async {
          final words = await database.select(database.vocabularyWords).get();
          final stored = words.singleWhere((word) => word.id == station.id);
          expect(stored.isBookmarked, expected);
          expect(stored.ownerId, station.ownerId);
          expect(stored.categoryId, travel.id);
          expect(stored.spelling, 'station');
          expect(stored.isDeleted, isFalse);
          expect(
            words.singleWhere((word) => word.spelling == 'ocean').isBookmarked,
            isTrue,
          );
        });
      }

      Future<void> waitForSavedWordsUi({String? dismissedAction}) async {
        final savedChip = find.widgetWithText(ChoiceChip, 'คำที่เก็บไว้');
        for (var index = 0; index < 50; index++) {
          await tester.pump(const Duration(milliseconds: 20));
          final sheetClosed =
              dismissedAction == null ||
              find.text(dismissedAction).evaluate().isEmpty;
          if (sheetClosed &&
              savedChip.evaluate().length == 1 &&
              tester.widget<ChoiceChip>(savedChip).selected &&
              find.text('ticket').evaluate().isEmpty) {
            return;
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        if (dismissedAction != null) {
          expect(find.text(dismissedAction), findsNothing);
        }
        expect(tester.widget<ChoiceChip>(savedChip).selected, isTrue);
        expect(find.text('ticket'), findsNothing);
      }

      try {
        await pumpCategories(tester);
        await pumpUntilFound(tester, find.text('Travel'));
        await tester.tap(find.text('Travel'));
        await pumpUntilFound(tester, find.text('station'));
        await finishRouteTransition(tester);
        expect(find.text('ticket'), findsOneWidget);
        expect(find.byTooltip('ลบคำศัพท์ station'), findsOneWidget);

        await tester.tap(find.byTooltip('จัดการคำนี้ station'));
        await pumpUntilFound(tester, find.text('เก็บไว้อ่านอีกครั้ง'));
        await finishRouteTransition(tester);
        await tester.tap(find.text('เก็บไว้อ่านอีกครั้ง'));
        await finishRouteTransition(tester);
        await expectStoredBookmark(true);
        await waitForSavedWordsUi(dismissedAction: 'เก็บไว้อ่านอีกครั้ง');
        expect(find.text('station'), findsOneWidget);
        expect(find.text('ticket'), findsNothing);
        expect(find.text('ocean'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await pumpCategories(tester);
        await pumpUntilFound(tester, find.text('Travel'));
        await tester.tap(find.text('Travel'));
        await pumpUntilFound(tester, find.text('station'));
        await finishRouteTransition(tester);
        await tester.tap(find.text('คำที่เก็บไว้'));
        await waitForSavedWordsUi();
        expect(find.text('station'), findsOneWidget);
        expect(find.text('ticket'), findsNothing);
        expect(find.text('ocean'), findsNothing);
        await expectStoredBookmark(true);

        await tester.tap(find.byTooltip('จัดการคำนี้ station'));
        await pumpUntilFound(tester, find.text('นำออกจากรายการคำที่เก็บไว้'));
        await finishRouteTransition(tester);
        await tester.tap(find.text('นำออกจากรายการคำที่เก็บไว้'));
        await pumpUntilFound(tester, find.text('ยังไม่มีคำที่เก็บไว้'));
        await finishRouteTransition(tester);
        await expectStoredBookmark(false);
        await waitForSavedWordsUi(
          dismissedAction: 'นำออกจากรายการคำที่เก็บไว้',
        );
        expect(find.text('station'), findsNothing);
        await tester.tap(find.text('คำทั้งหมด'));
        await pumpUntilFound(tester, find.text('station'));
        expect(find.text('ticket'), findsOneWidget);
        expect(find.text('ocean'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(database.close);
        await tester.pump(const Duration(milliseconds: 1));
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'open bookmark sheet hides the old word after an active owner switch',
    (tester) async {
      final vocabulary = dependencies.vocabulary!;
      const nextOwner = 'local:bookmark-owner-b';
      const privateWord = 'synthetic-private-a';
      const privateMeaning = 'คำของบัญชีเดิม';
      const saveLabel = 'เก็บไว้อ่านอีกครั้ง';
      try {
        Future<void> activate(String ownerId) => database.transaction(() async {
          await (database.update(database.localOwners)
                ..where((row) => row.isActive.equals(true)))
              .write(const LocalOwnersCompanion(isActive: Value(false)));
          final changed =
              await (database.update(database.localOwners)
                    ..where((row) => row.id.equals(ownerId)))
                  .write(const LocalOwnersCompanion(isActive: Value(true)));
          if (changed != 1) throw StateError('Fixture must activate one owner');
        });

        Future<(List<VocabularyWord>, List<OutboxOperation>)>
        snapshot() async => (
          await database.select(database.vocabularyWords).get(),
          await database.select(database.outboxOperations).get(),
        );

        Future<
          ({
            String originalOwner,
            (List<VocabularyWord>, List<OutboxOperation>) rows,
          })
        >
        seed() async {
          final category = await vocabulary.createCategory('ชุดคำ A');
          final word = await vocabulary.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: privateWord,
              meaning: privateMeaning,
              partOfSpeech: 'noun',
            ),
          );
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: nextOwner,
                  createdAtUtcMs: nowUtc.millisecondsSinceEpoch,
                  isActive: const Value(false),
                ),
              );
          await activate(nextOwner);
          final otherCategory = await vocabulary.createCategory('ชุดคำ B');
          await vocabulary.createWord(
            CreateWordCommand(
              categoryId: otherCategory.id,
              spelling: 'synthetic-private-b',
              meaning: 'คำของบัญชีใหม่',
              partOfSpeech: 'noun',
            ),
          );
          await activate(word.ownerId);
          return (originalOwner: word.ownerId, rows: await snapshot());
        }

        final seeded = (await tester.runAsync(
          () => seed().timeout(const Duration(seconds: 5)),
        ))!;

        await pumpCategories(tester);
        await pumpUntilFound(tester, find.text('ชุดคำ A'));
        await tester.tap(find.text('ชุดคำ A'));
        await pumpUntilFound(tester, find.text(privateWord));
        await finishRouteTransition(tester);
        await tester.tap(find.byTooltip('จัดการคำนี้ $privateWord'));
        final save = find.widgetWithText(FilledButton, saveLabel);
        await pumpUntilFound(tester, save.hitTestable());
        final sheetText = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(privateWord),
        );
        expect(sheetText, findsOneWidget);
        expect(find.text(privateMeaning), findsWidgets);
        final lateTap = tester.widget<FilledButton>(save).onPressed!;

        var switched = false;
        final switching = activate(
          nextOwner,
        ).whenComplete(() => switched = true);
        unawaited(switching.then<void>((_) {}, onError: (Object _) {}));

        for (var index = 0; index < 50; index++) {
          await tester.pump(const Duration(milliseconds: 20));
          if (switched &&
              find.text(privateWord).evaluate().isEmpty &&
              find.text(privateMeaning).evaluate().isEmpty &&
              save.evaluate().isEmpty) {
            break;
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(switched, isTrue, reason: 'the active owner switch must finish');
        await switching;
        await finishRouteTransition(tester);
        expect(find.text(privateWord), findsNothing);
        expect(find.text(privateMeaning), findsNothing);
        expect(save, findsNothing);

        final visibleBeforeTap = tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data)
            .whereType<String>()
            .toList();
        lateTap();
        await finishRouteTransition(tester);
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .map((widget) => widget.data)
              .whereType<String>()
              .toList(),
          visibleBeforeTap,
        );
        final after = (await tester.runAsync(
          () => snapshot().timeout(const Duration(seconds: 5)),
        ))!;
        expect(after.$1, seeded.rows.$1);
        expect(after.$2, seeded.rows.$2);
        expect(
          after.$1.map((row) => row.ownerId),
          unorderedEquals([seeded.originalOwner, nextOwner]),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        var closed = false;
        final closing = database.close().whenComplete(() => closed = true);
        unawaited(closing.then<void>((_) {}, onError: (Object _) {}));
        for (var index = 0; index < 80 && !closed; index++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(
          closed,
          isTrue,
          reason: 'database close must finish after unmount',
        );
        await closing;
        await tester.pump();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

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
      expect(find.byTooltip('ตัวเลือกชุด Travel'), findsOneWidget);
      await tester.tap(find.text('Travel'));
      await pumpUntilFound(tester, find.byKey(const ValueKey('add-word')));
      await finishRouteTransition(tester);
      expect(find.byKey(const ValueKey('source-practice')), findsOneWidget);
      expect(find.text('ฝึกจากไฟล์'), findsOneWidget);
      expect(find.byKey(const ValueKey('import-words')), findsNothing);
      expect(find.text('เพิ่มคำ'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('source-practice')),
          matching: find.byType(Wrap),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('source-practice')));
      await pumpUntilFound(tester, find.text('ฝึกจากไฟล์ในเครื่อง'));
      await tester.tap(find.byTooltip('Back').last);
      await pumpUntilFound(tester, find.byKey(const ValueKey('add-word')));
      await finishRouteTransition(tester);

      await tester.tap(find.byKey(const ValueKey('add-word')).last);
      await pumpUntilFound(tester, find.text('พิมพ์คำศัพท์'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('พิมพ์คำศัพท์'));
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

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpCategories(tester);
      await pumpUntilFound(tester, find.text('Travel'));

      expect(find.text('Travel'), findsOneWidget);
      await tester.tap(find.text('Travel'));
      await pumpUntilFound(tester, find.text('station'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(database.close);
      await tester.pump(const Duration(milliseconds: 1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
