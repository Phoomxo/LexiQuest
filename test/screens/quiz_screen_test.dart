import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late LearningUseCases learning;
  var id = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    id = 0;
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => DateTime.utc(2026, 7, 30, 10),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: owner.id,
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-1',
            ownerId: owner.id,
            categoryId: 'category-1',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'สถานี',
            normalizedMeaning: 'สถานี',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++id}',
      nowUtc: () => DateTime.utc(2026, 7, 30, 10, 1),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
  });

  tearDown(() => database.close());

  testWidgets('answer is durable before score screen is shown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(categoryId: 'category-1', learning: learning),
      ),
    );
    await _pumpUntilFound(tester, find.text('station'));

    expect(find.text('station'), findsOneWidget);
    await tester.tap(find.text('สถานี'));
    await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
    await tester.tap(find.text('ดูผลการเรียน'));
    await _pumpUntilFound(tester, find.byType(ScoreScreen));

    expect(find.byType(ScoreScreen), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    final session = await database
        .select(database.learningSessions)
        .getSingle();
    expect(session.state, 'completed');
  });

  testWidgets('missing category shows honest empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(categoryId: 'missing', learning: learning),
      ),
    );
    final emptyState = find.textContaining('ยังไม่มีคำศัพท์สำหรับ Quiz');
    await _pumpUntilFound(tester, emptyState);

    expect(emptyState, findsOneWidget);
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  testWidgets('retry reuses pending evidence identity', (tester) async {
    final repository = _FailFirstLearningRepository(
      DriftLearningRepository(database),
    );
    var retryId = 0;
    final retryLearning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'retry-${++retryId}',
      nowUtc: () => DateTime.utc(2026, 7, 30, 10, 2, retryId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(categoryId: 'category-1', learning: retryLearning),
      ),
    );
    await _pumpUntilFound(tester, find.text('station'));

    await tester.tap(find.text('สถานี'));
    await _pumpUntilFound(tester, find.byType(SnackBar));
    await tester.tap(find.text('สถานี'));
    await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));

    expect(repository.commands, hasLength(2));
    final first = repository.commands.first;
    final retry = repository.commands.last;
    expect(retry.id, first.id);
    expect(retry.occurredAtUtc, first.occurredAtUtc);
    expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
    expect(retry.evidenceContext.evidenceClass, EvidenceClass.recognition);
    expect(
      retry.evidenceContext.classificationSource,
      EvidenceClassificationSource.legacyInferred,
    );
  });

  test(
    'current activity declarations cover every required evidence class',
    () async {
      var nextId = 0;
      final adapter = CurrentActivityEvidenceAdapter(
        generateId: () => 'declaration-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 14),
        rolloutProvider: const FixedCurrentActivityRolloutProvider.legacy(),
        researchContextProvider:
            const LegacyCurrentActivityResearchContextProvider(),
      );
      const expected = <CurrentActivityInput, EvidenceClass>{
        CurrentActivityInput.meaningMultipleChoice: EvidenceClass.recognition,
        CurrentActivityInput.srsRecall: EvidenceClass.independentRecall,
        CurrentActivityInput.typedRecall: EvidenceClass.independentRecall,
        CurrentActivityInput.associativeRecall: EvidenceClass.independentRecall,
        CurrentActivityInput.ghostDuel: EvidenceClass.recreational,
        CurrentActivityInput.speakToText: EvidenceClass.pronunciation,
        CurrentActivityInput.shadowing: EvidenceClass.pronunciation,
        CurrentActivityInput.readingExposure: EvidenceClass.exposure,
      };

      for (final input in CurrentActivityInput.values) {
        final pending = await adapter.prepare(
          input: input,
          sessionId: 'session-1',
          wordId: 'word-1',
          isCorrect: true,
          responseTimeMs: 1,
          attemptNumber: 1,
        );
        expect(pending.evidenceContext.evidenceClass, expected[input]);
        expect(
          pending.evidenceContext.classificationSource,
          EvidenceClassificationSource.legacyInferred,
        );
      }
    },
  );

  test('shadow and enforced contexts use injected research metadata', () async {
    for (final mode in <EvidencePolicyRolloutMode>{
      EvidencePolicyRolloutMode.shadow,
      EvidencePolicyRolloutMode.enforced,
    }) {
      final adapter = CurrentActivityEvidenceAdapter(
        generateId: () => 'research-${mode.name}',
        nowUtc: () => DateTime.utc(2026, 8, 14),
        rolloutProvider: FixedCurrentActivityRolloutProvider(mode),
        researchContextProvider: const _ResearchContextProvider(),
      );
      final pending = await adapter.prepare(
        input: CurrentActivityInput.ghostDuel,
        sessionId: 'session-1',
        wordId: 'word-1',
        isCorrect: true,
        responseTimeMs: 1,
        attemptNumber: 1,
      );
      final context = pending.evidenceContext;

      expect(context.rolloutMode, mode);
      expect(
        context.classificationSource,
        EvidenceClassificationSource.declared,
      );
      expect(context.evidenceClass, EvidenceClass.recreational);
      expect(context.protocolId, 'evidence-pilot');
      expect(context.assignmentId, 'assignment-1');
      expect(context.researchConsentVersion, 1);
      expect(context.engagementAllowed, isFalse);
    }
  });

  test(
    'protocol evidence-class overrides are restricted to Ghost Duel',
    () async {
      final adapter = CurrentActivityEvidenceAdapter(
        generateId: () => 'override-1',
        nowUtc: () => DateTime.utc(2026, 8, 14),
        rolloutProvider: const FixedCurrentActivityRolloutProvider(
          EvidencePolicyRolloutMode.shadow,
        ),
        researchContextProvider: const _ResearchContextProvider(
          evidenceClassOverride: EvidenceClass.guidedPractice,
        ),
      );

      await expectLater(
        adapter.prepare(
          input: CurrentActivityInput.meaningMultipleChoice,
          sessionId: 'session-1',
          wordId: 'word-1',
          isCorrect: true,
          responseTimeMs: 1,
          attemptNumber: 1,
        ),
        throwsStateError,
      );
      final ghost = await adapter.prepare(
        input: CurrentActivityInput.ghostDuel,
        sessionId: 'session-1',
        wordId: 'word-1',
        isCorrect: true,
        responseTimeMs: 1,
        attemptNumber: 1,
      );
      expect(ghost.evidenceContext.evidenceClass, EvidenceClass.guidedPractice);
    },
  );
}

final class _ResearchContextProvider
    implements CurrentActivityResearchContextProvider {
  const _ResearchContextProvider({this.evidenceClassOverride});

  final EvidenceClass? evidenceClassOverride;

  @override
  Future<CurrentActivityResearchContext> resolve({
    required CurrentActivityInput input,
    required EvidencePolicyRolloutMode rolloutMode,
  }) async => CurrentActivityResearchContext(
    engagementAllowed: false,
    protocolEvidenceClassOverride: evidenceClassOverride,
    protocolId: 'evidence-pilot',
    protocolVersion: '1.0.0',
    experimentId: 'evidence-eligibility',
    experimentVersion: 1,
    assignmentId: 'assignment-1',
    cohort: 'shadow',
    researchConsentVersion: 1,
  );
}

final class _FailFirstLearningRepository implements LearningRepository {
  _FailFirstLearningRepository(this.delegate);

  final LearningRepository delegate;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  bool _failed = false;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    limit: limit,
  );

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) {
    commands.add(command);
    if (!_failed) {
      _failed = true;
      throw StateError('simulated local failure');
    }
    return delegate.recordAnswer(command);
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => delegate.finishSession(
    ownerId: ownerId,
    sessionId: sessionId,
    endedAtUtc: endedAtUtc,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
