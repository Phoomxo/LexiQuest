import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:drift/drift.dart' show Value;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'dart:async';
import 'package:vocab_learning_app/features/vocabulary/application/cefr_practice_examples.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase, LocalOwnersCompanion;
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

  AppDependencies dependencies(
    VocabularyUseCases vocabulary,
    FeatureRegistry features,
  ) => AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: gateDependencies.runtimeStatus,
    config: null,
    guestSessionService: _GuestSessionService(),
    quest: testQuestUseCases(),
    experiments: gateDependencies.experiments,
    consents: gateDependencies.consents,
    experimentAssignments: gateDependencies.experimentAssignments,
    assignedLearningEventContext: gateDependencies.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        gateDependencies.evidencePolicyRolloutModeProvider,
    vocabulary: vocabulary,
    features: features,
  );

  for (final words in [false, true]) {
    testWidgets(
      'AV callbacks retire across emergency gate round trip words=$words',
      (tester) async {
        final features = RuntimeFeatureRegistry(
          const BuildFeatureRegistry.allEnabled(),
        );
        addTearDown(features.dispose);
        final vocabulary = _vocabulary(
          _VocabularyRepository(
            [
              _word(
                id: 'word:book',
                ownerId: _OwnerRepository.owner.id,
                categoryId: 'category:personal',
              ),
            ],
            categories: [_category(readOnly: false)],
          ),
        );
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: dependencies(vocabulary, features),
            child: MaterialApp(
              home: words
                  ? const VocabListScreen(
                      categoryId: 'category:personal',
                      categoryName: 'My words',
                    )
                  : const CategoriesPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final VoidCallback old = words
            ? () {}
            : tester
                  .widget<ListTile>(find.widgetWithText(ListTile, 'My words'))
                  .onTap!;
        final search = words
            ? tester.widget<SearchBar>(find.byType(SearchBar)).onChanged
            : null;
        features.emergencyOff(Feature.vocabulary);
        await tester.pumpAndSettle();
        expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
        features.clearOverride(Feature.vocabulary);
        await tester.pumpAndSettle();
        if (words) {
          search!('missing');
        } else {
          old();
        }
        await tester.pumpAndSettle();
        if (words) {
          expect(find.widgetWithText(ListTile, 'book'), findsOneWidget);
        } else {
          expect(find.byType(VocabListScreen), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('AV immediate pop retires mounted callback words=$words', (
      tester,
    ) async {
      final vocabulary = _vocabulary(
        _VocabularyRepository(
          [
            _word(
              id: 'word:book',
              ownerId: _OwnerRepository.owner.id,
              categoryId: 'category:personal',
            ),
          ],
          categories: [_category(readOnly: false)],
        ),
      );
      final nav = GlobalKey<NavigatorState>();
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
          builder: (_) => words
              ? VocabListScreen(
                  categoryId: 'category:personal',
                  categoryName: 'My words',
                  vocabulary: vocabulary,
                )
              : CategoriesPage(vocabulary: vocabulary),
        ),
      );
      await tester.pumpAndSettle();
      final search = words
          ? tester.widget<SearchBar>(find.byType(SearchBar)).onChanged
          : null;
      final open = words
          ? null
          : tester
                .widget<ListTile>(find.widgetWithText(ListTile, 'My words'))
                .onTap!;
      nav.currentState!.pop();
      if (words) {
        search!('missing');
      } else {
        open!();
      }
      await tester.pumpAndSettle();
      expect(find.text('root'), findsOneWidget);
      expect(find.byType(VocabListScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'AV live child survives parent removal and follows replacement registry',
    (tester) async {
      final vocabulary = _vocabulary(
        _VocabularyRepository(
          [
            _word(
              id: 'word:book',
              ownerId: _OwnerRepository.owner.id,
              categoryId: 'category:personal',
            ),
          ],
          categories: [_category(readOnly: false)],
        ),
      );
      final replacement = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(replacement.dispose);
      final nav = GlobalKey<NavigatorState>();
      var deps = dependencies(
        vocabulary,
        const BuildFeatureRegistry.allEnabled(),
      );
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (_, set) {
            update = set;
            return AppDependenciesScope(
              dependencies: deps,
              child: MaterialApp(
                navigatorKey: nav,
                home: const Scaffold(body: Text('root')),
              ),
            );
          },
        ),
      );
      final parent = MaterialPageRoute<void>(
        builder: (_) => const CategoriesPage(),
      );
      nav.currentState!.push(parent);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'My words'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'book'), findsOneWidget);
      nav.currentState!.removeRoute(parent);
      await tester.pumpAndSettle();
      update(() => deps = dependencies(vocabulary, replacement));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), 'book');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'book'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('word-field')))
            .controller!
            .text,
        'book',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      replacement.emergencyOff(Feature.vocabulary);
      await tester.pumpAndSettle();
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('root'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final immediate in [false, true]) {
    testWidgets(
      'AV read handles synchronous=$immediate failure and narrow Thai retry',
      (tester) async {
        var reads = 0;
        final vocabulary = _vocabulary(
          _VocabularyRepository(
            [],
            wordStream: (_, __) {
              reads++;
              if (reads == 1) {
                if (immediate) throw StateError('sync');
                return Stream.error(StateError('immediate'));
              }
              return Stream.value([
                _word(
                  id: 'word:book',
                  ownerId: _OwnerRepository.owner.id,
                  categoryId: 'category:personal',
                ),
              ]);
            },
          ),
        );
        tester.view.physicalSize = const Size(360, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: gateDependencies,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: VocabListScreen(
                categoryId: 'category:personal',
                categoryName: 'My words',
                vocabulary: vocabulary,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final retry = find.widgetWithText(OutlinedButton, 'ลองใหม่');
        await tester.ensureVisible(retry);
        await tester.pump();
        expect(retry.hitTestable(), findsOneWidget);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(reads, 2);
        expect(find.widgetWithText(ListTile, 'book'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final boundary in [
    'owner-categories',
    'owner-words',
    'category-removal',
  ]) {
    testWidgets('AV real Drift browse retires $boundary', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var id = 0;
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'av-owner-${++id}',
        nowUtc: () => DateTime.utc(2026, 9, 25),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(db),
        generateId: () => 'av-${++id}',
        nowUtc: () => DateTime.utc(2026, 9, 25),
      );
      late VocabularyCategory category;
      {
        category = await vocabulary.createCategory('AV private');
        await vocabulary.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'privatebook',
            meaning: 'private meaning',
            partOfSpeech: 'noun',
          ),
        );
      }
      Future<void> settleRead() async {
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        app(
          home: boundary == 'owner-categories'
              ? CategoriesPage(vocabulary: vocabulary)
              : VocabListScreen(
                  vocabulary: vocabulary,
                  categoryId: category.id,
                  categoryName: category.name,
                ),
        ),
      );
      await settleRead();
      expect(
        find.text(
          boundary == 'owner-categories' ? 'AV private' : 'privatebook',
        ),
        findsOneWidget,
      );
      {
        if (boundary == 'category-removal') {
          await vocabulary.deleteCategory(category.id);
        } else {
          await db.transaction(() async {
            await db
                .update(db.localOwners)
                .write(const LocalOwnersCompanion(isActive: Value(false)));
          });
          await owners.getOrCreateActiveOwner();
        }
      }
      await settleRead();
      expect(
        find.text(
          boundary == 'owner-categories' ? 'AV private' : 'privatebook',
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('add-word')), findsNothing);
      expect(
        find.text('AV private'),
        findsNothing,
        reason: 'Retired category title must not expose the previous owner',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await settleRead();
    });
  }
  testWidgets(
    'AV search retains its subscribed list and original query after return',
    (tester) async {
      var reads = 0;
      final word = _word(
        id: 'word:book',
        ownerId: _OwnerRepository.owner.id,
        categoryId: 'category:personal',
      );
      final vocabulary = _vocabulary(
        _VocabularyRepository(
          [word],
          categories: [_category(readOnly: false)],
          wordStream: (_, __) {
            reads++;
            return Stream.value([word]);
          },
        ),
      );
      await tester.pumpWidget(
        app(
          home: VocabListScreen(
            categoryId: 'category:personal',
            categoryName: 'My words',
            vocabulary: vocabulary,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), 'book');
      await tester.pumpAndSettle();
      expect(
        reads,
        1,
        reason: 'Local filtering must not restart the canonical read',
      );
      await tester.tap(find.widgetWithText(ListTile, 'book'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('word-field')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        'book',
      );
      expect(find.text('My words'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'book'), findsOneWidget);
    },
  );

  testWidgets(
    'AV word read failure offers bounded explicit retry and retains query',
    (tester) async {
      final streams = <StreamController<List<VocabularyWord>>>[];
      addTearDown(() async {
        for (final s in streams) {
          await s.close();
        }
      });
      final vocabulary = _vocabulary(
        _VocabularyRepository(
          [],
          wordStream: (_, __) {
            final c = StreamController<List<VocabularyWord>>();
            streams.add(c);
            return c.stream;
          },
        ),
      );
      await tester.pumpWidget(
        app(
          home: VocabListScreen(
            categoryId: 'category:personal',
            categoryName: 'My words',
            vocabulary: vocabulary,
          ),
        ),
      );
      await tester.pump();
      streams.last.addError(StateError('read unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('อ่านคำศัพท์ไม่สำเร็จ'), findsOneWidget);
      expect(find.text('ลองใหม่'), findsOneWidget);
      final retry = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'ลองใหม่'),
          )
          .onPressed!;
      retry();
      retry();
      await tester.pump();
      expect(streams, hasLength(2));
      streams.last.add([
        _word(
          id: 'word:book',
          ownerId: _OwnerRepository.owner.id,
          categoryId: 'category:personal',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'book'), findsOneWidget);
      retry();
      await tester.pump();
      expect(streams, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('AV category retry callback is single flight', (tester) async {
    final streams = _CategoryStreams();
    addTearDown(streams.close);
    await tester.pumpWidget(
      app(
        home: CategoriesPage(
          vocabulary: _vocabulary(
            _VocabularyRepository([], categoryStream: streams.watch),
          ),
        ),
      ),
    );
    await tester.pump();
    streams.controllers.single.addError(StateError('failure'));
    await tester.pumpAndSettle();
    final retry = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'ลองใหม่'))
        .onPressed!;
    retry();
    retry();
    await tester.pump();
    expect(streams.controllers, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('AV repeated category callback opens exactly one child', (
    tester,
  ) async {
    final vocabulary = _vocabulary(
      _VocabularyRepository([], categories: [_category(readOnly: false)]),
    );
    await tester.pumpWidget(app(home: CategoriesPage(vocabulary: vocabulary)));
    await tester.pumpAndSettle();
    final open = tester
        .widget<ListTile>(find.widgetWithText(ListTile, 'My words'))
        .onTap!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(find.byType(VocabListScreen, skipOffstage: false), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesPage), findsOneWidget);
  });

  for (final boundary in [
    'tab',
    'cover',
    'pop',
    'dispose',
    'lifecycle',
    'dependency',
    'removed',
  ]) {
    testWidgets('AV category callback retires on $boundary', (tester) async {
      final streams = _CategoryStreams();
      addTearDown(streams.close);
      final vocabulary = _vocabulary(
        _VocabularyRepository([], categoryStream: streams.watch),
      );
      final nav = GlobalKey<NavigatorState>();
      var visible = true;
      var present = true;
      var selected = vocabulary;
      late StateSetter update;
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
                  child: present
                      ? CategoriesPage(vocabulary: selected)
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      streams.controllers.single.add([_category(readOnly: false)]);
      await tester.pumpAndSettle();
      final open = tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'My words'))
          .onTap!;
      if (boundary == 'tab') {
        update(() => visible = false);
        await tester.pump();
      }
      if (boundary == 'dispose') {
        update(() => present = false);
        await tester.pump();
      }
      if (boundary == 'cover') {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
        await tester.pumpAndSettle();
      }
      if (boundary == 'pop') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      if (boundary == 'lifecycle') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
      }
      if (boundary == 'dependency') {
        update(
          () => selected = _vocabulary(
            _VocabularyRepository([], categories: [_category(readOnly: true)]),
          ),
        );
        await tester.pumpAndSettle();
      }
      if (boundary == 'removed') {
        streams.controllers.single.add([]);
        await tester.pumpAndSettle();
      }
      open();
      await tester.pump();
      expect(find.byType(VocabListScreen, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      if (boundary == 'lifecycle') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
    });
  }

  for (final boundary in ['tab', 'cover', 'dispose', 'lifecycle', 'category']) {
    testWidgets('AV search callback retires on $boundary', (tester) async {
      final vocabulary = _vocabulary(
        _VocabularyRepository([
          _word(
            id: 'word:book',
            ownerId: _OwnerRepository.owner.id,
            categoryId: 'category:personal',
          ),
        ]),
      );
      final nav = GlobalKey<NavigatorState>();
      var visible = true;
      var present = true;
      var category = 'category:personal';
      late StateSetter update;
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
                  child: present
                      ? VocabListScreen(
                          categoryId: category,
                          categoryName: 'My words',
                          vocabulary: vocabulary,
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final change = tester
          .widget<SearchBar>(find.byType(SearchBar))
          .onChanged!;
      if (boundary == 'tab') {
        update(() => visible = false);
        await tester.pump();
      }
      if (boundary == 'dispose') {
        update(() => present = false);
        await tester.pump();
      }
      if (boundary == 'cover') {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
        await tester.pumpAndSettle();
      }
      if (boundary == 'lifecycle') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
      }
      if (boundary == 'category') {
        update(() => category = 'category:replacement');
        await tester.pumpAndSettle();
      }
      change('missing');
      await tester.pump();
      if (boundary == 'tab') {
        update(() => visible = true);
        await tester.pumpAndSettle();
      }
      if (boundary == 'cover') {
        nav.currentState!.pop();
        await tester.pumpAndSettle();
      }
      if (boundary == 'lifecycle') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      }
      if (boundary != 'dispose') {
        expect(find.text('ไม่พบคำศัพท์ที่ตรงกับคำค้น'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
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
    this.wordStream,
  });

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
