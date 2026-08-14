import '../../identity/domain/local_owner_repository.dart';
import '../../../runtime/app_build_info.dart';
import '../../events/application/event_v1_to_v2_adapter.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../rewards/application/shadow_reward_orchestrator.dart';
import '../domain/evidence_context.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_event_context.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';

typedef LearningIdGenerator = String Function();
typedef LearningUtcNow = DateTime Function();
typedef LearningMutationNotifier = void Function();

final class LearningUseCases {
  LearningUseCases({
    required this.owners,
    required this.repository,
    required this.generateId,
    required this.nowUtc,
    required this.buildInfo,
    this.onLocalMutation,
    this.shadowOrchestrator,
    EventV1ToV2Adapter? eventAdapter,
    LearningEventContextProvider? eventContextProvider,
    this.onSideEffectsPending,
  }) : eventAdapter =
           eventAdapter ??
           EventV1ToV2Adapter(
             appVersion: buildInfo.version,
             buildId: buildInfo.buildId,
           ),
       eventContextProvider =
           eventContextProvider ?? const BaselineLearningEventContextProvider();

  final LocalOwnerRepository owners;
  final LearningRepository repository;
  final LearningIdGenerator generateId;
  final LearningUtcNow nowUtc;
  final AppBuildInfo buildInfo;
  final LearningMutationNotifier? onLocalMutation;

  /// Shadow mode — when non-null, every recorded answer is also run through
  /// the V2 reward eligibility pipeline in dry-run mode.  Null = disabled.
  final ShadowRewardOrchestrator? shadowOrchestrator;

  /// Adapts canonical evidence commands to immutable V2 events.
  final EventV1ToV2Adapter eventAdapter;

  /// Resolves consent and assignment metadata outside the widget layer.
  final LearningEventContextProvider eventContextProvider;

  /// Schedules a bounded durable replay batch without delaying this answer.
  final void Function(String ownerId)? onSideEffectsPending;

  Future<QuizSession> startQuiz({String? categoryId, int limit = 10}) async {
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
        activityType: 'quiz',
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
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final requested = wordIds.map((id) => _requiredId(id, 'wordId')).toSet();
    if (requested.isEmpty) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final owner = await owners.getOrCreateActiveOwner();
    final words = await repository.listQuizWords(ownerId: owner.id, limit: 100);
    final selected = words
        .where((word) => requested.contains(word.id))
        .take(limit)
        .toList(growable: false);
    if (selected.isEmpty) {
      return const QuizSession(id: '', questions: [], startedAtUtc: null);
    }
    final now = _now();
    final sessionId = 'session:${_nextId()}';
    await repository.startSession(
      LearningSessionDraft(
        id: sessionId,
        ownerId: owner.id,
        activityType: 'ghostDuel',
        startedAtUtc: now,
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
    );
    return QuizSession(
      id: sessionId,
      questions: _questions(selected),
      startedAtUtc: now,
    );
  }

  Future<AnswerRecordResult> recordEvidence({
    required String sourceEvidenceId,
    required DateTime occurredAtUtc,
    required String sessionId,
    required String wordId,
    required String promptMode,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    required EvidenceContext evidenceContext,
    String? providerProvenance,
  }) async {
    final canonicalEvidenceId = _stableEvidenceId(sourceEvidenceId);
    final canonicalOccurredAtUtc = _requiredUtc(occurredAtUtc, 'occurredAtUtc');
    evidenceContext.validate();
    final canonicalSessionId = _requiredId(sessionId, 'sessionId');
    final canonicalWordId = _requiredId(wordId, 'wordId');
    final canonicalPromptMode = _requiredId(promptMode, 'promptMode');
    final owner = await owners.getOrCreateActiveOwner();
    final candidate = RecordAnswerCandidate(
      id: canonicalEvidenceId,
      ownerId: owner.id,
      sessionId: canonicalSessionId,
      wordId: canonicalWordId,
      promptMode: canonicalPromptMode,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      occurredAtUtc: canonicalOccurredAtUtc,
      evidenceContext: evidenceContext,
      providerProvenance: providerProvenance,
    );
    final replayRepository = repository;
    final replay = replayRepository is LearningEvidenceReplayRepository
        ? await (replayRepository as LearningEvidenceReplayRepository)
              .replayCommittedAnswer(candidate)
        : null;
    late final EventEnvelopeV2 durableEvent;
    late final AnswerRecordResult result;
    if (replay != null) {
      durableEvent = replay.event;
      result = replay.result;
    } else {
      final learningEventContext = await eventContextProvider.resolve(
        ownerId: owner.id,
        occurredAtUtc: canonicalOccurredAtUtc,
        evidenceContext: evidenceContext,
      );
      learningEventContext.validateAgainst(
        evidenceContext: evidenceContext,
        occurredAtUtc: canonicalOccurredAtUtc,
      );
      durableEvent = eventAdapter.adaptFromCommand(
        sourceEvidenceId: canonicalEvidenceId,
        ownerId: owner.id,
        sessionId: canonicalSessionId,
        wordId: canonicalWordId,
        promptMode: canonicalPromptMode,
        isCorrect: isCorrect,
        attemptNumber: attemptNumber,
        occurredAtUtc: canonicalOccurredAtUtc,
        evidenceContext: evidenceContext,
        learningEventContext: learningEventContext,
      );
      result = await repository.recordAnswer(
        RecordAnswerCommand(
          id: canonicalEvidenceId,
          ownerId: owner.id,
          sessionId: canonicalSessionId,
          wordId: canonicalWordId,
          promptMode: canonicalPromptMode,
          isCorrect: isCorrect,
          responseTimeMs: responseTimeMs,
          attemptNumber: attemptNumber,
          occurredAtUtc: canonicalOccurredAtUtc,
          evidenceContext: evidenceContext,
          providerProvenance: providerProvenance,
          event: durableEvent,
        ),
      );
    }
    onLocalMutation?.call();

    // Shadow V2 reward pipeline — runs after production succeeds.
    // Errors are swallowed: shadow mode must never break production.
    final shadow = shadowOrchestrator;
    if (shadow != null) {
      try {
        await shadow.processShadow(durableEvent);
      } catch (_) {
        // Intentionally swallowed — shadow mode must never break production.
      }
    }

    // Persistence is the durable handoff. Without an injected scheduler,
    // startup reconciliation owns replay and no side effect runs inline.
    onSideEffectsPending?.call(owner.id);

    return result;
  }

  /// Temporary compatibility entry point while production screens migrate to
  /// caller-owned evidence identity in Foundation Task 8.
  @Deprecated('Use recordEvidence with a retained caller-owned identity.')
  Future<AnswerRecordResult> recordAnswer({
    required String sessionId,
    required String wordId,
    required String promptMode,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    String? providerProvenance,
  }) {
    final sourceEvidenceId = 'attempt:${_nextId()}';
    final occurredAtUtc = _now();
    return recordEvidence(
      sourceEvidenceId: sourceEvidenceId,
      occurredAtUtc: occurredAtUtc,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: promptMode,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      evidenceContext: EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'legacy-current-activity',
        hintLevel: 0,
        contentRevision: 'legacy-unknown',
        engagementAllowed: true,
      ),
      providerProvenance: providerProvenance,
    );
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

  /// Returns the most recent active session for the current owner, or null.
  Future<LearningSessionSummary?> getActiveSession() async {
    final owner = await owners.getOrCreateActiveOwner();
    return repository.getActiveSession(ownerId: owner.id);
  }

  /// Abandons all active sessions for the current owner. Call on app start
  /// when the user chooses not to resume.
  Future<void> abandonActiveSessions() async {
    final owner = await owners.getOrCreateActiveOwner();
    await repository.abandonActiveSessions(ownerId: owner.id);
  }

  /// Returns the [limit] most recent completed sessions for the current owner.
  Future<List<LearningSessionSummary>> listSessionHistory({
    int limit = 20,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    return repository.listSessionHistory(ownerId: owner.id, limit: limit);
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
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    final result = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-event:${_nextId()}',
        ownerId: owner.id,
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

  List<QuizQuestion> _questions(List<QuizWord> words) {
    final allMeanings =
        words.map((word) => word.meaning).toSet().toList(growable: false)
          ..sort();
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

  DateTime _requiredUtc(DateTime value, String field) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, field, 'must be UTC');
    }
    return value;
  }

  String _stableEvidenceId(String value) {
    if (!LearningEvidenceContract.validSourceEvidenceId(value)) {
      throw ArgumentError.value(
        value,
        'sourceEvidenceId',
        'invalid stable identifier',
      );
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
