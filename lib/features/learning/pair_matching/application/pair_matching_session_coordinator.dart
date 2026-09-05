import 'dart:convert';
import '../../application/current_activity_evidence.dart';
import '../../application/learning_use_cases.dart';
import '../../domain/evidence_context.dart';
import '../../domain/learning_models.dart';
import '../../domain/lexical_prompt_artifact_identity.dart';
import '../data/pair_matching_checkpoint_codec.dart';
import '../domain/pair_matching_engine.dart';
import '../domain/pair_active_clock.dart';
import '../domain/pair_matching_checkpoint_budget.dart';
import 'pair_matching_atomic_start.dart';
import '../../../review/application/pair_review_deferral.dart';
import '../../../review/domain/review_queue_item.dart';

typedef PairSessionOperation =
    Future<void> Function(Future<void> Function() action);

/// M12 application owner for the v6 session. Hosts dispatch typed intents and
/// await acknowledgement; they never write answers/checkpoints themselves.
final class PairMatchingSessionCoordinator {
  PairMatchingSessionCoordinator._(
    this._checkpoint, {
    required this.operation,
    required this.learning,
    required this.evidence,
    required this.activeOwnerId,
    required this.acceptsOperation,
    required this.runAdmittedOperation,
    required this.runRecoveryOperation,
    required PairMatchingCheckpointSnapshot snapshot,
    required int Function() monotonicMicros,
    this.completeSession,
    this.ownClose,
  }) : _snapshot = snapshot,
       _state = snapshot.engine,
       _clock = PairActiveClock(
         snapshot.timer ?? PairTimerState.initial(operation.plan.timerPreset),
         monotonicMicros,
       );
  final PairMatchingStartOperation operation;
  final LearningUseCases learning;
  final CurrentActivityEvidenceAdapter evidence;
  final String? Function() activeOwnerId;
  final bool Function()? acceptsOperation;
  final PairSessionOperation? runAdmittedOperation, runRecoveryOperation;
  final Future<LearningSessionSummary> Function(PendingLearningSessionClose)?
  completeSession;
  final void Function(PendingLearningSessionClose, Future<void> Function())?
  ownClose;
  bool _closeOwned = false;
  Future<void>? _closeCheckpointInFlight;
  LearningActivityCheckpoint _checkpoint;
  PairMatchingCheckpointSnapshot _snapshot;
  PairMatchingState _state;
  PairMatchingState get state => _state;
  final PairActiveClock _clock;
  PairTimerState get timer => _clock.value;
  bool get timerPaused => _clock.isPaused;
  PairPauseLease? _operationPause;
  PairPauseLease? _capacityPause;
  PairPauseLease? _completedPause;
  PendingLearningSessionClose? _close;
  LearningSessionSummary? _summary;
  LearningSessionSummary? get completedSummary => _summary;
  bool get summaryPresented => _snapshot.terminal?.presented == true;
  int get checkpointRevision => _checkpoint.revision;
  bool _disposed = false, _busy = false;
  PendingCurrentActivityEvidence? _pending;
  FrozenPendingCurrentActivityEvidence? _frozen;
  LearningActivityCheckpoint? _pendingAppend;
  PairMatchingCheckpointSnapshot? _pendingSnapshot;
  PairMatchingState? _capturedState;

  static Future<PairMatchingSessionCoordinator> restore({
    required PairMatchingStartOperation operation,
    required LearningUseCases learning,
    required CurrentActivityEvidenceAdapter evidence,
    required String? Function() activeOwnerId,
    bool Function()? acceptsOperation,
    PairSessionOperation? runAdmittedOperation,
    PairSessionOperation? runRecoveryOperation,
    int Function()? monotonicMicros,
    Future<LearningSessionSummary> Function(PendingLearningSessionClose)?
    completeSession,
    void Function(PendingLearningSessionClose, Future<void> Function())?
    ownClose,
  }) async {
    if (!identical(evidence.learning, learning) ||
        activeOwnerId() != operation.plan.ownerId) {
      throw StateError('Pair learning authority/owner changed');
    }
    final recovery = await learning.loadExactActivityRecovery(
      ownerId: operation.plan.ownerId,
      sessionId: operation.plan.learningSessionId,
      activityType: 'matching',
    );
    if (activeOwnerId() != operation.plan.ownerId ||
        recovery == null ||
        recovery.checkpoint == null ||
        recovery.session.ownerId != operation.plan.ownerId ||
        recovery.session.startedAtUtc != operation.plan.createdAtUtc ||
        recovery.session.appVersion != operation.appVersion ||
        recovery.session.buildId != operation.buildId) {
      throw StateError('Pair exact recovery unavailable');
    }
    final snapshot = PairMatchingCheckpointCodec.decode(
      recovery.checkpoint!.state,
    );
    if (snapshot.startOperation != operation.stableSerialization ||
        snapshot.engine.plan.planFingerprint !=
            operation.plan.planFingerprint) {
      throw StateError('Pair recovery plan changed');
    }
    final c = PairMatchingSessionCoordinator._(
      recovery.checkpoint!,
      operation: operation,
      learning: learning,
      evidence: evidence,
      activeOwnerId: activeOwnerId,
      acceptsOperation: acceptsOperation,
      runAdmittedOperation: runAdmittedOperation,
      runRecoveryOperation: runRecoveryOperation,
      snapshot: snapshot,
      monotonicMicros:
          monotonicMicros ?? (Stopwatch()..start()).elapsedMicrosecondsReader,
      completeSession: completeSession,
      ownClose: ownClose,
    );
    c._validateRecovery(recovery);
    final frozen = snapshot.frozenEvidence;
    if (frozen != null) {
      c._frozen = FrozenPendingCurrentActivityEvidence.fromJson(frozen);
      c._validateFrozen(c._frozen!);
      c._pending = evidence.restore(c._frozen!);
    }
    final terminal = snapshot.terminal;
    if (terminal?.atUtc != recovery.checkpoint!.terminalAtUtc ||
        (terminal?.acknowledged ?? false) !=
            recovery.checkpoint!.terminalAcknowledged ||
        (recovery.session.state != 'active' &&
            recovery.session.state != 'completed') ||
        (recovery.session.state == 'completed' &&
            (terminal == null ||
                recovery.session.endedAtUtc != terminal.atUtc))) {
      throw StateError('Pair terminal recovery identity changed');
    }
    if (terminal != null) {
      c._close = learning.restoreSessionClose(
        sessionId: operation.plan.learningSessionId,
        ownerId: operation.plan.ownerId,
        completedAtUtc: terminal.atUtc,
      );
      if (recovery.session.state == 'completed') c._summary = recovery.session;
    }
    return c;
  }

  void _validateRecovery(LearningActivityRecovery recovery) {
    final expected = [
      ...state.attempts,
      if (state.pending != null) state.pending!,
    ];
    if (recovery.attempts.length < state.attempts.length ||
        recovery.attempts.length > expected.length) {
      throw StateError('Pair attempt ledger mismatch');
    }
    for (var i = 0; i < recovery.attempts.length; i++) {
      final actual = recovery.attempts[i], role = expected[i];
      final id = i < _snapshot.evidenceIds.length
          ? _snapshot.evidenceIds[i]
          : _snapshot.frozenEvidence!['sourceEvidenceId'];
      final guided = state.classificationFor(role).hintLevel > 0;
      if (actual.id != id ||
          actual.ownerId != operation.plan.ownerId ||
          actual.sessionId != operation.plan.learningSessionId ||
          actual.wordId != role.promptWordId ||
          actual.isCorrect != role.isCorrect ||
          actual.attemptNumber != i + 1 ||
          actual.responseTimeMs != role.responseTimeMs ||
          actual.promptMode != 'matchingPair' ||
          actual.providerProvenance != 'pinned-lexical-matching' ||
          actual.evidenceContext.contentRevision !=
              _contentRevision(role.promptWordId) ||
          actual.evidenceContext.skillId != 'matching-recognition' ||
          actual.evidenceContext.evidenceClass !=
              (guided
                  ? EvidenceClass.guidedPractice
                  : EvidenceClass.recognition) ||
          actual.evidenceContext.hintLevel != (guided ? 1 : 0)) {
        throw StateError('Pair authenticated attempt differs from ledger');
      }
      if (i == state.attempts.length) {
        final frozen = FrozenPendingCurrentActivityEvidence.fromJson(
          _snapshot.frozenEvidence!,
        );
        if (actual.occurredAtUtc != frozen.occurredAtUtc ||
            actual.actorIdentity != frozen.actorIdentity ||
            jsonEncode(actual.evidenceContext.toJson()) !=
                jsonEncode(frozen.evidenceContext.toJson()) ||
            jsonEncode(actual.eventContext?.toJson()) !=
                jsonEncode(frozen.eventContext.toJson())) {
          throw StateError('Pair pending committed identity changed');
        }
      }
    }
  }

  String _contentRevision(String wordId) {
    final item = operation.plan.orderedLexicalItems.singleWhere(
      (i) => i.wordId == wordId,
    );
    return LexicalPromptArtifactResolver.resolveForAdapter(
      promptMode: 'matchingPair',
      wordId: wordId,
      coreRevision: item.contentRevision,
      coreChecksumSha256: item.checksum,
    )!.evidenceContentRevision;
  }

  void _validateFrozen(
    FrozenPendingCurrentActivityEvidence frozen, {
    PairMatchingState? capturedState,
  }) {
    final role = (capturedState ?? state).pending!;
    if (frozen.contentRevision != _contentRevision(role.promptWordId) ||
        frozen.declaredEvidenceClass !=
            (capturedState ?? state).classificationFor(role).evidenceClass ||
        frozen.contrastiveFeedback != null) {
      throw StateError('Pair frozen evidence pin/classification changed');
    }
  }

  void _requireLive({bool checkLease = true}) {
    if (_disposed ||
        activeOwnerId() != operation.plan.ownerId ||
        (checkLease && acceptsOperation?.call() == false)) {
      throw StateError('Stale Pair coordinator owner/lifecycle');
    }
  }

  Future<void> _admit(
    Future<void> Function() action, {
    bool recovery = false,
  }) async {
    _requireLive(checkLease: false);
    if (_busy) throw StateError('Pair operation already admitted');
    _busy = true;
    _operationPause ??= _clock.pause(PairPauseReason.persistence);
    try {
      Future<void> guarded() async {
        _requireLive();
        await action();
        _requireLive();
      }

      final runner = recovery ? runRecoveryOperation : runAdmittedOperation;
      if (runner == null) {
        await guarded();
      } else {
        await runner(guarded);
      }
      _requireLive(checkLease: false);
    } finally {
      _busy = false;
      if (state.complete) {
        _completedPause ??= _clock.pause(PairPauseReason.boardUnavailable);
      }
      if (_pendingAppend == null && _pending == null && _close == null) {
        final pause = _operationPause;
        _operationPause = null;
        // The write is already acknowledged. Hold capacity instead of failing
        // that accepted operation or opening an interval we cannot flush.
        _prepareClockResume(failIfFull: false);
        if (pause != null) _clock.release(pause);
      }
    }
  }

  Future<void> dispatch(PairMatchingCommand command) => _admit(() async {
    if (_pendingAppend != null || _pending != null) {
      throw StateError('Pair exact retry required');
    }
    if (_snapshot.terminal != null || _close != null) {
      throw StateError('Pair terminal is read only');
    }
    if (command is PairTimerDecision) {
      await _decideTimer(command);
      return;
    }
    if (timer.mode == PairTimerMode.timeoutDecision ||
        (timer.timed && timer.remainingActiveMs == 0)) {
      throw StateError('Pair timeout decision required');
    }
    final transition = PairMatchingEngine.reduce(_state, command);
    if (identical(transition.state, _state)) return;
    if (transition.attempt != null) {
      _requireCapacity(
        PairMatchingEngine.acknowledge(
          transition.state,
          transition.attempt!.operationId,
        ),
        timer,
        2,
      );
    }
    if (command is PairRevealMapping) {
      _requireCapacity(transition.state, timer, 1);
    }
    PairMatchingCheckpointCodec.requireCompletionCapacity(
      _currentSnapshot(engine: transition.state),
    );
    final attempt = transition.attempt;
    if (attempt == null) {
      _state = transition.state;
      if (command is PairRevealMapping) await _append(_currentSnapshot());
      return;
    }
    _pending = evidence.captureMatching(
      ownerId: operation.plan.ownerId,
      sessionId: operation.plan.learningSessionId,
      wordId: attempt.promptWordId,
      isCorrect: attempt.isCorrect,
      responseTimeMs: attempt.responseTimeMs,
      attemptNumber: state.attempts.length + 1,
      contentRevision: _contentRevision(attempt.promptWordId),
      classification: transition.state.classificationFor(attempt),
    );
    _capturedState = transition.state;
    await _resumeEvidence();
  });

  PairMatchingCheckpointSnapshot _currentSnapshot({
    PairMatchingState? engine,
    List<String>? evidenceIds,
    Map<String, Object?>? frozen,
  }) => PairMatchingCheckpointSnapshot(
    engine: engine ?? state,
    startOperation: operation.stableSerialization,
    evidenceIds: evidenceIds ?? _snapshot.evidenceIds,
    frozenEvidence: frozen,
    timer: timer,
    terminal: _snapshot.terminal,
  );
  Future<void> _resumeEvidence() async {
    final pending = _pending;
    if (pending == null) {
      if (_pendingSnapshot != null) {
        await _append(_pendingSnapshot!);
        _state = _snapshot.engine;
      }
      return;
    }
    if (_pendingSnapshot != null && _pendingSnapshot!.engine.pending == null) {
      await _append(_pendingSnapshot!);
      _state = _snapshot.engine;
      _pending = null;
      _frozen = null;
      _capturedState = null;
      return;
    }
    _frozen ??= await pending.freezeForRecovery();
    _requireLive();
    final candidate = _capturedState ?? _state;
    _validateFrozen(_frozen!, capturedState: candidate);
    final candidateSnapshot = _currentSnapshot(
      engine: candidate,
      frozen: _frozen!.toJson(),
    );
    try {
      PairMatchingCheckpointCodec.requireCompletionCapacity(candidateSnapshot);
    } on StateError {
      // No persistence has been attempted for a captured-only candidate. A
      // newly unsupported metadata schema is rejected before admission.
      if (_capturedState != null &&
          _snapshot.engine.pending == null &&
          _pendingAppend == null) {
        _pending = null;
        _frozen = null;
        _capturedState = null;
      }
      rethrow;
    }
    _state = candidate;
    if (_snapshot.engine.pending == null) {
      await _append(_currentSnapshot(frozen: _frozen!.toJson()));
    }
    _requireLive();
    if (!pending.isCommitted) {
      await (pending.requiresRetry ? pending.retry() : pending.record());
    }
    _requireLive();
    final committed = PairMatchingEngine.acknowledge(
      _state,
      _state.pending!.operationId,
    );
    await _append(
      _currentSnapshot(
        engine: committed,
        evidenceIds: [..._snapshot.evidenceIds, pending.sourceEvidenceId],
      ),
    );
    _state = committed;
    _pending = null;
    _frozen = null;
    _capturedState = null;
  }

  Future<void> retryPending() => _admit(() async {
    await _resumeEvidence();
    if (_close != null || _snapshot.terminal != null) await _finishRecovery();
  }, recovery: true);
  Future<List<ReviewQueueItem>> deferredReview(
    PairReviewDeferral adapter,
  ) async {
    _requireLive(checkLease: false);
    final result = <ReviewQueueItem>[];
    // Only the durable acknowledged snapshot supplies provenance identities.
    for (final ticket in _snapshot.engine.repairTickets.where(
      (t) => t.deferred,
    )) {
      final item = operation.plan.orderedLexicalItems.singleWhere(
        (i) => i.wordId == ticket.wordId,
      );
      final need = await adapter.expose(
        ownerId: operation.plan.ownerId,
        sessionId: operation.plan.learningSessionId,
        wordId: ticket.wordId,
        contentRevision: item.contentRevision,
        answerId: _snapshot.evidenceIds[ticket.originalOrdinal],
      );
      _requireLive(checkLease: false);
      if (need != null) result.add(need);
    }
    return List.unmodifiable(result);
  }

  void _requireFlushCapacity() {
    _requireCapacity(state, timer, 1);
  }

  Future<void> flush() => _admit(() async {
    if (_pending != null || _pendingAppend != null) {
      throw StateError('Pair exact retry required');
    }
    if (jsonEncode(_snapshot.engine.toJson()) == jsonEncode(state.toJson())) {
      final stored =
          _snapshot.timer ?? PairTimerState.initial(operation.plan.timerPreset);
      if (stored.remainingActiveMs == timer.remainingActiveMs &&
          stored.elapsedActiveMs == timer.elapsedActiveMs) {
        return;
      }
    }
    _requireFlushCapacity();
    PairMatchingCheckpointCodec.requireCompletionCapacity(_currentSnapshot());
    await _append(_currentSnapshot());
  });
  Future<void> _append(PairMatchingCheckpointSnapshot snapshot) async {
    _requireLive();
    final map = snapshot.toJson();
    PairMatchingCheckpointCodec.decode(map);
    if (_pendingAppend != null &&
        jsonEncode(_pendingAppend!.state) != jsonEncode(map)) {
      throw StateError('Cannot replace uncertain Pair checkpoint');
    }
    _pendingSnapshot ??= snapshot;
    _pendingAppend ??= LearningActivityCheckpoint(
      sessionId: operation.plan.learningSessionId,
      activityType: 'matching',
      revision: _checkpoint.revision + 1,
      occurredAtUtc: learning.nowUtc(),
      state: map,
      terminalAtUtc: snapshot.terminal?.atUtc,
      terminalAcknowledged: snapshot.terminal?.acknowledged ?? false,
    );
    await learning.appendActivityCheckpoint(
      _pendingAppend!,
      ownerId: operation.plan.ownerId,
    );
    _requireLive();
    _checkpoint = _pendingAppend!;
    _snapshot = _pendingSnapshot!;
    if (_snapshot.timer != null) _clock.replace(_snapshot.timer!);
    _pendingAppend = null;
    _pendingSnapshot = null;
  }

  void dispose() {
    _disposed = true;
    _clock.pause(PairPauseReason.boardUnavailable);
  }

  void resumeInteraction() {
    _requireLive(checkLease: false);
    if (state.complete ||
        _pendingAppend != null ||
        _pending != null ||
        _snapshot.terminal != null) {
      throw StateError('Pair exact recovery required');
    }
    _prepareClockResume();
    _clock.resumeInteraction();
  }

  /// Host acquires immediately, then awaits flush before acknowledging a
  /// lifecycle boundary. A burst folds into one flush; tokens are never reused.
  PairPauseLease pause(PairPauseReason reason) {
    _requireLive(checkLease: false);
    return _clock.pause(reason);
  }

  void releasePause(PairPauseLease token) {
    _requireLive(checkLease: false);
    if (!_clock.owns(token)) return;
    _prepareClockResume();
    _clock.release(token);
  }

  Future<void> expire() {
    if (!timer.timed || timer.remainingActiveMs > 0 || state.complete) {
      return Future.value();
    }
    return dispatch(
      PairTimerDecision(
        operationId: '${state.operationRevision}:expire',
        ownerId: operation.plan.ownerId,
        sessionId: operation.plan.learningSessionId,
        roundOrdinal: state.roundOrdinal,
        expectedRevision: state.operationRevision,
        action: PairTimerAction.expire,
      ),
    );
  }

  void _requireCapacity(
    PairMatchingState candidate,
    PairTimerState clock,
    int cost,
  ) {
    if (!_hasCapacity(candidate, clock, cost)) {
      throw StateError('Pair persistence capacity reserved');
    }
  }

  void _prepareClockResume({bool failIfFull = true}) {
    if (!state.complete && timer.timed && !_hasCapacity(state, timer, 1)) {
      _capacityPause ??= _clock.pause(PairPauseReason.capacity);
      if (failIfFull) throw StateError('Pair persistence capacity reserved');
      return;
    }
    final capacity = _capacityPause;
    _capacityPause = null;
    if (capacity != null) _clock.release(capacity);
  }

  bool _hasCapacity(
    PairMatchingState candidate,
    PairTimerState clock,
    int cost,
  ) {
    final remaining = candidate.remainingRepairAttemptBound;
    final reveals = candidate.plan.orderedLexicalItems
        .where(
          (i) =>
              !candidate.matchedWordIds.contains(i.wordId) &&
              !candidate.supportedWordIds.contains(i.wordId),
        )
        .length;
    return PairMatchingCheckpointBudget.canTransition(
      revision: _checkpoint.revision,
      cost: cost,
      attempts: candidate.attempts.length,
      remainingAttemptBound: remaining,
      revealReserve: reveals,
      timerReserve: clock.decisionReserve,
    );
  }

  Future<void> _decideTimer(PairTimerDecision command) async {
    var next = timer;
    if (command.ownerId != operation.plan.ownerId ||
        command.sessionId != operation.plan.learningSessionId) {
      throw StateError('Stale Pair timer owner/session');
    }
    if (next.lastOperationId == command.operationId) {
      if (next.lastFingerprint != command.fingerprint) {
        throw StateError('Pair timer payload conflict');
      }
      return;
    }
    if (state.complete) throw StateError('Pair board already complete');
    switch (command.action) {
      case PairTimerAction.expire:
        if (!next.timed || next.remainingActiveMs != 0) {
          throw StateError('Pair timer has not expired');
        }
        next = next.copy(mode: PairTimerMode.timeoutDecision);
      case PairTimerAction.continueUntimed:
        if (next.mode != PairTimerMode.timeoutDecision &&
            !next.reasons.contains(PairPauseReason.clockFault) &&
            !next.timed) {
          throw StateError('Pair Continue unavailable');
        }
        next = next.copy(
          mode: PairTimerMode.continuedUntimed,
          remainingActiveMs: 0,
          reasons: next.reasons
              .where(
                (r) =>
                    r != PairPauseReason.clockFault &&
                    r != PairPauseReason.capacity,
              )
              .toSet(),
        );
      case PairTimerAction.extend:
        if (next.mode != PairTimerMode.timeoutDecision || next.extensionUsed) {
          throw StateError('Pair extension unavailable');
        }
        next = next.copy(
          mode: PairTimerMode.extendedRunning,
          remainingActiveMs: 30000,
          extensionUsed: true,
        );
      case PairTimerAction.restart:
        if (next.mode != PairTimerMode.timeoutDecision) {
          throw StateError('Pair restart unavailable');
        }
        next = next.copy(
          mode: PairTimerMode.running,
          remainingActiveMs: PairTimerState.initial(
            operation.plan.timerPreset,
          ).remainingActiveMs,
        );
    }
    next = next.copy(
      lastOperationId: command.operationId,
      lastFingerprint: command.fingerprint,
    );
    final candidate = PairMatchingEngine.reduce(state, command).state;
    _requireCapacity(candidate, next, 1);
    final snapshot = PairMatchingCheckpointSnapshot(
      engine: candidate,
      startOperation: operation.stableSerialization,
      evidenceIds: _snapshot.evidenceIds,
      timer: next,
    );
    PairMatchingCheckpointCodec.requireCompletionCapacity(snapshot);
    await _append(snapshot);
    _state = candidate;
  }

  Future<LearningSessionSummary> finish() async {
    await _admit(_finishRecovery, recovery: true);
    return _summary!;
  }

  Future<void> _finishRecovery() async {
    if (_pending != null || _capturedState != null) {
      throw StateError('Pair answer retry required');
    }
    if (_pendingSnapshot != null) {
      await _append(_pendingSnapshot!);
      _state = _snapshot.engine;
    }
    if (!state.complete) throw StateError('Pair planned completion required');
    if (_snapshot.terminal?.acknowledged == true) return;
    final close = _close ??= learning.captureSessionClose(
      sessionId: operation.plan.learningSessionId,
      ownerId: operation.plan.ownerId,
    );
    if (!_closeOwned) {
      ownClose?.call(close, _ensureCloseCheckpoint);
      _closeOwned = true;
    }
    await _ensureCloseCheckpoint();
    final summary =
        await (completeSession?.call(close) ??
            (close.requiresRetry ? close.retry() : close.finish()));
    _requireLive();
    if (summary.id != operation.plan.learningSessionId ||
        summary.ownerId != operation.plan.ownerId ||
        summary.state != 'completed' ||
        summary.endedAtUtc != close.completedAtUtc ||
        summary.correctCount !=
            state.attempts.where((a) => a.isCorrect).length ||
        summary.wrongCount !=
            state.attempts.where((a) => !a.isCorrect).length) {
      throw StateError('Pair canonical summary changed');
    }
    _summary = summary;
    await _append(
      _terminalSnapshot(
        PairTerminalState(close.completedAtUtc, acknowledged: true),
      ),
    );
  }

  PairMatchingCheckpointSnapshot _terminalSnapshot(
    PairTerminalState terminal,
  ) => PairMatchingCheckpointSnapshot(
    engine: state,
    startOperation: operation.stableSerialization,
    evidenceIds: _snapshot.evidenceIds,
    timer: timer,
    terminal: terminal,
  );
  Future<void> _ensureCloseCheckpoint() async {
    _requireLive();
    final existing = _closeCheckpointInFlight;
    if (existing != null) return existing;
    final close = _close;
    if (close == null) throw StateError('Pair close identity unavailable');
    if (_snapshot.terminal != null) return;
    final write = _append(
      _terminalSnapshot(PairTerminalState(close.completedAtUtc)),
    );
    _closeCheckpointInFlight = write;
    try {
      await write;
    } finally {
      if (identical(_closeCheckpointInFlight, write)) {
        _closeCheckpointInFlight = null;
      }
    }
  }

  Future<void> markSummaryPresented() => _admit(() async {
    if (_pendingSnapshot != null) await _append(_pendingSnapshot!);
    final terminal = _snapshot.terminal;
    if (terminal == null || !terminal.acknowledged) {
      throw StateError('Pair terminal acknowledgement required');
    }
    if (terminal.presented) return;
    await _append(
      _terminalSnapshot(
        PairTerminalState(terminal.atUtc, acknowledged: true, presented: true),
      ),
    );
  }, recovery: true);
}

extension on Stopwatch {
  int elapsedMicrosecondsReader() => elapsedMicroseconds;
}
