import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'dart:async';
import 'package:vocab_learning_app/features/vocabulary/application/cefr_practice_examples.dart';
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
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';

import 'package:vocab_learning_app/screens/add_vocab_screen.dart';
import '../features/vocabulary/word_delete_admission_test.dart' show WritePause;

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
      vocabulary: VocabularyUseCases(
        owners: DriftLocalOwnerRepository(
          gateDatabase,
          generateId: () => "gate",
          nowUtc: () => DateTime.utc(2026),
        ),
        vocabulary: DriftVocabularyRepository(gateDatabase),
        generateId: () => "gate-item",
        nowUtc: () => DateTime.utc(2026),
      ),
    );
  });
  tearDown(() => gateDatabase.close());
  Widget app({required Widget home}) => AppDependenciesScope(
    dependencies: gateDependencies,
    child: MaterialApp(home: home),
  );

  for (final boundary in [
    'owner',
    'category',
    'word',
    'dependency',
    'cover',
    'tab',
    'lifecycle',
    'dispose',
  ]) {
    testWidgets(
      'AY retained form save rejects $boundary and protects partial draft',
      (tester) async {
        final f = await _Fixture.create(gateDatabase);
        var vocabulary = f.useCases;
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
                    child: AddWordScreen(
                      vocabulary: vocabulary,
                      categoryId: f.category.id,
                      word: f.word,
                      featureRegistry: const BuildFeatureRegistry.allEnabled(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await _pumps(tester);
        await tester.enterText(
          find.byKey(const ValueKey('meaning-field')),
          'private draft',
        );
        await tester.pump();
        final save = tester
            .widget<FilledButton>(find.byKey(const ValueKey('save-word')))
            .onPressed!;
        final cefr = tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged!;
        if (boundary == 'owner') {
          await gateDatabase.customUpdate(
            'UPDATE local_owners SET is_active = 0',
          );
          await f.owners.getOrCreateActiveOwner();
        }
        if (boundary == 'category') {
          await f.useCases.renameCategory(f.category.id, 'Changed');
        }
        if (boundary == 'word') {
          await f.useCases.updateWord(
            UpdateWordCommand(
              id: f.word.id,
              categoryId: f.category.id,
              spelling: 'book',
              meaning: 'external update',
              partOfSpeech: 'noun',
            ),
          );
        }
        if (boundary == 'dependency') {
          update(
            () => vocabulary = VocabularyUseCases(
              owners: f.owners,
              vocabulary: DriftVocabularyRepository(gateDatabase),
              generateId: () => 'replacement',
              nowUtc: () => DateTime.utc(2026),
            ),
          );
        }
        if (boundary == 'cover') {
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
        }
        if (boundary == 'tab') update(() => visible = false);
        if (boundary == 'lifecycle') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        if (boundary == 'dispose') await tester.pumpWidget(const SizedBox());
        await _pumps(tester);
        final before = await gateDatabase
            .select(gateDatabase.vocabularyWords)
            .get();
        final outbox = await gateDatabase
            .select(gateDatabase.outboxOperations)
            .get();
        save();
        cefr('C2');
        await _pumps(tester);
        expect(
          await gateDatabase.select(gateDatabase.vocabularyWords).get(),
          before,
        );
        expect(
          await gateDatabase.select(gateDatabase.outboxOperations).get(),
          outbox,
        );
        expect(tester.takeException(), isNull);
        if (boundary == 'owner') {
          expect(find.text('private draft'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
        await _pumps(tester);
      },
    );
  }
  testWidgets(
    'AY initial owner read failure has Thai retry and keeps partial draft',
    (tester) async {
      final f = await _Fixture.create(gateDatabase);
      final owners = _FaultOwner(f.owners)..failing = true;
      final useCases = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(gateDatabase),
        generateId: () => 'new',
        nowUtc: () => DateTime.utc(2026),
      );
      await tester.pumpWidget(
        app(
          home: AddWordScreen(
            categoryId: f.category.id,
            vocabulary: useCases,
            featureRegistry: const BuildFeatureRegistry.allEnabled(),
          ),
        ),
      );
      await _pumps(tester);
      expect(find.text('ลองใหม่'), findsOneWidget);
      owners.failing = false;
      await tester.tap(find.text('ลองใหม่'));
      await _pumps(tester);
      await tester.enterText(
        find.byKey(const ValueKey('meaning-field')),
        'partial',
      );
      expect(find.text('partial'), findsOneWidget);
      expect(
        await gateDatabase.select(gateDatabase.vocabularyWords).get(),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
      await _pumps(tester);
    },
  );
  testWidgets(
    'AY early explicit Save waits for initial owner read then writes once',
    (tester) async {
      final f = await _Fixture.create(gateDatabase);
      final owners = _FaultOwner(f.owners)..pending = Completer<LocalOwner>();
      final useCases = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(gateDatabase),
        generateId: () => 'early',
        nowUtc: () => DateTime.utc(2026),
      );
      await tester.pumpWidget(
        app(
          home: AddWordScreen(
            categoryId: f.category.id,
            vocabulary: useCases,
            featureRegistry: const BuildFeatureRegistry.allEnabled(),
          ),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('word-field')), 'early');
      await tester.enterText(
        find.byKey(const ValueKey('meaning-field')),
        'draft',
      );
      await tester.enterText(
        find.byKey(const ValueKey('part-of-speech-field')),
        'noun',
      );
      final save = tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-word')))
          .onPressed!;
      save();
      save();
      await tester.pump();
      expect(
        await gateDatabase.select(gateDatabase.vocabularyWords).get(),
        hasLength(1),
      );
      final pending = owners.pending!;
      owners.pending = null;
      pending.complete(await f.owners.getOrCreateActiveOwner());
      await _pumps(tester);
      expect(
        await gateDatabase.select(gateDatabase.vocabularyWords).get(),
        hasLength(2),
      );
      expect(
        (await gateDatabase.select(gateDatabase.outboxOperations).get()).where(
          (r) => r.entityId == 'word:early',
        ),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
      await _pumps(tester);
    },
  );
  for (final editing in [false, true]) {
    for (final committed in [false, true]) {
      testWidgets(
        'AY uncertain acknowledgement edit=$editing committed=$committed never resubmits automatically',
        (tester) async {
          final f = await _Fixture.create(gateDatabase);
          final repo = _FaultRepository(
            DriftVocabularyRepository(gateDatabase),
          );
          var id = 0;
          final u = VocabularyUseCases(
            owners: f.owners,
            vocabulary: repo,
            generateId: () => 'attempt-${id++}',
            nowUtc: () => DateTime.utc(2026),
          );
          await tester.pumpWidget(
            app(
              home: AddWordScreen(
                categoryId: f.category.id,
                word: editing ? f.word : null,
                vocabulary: u,
                featureRegistry: const BuildFeatureRegistry.allEnabled(),
              ),
            ),
          );
          await _pumps(tester);
          await tester.enterText(
            find.byKey(const ValueKey('word-field')),
            editing ? 'book' : 'new',
          );
          await tester.enterText(
            find.byKey(const ValueKey('meaning-field')),
            'private draft',
          );
          await tester.enterText(
            find.byKey(const ValueKey('part-of-speech-field')),
            'noun',
          );
          repo.failBefore = !committed;
          repo.failAfter = committed;
          final save = tester
              .widget<FilledButton>(find.byKey(const ValueKey('save-word')))
              .onPressed!;
          save();
          save();
          await _pumps(tester);
          expect(repo.mutationCalls, 1);
          final rows = await gateDatabase
              .select(gateDatabase.vocabularyWords)
              .get();
          final outbox = await gateDatabase
              .select(gateDatabase.outboxOperations)
              .get();
          expect(rows.length, editing || !committed ? 1 : 2);
          expect(
            rows.singleWhere((r) => r.id == f.word.id).localRevision,
            editing && committed ? 2 : 1,
          );
          expect(find.text('ลองใหม่'), findsOneWidget);
          await tester.tap(find.text('ลองใหม่'));
          await _pumps(tester);
          expect(repo.mutationCalls, 1);
          expect(
            await gateDatabase.select(gateDatabase.outboxOperations).get(),
            outbox,
          );
          if (!committed) {
            expect(find.text('private draft'), findsOneWidget);
            repo.failBefore = false;
            tester
                .widget<FilledButton>(find.byKey(const ValueKey('save-word')))
                .onPressed!();
            await _pumps(tester);
            expect(repo.mutationCalls, 2);
          } else {
            expect(
              tester
                  .widget<FilledButton>(find.byKey(const ValueKey('save-word')))
                  .onPressed,
              isNull,
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('meaning-field')),
                  )
                  .enabled,
              isFalse,
            );
          }
          await tester.pumpWidget(const SizedBox());
          await _pumps(tester);
        },
      );
    }
    testWidgets(
      'AY native save edit=$editing rolls back after outbox on cover',
      (tester) async {
        final pause = WritePause('outbox_operations');
        final db = AppDatabase(NativeDatabase.memory().interceptWith(pause));
        final f = await _Fixture.create(db);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: gateDependencies,
            child: MaterialApp(
              navigatorKey: navigator,
              home: AddWordScreen(
                categoryId: f.category.id,
                word: editing ? f.word : null,
                vocabulary: f.useCases,
                featureRegistry: const BuildFeatureRegistry.allEnabled(),
              ),
            ),
          ),
        );
        await _pumps(tester);
        await tester.enterText(find.byKey(const ValueKey('word-field')), 'new');
        await tester.enterText(
          find.byKey(const ValueKey('meaning-field')),
          'draft',
        );
        await tester.enterText(
          find.byKey(const ValueKey('part-of-speech-field')),
          'noun',
        );
        final before = await db.select(db.vocabularyWords).get();
        final outbox = await db.select(db.outboxOperations).get();
        pause.armed = true;
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('save-word')))
            .onPressed!();
        await _pumps(tester);
        expect(pause.entered.isCompleted, isTrue);
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        pause.release.complete();
        await _pumps(tester);
        expect(await db.select(db.vocabularyWords).get(), before);
        expect(await db.select(db.outboxOperations).get(), outbox);
        expect(find.text('cover'), findsOneWidget);
        expect(
          find.text('กรุณากรอกข้อมูลให้ครบและไม่เกินความยาวที่กำหนด'),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
        await _pumps(tester);
        await db.close();
      },
    );
  }
  for (final boundary in ['cover', 'emergency', 'replacement', 'removal']) {
    testWidgets('AY retained optional fill and CEFR reject $boundary', (
      tester,
    ) async {
      final f = await _Fixture.create(gateDatabase);
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      final navigator = GlobalKey<NavigatorState>();
      var word = f.word;
      late StateSetter update;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: gateDependencies,
          child: MaterialApp(
            navigatorKey: navigator,
            home: StatefulBuilder(
              builder: (_, set) {
                update = set;
                return AddWordScreen(
                  categoryId: f.category.id,
                  word: word,
                  vocabulary: f.useCases,
                  featureRegistry: features,
                );
              },
            ),
          ),
        ),
      );
      await _pumps(tester);
      final fill = tester
          .widgetList<MenuActionBinding>(find.byType(MenuActionBinding))
          .singleWhere((w) => w.id == 'vocabulary/word-fill')
          .onForm!;
      final cefr = tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged!;
      if (boundary == 'cover') {
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
      }
      if (boundary == 'emergency') {
        features.emergencyOff(Feature.vocabulary);
        features.clearOverride(Feature.vocabulary);
      }
      if (boundary == 'replacement') {
        update(
          () =>
              word = f.word.copyWith(meaning: 'replacement', localRevision: 2),
        );
      }
      if (boundary == 'removal') await f.useCases.deleteWord(f.word.id);
      await _pumps(tester);
      final result = await fill({
        'spelling': 'secret',
        'meaning': 'secret',
        'partOfSpeech': 'noun',
        'cefrLevel': 'C2',
      });
      cefr('C2');
      await _pumps(tester);
      expect(result['status'], isNot('filled'));
      expect(find.text('secret', skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _pumps(tester);
      features.dispose();
    });
  }
  testWidgets(
    'AY recoverable owner read error retains partial draft and requires explicit Save',
    (tester) async {
      final f = await _Fixture.create(gateDatabase);
      final owner = _FaultOwner(f.owners);
      final u = VocabularyUseCases(
        owners: owner,
        vocabulary: DriftVocabularyRepository(gateDatabase),
        generateId: () => 'retry',
        nowUtc: () => DateTime.utc(2026),
      );
      await tester.pumpWidget(
        app(
          home: AddWordScreen(
            categoryId: f.category.id,
            vocabulary: u,
            featureRegistry: const BuildFeatureRegistry.allEnabled(),
          ),
        ),
      );
      await _pumps(tester);
      await tester.enterText(find.byKey(const ValueKey('word-field')), 'retry');
      await tester.enterText(
        find.byKey(const ValueKey('meaning-field')),
        'partial',
      );
      await tester.enterText(
        find.byKey(const ValueKey('part-of-speech-field')),
        'noun',
      );
      owner.failing = true;
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-word')))
          .onPressed!();
      await _pumps(tester);
      expect(find.text('partial'), findsOneWidget);
      expect(find.text('ลองใหม่'), findsOneWidget);
      owner.failing = false;
      await tester.tap(find.text('ลองใหม่'));
      await _pumps(tester);
      expect(
        await gateDatabase.select(gateDatabase.vocabularyWords).get(),
        hasLength(1),
      );
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-word')))
          .onPressed!();
      await _pumps(tester);
      expect(
        await gateDatabase.select(gateDatabase.vocabularyWords).get(),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
      await _pumps(tester);
    },
  );
  testWidgets('AY retained cancel cannot pop covering route', (tester) async {
    final f = await _Fixture.create(gateDatabase);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: gateDependencies,
        child: MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AddWordScreen(
          categoryId: f.category.id,
          vocabulary: f.useCases,
          featureRegistry: const BuildFeatureRegistry.allEnabled(),
        ),
      ),
    );
    await _pumps(tester);
    final cancel = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_back))
        .onPressed!;
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover')),
      ),
    );
    await _pumps(tester);
    cancel();
    await _pumps(tester);
    expect(find.text('cover'), findsOneWidget);
    expect(
      await gateDatabase.select(gateDatabase.vocabularyWords).get(),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
    await _pumps(tester);
  });
  testWidgets('AY owned CEFR chooser remains usable and saves selected level', (
    tester,
  ) async {
    final f = await _Fixture.create(gateDatabase);
    await tester.pumpWidget(
      app(
        home: AddWordScreen(
          categoryId: f.category.id,
          word: f.word,
          vocabulary: f.useCases,
          featureRegistry: const BuildFeatureRegistry.allEnabled(),
        ),
      ),
    );
    await _pumps(tester);
    final chooser = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(chooser);
    await tester.tap(chooser);
    await tester.pumpAndSettle();
    await tester.tap(find.text('B2').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('word-field')), findsOneWidget);
    expect(find.text('B2'), findsOneWidget);
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('save-word')))
        .onPressed!();
    await _pumps(tester);
    expect(
      (await gateDatabase.select(gateDatabase.vocabularyWords).get())
          .single
          .cefrLevel,
      'B2',
    );
    await tester.pumpWidget(const SizedBox());
    await _pumps(tester);
  });
  testWidgets('AY pending initial owner hides existing private word', (
    tester,
  ) async {
    final f = await _Fixture.create(gateDatabase);
    final owner = _FaultOwner(f.owners)..pending = Completer<LocalOwner>();
    final u = VocabularyUseCases(
      owners: owner,
      vocabulary: DriftVocabularyRepository(gateDatabase),
      generateId: () => 'hidden',
      nowUtc: () => DateTime.utc(2026),
    );
    await tester.pumpWidget(
      app(
        home: AddWordScreen(
          categoryId: f.category.id,
          word: f.word,
          vocabulary: u,
          featureRegistry: const BuildFeatureRegistry.allEnabled(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('book'), findsNothing);
    expect(find.text('original'), findsNothing);
    final pending = owner.pending!;
    owner.pending = null;
    pending.complete(await f.owners.getOrCreateActiveOwner());
    await _pumps(tester);
    expect(find.text('book'), findsOneWidget);
    expect(find.text('original'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _pumps(tester);
  });
}

class _Fixture {
  _Fixture(this.owners, this.useCases, this.category, this.word);
  final DriftLocalOwnerRepository owners;
  final VocabularyUseCases useCases;
  final VocabularyCategory category;
  final VocabularyWord word;
  static Future<_Fixture> create(AppDatabase db) async {
    var ownerId = 0, id = 0;
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'owner-${ownerId++}',
      nowUtc: () => DateTime.utc(2026),
    );
    final u = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(db),
      generateId: () => 'item-${id++}',
      nowUtc: () => DateTime.utc(2026),
    );
    final c = await u.createCategory('Private');
    final w = await u.createWord(
      CreateWordCommand(
        categoryId: c.id,
        spelling: 'book',
        meaning: 'original',
        partOfSpeech: 'noun',
      ),
    );
    return _Fixture(owners, u, c, w);
  }
}

class _FaultOwner implements LocalOwnerRepository {
  _FaultOwner(this.delegate);
  final LocalOwnerRepository delegate;
  bool failing = false;
  Completer<LocalOwner>? pending;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() {
    if (failing) throw StateError('read fault');
    return pending?.future ?? delegate.getOrCreateActiveOwner();
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      delegate.bindFirebaseUid(ownerId, firebaseUid);
}

final class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'form-fixture');
}

Future<void> _pumps(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _FaultRepository implements VocabularyRepository {
  _FaultRepository(this.delegate);
  final VocabularyRepository delegate;
  var failReadback = false;
  bool failBefore = false, failAfter = false;
  var mutationCalls = 0;

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) {
    return delegate.listAllWords(ownerId);
  }

  @override
  Future<void> deleteWord({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
  }) async {
    await delegate.deleteWord(ownerId: ownerId, wordId: wordId, nowUtc: nowUtc);
  }

  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) =>
      delegate.watchCategories(ownerId);
  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) =>
      delegate.watchWords(ownerId, categoryId);
  @override
  Future<List<VocabularyWord>> readPinnedByIds(Iterable<String> ids) {
    if (failReadback) throw StateError('injected post-commit read failure');
    return delegate.readPinnedByIds(ids);
  }

  @override
  Future<VocabularyCategory> createCategory(VocabularyCategory category) =>
      delegate.createCategory(category);
  @override
  Future<VocabularyCategory> renameCategory({
    required String ownerId,
    required String categoryId,
    required String name,
    required String normalizedName,
    required DateTime nowUtc,
  }) => delegate.renameCategory(
    ownerId: ownerId,
    categoryId: categoryId,
    name: name,
    normalizedName: normalizedName,
    nowUtc: nowUtc,
  );
  @override
  Future<void> deleteCategory({
    required String ownerId,
    required String categoryId,
    required DateTime nowUtc,
  }) => delegate.deleteCategory(
    ownerId: ownerId,
    categoryId: categoryId,
    nowUtc: nowUtc,
  );
  @override
  Future<VocabularyWord> createWord(VocabularyWord word) async {
    mutationCalls++;
    if (failBefore) throw StateError("disk failure");
    final result = await delegate.createWord(word);
    if (failAfter) throw StateError("lost acknowledgement");
    return result;
  }

  @override
  Future<VocabularyWord> updateWord(VocabularyWord word) async {
    mutationCalls++;
    if (failBefore) throw StateError("disk failure");
    final result = await delegate.updateWord(word);
    if (failAfter) throw StateError("lost acknowledgement");
    return result;
  }
}
