import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
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
  late RuntimeFeatureRegistry registry;
  var withdrawOnCommit = false;
  late DateTime nowUtc;
  late int idCounter;
  late Directory offlineDirectory;
  late OfflineContentManager offlineContent;

  setUp(() async {
    withdrawOnCommit = false;
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
      onLocalMutation: () {
        if (withdrawOnCommit) registry.emergencyOff(Feature.vocabulary);
      },
    );
    final research = InertResearchDependencies(database);
    offlineContent = VerifiedOfflineContentManager(
      repository: DriftOfflineContentRepository(database),
      adapters: const <OfflineContentDownloadAdapter>[],
      removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
      rootDirectory: () async => offlineDirectory,
      nowUtc: () => nowUtc,
    );
    registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
    );
    addTearDown(registry.dispose);
    dependencies = AppDependencies(
      features: const BuildFeatureRegistry.fieldDefaults(),
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
        onLocalMutation: () {
          if (withdrawOnCommit) registry.emergencyOff(Feature.vocabulary);
        },
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
          home: ProductionFeatureGate(
            feature: Feature.vocabulary,
            registry: registry,
            builder: (_) => CategoriesPage(featureRegistry: registry),
          ),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<T> pumpResult<T>(WidgetTester tester, Future<T> future) async {
    T? result;
    Object? error;
    var done = false;
    future.then(
      (value) {
        result = value;
        done = true;
      },
      onError: (Object value) {
        error = value;
        done = true;
      },
    );
    for (var i = 0; i < 100 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    if (error != null) throw error!;
    expect(done, isTrue, reason: 'bounded database operation');
    return result as T;
  }

  for (final deleteWord in [false, true]) {
    testWidgets(
      'withdrawal fences pending ${deleteWord ? "word deletion" : "category creation"} dialog',
      (tester) async {
        try {
          final category = await tester.runAsync(
            () => dependencies.vocabulary!.createCategory('Travel'),
          );
          if (deleteWord) {
            await tester.runAsync(
              () => dependencies.vocabulary!.createWord(
                CreateWordCommand(
                  categoryId: category!.id,
                  spelling: 'station',
                  meaning: 'สถานี',
                  partOfSpeech: 'noun',
                ),
              ),
            );
          }
          await pumpCategories(tester);
          await pumpUntilFound(tester, find.text('Travel'));
          if (deleteWord) {
            await tester.tap(find.text('Travel'));
            await finishRouteTransition(tester);
            await pumpUntilFound(tester, find.text('station'));
            await tester.tap(find.byTooltip('ลบคำศัพท์'));
          } else {
            await tester.tap(find.byKey(const ValueKey('add-category')));
          }
          await finishRouteTransition(tester);
          if (!deleteWord) {
            await tester.enterText(
              find.byKey(const ValueKey('category-name-field')),
              'After withdrawal',
            );
          }
          final before = await pumpResult(
            tester,
            database.select(database.outboxOperations).get(),
          );
          registry.emergencyOff(Feature.vocabulary);
          await tester.tap(
            deleteWord
                ? find.widgetWithText(FilledButton, 'ลบ')
                : find.byKey(const ValueKey('save-category')),
          );
          await tester.pump();
          final after = await pumpResult(
            tester,
            database.select(database.outboxOperations).get(),
          );
          expect(after.length, before.length);
          final categories = await pumpResult(
            tester,
            database.select(database.vocabularyCategories).get(),
          );
          expect(categories, hasLength(1));
          if (deleteWord) {
            final words = await pumpResult(
              tester,
              database.select(database.vocabularyWords).get(),
            );
            expect(words.single.isDeleted, isFalse);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpResult(tester, database.close());
        }
      },
    );
  }

  for (final importing in [false, true]) {
    for (final withdrawal in ['enabled', 'before', 'committed']) {
      final withdraw = withdrawal == 'before';
      testWidgets(
        '${importing ? "import" : "editor"} descendant $withdrawal callback',
        (tester) async {
          try {
            await tester.runAsync(
              () => dependencies.vocabulary!.createCategory('Travel'),
            );
            await pumpCategories(tester);
            await pumpUntilFound(tester, find.text('Travel'));
            await tester.tap(find.text('Travel'));
            await finishRouteTransition(tester);
            await pumpUntilFound(
              tester,
              find.byKey(const ValueKey('add-word')),
            );
            await tester.tap(
              importing
                  ? find.byTooltip('นำเข้าคำศัพท์')
                  : find.byKey(const ValueKey('add-word')),
            );
            await finishRouteTransition(tester);
            final button = find.byKey(
              ValueKey(importing ? 'import-words' : 'save-word'),
            );
            await pumpUntilFound(tester, button);
            if (importing) {
              await tester.enterText(
                find.byKey(const ValueKey('import-rows-field')),
                'station,สถานี,noun',
              );
            } else {
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
            }
            final submit = tester.widget<FilledButton>(button).onPressed!;
            final before = await pumpResult(
              tester,
              database
                  .customSelect('SELECT COUNT(*) AS n FROM outbox_operations')
                  .getSingle(),
            );
            withdrawOnCommit = withdrawal == 'committed';
            if (withdraw) registry.emergencyOff(Feature.vocabulary);
            // Invoke before rebuild as well: admission must use the current registry.
            submit();
            await pumpResult(
              tester,
              Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump();
            final words = await pumpResult(
              tester,
              database
                  .customSelect('SELECT COUNT(*) AS n FROM vocabulary_words')
                  .getSingle(),
            );
            final after = await pumpResult(
              tester,
              database
                  .customSelect('SELECT COUNT(*) AS n FROM outbox_operations')
                  .getSingle(),
            );
            expect(words.read<int>('n'), withdraw ? 0 : 1);
            expect(
              after.read<int>('n') - before.read<int>('n'),
              withdraw ? 0 : greaterThan(0),
            );
            if (withdraw) {
              expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
              submit();
              await tester.pump();
              await tester.pumpWidget(const SizedBox.shrink());
              submit();
              await tester.pump();
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await pumpResult(tester, database.close());
          }
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
}
