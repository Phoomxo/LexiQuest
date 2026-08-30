import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/matching_mode_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/accessibility_semantics_test_support.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late LearningUseCases learning;
  var generatedId = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'matching-screen-owner',
      nowUtc: () => DateTime.utc(2026, 8, 25, 9),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database.customStatement(
      'INSERT INTO vocabulary_categories '
      '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
      "VALUES ('category:travel', ?, 'Travel', 'travel', 1, 1)",
      <Object?>[owner.id],
    );
    for (final entry in const <(String, String, String)>[
      ('word:airport', 'airport', 'place for flights'),
      ('word:station', 'station', 'place for trains'),
      ('word:market', 'market', 'place to buy goods'),
    ]) {
      await database.customStatement(
        'INSERT INTO vocabulary_words '
        '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
        'normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) '
        "VALUES (?, ?, 'category:travel', ?, ?, ?, ?, 'noun', 1, 1)",
        <Object?>[entry.$1, owner.id, entry.$2, entry.$2, entry.$3, entry.$3],
      );
    }
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'matching-screen-${++generatedId}',
      nowUtc: () => DateTime.utc(2026, 8, 25, 10, 0, generatedId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-screen'),
    );
  });

  tearDown(() => database.close());

  testWidgets(
    'f38 ultra review: matching feedback follows response semantics',
    (tester) => withAccessibilitySemantics(tester, () async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: _screen(learning),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('matching-word-word:airport')),
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('0 of 3 pairs matched'), findsOneWidget);
      expect(find.bySemanticsLabel('Word airport'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Meaning place for flights'),
        findsOneWidget,
      );
      expect(find.text('Correct answer: place for flights'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('matching-word-word:airport')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('matching-word-word:airport')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('matching-meaning-word:airport')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('matching-meaning-word:airport')),
      );
      await _pumpUntilFound(
        tester,
        find.text('Correct answer: place for flights'),
      );

      final root = find.byType(MatchingModeScreen);
      expectInsideAccessibilityRole(
        scope: root,
        descendant: find.byKey(const ValueKey<String>('answer-feedback-panel')),
        role: AccessibilitySemanticRole.feedback,
      );
      expectRenderedAccessibilityTraversal(
        tester,
        scope: root,
        roles: const <AccessibilitySemanticRole>[
          AccessibilitySemanticRole.prompt,
          AccessibilitySemanticRole.responseAndInput,
          AccessibilitySemanticRole.feedback,
          AccessibilitySemanticRole.navigation,
        ],
      );

      final attempt =
          (await database.select(database.answerAttempts).get()).single;
      expect(attempt.promptMode, 'matchingPair');
      expect(
        _context(attempt.evidenceContextJson).evidenceClass,
        EvidenceClass.recognition,
      );
      expect(tester.takeException(), isNull);
    }),
  );

  testWidgets('explicit support is guided practice and never mastery', (
    tester,
  ) async {
    const adapter = MatchingModeAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonModeHost(
          adapter: adapter,
          learning: learning,
          createController: (modeAdapter) =>
              UnifiedLessonController(learning: learning, adapter: modeAdapter),
          builder: (_) => _screen(learning, adapter: adapter),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('Show strategy'));
    await tester.tap(find.text('Show strategy'));
    await tester.tap(
      find.byKey(const ValueKey<String>('matching-word-word:airport')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('matching-meaning-word:airport')),
    );
    await _pumpUntilFound(
      tester,
      find.text('Correct answer: place for flights'),
    );

    final attempt =
        (await database.select(database.answerAttempts).get()).single;
    final context = _context(attempt.evidenceContextJson);
    expect(context.evidenceClass, EvidenceClass.guidedPractice);
    expect(context.hintLevel, 1);
    expect(await database.select(database.srsStates).get(), isEmpty);
  });

  testWidgets('timeout closes once without inventing unanswered evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatchingModeScreen(
          categoryId: 'category:travel',
          learning: learning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
          modeAdapter: const MatchingModeAdapter(),
          timeLimit: const Duration(seconds: 1),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('matching-word-word:airport')),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(ScoreScreen), findsOneWidget);
    expect(await database.select(database.answerAttempts).get(), isEmpty);
    final sessions = await database.select(database.learningSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.state, 'completed');
  });

  testWidgets('production screen resumes its checkpointed session', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: _screen(learning)));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('matching-word-word:airport')),
    );
    final original =
        (await database.select(database.learningSessions).get()).single;

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await (database.update(
      database.vocabularyWords,
    )..where((row) => row.id.equals('word:airport'))).write(
      const VocabularyWordsCompanion(
        meaning: Value('changed after checkpoint'),
        normalizedMeaning: Value('changed after checkpoint'),
        isDeleted: Value(true),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: _screen(learning, timeLimit: const Duration(minutes: 20)),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('matching-word-word:airport')),
    );
    expect(find.text('place for flights'), findsOneWidget);
    expect(find.textContaining('20 min'), findsNothing);
    expect(find.textContaining('Time remaining:'), findsOneWidget);
    final sessions = await database.select(database.learningSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.id, original.id);
    expect(sessions.single.activityType, MatchingModeAdapter.activityType);
  });

  testWidgets('default implemented-off registry cannot initialize the screen', (
    tester,
  ) async {
    final features = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    addTearDown(features.dispose);
    final research = InertResearchDependencies(database);
    final evidence = CurrentActivityEvidenceAdapter(learning: learning);
    final dependencies = AppDependencies(
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
      experiments: research.experiments,
      consents: research.consents,
      experimentAssignments: research.experimentAssignments,
      assignedLearningEventContext: research.assignedLearningEventContext,
      evidencePolicyRolloutModeProvider:
          research.evidencePolicyRolloutModeProvider,
      features: features,
      database: database,
      localOwners: owners,
      learning: learning,
      currentActivityEvidence: evidence,
      lessonModes: buildLessonModeRegistry(),
    );

    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: const MaterialApp(home: MatchingModeScreen()),
      ),
    );
    await _pumpUntilEither(
      tester,
      find.text('Matching is unavailable. No learning data changed.'),
      find.byKey(const ValueKey<String>('matching-word-word:airport')),
    );

    expect(
      find.text('Matching is unavailable. No learning data changed.'),
      findsOneWidget,
    );
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  testWidgets(
    'live off during delayed initialization compensates once and fences callbacks',
    (tester) async {
      const adapter = MatchingModeAdapter();
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      final controller = UnifiedLessonController(
        learning: learning,
        adapter: adapter,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      Future<QuizSession> delayedLoad() async {
        final session = await learning.startQuiz(categoryId: 'category:travel');
        entered.complete();
        await release.future;
        return session;
      }

      final research = InertResearchDependencies(database);
      final evidence = CurrentActivityEvidenceAdapter(learning: learning);
      final dependencies = AppDependencies(
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
        experiments: research.experiments,
        consents: research.consents,
        experimentAssignments: research.experimentAssignments,
        assignedLearningEventContext: research.assignedLearningEventContext,
        evidencePolicyRolloutModeProvider:
            research.evidencePolicyRolloutModeProvider,
        features: features,
        database: database,
        localOwners: owners,
        learning: learning,
        currentActivityEvidence: evidence,
      );

      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(
            home: UnifiedLessonModeHost(
              adapter: adapter,
              feature: Feature.quiz,
              featureRegistry: features,
              learning: learning,
              createController: (_) => controller,
              builder: (_) => MatchingModeScreen(
                learning: learning,
                evidenceAdapter: evidence,
                modeAdapter: adapter,
                loadSession: delayedLoad,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(MatchingModeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (var pump = 0; pump < 50 && !entered.isCompleted; pump += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(entered.isCompleted, isTrue);
      features.emergencyOff(Feature.quiz);
      release.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(MatchingModeScreen), findsNothing);
      expect(controller.state.status, LessonSessionStatus.abandoned);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      final sessions = await database.select(database.learningSessions).get();
      expect(sessions.where((row) => row.state == 'active'), isEmpty);
      expect(sessions.where((row) => row.state == 'abandoned'), hasLength(1));
    },
  );
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

Widget _screen(
  LearningUseCases learning, {
  MatchingModeAdapter adapter = const MatchingModeAdapter(),
  Duration timeLimit = const Duration(minutes: 10),
}) => MatchingModeScreen(
  categoryId: 'category:travel',
  learning: learning,
  evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
  modeAdapter: adapter,
  timeLimit: timeLimit,
);

EvidenceContext _context(String json) => EvidenceContext.fromJson(
  (jsonDecode(json) as Map<Object?, Object?>).cast<String, Object?>(),
);

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _pumpUntilEither(
  WidgetTester tester,
  Finder first,
  Finder second,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (first.evaluate().isNotEmpty || second.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $first or $second');
}
