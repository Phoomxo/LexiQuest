import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late LearningUseCases learning;
  var generatedId = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'cloze-screen-owner',
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
      owner.id,
      'word:airport',
      'airport',
      2,
      _checksumB,
    );
    await _insertWord(
      database,
      owner.id,
      'word:station',
      'station',
      3,
      _checksumA,
    );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'screen-${++generatedId}',
      nowUtc: () => DateTime.utc(2026, 8, 25, 10, 0, generatedId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'f09-screen'),
    );
  });

  tearDown(() => database.close());

  testWidgets(
    'selected cloze is responsive at 200 percent and UI only presents feedback',
    (tester) async {
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

      await _pumpUntilFound(tester, find.text('The _____ is busy.'));
      expect(tester.takeException(), isNull);
      expect(find.text('Correct answer: airport'), findsNothing);

      final option = find.byKey(
        const ValueKey<String>('cloze-option-word:airport-airport'),
      );
      expect(
        option,
        findsNothing,
        reason: 'answers stay hidden before mode choice',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('cloze-mode-selected')),
      );
      await tester.pump();
      await tester.ensureVisible(option);
      await tester.tap(option);
      await _pumpUntilFound(tester, find.text('Correct answer: airport'));

      final attempt =
          (await database.select(database.answerAttempts).get()).single;
      final context = _context(attempt.evidenceContextJson);
      expect(attempt.promptMode, 'clozeSelected');
      expect(context.evidenceClass, EvidenceClass.recognition);
      expect(context.hintLevel, 0);
      expect(
        context.contentRevision,
        'lexical-cloze:word:airport@2:$_checksumB',
      );
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('typed cloze is independent recall until a shell hint is used', (
    tester,
  ) async {
    const adapter = ClozeModeAdapter();
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
    await _pumpUntilFound(tester, find.text('The _____ is busy.'));
    expect(
      find.byKey(const ValueKey<String>('cloze-option-word:airport-airport')),
      findsNothing,
      reason: 'typed recall cannot be exposed to selected-mode answers',
    );
    await tester.tap(find.byKey(const ValueKey<String>('cloze-mode-typed')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('cloze-typed-answer')),
      ' AIRPORT ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('cloze-submit-typed')));
    await _pumpUntilFound(tester, find.text('Correct answer: airport'));

    var attempts = await database.select(database.answerAttempts).get();
    expect(attempts, hasLength(1));
    expect(attempts.single.promptMode, 'clozeTyped');
    expect(
      _context(attempts.single.evidenceContextJson).evidenceClass,
      EvidenceClass.independentRecall,
    );
    expect(await database.select(database.srsStates).get(), hasLength(1));

    await tester.tap(find.byKey(const ValueKey<String>('cloze-next')));
    await _pumpUntilFound(tester, find.text('The _____ closes.'));
    await tester.tap(find.text('Show strategy'));
    await tester.tap(find.byKey(const ValueKey<String>('cloze-mode-typed')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('cloze-typed-answer')),
      'station',
    );
    await tester.tap(find.byKey(const ValueKey<String>('cloze-submit-typed')));
    await _pumpUntilFound(tester, find.text('Correct answer: station'));

    attempts = await database.select(database.answerAttempts).get();
    expect(attempts, hasLength(2));
    final guided = _context(attempts.last.evidenceContextJson);
    expect(guided.evidenceClass, EvidenceClass.guidedPractice);
    expect(guided.hintLevel, 1);
    expect(await database.select(database.srsStates).get(), hasLength(1));
  });

  testWidgets('unreviewed example is announced and skipped without evidence', (
    tester,
  ) async {
    final words = _reviewedWords();
    final first = words.first.copyWith(
      contentReviewState: ContentReviewState.unreviewed,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FillInTheBlanksScreen(
          categoryId: 'category:travel',
          learning: learning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
          modeAdapter: const ClozeModeAdapter(),
          loadLexicalWords: (_) async => <VocabularyWord>[first, words.last],
        ),
      ),
    );

    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('cloze-skip')),
    );
    expect(
      find.bySemanticsLabel(
        'Skipped. The cloze example has not been approved.',
      ),
      findsOneWidget,
    );
    expect(await database.select(database.answerAttempts).get(), isEmpty);
    await tester.tap(find.byKey(const ValueKey<String>('cloze-skip')));
    await _pumpUntilFound(tester, find.text('The _____ closes.'));
    expect(await database.select(database.answerAttempts).get(), isEmpty);
  });

  testWidgets('route terminal acceptance fences a retained cloze callback', (
    tester,
  ) async {
    const adapter = ClozeModeAdapter();
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
          builder: (_) => _screen(learning, adapter: adapter),
        ),
      ),
    );
    final option = find.byKey(
      const ValueKey<String>('cloze-option-word:airport-airport'),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('cloze-mode-selected')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('cloze-mode-selected')));
    await tester.pump();
    expect(option, findsOneWidget);
    final retained = tester.widget<FilledButton>(option).onPressed!;

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
    'terminal claim during delayed metadata load never attaches review',
    (tester) async {
      const adapter = ClozeModeAdapter();
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
      final loaderEntered = Completer<void>();
      final loaderRelease = Completer<List<VocabularyWord>>();
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedLessonShell(
            controller: controller,
            routeLifecycle: routeLifecycle,
            builder: (_) => FillInTheBlanksScreen(
              categoryId: 'category:travel',
              learning: learning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: learning,
              ),
              modeAdapter: adapter,
              loadLexicalWords: (_) {
                if (!loaderEntered.isCompleted) loaderEntered.complete();
                return loaderRelease.future;
              },
            ),
          ),
        ),
      );
      for (var pump = 0; pump < 50 && !loaderEntered.isCompleted; pump += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(loaderEntered.isCompleted, isTrue);

      final terminal = routeLifecycle.retire();
      loaderRelease.complete(_reviewedWords());
      await tester.runAsync(() => terminal);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(routeLifecycle.acceptsOperations, isFalse);
      expect(
        find.byKey(const ValueKey<String>('cloze-input-mode')),
        findsNothing,
      );
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      final sessions = await database.select(database.learningSessions).get();
      expect(sessions, hasLength(1));
      expect(sessions.single.state, 'abandoned');
    },
  );

  testWidgets('metadata load failure terminally abandons the durable session', (
    tester,
  ) async {
    const adapter = ClozeModeAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonModeHost(
          adapter: adapter,
          learning: learning,
          createController: (modeAdapter) =>
              UnifiedLessonController(learning: learning, adapter: modeAdapter),
          builder: (_) => FillInTheBlanksScreen(
            categoryId: 'category:travel',
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: adapter,
            loadLexicalWords: (_) => Future<List<VocabularyWord>>.error(
              StateError('simulated metadata failure'),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.text('Cloze Test is unavailable. No learning data changed.'),
    );
    final sessions = await database.select(database.learningSessions).get();
    expect(sessions.where((session) => session.state == 'active'), isEmpty);
    expect(
      sessions.where((session) => session.state == 'abandoned'),
      hasLength(1),
    );
  });
}

Widget _screen(LearningUseCases learning, {ClozeModeAdapter? adapter}) =>
    FillInTheBlanksScreen(
      categoryId: 'category:travel',
      learning: learning,
      evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
      modeAdapter: adapter ?? const ClozeModeAdapter(),
      loadLexicalWords: (_) async => _reviewedWords(),
    );

EvidenceContext _context(String json) => EvidenceContext.fromJson(
  (jsonDecode(json) as Map<Object?, Object?>).cast<String, Object?>(),
);

List<VocabularyWord> _reviewedWords() => <VocabularyWord>[
  _lexicalWord(
    id: 'word:airport',
    spelling: 'airport',
    revision: 2,
    checksum: _checksumB,
    example: 'The airport is busy.',
  ),
  _lexicalWord(
    id: 'word:station',
    spelling: 'station',
    revision: 3,
    checksum: _checksumA,
    example: 'The station closes.',
  ),
];

VocabularyWord _lexicalWord({
  required String id,
  required String spelling,
  required int revision,
  required String checksum,
  required String example,
}) => VocabularyWord(
  id: id,
  ownerId: 'owner:packaged',
  categoryId: 'category:travel',
  spelling: spelling,
  normalizedSpelling: normalizeVocabularyText(spelling),
  meaning: 'meaning',
  normalizedMeaning: 'meaning',
  partOfSpeech: 'noun',
  source: 'pack',
  isGlobal: true,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026, 8, 1),
  updatedAtUtc: DateTime.utc(2026, 8, 2),
  contentRevision: revision,
  contentChecksumSha256: checksum,
  contentProvenance: ContentProvenance.packaged,
  contentReviewState: ContentReviewState.approved,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: RichLexicalMetadata(
    verifiedArtifactChecksumSha256: checksum,
    examples: <String>[example],
  ),
);

Future<void> _insertWord(
  AppDatabase database,
  String ownerId,
  String id,
  String spelling,
  int revision,
  String checksum,
) => database
    .into(database.vocabularyWords)
    .insert(
      VocabularyWordsCompanion.insert(
        id: id,
        ownerId: ownerId,
        categoryId: 'category:travel',
        spelling: spelling,
        normalizedSpelling: spelling,
        meaning: 'meaning',
        normalizedMeaning: 'meaning',
        partOfSpeech: 'noun',
        contentRevision: Value(revision),
        contentChecksumSha256: Value(checksum),
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
