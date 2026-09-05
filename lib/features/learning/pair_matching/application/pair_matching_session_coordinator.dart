import 'dart:convert';
import '../../application/current_activity_evidence.dart';
import '../../application/learning_use_cases.dart';
import '../../domain/evidence_context.dart';
import '../../domain/hint_policy.dart';
import '../../domain/learning_models.dart';
import '../../domain/lexical_prompt_artifact_identity.dart';
import '../data/pair_matching_checkpoint_codec.dart';
import '../domain/pair_matching_engine.dart';
import '../domain/pair_matching_checkpoint_budget.dart';
import 'pair_matching_atomic_start.dart';

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
  }) : _snapshot = snapshot,
       _state = snapshot.engine;
  final PairMatchingStartOperation operation;
  final LearningUseCases learning;
  final CurrentActivityEvidenceAdapter evidence;
  final String? Function() activeOwnerId;
  final bool Function()? acceptsOperation;
  final PairSessionOperation? runAdmittedOperation, runRecoveryOperation;
  LearningActivityCheckpoint _checkpoint;
  PairMatchingCheckpointSnapshot _snapshot;
  PairMatchingState _state;
  PairMatchingState get state => _state;
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
    );
    c._validateRecovery(recovery);
    final frozen = snapshot.frozenEvidence;
    if (frozen != null) {
      c._frozen = FrozenPendingCurrentActivityEvidence.fromJson(frozen);
      c._validateFrozen(c._frozen!);
      c._pending = evidence.restore(c._frozen!);
    }
    // A terminal session is readable, but PM4 owns exact terminal dispatch.
    if (recovery.session.state != 'active') c._disposed = true;
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
      final guided = role.role == PairAttemptRole.guidedCompletion;
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
            (role.role == PairAttemptRole.guidedCompletion
                ? EvidenceClass.guidedPractice
                : EvidenceClass.recognition) ||
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
    }
  }

  Future<void> dispatch(PairMatchingCommand command) => _admit(() async {
    if (_pendingAppend != null || _pending != null) {
      throw StateError('Pair exact retry required');
    }
    final transition = PairMatchingEngine.reduce(_state, command);
    if (identical(transition.state, _state)) return;
    if (transition.attempt != null &&
        !PairMatchingCheckpointBudget.canAnswer(
          revision: _checkpoint.revision,
          attempts: state.attempts.length,
          remainingPairs:
              operation.plan.orderedLexicalItems.length -
              state.matchedWordIds.length,
          isCorrect: transition.attempt!.isCorrect,
        )) {
      throw StateError('Pair persistence capacity reserved');
    }
    if (command is PairRevealMapping) _requireFlushCapacity();
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
      classification: HintEvidenceClassification(
        evidenceClass: attempt.role == PairAttemptRole.guidedCompletion
            ? EvidenceClass.guidedPractice
            : EvidenceClass.recognition,
        hintLevel: attempt.role == PairAttemptRole.guidedCompletion ? 1 : 0,
      ),
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
  );
  Future<void> _resumeEvidence() async {
    final pending = _pending;
    if (pending == null) {
      if (_pendingSnapshot != null) await _append(_pendingSnapshot!);
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

  Future<void> retryPending() => _admit(_resumeEvidence, recovery: true);
  void _requireFlushCapacity() {
    final remaining =
        operation.plan.orderedLexicalItems.length - state.matchedWordIds.length;
    if (_checkpoint.revision +
            1 +
            remaining * 2 +
            PairMatchingCheckpointBudget.terminalReserve +
            PairMatchingCheckpointBudget.continueUntimedReserve >
        PairMatchingCheckpointBudget.maximumRevisions) {
      throw StateError('Pair flush capacity reserved');
    }
  }

  Future<void> flush() => _admit(() async {
    if (_pending != null || _pendingAppend != null) {
      throw StateError('Pair exact retry required');
    }
    if (jsonEncode(_snapshot.engine.toJson()) == jsonEncode(state.toJson())) {
      return;
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
    );
    await learning.appendActivityCheckpoint(
      _pendingAppend!,
      ownerId: operation.plan.ownerId,
    );
    _requireLive();
    _checkpoint = _pendingAppend!;
    _snapshot = _pendingSnapshot!;
    _pendingAppend = null;
    _pendingSnapshot = null;
  }

  void dispose() {
    _disposed = true;
  }
}
