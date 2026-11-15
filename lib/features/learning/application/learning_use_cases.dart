import '../../identity/domain/local_owner_repository.dart';
import '../../../runtime/app_build_info.dart';
import '../../events/application/event_v1_to_v2_adapter.dart';
import '../../rewards/application/shadow_reward_orchestrator.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import '../domain/cloze_prompt_policy.dart';
import '../domain/quiz_prompt_policy.dart';
import '../domain/quiz_round.dart';
import '../domain/review_ladder.dart';
import '../domain/scramble_prompt_policy.dart';
import '../domain/source_reading_round.dart';
import '../domain/srs_recall_snapshot.dart';

typedef LearningIdGenerator = String Function();
typedef LearningUtcNow = DateTime Function();
typedef LearningMutationNotifier = void Function();
typedef ReviewDeskData = ({ReviewLadderPair? pair, ReviewLadderRound? latest});
typedef AnswerCommittedSink =
    Future<void> Function({
      required String ownerId,
      required String attemptId,
      required int occurredAtUtcMs,
    });

final class LearningUseCases {
  LearningUseCases({
    required this.owners,
    required this.repository,
    required this.generateId,
    required this.nowUtc,
    required this.buildInfo,
    this.onLocalMutation,
    this.shadowOrchestrator,
    this.eventAdapter,
    this.onAnswerCommitted,
  });

  final LocalOwnerRepository owners;
  final LearningRepository repository;
  final LearningIdGenerator generateId;
  final LearningUtcNow nowUtc;
  final AppBuildInfo buildInfo;
  final LearningMutationNotifier? onLocalMutation;
  final AnswerCommittedSink? onAnswerCommitted;

  /// Shadow mode — when non-null, every recorded answer is also run through
  /// the V2 reward eligibility pipeline in dry-run mode.  Null = disabled.
  final ShadowRewardOrchestrator? shadowOrchestrator;

  /// Required when [shadowOrchestrator] is non-null; adapts V1 commands to
  /// a V2 event for shadow processing.
  final EventV1ToV2Adapter? eventAdapter;

  bool get supportsDurableQuiz => repository is DurableQuizRepository;

  bool get supportsReviewLadder => repository is ReviewLadderRepository;

  ReviewLadderRepository get _reviewLadder {
    final current = repository;
    if (current is ReviewLadderRepository) return current;
    throw StateError('Review ladder is unavailable');
  }

  Future<String> _reviewOwner(String expectedOwnerId) async {
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    return owner.id;
  }

  Future<ReviewDeskData> loadReviewDesk({
    required String expectedOwnerId,
  }) async {
    final ownerId = await _reviewOwner(expectedOwnerId);
    return (
      pair: await _reviewLadder.findReviewLadderPair(ownerId: ownerId),
      latest: await _reviewLadder.readLatestReviewLadder(ownerId: ownerId),
    );
  }

  Future<ReviewLadderRound> openReviewLadder({
    required String expectedOwnerId,
    required ReviewLadderPair pair,
  }) async {
    final ownerId = await _reviewOwner(expectedOwnerId);
    return _reviewLadder.openReviewLadderRound(
      session: LearningSessionDraft(
        id: 'session:${_nextId()}',
        ownerId: ownerId,
        activityType: 'reviewLadder',
        startedAtUtc: _now(),
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
      pair: pair,
    );
  }

  Future<ReviewLadderRound> changeReviewLadder({
    required String expectedOwnerId,
    required ReviewLadderRound expected,
    required ReviewLadderAction action,
    required DateTime atUtc,
    int? option,
    String? text,
  }) async => _reviewLadder.changeReviewLadderRound(
    ownerId: await _reviewOwner(expectedOwnerId),
    expected: expected,
    action: action,
    atUtc: atUtc,
    option: option,
    text: text,
  );

  Future<LearningSessionSummary> finishReviewLadder({
    required String expectedOwnerId,
    required ReviewLadderRound round,
  }) async {
    if (round.phase != ReviewLadderPhase.result) {
      throw StateError('Review ladder is not ready to finish');
    }
    final ownerId = await _reviewOwner(expectedOwnerId);
    if (round.independentChoice case final first?) {
      await recordAnswer(
        sessionId: round.sessionId,
        wordId: round.pair.target.id,
        promptMode: QuizPromptKind.meaningChoice.name,
        isCorrect: first.option == 1,
        responseTimeMs: null,
        attemptNumber: 1,
        attemptId: 'attempt:${round.sessionId}:review:0',
        occurredAtUtc: first.checkedAtUtc,
        expectedOwnerId: expectedOwnerId,
      );
    }
    final summary = await _reviewLadder.finishReviewLadderRound(
      ownerId: ownerId,
      expected: round,
      endedAtUtc: _now(),
    );
    onLocalMutation?.call();
    return summary;
  }

  bool get supportsDurableSourceReading =>
      repository is DurableSourceReadingRepository;

  Future<SourceReadingRound> openSourceReadingRound({
    required String expectedOwnerId,
    required SourceReadingScope scope,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    return (repository as DurableSourceReadingRepository)
        .openSourceReadingRound(
          session: LearningSessionDraft(
            id: 'session:${_nextId()}',
            ownerId: owner.id,
            activityType: 'associativeReading',
            startedAtUtc: _now(),
            appVersion: buildInfo.version,
            buildId: buildInfo.buildId,
          ),
          scope: scope,
        );
  }

  Future<SourceReadingRound> saveSourceReadingRound({
    required String expectedOwnerId,
    required SourceReadingRound expected,
    required SourceReadingDraft draft,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    return (repository as DurableSourceReadingRepository)
        .saveSourceReadingRound(
          ownerId: owner.id,
          expected: expected,
          draft: draft,
        );
  }

  Future<LearningSessionResult> finishSourceReadingRound({
    required String expectedOwnerId,
    required SourceReadingRound round,
  }) async {
    final first = round.draft.first;
    if (round.draft.phase != SourceReadingPhase.summary || first == null) {
      throw StateError('Source reading is not ready to finish');
    }
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    final mistakeIds = <String>[];
    for (final (slot, word) in round.scope.words.indexed) {
      final isCorrect = sourceRecallMatches(first.answers[slot], word.spelling);
      if (!isCorrect) mistakeIds.add(word.id);
      await recordAnswer(
        sessionId: round.sessionId,
        wordId: word.id,
        promptMode: 'associativeRecall',
        isCorrect: isCorrect,
        responseTimeMs: null,
        attemptNumber: slot + 1,
        attemptId: 'attempt:${round.sessionId}:associative:$slot',
        occurredAtUtc: first.checkedAtUtc,
        expectedOwnerId: expectedOwnerId,
      );
    }
    final summary = await (repository as DurableSourceReadingRepository)
        .finishSourceReadingRound(
          ownerId: owner.id,
          expected: round,
          endedAtUtc: _now(),
        );
    onLocalMutation?.call();
    return LearningSessionResult(
      summary: summary,
      mistakeWordIds: mistakeIds,
      sourceSentence: round.draft.sentence.trim(),
    );
  }

  Future<QuizSession> startQuiz({
    String? categoryId,
    int limit = 10,
    String? expectedOwnerId,
    QuizPromptKind kind = QuizPromptKind.meaningChoice,
    QuizOrigin? origin,
    bool skipUnavailable = false,
    String? categoryName,
    String? returnLabel,
    QuizRoundSettings? settings,
  }) => _startVocabularySession(
    categoryId,
    settings?.questionCount ?? limit,
    'quiz',
    expectedOwnerId: expectedOwnerId,
    kind: kind,
    origin: origin,
    skipUnavailable: skipUnavailable,
    categoryName: categoryName,
    returnLabel: returnLabel,
    settings: settings,
  );

  Future<QuizSession> startCloze({
    required QuizPromptKind kind,
    required String expectedOwnerId,
    String? categoryId,
    String? parentSessionId,
    String? categoryName,
    String? returnLabel,
    bool skipUnavailable = false,
  }) async {
    if (!kind.isCloze) throw ArgumentError.value(kind, 'kind');
    final durable = repository;
    if (durable is! DurableQuizRepository) {
      throw StateError('Durable practice unavailable');
    }
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    final parentId = _optionalId(parentSessionId, 'parentSessionId');
    final selectedCategory = _optionalId(categoryId, 'categoryId');
    final targets = parentId == null
        ? null
        : await durable.loadCompletedQuizMistakeIds(
            ownerId: owner.id,
            sessionId: parentId,
          );
    if (targets?.isEmpty == true) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final origin = QuizOrigin(
      route: 'cloze',
      promptKind: kind,
      categoryId: selectedCategory,
      parentId: parentId,
    );
    final existing = await _openRound(owner.id, origin, skipUnavailable);
    if (existing != null) return _quizSession(existing);
    final question = await _firstClozeQuestion(owner.id, origin, targets);
    if (question == null) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final round = await durable.openOrStartAuthoredRound(
      LearningSessionDraft(
        id: 'session:${_nextId()}',
        ownerId: owner.id,
        activityType: 'cloze',
        startedAtUtc: _now(),
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
        quizPlan: QuizPlan(
          origin: origin,
          questions: [question],
          categoryName: categoryName,
          returnLabel: returnLabel,
        ),
      ),
      skipUnavailable: skipUnavailable,
    );
    return _quizSession(round);
  }

  Future<QuizSession> startScramble({
    required QuizPromptKind kind,
    required String expectedOwnerId,
    required String? categoryId,
    String? wordId,
    String? parentSessionId,
    String? categoryName,
    String? returnLabel,
    bool skipUnavailable = false,
  }) async {
    if (!kind.isScramble) throw ArgumentError.value(kind, 'kind');
    final durable = repository;
    if (durable is! DurableQuizRepository) {
      throw StateError('Durable practice unavailable');
    }
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    final origin = QuizOrigin(
      route: 'word-games',
      promptKind: kind,
      categoryId: _optionalId(categoryId, 'categoryId'),
      wordIds: wordId == null ? null : [_requiredId(wordId, 'wordId')],
      parentId: _optionalId(parentSessionId, 'parentSessionId'),
    );
    QuizWord? parentWord;
    if (origin.parentId case final parentId?) {
      final parent = await durable.loadQuizRound(
        ownerId: owner.id,
        sessionId: parentId,
      );
      if (kind != QuizPromptKind.sentenceScramble ||
          parent == null ||
          !(parent.plan.origin.promptKind.isCloze ||
              parent.plan.origin.promptKind == QuizPromptKind.wordScramble)) {
        throw StateError('Sentence source round is unavailable');
      }
      final question = parent.plan.questions[parent.cursor.slot];
      if (question.word.id != origin.wordIds?.single ||
          question.word.categoryId != origin.categoryId ||
          parent.feedback?.isCorrectFor(question) != true) {
        throw StateError('Sentence source answer is unavailable');
      }
      parentWord = question.word;
    }
    if (parentWord == null) {
      final open = await _openRound(owner.id, origin, skipUnavailable);
      if (open != null) return _quizSession(open);
    }
    final words = await repository.listQuizWords(
      ownerId: owner.id,
      categoryId: origin.categoryId,
      wordIds: origin.wordIds,
      normalizedSpellings: kind == QuizPromptKind.sentenceScramble
          ? const ['ticket', 'platform']
          : null,
      limit: null,
    );
    final question = ScramblePromptPolicy.first(words, kind);
    if (parentWord != null &&
        question?.word.localRevision != parentWord.localRevision) {
      throw QuizVocabularyChanged();
    }
    if (question == null) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final round = await durable.openOrStartAuthoredRound(
      LearningSessionDraft(
        id: 'session:${_nextId()}',
        ownerId: owner.id,
        activityType: kind.name,
        startedAtUtc: _now(),
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
        quizPlan: QuizPlan(
          origin: origin,
          questions: [question],
          categoryName: categoryName,
          returnLabel: returnLabel,
        ),
      ),
      skipUnavailable: skipUnavailable,
    );
    return _quizSession(round);
  }

  Future<bool> hasClozeRepair({
    required String parentSessionId,
    required String expectedOwnerId,
  }) async {
    final durable = repository;
    if (durable is! DurableQuizRepository) return false;
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    final parentId = _requiredId(parentSessionId, 'parentSessionId');
    final targets = await durable.loadCompletedQuizMistakeIds(
      ownerId: owner.id,
      sessionId: parentId,
    );
    if (targets.isEmpty) return false;
    final origin = QuizOrigin(
      route: 'cloze',
      promptKind: QuizPromptKind.clozeChoice,
      parentId: parentId,
    );
    return await _openRound(owner.id, origin, true) != null ||
        await _firstClozeQuestion(owner.id, origin, targets) != null;
  }

  Future<QuizQuestion?> _firstClozeQuestion(
    String ownerId,
    QuizOrigin origin,
    Set<String>? targets,
  ) async {
    final words = await repository.listQuizWords(
      ownerId: ownerId,
      categoryId: origin.categoryId,
      normalizedSpellings: ClozePromptPolicy.spellings,
      normalizedMeanings: ClozePromptPolicy.meanings,
      limit: null,
    );
    return ClozePromptPolicy.build(
      words: words,
      kind: origin.promptKind,
      targetWordIds: targets,
    ).firstOrNull;
  }

  Future<({QuizSession? existing, int available})> prepareCategoryQuiz({
    required QuizOrigin origin,
    required String expectedOwnerId,
    bool skipUnavailable = false,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    if (origin.categoryId == null || !supportsDurableQuiz) {
      throw StateError('Configured category quiz unavailable');
    }
    _checkOrigin(
      origin,
      kind: origin.promptKind,
      categoryId: origin.categoryId,
    );
    final open = await _openRound(owner.id, origin, skipUnavailable);
    if (open != null) return (existing: _quizSession(open), available: 0);
    final questions = await _categoryQuizQuestions(
      owner.id,
      origin.categoryId,
      origin.promptKind,
      10,
      configured: true,
    );
    return (existing: null, available: questions.length);
  }

  Future<QuizSession> startReading({int limit = 2}) =>
      _startVocabularySession(null, limit, 'associativeReading');

  Future<List<QuizWord>> prepareReading({int limit = 2}) async {
    final owner = await owners.getOrCreateActiveOwner();
    return repository.listQuizWords(ownerId: owner.id, limit: limit);
  }

  Future<QuizSession> startReadingForWords({
    required Iterable<String> wordIds,
    int limit = 2,
  }) => _startWordPractice(wordIds, limit, 'associativeReading');

  Future<QuizSession> _startVocabularySession(
    String? categoryId,
    int limit,
    String activityType, {
    String? expectedOwnerId,
    QuizPromptKind kind = QuizPromptKind.meaningChoice,
    QuizOrigin? origin,
    bool skipUnavailable = false,
    String? categoryName,
    String? returnLabel,
    QuizRoundSettings? settings,
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    _checkOrigin(origin, kind: kind, categoryId: categoryId);
    if (settings != null &&
        (origin == null || categoryId == null || !supportsDurableQuiz)) {
      throw StateError('Configured category quiz unavailable');
    }
    final open = await _openRound(owner.id, origin, skipUnavailable);
    if (open != null) return _quizSession(open);
    final questions = await _categoryQuizQuestions(
      owner.id,
      categoryId,
      kind,
      limit,
      configured: settings != null,
    );
    if (settings != null && questions.length < limit) {
      throw QuizRoundShortage(questions.length);
    }
    return _startQuestions(
      owner.id,
      activityType,
      questions,
      origin: origin,
      categoryName: categoryName,
      returnLabel: returnLabel,
      settings: settings,
    );
  }

  Future<List<QuizQuestion>> _categoryQuizQuestions(
    String ownerId,
    String? categoryId,
    QuizPromptKind kind,
    int limit, {
    required bool configured,
  }) async {
    final words = await repository.listQuizWords(
      ownerId: ownerId,
      categoryId: _optionalId(categoryId, 'categoryId'),
      limit: kind == QuizPromptKind.meaningChoice && !configured ? limit : null,
      normalizedSpellings: kind == QuizPromptKind.definitionChoice
          ? QuizPromptPolicy.definitionSpellings
          : null,
      normalizedMeanings: kind == QuizPromptKind.definitionChoice
          ? QuizPromptPolicy.definitionMeanings
          : null,
    );
    final questions = QuizPromptPolicy.build(
      words: words,
      kind: kind,
      limit: limit,
    );
    if (!configured) return questions;
    return questions
        .where((question) => question.options.toSet().length >= 2)
        .toList(growable: false);
  }

  Future<QuizSession> startDueReview({
    int limit = 20,
    String? expectedOwnerId,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    final now = _now();
    final words = await repository.listDueWords(
      ownerId: owner.id,
      nowUtc: now,
      limit: limit,
    );
    if (words.isEmpty) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final sessionId = 'session:${_nextId()}';
    await repository.startSession(
      LearningSessionDraft(
        id: sessionId,
        ownerId: owner.id,
        activityType: 'srsReview',
        startedAtUtc: now,
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
    );
    return QuizSession(
      id: sessionId,
      questions: QuizPromptPolicy.build(
        words: words,
        kind: QuizPromptKind.meaningChoice,
        limit: limit,
      ),
      startedAtUtc: now,
    );
  }

  Future<QuizSession> startWeaknessPractice({
    required Iterable<String> wordIds,
    int limit = 20,
    String? expectedOwnerId,
    QuizPromptKind kind = QuizPromptKind.meaningChoice,
    QuizOrigin? origin,
    bool skipUnavailable = false,
    String? categoryName,
    String? returnLabel,
  }) => _startWordPractice(
    wordIds,
    limit,
    'weaknessPractice',
    expectedOwnerId: expectedOwnerId,
    kind: kind,
    origin: origin,
    skipUnavailable: skipUnavailable,
    categoryName: categoryName,
    returnLabel: returnLabel,
  );

  Future<QuizSession> startGhostDuel({
    required Iterable<String> wordIds,
    int limit = 20,
  }) => _startWordPractice(wordIds, limit, 'ghostDuel');

  Future<QuizSession> startSourcePracticeForWords({
    required Iterable<String> wordIds,
    int limit = 20,
    String? expectedOwnerId,
    QuizPromptKind kind = QuizPromptKind.meaningChoice,
    QuizOrigin? origin,
    bool skipUnavailable = false,
    String? categoryName,
    String? returnLabel,
  }) => _startWordPractice(
    wordIds,
    limit,
    'sourcePractice',
    expectedOwnerId: expectedOwnerId,
    kind: kind,
    origin: origin,
    skipUnavailable: skipUnavailable,
    categoryName: categoryName,
    returnLabel: returnLabel,
  );

  Future<QuizSession> _startWordPractice(
    Iterable<String> wordIds,
    int limit,
    String activityType, {
    String? expectedOwnerId,
    QuizPromptKind kind = QuizPromptKind.meaningChoice,
    QuizOrigin? origin,
    bool skipUnavailable = false,
    String? categoryName,
    String? returnLabel,
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final selectedIds = wordIds.map((id) => _requiredId(id, 'wordId')).toList();
    final requested = selectedIds.toSet();
    if (requested.isEmpty) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    _checkOrigin(origin, kind: kind, wordIds: selectedIds);
    final open = await _openRound(owner.id, origin, skipUnavailable);
    if (open != null) return _quizSession(open);
    final List<QuizQuestion> questions;
    if (kind != QuizPromptKind.meaningChoice) {
      final words = await repository.listQuizWords(
        ownerId: owner.id,
        limit: null,
        normalizedSpellings: kind == QuizPromptKind.definitionChoice
            ? QuizPromptPolicy.definitionSpellings
            : null,
        normalizedMeanings: kind == QuizPromptKind.definitionChoice
            ? QuizPromptPolicy.definitionMeanings
            : null,
      );
      questions = QuizPromptPolicy.build(
        words: words,
        kind: kind,
        limit: limit,
        targetWordIds: requested,
      );
    } else {
      final selected = await repository.listQuizWords(
        ownerId: owner.id,
        wordIds: requested,
        limit: limit,
      );
      final optionWords = selected.isEmpty
          ? const <QuizWord>[]
          : await repository.listQuizWords(ownerId: owner.id, limit: 100);
      questions = QuizPromptPolicy.build(
        words: selected,
        optionWords: optionWords,
        kind: kind,
        limit: limit,
      );
    }
    return _startQuestions(
      owner.id,
      activityType,
      questions,
      origin: origin,
      categoryName: categoryName,
      returnLabel: returnLabel,
    );
  }

  Future<QuizRound?> _openRound(
    String ownerId,
    QuizOrigin? origin,
    bool skipUnavailable,
  ) async {
    final durable = repository;
    if (durable is! DurableQuizRepository || origin == null) return null;
    return durable.findOpenQuizRound(
      ownerId: ownerId,
      origin: origin,
      skipUnavailable: skipUnavailable,
    );
  }

  void _checkOrigin(
    QuizOrigin? origin, {
    required QuizPromptKind kind,
    String? categoryId,
    List<String>? wordIds,
  }) {
    if (origin == null) return;
    final selected = origin.wordIds;
    if (origin.promptKind != kind ||
        (wordIds == null
            ? selected != null || origin.categoryId != categoryId
            : selected == null ||
                  selected.length != wordIds.length ||
                  Iterable<int>.generate(
                    wordIds.length,
                  ).any((index) => wordIds[index] != selected[index]))) {
      throw ArgumentError('Quiz origin does not match the requested practice');
    }
  }

  QuizSession _quizSession(QuizRound round) => QuizSession(
    id: round.sessionId,
    questions: round.plan.questions,
    startedAtUtc: round.startedAtUtc,
    durableRound: round,
  );

  Future<QuizSession> _startQuestions(
    String ownerId,
    String activityType,
    List<QuizQuestion> questions, {
    QuizOrigin? origin,
    String? categoryName,
    String? returnLabel,
    QuizRoundSettings? settings,
  }) async {
    if (questions.isEmpty) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final durable = repository;
    final plan =
        origin != null &&
            durable is DurableQuizRepository &&
            questions.every((question) => question.options.toSet().length >= 2)
        ? QuizPlan(
            origin: origin,
            questions: questions,
            categoryName: categoryName,
            returnLabel: returnLabel,
            settings: settings,
          )
        : null;
    final now = _now();
    final sessionId = 'session:${_nextId()}';
    await repository.startSession(
      LearningSessionDraft(
        id: sessionId,
        ownerId: ownerId,
        activityType: activityType,
        startedAtUtc: now,
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
        quizPlan: plan,
      ),
    );
    if (plan != null && durable is DurableQuizRepository) {
      final round = await durable.loadQuizRound(
        ownerId: ownerId,
        sessionId: sessionId,
      );
      if (round == null) throw StateError('Saved quiz round is missing');
      return _quizSession(round);
    }
    return QuizSession(id: sessionId, questions: questions, startedAtUtc: now);
  }

  Future<QuizRound?> loadQuizRound(
    String sessionId, {
    required String expectedOwnerId,
  }) async {
    final durable = repository;
    if (durable is! DurableQuizRepository) return null;
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    return durable.loadQuizRound(ownerId: owner.id, sessionId: sessionId);
  }

  Future<QuizRound> advanceQuizRound(
    String sessionId, {
    required int expectedRevision,
    required QuizStep step,
    required String expectedOwnerId,
    int activeResponseMs = 0,
  }) async {
    final durable = repository;
    if (durable is! DurableQuizRepository) {
      throw StateError('Quiz recovery unavailable');
    }
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    final round = await durable.advanceQuizRound(
      ownerId: owner.id,
      sessionId: sessionId,
      expectedRevision: expectedRevision,
      step: step,
      atUtc: _now(),
      activeResponseMs: activeResponseMs,
    );
    if (step == QuizStep.finish) onLocalMutation?.call();
    return round;
  }

  Future<AnswerRecordResult> recordAnswer({
    required String sessionId,
    required String wordId,
    required String promptMode,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    String? providerProvenance,
    String? attemptId,
    DateTime? occurredAtUtc,
    String? expectedOwnerId,
    QuizAdmission? quiz,
    SrsRecallSnapshot? srsRecallSnapshot,
  }) async {
    if ((attemptId == null) != (occurredAtUtc == null)) {
      throw ArgumentError(
        'retry identity and timestamp must be supplied together',
      );
    }
    final recordedAt = occurredAtUtc ?? _now();
    if (!recordedAt.isUtc) throw ArgumentError('occurredAtUtc must be UTC');
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    final command = RecordAnswerCommand(
      id: attemptId == null
          ? 'attempt:${_nextId()}'
          : _requiredId(attemptId, 'attemptId'),
      ownerId: owner.id,
      sessionId: _requiredId(sessionId, 'sessionId'),
      wordId: _requiredId(wordId, 'wordId'),
      promptMode: _requiredId(promptMode, 'promptMode'),
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      occurredAtUtc: recordedAt,
      providerProvenance: providerProvenance,
      quiz: quiz,
      srsRecallSnapshot: srsRecallSnapshot,
    );
    final result = await repository.recordAnswer(command);
    onLocalMutation?.call();

    // Shadow V2 reward pipeline — runs after production succeeds.
    // Errors are swallowed: shadow mode must never break production.
    final shadow = shadowOrchestrator;
    final adapter = eventAdapter;
    if (shadow != null && adapter != null) {
      try {
        final v2Event = adapter.adaptFromCommand(
          ownerId: owner.id,
          sessionId: _requiredId(sessionId, 'sessionId'),
          wordId: _requiredId(wordId, 'wordId'),
          promptMode: _requiredId(promptMode, 'promptMode'),
          isCorrect: isCorrect,
          responseTimeMs: responseTimeMs,
          attemptNumber: attemptNumber,
          occurredAtUtc: recordedAt,
          providerProvenance: providerProvenance,
          appVersion: buildInfo.version,
          buildId: buildInfo.buildId,
        );
        await shadow.processShadow(v2Event);
      } catch (_) {
        // Intentionally swallowed — shadow mode must never break production.
      }
    }

    try {
      await onAnswerCommitted?.call(
        ownerId: command.ownerId,
        attemptId: command.id,
        occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
      );
    } catch (_) {
      // Durable answers remain available for startup or replay repair.
    }

    return result;
  }

  Future<LearningSessionSummary> finishSession(
    String sessionId, {
    String? expectedOwnerId,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    final result = await repository.finishSession(
      ownerId: owner.id,
      sessionId: _requiredId(sessionId, 'sessionId'),
      endedAtUtc: _now(),
    );
    onLocalMutation?.call();
    return result;
  }

  void _requireExpectedOwner(String actualOwnerId, String? expectedOwnerId) {
    if (expectedOwnerId != null &&
        actualOwnerId != _requiredId(expectedOwnerId, 'expectedOwnerId')) {
      throw StateError('learning owner is no longer active');
    }
  }

  Future<ReadingProgressSnapshot?> loadReadingProgress({
    required String documentId,
    required int documentRevision,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    return repository.readReadingProgress(
      ownerId: owner.id,
      documentId: _requiredId(documentId, 'documentId'),
      documentRevision: documentRevision,
    );
  }

  Future<ReadingProgressSnapshot> saveReadingProgress({
    required String documentId,
    required int documentRevision,
    required int position,
    required bool isCompleted,
    String? expectedOwnerId,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    final expected = expectedOwnerId?.trim();
    if (expected != null && expected.isNotEmpty && owner.id != expected) {
      throw StateError('reading owner is no longer active');
    }
    final result = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-event:${_nextId()}',
        ownerId: expected == null || expected.isEmpty ? owner.id : expected,
        documentId: _requiredId(documentId, 'documentId'),
        documentRevision: documentRevision,
        position: position,
        isCompleted: isCompleted,
        occurredAtUtc: _now(),
      ),
    );
    onLocalMutation?.call();
    return result;
  }

  String _nextId() {
    final value = generateId().trim();
    if (value.isEmpty) throw StateError('learning id generator returned blank');
    return value;
  }

  DateTime _now() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
    return value;
  }

  String _requiredId(String value, String field) {
    final canonical = value.trim();
    if (canonical.isEmpty || canonical.length > 256) {
      throw ArgumentError.value(value, field, 'invalid identifier');
    }
    return canonical;
  }

  String? _optionalId(String? value, String field) {
    return value == null ? null : _requiredId(value, field);
  }
}
