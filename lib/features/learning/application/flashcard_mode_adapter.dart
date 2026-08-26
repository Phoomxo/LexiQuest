import 'package:flutter/foundation.dart';

import '../domain/evidence_context.dart';
import '../domain/learning_models.dart';
import '../domain/lesson_mode.dart';
import '../domain/session_configuration.dart';
import 'current_activity_evidence.dart';
import 'learning_use_cases.dart';

typedef FlashcardSessionCompleter =
    Future<LearningSessionSummary> Function(PendingLearningSessionClose close);
typedef FlashcardAdmittedOperation =
    Future<T> Function<T>(Future<T> Function() operation);
typedef FlashcardRecoveryOperation =
    Future<T> Function<T>(Future<T> Function() operation);
typedef FlashcardOperationAcceptance = bool Function();

enum FlashcardReviewPhase {
  awaitingRecall,
  savingEvidence,
  evidenceRetryRequired,
  revealed,
  completing,
  completionRetryRequired,
  completed,
}

/// The production flashcard adapter owns the per-route review state machine.
/// It delegates every durable write to the canonical current-activity evidence
/// gateway and [LearningUseCases]; it is never an SRS writer itself.
final class FlashcardModeAdapter
    implements
        FocusTimerSupportingLessonModeAdapter,
        SessionConfigurableLessonModeAdapter {
  const FlashcardModeAdapter();

  @override
  LessonMode get mode => LessonMode.flashcard;

  @override
  SessionConfigurationCapabilities get sessionConfigurationCapabilities =>
      const SessionConfigurationCapabilities(
        minimumItemCount: 1,
        maximumItemCount: 100,
        defaultItemCount: 10,
        directions: <SessionDirection>{SessionDirection.forward},
        difficulties: <SessionDifficulty>{SessionDifficulty.standard},
        maximumHintBudget: 0,
        supportsTimed: true,
        supportsUntimedAlternative: true,
        supportsPackSelection: false,
      );

  FlashcardReviewController createReview({
    required QuizSession session,
    required LearningUseCases learning,
    required CurrentActivityEvidenceAdapter evidence,
    FlashcardSessionCompleter? completeSession,
    FlashcardAdmittedOperation? runAdmittedOperation,
    FlashcardRecoveryOperation? runRecoveryOperation,
    FlashcardOperationAcceptance? acceptsOperation,
  }) {
    if (session.isEmpty) {
      throw ArgumentError.value(session, 'session', 'must contain a card');
    }
    if (!identical(evidence.learning, learning)) {
      throw ArgumentError(
        'Flashcard evidence must use the session LearningUseCases authority.',
      );
    }
    return FlashcardReviewController._(
      session: session,
      learning: learning,
      evidence: evidence,
      completeSession:
          completeSession ??
          (close) => close.requiresRetry ? close.retry() : close.finish(),
      runAdmittedOperation:
          runAdmittedOperation ?? <T>(operation) => operation(),
      runRecoveryOperation:
          runRecoveryOperation ?? <T>(operation) => operation(),
      acceptsOperation: acceptsOperation ?? () => true,
    );
  }

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final context = support.evidenceContext;
    switch (response.promptMode) {
      case 'flashcardExposure':
        if (context.evidenceClass != EvidenceClass.exposure) {
          throw StateError('A revealed flashcard must remain exposure.');
        }
        return context;
      case 'srsRecall':
        if (context.evidenceClass != EvidenceClass.independentRecall ||
            context.hintLevel != 0) {
          throw StateError(
            'Only an unrevealed self-rating is independent SRS recall.',
          );
        }
        return context;
      default:
        throw StateError(
          'Unsupported flashcard prompt mode ${response.promptMode}.',
        );
    }
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('FlashcardReviewController owns durable item selection.'),
  );
}

final class FlashcardReviewController extends ChangeNotifier {
  FlashcardReviewController._({
    required this._session,
    required this._learning,
    required this._evidence,
    required this._completeSession,
    required this._runAdmittedOperation,
    required this._runRecoveryOperation,
    required this._acceptsOperation,
  });

  final QuizSession _session;
  final LearningUseCases _learning;
  final CurrentActivityEvidenceAdapter _evidence;
  final FlashcardSessionCompleter _completeSession;
  final FlashcardAdmittedOperation _runAdmittedOperation;
  final FlashcardRecoveryOperation _runRecoveryOperation;
  final FlashcardOperationAcceptance _acceptsOperation;

  var _index = 0;
  var _phase = FlashcardReviewPhase.awaitingRecall;
  PendingCurrentActivityEvidence? _pendingEvidence;
  _FlashcardEvidenceKind? _pendingKind;
  PendingLearningSessionClose? _pendingClose;
  bool _disposed = false;

  QuizSession get session => _session;
  int get index => _index;
  QuizQuestion get currentQuestion => _session.questions[_index];
  FlashcardReviewPhase get phase => _phase;
  bool get isRevealed => _phase == FlashcardReviewPhase.revealed;
  bool get isCompleted => _phase == FlashcardReviewPhase.completed;
  bool get isSaving =>
      _phase == FlashcardReviewPhase.savingEvidence ||
      _phase == FlashcardReviewPhase.completing;
  bool get requiresRetry =>
      _phase == FlashcardReviewPhase.evidenceRetryRequired ||
      _phase == FlashcardReviewPhase.completionRetryRequired;
  bool get requiresCompletionRetry =>
      _phase == FlashcardReviewPhase.completionRetryRequired;
  bool get persistenceLocked =>
      _pendingEvidence != null || _pendingClose != null;
  bool get actionLocked =>
      !_acceptsOperation() ||
      _phase != FlashcardReviewPhase.awaitingRecall &&
          _phase != FlashcardReviewPhase.revealed;
  String? get pendingEvidenceId => _pendingEvidence?.sourceEvidenceId;

  Future<void> rate({required bool remembered, required int responseTimeMs}) {
    _requireOperationAccepted();
    _requirePhase(FlashcardReviewPhase.awaitingRecall, 'rate');
    return _captureAndRecord(
      kind: _FlashcardEvidenceKind.independentRecall,
      input: CurrentActivityInput.srsRecall,
      isCorrect: remembered,
      responseTimeMs: responseTimeMs,
    );
  }

  Future<void> reveal({required int responseTimeMs}) {
    _requireOperationAccepted();
    _requirePhase(FlashcardReviewPhase.awaitingRecall, 'reveal');
    return _captureAndRecord(
      kind: _FlashcardEvidenceKind.exposure,
      input: null,
      isCorrect: false,
      responseTimeMs: responseTimeMs,
    );
  }

  Future<void> advanceAfterReveal() async {
    _requireNotDisposed();
    _requirePhase(FlashcardReviewPhase.revealed, 'advance');
    await _runRecoveryOperation(() async {
      _requirePhase(FlashcardReviewPhase.revealed, 'advance');
      await _advanceOrComplete();
    });
  }

  Future<void> retry() {
    _requireNotDisposed();
    return _runRecoveryOperation(() async {
      switch (_phase) {
        case FlashcardReviewPhase.evidenceRetryRequired:
          final pending = _pendingEvidence;
          final kind = _pendingKind;
          if (pending == null || kind == null || !pending.requiresRetry) {
            throw StateError('Exact flashcard evidence retry is unavailable.');
          }
          _setPhase(FlashcardReviewPhase.savingEvidence);
          try {
            await pending.retry();
          } catch (_) {
            _setPhase(FlashcardReviewPhase.evidenceRetryRequired);
            rethrow;
          }
          await _afterEvidenceCommitted(kind);
          return;
        case FlashcardReviewPhase.completionRetryRequired:
          await _complete();
          return;
        default:
          throw StateError('Flashcard review is not awaiting retry.');
      }
    });
  }

  Future<void> _captureAndRecord({
    required _FlashcardEvidenceKind kind,
    required CurrentActivityInput? input,
    required bool isCorrect,
    required int responseTimeMs,
  }) {
    if (responseTimeMs < 0) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must not be negative',
      );
    }
    return _runAdmittedOperation(() async {
      _requirePhase(FlashcardReviewPhase.awaitingRecall, 'record evidence');
      final pending = kind == _FlashcardEvidenceKind.exposure
          ? _evidence.captureFlashcardExposure(
              sessionId: _session.id,
              wordId: currentQuestion.word.id,
              responseTimeMs: responseTimeMs,
              attemptNumber: _index + 1,
            )
          : _evidence.capture(
              input: input!,
              sessionId: _session.id,
              wordId: currentQuestion.word.id,
              isCorrect: isCorrect,
              responseTimeMs: responseTimeMs,
              attemptNumber: _index + 1,
            );
      _pendingEvidence = pending;
      _pendingKind = kind;
      _setPhase(FlashcardReviewPhase.savingEvidence);
      try {
        await pending.record();
      } catch (_) {
        _setPhase(FlashcardReviewPhase.evidenceRetryRequired);
        rethrow;
      }
      await _afterEvidenceCommitted(kind);
    });
  }

  Future<void> _afterEvidenceCommitted(_FlashcardEvidenceKind kind) async {
    _pendingEvidence = null;
    _pendingKind = null;
    if (kind == _FlashcardEvidenceKind.exposure) {
      _setPhase(FlashcardReviewPhase.revealed);
      return;
    }
    await _advanceOrComplete();
  }

  Future<void> _advanceOrComplete() async {
    if (_index < _session.questions.length - 1) {
      _index += 1;
      _setPhase(FlashcardReviewPhase.awaitingRecall);
      return;
    }
    await _complete();
  }

  Future<void> _complete() async {
    final close = _pendingClose ??= _learning.captureSessionClose(
      sessionId: _session.id,
    );
    _setPhase(FlashcardReviewPhase.completing);
    try {
      await _completeSession(close);
      _pendingClose = null;
      _setPhase(FlashcardReviewPhase.completed);
    } catch (_) {
      _setPhase(FlashcardReviewPhase.completionRetryRequired);
      rethrow;
    }
  }

  void _requirePhase(FlashcardReviewPhase expected, String action) {
    _requireNotDisposed();
    if (_phase != expected) {
      throw StateError('Cannot $action flashcard review from ${_phase.name}.');
    }
  }

  void _requireOperationAccepted() {
    _requireNotDisposed();
    if (!_acceptsOperation()) {
      throw StateError('The flashcard route is no longer accepting actions.');
    }
  }

  void _requireNotDisposed() {
    if (_disposed) throw StateError('Flashcard review is disposed.');
  }

  void _setPhase(FlashcardReviewPhase next) {
    _phase = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

enum _FlashcardEvidenceKind { exposure, independentRecall }
