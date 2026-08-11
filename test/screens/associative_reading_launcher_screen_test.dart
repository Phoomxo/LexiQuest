import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_associative_learning_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/associative_reading_launcher_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/test_quest_use_cases.dart';

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late VocabularyUseCases vocabulary;
  late LearningUseCases learning;
  late DriftAssociativeLearningAdapter associativeLearning;
  late AppDependencies dependencies;
  var id = 0;

  AppDependencies makeDependencies({
    FeatureRegistry features = const BuildFeatureRegistry.fieldDefaults(),
  }) {
    return AppDependencies(
      initialRoute: AppRoute.home,
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      quest: testQuestUseCases(),
      features: features,
      database: database,
      localOwners: owners,
      vocabulary: vocabulary,
      learning: learning,
      associativeLearning: associativeLearning,
    );
  }

  setUp(() async {
    id = 0;
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'launcher-owner',
      nowUtc: () => DateTime.utc(2026, 8, 9, 11),
    );
    await owners.getOrCreateActiveOwner();
    vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'launcher-${++id}',
      nowUtc: () => DateTime.utc(2026, 8, 9, 11),
    );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'learning-${++id}',
      nowUtc: () => DateTime.utc(2026, 8, 9, 11),
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'associative-launcher-test',
      ),
    );
    associativeLearning = DriftAssociativeLearningAdapter(database);
    dependencies = makeDependencies();
  });

  Future<void> pump(WidgetTester tester, Widget home) {
    return tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: MaterialApp(home: home),
      ),
    );
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 100,
  }) async {
    for (var index = 0; index < maxPumps; index++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    fail('Widget did not appear after $maxPumps bounded pumps: $finder');
  }

  Future<void> seedWords(int count) async {
    final category = await vocabulary.createCategory('Reading');
    for (var index = 0; index < count; index++) {
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'word-$index',
          meaning: 'meaning-$index',
          partOfSpeech: 'noun',
          cefrLevel: 'B1',
        ),
      );
    }
  }

  Future<void> closeHarness(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'visible reading feature reaches launcher and injects up to 10 owned words',
    (tester) async {
      await tester.runAsync(() => seedWords(12));
      await pump(tester, const ChooseModeScreen());
      await tester.pump();

      expect(find.text('Associative Reading'), findsOneWidget);
      await tester.tap(find.text('Associative Reading'));
      await pumpUntilFound(tester, find.text('Start reading'));
      expect(find.byType(AssociativeReadingLauncherScreen), findsOneWidget);
      expect(find.text('Start reading'), findsOneWidget);

      await tester.tap(find.text('Start reading'));
      await pumpUntilFound(
        tester,
        find.byType(AssociativeReadingSessionScreen),
      );
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

      final session = tester.widget<AssociativeReadingSessionScreen>(
        find.byType(AssociativeReadingSessionScreen),
      );
      final activeOwner = (await tester.runAsync(
        owners.getOrCreateActiveOwner,
      ))!;
      final ownedWords = (await tester.runAsync(
        () => vocabulary.getGameWords(limit: 100),
      ))!;
      final ownedIds = ownedWords.map((word) => word.id).toSet();
      expect(session.targetWords, hasLength(10));
      expect(session.targetWordIds, hasLength(10));
      expect(session.targetWordIds!.values, everyElement(isIn(ownedIds)));
      expect(session.targetWordIds!.values, hasLength(10));
      expect(
        ownedWords.map((word) => word.ownerId),
        everyElement(activeOwner.id),
      );
      expect(identical(session.learning, learning), isTrue);
      expect(
        identical(session.associativeLearning, associativeLearning),
        isTrue,
      );
      expect(session.cefrLevel, 'B1');
      expect(
        session.documentId,
        matches(RegExp(r'^associative-reading:[0-9a-f]{64}$')),
      );
      expect(session.documentRevision, inInclusiveRange(1, 4503599627370496));
      await closeHarness(tester);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  for (final testCase in const [
    (
      label: 'baseline',
      firstRevision: 5,
      secondRevision: 1,
      reverse: false,
      firstCefr: null,
      expectedCefr: 'A2',
    ),
    (
      label: 'content revision',
      firstRevision: 5,
      secondRevision: 2,
      reverse: false,
      firstCefr: null,
      expectedCefr: 'A2',
    ),
    (
      label: 'reversed order',
      firstRevision: 5,
      secondRevision: 2,
      reverse: true,
      firstCefr: null,
      expectedCefr: 'A2',
    ),
    (
      label: 'effective CEFR revision',
      firstRevision: 6,
      secondRevision: 2,
      reverse: false,
      firstCefr: 'C1',
      expectedCefr: 'C1',
    ),
  ]) {
    testWidgets('document identity and revision track ordered word revisions: '
        '${testCase.label}', (tester) async {
      try {
        final seeded = await tester
            .runAsync<({String firstId, String secondId})>(() async {
              final category = await vocabulary.createCategory('Identity');
              final first = await vocabulary.createWord(
                CreateWordCommand(
                  categoryId: category.id,
                  spelling: 'alpha',
                  meaning: 'first meaning',
                  partOfSpeech: 'noun',
                ),
              );
              final second = await vocabulary.createWord(
                CreateWordCommand(
                  categoryId: category.id,
                  spelling: 'beta',
                  meaning: 'second meaning',
                  partOfSpeech: 'noun',
                ),
              );
              await (database.update(
                database.vocabularyWords,
              )..where((row) => row.id.equals(first.id))).write(
                VocabularyWordsCompanion(
                  localRevision: Value(testCase.firstRevision),
                  cefrLevel: Value(testCase.firstCefr),
                  normalizedSpelling: Value(
                    testCase.reverse ? 'z-alpha' : 'alpha',
                  ),
                ),
              );
              await (database.update(
                database.vocabularyWords,
              )..where((row) => row.id.equals(second.id))).write(
                VocabularyWordsCompanion(
                  meaning: Value(
                    testCase.secondRevision > 1
                        ? 'second meaning revised'
                        : 'second meaning',
                  ),
                  normalizedMeaning: Value(
                    testCase.secondRevision > 1
                        ? 'second meaning revised'
                        : 'second meaning',
                  ),
                  localRevision: Value(testCase.secondRevision),
                  normalizedSpelling: Value(
                    testCase.reverse ? 'a-beta' : 'beta',
                  ),
                ),
              );
              return (firstId: first.id, secondId: second.id);
            });
        final firstId = seeded!.firstId;
        final secondId = seeded.secondId;

        await pump(tester, const AssociativeReadingLauncherScreen());
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await pumpUntilFound(
          tester,
          find.byType(AssociativeReadingSessionScreen),
        );
        final session = tester.widget<AssociativeReadingSessionScreen>(
          find.byType(AssociativeReadingSessionScreen),
        );
        final revisions = <String, int>{
          firstId: testCase.firstRevision,
          secondId: testCase.secondRevision,
        };
        final orderedPairs = <List<Object>>[
          for (final word in session.targetWords)
            [
              session.targetWordIds![word]!,
              revisions[session.targetWordIds![word]]!,
            ],
        ];
        final digest = sha256
            .convert(utf8.encode(jsonEncode(orderedPairs)))
            .toString();
        final expectedRevision =
            int.parse(digest.substring(0, 13), radix: 16) + 1;

        expect(
          session.targetWords,
          testCase.reverse ? const ['beta', 'alpha'] : const ['alpha', 'beta'],
        );
        expect(session.cefrLevel, testCase.expectedCefr);
        expect(session.documentId, 'associative-reading:$digest');
        expect(session.documentRevision, expectedRevision);
      } finally {
        await closeHarness(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 20)));
  }

  testWidgets('hidden reading feature omits the reading tile', (tester) async {
    dependencies = makeDependencies(
      features: const BuildFeatureRegistry({
        Feature.reading: FeatureState.hidden,
      }),
    );
    await pump(tester, const ChooseModeScreen());
    await tester.pump();

    expect(find.text('Associative Reading'), findsNothing);
    await closeHarness(tester);
  });

  testWidgets(
    'duplicate display spellings keep one target with one durable word ID',
    (tester) async {
      await tester.runAsync(() async {
        final firstCategory = await vocabulary.createCategory('First');
        final secondCategory = await vocabulary.createCategory('Second');
        for (final category in [firstCategory, secondCategory]) {
          await vocabulary.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: 'echo',
              meaning: category.name,
              partOfSpeech: 'noun',
              cefrLevel: 'A2',
            ),
          );
        }
      });
      await pump(tester, const AssociativeReadingLauncherScreen());
      await pumpUntilFound(tester, find.text('Start reading'));

      await tester.tap(find.text('Start reading'));
      await pumpUntilFound(
        tester,
        find.byType(AssociativeReadingSessionScreen),
      );
      final session = tester.widget<AssociativeReadingSessionScreen>(
        find.byType(AssociativeReadingSessionScreen),
      );

      expect(session.targetWords, hasLength(session.targetWordIds!.length));
      expect(session.targetWords, hasLength(1));
      expect(session.targetWordIds, contains('echo'));
      await closeHarness(tester);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'empty vocabulary action opens vocabulary creation',
    (tester) async {
      await pump(tester, const AssociativeReadingLauncherScreen());
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('associative-reading-empty')),
      );

      expect(
        find.byKey(const ValueKey('associative-reading-empty')),
        findsOneWidget,
      );
      expect(find.text('Create vocabulary'), findsOneWidget);
      await tester.tap(find.text('Create vocabulary'));
      await pumpUntilFound(tester, find.byType(CategoriesPage));

      expect(find.byType(CategoriesPage), findsOneWidget);
      await closeHarness(tester);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
