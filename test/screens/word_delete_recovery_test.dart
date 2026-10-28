import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'dart:async';
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

  for (final boundary in [
    'duplicate',
    'cover',
    'tab',
    'lifecycle',
    'replacement',
    'pop',
    'owner',
    'word',
  ]) {
    testWidgets('AX retained delete entry rejects $boundary', (tester) async {
      final category = _category(readOnly: false);
      final target = _word(
        id: 'target',
        ownerId: category.ownerId,
        categoryId: category.id,
      );
      final repository = _VocabularyRepository(
        [target],
        categories: [category],
      );
      final owners = _OwnerRepository();
      var vocabulary = _vocabulary(repository, owners: owners);
      var visible = true;
      late StateSetter update;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: gateDependencies,
          child: MaterialApp(
            navigatorKey: navigator,
            home: StatefulBuilder(
              builder: (context, set) {
                update = set;
                return TickerMode(
                  enabled: visible,
                  child: VocabListScreen(
                    vocabulary: vocabulary,
                    categoryId: category.id,
                    categoryName: category.name,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .onPressed!;
      if (boundary == 'duplicate') {
        entry();
        entry();
      }
      if (boundary == 'cover') {
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
        await tester.pumpAndSettle();
        entry();
      }
      if (boundary == 'tab') {
        update(() => visible = false);
        await tester.pump();
        entry();
      }
      if (boundary == 'lifecycle') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        entry();
      }
      if (boundary == 'replacement') {
        update(
          () => vocabulary = _vocabulary(
            _VocabularyRepository([target], categories: [category]),
          ),
        );
        await tester.pumpAndSettle();
        entry();
      }
      if (boundary == 'pop') {
        await tester.pumpWidget(const SizedBox());
        entry();
      }
      if (boundary == 'owner') {
        owners.active = LocalOwner(
          id: 'other',
          createdAtUtc: DateTime.utc(2026),
        );
        entry();
      }
      if (boundary == 'word') {
        repository.words.clear();
        entry();
      }
      await tester.pumpAndSettle();
      expect(
        find.byType(AlertDialog, skipOffstage: false),
        boundary == 'duplicate' ? findsOneWidget : findsNothing,
      );
      expect(repository.deleted, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  for (final control in ['confirm', 'cancel', 'optional']) {
    testWidgets('AX retained $control cannot act on covering route', (
      tester,
    ) async {
      final category = _category(readOnly: false);
      final target = _word(
        id: 'target',
        ownerId: category.ownerId,
        categoryId: category.id,
      );
      final repo = _VocabularyRepository([target], categories: [category]);
      await tester.pumpWidget(
        MenuActionScope(
          registry: MenuActionRegistry(currentOwner: () => category.ownerId),
          child: app(
            home: VocabListScreen(
              vocabulary: _vocabulary(repo),
              categoryId: category.id,
              categoryName: category.name,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
      await tester.pumpAndSettle();
      final confirm = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลบ'))
          .onPressed!;
      final cancel = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'ยกเลิก'))
          .onPressed!;
      final optional = tester
          .widget<MenuActionBinding>(
            find.byWidgetPredicate(
              (w) =>
                  w is MenuActionBinding &&
                  w.id == 'vocabulary/word-delete-confirm',
            ),
          )
          .onForm!;
      final nav = Navigator.of(tester.element(find.byType(AlertDialog)));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover')),
        ),
      );
      await tester.pumpAndSettle();
      if (control == 'confirm')
        confirm();
      else if (control == 'cancel')
        cancel();
      else
        await optional({'wordId': target.id});
      await tester.pumpAndSettle();
      expect(find.text('cover'), findsOneWidget);
      expect(repo.deleted, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'AX ordinary uncertain acknowledgement is truthful and never automatically repeats',
    (tester) async {
      final c = _category(readOnly: false);
      final w = _word(id: 'target', ownerId: c.ownerId, categoryId: c.id);
      final repo = _VocabularyRepository([w], categories: [c])
        ..deleteFailure = true;
      await tester.pumpWidget(
        app(
          home: VocabListScreen(
            vocabulary: _vocabulary(repo),
            categoryId: c.id,
            categoryName: c.name,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ยังยืนยันผลการลบไม่ได้'), findsOneWidget);
      expect(repo.deleted, [w.id]);
      await tester.pump(const Duration(seconds: 2));
      expect(repo.deleted, [w.id]);
    },
  );
  testWidgets(
    'AX owned confirmation remains usable and deletes only selected word',
    (tester) async {
      final c = _category(readOnly: false);
      final w = _word(id: 'target', ownerId: c.ownerId, categoryId: c.id);
      final other = _word(id: 'survivor', ownerId: c.ownerId, categoryId: c.id);
      final repo = _VocabularyRepository([w, other], categories: [c]);
      await tester.pumpWidget(
        app(
          home: VocabListScreen(
            vocabulary: _vocabulary(repo),
            categoryId: c.id,
            categoryName: c.name,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.delete_outline).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
      await tester.pumpAndSettle();
      expect(repo.deleted, [w.id]);
      expect(repo.words.map((w) => w.id), [other.id]);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  for (final boundary in [
    'cover-return',
    'tab',
    'lifecycle',
    'feature',
    'dependency',
    'category',
    'word',
    'owner',
    'dispose',
  ]) {
    testWidgets('AX current confirmation rejects changed $boundary', (
      tester,
    ) async {
      final c = _category(readOnly: false);
      final w = _word(id: 'target', ownerId: c.ownerId, categoryId: c.id);
      final repo = _VocabularyRepository([w], categories: [c]);
      final owners = _OwnerRepository();
      var useCases = _vocabulary(repo, owners: owners);
      var visible = true;
      late StateSetter update;
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: gateDependencies,
          child: MaterialApp(
            navigatorKey: nav,
            home: StatefulBuilder(
              builder: (_, set) {
                update = set;
                return TickerMode(
                  enabled: visible,
                  child: VocabListScreen(
                    vocabulary: useCases,
                    featureRegistry: features,
                    categoryId: c.id,
                    categoryName: c.name,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
      await tester.pumpAndSettle();
      final confirm = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลบ'))
          .onPressed!;
      if (boundary == 'cover-return') {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
        await tester.pumpAndSettle();
        nav.currentState!.pop();
        await tester.pumpAndSettle();
      }
      if (boundary == 'tab') {
        update(() => visible = false);
        await tester.pump();
        update(() => visible = true);
        await tester.pump();
      }
      if (boundary == 'lifecycle') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      }
      if (boundary == 'feature') {
        features.emergencyOff(Feature.vocabulary);
        features.clearOverride(Feature.vocabulary);
        await tester.pump();
      }
      if (boundary == 'dependency') {
        update(
          () => useCases = _vocabulary(
            _VocabularyRepository([w], categories: [c]),
          ),
        );
        await tester.pumpAndSettle();
      }
      if (boundary == 'category') repo.categories.clear();
      if (boundary == 'word')
        repo.words[0] = w.copyWith(localRevision: 2, meaning: 'changed');
      if (boundary == 'owner')
        owners.active = LocalOwner(
          id: 'other',
          createdAtUtc: DateTime.utc(2026),
        );
      if (boundary == 'dispose') await tester.pumpWidget(const SizedBox());
      confirm();
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);
      expect(tester.takeException(), isNull);
      if (boundary == 'owner')
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('book', findRichText: true),
          ),
          findsNothing,
        );
    });
  }
  testWidgets(
    'AX explicit confirm waits initial owner read and duplicates commit once',
    (tester) async {
      final c = _category(readOnly: false);
      final w = _word(id: 'target', ownerId: c.ownerId, categoryId: c.id);
      final repo = _VocabularyRepository([w], categories: [c]);
      final pending = Completer<LocalOwner>();
      final owners = _OwnerRepository()
        ..pauseAt = 3
        ..pending = pending;
      await tester.pumpWidget(
        app(
          home: VocabListScreen(
            vocabulary: _vocabulary(repo, owners: owners),
            categoryId: c.id,
            categoryName: c.name,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      final confirm = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลบ'))
          .onPressed!;
      confirm();
      confirm();
      await tester.pump();
      expect(repo.deleted, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      pending.complete(_OwnerRepository.owner);
      await tester.pumpAndSettle();
      expect(repo.deleted, [w.id]);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('AX failed owner read offers explicit Thai retry before delete', (
    tester,
  ) async {
    final c = _category(readOnly: false);
    final w = _word(id: 'target', ownerId: c.ownerId, categoryId: c.id);
    final repo = _VocabularyRepository([w], categories: [c]);
    final owners = _OwnerRepository();
    await tester.pumpWidget(
      app(
        home: VocabListScreen(
          vocabulary: _vocabulary(repo, owners: owners),
          categoryId: c.id,
          categoryName: c.name,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
    await tester.pumpAndSettle();
    owners.failing = true;
    await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
    expect(find.text('ลองใหม่'), findsOneWidget);
    owners.failing = false;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
    await tester.pumpAndSettle();
    expect(repo.deleted, [w.id]);
  });

  for (final boundary in ['cover', 'lifecycle']) {
    testWidgets(
      'AX canonical delete rolls back after outbox write on $boundary',
      (tester) async {
        final pause = _WritePause('outbox_operations');
        final db = AppDatabase(NativeDatabase.memory().interceptWith(pause));
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'real-owner',
          nowUtc: () => DateTime.utc(2026),
        );
        var nextId = 0;
        final useCases = VocabularyUseCases(
          owners: owners,
          vocabulary: DriftVocabularyRepository(db),
          generateId: () => 'real-${nextId++}',
          nowUtc: () => DateTime.utc(2026),
        );
        final c = await useCases.createCategory('Private');
        final w = await useCases.createWord(
          CreateWordCommand(
            categoryId: c.id,
            spelling: 'private-target',
            meaning: 'หนังสือ',
            partOfSpeech: 'noun',
          ),
        );
        final before = await db.select(db.outboxOperations).get();
        await tester.pumpWidget(
          app(
            home: VocabListScreen(
              vocabulary: useCases,
              categoryId: c.id,
              categoryName: c.name,
            ),
          ),
        );
        await _pumps(tester);
        expect(find.text('private-target'), findsOneWidget);
        await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
        await _pumps(tester);
        final navigator = Navigator.of(
          tester.element(find.byType(AlertDialog)),
        );
        pause.armed = true;
        await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
        await _pumps(tester);
        expect(pause.entered.isCompleted, isTrue);
        if (boundary == 'cover') {
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
          await tester.pump();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
        }
        pause.release.complete();
        await _pumps(tester);
        final row = await (db.select(
          db.vocabularyWords,
        )..where((r) => r.id.equals(w.id))).getSingle();
        expect(row.isDeleted, isFalse);
        expect(row.localRevision, w.localRevision);
        expect(await db.select(db.outboxOperations).get(), before);
        if (boundary == 'lifecycle')
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        await tester.pumpWidget(const SizedBox());
        await _pumps(tester);
        await db.close();
        await _pumps(tester);
      },
    );
  }
  for (final change in ['owner', 'category', 'word']) {
    testWidgets(
      'AX canonical $change replacement retires private dialog and retained confirm',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        var ownerId = 0;
        var id = 0;
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'owner-${ownerId++}',
          nowUtc: () => DateTime.utc(2026),
        );
        final useCases = VocabularyUseCases(
          owners: owners,
          vocabulary: DriftVocabularyRepository(db),
          generateId: () => 'item-${id++}',
          nowUtc: () => DateTime.utc(2026),
        );
        final c = await useCases.createCategory('Private category');
        final w = await useCases.createWord(
          CreateWordCommand(
            categoryId: c.id,
            spelling: 'secret-book',
            meaning: 'หนังสือส่วนตัว',
            partOfSpeech: 'noun',
          ),
        );
        await tester.pumpWidget(
          app(
            home: VocabListScreen(
              vocabulary: useCases,
              categoryId: c.id,
              categoryName: c.name,
            ),
          ),
        );
        await _pumps(tester);
        await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
        await _pumps(tester);
        final confirm = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลบ'))
            .onPressed!;
        if (change == 'owner') {
          await db.transaction(() async {
            await db.customUpdate(
              'UPDATE local_owners SET is_active = 0',
              updates: {db.localOwners},
            );
            await owners.getOrCreateActiveOwner();
          });
        }
        if (change == 'category')
          await db.customUpdate(
            'UPDATE vocabulary_categories SET local_revision = local_revision + 1 WHERE id = ?',
            variables: [drift.Variable(c.id)],
            updates: {db.vocabularyCategories},
          );
        if (change == 'word')
          await db.customUpdate(
            'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
            variables: [drift.Variable(w.id)],
            updates: {db.vocabularyWords},
          );
        await _pumps(tester);
        confirm();
        await _pumps(tester);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('secret-book'),
          ),
          findsNothing,
        );
        expect(
          (await (db.select(
            db.vocabularyWords,
          )..where((r) => r.id.equals(w.id))).getSingle()).isDeleted,
          isFalse,
        );
        expect(
          (await db.select(db.outboxOperations).get()).where(
            (o) => o.operationKind == 'delete',
          ),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        await _pumps(tester);
        await db.close();
        await _pumps(tester);
      },
    );
  }
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
  bool failing = false;
  Completer<LocalOwner>? pending;
  int calls = 0;
  int? pauseAt;
  static final owner = LocalOwner(
    id: 'local:vocab-list-test',
    createdAtUtc: DateTime.utc(2026, 9, 8),
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() {
    calls++;
    if (failing) throw StateError("read unavailable");
    return (pauseAt == null || calls >= pauseAt!) && pending != null
        ? pending!.future
        : Future.value(active ?? owner);
  }

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

  final deleted = <String>[];
  bool deleteFailure = false;
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
  }) async {
    deleted.add(wordId);
    if (deleteFailure) throw StateError('uncertain acknowledgement');
    words.removeWhere((w) => w.id == wordId);
  }
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
  Future<VocabularyImportResult?> readResult({
    required String importId,
    required String ownerId,
    required String categoryId,
  }) => throw UnimplementedError();

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

Future<void> _pumps(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _WritePause extends drift.QueryInterceptor {
  _WritePause(this.table);
  final String table;
  bool armed = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> pause(String statement) async {
    if (armed && statement.contains('"$table"')) {
      armed = false;
      entered.complete();
      await release.future;
    }
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runInsert(executor, statement, args);
    await pause(statement);
    return result;
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runUpdate(executor, statement, args);
    await pause(statement);
    return result;
  }
}
