import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  const adapter = ClozeModeAdapter();

  test('pins one reviewed lexical example at the session revision', () {
    final items = adapter.pinItems(
      session: _session(<QuizWord>[
        _quizWord('word:station', revision: 3, checksum: _checksumA),
        _quizWord('word:airport', revision: 2, checksum: _checksumB),
        _quizWord('word:market', revision: 4, checksum: _checksumC),
        _quizWord('word:hotel', revision: 5, checksum: _checksumD),
      ]),
      lexicalWords: <VocabularyWord>[
        _lexicalWord(
          id: 'word:station',
          revision: 3,
          checksum: _checksumA,
          examples: const <String>['The station closes at midnight.'],
        ),
        _lexicalWord(
          id: 'word:airport',
          revision: 3,
          checksum: _checksumB,
          examples: const <String>['The airport is busy.'],
        ),
        _lexicalWord(
          id: 'word:market',
          revision: 4,
          checksum: _checksumC,
          reviewState: ContentReviewState.unreviewed,
          examples: const <String>['The market opens early.'],
        ),
        _lexicalWord(
          id: 'word:hotel',
          revision: 5,
          checksum: _checksumD,
          examples: const <String>['The hotel and another HOTEL are full.'],
        ),
      ],
    );

    expect(items, hasLength(4));
    final question = items.first.question!;
    expect(question.prompt, 'The _____ closes at midnight.');
    expect(question.correctAnswer, 'station');
    expect(
      question.identity,
      const ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: 'word:station',
        revision: 3,
      ),
    );
    expect(items[1].skipReason, ClozeSkipReason.staleContent);
    expect(items[2].skipReason, ClozeSkipReason.unreviewedContent);
    expect(items[3].skipReason, ClozeSkipReason.ambiguousExample);
  });

  test(
    'restart reconstructs deterministic canonically distinct selected options',
    () {
      final session = _session(<QuizWord>[
        _quizWord('word:station', spelling: 'station'),
        _quizWord('word:station-copy', spelling: '  STATION  '),
        _quizWord('word:airport', spelling: 'airport'),
        _quizWord('word:market', spelling: 'market'),
        _quizWord('word:hotel', spelling: 'hotel'),
      ]);
      final lexical = <VocabularyWord>[
        _lexicalWord(
          id: 'word:station',
          spelling: 'station',
          examples: const <String>['The station closes.'],
        ),
        _lexicalWord(
          id: 'word:station-copy',
          spelling: '  STATION  ',
          examples: const <String>['A STATION can be crowded.'],
        ),
        _lexicalWord(
          id: 'word:airport',
          spelling: 'airport',
          examples: const <String>['The airport is busy.'],
        ),
        _lexicalWord(
          id: 'word:market',
          spelling: 'market',
          examples: const <String>['The market opens.'],
        ),
        _lexicalWord(
          id: 'word:hotel',
          spelling: 'hotel',
          examples: const <String>['The hotel is quiet.'],
        ),
      ];

      final first = adapter.pinItems(session: session, lexicalWords: lexical);
      final replay = const ClozeModeAdapter().pinItems(
        session: session,
        lexicalWords: lexical,
      );
      final options = first.first.question!.options;
      expect(options, replay.first.question!.options);
      expect(first.first.question!.prompt, replay.first.question!.prompt);
      expect(
        first.first.question!.contentRevision,
        replay.first.question!.contentRevision,
      );
      expect(
        options.map(normalizeVocabularyText).toSet(),
        hasLength(options.length),
      );
      expect(
        options.where((value) => normalizeVocabularyText(value) == 'station'),
        hasLength(1),
      );
    },
  );

  test(
    'classifies selected, independent typed, and fail-closed hinted typed',
    () {
      expect(
        adapter
            .classifyResponse(
              inputMode: ClozeInputMode.selected,
              hint: const HintUsageSnapshot.known(0),
            )
            .evidenceClass,
        EvidenceClass.recognition,
      );
      expect(
        adapter
            .classifyResponse(
              inputMode: ClozeInputMode.typed,
              hint: const HintUsageSnapshot.known(0),
            )
            .evidenceClass,
        EvidenceClass.independentRecall,
      );
      expect(
        adapter
            .classifyResponse(
              inputMode: ClozeInputMode.typed,
              hint: const HintUsageSnapshot.known(1),
            )
            .evidenceClass,
        EvidenceClass.guidedPractice,
      );
      final unknown = adapter.classifyResponse(
        inputMode: ClozeInputMode.typed,
        hint: const HintUsageSnapshot.unknown(),
      );
      expect(unknown.evidenceClass, EvidenceClass.guidedPractice);
      expect(unknown.hintLevel, 2);
    },
  );

  test('adapter and shared helper agree for selected cloze assistance', () {
    final cases = <({HintUsageSnapshot hint, int recordedLevel})>[
      (hint: const HintUsageSnapshot.known(0), recordedLevel: 0),
      (hint: const HintUsageSnapshot.known(1), recordedLevel: 1),
      (hint: const HintUsageSnapshot.unknown(), recordedLevel: -1),
    ];

    for (final testCase in cases) {
      final adapterResult = adapter.classifyResponse(
        inputMode: ClozeInputMode.selected,
        hint: testCase.hint,
      );
      final sharedResult = classifyCurrentActivityEvidence(
        CurrentActivityInput.clozeSelected,
        hintLevel: testCase.recordedLevel,
      );
      expect(sharedResult.evidenceClass, adapterResult.evidenceClass);
      expect(sharedResult.hintLevel, adapterResult.hintLevel);
    }
  });

  group('durable cloze evidence', () {
    late AppDatabase database;
    late DriftLocalOwnerRepository owners;
    late LearningUseCases learning;
    var generatedId = 0;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'cloze-owner',
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
      await _insertWord(
        database,
        owner.id,
        'word:market',
        'market',
        4,
        _checksumC,
      );
      learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'cloze-${++generatedId}',
        nowUtc: () => DateTime.utc(2026, 8, 25, 10, 0, generatedId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f09-test'),
      );
    });

    tearDown(() => database.close());

    test(
      'selected and hinted typed do not update mastery; unhinted typed does',
      () async {
        final session = await learning.startQuiz(categoryId: 'category:travel');
        var hint = const HintUsageSnapshot.known(0);
        final review = adapter.createReview(
          session: session,
          lexicalWords: <VocabularyWord>[
            _lexicalWord(
              id: 'word:airport',
              spelling: 'airport',
              revision: 2,
              checksum: _checksumB,
              examples: const <String>['The airport is busy.'],
            ),
            _lexicalWord(
              id: 'word:station',
              spelling: 'station',
              revision: 3,
              checksum: _checksumA,
              examples: const <String>['The station closes.'],
            ),
            _lexicalWord(
              id: 'word:market',
              spelling: 'market',
              revision: 4,
              checksum: _checksumC,
              examples: const <String>['The market opens early.'],
            ),
          ],
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          hintUsage: () => hint,
        );
        addTearDown(review.dispose);

        final first = review.currentItem.question!;
        await review.answerSelected(
          option: first.correctAnswer,
          responseTimeMs: 600,
        );
        await review.advance();
        hint = const HintUsageSnapshot.known(1);
        await review.answerTyped(
          text: review.currentItem.question!.correctAnswer,
          responseTimeMs: 700,
        );
        await review.advance();
        hint = const HintUsageSnapshot.known(0);
        await review.answerTyped(
          text: review.currentItem.question!.correctAnswer,
          responseTimeMs: 800,
        );

        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts.map((row) => row.promptMode), <String>[
          'clozeSelected',
          'clozeTyped',
          'clozeTyped',
        ]);
        expect(attempts.map((row) => row.evidenceClass), <String>[
          EvidenceClass.recognition.name,
          EvidenceClass.guidedPractice.name,
          EvidenceClass.independentRecall.name,
        ]);
        expect(await database.select(database.srsStates).get(), hasLength(1));
      },
    );

    test(
      'unknown input is rejected before any evidence or mastery write',
      () async {
        final session = await learning.startQuiz(categoryId: 'category:travel');
        final review = adapter.createReview(
          session: session,
          lexicalWords: <VocabularyWord>[
            _lexicalWord(
              id: 'word:airport',
              spelling: 'airport',
              revision: 2,
              checksum: _checksumB,
              examples: const <String>['The airport is busy.'],
            ),
            _lexicalWord(
              id: 'word:station',
              spelling: 'station',
              revision: 3,
              checksum: _checksumA,
              examples: const <String>['The station closes.'],
            ),
            _lexicalWord(
              id: 'word:market',
              spelling: 'market',
              revision: 4,
              checksum: _checksumC,
              examples: const <String>['The market opens early.'],
            ),
          ],
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          hintUsage: () => const HintUsageSnapshot.unknown(),
        );
        addTearDown(review.dispose);

        expect(
          () => review.answerTyped(text: '   ', responseTimeMs: 400),
          throwsArgumentError,
        );
        expect(
          () =>
              review.answerSelected(option: 'not-pinned', responseTimeMs: 400),
          throwsArgumentError,
        );
        expect(await database.select(database.answerAttempts).get(), isEmpty);
        expect(await database.select(database.srsStates).get(), isEmpty);

        await review.answerTyped(
          text: review.currentItem.question!.correctAnswer,
          responseTimeMs: 500,
        );
        final attempt =
            (await database.select(database.answerAttempts).get()).single;
        expect(attempt.evidenceClass, EvidenceClass.guidedPractice.name);
        expect(await database.select(database.srsStates).get(), isEmpty);
      },
    );

    test(
      'lost acknowledgement retries the exact frozen typed occurrence',
      () async {
        final repository = _LostAckLearningRepository(
          DriftLearningRepository(database),
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'retry-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 11, 0, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f09-test'),
        );
        final session = await retryLearning.startQuiz(
          categoryId: 'category:travel',
        );
        final review = adapter.createReview(
          session: session,
          lexicalWords: <VocabularyWord>[
            _lexicalWord(
              id: 'word:airport',
              spelling: 'airport',
              revision: 2,
              checksum: _checksumB,
              examples: const <String>['The airport is busy.'],
            ),
            _lexicalWord(
              id: 'word:station',
              spelling: 'station',
              revision: 3,
              checksum: _checksumA,
              examples: const <String>['The station closes.'],
            ),
            _lexicalWord(
              id: 'word:market',
              spelling: 'market',
              revision: 4,
              checksum: _checksumC,
              examples: const <String>['The market opens early.'],
            ),
          ],
          learning: retryLearning,
          evidence: CurrentActivityEvidenceAdapter(learning: retryLearning),
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);

        await expectLater(
          review.answerTyped(
            text: review.currentItem.question!.correctAnswer,
            responseTimeMs: 1234,
          ),
          throwsStateError,
        );
        expect(review.phase, ClozeReviewPhase.evidenceRetryRequired);
        await review.retryEvidence();

        expect(repository.commands, hasLength(2));
        final first = repository.commands.first;
        final retry = repository.commands.last;
        expect(retry.id, first.id);
        expect(retry.occurredAtUtc, first.occurredAtUtc);
        expect(retry.promptMode, first.promptMode);
        expect(retry.responseTimeMs, first.responseTimeMs);
        expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
      },
    );
  });
}

QuizSession _session(List<QuizWord> words) => QuizSession(
  id: 'session:cloze',
  startedAtUtc: DateTime.utc(2026, 8, 25, 9),
  questions: words
      .map((word) => QuizQuestion(word: word, options: const <String>[]))
      .toList(growable: false),
);

QuizWord _quizWord(
  String id, {
  String? spelling,
  int revision = 1,
  String checksum = _checksumA,
}) => QuizWord(
  id: id,
  categoryId: 'category:travel',
  spelling: spelling ?? id.substring('word:'.length),
  normalizedSpelling: normalizeVocabularyText(
    spelling ?? id.substring('word:'.length),
  ),
  meaning: 'meaning',
  normalizedMeaning: 'meaning',
  partOfSpeech: 'noun',
  contentRevision: revision,
  contentChecksumSha256: checksum,
);

VocabularyWord _lexicalWord({
  required String id,
  String? spelling,
  int revision = 1,
  String checksum = _checksumA,
  List<String> examples = const <String>[],
  ContentReviewState reviewState = ContentReviewState.approved,
}) => VocabularyWord(
  id: id,
  ownerId: 'owner:packaged',
  categoryId: 'category:travel',
  spelling: spelling ?? id.substring('word:'.length),
  normalizedSpelling: normalizeVocabularyText(
    spelling ?? id.substring('word:'.length),
  ),
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
  contentReviewState: reviewState,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: RichLexicalMetadata(
    verifiedArtifactChecksumSha256: checksum,
    examples: examples,
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

final class _LostAckLearningRepository implements LearningRepository {
  _LostAckLearningRepository(this.delegate);

  final LearningRepository delegate;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  bool _lostAcknowledgement = false;

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
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    final result = await delegate.recordAnswer(command);
    if (!_lostAcknowledgement) {
      _lostAcknowledgement = true;
      throw StateError('simulated acknowledgement loss');
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _checksumA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _checksumB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _checksumC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _checksumD =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
