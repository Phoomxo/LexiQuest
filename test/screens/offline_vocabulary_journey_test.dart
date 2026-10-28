import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(database.close);
      await tester.pump(const Duration(milliseconds: 1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
