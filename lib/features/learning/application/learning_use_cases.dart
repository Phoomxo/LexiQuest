import '../../identity/domain/local_owner_repository.dart';
import '../../../runtime/app_build_info.dart';
import '../../events/application/event_v1_to_v2_adapter.dart';
import '../../rewards/application/shadow_reward_orchestrator.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import '../domain/quiz_prompt_policy.dart';

typedef LearningIdGenerator = String Function();
typedef LearningUtcNow = DateTime Function();
typedef LearningMutationNotifier = void Function();
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

  Future<QuizSession> startQuiz({
    String? categoryId,
    int limit = 10,
    String? expectedOwnerId,
    QuizPromptKind kind = QuizPromptKind.meaningChoice,
  }) => _startVocabularySession(
    categoryId,
    limit,
    'quiz',
    expectedOwnerId: expectedOwnerId,
    kind: kind,
  );

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
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
    final words = await repository.listQuizWords(
      ownerId: owner.id,
      categoryId: _optionalId(categoryId, 'categoryId'),
      limit: kind == QuizPromptKind.meaningChoice ? limit : null,
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
    if (questions.isEmpty) {
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
    return QuizSession(id: sessionId, startedAtUtc: now, questions: questions);
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
  }) => _startWordPractice(
    wordIds,
    limit,
    'weaknessPractice',
    expectedOwnerId: expectedOwnerId,
    kind: kind,
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
  }) => _startWordPractice(
    wordIds,
    limit,
    'sourcePractice',
    expectedOwnerId: expectedOwnerId,
    kind: kind,
  );

  Future<QuizSession> _startWordPractice(
    Iterable<String> wordIds,
    int limit,
    String activityType, {
    String? expectedOwnerId,
    QuizPromptKind kind = QuizPromptKind.meaningChoice,
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final requested = wordIds.map((id) => _requiredId(id, 'wordId')).toSet();
    if (requested.isEmpty) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final owner = await owners.getOrCreateActiveOwner();
    _requireExpectedOwner(owner.id, expectedOwnerId);
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
    if (questions.isEmpty) {
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
    return QuizSession(id: sessionId, questions: questions, startedAtUtc: now);
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
