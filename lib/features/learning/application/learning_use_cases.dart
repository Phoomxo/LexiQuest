import '../../identity/domain/local_owner_repository.dart';
import '../../../runtime/app_build_info.dart';
import '../../events/application/event_v1_to_v2_adapter.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../rewards/application/shadow_reward_orchestrator.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';

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
  });

  final LocalOwnerRepository owners;
  final LearningRepository repository;
  final LearningIdGenerator generateId;
  final LearningUtcNow nowUtc;
  final AppBuildInfo buildInfo;
  final LearningMutationNotifier? onLocalMutation;

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
      _startVocabularySession(categoryId, limit, 'quiz');

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

  Future<QuizSession> startDueReview({int limit = 20}) async {
    final owner = await owners.getOrCreateActiveOwner();
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
      questions: _questions(words),
      startedAtUtc: now,
    );
  }

  Future<QuizSession> startWeaknessPractice({
    required Iterable<String> wordIds,
    int limit = 20,
  }) => _startWordPractice(wordIds, limit, 'weaknessPractice');

  Future<QuizSession> startGhostDuel({
    required Iterable<String> wordIds,
    int limit = 20,
  }) => _startWordPractice(wordIds, limit, 'ghostDuel');

  Future<QuizSession> startSourcePracticeForWords({
    required Iterable<String> wordIds,
    int limit = 20,
  }) => _startWordPractice(wordIds, limit, 'sourcePractice');

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
  }) async {
    if ((attemptId == null) != (occurredAtUtc == null)) {
      throw ArgumentError(
        'retry identity and timestamp must be supplied together',
      );
    }
    final recordedAt = occurredAtUtc ?? _now();
    if (!recordedAt.isUtc) throw ArgumentError('occurredAtUtc must be UTC');
    final owner = await owners.getOrCreateActiveOwner();
    final result = await repository.recordAnswer(
      RecordAnswerCommand(
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
      ),
    );
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

    // Quest pipeline hook — forward answer event to quest use cases.
    // Uses the same V2 event produced for shadow mode when available;
    // builds a fresh event otherwise.  Errors are swallowed.
    final questSink = questEventSink;
    if (questSink != null) {
      try {
        final questEvent = adapter?.adaptFromCommand(
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
      await streakEventSink?.call();
    } catch (_) {}

    return result;
  }

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
