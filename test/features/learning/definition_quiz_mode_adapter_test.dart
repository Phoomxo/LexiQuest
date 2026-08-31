import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/definition_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart'
    show normalizeVocabularyText;
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  const adapter = DefinitionQuizModeAdapter();

  test('verified lexical schema v2 loads a pinned English definition', () {
    final metadata = RichLexicalMetadata.fromVerifiedArtifact(
      bytes: Uint8List.fromList(
        utf8.encode('''
{"schemaVersion":2,"wordId":"word:station","contentRevision":3,
"englishDefinition":"A place where trains stop for passengers.",
"ipa":null,"examples":[],"synonyms":[],"antonyms":[],"audio":null}
'''),
      ),
      wordId: 'word:station',
      contentRevision: 3,
      verifiedArtifactChecksumSha256: _artifactChecksum,
    );

    expect(
      metadata.englishDefinition,
      'A place where trains stop for passengers.',
    );
    expect(metadata.verifiedArtifactChecksumSha256, _artifactChecksum);
  });

  test('pins only reviewed English definitions at the session revision', () {
    final session = _session(<QuizWord>[
      _quizWord('word:station', revision: 3, checksum: _checksumA),
      _quizWord('word:airport', revision: 2, checksum: _checksumB),
      _quizWord('word:hotel', revision: 5, checksum: _checksumC),
      _quizWord('word:market', revision: 4, checksum: _checksumD),
      _quizWord('word:harbor', revision: 1, checksum: _checksumA),
    ]);

    final items = adapter.pinItems(
      session: session,
      lexicalWords: <VocabularyWord>[
        _lexicalWord(
          id: 'word:station',
          revision: 3,
          checksum: _checksumA,
          artifactChecksum: _artifactChecksum,
          definition: 'A place where trains stop for passengers.',
        ),
        _lexicalWord(
          id: 'word:airport',
          revision: 3,
          checksum: _checksumB,
          definition: 'A place where aircraft arrive and depart.',
        ),
        _lexicalWord(
          id: 'word:hotel',
          revision: 5,
          checksum: _checksumC,
          definition: null,
        ),
        _lexicalWord(
          id: 'word:market',
          revision: 4,
          checksum: _checksumD,
          definition: 'A place where people buy and sell goods.',
          reviewState: ContentReviewState.unreviewed,
        ),
        _lexicalWord(
          id: 'word:harbor',
          definition: 'A sheltered place where ships can anchor.',
          includeArtifactChecksum: false,
        ),
      ],
    );

    expect(items, hasLength(5));
    expect(
      items[0].question!.identity,
      const ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: 'word:station',
        revision: 3,
      ),
    );
    expect(
      items[0].question!.definition,
      'A place where trains stop for passengers.',
    );
    expect(items[0].question!.checksumSha256, isNot(_artifactChecksum));
    expect(items[0].question!.manifestChecksumSha256, _artifactChecksum);
    expect(items[1].skipReason, DefinitionQuizSkipReason.staleDefinition);
    expect(items[2].skipReason, DefinitionQuizSkipReason.missingDefinition);
    expect(items[3].skipReason, DefinitionQuizSkipReason.unreviewedDefinition);
    expect(items[4].skipReason, DefinitionQuizSkipReason.missingDefinition);
    expect(
      items.skip(1).every((item) => item.question == null),
      isTrue,
      reason: 'invalid definitions must remain auditable skips, not evidence',
    );
  });

  test('real definition prompts bind both core and rich artifact identity', () {
    String identity({required String core, required String rich}) => adapter
        .pinItems(
          session: _session(<QuizWord>[
            _quizWord('word:station', revision: 3, checksum: core),
          ]),
          lexicalWords: <VocabularyWord>[
            _lexicalWord(
              id: 'word:station',
              revision: 3,
              checksum: core,
              artifactChecksum: rich,
              definition: 'A place where trains stop for passengers.',
            ),
          ],
        )
        .single
        .question!
        .contentRevision;

    final baseline = identity(core: _checksumA, rich: _artifactChecksum);

    expect(
      identity(core: _checksumB, rich: _artifactChecksum),
      isNot(baseline),
    );
    expect(identity(core: _checksumA, rich: _checksumC), isNot(baseline));
  });

  test('pins reproducible ambiguity-safe distractors by canonical text', () {
    final session = _session(<QuizWord>[
      _quizWord('word:lead-noun', spelling: 'Lead'),
      _quizWord('word:lead-duplicate', spelling: '  LEAD  '),
      _quizWord('word:guide', spelling: 'guide'),
      _quizWord('word:direct', spelling: 'direct'),
      _quizWord('word:station', spelling: 'station'),
      _quizWord('word:airport', spelling: 'airport'),
    ]);
    final lexical = <VocabularyWord>[
      _lexicalWord(
        id: 'word:lead-noun',
        spelling: 'Lead',
        definition: 'A heavy metal.',
      ),
      _lexicalWord(
        id: 'word:lead-duplicate',
        spelling: '  LEAD  ',
        definition: 'To guide someone.',
      ),
      _lexicalWord(
        id: 'word:guide',
        spelling: 'guide',
        definition: 'To guide someone.',
      ),
      _lexicalWord(
        id: 'word:direct',
        spelling: 'direct',
        definition: 'a   HEAVY metal.',
      ),
      _lexicalWord(
        id: 'word:station',
        spelling: 'station',
        definition: 'A railway stopping place.',
      ),
      _lexicalWord(
        id: 'word:airport',
        spelling: 'airport',
        definition: 'A place for aircraft.',
      ),
    ];

    final first = adapter.pinItems(session: session, lexicalWords: lexical);
    final replay = adapter.pinItems(session: session, lexicalWords: lexical);
    final lead = first.first.question!;

    expect(lead.options, replay.first.question!.options);
    expect(
      lead.options.where((option) => normalizeVocabularyText(option) == 'lead'),
      hasLength(1),
    );
    expect(
      lead.options,
      isNot(contains('direct')),
      reason: 'an equivalent definition makes that distractor ambiguous',
    );
    expect(
      lead.options.map(normalizeVocabularyText).toSet(),
      hasLength(lead.options.length),
    );
  });

  test('classifies unhinted answers as recognition and any hint as guided', () {
    final response = LessonResponse(
      sourceEvidenceId: 'attempt:def-1',
      occurredAtUtc: DateTime.utc(2026, 8, 25, 10),
      sessionId: 'session:def-1',
      wordId: 'word:station',
      promptMode: 'definitionChoice',
      isCorrect: true,
      responseTimeMs: 800,
      attemptNumber: 1,
      feedbackContext: const AnswerFeedbackContext(
        canonicalCorrectAnswer: 'station',
      ),
    );
    final unhinted = EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.recognition,
      skillId: 'definition-recognition',
      hintLevel: 0,
      contentRevision: 'lexical-definition:word:station@3:$_checksumA',
      engagementAllowed: true,
    );
    final hinted = EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.guidedPractice,
      skillId: 'definition-recognition',
      hintLevel: 1,
      contentRevision: 'lexical-definition:word:station@3:$_checksumA',
      engagementAllowed: true,
    );

    expect(
      adapter.classify(response, LessonSupport(evidenceContext: unhinted)),
      same(unhinted),
    );
    expect(
      adapter.classify(response, LessonSupport(evidenceContext: hinted)),
      same(hinted),
    );
    expect(
      () => adapter.classify(
        response,
        LessonSupport(
          evidenceContext: EvidenceContext.legacyCompatibility(
            evidenceClass: EvidenceClass.recognition,
            skillId: 'definition-recognition',
            hintLevel: 0,
            contentRevision: 'lexical-definition:word:station@3:not-a-checksum',
            engagementAllowed: true,
          ),
        ),
      ),
      throwsStateError,
    );
    expect(adapter.hintPolicy, isA<HintPolicy>());
    expect(
      adapter.classifyHintUsage(const HintUsageSnapshot.known(0)).evidenceClass,
      EvidenceClass.recognition,
    );
    expect(
      adapter.classifyHintUsage(const HintUsageSnapshot.known(1)).evidenceClass,
      EvidenceClass.guidedPractice,
    );
    expect(
      adapter.classifyHintUsage(const HintUsageSnapshot.unknown()).hintLevel,
      2,
      reason: 'unknown assistance must fail closed as guided evidence',
    );
    expect(
      classifyCurrentActivityEvidence(
        CurrentActivityInput.definitionMultipleChoice,
        hintLevel: 0,
      ).evidenceClass,
      EvidenceClass.recognition,
    );
    expect(
      classifyCurrentActivityEvidence(
        CurrentActivityInput.definitionMultipleChoice,
        hintLevel: 1,
      ).evidenceClass,
      EvidenceClass.guidedPractice,
    );
  });

  group('review evidence', () {
    late AppDatabase database;
    late DriftLocalOwnerRepository owners;
    late LearningUseCases learning;
    var generatedId = 0;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      generatedId = 0;
      owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'definition-owner',
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
      await _insertDefinitionWord(
        database,
        ownerId: owner.id,
        id: 'word:airport',
        spelling: 'airport',
        revision: 2,
        checksum: _canonicalCoreChecksum('airport'),
      );
      await _insertDefinitionWord(
        database,
        ownerId: owner.id,
        id: 'word:station',
        spelling: 'station',
        revision: 3,
        checksum: _canonicalCoreChecksum('station'),
      );
      learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'definition-${++generatedId}',
        nowUtc: () => DateTime.utc(2026, 8, 25, 10, 0, generatedId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f08-test'),
      );
    });

    tearDown(() => database.close());

    test(
      'writes pinned recognition and hinted guided evidence without SRS',
      () async {
        final session = await learning.startQuiz(categoryId: 'category:travel');
        var hintLevel = 0;
        var hintResets = 0;
        final review = adapter.createReview(
          session: session,
          lexicalWords: <VocabularyWord>[
            _lexicalWord(
              id: 'word:airport',
              spelling: 'airport',
              revision: 2,
              checksum: _canonicalCoreChecksum('airport'),
              definition: 'A place where aircraft arrive and depart.',
            ),
            _lexicalWord(
              id: 'word:station',
              spelling: 'station',
              revision: 3,
              checksum: _canonicalCoreChecksum('station'),
              definition: 'A place where trains stop for passengers.',
            ),
          ],
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          hintUsage: () => HintUsageSnapshot.known(hintLevel),
          resetHintsAfterCommit: () => hintResets += 1,
        );
        addTearDown(review.dispose);
        final expectedContentRevisions = review.items
            .map((item) => item.question!.contentRevision)
            .toList(growable: false);

        await review.answer(
          option: review.currentItem.question!.correctOption,
          responseTimeMs: 750,
        );
        expect(review.feedback?.isCorrect, isTrue);
        await review.advance();
        hintLevel = 1;
        await review.answer(
          option: review.currentItem.question!.correctOption,
          responseTimeMs: 900,
        );

        final attempts = await database.select(database.answerAttempts).get();
        final contexts = attempts
            .map(
              (row) => EvidenceContext.fromJson(
                (jsonDecode(row.evidenceContextJson) as Map<Object?, Object?>)
                    .cast<String, Object?>(),
              ),
            )
            .toList(growable: false);
        expect(attempts, hasLength(2));
        expect(attempts.map((row) => row.promptMode).toSet(), <String>{
          'definitionChoice',
        });
        expect(attempts.map((row) => row.evidenceClass), <String>[
          EvidenceClass.recognition.name,
          EvidenceClass.guidedPractice.name,
        ]);
        expect(contexts.map((context) => context.hintLevel), <int>[0, 1]);
        expect(
          contexts.map((context) => context.contentRevision),
          expectedContentRevisions,
        );
        expect(await database.select(database.srsStates).get(), isEmpty);
        expect(hintResets, 2);
      },
    );

    test(
      'commit then acknowledgement loss retries one exact attempt',
      () async {
        final repository = _LostAckLearningRepository(
          DriftLearningRepository(database),
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'retry-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 11, 0, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f08-test'),
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
              checksum: _canonicalCoreChecksum('airport'),
              definition: 'A place where aircraft arrive and depart.',
            ),
            _lexicalWord(
              id: 'word:station',
              spelling: 'station',
              revision: 3,
              checksum: _canonicalCoreChecksum('station'),
              definition: 'A place where trains stop for passengers.',
            ),
          ],
          learning: retryLearning,
          evidence: CurrentActivityEvidenceAdapter(learning: retryLearning),
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);

        await expectLater(
          review.answer(
            option: review.currentItem.question!.correctOption,
            responseTimeMs: 1234,
          ),
          throwsStateError,
        );
        expect(review.phase, DefinitionQuizReviewPhase.evidenceRetryRequired);
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );

        await review.retryEvidence();

        expect(repository.commands, hasLength(2));
        final first = repository.commands.first;
        final retry = repository.commands.last;
        expect(retry.id, first.id);
        expect(retry.sessionId, first.sessionId);
        expect(retry.wordId, first.wordId);
        expect(retry.promptMode, first.promptMode);
        expect(retry.isCorrect, first.isCorrect);
        expect(retry.responseTimeMs, first.responseTimeMs);
        expect(retry.attemptNumber, first.attemptNumber);
        expect(retry.occurredAtUtc, first.occurredAtUtc);
        expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
        expect(retry.providerProvenance, first.providerProvenance);
        expect(retry.event?.toJson(), first.event?.toJson());
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
        final events = await database.select(database.eventsV2).get();
        expect(
          events.where((event) => event.eventId.startsWith('learning-event:')),
          hasLength(1),
        );
        expect(
          events.where(
            (event) => event.eventId.startsWith('learning-evidence-decisions:'),
          ),
          hasLength(1),
        );
        expect(await database.select(database.srsStates).get(), isEmpty);
      },
    );
  });
}

QuizSession _session(List<QuizWord> words) => QuizSession(
  id: 'session:definition',
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
  meaning: 'ความหมาย',
  partOfSpeech: 'noun',
  contentRevision: revision,
  contentChecksumSha256: checksum,
);

VocabularyWord _lexicalWord({
  required String id,
  String? spelling,
  int revision = 1,
  String checksum = _checksumA,
  String? definition,
  String? artifactChecksum,
  bool includeArtifactChecksum = true,
  ContentReviewState reviewState = ContentReviewState.approved,
}) => VocabularyWord(
  id: id,
  ownerId: 'owner:packaged',
  categoryId: 'category:travel',
  spelling: spelling ?? id.substring('word:'.length),
  normalizedSpelling: normalizeVocabularyText(
    spelling ?? id.substring('word:'.length),
  ),
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
  contentChecksumSha256: checksum,
  contentProvenance: ContentProvenance.packaged,
  contentReviewState: reviewState,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: RichLexicalMetadata(
    englishDefinition: definition,
    verifiedContentRevision: revision,
    verifiedArtifactChecksumSha256: includeArtifactChecksum
        ? artifactChecksum ?? checksum
        : null,
  ),
);

const _checksumA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _checksumB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _checksumC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _checksumD =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _artifactChecksum =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

Future<void> _insertDefinitionWord(
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
        contentRevision: Value(revision),
        contentChecksumSha256: Value(checksum),
        createdAtUtcMs: 1,
        updatedAtUtcMs: 1,
      ),
    );

String _canonicalCoreChecksum(String spelling) =>
    ContentQualityPolicy.vocabularyChecksumSha256(
      categoryId: 'category:travel',
      spelling: spelling,
      normalizedSpelling: spelling,
      meaning: 'ความหมาย',
      normalizedMeaning: 'ความหมาย',
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'manual',
      isGlobal: false,
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
