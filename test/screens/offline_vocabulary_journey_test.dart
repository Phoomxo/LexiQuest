import 'dart:io';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/screens/add_vocab_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/screens/add_multiple_words_screen.dart';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/data/drift_offline_content_repository.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'offline-vocabulary-guest');
}

void main() {
  late AppDatabase database;
  late AppDependencies dependencies;
  late DateTime nowUtc;
  late int idCounter;
  late Directory offlineDirectory;
  late OfflineContentManager offlineContent;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    offlineDirectory = await Directory.systemTemp.createTemp(
      'lexiquest-offline-vocabulary-',
    );
    addTearDown(() async {
      if (await offlineDirectory.exists()) {
        await offlineDirectory.delete(recursive: true);
      }
    });
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
    final research = InertResearchDependencies(database);
    offlineContent = VerifiedOfflineContentManager(
      repository: DriftOfflineContentRepository(database),
      adapters: const <OfflineContentDownloadAdapter>[],
      removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
      rootDirectory: () async => offlineDirectory,
      nowUtc: () => nowUtc,
    );
    dependencies = AppDependencies(
      initialRoute: AppRoute.home,
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSessionService(),
      quest: testQuestUseCases(),
      experiments: research.experiments,
      consents: research.consents,
      experimentAssignments: research.experimentAssignments,
      assignedLearningEventContext: research.assignedLearningEventContext,
      evidencePolicyRolloutModeProvider:
          research.evidencePolicyRolloutModeProvider,
      database: database,
      localOwners: owners,
      vocabulary: vocabulary,
      vocabularyImporter: ImportVocabulary(
        owners: owners,
        repository: DriftVocabularyImportRepository(database),
        generateId: () => 'import-${++idCounter}',
        nowUtc: () => nowUtc,
      ),
      offlineContent: offlineContent,
    );
  });

  Future<void> pumpCategories(
    WidgetTester tester, {
    ThemeData? theme,
    double textScale = 1,
  }) {
    return tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: CategoriesPage(),
        ),
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

  testWidgets('category draft survives late optional AI attachment', (
    tester,
  ) async {
    final active = await tester.runAsync(
      dependencies.vocabulary!.owners.getOrCreateActiveOwner,
    );
    String? owner;
    final registry = MenuActionRegistry(currentOwner: () => owner);
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: AppDependenciesScope(
          dependencies: dependencies,
          child: const MaterialApp(home: CategoriesPage()),
        ),
      ),
    );
    await pumpUntilFound(
      tester,
      find.text('ยังไม่มีหมวดหมู่\nเพิ่มหมวดหมู่เพื่อเริ่มเก็บคำศัพท์'),
    );
    await tester.tap(find.byKey(const ValueKey('add-category')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'ของใช้',
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(registry.snapshot()['actions'], isEmpty);
    owner = active!.id;
    final actions = registry.snapshot()['actions'] as List;
    expect(
      actions.map((entry) => (entry as Map)['id']),
      containsAll(['vocabulary/category-fill', 'vocabulary/category-save']),
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('category-name-field')))
          .controller!
          .text,
      'ของใช้',
    );
    owner = 'other-owner';
    expect(registry.snapshot()['actions'], isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(database.close);
  });

  testWidgets(
    'MCP category form persists once and manual draft survives disconnect',
    (tester) async {
      final vocabulary = dependencies.vocabulary!;
      final active = await tester.runAsync(
        vocabulary.owners.getOrCreateActiveOwner,
      );
      String? owner = active!.id;
      final registry = MenuActionRegistry(currentOwner: () => owner);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: AppDependenciesScope(
            dependencies: dependencies,
            child: const MaterialApp(home: CategoriesPage()),
          ),
        ),
      );
      await pumpUntilFound(tester, find.byKey(const ValueKey('add-category')));
      var request = 0;
      Future<Map<String, Object?>> invoke(
        String id, {
        Map<String, String> values = const {},
      }) async {
        final result = await tester.runAsync(
          () => registry.execute(
            id: id,
            owner: owner!,
            revision: registry.snapshot()['revision'] as int,
            requestId: 'category-${request++}',
            values: values,
          ),
        );
        await tester.pumpAndSettle();
        return result!;
      }

      await invoke('vocabulary/add-category');
      expect((await invoke('vocabulary/category-save'))['status'], 'invalid');
      final revision = registry.snapshot()['revision'] as int;
      expect(
        (await invoke(
          'vocabulary/category-fill',
          values: {'name': '  ของใช้   รอบตัว  '},
        ))['status'],
        'filled',
      );
      expect(
        await tester.runAsync(
          () => database.select(database.vocabularyCategories).get(),
        ),
        isEmpty,
      );
      expect(
        (await registry.execute(
          id: 'vocabulary/category-save',
          owner: owner,
          revision: revision,
          requestId: 'old-category-form',
        ))['status'],
        'stale',
      );
      final savedRevision = registry.snapshot()['revision'] as int;
      final saving = registry.execute(
        id: 'vocabulary/category-save',
        owner: owner,
        revision: savedRevision,
        requestId: 'save-category-once',
      );
      Map<String, Object?>? saved;
      saving.then((value) => saved = value);
      for (var i = 0; i < 50 && saved == null; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(saved, isNotNull, reason: 'Persist and read-back must finish');
      await tester.pumpAndSettle();
      expect(saved!['status'], 'saved');
      expect((saved!['record'] as Map)['name'], 'ของใช้ รอบตัว');
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        await registry.execute(
          id: 'vocabulary/category-save',
          owner: owner,
          revision: savedRevision,
          requestId: 'save-category-once',
        ),
        saved,
      );
      final rows = await tester.runAsync(
        () => database.select(database.vocabularyCategories).get(),
      );
      expect(rows, hasLength(1));
      expect(rows!.single.name, 'ของใช้ รอบตัว');
      expect(rows.single.ownerId, active.id);
      await invoke('vocabulary/add-category');
      await invoke(
        'vocabulary/category-fill',
        values: {'name': 'ของใช้ รอบตัว'},
      );
      expect((await invoke('vocabulary/category-save'))['status'], 'duplicate');
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('category-name-field')),
        'การเดินทาง',
      );
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('category-name-field')),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      tester.testTextInput.hide();
      owner = null;
      expect(registry.snapshot()['actions'], isEmpty);
      await tester.tap(find.byKey(const ValueKey('save-category')));
      await pumpUntilFound(tester, find.widgetWithText(ListTile, 'การเดินทาง'));
      for (
        var i = 0;
        i < 50 && find.byType(AlertDialog).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'Manual save must finish verified read-back',
      );
      await tester.pumpAndSettle();
      final after = await tester.runAsync(
        () => database.select(database.vocabularyCategories).get(),
      );
      expect(after, hasLength(2));
      expect(after!.every((row) => row.ownerId == active.id), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(database.close);
    },
  );

  testWidgets('word draft survives late optional AI attachment', (
    tester,
  ) async {
    final category = await tester.runAsync(
      () => dependencies.vocabulary!.createCategory('Late AI'),
    );
    String? owner;
    final registry = MenuActionRegistry(currentOwner: () => owner);
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(home: AddWordScreen(categoryId: category!.id)),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('word-field')), 'book');
    await tester.pump();
    final editable = find.descendant(
      of: find.byKey(const ValueKey('word-field')),
      matching: find.byType(EditableText),
    );
    final focus = tester.widget<EditableText>(editable).focusNode;
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(registry.snapshot()['actions'], isEmpty);
    owner = category.ownerId;
    final actions = registry.snapshot()['actions'] as List;
    expect(
      actions.map((entry) => (entry as Map)['id']),
      containsAll(['vocabulary/word-fill', 'vocabulary/word-save']),
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('word-field')))
          .controller!
          .text,
      'book',
    );
    expect(tester.widget<EditableText>(editable).focusNode, same(focus));
    expect(focus.hasFocus, isTrue);
    owner = 'other-owner';
    expect(registry.snapshot()['actions'], isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(database.close);
  });

  testWidgets('MCP word delete requires exact target and verifies tombstone', (
    tester,
  ) async {
    final vocabulary = dependencies.vocabulary!;
    final category = await tester.runAsync(
      () => vocabulary.createCategory('Delete fixture'),
    );
    final word = await tester.runAsync(
      () => vocabulary.createWord(
        CreateWordCommand(
          categoryId: category!.id,
          spelling: 'book',
          meaning: 'หนังสือ',
          partOfSpeech: 'noun',
        ),
      ),
    );
    var owner = category!.ownerId;
    final registry = MenuActionRegistry(currentOwner: () => owner);
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(
            home: VocabListScreen(
              categoryId: category.id,
              categoryName: category.name,
            ),
          ),
        ),
      ),
    );
    await pumpUntilFound(tester, find.widgetWithText(ListTile, 'book'));
    var request = 0;
    Future<Map<String, Object?>> invoke(
      String id, {
      Map<String, String> values = const {},
    }) async {
      Map<String, Object?>? result;
      registry
          .execute(
            id: id,
            owner: owner,
            revision: registry.snapshot()['revision'] as int,
            requestId: 'delete-${request++}',
            values: values,
          )
          .then((value) => result = value);
      for (var i = 0; i < 50 && result == null; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(
        result,
        isNotNull,
        reason: 'Delete command must finish within bounded frame/IO pumps',
      );
      await tester.pumpAndSettle();
      return result!;
    }

    expect((await invoke('vocabulary/word/0/delete'))['status'], 'invoked');
    expect(find.byType(AlertDialog), findsOneWidget);
    owner = 'other-owner';
    expect(registry.snapshot()['actions'], isEmpty);
    expect(registry.snapshot()['context'], isEmpty);
    owner = category.ownerId;

    expect(
      (await tester.runAsync(
        () => database.select(database.vocabularyWords).get(),
      ))!.single.isDeleted,
      isFalse,
    );
    expect(
      (await invoke(
        'vocabulary/word-delete-confirm',
        values: {'wordId': 'wrong-target'},
      ))['status'],
      'invalid',
    );
    await invoke('vocabulary/word-delete-cancel');
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      (await tester.runAsync(
        () => database.select(database.vocabularyWords).get(),
      ))!.single.isDeleted,
      isFalse,
    );
    await invoke('vocabulary/word/0/delete');
    expect(
      (await invoke(
        'vocabulary/word-delete-confirm',
        values: {'wordId': word!.id},
      ))['status'],
      'deleted',
    );
    final rows = await tester.runAsync(
      () => database.select(database.vocabularyWords).get(),
    );
    expect(rows, hasLength(1));
    expect(rows!.single.id, word.id);
    expect(rows.single.isDeleted, isTrue);
    expect(rows.single.ownerId, owner);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(database.close);
  });

  testWidgets(
    'MCP import previews without writing and verifies mixed outcomes',
    (tester) async {
      final category = await tester.runAsync(
        () => dependencies.vocabulary!.createCategory('Import fixture'),
      );
      final registry = MenuActionRegistry(
        currentOwner: () => category!.ownerId,
      );
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: AppDependenciesScope(
            dependencies: dependencies,
            child: MaterialApp(
              home: AddMultipleWordsScreen(
                categoryId: category!.id,
                categoryName: category.name,
              ),
            ),
          ),
        ),
      );
      var request = 0;
      Future<Map<String, Object?>> invoke(
        String id, {
        Map<String, String> values = const {},
      }) async {
        Map<String, Object?>? result;
        registry
            .execute(
              id: id,
              owner: category.ownerId,
              revision: registry.snapshot()['revision'] as int,
              requestId: 'import-${request++}',
              values: values,
            )
            .then((value) => result = value);
        for (var i = 0; i < 50 && result == null; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        expect(result, isNotNull);
        await tester.pumpAndSettle();
        return result!;
      }

      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      const rows = 'book,หนังสือ,noun\nbook,หนังสือ,noun\npen,,noun';
      expect(
        (await invoke(
          'vocabulary/import-fill',
          values: {'rows': rows},
        ))['status'],
        'filled',
      );
      final preview = await invoke('vocabulary/import-preview');
      expect(preview['status'], 'previewed');
      expect(preview['totalRows'], 3);
      expect(preview['validRows'], 2);
      expect(preview['databaseChecked'], isFalse);
      expect((preview['rejected'] as List).single, {
        'rowNumber': 3,
        'code': 'missingMeaning',
      });
      expect(
        await tester.runAsync(
          () => database.select(database.vocabularyWords).get(),
        ),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => database.select(database.vocabularyImports).get(),
        ),
        isEmpty,
      );
      final result = await invoke('vocabulary/import-save');
      expect(result['status'], 'saved');
      final record = result['record'] as Map;
      expect(record['accepted'], 1);
      expect(record['duplicates'], 1);
      expect((record['rejected'] as List).single, {
        'rowNumber': 3,
        'code': 'missingMeaning',
      });
      final stored = await tester.runAsync(
        () => database.select(database.vocabularyWords).get(),
      );
      expect(stored, hasLength(1));
      expect(stored!.single.meaning, 'หนังสือ');
      final imports = await tester.runAsync(
        () => database.select(database.vocabularyImports).get(),
      );
      expect(imports, hasLength(1));
      expect(imports!.single.id, record['importId']);
      expect((await invoke('vocabulary/import-save'))['status'], 'saved');
      expect(
        await tester.runAsync(
          () => database.select(database.vocabularyWords).get(),
        ),
        hasLength(1),
      );
      expect(
        await tester.runAsync(
          () => database.select(database.vocabularyImports).get(),
        ),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(database.close);
    },
  );

  testWidgets(
    'MCP fills Thai word, verifies persistence and does not replay a write',
    (tester) async {
      final vocabulary = dependencies.vocabulary!;
      final category = await tester.runAsync(
        () => vocabulary.createCategory('MCP test'),
      );
      var owner = category!.ownerId;
      final registry = MenuActionRegistry(currentOwner: () => owner);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: AppDependenciesScope(
            dependencies: dependencies,
            child: MaterialApp(home: AddWordScreen(categoryId: category.id)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var request = 0;
      Future<Map<String, Object?>> invoke(
        String id, {
        Map<String, String> values = const {},
      }) async {
        bool available() => (registry.snapshot()['actions'] as List).any(
          (entry) => (entry as Map)['id'] == id,
        );
        for (var i = 0; i < 50 && !available(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(
          available(),
          isTrue,
          reason: 'Local owner must admit the form tool',
        );
        final result = await tester.runAsync(
          () => registry.execute(
            id: id,
            owner: owner,
            revision: registry.snapshot()['revision'] as int,
            requestId: 'form-${request++}',
            values: values,
          ),
        );
        await tester.pumpAndSettle();
        return result!;
      }

      expect((await invoke('vocabulary/word-save'))['status'], 'invalid');
      await tester.tap(find.byKey(const ValueKey('word-field')));
      await tester.enterText(find.byKey(const ValueKey('word-field')), 'b');
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('word-field')),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
        reason:
            'Manual typing must not lose focus when refreshing MCP commands.',
      );
      tester.testTextInput.hide();
      final emptyRevision = registry.snapshot()['revision'] as int;
      final values = {
        'spelling': 'book',
        'meaning': 'หนังสือ',
        'partOfSpeech': 'noun',
        'cefrLevel': 'A1',
      };
      expect(
        (await invoke('vocabulary/word-fill', values: values))['status'],
        'filled',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('meaning-field')))
            .controller!
            .text,
        'หนังสือ',
      );
      expect(
        (await tester.runAsync(
          () => registry.execute(
            id: 'vocabulary/word-save',
            owner: owner,
            revision: emptyRevision,
            requestId: 'outdated-draft',
          ),
        ))!['status'],
        'stale',
      );
      final before = await tester.runAsync(
        () => database.select(database.vocabularyWords).get(),
      );
      expect(before, isEmpty);
      final revision = registry.snapshot()['revision'] as int;
      final saved = await tester.runAsync(
        () => registry.execute(
          id: 'vocabulary/word-save',
          owner: owner,
          revision: revision,
          requestId: 'persist',
        ),
      );
      await tester.pumpAndSettle();
      expect(saved!['status'], 'saved');
      expect((saved['record'] as Map)['meaning'], 'หนังสือ');
      final rows = await tester.runAsync(
        () => database.select(database.vocabularyWords).get(),
      );
      expect(rows, hasLength(1));
      expect(rows!.single.meaning, 'หนังสือ');
      expect(
        await registry.execute(
          id: 'vocabulary/word-save',
          owner: owner,
          revision: revision,
          requestId: 'persist',
        ),
        saved,
      );
      final repeated = await tester.runAsync(
        () => database.select(database.vocabularyWords).get(),
      );
      expect(repeated, hasLength(1));
      expect((await invoke('vocabulary/word-save'))['status'], 'duplicate');
      final savedWord = await tester.runAsync(
        () => vocabulary.readPinnedByIds([rows.single.id]),
      );
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: AppDependenciesScope(
            dependencies: dependencies,
            child: MaterialApp(
              home: AddWordScreen(
                key: const ValueKey('edit'),
                categoryId: category.id,
                word: savedWord!.single,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (await invoke(
          'vocabulary/word-fill',
          values: {...values, 'cefrLevel': 'X9'},
        ))['status'],
        'invalid',
      );
      expect(
        (await invoke(
          'vocabulary/word-fill',
          values: {...values, 'meaning': 'หนังสือเรียน'},
        ))['status'],
        'filled',
      );
      expect((await invoke('vocabulary/word-save'))['status'], 'saved');
      final edited = await tester.runAsync(
        () => database.select(database.vocabularyWords).get(),
      );
      expect(edited, hasLength(1));
      expect(edited!.single.meaning, 'หนังสือเรียน');
      expect(edited.single.localRevision, 2);
      owner = 'other-owner';
      expect(registry.snapshot()['actions'], isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(database.close);
    },
  );

  testWidgets(
    'word search distinguishes no matches from an empty category',
    (tester) async {
      final vocabulary = dependencies.vocabulary!;
      await tester.runAsync(() async {
        final category = await vocabulary.createCategory('Travel');
        for (final spelling in ['station', 'airport']) {
          await vocabulary.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: spelling,
              meaning: spelling == 'station' ? 'สถานี' : 'สนามบิน',
              partOfSpeech: 'noun',
            ),
          );
        }
      });
      await pumpCategories(tester);
      await pumpUntilFound(tester, find.text('Travel'));
      await tester.tap(find.text('Travel'));
      await finishRouteTransition(tester);
      await pumpUntilFound(tester, find.text('station'));
      expect(find.text('airport'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'unmatched query');
      await pumpUntilFound(tester, find.text('ไม่พบคำศัพท์ที่ตรงกับคำค้น'));
      expect(find.text('ยังไม่มีคำศัพท์ในหมวดนี้'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await pumpUntilFound(tester, find.text('station'));
      expect(find.text('airport'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(database.close);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'device regression: category form fits landscape keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(2226, 1080);
      tester.view.devicePixelRatio = 2.75;
      tester.view.padding = const FakeViewPadding(top: 77);
      tester.view.viewPadding = const FakeViewPadding(top: 77);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await pumpCategories(tester, theme: M3Theme.darkTheme);
      await pumpUntilFound(tester, find.textContaining('ยังไม่มีหมวดหมู่'));
      await tester.tap(find.byKey(const ValueKey('add-category')));
      await finishRouteTransition(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 550);
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      expect(tester.takeException(), isNull);
      final save = find.byKey(const ValueKey('save-category'));
      await tester.ensureVisible(save);
      expect(save.hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(database.close);
      await tester.pump(const Duration(milliseconds: 1));
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
      await tester.tap(find.text('Travel'));
      await pumpUntilFound(tester, find.byKey(const ValueKey('add-word')));
      await finishRouteTransition(tester);
      expect(find.text('ยังไม่มีคำศัพท์ในหมวดนี้'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add-word')));
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
      expect(
        await offlineContent.cleanupForDiskPressure(bytesToFree: 1024),
        0,
        reason: 'empty offline cleanup must not affect local vocabulary',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpCategories(tester);
      await pumpUntilFound(tester, find.text('Travel'));

      expect(find.text('Travel'), findsOneWidget);
      await tester.tap(find.text('Travel'));
      await pumpUntilFound(tester, find.text('station'));

      // A long list must leave its final row reachable above both FABs.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(() async {
        final category = await database
            .select(database.vocabularyCategories)
            .getSingle();
        for (var index = 0; index < 20; index++) {
          final spelling = 'word${index.toString().padLeft(2, '0')}';
          await database.customStatement(
            'INSERT INTO vocabulary_words '
            '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
            'normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) '
            "VALUES (?, ?, ?, ?, ?, 'คำทดสอบ', 'คำทดสอบ', 'noun', 1, 1)",
            <Object?>[
              'layout:$index',
              category.ownerId,
              category.id,
              spelling,
              spelling,
            ],
          );
        }
      });
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpCategories(tester, theme: M3Theme.darkTheme, textScale: 2);
      await pumpUntilFound(tester, find.text('Travel'));
      await tester.tap(find.text('Travel'));
      await finishRouteTransition(tester);
      await pumpUntilFound(tester, find.text('station'));
      await tester.scrollUntilVisible(
        find.text('word19'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      final lastRow = find.ancestor(
        of: find.text('word19'),
        matching: find.byType(ListTile),
      );
      final delete = find.descendant(
        of: lastRow,
        matching: find.byTooltip('ลบคำศัพท์'),
      );
      expect(
        tester.getBottomRight(lastRow).dy,
        lessThan(tester.getTopLeft(find.byTooltip('นำเข้าคำศัพท์')).dy),
      );
      expect(delete.hitTestable(), findsOneWidget);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text('ลบ “word19” (คำทดสอบ) หรือไม่'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(find.text('word19'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(database.close);
      await tester.pump(const Duration(milliseconds: 1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
