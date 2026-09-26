import 'dart:async';
import '../features/vocabulary/manual_import_admission_test.dart'
    show WritePause;
import 'package:drift/drift.dart' as drift;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/add_multiple_words_screen.dart';
import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_import.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';

class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'test');
}

class Owners implements LocalOwnerRepository {
  Owners(this.delegate);
  final LocalOwnerRepository delegate;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    if (fail) throw StateError('read failure');
    await gate?.future;
    return delegate.getOrCreateActiveOwner();
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String a, String b) =>
      delegate.bindFirebaseUid(a, b);
}

class Repo implements VocabularyImportRepository {
  Repo(this.delegate);
  final VocabularyImportRepository delegate;
  int writes = 0;
  void Function()? cancelBefore;
  bool failBefore = false, failAfter = false, failRead = false;
  Completer<void>? readGate;
  Completer<void>? readEntered;
  bool wrongIdentity = false;
  @override
  Future<VocabularyImportResult> persist(
    PreparedVocabularyImport value, {
    required bool Function() isCancelled,
  }) async {
    writes++;
    if (cancelBefore != null) {
      cancelBefore!();
      throw const VocabularyImportCancelled();
    }
    if (failBefore) throw StateError('before');
    final result = await delegate.persist(value, isCancelled: isCancelled);
    if (failAfter) throw StateError('lost acknowledgement');
    return result;
  }

  @override
  Future<VocabularyImportResult?> readResult({
    required String importId,
    required String ownerId,
    required String categoryId,
  }) async {
    if (readEntered != null && !readEntered!.isCompleted) {
      readEntered!.complete();
    }
    await readGate?.future;
    if (failRead) throw StateError('readback');
    final result = await delegate.readResult(
      importId: importId,
      ownerId: ownerId,
      categoryId: categoryId,
    );
    if (wrongIdentity && result != null) {
      return VocabularyImportResult(
        importId: "other",
        accepted: result.accepted,
        duplicates: result.duplicates,
        rejected: result.rejected,
      );
    }
    return result;
  }
}

Future<void> pumps(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class Fixture {
  Fixture({drift.QueryInterceptor? interceptor})
    : db = AppDatabase(
        interceptor == null
            ? NativeDatabase.memory()
            : NativeDatabase.memory().interceptWith(interceptor),
      );
  final AppDatabase db;
  late Owners owners;
  late Repo repo;
  late VocabularyUseCases vocab;
  late ImportVocabulary importer;
  late AppDependencies deps;
  late String category, owner;
  int ids = 0;
  final features = RuntimeFeatureRegistry(
    const BuildFeatureRegistry.allEnabled(),
  );
  Future<void> init() async {
    addTearDown(features.dispose);
    addTearDown(db.close);
    owners = Owners(
      DriftLocalOwnerRepository(
        db,
        generateId: () => 'owner-${ids++}',
        nowUtc: () => DateTime.utc(2026),
      ),
    );
    repo = Repo(DriftVocabularyImportRepository(db));
    vocab = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(db),
      generateId: () => 'item-${ids++}',
      nowUtc: () => DateTime.utc(2026),
    );
    final c = await vocab.createCategory('Private');
    category = c.id;
    owner = c.ownerId;
    importer = makeImporter();
    final research = InertResearchDependencies(db);
    deps = AppDependencies(
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
      vocabulary: vocab,
    );
  }

  ImportVocabulary makeImporter() => ImportVocabulary(
    owners: owners,
    repository: repo,
    generateId: () => 'import-${ids++}',
    nowUtc: () => DateTime.utc(2026),
  );
  Widget app(Widget child, {GlobalKey<NavigatorState>? navigatorKey}) =>
      AppDependenciesScope(
        dependencies: deps,
        child: MaterialApp(navigatorKey: navigatorKey, home: child),
      );
  Widget screen({ImportVocabulary? source, String? selected}) =>
      AddMultipleWordsScreen(
        importer: source ?? importer,
        categoryId: selected ?? category,
        categoryName: 'Private',
        featureRegistry: features,
      );
  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await pumps(t);
    await db.close();
  }
}

void main() {
  testWidgets(
    'AZ cancellation followed by owner read failure is observed and recoverable',
    (t) async {
      final f = Fixture();
      await f.init();
      await t.pumpWidget(f.app(f.screen()));
      await pumps(t);
      f.repo.cancelBefore = () => f.owners.fail = true;
      await t.enterText(
        find.byKey(const ValueKey('import-rows-field')),
        'book,Book,noun',
      );
      await t.tap(find.byKey(const ValueKey('import-words')));
      await pumps(t);
      expect(t.takeException(), isNull);
      expect(await f.db.select(f.db.vocabularyImports).get(), isEmpty);
      expect(find.text('ลองใหม่'), findsOneWidget);
      f.owners.fail = false;
      f.repo.cancelBefore = null;
      await t.tap(find.text('ลองใหม่'));
      await pumps(t);
      expect(f.repo.writes, 1);
      await t.tap(find.byKey(const ValueKey('import-words')));
      await pumps(t);
      expect(f.repo.writes, 2);
      await f.close(t);
    },
  );

  test(
    'AZ canonical active owner retirement inside import transaction rolls back all rows',
    () async {
      final f = Fixture();
      await f.init();
      await f.db.customStatement(
        'CREATE TRIGGER az_retire AFTER INSERT ON vocabulary_words BEGIN UPDATE local_owners SET is_active=0; END',
      );
      Object? failure;
      try {
        await f.importer(
          categoryId: f.category,
          rows: const [
            {'word': 'book', 'meaning': 'Book', 'partOfSpeech': 'noun'},
          ],
          sourceName: 'manual-import',
          expectedOwnerId: f.owner,
        );
      } catch (e) {
        failure = e;
      }
      expect(failure, isNotNull);
      expect(await f.db.select(f.db.vocabularyWords).get(), isEmpty);
      expect(await f.db.select(f.db.vocabularyImports).get(), isEmpty);
      expect(await f.db.select(f.db.outboxOperations).get(), hasLength(1));
      expect(
        (await f.db.select(f.db.localOwners).get()).single.isActive,
        isTrue,
      );
    },
  );

  for (final boundary in ['owner', 'identity']) {
    test('AZ verification rechecks $boundary after receipt read', () async {
      final f = Fixture();
      await f.init();
      final result = await f.importer(
        categoryId: f.category,
        rows: const [
          {'word': 'book', 'meaning': 'Book', 'partOfSpeech': 'noun'},
        ],
        sourceName: 'manual-import',
        expectedOwnerId: f.owner,
      );
      f.repo.readGate = Completer<void>();
      f.repo.readEntered = Completer<void>();
      final pending = f.importer.verifyResult(
        result,
        expectedOwnerId: f.owner,
        categoryId: f.category,
      );
      await f.repo.readEntered!.future;
      if (boundary == 'owner') {
        await f.db.customUpdate('UPDATE local_owners SET is_active=0');
        await f.owners.getOrCreateActiveOwner();
      } else {
        f.repo.wrongIdentity = true;
      }
      f.repo.readGate!.complete();
      expect(await pending, isFalse);
      expect(f.repo.writes, 1);
    });
  }
  for (final boundary in ['dependency', 'selected']) {
    testWidgets(
      'AZ pending committed reconciliation hides draft after $boundary replacement',
      (t) async {
        final f = Fixture();
        await f.init();
        var source = f.importer;
        var selected = f.category;
        late StateSetter update;
        await t.pumpWidget(
          f.app(
            StatefulBuilder(
              builder: (c, set) {
                update = set;
                return f.screen(source: source, selected: selected);
              },
            ),
          ),
        );
        await pumps(t);
        f.repo.readGate = Completer<void>();
        f.repo.readEntered = Completer<void>();
        await t.enterText(
          find.byKey(const ValueKey('import-rows-field')),
          'book,private,noun',
        );
        await t.tap(find.byKey(const ValueKey('import-words')));
        await pumps(t);
        expect(f.repo.readEntered!.isCompleted, isTrue);
        update(() {
          if (boundary == 'dependency') {
            source = f.makeImporter();
          } else {
            selected = 'other';
          }
        });
        await t.pump();
        f.repo.readGate!.complete();
        await pumps(t);
        expect(find.byKey(const ValueKey('import-rows-field')), findsNothing);
        expect(f.repo.writes, 1);
        expect(await f.db.select(f.db.vocabularyWords).get(), hasLength(1));
        await f.close(t);
      },
    );
  }

  testWidgets('AZ retained preview rejects canonical owner change', (t) async {
    final f = Fixture();
    await f.init();
    await t.pumpWidget(f.app(f.screen()));
    await pumps(t);
    await t.enterText(
      find.byKey(const ValueKey('import-rows-field')),
      'book,private,noun',
    );
    await t.pump();
    final preview = t
        .widgetList<MenuActionBinding>(find.byType(MenuActionBinding))
        .firstWhere((w) => w.id == 'vocabulary/import-preview')
        .onForm!;
    await f.db.customUpdate('UPDATE local_owners SET is_active=0');
    await f.owners.getOrCreateActiveOwner();
    final result = await preview({});
    expect(result['status'], isNot('previewed'));
    expect(result.containsKey('totalRows'), isFalse);
    expect(f.repo.writes, 0);
    await f.close(t);
  });
  testWidgets('AZ retained back cannot pop a covering route', (t) async {
    final f = Fixture();
    await f.init();
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      f.app(const Scaffold(body: Text('root')), navigatorKey: nav),
    );
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => f.screen()));
    await pumps(t);
    final back = t
        .widget<IconButton>(
          find.descendant(
            of: find.byType(BackButton),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!;
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover')),
      ),
    );
    await pumps(t);
    back();
    await pumps(t);
    expect(find.text('cover'), findsOneWidget);
    await f.close(t);
  });
  for (final boundary in ['cover', 'pop', 'emergency']) {
    testWidgets('AZ in flight native import rolls back on $boundary', (
      t,
    ) async {
      final pause = WritePause('outbox_operations');
      final f = Fixture(interceptor: pause);
      await f.init();
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        f.app(const Scaffold(body: Text('root')), navigatorKey: nav),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => f.screen()),
      );
      await pumps(t);
      await t.enterText(
        find.byKey(const ValueKey('import-rows-field')),
        'book,Book,noun',
      );
      pause.armed = true;
      await t.tap(find.byKey(const ValueKey('import-words')));
      await pumps(t);
      expect(pause.entered.isCompleted, isTrue);
      if (boundary == 'cover') {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
      }
      if (boundary == 'pop') nav.currentState!.pop();
      if (boundary == 'emergency') {
        f.features.emergencyOff(Feature.vocabulary);
        f.features.clearOverride(Feature.vocabulary);
      }
      await t.pump();
      pause.release.complete();
      await pumps(t);
      expect(await f.db.select(f.db.vocabularyWords).get(), isEmpty);
      expect(await f.db.select(f.db.vocabularyImports).get(), isEmpty);
      expect(await f.db.select(f.db.vocabularyImportRows).get(), isEmpty);
      expect(await f.db.select(f.db.outboxOperations).get(), hasLength(1));
      if (boundary == 'cover') expect(find.text('cover'), findsOneWidget);
      await f.close(t);
    });
  }
  testWidgets(
    'AZ readback owner change keeps committed import without success or resubmission',
    (t) async {
      final f = Fixture();
      await f.init();
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        f.app(const Scaffold(body: Text('root')), navigatorKey: nav),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => f.screen()),
      );
      await pumps(t);
      f.repo.readGate = Completer<void>();
      await t.enterText(
        find.byKey(const ValueKey('import-rows-field')),
        'book,Book,noun',
      );
      await t.tap(find.byKey(const ValueKey('import-words')));
      await pumps(t);
      expect(f.repo.writes, 1);
      await f.db.customUpdate('UPDATE local_owners SET is_active=0');
      await f.owners.getOrCreateActiveOwner();
      f.repo.readGate!.complete();
      await pumps(t);
      expect(nav.currentState!.canPop(), isTrue);
      expect(find.text('บริบทเปลี่ยนแล้ว กรุณาปิดและเปิดใหม่'), findsOneWidget);
      expect(await f.db.select(f.db.vocabularyWords).get(), hasLength(1));
      expect(f.repo.writes, 1);
      await f.close(t);
    },
  );

  for (final boundary in [
    'owner',
    'category',
    'remove',
    'dependency',
    'selected',
    'cover',
    'tab',
    'lifecycle',
    'emergency',
    'dispose',
  ]) {
    testWidgets('AZ retained import and fill reject $boundary', (t) async {
      final f = Fixture();
      await f.init();
      var importer = f.importer;
      var selected = f.category;
      var visible = true;
      late StateSetter update;
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        f.app(
          StatefulBuilder(
            builder: (c, set) {
              update = set;
              return TickerMode(
                enabled: visible,
                child: f.screen(source: importer, selected: selected),
              );
            },
          ),
          navigatorKey: nav,
        ),
      );
      await pumps(t);
      await t.enterText(
        find.byKey(const ValueKey('import-rows-field')),
        'book,Private draft,noun',
      );
      await t.pump();
      final save = t
          .widget<FilledButton>(find.byKey(const ValueKey('import-words')))
          .onPressed!;
      final fill = t
          .widgetList<MenuActionBinding>(find.byType(MenuActionBinding))
          .firstWhere((w) => w.id == 'vocabulary/import-fill')
          .onForm!;
      if (boundary == 'owner') {
        await f.db.customUpdate('UPDATE local_owners SET is_active=0');
        await f.owners.getOrCreateActiveOwner();
      }
      if (boundary == 'category') {
        await f.vocab.renameCategory(f.category, 'changed');
      }
      if (boundary == 'remove') await f.vocab.deleteCategory(f.category);
      if (boundary == 'dependency') update(() => importer = f.makeImporter());
      if (boundary == 'selected') update(() => selected = 'missing');
      if (boundary == 'cover') {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
      }
      if (boundary == 'tab') update(() => visible = false);
      if (boundary == 'lifecycle') {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      if (boundary == 'emergency') {
        f.features.emergencyOff(Feature.vocabulary);
        f.features.clearOverride(Feature.vocabulary);
      }
      if (boundary == 'dispose') await t.pumpWidget(const SizedBox());
      await pumps(t);
      final result = await fill({'rows': 'replacement,Secret,noun'});
      await pumps(t);
      expect(result['status'], isNot('filled'));
      save();
      await pumps(t);
      expect(f.repo.writes, 0);
      expect(await f.db.select(f.db.vocabularyImports).get(), isEmpty);
      if ([
        'owner',
        'category',
        'remove',
        'dependency',
        'selected',
      ].contains(boundary)) {
        expect(find.text('Private draft'), findsNothing);
      }
      expect(t.takeException(), isNull);
      await f.close(t);
    });
  }
  testWidgets(
    'AZ initial owner failure offers explicit Thai retry retaining draft',
    (t) async {
      final f = Fixture();
      await f.init();
      f.owners.fail = true;
      await t.pumpWidget(f.app(f.screen()));
      await pumps(t);
      await t.enterText(
        find.byKey(const ValueKey('import-rows-field')),
        'book,partial,noun',
      );
      await t.pump();
      expect(find.text('ลองใหม่'), findsOneWidget);
      expect(f.repo.writes, 0);
      f.owners.fail = false;
      await t.tap(find.text('ลองใหม่'));
      await pumps(t);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('import-rows-field')))
            .controller!
            .text,
        'book,partial,noun',
      );
      expect(f.repo.writes, 0);
      await t.tap(find.byKey(const ValueKey('import-words')));
      await pumps(t);
      expect(f.repo.writes, 1);
      expect(await f.db.select(f.db.vocabularyWords).get(), hasLength(1));
      await f.close(t);
    },
  );
  testWidgets(
    'AZ early explicit import waits for owner and ignores duplicate submits',
    (t) async {
      final f = Fixture();
      await f.init();
      f.owners.gate = Completer<void>();
      await t.pumpWidget(f.app(f.screen()));
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('import-rows-field')),
        'book,Book,noun',
      );
      final save = t
          .widget<FilledButton>(find.byKey(const ValueKey('import-words')))
          .onPressed!;
      save();
      save();
      await t.pump();
      expect(f.repo.writes, 0);
      f.owners.gate!.complete();
      await pumps(t);
      expect(f.repo.writes, 1);
      expect(await f.db.select(f.db.vocabularyWords).get(), hasLength(1));
      await f.close(t);
    },
  );
  for (final committed in [false, true]) {
    testWidgets(
      'AZ ambiguous acknowledgement committed=$committed never resubmits automatically',
      (t) async {
        final f = Fixture();
        await f.init();
        f.repo.failBefore = !committed;
        f.repo.failAfter = committed;
        await t.pumpWidget(f.app(f.screen()));
        await pumps(t);
        await t.enterText(
          find.byKey(const ValueKey('import-rows-field')),
          'book,Book,noun',
        );
        await t.tap(find.byKey(const ValueKey('import-words')));
        await pumps(t);
        expect(f.repo.writes, 1);
        expect(find.text('ลองใหม่'), findsOneWidget);
        f.repo.failBefore = false;
        f.repo.failAfter = false;
        await t.tap(find.text('ลองใหม่'));
        await pumps(t);
        expect(f.repo.writes, 1);
        if (!committed) {
          await t.tap(find.byKey(const ValueKey('import-words')));
          await pumps(t);
          expect(f.repo.writes, 2);
        }
        expect(await f.db.select(f.db.vocabularyWords).get(), hasLength(1));
        await f.close(t);
      },
    );
  }
  testWidgets(
    'AZ native committed readback retry reads without importing again',
    (t) async {
      final f = Fixture();
      await f.init();
      f.repo.failRead = true;
      await t.pumpWidget(f.app(f.screen()));
      await pumps(t);
      await t.enterText(
        find.byKey(const ValueKey('import-rows-field')),
        'book,Book,noun',
      );
      await t.tap(find.byKey(const ValueKey('import-words')));
      await pumps(t);
      expect(f.repo.writes, 1);
      expect(find.text('ลองใหม่'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('import-words')))
            .onPressed,
        isNull,
      );
      f.repo.failRead = false;
      await t.tap(find.text('ลองใหม่'));
      await pumps(t);
      expect(f.repo.writes, 1);
      expect(await f.db.select(f.db.vocabularyImports).get(), hasLength(1));
      await f.close(t);
    },
  );
}
