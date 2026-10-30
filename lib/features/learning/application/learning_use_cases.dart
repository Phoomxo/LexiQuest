import 'dart:convert';

import '../../../ai/ai_models.dart';
import '../../../ai/content_provider.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../../runtime/app_build_info.dart';
import '../../events/application/event_v1_to_v2_adapter.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../rewards/application/shadow_reward_orchestrator.dart';
import '../domain/accepted_quiz_plan.dart';
import '../domain/cloze_content.dart';
import '../domain/evidence_context.dart';
import '../domain/evidence_eligibility_policy.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import '../domain/sentence_scramble_content.dart';
import 'current_activity_evidence.dart';

typedef LearningIdGenerator = String Function();
typedef LearningUtcNow = DateTime Function();
typedef LearningMutationNotifier = void Function();

/// Receives a [EventEnvelopeV2] produced from every recorded answer.
///
/// Used by callers (e.g. [AppDependencies]) to forward learning events into
/// the quest pipeline when [Feature.questV2] is enabled.  Errors from the
/// sink are swallowed — the sink must never break production.
typedef QuestEventSink = Future<void> Function(EventEnvelopeV2 event);

/// Called after every successful `recordAnswer` so that [StreakUseCases] can
/// log the learning day and update streak counters.
///
/// No argument — the streak use case resolves the owner and the current UTC
/// time from its own injected dependencies.  Errors are swallowed.
typedef StreakEventSink = Future<void> Function();

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
    this.questEventSink,
    this.streakEventSink,
    this.contentProvider,
  });

  final LocalOwnerRepository owners;
  final LearningRepository repository;
  final LearningIdGenerator generateId;
  final LearningUtcNow nowUtc;
  final AppBuildInfo buildInfo;
  final ContentProvider? contentProvider;
  final LearningMutationNotifier? onLocalMutation;
  final Expando<bool> _finishedNativeNotifications = Expando<bool>();

  /// Shadow mode — when non-null, every recorded answer is also run through
  /// the V2 reward eligibility pipeline in dry-run mode.  Null = disabled.
  final ShadowRewardOrchestrator? shadowOrchestrator;

  /// Required when [shadowOrchestrator] is non-null; adapts V1 commands to
  /// [EventEnvelopeV2] for shadow processing.
  final EventV1ToV2Adapter? eventAdapter;

  /// Quest pipeline hook — when non-null, the V2 event from each answer is
  /// forwarded to [QuestUseCases.processEvent] (or a compatible consumer).
  ///
  /// Wired at the [AppDependencies] composition root when
  /// `Feature.questV2` is enabled.  Errors are swallowed.
  final QuestEventSink? questEventSink;

  /// Streak pipeline hook — when non-null, called after every successful
  /// answer so that [StreakUseCases.recordLearningDay] can update counters.
  ///
  /// Wired at the [AppDependencies] composition root.  Errors are swallowed.
  final StreakEventSink? streakEventSink;

  Future<QuizSession> startQuiz({String? categoryId, int limit = 10}) =>
      _startConfigured(
        QuizConfiguration.category(
          categoryId: _optionalId(categoryId, 'categoryId'),
          limit: limit,
        ),
      );

  Future<QuizSession> startReading({int limit = 2}) =>
      _startVocabularySession(null, limit, 'associativeReading');

  NativeExerciseRepository get _nativeExercises => switch (repository) {
    final NativeExerciseRepository capability => capability,
    _ => throw StateError('Dictation persistence is unavailable'),
  };

  Future<DictationSession?> prepareDictation({
    String? categoryId,
    required bool Function() stillCurrent,
  }) async {
    _requireCurrentNativeExercise(stillCurrent);
    final owner = await owners.getOrCreateActiveOwner();
    _requireCurrentNativeExercise(stillCurrent);
    final words = await repository.listQuizWords(
      ownerId: owner.id,
      categoryId: _optionalId(categoryId, 'categoryId'),
      limit: 1,
    );
    _requireCurrentNativeExercise(stillCurrent);
    final currentOwner = await owners.getOrCreateActiveOwner();
    if (currentOwner.id != owner.id) {
      throw StateError('Dictation owner changed');
    }
    _requireCurrentNativeExercise(stillCurrent);
    if (words.isEmpty) return null;
    return DictationSession(
      session: LearningSessionDraft(
        id: '${DictationSession.idPrefix}${_nextId()}',
        ownerId: owner.id,
        activityType: 'dictation',
        startedAtUtc: _now(),
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
      word: words.single,
    );
  }

  Future<WordScrambleSession?> prepareWordScramble({
    String? categoryId,
    required bool Function() stillCurrent,
  }) async {
    _requireCurrentNativeExercise(stillCurrent);
    final owner = await owners.getOrCreateActiveOwner();
    _requireCurrentNativeExercise(stillCurrent);
    final candidates = await _nativeWordCandidates(
      ownerId: owner.id,
      categoryId: _optionalId(categoryId, 'categoryId'),
      supports: WordScrambleSession.supportsTarget,
      count: 1,
      stillCurrent: stillCurrent,
    );
    final currentOwner = await owners.getOrCreateActiveOwner();
    if (currentOwner.id != owner.id) {
      throw StateError('Word Scramble owner changed');
    }
    _requireCurrentNativeExercise(stillCurrent);
    final target = candidates.firstOrNull;
    if (target == null) return null;
    return WordScrambleSession(
      session: LearningSessionDraft(
        id: '${WordScrambleSession.idPrefix}${_nextId()}',
        ownerId: owner.id,
        activityType: 'wordScramble',
        startedAtUtc: _now(),
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
      word: target,
    );
  }

  Future<SentenceScrambleSession?> prepareSentenceScramble({
    String? categoryId,
    required bool Function() stillCurrent,
  }) async {
    _requireCurrentNativeExercise(stillCurrent);
    final provider = contentProvider;
    if (provider == null) return null;
    if (await _nativeExercises.hasAmbientTransaction()) {
      throw StateError(
        'Sentence Scramble generation requires an independent read boundary',
      );
    }
    _requireCurrentNativeExercise(stillCurrent);
    final owner = await owners.getOrCreateActiveOwner();
    _requireCurrentNativeExercise(stillCurrent);
    final candidates = await _nativeWordCandidates(
      ownerId: owner.id,
      categoryId: _optionalId(categoryId, 'categoryId'),
      supports: (word) => SentenceScrambleContent.supportsTarget(word.spelling),
      count: 1,
      stillCurrent: stillCurrent,
    );
    final target = candidates.firstOrNull;
    if (target == null) return null;
    if (await _nativeExercises.hasAmbientTransaction()) {
      throw StateError(
        'Sentence Scramble generation requires an independent read boundary',
      );
    }
    _requireCurrentNativeExercise(stillCurrent);
    final beforeGenerationOwner = await owners.getOrCreateActiveOwner();
    if (beforeGenerationOwner.id != owner.id) {
      throw StateError('Sentence Scramble owner changed');
    }
    _requireCurrentNativeExercise(stillCurrent);
    final response = await provider.generate(
      ContentRequest.create(
        text: target.spelling,
        kind: ContentKind.sentence,
        cefr: CefrLevel.a2,
        language: 'en',
      ),
    );
    _requireCurrentNativeExercise(stillCurrent);
    final currentOwner = await owners.getOrCreateActiveOwner();
    if (currentOwner.id != owner.id) {
      throw StateError('Sentence Scramble owner changed');
    }
    _requireCurrentNativeExercise(stillCurrent);
    final SentenceScrambleContent content;
    try {
      content = SentenceScrambleContent.parse(
        targetSpelling: target.spelling,
        response: response,
      );
    } on FormatException {
      return null;
    }
    final draft = LearningSessionDraft(
      id: '${SentenceScrambleSession.idPrefix}${_nextId()}',
      ownerId: owner.id,
      activityType: 'sentenceScramble',
      startedAtUtc: _now(),
      appVersion: buildInfo.version,
      buildId: buildInfo.buildId,
    );
    _requireCurrentNativeExercise(stillCurrent);
    return SentenceScrambleSession(
      session: draft,
      word: target,
      content: content,
    );
  }

  Future<ClozeSession?> prepareCloze({
    String? categoryId,
    required ClozeVariant variant,
    required bool Function() stillCurrent,
  }) async {
    _requireCurrentNativeExercise(stillCurrent);
    final provider = contentProvider;
    if (provider == null) return null;
    if (await _nativeExercises.hasAmbientTransaction()) {
      throw StateError(
        'Cloze generation requires an independent read boundary',
      );
    }
    _requireCurrentNativeExercise(stillCurrent);
    final owner = await owners.getOrCreateActiveOwner();
    _requireCurrentNativeExercise(stillCurrent);
    final selectedCategory = _optionalId(categoryId, 'categoryId');
    bool supports(QuizWord word) => ClozeContent.supportsTarget(word.spelling);
    QuizWord? target;
    var choices = <QuizWord>[];
    List<QuizWord> candidates;
    if (variant == ClozeVariant.typed) {
      candidates = await _nativeWordCandidates(
        ownerId: owner.id,
        categoryId: selectedCategory,
        supports: supports,
        count: 1,
        stillCurrent: stillCurrent,
      );
    } else if (selectedCategory != null) {
      candidates = await _nativeWordCandidates(
        ownerId: owner.id,
        categoryId: selectedCategory,
        supports: supports,
        count: 3,
        distinctSpellings: true,
        stillCurrent: stillCurrent,
      );
    } else {
      // Preserve the first eligible category in global lexical ID order,
      // retaining only its three choices rather than all categories' words.
      candidates = <QuizWord>[];
      String? afterCandidateId;
      final rejectedCategories = <String>{};
      while (candidates.isEmpty) {
        final next = await _nativeWordCandidates(
          ownerId: owner.id,
          categoryId: null,
          afterWordId: afterCandidateId,
          supports: (word) =>
              !rejectedCategories.contains(word.categoryId) && supports(word),
          count: 1,
          stillCurrent: stillCurrent,
        );
        if (next.isEmpty) {
          break;
        }
        final candidate = next.single;
        final sameCategory = await _nativeWordCandidates(
          ownerId: owner.id,
          categoryId: candidate.categoryId,
          supports: supports,
          count: 3,
          distinctSpellings: true,
          stillCurrent: stillCurrent,
        );
        if (sameCategory.length == 3) {
          candidates = sameCategory;
        } else {
          rejectedCategories.add(candidate.categoryId);
        }
        afterCandidateId = candidate.id;
      }
    }
    if (variant == ClozeVariant.typed && candidates.isNotEmpty) {
      target = candidates.single;
    } else if (candidates.length == 3) {
      target = candidates.first;
      final offset =
          target.id.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
          candidates.length;
      choices = [...candidates.skip(offset), ...candidates.take(offset)];
    }
    if (target == null) return null;
    if (await _nativeExercises.hasAmbientTransaction()) {
      throw StateError(
        'Cloze generation requires an independent read boundary',
      );
    }
    _requireCurrentNativeExercise(stillCurrent);
    final beforeGenerationOwner = await owners.getOrCreateActiveOwner();
    if (beforeGenerationOwner.id != owner.id) {
      throw StateError('Cloze owner changed');
    }
    _requireCurrentNativeExercise(stillCurrent);
    final response = await provider.generate(
      ContentRequest.create(
        text: target.spelling,
        kind: ContentKind.sentence,
        cefr: CefrLevel.a2,
        language: 'en',
      ),
    );
    _requireCurrentNativeExercise(stillCurrent);
    final currentOwner = await owners.getOrCreateActiveOwner();
    if (currentOwner.id != owner.id) throw StateError('Cloze owner changed');
    _requireCurrentNativeExercise(stillCurrent);
    final ClozeContent content;
    try {
      content = ClozeContent.parse(
        targetSpelling: target.spelling,
        response: response,
      );
    } on FormatException {
      return null;
    }
    final draft = LearningSessionDraft(
      id: '${ClozeSession.idPrefix}${_nextId()}',
      ownerId: owner.id,
      activityType: 'cloze',
      startedAtUtc: _now(),
      appVersion: buildInfo.version,
      buildId: buildInfo.buildId,
    );
    _requireCurrentNativeExercise(stillCurrent);
    return switch (variant) {
      ClozeVariant.typed => TypedClozeSession(
        session: draft,
        word: target,
        content: content,
      ),
      ClozeVariant.choice => ChoiceClozeSession(
        session: draft,
        word: target,
        content: content,
        choices: choices,
      ),
    };
  }

  Future<List<QuizWord>> _nativeWordCandidates({
    required String ownerId,
    required String? categoryId,
    required bool Function(QuizWord word) supports,
    required int count,
    required bool Function() stillCurrent,
    bool distinctSpellings = false,
    String? afterWordId,
  }) async {
    final candidates = <QuizWord>[];
    var cursor = afterWordId;
    while (candidates.length < count) {
      final page = await repository.listQuizWords(
        ownerId: ownerId,
        categoryId: categoryId,
        afterWordId: cursor,
        limit: 100,
      );
      _requireCurrentNativeExercise(stillCurrent);
      for (final word in page) {
        if (!supports(word) ||
            candidates.any((saved) => saved.id == word.id) ||
            (distinctSpellings &&
                candidates.any(
                  (saved) =>
                      saved.spelling.trim().toLowerCase() ==
                      word.spelling.trim().toLowerCase(),
                ))) {
          continue;
        }
        candidates.add(word);
        if (candidates.length == count) {
          return candidates;
        }
      }
      if (page.length < 100) {
        return candidates;
      }
      final nextCursor = page.last.id;
      if (nextCursor == cursor) {
        throw StateError('Native word page did not advance');
      }
      cursor = nextCursor;
    }
    return candidates;
  }

  Future<T> startNativeExercise<T extends AcceptedNativeExercise>(
    T exercise, {
    required bool Function() stillCurrent,
  }) => _nativeExercises.startNativeExercise(
    exercise,
    stillCurrent: stillCurrent,
  );

  RecordAnswerCommand prepareNativeAnswer(NativeAnswerInput input) {
    final exercise = input.exercise;
    final occurredAt = _now();
    if (occurredAt.isBefore(exercise.startedAtUtc)) {
      throw StateError('Dictation clock precedes its original start');
    }
    final (promptMode, isCorrect, hintLevel) = switch (input) {
      DictationAnswerInput(:final exercise, :final response, :final assisted) =>
        (
          'dictation',
          response.trim().toLowerCase() ==
              exercise.word.spelling.trim().toLowerCase(),
          assisted ? 1 : 0,
        ),
      WordScrambleAnswerInput(:final exercise, :final response) => (
        'wordScramble',
        response.trim().toLowerCase() ==
            exercise.word.spelling.trim().toLowerCase(),
        0,
      ),
      SentenceScrambleAnswerInput(:final exercise, :final response) => (
        'sentenceScramble',
        exercise.content.matchesResponse(response),
        0,
      ),
      TypedClozeAnswerInput(:final exercise, :final response) => (
        'clozeTyped',
        response.trim().toLowerCase() == exercise.word.spelling.toLowerCase(),
        1,
      ),
      ChoiceClozeAnswerInput(:final exercise, :final optionId)
          when exercise.choices.any((option) => option.id == optionId) =>
        ('clozeChoice', optionId == exercise.word.id, 0),
      ChoiceClozeAnswerInput() => throw ArgumentError(
        'Cloze response is not one of its original choices',
      ),
    };
    return RecordAnswerCommand(
      id: 'attempt:${_nextId()}',
      ownerId: exercise.ownerId,
      sessionId: exercise.id,
      wordId: exercise.word.id,
      promptMode: promptMode,
      isCorrect: isCorrect,
      responseTimeMs: input.responseTime.inMilliseconds
          .clamp(0, LearningEvidenceContract.maxResponseTimeMs)
          .toInt(),
      attemptNumber: 1,
      occurredAtUtc: occurredAt,
      providerProvenance: switch (exercise) {
        DictationSession() => null,
        WordScrambleSession() => null,
        SentenceScrambleSession() => exercise.providerProvenance,
        ClozeSession() => exercise.providerProvenance,
      },
      evidenceContext: captureCurrentActivityEvidence(
        promptMode: promptMode,
        contentRevision: exercise.evidenceContentRevision,
        hintLevel: hintLevel,
      ),
    );
  }

  Future<AnswerRecordResult> commitNativeAnswer(
    AcceptedNativeExercise exercise,
    RecordAnswerCommand command, {
    required bool Function() stillCurrent,
  }) async {
    final result = await _nativeExercises.commitNativeAnswer(
      exercise,
      command,
      stillCurrent: stillCurrent,
    );
    await _afterRecordedAnswer(command, result);
    return result;
  }

  NativeFinishIntent prepareNativeFinish(
    AcceptedNativeExercise exercise,
    RecordAnswerCommand answer,
  ) {
    final endedAt = _now();
    if (endedAt.isBefore(answer.occurredAtUtc)) {
      throw StateError('Dictation clock precedes its saved answer');
    }
    return NativeFinishIntent(
      exercise: exercise,
      answer: answer,
      endedAtUtc: endedAt,
    );
  }

  Future<LearningSessionSummary> finishNativeExercise(
    NativeFinishIntent intent, {
    required bool Function() stillCurrent,
  }) async {
    final result = await _nativeExercises.finishNativeExercise(
      intent,
      stillCurrent: stillCurrent,
    );
    if (_finishedNativeNotifications[intent.exercise] != true) {
      _finishedNativeNotifications[intent.exercise] = true;
      onLocalMutation?.call();
    }
    return result;
  }

  void _requireCurrentNativeExercise(bool Function() stillCurrent) {
    if (!stillCurrent()) throw StateError('Dictation is no longer current');
  }

  SrsReviewRepository get _srsReviews => switch (repository) {
    SrsReviewRepository capability => capability,
    _ => throw StateError('Owned SRS review persistence is unavailable'),
  };

  final _srsScopes = Expando<_SrsUseCaseScope>();

  Future<SrsReviewSession?> prepareSrsReview({
    required String expectedOwnerId,
    Iterable<String>? sourceWordIds,
    int limit = 20,
    required bool Function() stillCurrent,
  }) async {
    if (!stillCurrent()) throw StateError('SRS review is no longer current');
    final owner = _requiredId(expectedOwnerId, 'expectedOwnerId');
    if (limit < 1 || limit > 20) {
      throw RangeError.range(limit, 1, 20, 'limit');
    }
    final selected = sourceWordIds
        ?.map((id) => _requiredId(id, 'wordId'))
        .toList(growable: false);
    if (selected != null &&
        (selected.length > limit ||
            selected.toSet().length != selected.length)) {
      throw ArgumentError('SRS source selection must contain unique owned IDs');
    }
    if (selected?.isEmpty ?? false) return null;
    final review = await _srsReviews.prepareSrsReview(
      session: LearningSessionDraft(
        id: '${SrsReviewSession.idPrefix}${_nextId()}',
        ownerId: owner,
        activityType: 'srsReview',
        startedAtUtc: _srsNow(),
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
      selection: selected == null
          ? SrsReviewSelection.due
          : SrsReviewSelection.source,
      sourceWordIds: selected == null ? null : List.unmodifiable(selected),
      limit: limit,
      stillCurrent: stillCurrent,
    );
    if (!stillCurrent()) throw StateError('SRS review is no longer current');
    if (review != null) {
      if (review.ownerId != owner) {
        throw StateError('SRS review owner changed');
      }
      _srsScopes[review] = _SrsUseCaseScope(stillCurrent);
    }
    return review;
  }

  _SrsUseCaseScope _srsScope(SrsReviewSession review) {
    final scope = _srsScopes[review];
    if (scope == null) {
      throw StateError('SRS review requires its original preparing usecase');
    }
    if (scope.invalidated || !scope.current()) {
      scope.invalidated = true;
      throw StateError('SRS review is no longer current');
    }
    return scope;
  }

  bool _currentSrs(SrsReviewSession review, bool Function() stillCurrent) {
    final scope = _srsScope(review);
    if (!stillCurrent()) {
      scope.invalidated = true;
      return false;
    }
    return true;
  }

  Future<SrsReviewSession> startSrsReview(
    SrsReviewSession review, {
    required bool Function() stillCurrent,
  }) async {
    final scope = _srsScope(review);
    final result = await _srsReviews.startSrsReview(
      review,
      stillCurrent: () => _currentSrs(review, stillCurrent),
    );
    if (!_currentSrs(review, stillCurrent) ||
        !identical(result.review, review)) {
      throw StateError('SRS start receipt changed');
    }
    scope.started = true;
    if (!scope.startNotified) {
      scope.startNotified = true;
      _notifySrsReceipt();
    }
    return review;
  }

  SrsReviewAnswerIntent prepareSrsRating({
    required SrsReviewSession review,
    required int cardIndex,
    required bool recalled,
    required int? responseTimeMs,
  }) {
    final scope = _srsScope(review);
    if (!scope.started || scope.closing != null) {
      throw StateError('SRS rating requires its original active start receipt');
    }
    if (cardIndex < 0 || cardIndex >= review.words.length) {
      throw RangeError.range(
        cardIndex,
        0,
        review.words.length - 1,
        'cardIndex',
      );
    }
    if (responseTimeMs != null &&
        (responseTimeMs < 0 ||
            responseTimeMs > LearningEvidenceContract.maxResponseTimeMs)) {
      throw ArgumentError.value(responseTimeMs, 'responseTimeMs');
    }
    final original = scope.answers[cardIndex];
    if (original != null) {
      if (original.command.isCorrect != recalled ||
          original.command.responseTimeMs != responseTimeMs) {
        throw StateError('SRS pending rating changed');
      }
      return original;
    }
    if (cardIndex != scope.confirmed.length) {
      throw StateError('SRS requires the previous original rating receipt');
    }
    final word = review.words[cardIndex];
    final intent = SrsReviewAnswerIntent(
      review: review,
      cardIndex: cardIndex,
      command: RecordAnswerCommand(
        id: 'attempt:srs:${review.id}:$cardIndex',
        ownerId: review.ownerId,
        sessionId: review.id,
        wordId: word.id,
        promptMode: 'srsRecall',
        isCorrect: recalled,
        responseTimeMs: responseTimeMs,
        attemptNumber: cardIndex + 1,
        occurredAtUtc: _srsNow(),
        evidenceContext: captureCurrentActivityEvidence(
          promptMode: 'srsRecall',
          contentRevision: word.contentRevision,
        ),
      ),
    );
    scope.answers[cardIndex] = intent;
    return intent;
  }

  Future<AnswerRecordResult> commitSrsRating(
    SrsReviewAnswerIntent intent, {
    required bool Function() stillCurrent,
  }) async {
    final review = intent.review;
    final scope = _srsScope(review);
    if (!scope.started || !identical(scope.answers[intent.cardIndex], intent)) {
      throw StateError('SRS rating requires its original pending intent');
    }
    final result = await _srsReviews.commitSrsRating(
      intent,
      stillCurrent: () => _currentSrs(review, stillCurrent),
    );
    if (!_currentSrs(review, stillCurrent)) {
      throw StateError('SRS rating receipt is no longer current');
    }
    scope.confirmed.add(intent.cardIndex);
    if (scope.notifiedAnswers.add(intent.cardIndex)) {
      _notifySrsReceipt();
      await _afterAnswerSinks(intent.command);
    }
    return result;
  }

  SrsReviewFinishIntent prepareSrsFinish(SrsReviewSession review) {
    final scope = _srsScope(review);
    if (!scope.started || scope.confirmed.length != review.words.length) {
      throw StateError('SRS completion requires every original rating receipt');
    }
    final original = scope.closing;
    if (original != null) return original;
    final endedAt = _srsNow();
    if (scope.answers.values.any(
      (answer) => endedAt.isBefore(answer.command.occurredAtUtc),
    )) {
      throw ArgumentError('SRS end precedes its original ratings');
    }
    return scope.closing = SrsReviewFinishIntent(
      review: review,
      endedAtUtc: endedAt,
    );
  }

  Future<LearningSessionSummary> finishSrsReview(
    SrsReviewFinishIntent intent, {
    required bool Function() stillCurrent,
  }) async {
    final review = intent.review;
    final scope = _srsScope(review);
    if (!identical(scope.closing, intent)) {
      throw StateError('SRS completion requires its original close intent');
    }
    final result = await _srsReviews.finishSrsReview(
      intent,
      stillCurrent: () => _currentSrs(review, stillCurrent),
    );
    if (!_currentSrs(review, stillCurrent)) {
      throw StateError('SRS completion receipt is no longer current');
    }
    if (!scope.finishNotified) {
      scope.finishNotified = true;
      _notifySrsReceipt();
    }
    return result.summary;
  }

  DateTime _srsNow() => DateTime.fromMillisecondsSinceEpoch(
    _now().millisecondsSinceEpoch,
    isUtc: true,
  );

  void _notifySrsReceipt() {
    try {
      onLocalMutation?.call();
    } on Object {
      // A committed original receipt remains valid if optional notification fails.
    }
  }

  Future<QuizSession> startShadowing({int limit = 1}) =>
      _startVocabularySession(null, limit, 'shadowing');

  Future<QuizSession> startSourcePronunciationForWords({
    required Iterable<String> wordIds,
    int limit = 1,
  }) => _startWordPractice(wordIds, limit, 'pronunciation');

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
    String activityType,
  ) async {
    final owner = await owners.getOrCreateActiveOwner();
    final words = await repository.listQuizWords(
      ownerId: owner.id,
      categoryId: _optionalId(categoryId, 'categoryId'),
      limit: limit,
    );
    if (words.isEmpty) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final now = _now();
    final sessionId = 'session:${_nextId()}';
    await repository.startSession(
      LearningSessionDraft(
        id: sessionId,
        ownerId: owner.id,
        activityType: activityType,
        startedAtUtc: now,
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
    );
    return QuizSession(
      id: sessionId,
      startedAtUtc: now,
      questions: _questions(words),
    );
  }

  Future<QuizSession> startWeaknessPractice({
    required Iterable<String> wordIds,
    int limit = 20,
  }) {
    final requested = wordIds.map((id) => _requiredId(id, 'wordId')).toList();
    if (requested.isEmpty) {
      return Future.value(
        const QuizSession(id: '', questions: [], startedAtUtc: null),
      );
    }
    return _startConfigured(
      QuizConfiguration.weaknessPractice(wordIds: requested, limit: limit),
    );
  }

  Future<QuizSession> startGhostDuel({
    required Iterable<String> wordIds,
    int limit = 20,
  }) => _startWordPractice(wordIds, limit, 'ghostDuel');

  Future<QuizSession> startSourcePracticeForWords({
    required Iterable<String> wordIds,
    int limit = 20,
  }) {
    final requested = wordIds.map((id) => _requiredId(id, 'wordId')).toList();
    if (requested.isEmpty) {
      return Future.value(
        const QuizSession(id: '', questions: [], startedAtUtc: null),
      );
    }
    return _startConfigured(
      QuizConfiguration.sourcePractice(wordIds: requested, limit: limit),
    );
  }

  Future<QuizSession> _startWordPractice(
    Iterable<String> wordIds,
    int limit,
    String activityType,
  ) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final requested = wordIds.map((id) => _requiredId(id, 'wordId')).toSet();
    if (requested.isEmpty) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final owner = await owners.getOrCreateActiveOwner();
    final selected = await repository.listQuizWords(
      ownerId: owner.id,
      wordIds: requested,
      limit: limit,
    );
    if (selected.isEmpty) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final optionWords = await repository.listQuizWords(
      ownerId: owner.id,
      limit: 100,
    );
    final now = _now();
    final sessionId = 'session:${_nextId()}';
    await repository.startSession(
      LearningSessionDraft(
        id: sessionId,
        ownerId: owner.id,
        activityType: activityType,
        startedAtUtc: now,
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
    );
    return QuizSession(
      id: sessionId,
      questions: _questions([...selected], optionWords: optionWords),
      startedAtUtc: now,
    );
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
    EvidenceContext? evidenceContext,
  }) async {
    if ((attemptId == null) != (occurredAtUtc == null)) {
      throw ArgumentError(
        'retry identity and timestamp must be supplied together',
      );
    }
    final recordedAt = occurredAtUtc ?? _now();
    if (!recordedAt.isUtc) throw ArgumentError('occurredAtUtc must be UTC');
    final owner = await owners.getOrCreateActiveOwner();
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
      evidenceContext: evidenceContext,
    );
    final result = await repository.recordAnswer(command);
    await _afterRecordedAnswer(command, result);
    return result;
  }

  Future<void> _afterRecordedAnswer(
    RecordAnswerCommand command,
    AnswerRecordResult result,
  ) async {
    if (!result.inserted) return;
    onLocalMutation?.call();
    await _afterAnswerSinks(command);
  }

  Future<void> _afterAnswerSinks(RecordAnswerCommand command) async {
    // Shadow V2 reward pipeline — runs after production succeeds.
    // Errors are swallowed: shadow mode must never break production.
    final shadow = shadowOrchestrator;
    final adapter = eventAdapter;
    if (shadow != null &&
        adapter != null &&
        _allowsProjection(command, LearningProjection.xp) &&
        _allowsProjection(command, LearningProjection.coins)) {
      try {
        final v2Event = adapter.adaptFromCommand(
          attemptId: command.id,
          ownerId: command.ownerId,
          sessionId: command.sessionId,
          wordId: command.wordId,
          promptMode: command.promptMode,
          isCorrect: command.isCorrect,
          responseTimeMs: command.responseTimeMs,
          attemptNumber: command.attemptNumber,
          occurredAtUtc: command.occurredAtUtc,
          providerProvenance: command.providerProvenance,
          appVersion: buildInfo.version,
          buildId: buildInfo.buildId,
        );
        await shadow.processShadow(v2Event);
      } catch (_) {
        // Intentionally swallowed — shadow mode must never break production.
      }
    }

    // Quest pipeline hook — forward answer event to quest use cases.
    // Both optional sinks use the canonical persisted answer identity.
    // Errors are swallowed.
    final questSink = questEventSink;
    if (questSink != null &&
        _allowsProjection(command, LearningProjection.quest)) {
      try {
        final questEvent = adapter?.adaptFromCommand(
          attemptId: command.id,
          ownerId: command.ownerId,
          sessionId: command.sessionId,
          wordId: command.wordId,
          promptMode: command.promptMode,
          isCorrect: command.isCorrect,
          responseTimeMs: command.responseTimeMs,
          attemptNumber: command.attemptNumber,
          occurredAtUtc: command.occurredAtUtc,
          providerProvenance: command.providerProvenance,
          appVersion: buildInfo.version,
          buildId: buildInfo.buildId,
        );
        if (questEvent != null) {
          await questSink(questEvent);
        }
      } catch (_) {
        // Intentionally swallowed — quest hook must never break production.
      }
    }

    // Streak hook — notify StreakUseCases that a learning event occurred.
    // Errors are swallowed — streak tracking must never break production.
    try {
      if (_allowsProjection(command, LearningProjection.streak)) {
        await streakEventSink?.call();
      }
    } catch (_) {}
  }

  bool _allowsProjection(
    RecordAnswerCommand command,
    LearningProjection projection,
  ) => LearningEvidenceContract.allowsOrdinaryProjection(
    promptMode: command.promptMode,
    evidenceClass: command.evidenceContext.evidenceClass.name,
    evidenceContextJson: jsonEncode(command.evidenceContext.toJson()),
    projection: projection,
  );

  Future<LearningSessionSummary> finishSession(String sessionId) async {
    final owner = await owners.getOrCreateActiveOwner();
    final result = await repository.finishSession(
      ownerId: owner.id,
      sessionId: _requiredId(sessionId, 'sessionId'),
      endedAtUtc: _now(),
    );
    onLocalMutation?.call();
    return result;
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

  final _freshQuizQuestions =
      <({String ownerId, String sessionId, int ordinal})>{};

  ConfiguredQuizRepository get _configured => switch (repository) {
    ConfiguredQuizRepository capability => capability,
    _ => throw StateError('configured quiz repository capability unavailable'),
  };

  Future<ConfiguredQuizLaunch> prepareConfiguredQuiz({
    required QuizConfiguration configuration,
    String? expectedOwnerId,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    if (expectedOwnerId != null && owner.id != expectedOwnerId) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.ownerChanged,
      );
    }
    return ConfiguredQuizLaunch(
      session: LearningSessionDraft(
        id: 'session:${_nextId()}',
        ownerId: owner.id,
        activityType: configuration.activityType,
        startedAtUtc: _now(),
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
      configuration: configuration,
    );
  }

  Future<ConfiguredQuizState> startConfiguredQuiz(
    ConfiguredQuizLaunch launch, {
    bool notifyLocalMutation = true,
  }) async {
    if (launch.session.activityType != launch.configuration.activityType) {
      throw ArgumentError('quiz launch and configuration activity differ');
    }
    final existing = await _configured.findConfiguredQuizStart(launch);
    if (existing != null) {
      _forgetQuizQuestion(existing);
      return existing.asRestored();
    }
    final configuration = launch.configuration;
    final words = await repository.listQuizWords(
      ownerId: launch.session.ownerId,
      categoryId: configuration.categoryId,
      wordIds: configuration.selectionKind == QuizSelectionKind.category
          ? null
          : configuration.wordIds,
      limit: configuration.requestedItemCount,
    );
    if (words.isEmpty) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.emptySelection,
      );
    }
    final optionWords =
        configuration.selectionKind == QuizSelectionKind.category
        ? const <QuizWord>[]
        : await repository.listQuizWords(
            ownerId: launch.session.ownerId,
            limit: 100,
          );
    final plan = AcceptedQuizPlan.create(
      configuration: configuration,
      questions: _questions(words, optionWords: optionWords),
    );
    final saved = await _configured.startConfiguredQuiz(
      session: launch.session,
      plan: plan,
    );
    if (!saved.restored &&
        saved.checkpointRevision == 1 &&
        saved.checkpoint is AwaitingQuizAnswer) {
      _markFreshQuizQuestion(saved);
    }
    if (notifyLocalMutation && !saved.restored) {
      onLocalMutation?.call();
    }
    return saved;
  }

  Future<ConfiguredQuizState> resumeQuiz({
    required String sessionId,
    required String expectedOwnerId,
  }) async {
    final saved = await _configured.resumeQuiz(
      sessionId: _requiredId(sessionId, 'sessionId'),
      expectedOwnerId: _requiredId(expectedOwnerId, 'expectedOwnerId'),
    );
    _forgetQuizQuestion(saved);
    return saved.asRestored();
  }

  Future<ConfiguredQuizState> setQuizHint({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
    required bool visible,
  }) async {
    final saved = await _configured.resumeQuiz(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
    );
    final checkpoint = saved.checkpoint;
    if (checkpoint is! AwaitingQuizAnswer) {
      throw StateError('quiz question is not awaiting input');
    }
    if (checkpoint.assistance.hintVisible == visible &&
        expectedRevision >= 1 &&
        expectedRevision >= saved.checkpointRevision - 1 &&
        expectedRevision <= saved.checkpointRevision) {
      return saved;
    }
    return _configured.saveQuizCheckpoint(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
      expectedRevision: expectedRevision,
      checkpoint: AwaitingQuizAnswer(
        planId: saved.plan.id,
        questionOrdinal: checkpoint.questionOrdinal,
        assistance: visible
            ? checkpoint.assistance.showHint(_now().millisecondsSinceEpoch)
            : checkpoint.assistance.hideHint(),
      ),
    );
  }

  Future<ConfiguredQuizState> prepareQuizAnswer({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
    int? selectedOptionOrdinal,
    bool revealed = false,
    int? responseTimeMs,
  }) async {
    final saved = await _configured.resumeQuiz(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
    );
    final checkpoint = saved.checkpoint;
    final existing = checkpoint.answer;
    if (existing != null) {
      if ((checkpoint is PendingQuizAnswer ||
              checkpoint is AnsweredQuizQuestion) &&
          existing.selectedOptionOrdinal == selectedOptionOrdinal &&
          existing.revealed == revealed &&
          (expectedRevision == saved.checkpointRevision ||
              expectedRevision ==
                  saved.checkpointRevision -
                      (checkpoint is PendingQuizAnswer ? 1 : 2))) {
        return saved;
      }
      throw StateError('pending quiz selection changed');
    }
    if (checkpoint is! AwaitingQuizAnswer ||
        expectedRevision != saved.checkpointRevision) {
      throw StateError('quiz checkpoint changed');
    }
    final occurredAt = _now().millisecondsSinceEpoch;
    final assistance = revealed
        ? checkpoint.assistance.withReveal(occurredAt)
        : checkpoint.assistance;
    final fresh = _freshQuizQuestions.contains((
      ownerId: saved.ownerId,
      sessionId: saved.sessionId,
      ordinal: checkpoint.questionOrdinal,
    ));
    final answer = QuizAnswerReceipt.capture(
      plan: saved.plan,
      ownerId: expectedOwnerId,
      attemptId: 'attempt:${_nextId()}',
      questionOrdinal: checkpoint.questionOrdinal,
      selectedOptionOrdinal: selectedOptionOrdinal,
      revealed: revealed,
      assistance: assistance,
      occurredAtUtcMs: occurredAt,
      responseTimeMs: fresh ? responseTimeMs : null,
    );
    final pending = await _configured.saveQuizCheckpoint(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
      expectedRevision: expectedRevision,
      checkpoint: PendingQuizAnswer(
        planId: saved.plan.id,
        questionOrdinal: checkpoint.questionOrdinal,
        assistance: assistance,
        answer: answer,
      ),
    );
    _forgetQuizQuestion(saved);
    return pending;
  }

  Future<ConfiguredQuizAnswerResult> commitQuizAnswer({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  }) async {
    final result = await _configured.commitQuizAnswer(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
      expectedRevision: expectedRevision,
    );
    final receipt = result.state.checkpoint.answer!;
    await _afterRecordedAnswer(
      receipt.toCommand(sessionId: sessionId),
      result.record,
    );
    return result;
  }

  Future<ConfiguredQuizState> advanceQuiz({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  }) async {
    final saved = await _configured.resumeQuiz(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
    );
    final previous = saved.checkpoint;
    if (previous is AwaitingQuizAnswer &&
        expectedRevision >= 1 &&
        expectedRevision == saved.checkpointRevision - 1) {
      return saved;
    }
    if (previous is! AnsweredQuizQuestion ||
        previous.questionOrdinal + 1 >= saved.plan.questions.length) {
      throw StateError('quiz cannot advance from this checkpoint');
    }
    final next = await _configured.saveQuizCheckpoint(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
      expectedRevision: expectedRevision,
      checkpoint: AwaitingQuizAnswer(
        planId: saved.plan.id,
        questionOrdinal: previous.questionOrdinal + 1,
        assistance: QuizAssistance(),
      ),
    );
    _markFreshQuizQuestion(next);
    return next;
  }

  Future<ConfiguredQuizState> prepareQuizFinish({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  }) async {
    final saved = await _configured.resumeQuiz(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
    );
    final previous = saved.checkpoint;
    if ((previous is ClosingQuizSession || previous is CompletedQuizSession) &&
        (expectedRevision == saved.checkpointRevision ||
            expectedRevision ==
                saved.checkpointRevision -
                    (previous is ClosingQuizSession ? 1 : 2))) {
      return saved;
    }
    if (previous is! AnsweredQuizQuestion ||
        previous.questionOrdinal != saved.plan.questions.length - 1) {
      throw StateError('quiz has unanswered questions');
    }
    return _configured.saveQuizCheckpoint(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
      expectedRevision: expectedRevision,
      checkpoint: ClosingQuizSession(
        planId: saved.plan.id,
        questionOrdinal: previous.questionOrdinal,
        assistance: previous.assistance,
        close: QuizCloseReceipt(
          capturedOwnerId: expectedOwnerId,
          endedAtUtcMs: _now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  Future<ConfiguredQuizFinishResult> finishConfiguredQuiz({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
    bool notifyLocalMutation = true,
  }) async {
    final result = await _configured.finishConfiguredQuiz(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
      expectedRevision: expectedRevision,
    );
    if (notifyLocalMutation) {
      onLocalMutation?.call();
    }
    return result;
  }

  Future<ConfiguredQuizState> abandonQuiz({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  }) async {
    final saved = await _configured.resumeQuiz(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
    );
    if (saved.checkpoint is AbandonedQuizSession) return saved;
    final abandoned = await _configured.saveQuizCheckpoint(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
      expectedRevision: expectedRevision,
      checkpoint: AbandonedQuizSession(
        planId: saved.plan.id,
        questionOrdinal: saved.checkpoint.questionOrdinal,
        assistance: saved.checkpoint.assistance,
        close: QuizCloseReceipt(
          capturedOwnerId: expectedOwnerId,
          endedAtUtcMs: _now().millisecondsSinceEpoch,
        ),
      ),
    );
    _forgetQuizQuestion(saved);
    onLocalMutation?.call();
    return abandoned;
  }

  void _markFreshQuizQuestion(ConfiguredQuizState saved) =>
      _freshQuizQuestions.add((
        ownerId: saved.ownerId,
        sessionId: saved.sessionId,
        ordinal: saved.checkpoint.questionOrdinal,
      ));

  void _forgetQuizQuestion(ConfiguredQuizState saved) =>
      _freshQuizQuestions.removeWhere(
        (key) =>
            key.ownerId == saved.ownerId && key.sessionId == saved.sessionId,
      );

  Future<QuizSession> _startConfigured(QuizConfiguration configuration) async {
    final launch = await prepareConfiguredQuiz(configuration: configuration);
    try {
      return (await startConfiguredQuiz(launch)).asQuizSession;
    } on ConfiguredQuizUnavailable catch (error) {
      if (error.reason != ConfiguredQuizUnavailableReason.emptySelection) {
        rethrow;
      }
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
  }

  List<QuizQuestion> _questions(
    List<QuizWord> words, {
    List<QuizWord> optionWords = const [],
  }) {
    final allMeanings = [
      ...words,
      ...optionWords,
    ].map((word) => word.meaning).toSet().toList(growable: false)..sort();
    return words
        .map((word) {
          final distractors = allMeanings
              .where((meaning) => meaning != word.meaning)
              .take(3)
              .toList(growable: true);
          final options = <String>[word.meaning, ...distractors];
          final offset =
              word.id.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
              options.length;
          final rotated = <String>[
            ...options.skip(offset),
            ...options.take(offset),
          ];
          return QuizQuestion(word: word, options: List.unmodifiable(rotated));
        })
        .toList(growable: false);
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

final class _SrsUseCaseScope {
  _SrsUseCaseScope(this.current);
  final bool Function() current;
  bool invalidated = false;
  bool started = false;
  bool startNotified = false;
  bool finishNotified = false;
  final answers = <int, SrsReviewAnswerIntent>{};
  final confirmed = <int>{};
  final notifiedAnswers = <int>{};
  SrsReviewFinishIntent? closing;
}
