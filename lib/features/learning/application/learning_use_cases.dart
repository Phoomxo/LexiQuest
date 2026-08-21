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

/// Immutable response semantics captured by the UI before any provider wait.
final class FrozenLearningEvidenceCommand {
  const FrozenLearningEvidenceCommand({
    required this.sourceEvidenceId,
    required this.occurredAtUtc,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.attemptNumber,
    required this.providerProvenance,
  });

  final String sourceEvidenceId;
  final DateTime occurredAtUtc;
  final String sessionId;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final int? responseTimeMs;
  final int attemptNumber;
  final String? providerProvenance;
}

/// Canonical response semantics bound to the active owner before any
/// asynchronous policy or research-state resolution begins.
final class OwnerBoundLearningEvidenceBasis {
  const OwnerBoundLearningEvidenceBasis._({
    required this.ownerId,
    required this.command,
  });

  final String ownerId;
  final FrozenLearningEvidenceCommand command;
}

final class ResolvedLearningEvidenceContexts {
  const ResolvedLearningEvidenceContexts({
    required this.evidenceContext,
    required this.eventContext,
  });

  final EvidenceContext evidenceContext;
  final LearningEventContext eventContext;
}

typedef LearningEvidenceContextsResolver =
    Future<ResolvedLearningEvidenceContexts> Function({
      required String ownerId,
      required FrozenLearningEvidenceCommand command,
    });

/// Owner-bound evidence ready for replay/write without another owner lookup.
final class ResolvedLearningEvidenceRecord {
  const ResolvedLearningEvidenceRecord._({
    required this.ownerId,
    required this.command,
    required this.contexts,
  });

  final String ownerId;
  final FrozenLearningEvidenceCommand command;
  final ResolvedLearningEvidenceContexts contexts;
}

enum PendingLearningSessionCloseStatus {
  captured,
  bindingOwner,
  writing,
  retryRequired,
  committed,
}

/// One frozen, owner-bound-once session close that can be retried without
/// changing its session identity or completion time.
final class PendingLearningSessionClose {
  PendingLearningSessionClose._({
    required this._learning,
    required this.sessionId,
    required this.completedAtUtc,
  });

  final LearningUseCases _learning;
  final String sessionId;
  final DateTime completedAtUtc;

  PendingLearningSessionCloseStatus _status =
      PendingLearningSessionCloseStatus.captured;
  String? _ownerId;
  Future<String>? _ownerBindingInFlight;
  Future<LearningSessionSummary>? _finishInFlight;
  LearningSessionSummary? _result;

  PendingLearningSessionCloseStatus get status => _status;
  bool get requiresRetry =>
      _status == PendingLearningSessionCloseStatus.retryRequired;
  bool get isCommitted =>
      _status == PendingLearningSessionCloseStatus.committed;
  bool get isInFlight => _finishInFlight != null;

  Future<LearningSessionSummary> finish() {
    final inFlight = _finishInFlight;
    if (inFlight != null) return inFlight;
    if (requiresRetry) {
      return Future<LearningSessionSummary>.error(
        StateError('explicit retry is required for pending session close'),
      );
    }
    final result = _result;
    if (result != null) return Future<LearningSessionSummary>.value(result);
    return _startFinish();
  }

  Future<LearningSessionSummary> retry() {
    final inFlight = _finishInFlight;
    if (inFlight != null) return inFlight;
    if (!requiresRetry) {
      return Future<LearningSessionSummary>.error(
        StateError('pending session close is not awaiting retry'),
      );
    }
    return _startFinish();
  }

  Future<LearningSessionSummary> _startFinish() {
    final future = _executeFinish();
    _finishInFlight = future;
    return future;
  }

  Future<LearningSessionSummary> _executeFinish() async {
    try {
      _status = PendingLearningSessionCloseStatus.bindingOwner;
      final ownerId = await _bindOwnerOnce();
      _status = PendingLearningSessionCloseStatus.writing;
      final result = await _learning._finishCapturedSessionClose(
        ownerId: ownerId,
        sessionId: sessionId,
        completedAtUtc: completedAtUtc,
      );
      _result = result;
      _status = PendingLearningSessionCloseStatus.committed;
      return result;
    } catch (_) {
      _status = PendingLearningSessionCloseStatus.retryRequired;
      rethrow;
    } finally {
      _finishInFlight = null;
    }
  }

  Future<String> _bindOwnerOnce() {
    final ownerId = _ownerId;
    if (ownerId != null) return Future<String>.value(ownerId);
    return _ownerBindingInFlight ??= _bindOwnerAndMemoize();
  }

  Future<String> _bindOwnerAndMemoize() async {
    try {
      final owner = await _learning.owners.getOrCreateActiveOwner();
      final ownerId = _learning._requiredId(owner.id, 'ownerId');
      _ownerId = ownerId;
      return ownerId;
    } finally {
      _ownerBindingInFlight = null;
    }
  }
}

enum PendingReadingProgressStatus {
  captured,
  bindingOwner,
  writing,
  retryRequired,
  committed,
}

/// One frozen reading-progress mutation whose owner and command identity are
/// bound once and reused by every explicit retry.
final class PendingReadingProgress {
  PendingReadingProgress._({
    required this._learning,
    required this.eventId,
    required this.documentId,
    required this.documentRevision,
    required this.position,
    required this.isCompleted,
    required this.occurredAtUtc,
  });

  final LearningUseCases _learning;
  final String eventId;
  final String documentId;
  final int documentRevision;
  final int position;
  final bool isCompleted;
  final DateTime occurredAtUtc;

  PendingReadingProgressStatus _status = PendingReadingProgressStatus.captured;
  String? _ownerId;
  Future<String>? _ownerBindingInFlight;
  ReadingProgressCommand? _command;
  Future<ReadingProgressSnapshot>? _saveInFlight;
  ReadingProgressSnapshot? _result;

  PendingReadingProgressStatus get status => _status;
  bool get requiresRetry =>
      _status == PendingReadingProgressStatus.retryRequired;
  bool get isCommitted => _status == PendingReadingProgressStatus.committed;
  bool get isInFlight => _saveInFlight != null;

  Future<ReadingProgressSnapshot> save() {
    final inFlight = _saveInFlight;
    if (inFlight != null) return inFlight;
    if (requiresRetry) {
      return Future<ReadingProgressSnapshot>.error(
        StateError('explicit retry is required for pending reading progress'),
      );
    }
    final result = _result;
    if (result != null) return Future<ReadingProgressSnapshot>.value(result);
    return _startSave();
  }

  Future<ReadingProgressSnapshot> retry() {
    final inFlight = _saveInFlight;
    if (inFlight != null) return inFlight;
    if (!requiresRetry) {
      return Future<ReadingProgressSnapshot>.error(
        StateError('pending reading progress is not awaiting retry'),
      );
    }
    return _startSave();
  }

  Future<ReadingProgressSnapshot> _startSave() {
    final future = _executeSave();
    _saveInFlight = future;
    return future;
  }

  Future<ReadingProgressSnapshot> _executeSave() async {
    try {
      _status = PendingReadingProgressStatus.bindingOwner;
      final ownerId = await _bindOwnerOnce();
      final command = _command ??= ReadingProgressCommand(
        eventId: eventId,
        ownerId: ownerId,
        documentId: documentId,
        documentRevision: documentRevision,
        position: position,
        isCompleted: isCompleted,
        occurredAtUtc: occurredAtUtc,
      );
      _status = PendingReadingProgressStatus.writing;
      final result = await _learning._saveCapturedReadingProgress(command);
      _result = result;
      _status = PendingReadingProgressStatus.committed;
      return result;
    } catch (_) {
      _status = PendingReadingProgressStatus.retryRequired;
      rethrow;
    } finally {
      _saveInFlight = null;
    }
  }

  Future<String> _bindOwnerOnce() {
    final ownerId = _ownerId;
    if (ownerId != null) return Future<String>.value(ownerId);
    return _ownerBindingInFlight ??= _bindOwnerAndMemoize();
  }

  Future<String> _bindOwnerAndMemoize() async {
    try {
      final owner = await _learning.owners.getOrCreateActiveOwner();
      final ownerId = _learning._requiredId(owner.id, 'ownerId');
      _ownerId = ownerId;
      return ownerId;
    } finally {
      _ownerBindingInFlight = null;
    }
  }
}

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

  Future<String> startAssociativeReadingSession() async {
    final owner = await owners.getOrCreateActiveOwner();
    final startedAtUtc = _now();
    final sessionId = 'session:${_nextId()}';
    await repository.startSession(
      LearningSessionDraft(
        id: sessionId,
        ownerId: owner.id,
        activityType: 'associativeReading',
        startedAtUtc: startedAtUtc,
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
    );
    return sessionId;
  }

  /// Resolves the active owner once, then gives that exact owner and the
  /// already-frozen response command to the context resolver.
  Future<ResolvedLearningEvidenceRecord> resolveEvidenceForRecording({
    required FrozenLearningEvidenceCommand command,
    required LearningEvidenceContextsResolver resolveContexts,
  }) async {
    final basis = await bindEvidenceForRecording(command: command);
    return resolveOwnerBoundEvidenceForRecording(
      basis: basis,
      resolveContexts: resolveContexts,
    );
  }

  /// Canonicalizes the captured response and binds it to one active owner.
  Future<OwnerBoundLearningEvidenceBasis> bindEvidenceForRecording({
    required FrozenLearningEvidenceCommand command,
  }) async {
    final canonical = _canonicalEvidenceCommand(command);
    final owner = await owners.getOrCreateActiveOwner();
    return OwnerBoundLearningEvidenceBasis._(
      ownerId: _requiredId(owner.id, 'ownerId'),
      command: canonical,
    );
  }

  /// Resolves contexts for an already owner-bound basis without consulting
  /// mutable active-owner state again.
  Future<ResolvedLearningEvidenceRecord> resolveOwnerBoundEvidenceForRecording({
    required OwnerBoundLearningEvidenceBasis basis,
    required LearningEvidenceContextsResolver resolveContexts,
  }) async {
    final ownerId = _requiredId(basis.ownerId, 'ownerId');
    final canonical = _canonicalEvidenceCommand(basis.command);
    final contexts = await resolveContexts(
      ownerId: ownerId,
      command: canonical,
    );
    contexts.evidenceContext.validate();
    contexts.eventContext.validateAgainst(
      evidenceContext: contexts.evidenceContext,
      occurredAtUtc: canonical.occurredAtUtc,
    );
    return ResolvedLearningEvidenceRecord._(
      ownerId: ownerId,
      command: canonical,
      contexts: contexts,
    );
  }

  /// Replays/writes an owner-bound record without re-reading active-owner
  /// state. This keeps provider snapshot and canonical write on one owner.
  Future<AnswerRecordResult> recordResolvedEvidence(
    ResolvedLearningEvidenceRecord resolved,
  ) {
    final ownerId = _requiredId(resolved.ownerId, 'ownerId');
    final command = _canonicalEvidenceCommand(resolved.command);
    resolved.contexts.evidenceContext.validate();
    resolved.contexts.eventContext.validateAgainst(
      evidenceContext: resolved.contexts.evidenceContext,
      occurredAtUtc: command.occurredAtUtc,
    );
    return _recordCanonicalEvidence(
      ownerId: ownerId,
      command: command,
      evidenceContext: resolved.contexts.evidenceContext,
      resolvedEventContext: resolved.contexts.eventContext,
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
    final command = _canonicalEvidenceCommand(
      FrozenLearningEvidenceCommand(
        sourceEvidenceId: sourceEvidenceId,
        occurredAtUtc: occurredAtUtc,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: promptMode,
        isCorrect: isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: providerProvenance,
      ),
    );
    evidenceContext.validate();
    final owner = await owners.getOrCreateActiveOwner();
    return _recordCanonicalEvidence(
      ownerId: _requiredId(owner.id, 'ownerId'),
      command: command,
      evidenceContext: evidenceContext,
    );
  }

  Future<AnswerRecordResult> _recordCanonicalEvidence({
    required String ownerId,
    required FrozenLearningEvidenceCommand command,
    required EvidenceContext evidenceContext,
    LearningEventContext? resolvedEventContext,
  }) async {
    final candidate = RecordAnswerCandidate(
      id: command.sourceEvidenceId,
      ownerId: ownerId,
      sessionId: command.sessionId,
      wordId: command.wordId,
      promptMode: command.promptMode,
      isCorrect: command.isCorrect,
      responseTimeMs: command.responseTimeMs,
      attemptNumber: command.attemptNumber,
      occurredAtUtc: command.occurredAtUtc,
      evidenceContext: evidenceContext,
      providerProvenance: command.providerProvenance,
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
      final learningEventContext =
          resolvedEventContext ??
          await eventContextProvider.resolve(
            ownerId: ownerId,
            occurredAtUtc: command.occurredAtUtc,
            evidenceContext: evidenceContext,
          );
      learningEventContext.validateAgainst(
        evidenceContext: evidenceContext,
        occurredAtUtc: command.occurredAtUtc,
      );
      durableEvent = eventAdapter.adaptFromCommand(
        sourceEvidenceId: command.sourceEvidenceId,
        ownerId: ownerId,
        sessionId: command.sessionId,
        wordId: command.wordId,
        promptMode: command.promptMode,
        isCorrect: command.isCorrect,
        attemptNumber: command.attemptNumber,
        occurredAtUtc: command.occurredAtUtc,
        evidenceContext: evidenceContext,
        learningEventContext: learningEventContext,
      );
      result = await repository.recordAnswer(
        RecordAnswerCommand(
          id: command.sourceEvidenceId,
          ownerId: ownerId,
          sessionId: command.sessionId,
          wordId: command.wordId,
          promptMode: command.promptMode,
          isCorrect: command.isCorrect,
          responseTimeMs: command.responseTimeMs,
          attemptNumber: command.attemptNumber,
          occurredAtUtc: command.occurredAtUtc,
          evidenceContext: evidenceContext,
          providerProvenance: command.providerProvenance,
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
    onSideEffectsPending?.call(ownerId);

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

  PendingLearningSessionClose captureSessionClose({required String sessionId}) {
    return PendingLearningSessionClose._(
      learning: this,
      sessionId: _requiredId(sessionId, 'sessionId'),
      completedAtUtc: _now(),
    );
  }

  Future<LearningSessionSummary> finishSession(String sessionId) {
    return captureSessionClose(sessionId: sessionId).finish();
  }

  Future<LearningSessionSummary> _finishCapturedSessionClose({
    required String ownerId,
    required String sessionId,
    required DateTime completedAtUtc,
  }) async {
    final result = await repository.finishSession(
      ownerId: _requiredId(ownerId, 'ownerId'),
      sessionId: _requiredId(sessionId, 'sessionId'),
      endedAtUtc: _requiredUtc(completedAtUtc, 'completedAtUtc'),
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
  }) {
    return captureReadingProgress(
      documentId: documentId,
      documentRevision: documentRevision,
      position: position,
      isCompleted: isCompleted,
    ).save();
  }

  PendingReadingProgress captureReadingProgress({
    required String documentId,
    required int documentRevision,
    required int position,
    required bool isCompleted,
  }) {
    return PendingReadingProgress._(
      learning: this,
      eventId: 'reading-event:${_nextId()}',
      documentId: _requiredId(documentId, 'documentId'),
      documentRevision: documentRevision,
      position: position,
      isCompleted: isCompleted,
      occurredAtUtc: _now(),
    );
  }

  Future<ReadingProgressSnapshot> _saveCapturedReadingProgress(
    ReadingProgressCommand command,
  ) async {
    final result = await repository.saveReadingProgress(command);
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

  FrozenLearningEvidenceCommand _canonicalEvidenceCommand(
    FrozenLearningEvidenceCommand command,
  ) {
    return FrozenLearningEvidenceCommand(
      sourceEvidenceId: _stableEvidenceId(command.sourceEvidenceId),
      occurredAtUtc: _requiredUtc(command.occurredAtUtc, 'occurredAtUtc'),
      sessionId: _requiredId(command.sessionId, 'sessionId'),
      wordId: _requiredId(command.wordId, 'wordId'),
      promptMode: _requiredId(command.promptMode, 'promptMode'),
      isCorrect: command.isCorrect,
      responseTimeMs: command.responseTimeMs,
      attemptNumber: command.attemptNumber,
      providerProvenance: command.providerProvenance,
    );
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
