import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_failure.dart';
import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
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
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/packaged_starter_identity.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';

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

  testWidgets('AW add action admits only one owned dialog', (tester) async {
    final repository = _VocabularyRepository(
      [],
      categories: [_category(readOnly: false)],
    );
    await tester.pumpWidget(
      app(home: CategoriesPage(vocabulary: _vocabulary(repository))),
    );
    await tester.pumpAndSettle();
    final open = tester
        .widget<FloatingActionButton>(
          find.byKey(const ValueKey('add-category')),
        )
        .onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'My draft',
    );
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await tester.pumpAndSettle();
    expect(repository.created.single.name, 'My draft');
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final boundary in ['cover', 'tab', 'lifecycle', 'replacement', 'pop']) {
    testWidgets('AW retained add retires after $boundary', (tester) async {
      final vocabulary = _vocabulary(_VocabularyRepository([]));
      final replacement = _vocabulary(_VocabularyRepository([]));
      final nav = GlobalKey<NavigatorState>();
      late StateSetter update;
      var visible = true;
      var current = vocabulary;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: gateDependencies,
          child: MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('root')),
          ),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => StatefulBuilder(
            builder: (_, set) {
              update = set;
              return TickerMode(
                enabled: visible,
                child: CategoriesPage(vocabulary: current),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final open = tester
          .widget<FloatingActionButton>(
            find.byKey(const ValueKey('add-category')),
          )
          .onPressed!;
      if (boundary == 'cover') {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
        await tester.pumpAndSettle();
      }
      if (boundary == 'tab') {
        update(() => visible = false);
        await tester.pump();
      }
      if (boundary == 'replacement') {
        update(() => current = replacement);
        await tester.pumpAndSettle();
      }
      if (boundary == 'lifecycle') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
      }
      if (boundary == 'pop') nav.currentState!.pop();
      open();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      if (boundary == 'lifecycle')
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('AW draft cannot redirect save to replacement owner', (
    tester,
  ) async {
    final owners = _OwnerRepository();
    final repository = _VocabularyRepository([]);
    await tester.pumpWidget(
      app(
        home: CategoriesPage(
          vocabulary: _vocabulary(repository, owners: owners),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-category')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Private draft',
    );
    owners.active = LocalOwner(
      id: 'replacement',
      createdAtUtc: DateTime.utc(2026),
    );
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await tester.pumpAndSettle();
    expect(repository.created, isEmpty);
  });

  testWidgets('AW detached cancel cannot pop a covering route', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: gateDependencies,
        child: MaterialApp(
          navigatorKey: nav,
          home: CategoriesPage(
            vocabulary: _vocabulary(_VocabularyRepository([])),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-category')));
    await tester.pumpAndSettle();
    final cancel = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'ยกเลิก'))
        .onPressed!;
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover')),
      ),
    );
    await tester.pumpAndSettle();
    cancel();
    await tester.pumpAndSettle();
    expect(find.text('cover'), findsOneWidget);
  });
  for (final action in ['add', 'delete']) {
    testWidgets(
      'AW $action owned dialog retires mutation after owner replacement',
      (tester) async {
        final owners = _OwnerRepository();
        final repository = _VocabularyRepository(
          [],
          categories: [_category(readOnly: false)],
        );
        await tester.pumpWidget(
          app(
            home: CategoriesPage(
              vocabulary: _vocabulary(repository, owners: owners),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          action == 'add'
              ? find.byKey(const ValueKey('add-category'))
              : find.byTooltip('ลบหมวดหมู่'),
        );
        await tester.pumpAndSettle();
        if (action == 'add')
          await tester.enterText(
            find.byKey(const ValueKey('category-name-field')),
            'Private draft',
          );
        owners.active = LocalOwner(
          id: 'replacement',
          createdAtUtc: DateTime.utc(2026),
        );
        await tester.tap(
          action == 'add'
              ? find.byKey(const ValueKey('save-category'))
              : find.widgetWithText(FilledButton, 'ลบ'),
        );
        await tester.pumpAndSettle();
        expect(repository.created, isEmpty);
        expect(repository.deleted, isEmpty);
      },
    );
  }
  testWidgets('AW delete admits one owned dialog and explicit deletion', (
    tester,
  ) async {
    final repository = _VocabularyRepository(
      [],
      categories: [_category(readOnly: false)],
    );
    await tester.pumpWidget(
      app(home: CategoriesPage(vocabulary: _vocabulary(repository))),
    );
    await tester.pumpAndSettle();
    final open = tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.delete_outline),
        )
        .onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
    await tester.pumpAndSettle();
    expect(repository.deleted, ['category:personal']);
  });
  testWidgets('AW delete confirmation retires after category removed', (
    tester,
  ) async {
    final streams = _CategoryStreams();
    addTearDown(streams.close);
    final repository = _VocabularyRepository([], categoryStream: streams.watch);
    await tester.pumpWidget(
      app(home: CategoriesPage(vocabulary: _vocabulary(repository))),
    );
    await tester.pump();
    streams.controllers.first.add([_category(readOnly: false)]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ลบหมวดหมู่'));
    await tester.pumpAndSettle();
    final confirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลบ'))
        .onPressed!;
    for (final c in streams.controllers) {
      c.add([]);
    }
    await tester.pumpAndSettle();
    confirm();
    await tester.pumpAndSettle();
    expect(repository.deleted, isEmpty);
    expect(find.textContaining('My words'), findsNothing);
  });
  testWidgets(
    'AW uncertain category acknowledgement preserves draft and offers truthful recovery',
    (tester) async {
      final repository = _VocabularyRepository([])..createFailure = true;
      await tester.pumpWidget(
        app(home: CategoriesPage(vocabulary: _vocabulary(repository))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-category')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('category-name-field')),
        'My draft',
      );
      await tester.tap(find.byKey(const ValueKey('save-category')));
      await tester.pumpAndSettle();
      expect(
        find.text('ยังยืนยันผลการบันทึกไม่ได้ กรุณาตรวจหมวดหมู่ก่อนลองใหม่'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('category-name-field')),
            )
            .controller!
            .text,
        'My draft',
      );
      expect(repository.created, hasLength(1));
    },
  );
  for (final action in ['add', 'delete']) {
    for (final boundary in [
      'cover',
      'lifecycle',
      'feature',
      'replacement',
      'tab',
    ]) {
      testWidgets(
        'AW owned $action callbacks retire permanently after $boundary',
        (tester) async {
          final repository = _VocabularyRepository(
            [],
            categories: [_category(readOnly: false)],
          );
          var vocabulary = _vocabulary(repository);
          final features = RuntimeFeatureRegistry(
            const BuildFeatureRegistry.allEnabled(),
          );
          addTearDown(features.dispose);
          final nav = GlobalKey<NavigatorState>();
          late StateSetter update;
          var visible = true;
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
                      child: CategoriesPage(
                        vocabulary: vocabulary,
                        featureRegistry: features,
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            action == 'add'
                ? find.byKey(const ValueKey('add-category'))
                : find.byTooltip('ลบหมวดหมู่'),
          );
          await tester.pumpAndSettle();
          if (action == 'add')
            await tester.enterText(
              find.byKey(const ValueKey('category-name-field')),
              'Private draft',
            );
          final save = tester
              .widget<FilledButton>(
                find.widgetWithText(
                  FilledButton,
                  action == 'add' ? 'บันทึก' : 'ลบ',
                ),
              )
              .onPressed!;
          if (boundary == 'cover') {
            nav.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('cover')),
              ),
            );
            await tester.pumpAndSettle();
            nav.currentState!.pop();
            await tester.pumpAndSettle();
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
            await tester.pump();
            features.clearOverride(Feature.vocabulary);
            await tester.pumpAndSettle();
          }
          if (boundary == 'replacement') {
            update(() => vocabulary = _vocabulary(repository));
            await tester.pumpAndSettle();
          }
          if (boundary == 'tab') {
            update(() => visible = false);
            await tester.pump();
            update(() => visible = true);
            await tester.pumpAndSettle();
          }
          save();
          await tester.pumpAndSettle();
          expect(repository.created, isEmpty);
          expect(repository.deleted, isEmpty);
          expect(find.textContaining('Private draft'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'AW owner read failure retains partial draft and explicit read retry',
    (tester) async {
      final owners = _OwnerRepository();
      final repository = _VocabularyRepository([]);
      await tester.pumpWidget(
        app(
          home: CategoriesPage(
            vocabulary: _vocabulary(repository, owners: owners),
          ),
        ),
      );
      await tester.pumpAndSettle();
      owners.failing = true;
      await tester.tap(find.byKey(const ValueKey('add-category')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('category-name-field')),
        'Partial draft',
      );
      expect(
        find.text('ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่'),
        findsOneWidget,
      );
      owners.failing = false;
      await tester.tap(find.widgetWithText(TextButton, 'ลองใหม่'));
      await tester.pumpAndSettle();
      expect(repository.created, isEmpty);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('category-name-field')),
            )
            .controller!
            .text,
        'Partial draft',
      );
      await tester.tap(find.byKey(const ValueKey('save-category')));
      await tester.pumpAndSettle();
      expect(repository.created.single.name, 'Partial draft');
    },
  );

  for (final table in ['vocabulary_categories', 'outbox_operations']) {
    testWidgets(
      'AW delete retirement after $table write rolls back category words and outbox',
      (tester) async {
        final pause = _WritePause(table);
        final db = AppDatabase(NativeDatabase.memory().interceptWith(pause));
        addTearDown(db.close);
        var id = 0;
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'owner',
          nowUtc: () => DateTime.utc(2026),
        );
        final vocabulary = VocabularyUseCases(
          owners: owners,
          vocabulary: DriftVocabularyRepository(db),
          generateId: () => 'id-${id++}',
          nowUtc: () => DateTime.utc(2026),
        );
        final category = await vocabulary.createCategory('Private category');
        await vocabulary.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'book',
            meaning: 'book',
            partOfSpeech: 'noun',
          ),
        );
        await tester.pumpWidget(
          app(home: CategoriesPage(vocabulary: vocabulary)),
        );
        await _pumps(tester);
        await tester.tap(find.byTooltip('ลบหมวดหมู่'));
        await _pumps(tester);
        pause.armed = true;
        final before = (await db.select(db.outboxOperations).get()).length;
        await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
        await _pumps(tester);
        expect(pause.entered.isCompleted, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        pause.release.complete();
        await _pumps(tester);
        expect(
          (await db.select(db.vocabularyCategories).get()).single.isDeleted,
          isFalse,
        );
        expect(
          (await db.select(db.vocabularyWords).get()).single.isDeleted,
          isFalse,
        );
        expect((await db.select(db.outboxOperations).get()).length, before);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumps(tester);
        await db.close();
        await tester.pump();
      },
    );
  }
  for (final operation in ['fill', 'verify']) {
    testWidgets(
      'AW optional $operation revalidates canonical owner and hides private draft',
      (tester) async {
        final owners = _OwnerRepository();
        final repository = _VocabularyRepository([]);
        final registry = MenuActionRegistry(
          currentOwner: () => _OwnerRepository.owner.id,
        );
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: app(
              home: CategoriesPage(
                vocabulary: _vocabulary(repository, owners: owners),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('add-category')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('category-name-field')),
          'Private draft',
        );
        Future<Map<String, Object?>> invoke(
          String id,
          Map<String, String> values,
        ) async {
          final binding = tester.widget<MenuActionBinding>(
            find.byWidgetPredicate((w) => w is MenuActionBinding && w.id == id),
          );
          Map<String, Object?>? result;
          Future.sync(() => binding.onForm!(values)).then((r) => result = r);
          await tester.pumpAndSettle();
          expect(result, isNotNull);
          return result!;
        }

        if (operation == 'verify') {
          expect(
            (await invoke('vocabulary/category-save', {}))['status'],
            'outcome_unknown',
          );
          expect(repository.created, hasLength(1));
        }
        owners.active = LocalOwner(
          id: 'replacement',
          createdAtUtc: DateTime.utc(2026),
        );
        await invoke(
          operation == 'fill'
              ? 'vocabulary/category-fill'
              : 'vocabulary/category-save',
          operation == 'fill' ? {'name': 'Foreign fill'} : {},
        );
        expect(find.byKey(const ValueKey('category-name-field')), findsNothing);
        expect(find.text('Private draft'), findsNothing);
        expect(repository.created, hasLength(operation == 'fill' ? 0 : 1));
      },
    );
  }
  testWidgets('AW canonical owner rejection never blames the category name', (
    tester,
  ) async {
    final repository = _VocabularyRepository(
      [],
    )..createError = const InvalidVocabularyFailure('owner', 'stale operation');
    await tester.pumpWidget(
      app(home: CategoriesPage(vocabulary: _vocabulary(repository))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-category')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Valid name',
    );
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await tester.pumpAndSettle();
    expect(find.text('กรุณากรอกชื่อหมวดหมู่ให้ถูกต้อง'), findsNothing);
    expect(
      find.text('ข้อมูลหรือหน้าจอเปลี่ยนไปแล้ว กรุณาปิดและเปิดใหม่'),
      findsOneWidget,
    );
    expect(repository.created, isEmpty);
  });
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
  static final owner = LocalOwner(
    id: 'local:vocab-list-test',
    createdAtUtc: DateTime.utc(2026, 9, 8),
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() {
    if (failing) throw StateError('owner read unavailable');
    return Future.value(active ?? owner);
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
    this.wordStream,
  });

  final created = <VocabularyCategory>[];
  final deleted = <String>[];
  bool createFailure = false;
  Object? createError;
  final List<VocabularyWord> words;
  final Stream<List<VocabularyWord>> Function(String, String)? wordStream;
  final List<VocabularyCategory> categories;
  final Stream<List<VocabularyCategory>> Function(String)? categoryStream;

  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) =>
      wordStream?.call(ownerId, categoryId) ?? Stream.value(words);

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
  Future<VocabularyCategory> createCategory(VocabularyCategory category) async {
    if (createError != null) throw createError!;
    created.add(category);
    if (createFailure) throw StateError('uncertain acknowledgement');
    return category;
  }

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
  }) async {
    deleted.add(categoryId);
  }

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
