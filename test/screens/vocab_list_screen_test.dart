import 'dart:async';
import 'package:vocab_learning_app/features/vocabulary/application/cefr_practice_examples.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/packaged_starter_identity.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_import.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/add_multiple_words_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The shared asset Future must not retain an expired widget-test clock zone.
  setUpAll(() async {
    await CefrPracticeExamples.load();
  });
  late AppDatabase gateDatabase;
  late AppDependencies gateDependencies;
  setUp(() {
    gateDatabase = AppDatabase(NativeDatabase.memory());
    final research = InertResearchDependencies(gateDatabase);
    gateDependencies = AppDependencies(
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
      vocabulary: _vocabulary(_VocabularyRepository(const [])),
    );
  });
  tearDown(() => gateDatabase.close());
  Widget app({required Widget home}) => AppDependenciesScope(
    dependencies: gateDependencies,
    child: MaterialApp(home: home),
  );

  testWidgets(
    'MCP category menus open exact category and add dialog without mutation',
    (tester) async {
      final category = _category(readOnly: false);
      final vocabulary = _vocabulary(
        _VocabularyRepository(const [], categories: [category]),
      );
      final registry = MenuActionRegistry(
        currentOwner: () => _OwnerRepository.owner.id,
      );
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: app(home: CategoriesPage(vocabulary: vocabulary)),
        ),
      );
      await tester.pumpAndSettle();
      var request = 0;
      Future<void> invoke(String id) async {
        final result = await registry.execute(
          id: id,
          owner: _OwnerRepository.owner.id,
          revision: registry.snapshot()['revision'] as int,
          requestId: 'vocab-${request++}',
        );
        expect(result['status'], 'invoked');
        await tester.pumpAndSettle();
      }

      await invoke('vocabulary/add-category');
      expect(find.byType(AlertDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      await invoke('vocabulary/category/0');
      expect(find.byType(VocabListScreen), findsOneWidget);
      expect(
        tester.widget<VocabListScreen>(find.byType(VocabListScreen)).categoryId,
        category.id,
      );
      await invoke('vocabulary/add-word');
      expect(find.byKey(const ValueKey('word-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-word')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('MCP hides old owner category labels and callbacks immediately', (
    tester,
  ) async {
    var owner = _OwnerRepository.owner.id;
    final registry = MenuActionRegistry(currentOwner: () => owner);
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: app(
          home: CategoriesPage(
            vocabulary: _vocabulary(
              _VocabularyRepository(
                const [],
                categories: [_category(readOnly: false)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(registry.snapshot().toString(), contains('My words'));
    owner = 'owner:replacement';
    final fresh = registry.snapshot();
    expect(fresh.toString(), isNot(contains('My words')));
    final result = await registry.execute(
      id: 'vocabulary/category/0',
      owner: owner,
      revision: fresh['revision'] as int,
      requestId: 'changed-owner',
    );
    expect(result['status'], 'unavailable');
    expect(find.byType(VocabListScreen), findsNothing);
  });

  testWidgets(
    'MCP rejects a category index snapshot after its record is replaced',
    (tester) async {
      final streams = _CategoryStreams();
      addTearDown(streams.close);
      final registry = MenuActionRegistry(
        currentOwner: () => _OwnerRepository.owner.id,
      );
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: app(
            home: CategoriesPage(
              vocabulary: _vocabulary(
                _VocabularyRepository(const [], categoryStream: streams.watch),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      streams.controllers.single.add([_category(readOnly: false)]);
      await tester.pumpAndSettle();
      expect(
        registry.snapshot().toString(),
        contains('เปิดหมวดส่วนตัว My words'),
      );
      final previous = registry.snapshot()['revision'] as int;
      streams.controllers.single.add([_category(readOnly: true)]);
      await tester.pumpAndSettle();
      expect(
        registry.snapshot().toString(),
        contains('เปิดหมวดอ่านอย่างเดียว Everyday English'),
      );
      final stale = await registry.execute(
        id: 'vocabulary/category/0',
        owner: _OwnerRepository.owner.id,
        revision: previous,
        requestId: 'old-category',
      );
      expect(stale['status'], 'stale');
      expect(find.byType(VocabListScreen), findsNothing);
      final fresh = await registry.execute(
        id: 'vocabulary/category/0',
        owner: _OwnerRepository.owner.id,
        revision: registry.snapshot()['revision'] as int,
        requestId: 'new-category',
      );
      expect(fresh['status'], 'invoked');
      await tester.pumpAndSettle();
      expect(
        tester.widget<VocabListScreen>(find.byType(VocabListScreen)).categoryId,
        PackagedStarterIdentity.categoryId,
      );
    },
  );

  for (final readOnly in [false, true]) {
    testWidgets('MCP word routes preserve read-only policy $readOnly', (
      tester,
    ) async {
      final category = _category(readOnly: readOnly);
      final word = _word(
        id: 'word:route',
        ownerId: category.ownerId,
        categoryId: category.id,
        cefrLevel: 'A1',
      );
      final registry = MenuActionRegistry(
        currentOwner: () => _OwnerRepository.owner.id,
      );
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: app(
            home: VocabListScreen(
              categoryId: category.id,
              categoryName: category.name,
              vocabulary: _vocabulary(_VocabularyRepository([word])),
              importer: _importer(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var request = 0;
      Future<void> invoke(String id, String status) async {
        final result = await registry.execute(
          id: id,
          owner: _OwnerRepository.owner.id,
          revision: registry.snapshot()['revision'] as int,
          requestId: 'word-${request++}',
        );
        expect(result['status'], status);
        await tester.pumpAndSettle();
      }

      await invoke('vocabulary/word/0/examples', 'invoked');
      await tester.runAsync(() async {
        final catalog = await CefrPracticeExamples.load();
        expect(catalog.editorialLoadFailed, isFalse);
        expect(
          CefrPracticeExamples.resolve(
            catalog,
            spelling: 'book',
            meaning: 'หนังสือ',
            partOfSpeech: 'noun',
            cefrLevel: 'A1',
          ),
          isNotNull,
        );
      });
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cefr-practice-example')),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await invoke(
        'vocabulary/word/0/edit',
        readOnly ? 'unavailable' : 'invoked',
      );
      if (!readOnly) {
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('word-field')))
              .controller!
              .text,
          'book',
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await invoke(
        'vocabulary/word/0/delete',
        readOnly ? 'unavailable' : 'invoked',
      );
      if (!readOnly) {
        expect(find.byType(AlertDialog), findsOneWidget);
        await invoke('vocabulary/word-delete-cancel', 'invoked');
        expect(find.byType(AlertDialog), findsNothing);
      }
      await invoke('vocabulary/add-word', readOnly ? 'unavailable' : 'invoked');
      if (!readOnly) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await invoke('vocabulary/import', readOnly ? 'unavailable' : 'invoked');
      if (!readOnly) {
        expect(
          tester
              .widget<AddMultipleWordsScreen>(
                find.byType(AddMultipleWordsScreen),
              )
              .categoryId,
          category.id,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'category retry replaces failed streams and ignores retired data',
    (tester) async {
      final streams = _CategoryStreams();
      addTearDown(streams.close);
      final vocabulary = _vocabulary(
        _VocabularyRepository(const [], categoryStream: streams.watch),
      );
      await tester.pumpWidget(
        app(home: CategoriesPage(vocabulary: vocabulary)),
      );
      await tester.pump();
      expect(streams.controllers, hasLength(1));

      for (var attempt = 0; attempt < 2; attempt++) {
        streams.controllers[attempt].addError(
          StateError('synthetic stream error'),
        );
        await tester.pumpAndSettle();
        expect(find.text('ลองใหม่'), findsOneWidget);
        await tester.tap(find.text('ลองใหม่'));
        await tester.pump();
        expect(streams.controllers, hasLength(attempt + 2));
        expect(streams.cancelled, contains(attempt));
      }
      streams.controllers.last.add([_category(readOnly: false)]);
      await tester.pumpAndSettle();
      expect(find.text('My words'), findsOneWidget);
      expect(find.text('ลองใหม่'), findsNothing);
      streams.controllers.first.add([_category(readOnly: true)]);
      await tester.pumpAndSettle();
      expect(find.text('Everyday English'), findsNothing);
      expect(find.text('My words'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(streams.cancelled, containsAll([0, 1, 2]));
      expect(tester.takeException(), isNull);
    },
  );

  for (final replaceDependency in [false, true]) {
    testWidgets(
      'category owner change resubscribes replaceDependency=$replaceDependency',
      (tester) async {
        final streams = _CategoryStreams();
        addTearDown(streams.close);
        final owners = _OwnerRepository();
        final repository = _VocabularyRepository(
          const [],
          categoryStream: streams.watch,
        );
        final vocabulary = _vocabulary(repository, owners: owners);
        await tester.pumpWidget(
          app(home: CategoriesPage(vocabulary: vocabulary)),
        );
        await tester.pump();
        streams.controllers.single.add([_category(readOnly: false)]);
        await tester.pumpAndSettle();
        expect(find.text('My words'), findsOneWidget);
        owners.active = LocalOwner(
          id: 'owner:replacement',
          createdAtUtc: DateTime.utc(2026, 9, 9),
        );
        if (replaceDependency) {
          await tester.pumpWidget(
            app(
              home: CategoriesPage(
                vocabulary: _vocabulary(repository, owners: owners),
              ),
            ),
          );
        } else {
          streams.controllers.single.addError(StateError('synthetic retry'));
          await tester.pumpAndSettle();
          expect(find.text('ลองใหม่'), findsOneWidget);
          await tester.tap(find.text('ลองใหม่'));
        }
        await tester.pump();
        expect(streams.requestedOwners, [
          _OwnerRepository.owner.id,
          'owner:replacement',
        ]);
        expect(streams.cancelled, contains(0));
        final fresh = VocabularyCategory(
          id: 'category:replacement',
          ownerId: 'owner:replacement',
          name: 'Replacement words',
          normalizedName: 'replacement words',
          sortOrder: 0,
          localRevision: 1,
          isDeleted: false,
          createdAtUtc: DateTime.utc(2026, 9, 9),
          updatedAtUtc: DateTime.utc(2026, 9, 9),
        );
        streams.controllers.last.add([fresh]);
        await tester.pumpAndSettle();
        streams.controllers.first.add([_category(readOnly: false)]);
        await tester.pumpAndSettle();
        expect(find.text('Replacement words'), findsOneWidget);
        expect(find.text('My words'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(streams.cancelled, containsAll([0, 1]));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'packaged starter category stays navigable without a delete action',
    (tester) async {
      final repository = _VocabularyRepository(
        const [],
        categories: [_category(readOnly: true)],
      );

      await tester.pumpWidget(
        app(home: CategoriesPage(vocabulary: _vocabulary(repository))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Everyday English'), findsOneWidget);
      expect(find.byTooltip('ลบหมวดหมู่'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'Everyday English'));
      await tester.pumpAndSettle();
      expect(find.byType(VocabListScreen), findsOneWidget);
    },
  );

  testWidgets('personal category keeps its delete action', (tester) async {
    final repository = _VocabularyRepository(
      const [],
      categories: [_category(readOnly: false)],
    );

    await tester.pumpWidget(
      app(home: CategoriesPage(vocabulary: _vocabulary(repository))),
    );
    await tester.pumpAndSettle();

    expect(find.text('My words'), findsOneWidget);
    expect(find.byTooltip('ลบหมวดหมู่'), findsOneWidget);
  });

  testWidgets(
    'packaged starter catalog exposes learning content without mutation actions',
    (tester) async {
      final repository = _VocabularyRepository([
        _word(
          id: 'word:starter-book',
          ownerId: PackagedStarterIdentity.ownerId,
          categoryId: PackagedStarterIdentity.categoryId,
        ),
      ]);

      await tester.pumpWidget(
        app(
          home: VocabListScreen(
            categoryId: PackagedStarterIdentity.categoryId,
            categoryName: 'Everyday English',
            vocabulary: _vocabulary(repository),
            importer: _importer(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('book'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('add-word')), findsNothing);
      expect(find.byTooltip('นำเข้าคำศัพท์'), findsNothing);
      expect(find.byTooltip('ลบคำศัพท์'), findsNothing);
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'book')).onTap,
        isNull,
        reason: 'Reviewed starter words must not open an edit route.',
      );
    },
  );

  testWidgets('personal vocabulary keeps its mutation actions', (tester) async {
    final repository = _VocabularyRepository([
      _word(
        id: 'word:personal-book',
        ownerId: _OwnerRepository.owner.id,
        categoryId: 'category:personal',
      ),
    ]);

    await tester.pumpWidget(
      app(
        home: VocabListScreen(
          categoryId: 'category:personal',
          categoryName: 'My words',
          vocabulary: _vocabulary(repository),
          importer: _importer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('add-word')), findsOneWidget);
    expect(find.byTooltip('นำเข้าคำศัพท์'), findsOneWidget);
    expect(find.byTooltip('ลบคำศัพท์'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'book')).onTap,
      isNotNull,
    );
  });

  testWidgets(
    'CEFR example page is readable without modifying the saved word',
    (tester) async {
      final word = _word(
        id: 'word:example-book',
        ownerId: _OwnerRepository.owner.id,
        categoryId: 'category:personal',
        cefrLevel: 'A1',
      );
      final repository = _VocabularyRepository([word]);
      await tester.pumpWidget(
        app(
          home: VocabListScreen(
            categoryId: 'category:personal',
            categoryName: 'My words',
            vocabulary: _vocabulary(repository),
            importer: _importer(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('ดูตัวอย่างการใช้'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await CefrPracticeExamples.load();
      });
      await tester.pumpAndSettle();
      expect(find.text('ตัวอย่างการใช้คำ'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cefr-practice-example')),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repository.words.single, same(word));
      expect(find.byTooltip('ลบคำศัพท์'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

VocabularyUseCases _vocabulary(
  _VocabularyRepository repository, {
  LocalOwnerRepository? owners,
}) => VocabularyUseCases(
  owners: owners ?? _OwnerRepository(),
  vocabulary: repository,
  generateId: () => 'unused',
  nowUtc: () => DateTime.utc(2026, 9, 8),
);

ImportVocabulary _importer() => ImportVocabulary(
  owners: _OwnerRepository(),
  repository: _ImportRepository(),
  generateId: () => 'unused',
  nowUtc: () => DateTime.utc(2026, 9, 8),
);

VocabularyWord _word({
  required String id,
  required String ownerId,
  required String categoryId,
  String? cefrLevel,
}) => VocabularyWord(
  id: id,
  ownerId: ownerId,
  categoryId: categoryId,
  spelling: 'book',
  normalizedSpelling: 'book',
  meaning: 'หนังสือ',
  normalizedMeaning: 'หนังสือ',
  partOfSpeech: 'noun',
  cefrLevel: cefrLevel,
  source: 'fixture',
  isGlobal: false,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026, 9, 8),
  updatedAtUtc: DateTime.utc(2026, 9, 8),
);

VocabularyCategory _category({required bool readOnly}) => VocabularyCategory(
  id: readOnly ? PackagedStarterIdentity.categoryId : 'category:personal',
  ownerId: readOnly
      ? PackagedStarterIdentity.ownerId
      : _OwnerRepository.owner.id,
  name: readOnly ? 'Everyday English' : 'My words',
  normalizedName: readOnly ? 'everyday english' : 'my words',
  sortOrder: 0,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026, 9, 8),
  updatedAtUtc: DateTime.utc(2026, 9, 8),
);

final class _OwnerRepository implements LocalOwnerRepository {
  LocalOwner? active;
  static final owner = LocalOwner(
    id: 'local:vocab-list-test',
    createdAtUtc: DateTime.utc(2026, 9, 8),
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => active ?? owner;

  @override
  Future<LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async => owner;
}

final class _VocabularyRepository implements VocabularyRepository {
  _VocabularyRepository(
    this.words, {
    this.categories = const [],
    this.categoryStream,
  });

  final List<VocabularyWord> words;
  final List<VocabularyCategory> categories;
  final Stream<List<VocabularyCategory>> Function(String)? categoryStream;

  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) =>
      Stream.value(words);

  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) =>
      categoryStream?.call(ownerId) ?? Stream.value(categories);

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) async => words;

  @override
  Future<List<VocabularyWord>> readPinnedByIds(
    Iterable<String> wordIds,
  ) async => words;

  @override
  Future<VocabularyCategory> createCategory(VocabularyCategory category) =>
      throw UnimplementedError();

  @override
  Future<VocabularyCategory> renameCategory({
    required String ownerId,
    required String categoryId,
    required String name,
    required String normalizedName,
    required DateTime nowUtc,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteCategory({
    required String ownerId,
    required String categoryId,
    required DateTime nowUtc,
  }) => throw UnimplementedError();

  @override
  Future<VocabularyWord> createWord(VocabularyWord word) =>
      throw UnimplementedError();

  @override
  Future<VocabularyWord> updateWord(VocabularyWord word) =>
      throw UnimplementedError();

  @override
  Future<void> deleteWord({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
  }) => throw UnimplementedError();
}

final class _CategoryStreams {
  final requestedOwners = <String>[];
  final controllers = <StreamController<List<VocabularyCategory>>>[];
  final cancelled = <int>[];

  Stream<List<VocabularyCategory>> watch(String ownerId) {
    final index = controllers.length;
    requestedOwners.add(ownerId);
    final controller = StreamController<List<VocabularyCategory>>.broadcast(
      onCancel: () => cancelled.add(index),
    );
    controllers.add(controller);
    return controller.stream;
  }

  Future<void> close() async {
    for (final controller in controllers) {
      await controller.close();
    }
  }
}

final class _ImportRepository implements VocabularyImportRepository {
  @override
  Future<VocabularyImportResult> persist(
    PreparedVocabularyImport import, {
    required bool Function() isCancelled,
  }) => throw UnimplementedError();
}

final class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'vocab-gate-fixture');
}
