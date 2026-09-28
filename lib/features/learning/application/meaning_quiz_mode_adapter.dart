export '../domain/meaning_quiz_composition.dart';
import '../domain/meaning_quiz_composition.dart';
import 'package:flutter/foundation.dart';

import '../../vocabulary/domain/vocabulary_word.dart';
import '../domain/evidence_context.dart';
import '../domain/answer_feedback.dart';
import '../domain/contrastive_explanation.dart';
import '../domain/learning_models.dart';
import '../domain/lesson_mode.dart';
import '../domain/session_configuration.dart';
import 'current_activity_evidence.dart';
import 'learning_use_cases.dart';
import 'ordinary_meaning_recovery.dart';

typedef MeaningQuizSessionCompleter =
    Future<LearningSessionSummary> Function(PendingLearningSessionClose close);
typedef MeaningQuizInteractionRecorder = void Function();
typedef MeaningQuizOperationAcceptance = bool Function();
typedef MeaningQuizEvidenceOperation =
    Future<AnswerRecordResult> Function(
      Future<AnswerRecordResult> Function() operation,
    );

enum MeaningQuizReviewPhase {
  awaitingAnswer,
  savingEvidence,
  evidenceRetryRequired,
  answered,
  skipped,
  completing,
  completionRetryRequired,
  completed,
}

/// Typed production boundary for bidirectional meaning recognition.
final class MeaningQuizModeAdapter
    implements
        FocusTimerSupportingLessonModeAdapter,
        SessionConfigurableLessonModeAdapter {
  const MeaningQuizModeAdapter();

  @override
  LessonMode get mode => LessonMode.meaningQuiz;

  @override
  SessionConfigurationCapabilities get sessionConfigurationCapabilities =>
      const SessionConfigurationCapabilities(
        minimumItemCount: 1,
        maximumItemCount: 100,
        defaultItemCount: 10,
        directions: <SessionDirection>{
          SessionDirection.forward,
          SessionDirection.reverse,
          SessionDirection.mixed,
        },
        difficulties: <SessionDifficulty>{SessionDifficulty.standard},
        maximumHintBudget: 0,
        supportsTimed: true,
        supportsUntimedAlternative: true,
        supportsPackSelection: true,
      );

  MeaningQuizReviewController createReview({
    required QuizSession session,
    required LearningUseCases learning,
    required CurrentActivityEvidenceAdapter evidence,
    MeaningQuizSessionCompleter? completeSession,
    MeaningQuizInteractionRecorder? recordInteraction,
    MeaningQuizOperationAcceptance? acceptsOperation,
    MeaningQuizEvidenceOperation? runEvidenceOperation,
    SessionDirection direction = SessionDirection.mixed,
    Iterable<VocabularyWord> lexicalWords = const <VocabularyWord>[],
    Iterable<QuizWord> distractorWords = const <QuizWord>[],
  }) {
    if (session.isEmpty) {
      throw ArgumentError.value(session, 'session', 'must contain a question');
    }
    if (!identical(evidence.learning, learning)) {
      throw ArgumentError(
        'Meaning quiz evidence must use the session LearningUseCases authority.',
      );
    }
    return MeaningQuizReviewController._(
      session: session,
      questions: pinQuestions(
        session,
        direction: direction,
        lexicalWords: lexicalWords,
        distractorWords: distractorWords,
      ),
      learning: learning,
      evidence: evidence,
      completeSession:
          completeSession ??
          (close) => close.requiresRetry ? close.retry() : close.finish(),
      recordInteraction: recordInteraction ?? () {},
      acceptsOperation: acceptsOperation ?? () => true,
      runEvidenceOperation: runEvidenceOperation ?? (operation) => operation(),
    );
  }

  /// Pins direction, prompt, correctness and distractor order to canonical
  /// session content. Reconstructing the same session yields the same quiz.
  List<MeaningQuizQuestion> pinQuestions(
    QuizSession session, {
    SessionDirection direction = SessionDirection.mixed,
    Iterable<VocabularyWord> lexicalWords = const <VocabularyWord>[],
    Iterable<QuizWord> distractorWords = const <QuizWord>[],
  }) {
    final admitted = session.ordinaryMeaningPlan;
    if (admitted != null) {
      admitted.validatePresentation(session);
      return admitted.questions;
    }
    return composeMeaningQuiz(
      session,
      direction: direction,
      lexicalWords: lexicalWords,
      distractorWords: distractorWords,
    );
  }

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final context = support.evidenceContext;
    final unassistedRecognition =
        context.evidenceClass == EvidenceClass.recognition &&
        context.hintLevel == 0;
    final guidedMeaningChoice =
        response.promptMode == 'meaningChoice' &&
        context.evidenceClass == EvidenceClass.guidedPractice &&
        context.hintLevel > 0 &&
        context.hintLevel <= 2;
    if ((response.promptMode != 'meaningChoice' &&
            response.promptMode != 'wordChoice') ||
        (!unassistedRecognition && !guidedMeaningChoice)) {
      throw StateError(
        'Meaning quiz answers require recognition or guided meaning choice evidence.',
      );
    }
    return context;
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('MeaningQuizReviewController owns pinned item selection.'),
  );
}

final class MeaningQuizReviewController extends ChangeNotifier {
  MeaningQuizReviewController._({
    required this.session,
    required List<MeaningQuizQuestion> questions,
    required this._learning,
    required this._evidence,
    required this._completeSession,
    required this._recordInteraction,
    required this._acceptsOperation,
    required this._runEvidenceOperation,
  }) : questions = List<MeaningQuizQuestion>.unmodifiable(questions);

  final QuizSession session;
  final List<MeaningQuizQuestion> questions;
  final LearningUseCases _learning;
  final CurrentActivityEvidenceAdapter _evidence;
  final MeaningQuizSessionCompleter _completeSession;
  final MeaningQuizInteractionRecorder _recordInteraction;
  final MeaningQuizOperationAcceptance _acceptsOperation;
  final MeaningQuizEvidenceOperation _runEvidenceOperation;

  var _index = 0;
  var _phase = MeaningQuizReviewPhase.awaitingAnswer;
  PendingCurrentActivityEvidence? _pendingEvidence;
  FrozenAnswerFeedbackContext? _pendingFeedbackContext;
  PendingLearningSessionClose? _pendingClose;
  AnswerFeedback? _feedback;
  String? _selectedOption;
  bool _disposed = false;
  OrdinaryMeaningRecovery? _durable;
  FrozenPendingCurrentActivityEvidence? _frozen;

  bool get _acceptsDurable => !_disposed && _acceptsOperation();

  Future<void> initializeDurable() async {
    if (session.ordinaryMeaningPlan == null || _durable != null) return;
    final durable = await OrdinaryMeaningRecovery.load(
      learning: _learning,
      ownerId: session.ownerId!,
      sessionId: session.id,
      acceptsOperation: () => _acceptsDurable,
    );
    _requireOperationAccepted();
    final p = durable.progress;
    p.plan.validatePresentation(session);
    _durable = durable;
    _index = p.index;
    _selectedOption = p.selected;
    _frozen = p.evidence;
    if (p.evidence != null) {
      _pendingEvidence = _evidence.restore(p.evidence!);
      _pendingFeedbackContext = AnswerFeedbackContext(
        canonicalCorrectAnswer: currentQuestion.correctOption,
      ).freeze();
      _phase = MeaningQuizReviewPhase.evidenceRetryRequired;
      if (p.phase == 'answered' || p.phase == 'closing') {
        // Canonical replay recovers committed feedback without a new identity.
        final result = await durable.run(
          _pendingEvidence!.retry,
          () => _acceptsDurable,
        );
        await durable.requireCurrent(() => _acceptsDurable);
        _requireOperationAccepted();
        _feedback = AnswerFeedback.fromFrozenCommittedResult(
          result: result,
          context: _pendingFeedbackContext!,
        );
        _pendingEvidence = null;
        _pendingFeedbackContext = null;
        _phase = MeaningQuizReviewPhase.answered;
      }
    }
    if (p.phase == 'closing') {
      _pendingClose = _learning.restoreSessionClose(
        sessionId: session.id,
        ownerId: session.ownerId,
        completedAtUtc: p.closeAt!,
        runOperation: (operation) =>
            durable.run(operation, () => _acceptsDurable),
      );
      _phase = MeaningQuizReviewPhase.completionRetryRequired;
    } else if (p.phase == 'skipped') {
      _phase = MeaningQuizReviewPhase.skipped;
    }
  }

  Future<void> _persist(String phase, {int? index, DateTime? closeAt}) async {
    final durable = _durable;
    if (durable == null) return;
    await durable.save(
      OrdinaryMeaningProgress(
        plan: session.ordinaryMeaningPlan!,
        index: index ?? _index,
        phase: phase,
        selected: phase == 'awaitingAnswer' || phase == 'skipped'
            ? null
            : _selectedOption,
        evidence:
            phase == 'pending' || phase == 'answered' || phase == 'closing'
            ? _frozen
            : null,
        closeAt: closeAt,
      ),
      () => _acceptsDurable,
    );
    _requireOperationAccepted();
  }

  int get index => _index;
  MeaningQuizReviewPhase get phase => _phase;
  MeaningQuizQuestion get currentQuestion => questions[_index];
  AnswerFeedback? get feedback => _feedback;
  String? get selectedOption => _selectedOption;
  bool get isAnswered => _phase == MeaningQuizReviewPhase.answered;
  bool get isSkipped => _phase == MeaningQuizReviewPhase.skipped;
  bool get isCompleted => _phase == MeaningQuizReviewPhase.completed;
  bool get isSaving =>
      _phase == MeaningQuizReviewPhase.savingEvidence ||
      _phase == MeaningQuizReviewPhase.completing;
  bool get requiresRetry =>
      _phase == MeaningQuizReviewPhase.evidenceRetryRequired ||
      _phase == MeaningQuizReviewPhase.completionRetryRequired;
  bool get persistenceLocked =>
      isSaving ||
      requiresRetry ||
      _pendingEvidence != null ||
      _pendingClose != null;
  bool get actionLocked =>
      !_acceptsOperation() ||
      (_phase != MeaningQuizReviewPhase.awaitingAnswer &&
          _phase != MeaningQuizReviewPhase.answered &&
          _phase != MeaningQuizReviewPhase.skipped);

  Future<void> skip() async {
    _requireOperationAccepted();
    _requirePhase(MeaningQuizReviewPhase.awaitingAnswer, 'skip');
    if (session.ordinaryMeaningPlan != null && _durable == null) {
      await initializeDurable();
      _requireOperationAccepted();
      _requirePhase(MeaningQuizReviewPhase.awaitingAnswer, 'skip');
    }
    _recordInteraction();
    if (session.ordinaryMeaningPlan != null) {
      _setPhase(MeaningQuizReviewPhase.savingEvidence);
      try {
        await _persist('skipped');
      } catch (_) {
        _setPhase(MeaningQuizReviewPhase.awaitingAnswer);
        rethrow;
      }
    }
    _selectedOption = null;
    _setPhase(MeaningQuizReviewPhase.skipped);
  }

  Future<AnswerRecordResult> answer({
    required String option,
    required int responseTimeMs,
  }) {
    _requireOperationAccepted();
    _requirePhase(MeaningQuizReviewPhase.awaitingAnswer, 'answer');
    if (responseTimeMs < 0) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must not be negative',
      );
    }
    final question = currentQuestion;
    if (!question.options.contains(option)) {
      throw ArgumentError.value(option, 'option', 'is not a pinned option');
    }
    final feedbackContext = AnswerFeedbackContext(
      canonicalCorrectAnswer: question.correctOption,
    ).freeze();
    final isCorrect = option == question.correctOption;
    final input = question.direction == MeaningQuizDirection.wordToMeaning
        ? CurrentActivityInput.meaningMultipleChoice
        : CurrentActivityInput.meaningToWordMultipleChoice;
    final manifestIdentity = question.contrastiveIdentity;
    final contentRevision = manifestIdentity?.revision;
    final manifestChecksum = question.contrastiveChecksumSha256;
    final checksum = question.evidenceChecksumSha256;
    final hasPinnedLexicalIdentity =
        contentRevision != null &&
        contentRevision > 0 &&
        checksum != null &&
        manifestChecksum != null &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum);
    final selectedOptionId = question.optionIdentity(option);
    final correctOptionId = question.optionIdentity(question.correctOption);
    final contrastiveFeedback =
        !isCorrect &&
            hasPinnedLexicalIdentity &&
            selectedOptionId != null &&
            correctOptionId != null
        ? ContrastiveFeedbackContext(
            manifestIdentity: manifestIdentity!,
            manifestChecksumSha256: manifestChecksum,
            promptMode: input == CurrentActivityInput.meaningMultipleChoice
                ? 'meaningChoice'
                : 'wordChoice',
            evidenceContentRevision: contrastiveEvidenceContentRevision(
              promptMode: input == CurrentActivityInput.meaningMultipleChoice
                  ? 'meaningChoice'
                  : 'wordChoice',
              wordId: question.word.id,
              revision: contentRevision,
              checksumSha256: checksum,
            ),
            correctOptionId: correctOptionId,
            selectedDistractorId: selectedOptionId,
          )
        : null;
    _recordInteraction();
    final pending = hasPinnedLexicalIdentity
        ? _evidence.capturePinnedMeaningRecognition(
            ownerId: session.ownerId,
            input: input,
            sessionId: session.id,
            wordId: question.word.id,
            isCorrect: isCorrect,
            responseTimeMs: responseTimeMs,
            attemptNumber: _index + 1,
            contentRevision: contentRevision,
            checksumSha256: checksum,
            contrastiveFeedback: contrastiveFeedback,
          )
        : _evidence.capture(
            ownerId: session.ownerId,
            input: input,
            sessionId: session.id,
            wordId: question.word.id,
            isCorrect: isCorrect,
            responseTimeMs: responseTimeMs,
            attemptNumber: _index + 1,
          );
    _pendingEvidence = pending;
    _pendingFeedbackContext = feedbackContext;
    _selectedOption = option;
    _setPhase(MeaningQuizReviewPhase.savingEvidence);
    return _commitEvidence(
      pending,
      feedbackContext: feedbackContext,
      retry: false,
    );
  }

  Future<AnswerRecordResult> retryEvidence() {
    _requireOperationAccepted();
    _requirePhase(
      MeaningQuizReviewPhase.evidenceRetryRequired,
      'retry evidence',
    );
    final pending = _pendingEvidence;
    if (pending == null ||
        (!pending.requiresRetry && session.ordinaryMeaningPlan == null)) {
      throw StateError('Exact meaning recognition retry is unavailable.');
    }
    final feedbackContext = _pendingFeedbackContext;
    if (feedbackContext == null) {
      throw StateError('Frozen meaning quiz feedback is unavailable.');
    }
    _setPhase(MeaningQuizReviewPhase.savingEvidence);
    return _commitEvidence(
      pending,
      feedbackContext: feedbackContext,
      retry: true,
    );
  }

  Future<AnswerRecordResult> _commitEvidence(
    PendingCurrentActivityEvidence pending, {
    required FrozenAnswerFeedbackContext feedbackContext,
    required bool retry,
  }) async {
    try {
      if (session.ordinaryMeaningPlan != null) {
        // Initial attachment must precede capture; a restore never captures again.
        if (_durable == null) {
          final loaded = await OrdinaryMeaningRecovery.load(
            learning: _learning,
            ownerId: session.ownerId!,
            sessionId: session.id,
            acceptsOperation: () => _acceptsDurable,
          );
          _requireOperationAccepted();
          if (loaded.recovery.checkpoint!.revision != 1 ||
              loaded.progress.index != _index ||
              loaded.progress.phase != 'awaitingAnswer') {
            throw StateError(
              'Restore the accepted ordinary controller before answering',
            );
          }
          _durable = loaded;
        }
        _requireOperationAccepted();
        if (_frozen == null && _durable!.progress.phase == 'awaitingAnswer') {
          await _durable!.save(
            OrdinaryMeaningProgress(
              plan: session.ordinaryMeaningPlan!,
              index: _index,
              selected: _selectedOption,
            ),
            () => _acceptsDurable,
          );
          _requireOperationAccepted();
        }
        _frozen ??= await pending.freezeForRecovery();
        _requireOperationAccepted();
        await _durable!.reconcilePending(() => _acceptsDurable);
        _requireOperationAccepted();
        if (_durable!.progress.phase == 'answered' &&
            _durable!.progress.evidence?.sourceEvidenceId !=
                pending.sourceEvidenceId) {
          throw StateError('Ordinary answer identity changed');
        }
        if (_durable!.progress.phase != 'answered') await _persist('pending');
      }
      final result = await _runEvidenceOperation(() {
        Future<AnswerRecordResult> record() =>
            pending.requiresRetry ? pending.retry() : pending.record();
        return _durable == null
            ? record()
            : _durable!.run(record, () => _acceptsDurable);
      });
      if (session.ordinaryMeaningPlan != null) {
        _requireOperationAccepted();
        await _persist('answered');
      }
      final feedback = AnswerFeedback.fromFrozenCommittedResult(
        result: result,
        context: feedbackContext,
      );
      _feedback = feedback;
      _pendingEvidence = null;
      _pendingFeedbackContext = null;
      _setPhase(MeaningQuizReviewPhase.answered);
      return result;
    } catch (_) {
      if (pending.requiresRetry || session.ordinaryMeaningPlan != null) {
        if (_frozen != null && session.ordinaryMeaningPlan != null) {
          _pendingEvidence = _evidence.restore(_frozen!);
        }
        _setPhase(MeaningQuizReviewPhase.evidenceRetryRequired);
      } else {
        _pendingEvidence = null;
        _pendingFeedbackContext = null;
        _selectedOption = null;
        _setPhase(MeaningQuizReviewPhase.awaitingAnswer);
      }
      rethrow;
    }
  }

  Future<LearningSessionSummary?> advance() async {
    _requireOperationAccepted();
    if (_phase != MeaningQuizReviewPhase.answered &&
        _phase != MeaningQuizReviewPhase.skipped) {
      throw StateError('Cannot advance meaning quiz from ${_phase.name}.');
    }
    if (_index < questions.length - 1) {
      if (session.ordinaryMeaningPlan != null) {
        final previousPhase = _phase;
        _setPhase(MeaningQuizReviewPhase.savingEvidence);
        try {
          await _persist('awaitingAnswer', index: _index + 1);
        } catch (_) {
          _setPhase(previousPhase);
          rethrow;
        }
        _requireOperationAccepted();
      }
      _index += 1;
      _frozen = null;
      _selectedOption = null;
      _feedback = null;
      _setPhase(MeaningQuizReviewPhase.awaitingAnswer);
      return null;
    }
    return _complete();
  }

  Future<LearningSessionSummary> retryCompletion() {
    _requireOperationAccepted();
    _requirePhase(
      MeaningQuizReviewPhase.completionRetryRequired,
      'retry completion',
    );
    return _complete();
  }

  Future<LearningSessionSummary> _complete() async {
    _requireOperationAccepted();
    final close = _pendingClose ??= session.ordinaryMeaningPlan == null
        ? _learning.captureSessionClose(
            sessionId: session.id,
            ownerId: session.ownerId,
          )
        : _learning.restoreSessionClose(
            sessionId: session.id,
            ownerId: session.ownerId,
            runOperation: (operation) =>
                _durable!.run(operation, () => _acceptsDurable),
            completedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              _learning.nowUtc().millisecondsSinceEpoch,
              isUtc: true,
            ),
          );
    _setPhase(MeaningQuizReviewPhase.completing);
    try {
      if (session.ordinaryMeaningPlan != null) {
        await _persist('closing', closeAt: close.completedAtUtc);
        _requireOperationAccepted();
      }
      final summary = await _completeSession(close);
      if (session.ordinaryMeaningPlan != null) {
        _requireOperationAccepted();
        await _durable!.acknowledgeClose(() => _acceptsDurable);
        _requireOperationAccepted();
      }
      _pendingClose = null;
      _setPhase(MeaningQuizReviewPhase.completed);
      return summary;
    } catch (_) {
      _setPhase(MeaningQuizReviewPhase.completionRetryRequired);
      rethrow;
    }
  }

  void _requireOperationAccepted() {
    _requireNotDisposed();
    if (!_acceptsOperation()) {
      throw StateError(
        'The meaning quiz route is no longer accepting actions.',
      );
    }
  }

  void _requirePhase(MeaningQuizReviewPhase required, String action) {
    _requireNotDisposed();
    if (_phase != required) {
      throw StateError('Cannot $action meaning quiz from ${_phase.name}.');
    }
  }

  void _requireNotDisposed() {
    if (_disposed) throw StateError('Meaning quiz review is disposed.');
  }

  void _setPhase(MeaningQuizReviewPhase next) {
    if (_disposed) return;
    _phase = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
