import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/definition_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lexical_prompt_artifact_identity.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/definition_quiz_screen.dart';

import '../support/accessibility_semantics_test_support.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late LearningUseCases learning;
  var generatedId = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    generatedId = 0;
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'definition-screen-owner',
      nowUtc: () => DateTime.utc(2026, 8, 25, 9),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category:travel',
            ownerId: owner.id,
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await _insertWord(
      database,
      ownerId: owner.id,
      id: 'word:airport',
      spelling: 'airport',
      revision: 2,
      checksum: _coreChecksum(spelling: 'airport', meaning: 'ความหมาย'),
    );
    await _insertWord(
      database,
      ownerId: owner.id,
      id: 'word:station',
      spelling: 'station',
      revision: 3,
      checksum: _coreChecksum(spelling: 'station', meaning: 'ความหมาย'),
    );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'screen-${++generatedId}',
      nowUtc: () => DateTime.utc(2026, 8, 25, 10, 0, generatedId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'f08-screen'),
    );
  });

  tearDown(() => database.close());

  testWidgets(
    'f38 ultra review: definition feedback follows response semantics',
    (tester) => withAccessibilitySemantics(tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: DefinitionQuizScreen(
            categoryId: 'category:travel',
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: const DefinitionQuizModeAdapter(),
            loadLexicalWords: (_) async => _reviewedWords(),
          ),
        ),
      );

      await _pumpUntilFound(
        tester,
        find.text('A place where aircraft arrive and depart.'),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Correct answer: airport'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('definition-quiz-prompt')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('airport'));
      await tester.tap(find.text('airport'));
      await _pumpUntilFound(tester, find.text('Correct answer: airport'));

      final root = find.byType(DefinitionQuizScreen);
      expectInsideAccessibilityRole(
        scope: root,
        descendant: find.byKey(const ValueKey<String>('answer-feedback-panel')),
        role: AccessibilitySemanticRole.feedback,
        reason: 'committed definition feedback must own role 3',
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

      final attempts = await database.select(database.answerAttempts).get();
      expect(attempts, hasLength(1));
      final context = EvidenceContext.fromJson(
        (jsonDecode(attempts.single.evidenceContextJson)
                as Map<Object?, Object?>)
            .cast<String, Object?>(),
      );
      expect(context.evidenceClass, EvidenceClass.recognition);
      expect(context.hintLevel, 0);
      expect(
        context.contentRevision,
        _evidenceContentRevision(
          promptMode: 'definitionChoice',
          wordId: 'word:airport',
          spelling: 'airport',
          meaning: 'ความหมาย',
          revision: 2,
          artifactChecksum: _checksumB,
        ),
      );
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(tester.takeException(), isNull);
    }),
  );

  testWidgets(
    'f38 ultra review: definition skip owns prompt and response semantics',
    (tester) async {
      final words = _reviewedWords();
      final first = words.first.copyWith(
        contentReviewState: ContentReviewState.unreviewed,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DefinitionQuizScreen(
            categoryId: 'category:travel',
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: const DefinitionQuizModeAdapter(),
            loadLexicalWords: (_) async => <VocabularyWord>[first, words.last],
          ),
        ),
      );

      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('definition-quiz-skip')),
      );
      expect(
        find.bySemanticsLabel(
          'Skipped. The English definition has not been approved.',
        ),
        findsOneWidget,
      );
      final root = find.byType(DefinitionQuizScreen);
      expectInsideAccessibilityRole(
        scope: root,
        descendant: find.bySemanticsLabel(
          'Skipped. The English definition has not been approved.',
        ),
        role: AccessibilitySemanticRole.prompt,
        reason: 'a valid skip state still owns an announced prompt',
      );
      expectInsideAccessibilityRole(
        scope: root,
        descendant: find.byKey(const ValueKey<String>('definition-quiz-skip')),
        role: AccessibilitySemanticRole.responseAndInput,
        reason: 'the skip continuation is the available response action',
      );
      expect(await database.select(database.answerAttempts).get(), isEmpty);

      await tester.tap(
        find.byKey(const ValueKey<String>('definition-quiz-skip')),
      );
      await _pumpUntilFound(
        tester,
        find.text('A place where trains stop for passengers.'),
      );

      expect(await database.select(database.answerAttempts).get(), isEmpty);
    },
  );

  testWidgets('shell-owned hint is frozen as guided non-mastery evidence', (
    tester,
  ) async {
    const adapter = DefinitionQuizModeAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonModeHost(
          adapter: adapter,
          learning: learning,
          createController: (modeAdapter) =>
              UnifiedLessonController(learning: learning, adapter: modeAdapter),
          builder: (_) => DefinitionQuizScreen(
            categoryId: 'category:travel',
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: adapter,
            loadLexicalWords: (_) async => _reviewedWords(),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('Show strategy'));
    await tester.tap(find.text('Show strategy'));
    await tester.pump();
    expect(
      find.text('Use the part of speech and the definition wording as clues.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('airport'));
    await tester.tap(find.text('airport'));
    await _pumpUntilFound(tester, find.text('Correct answer: airport'));

    final attempt =
        (await database.select(database.answerAttempts).get()).single;
    final context = EvidenceContext.fromJson(
      (jsonDecode(attempt.evidenceContextJson) as Map<Object?, Object?>)
          .cast<String, Object?>(),
    );
    expect(context.evidenceClass, EvidenceClass.guidedPractice);
    expect(context.hintLevel, 1);
    expect(await database.select(database.srsStates).get(), isEmpty);
    expect(
      find.text('Show strategy'),
      findsOneWidget,
      reason: 'the shell resets hint state only after durable evidence',
    );
  });

  testWidgets('route terminal acceptance fences a retained definition answer', (
    tester,
  ) async {
    const adapter = DefinitionQuizModeAdapter();
    final controller = UnifiedLessonController(
      learning: learning,
      adapter: adapter,
    );
    addTearDown(controller.dispose);
    final routeLifecycle = UnifiedLessonRouteLifecycle(
      controller,
      learning,
      () => DateTime.utc(2026, 8, 25, 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonShell(
          controller: controller,
          routeLifecycle: routeLifecycle,
          builder: (_) => DefinitionQuizScreen(
            categoryId: 'category:travel',
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: adapter,
            loadLexicalWords: (_) async => _reviewedWords(),
          ),
        ),
      ),
    );

    final answer = find.byKey(
      const ValueKey<String>('definition-quiz-option-word:airport-airport'),
    );
    await _pumpUntilFound(tester, answer);
    final retained = tester.widget<FilledButton>(answer).onPressed!;

    final terminal = routeLifecycle.retire();
    retained();
    await tester.runAsync(() => terminal);
    await tester.pumpAndSettle();

    expect(routeLifecycle.acceptsOperations, isFalse);
    expect(await database.select(database.answerAttempts).get(), isEmpty);
    final sessions = await database.select(database.learningSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.state, 'abandoned');
  });

  testWidgets(
    'reviewed metadata load failure terminally closes its durable session',
    (tester) async {
      const adapter = DefinitionQuizModeAdapter();
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedLessonModeHost(
            adapter: adapter,
            learning: learning,
            createController: (modeAdapter) => UnifiedLessonController(
              learning: learning,
              adapter: modeAdapter,
            ),
            builder: (_) => DefinitionQuizScreen(
              categoryId: 'category:travel',
              learning: learning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: learning,
              ),
              modeAdapter: adapter,
              loadLexicalWords: (_) => Future<List<VocabularyWord>>.error(
                StateError('simulated lexical metadata failure'),
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(
        tester,
        find.text('Definition Quiz is unavailable. No learning data changed.'),
      );

      final sessions = await database.select(database.learningSessions).get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
    },
  );
}

List<VocabularyWord> _reviewedWords() => <VocabularyWord>[
  _lexicalWord(
    id: 'word:airport',
    spelling: 'airport',
    revision: 2,
    coreChecksum: _coreChecksum(spelling: 'airport', meaning: 'ความหมาย'),
    artifactChecksum: _checksumB,
    definition: 'A place where aircraft arrive and depart.',
  ),
  _lexicalWord(
    id: 'word:station',
    spelling: 'station',
    revision: 3,
    coreChecksum: _coreChecksum(spelling: 'station', meaning: 'ความหมาย'),
    artifactChecksum: _checksumA,
    definition: 'A place where trains stop for passengers.',
  ),
];

VocabularyWord _lexicalWord({
  required String id,
  required String spelling,
  required int revision,
  required String coreChecksum,
  required String artifactChecksum,
  required String definition,
}) => VocabularyWord(
  id: id,
  ownerId: 'owner:packaged',
  categoryId: 'category:travel',
  spelling: spelling,
  normalizedSpelling: normalizeVocabularyText(spelling),
  meaning: 'ความหมาย',
  normalizedMeaning: 'ความหมาย',
  partOfSpeech: 'noun',
  source: 'pack',
  isGlobal: true,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026, 8, 1),
  updatedAtUtc: DateTime.utc(2026, 8, 2),
  contentRevision: revision,
  contentChecksumSha256: coreChecksum,
  contentProvenance: ContentProvenance.packaged,
  contentReviewState: ContentReviewState.approved,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: RichLexicalMetadata(
    englishDefinition: definition,
    verifiedContentRevision: revision,
    verifiedArtifactChecksumSha256: artifactChecksum,
  ),
);

String _coreChecksum({required String spelling, required String meaning}) =>
    ContentQualityPolicy.vocabularyChecksumSha256(
      categoryId: 'category:travel',
      spelling: spelling,
      normalizedSpelling: spelling,
      meaning: meaning,
      normalizedMeaning: meaning,
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'pack',
      isGlobal: true,
    );

String _evidenceContentRevision({
  required String promptMode,
  required String wordId,
  required String spelling,
  required String meaning,
  required int revision,
  required String artifactChecksum,
}) {
  final checksum = LexicalPromptArtifactResolver.canonicalPromptChecksumSha256(
    promptMode: promptMode,
    coreChecksumSha256: _coreChecksum(spelling: spelling, meaning: meaning),
    verifiedArtifactRevision: revision,
    verifiedArtifactChecksumSha256: artifactChecksum,
  );
  return LexicalPromptArtifactResolver.formatEvidenceContentRevision(
    promptMode: promptMode,
    wordId: wordId,
    revision: revision,
    checksumSha256: checksum,
  );
}

Future<void> _insertWord(
  AppDatabase database, {
  required String ownerId,
  required String id,
  required String spelling,
  required int revision,
  required String checksum,
}) => database
    .into(database.vocabularyWords)
    .insert(
      VocabularyWordsCompanion.insert(
        id: id,
        ownerId: ownerId,
        categoryId: 'category:travel',
        spelling: spelling,
        normalizedSpelling: spelling,
        meaning: 'ความหมาย',
        normalizedMeaning: 'ความหมาย',
        partOfSpeech: 'noun',
        source: const Value<String>('pack'),
        isGlobal: const Value<bool>(true),
        contentRevision: Value(revision),
        contentChecksumSha256: Value(checksum),
        contentProvenance: Value(ContentProvenance.packaged.name),
        contentReviewState: Value(ContentReviewState.approved.name),
        contentPublicationState: Value(ContentPublicationState.published.name),
        createdAtUtcMs: 1,
        updatedAtUtcMs: 1,
      ),
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

const _checksumA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _checksumB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
