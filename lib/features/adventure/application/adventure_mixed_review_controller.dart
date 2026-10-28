import 'package:flutter/foundation.dart';

import '../../learning/application/cloze_mode_adapter.dart';
import '../../learning/application/current_activity_evidence.dart';
import '../../learning/application/definition_quiz_mode_adapter.dart';
import '../../learning/application/lesson_mode_registry.dart';
import '../../learning/application/learning_use_cases.dart';
import '../../learning/application/meaning_quiz_mode_adapter.dart';
import '../../learning/application/typed_recall_mode_adapter.dart';
import '../../learning/domain/answer_feedback.dart';
import '../../learning/domain/contrastive_explanation.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/hint_policy.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning_packs/domain/content_manifest.dart';
import 'adventure_mixed_review_prompt_catalog.dart';
import 'adventure_recovery_use_cases.dart';
import 'adventure_repair_policy.dart';

enum AdventureMixedReviewPhase {
  initializing,
  awaitingAnswer,
  awaitingFlashcardReveal,
  flashcardRevealed,
  savingFlashcard,
  savingEvidence,
  evidenceRetryRequired,
  savingSkip,
  skipRetryRequired,
  answered,
  completing,
  completionRetryRequired,
  completed,
  failed,
}

/// Narrow bridge to the Unified Lesson shell. The shell remains the owner of
/// controller state, feedback publication, active-time accounting and route
/// retirement while Adventure coordinates only the mixed-review cursor.
abstract interface class AdventureMixedReviewLessonHost {
  bool get acceptsOperations;

  Future<T> runRecoveryOperation<T>(Future<T> Function() operation);

  HintUsageSnapshot snapshotHintUsage();

  Future<QuizSession> initializeSession(
    QuizSession session, {
    PendingLearningSessionClose? recoveredClose,
  });

  Future<AnswerRecordResult> recordCapturedEvidence(
    PendingCurrentActivityEvidence pending, {
    required AnswerFeedbackContext feedbackContext,
    required LessonModeAdapter occurrenceAdapter,
  });

  void recordInteraction();

  void noteSkippedItem();

  void ownRecoveryClose(
    PendingLearningSessionClose close,
    Future<void> Function() ensureDurable,
  );

  Future<LearningSessionSummary> completeRecovery(
    PendingLearningSessionClose close,
  );
}

/// Drives one accepted mixed-review session over canonical Learning evidence.
/// Every learner occurrence is checkpointed before its evidence write, while
/// repair prompts and presentation remain transient and deterministic.
final class AdventureMixedReviewController extends ChangeNotifier {
  AdventureMixedReviewController({
    required this.recovery,
    required this.catalog,
    required this.registry,
    required this.host,
  });

  final AdventureRecoveryUseCases recovery;
  final AdventureMixedReviewPromptCatalog catalog;
  final LessonModeRegistry registry;
  final AdventureMixedReviewLessonHost host;

  AdventureMixedReviewPhase _phase = AdventureMixedReviewPhase.initializing;
  AdventureMixedReviewPrompt? _prompt;
  AdventureLearningItemRole? _role;
  AnswerFeedback? _feedback;
  String? _supportMessage;
  Object? _failure;
  LearningSessionSummary? _summary;
  PendingCurrentActivityEvidence? _pendingEvidence;
  AnswerFeedbackContext? _pendingFeedbackContext;
  PendingLearningSessionClose? _pendingClose;
  bool _initialized = false;
  bool _disposed = false;
  bool _flashcardRevealed = false;

  AdventureMixedReviewPhase get phase => _phase;
  AdventureMixedReviewPrompt? get prompt => _prompt;
  AdventureLearningItemRole? get role => _role;
  AnswerFeedback? get feedback => _feedback;
  String? get supportMessage => _supportMessage;
  Object? get failure => _failure;
  LearningSessionSummary? get summary => _summary;
  bool get isRepair => _role == AdventureLearningItemRole.repair;
  bool get hasRevealedFlashcard => _flashcardRevealed;
  bool get isBusy => switch (_phase) {
    AdventureMixedReviewPhase.initializing ||
    AdventureMixedReviewPhase.savingFlashcard ||
    AdventureMixedReviewPhase.savingEvidence ||
    AdventureMixedReviewPhase.savingSkip ||
    AdventureMixedReviewPhase.completing => true,
    _ => false,
  };
  bool get canSubmit =>
      _phase == AdventureMixedReviewPhase.awaitingAnswer &&
      host.acceptsOperations;
  bool get canSkip =>
      (_phase == AdventureMixedReviewPhase.awaitingAnswer ||
          _phase == AdventureMixedReviewPhase.awaitingFlashcardReveal) &&
      host.acceptsOperations;
  int get completedOriginalItems =>
      recovery.currentRun?.state.currentOriginalIndex ?? 0;
  int get originalItemCount => recovery.currentRun?.state.content.length ?? 0;
  int get occurrenceOrdinal =>
      recovery.currentRun?.state.nextOccurrenceOrdinal ?? 1;
  double get progress => originalItemCount == 0
      ? 0
      : (completedOriginalItems / originalItemCount).clamp(0, 1);

  Future<void> initialize() async {
    _requireNotDisposed();
    if (_initialized) return;
    _initialized = true;
    final run = _requireRun();
    try {
      if (run.state.phase == AdventureLearningCheckpointPhase.completed) {
        _summary = await recovery.loadCompletedSummary();
        _setPhase(AdventureMixedReviewPhase.completed);
        return;
      }
      await host.initializeSession(
        run.session,
        recoveredClose: run.pendingClose,
      );
      final refreshed = _requireRun();
      if (refreshed.state.phase == AdventureLearningCheckpointPhase.closing) {
        final close = refreshed.pendingClose;
        if (close == null) {
          throw StateError('Recovered mixed-review close is unavailable.');
        }
        _pendingClose = close;
        await _complete(close);
        return;
      }
      if (refreshed.state.phase ==
          AdventureLearningCheckpointPhase.pendingOccurrence) {
        _restorePendingOccurrence(refreshed);
        return;
      }
      await _selectNextPrompt();
    } catch (error) {
      _failure = error;
      if (_phase != AdventureMixedReviewPhase.completionRetryRequired) {
        _setPhase(AdventureMixedReviewPhase.failed);
      }
      rethrow;
    }
  }

  Future<void> submitChoice({
    required String option,
    required int responseTimeMs,
  }) async {
    _requireCanSubmit('submit a choice');
    final prompt = _requirePrompt();
    if (!prompt.options.contains(option)) {
      throw ArgumentError.value(option, 'option', 'is not a pinned option');
    }
    host.recordInteraction();
    final captured = _captureChoice(
      prompt: prompt,
      option: option,
      responseTimeMs: _responseTime(responseTimeMs),
    );
    await _checkpointAndCommit(captured);
  }

  Future<void> submitTyped({
    required String response,
    required int responseTimeMs,
  }) async {
    _requireCanSubmit('submit a typed response');
    final prompt = _requirePrompt();
    final adapter = _adapter<TypedRecallModeAdapter>(LessonMode.typedRecall);
    final pinned = prompt.typedRecallPrompt;
    if (prompt.mode != LessonMode.typedRecall || pinned == null) {
      throw StateError('This mixed-review prompt is not typed recall.');
    }
    host.recordInteraction();
    final captured = adapter.capture(
      evidence: recovery.evidence,
      ownerId: _requireRun().state.ownerId,
      sessionId: _requireRun().session.id,
      prompt: pinned,
      response: response,
      responseTimeMs: _responseTime(responseTimeMs),
      attemptNumber: occurrenceOrdinal,
      support: TypedRecallSupport(hint: host.snapshotHintUsage()),
    );
    await _checkpointAndCommit(
      _CapturedAdventureOccurrence(
        pending: captured.pending,
        feedbackContext: AnswerFeedbackContext(
          canonicalCorrectAnswer: pinned.canonicalAnswer,
          bookmarkIdentity: prompt.identity,
        ),
        adapter: adapter,
      ),
    );
  }

  Future<void> skip() async {
    _requireNotDisposed();
    if (!canSkip) throw StateError('Mixed-review item cannot be skipped now.');
    await _persistSkip();
  }

  Future<void> _persistSkip() async {
    final prompt = _requirePrompt();
    final role = _requireRole();
    host.recordInteraction();
    _failure = null;
    _setPhase(AdventureMixedReviewPhase.savingSkip);
    try {
      await host.runRecoveryOperation(() async {
        final run = _requireRun();
        if (run.state.phase == AdventureLearningCheckpointPhase.active) {
          await recovery.checkpointSkippedOccurrence(
            identity: prompt.identity,
            originalIndex: run.state.currentOriginalIndex,
            role: role,
            mode: prompt.mode,
            promptVariant: prompt.promptVariant,
          );
        }
        _acceptCheckpointOnly(AdventureAttemptOutcome.skipped);
        host.noteSkippedItem();
        _feedback = null;
        _supportMessage = role == AdventureLearningItemRole.repair
            ? 'เก็บคำนี้ไว้ทบทวนครั้งถัดไปแล้ว'
            : 'ข้ามข้อนี้แล้ว ความคืบหน้าเดิมยังอยู่ครบ';
        _setPhase(AdventureMixedReviewPhase.answered);
      });
    } catch (error) {
      _failure = error;
      _setPhase(AdventureMixedReviewPhase.skipRetryRequired);
      rethrow;
    }
  }

  void revealFlashcard() {
    _requireNotDisposed();
    if (_phase != AdventureMixedReviewPhase.awaitingFlashcardReveal ||
        !host.acceptsOperations) {
      throw StateError('Flashcard cannot be revealed now.');
    }
    host.recordInteraction();
    _flashcardRevealed = true;
    _setPhase(AdventureMixedReviewPhase.flashcardRevealed);
  }

  Future<void> continueAfterFlashcard() async {
    _requireNotDisposed();
    if (_phase != AdventureMixedReviewPhase.flashcardRevealed ||
        !host.acceptsOperations) {
      throw StateError('Flashcard exposure cannot continue now.');
    }
    _failure = null;
    _setPhase(AdventureMixedReviewPhase.savingFlashcard);
    try {
      await host.runRecoveryOperation(() async {
        final run = _requireRun();
        if (run.state.phase == AdventureLearningCheckpointPhase.active) {
          await recovery.checkpointFlashcardRepair(
            identity: _requirePrompt().identity,
            originalIndex: run.state.currentOriginalIndex,
          );
        }
        _acceptCheckpointOnly(AdventureAttemptOutcome.exposure);
        _feedback = null;
        _supportMessage = 'ทบทวนคำนี้แล้ว ไปต่อได้เลย';
        _setPhase(AdventureMixedReviewPhase.answered);
      });
    } catch (error) {
      _failure = error;
      _setPhase(AdventureMixedReviewPhase.flashcardRevealed);
      rethrow;
    }
  }

  Future<void> retryEvidence() async {
    _requireNotDisposed();
    if (_phase != AdventureMixedReviewPhase.evidenceRetryRequired ||
        !host.acceptsOperations) {
      throw StateError('Exact evidence retry is unavailable.');
    }
    final pending = _pendingEvidence ?? _requireRun().pendingEvidence;
    final context =
        _pendingFeedbackContext ?? _feedbackContext(_requirePrompt());
    if (pending == null) {
      throw StateError('Exact pending evidence is unavailable.');
    }
    final adapter = _occurrenceAdapter(_requirePrompt().mode);
    await _checkpointAndCommit(
      _CapturedAdventureOccurrence(
        pending: pending,
        feedbackContext: context,
        adapter: adapter,
      ),
    );
  }

  Future<void> retrySkip() async {
    _requireNotDisposed();
    if (_phase != AdventureMixedReviewPhase.skipRetryRequired ||
        !host.acceptsOperations) {
      throw StateError('Exact skip retry is unavailable.');
    }
    await _persistSkip();
  }

  Future<void> next() async {
    _requireNotDisposed();
    if (_phase != AdventureMixedReviewPhase.answered ||
        !host.acceptsOperations) {
      throw StateError('Mixed review cannot advance now.');
    }
    _feedback = null;
    _supportMessage = null;
    _failure = null;
    await _selectNextPrompt();
  }

  Future<void> retryCompletion() async {
    _requireNotDisposed();
    if (_phase != AdventureMixedReviewPhase.completionRetryRequired) {
      throw StateError('Exact completion retry is unavailable.');
    }
    final close = _pendingClose ?? _requireRun().pendingClose;
    if (close == null) {
      throw StateError('Exact pending session close is unavailable.');
    }
    await _complete(close);
  }

  Future<void> acknowledgeSummaryPresented() =>
      recovery.acknowledgeSummaryPresented();

  void noteInteraction() {
    if (!_disposed && host.acceptsOperations) host.recordInteraction();
  }

  _CapturedAdventureOccurrence _captureChoice({
    required AdventureMixedReviewPrompt prompt,
    required String option,
    required int responseTimeMs,
  }) {
    return switch (prompt.mode) {
      LessonMode.meaningQuiz => _captureMeaning(prompt, option, responseTimeMs),
      LessonMode.cloze => _captureCloze(prompt, option, responseTimeMs),
      LessonMode.definitionQuiz => _captureDefinition(
        prompt,
        option,
        responseTimeMs,
      ),
      _ => throw StateError('This mixed-review prompt requires typed input.'),
    };
  }

  _CapturedAdventureOccurrence _captureMeaning(
    AdventureMixedReviewPrompt prompt,
    String option,
    int responseTimeMs,
  ) {
    final adapter = _adapter<MeaningQuizModeAdapter>(LessonMode.meaningQuiz);
    final question = prompt.meaningQuizQuestion;
    if (question == null) {
      throw StateError('Pinned meaning question is unavailable.');
    }
    final identity = question.contrastiveIdentity;
    final checksum = question.evidenceChecksumSha256;
    final manifestChecksum = question.contrastiveChecksumSha256;
    if (identity == null || checksum == null || manifestChecksum == null) {
      throw StateError('Pinned meaning evidence identity is unavailable.');
    }
    final input = question.direction == MeaningQuizDirection.wordToMeaning
        ? CurrentActivityInput.meaningMultipleChoice
        : CurrentActivityInput.meaningToWordMultipleChoice;
    final rootAdapter = registry.resolve(_requireRun().state.mode)?.adapter;
    final hint = host.snapshotHintUsage();
    final recordedHintLevel = rootAdapter is HintSupportingLessonModeAdapter
        ? switch (hint.availability) {
            HintAvailability.available => hint.hintLevel ?? 2,
            HintAvailability.unavailable => 0,
            HintAvailability.unknown => 2,
          }
        : 0;
    final classification = HintEvidenceClassification(
      evidenceClass: recordedHintLevel > 0
          ? EvidenceClass.guidedPractice
          : EvidenceClass.recognition,
      hintLevel: recordedHintLevel,
    );
    final isCorrect = option == question.correctOption;
    final selectedOptionId = question.optionIdentity(option);
    final correctOptionId = question.optionIdentity(question.correctOption);
    final contrastive =
        !isCorrect && selectedOptionId != null && correctOptionId != null
        ? ContrastiveFeedbackContext(
            manifestIdentity: identity,
            manifestChecksumSha256: manifestChecksum,
            promptMode: prompt.promptVariant,
            evidenceContentRevision: contrastiveEvidenceContentRevision(
              promptMode: prompt.promptVariant,
              wordId: question.word.id,
              revision: identity.revision,
              checksumSha256: checksum,
            ),
            correctOptionId: correctOptionId,
            selectedDistractorId: selectedOptionId,
          )
        : null;
    final pending = recovery.evidence.capturePinnedMeaningRecognition(
      ownerId: _requireRun().state.ownerId,
      input: input,
      sessionId: _requireRun().session.id,
      wordId: question.word.id,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: occurrenceOrdinal,
      contentRevision: identity.revision,
      checksumSha256: checksum,
      classification: classification,
      contrastiveFeedback: contrastive,
    );
    return _CapturedAdventureOccurrence(
      pending: pending,
      feedbackContext: AnswerFeedbackContext(
        canonicalCorrectAnswer: question.correctOption,
      ),
      adapter: adapter,
    );
  }

  _CapturedAdventureOccurrence _captureCloze(
    AdventureMixedReviewPrompt prompt,
    String option,
    int responseTimeMs,
  ) {
    final adapter = _adapter<ClozeModeAdapter>(LessonMode.cloze);
    final question = prompt.clozeQuestion;
    if (question == null) {
      throw StateError('Pinned cloze question is unavailable.');
    }
    final classification = adapter.classifyResponse(
      inputMode: ClozeInputMode.selected,
      hint: host.snapshotHintUsage(),
    );
    final isCorrect = adapter.scoresCorrect(question, option);
    final selectedOptionId = question.optionIdentity(option);
    final correctOptionId = question.optionIdentity(question.correctAnswer);
    final contrastive =
        !isCorrect && selectedOptionId != null && correctOptionId != null
        ? ContrastiveFeedbackContext(
            manifestIdentity: question.identity,
            manifestChecksumSha256: question.manifestChecksumSha256,
            promptMode: 'clozeSelected',
            evidenceContentRevision: question.contentRevision,
            correctOptionId: correctOptionId,
            selectedDistractorId: selectedOptionId,
          )
        : null;
    final pending = recovery.evidence.captureCloze(
      ownerId: _requireRun().state.ownerId,
      sessionId: _requireRun().session.id,
      wordId: question.wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: occurrenceOrdinal,
      contentRevision: question.identity.revision,
      checksumSha256: question.checksumSha256,
      typed: false,
      classification: classification,
      contrastiveFeedback: contrastive,
    );
    return _CapturedAdventureOccurrence(
      pending: pending,
      feedbackContext: AnswerFeedbackContext(
        canonicalCorrectAnswer: question.correctAnswer,
        bookmarkIdentity: question.identity,
      ),
      adapter: adapter,
    );
  }

  _CapturedAdventureOccurrence _captureDefinition(
    AdventureMixedReviewPrompt prompt,
    String option,
    int responseTimeMs,
  ) {
    final adapter = _adapter<DefinitionQuizModeAdapter>(
      LessonMode.definitionQuiz,
    );
    final question = prompt.definitionQuizQuestion;
    if (question == null) {
      throw StateError('Pinned definition question is unavailable.');
    }
    final classification = adapter.classifyHintUsage(host.snapshotHintUsage());
    final isCorrect = adapter.scoresCorrect(question, option);
    final selectedOptionId = question.optionIdentity(option);
    final correctOptionId = question.optionIdentity(question.correctOption);
    final contrastive =
        !isCorrect && selectedOptionId != null && correctOptionId != null
        ? ContrastiveFeedbackContext(
            manifestIdentity: question.identity,
            manifestChecksumSha256: question.manifestChecksumSha256,
            promptMode: 'definitionChoice',
            evidenceContentRevision: question.contentRevision,
            correctOptionId: correctOptionId,
            selectedDistractorId: selectedOptionId,
          )
        : null;
    final pending = recovery.evidence.captureDefinitionRecognition(
      ownerId: _requireRun().state.ownerId,
      sessionId: _requireRun().session.id,
      wordId: question.wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: occurrenceOrdinal,
      contentRevision: question.identity.revision,
      checksumSha256: question.checksumSha256,
      classification: classification,
      contrastiveFeedback: contrastive,
    );
    return _CapturedAdventureOccurrence(
      pending: pending,
      feedbackContext: AnswerFeedbackContext(
        canonicalCorrectAnswer: question.correctOption,
        bookmarkIdentity: question.identity,
      ),
      adapter: adapter,
    );
  }

  Future<void> _checkpointAndCommit(
    _CapturedAdventureOccurrence captured,
  ) async {
    _failure = null;
    _pendingEvidence = captured.pending;
    _pendingFeedbackContext = captured.feedbackContext;
    _setPhase(AdventureMixedReviewPhase.savingEvidence);
    try {
      await host.runRecoveryOperation(() async {
        var run = _requireRun();
        if (run.state.phase == AdventureLearningCheckpointPhase.active) {
          await recovery.checkpointPendingEvidence(
            pending: captured.pending,
            originalIndex: run.state.currentOriginalIndex,
            role: _requireRole(),
            mode: _requirePrompt().mode,
          );
        }
        run = _requireRun();
        final occurrence = run.state.pendingOccurrence;
        if (occurrence == null ||
            occurrence.evidence?.sourceEvidenceId !=
                captured.pending.sourceEvidenceId) {
          throw StateError('Exact mixed-review occurrence is unavailable.');
        }
        final result = await host.recordCapturedEvidence(
          captured.pending,
          feedbackContext: captured.feedbackContext,
          occurrenceAdapter: captured.adapter,
        );
        final evidenceClass = captured.pending.evidenceContext?.evidenceClass;
        if (evidenceClass == null || !captured.pending.isCommitted) {
          throw StateError('Canonical evidence did not commit exactly once.');
        }
        final outcome = result.isCorrect
            ? evidenceClass == EvidenceClass.guidedPractice
                  ? AdventureAttemptOutcome.guided
                  : AdventureAttemptOutcome.correct
            : AdventureAttemptOutcome.incorrect;
        final decision = _acceptCommitted(
          result: result,
          evidenceClass: evidenceClass,
          outcome: outcome,
        );
        _feedback = AnswerFeedback.fromCommittedResult(
          result: result,
          context: captured.feedbackContext,
        );
        _supportMessage = _messageFor(decision, outcome, isRepair);
        _pendingEvidence = null;
        _pendingFeedbackContext = null;
        _setPhase(AdventureMixedReviewPhase.answered);
      });
    } catch (error) {
      _failure = error;
      _setPhase(AdventureMixedReviewPhase.evidenceRetryRequired);
      rethrow;
    }
  }

  AdventureRepairDecision _acceptCommitted({
    required AnswerRecordResult result,
    required EvidenceClass evidenceClass,
    required AdventureAttemptOutcome outcome,
  }) {
    final run = _requireRun();
    final role = _requireRole();
    return recovery.acceptPendingOccurrence(
      AdventureRepairAttempt(
        identity: _requirePrompt().identity,
        mode: _requirePrompt().mode,
        promptVariant: _requirePrompt().promptVariant,
        outcome: outcome,
        evidenceClass: evidenceClass,
        canonicalEvidenceCommitted: true,
        sourceEvidenceId: _pendingEvidence!.sourceEvidenceId,
        isRepair: role == AdventureLearningItemRole.repair,
      ),
      nextOriginalIndex:
          run.state.currentOriginalIndex +
          (role == AdventureLearningItemRole.original ? 1 : 0),
      remainingOriginalItems:
          run.state.content.length -
          run.state.currentOriginalIndex -
          (role == AdventureLearningItemRole.original ? 1 : 0),
    );
  }

  void _acceptCheckpointOnly(AdventureAttemptOutcome outcome) {
    final run = _requireRun();
    final prompt = _requirePrompt();
    final role = _requireRole();
    recovery.acceptPendingOccurrence(
      AdventureRepairAttempt(
        identity: prompt.identity,
        mode: prompt.mode,
        promptVariant: prompt.promptVariant,
        outcome: outcome,
        evidenceClass: null,
        canonicalEvidenceCommitted: false,
        sourceEvidenceId: null,
        isRepair: role == AdventureLearningItemRole.repair,
      ),
      nextOriginalIndex:
          run.state.currentOriginalIndex +
          (role == AdventureLearningItemRole.original ? 1 : 0),
      remainingOriginalItems:
          run.state.content.length -
          run.state.currentOriginalIndex -
          (role == AdventureLearningItemRole.original ? 1 : 0),
    );
  }

  Future<void> _selectNextPrompt() async {
    _setPhase(AdventureMixedReviewPhase.initializing);
    final run = _requireRun();
    final due = run.repairPolicy.dueRepairs;
    if (due.isNotEmpty) {
      final ticket = due.first;
      final mode = ticket.repairMode;
      final variant = ticket.repairPromptVariant;
      if (mode == null || variant == null) {
        throw StateError('Due repair has no exact prompt.');
      }
      final prompt = catalog.resolve(
        identity: ticket.identity,
        mode: mode,
        promptVariant: variant,
      );
      _showPrompt(prompt, AdventureLearningItemRole.repair);
      return;
    }
    if (run.state.currentOriginalIndex < run.state.content.length) {
      final identity = run.state.content[run.state.currentOriginalIndex];
      final prompt = _resolveOriginal(identity, run.state.mode);
      _showPrompt(prompt, AdventureLearningItemRole.original);
      return;
    }
    final close = recovery.learning.captureSessionClose(
      sessionId: run.session.id,
      ownerId: run.state.ownerId,
    );
    _pendingClose = close;
    await _complete(close);
  }

  AdventureMixedReviewPrompt _resolveOriginal(
    ContentIdentity identity,
    LessonMode mode,
  ) {
    final variants = switch (mode) {
      LessonMode.typedRecall => const <String>['typedRecall'],
      LessonMode.meaningQuiz => const <String>['meaningChoice', 'wordChoice'],
      LessonMode.cloze => const <String>['clozeSelected'],
      LessonMode.definitionQuiz => const <String>['definitionChoice'],
      _ => const <String>[],
    };
    for (final variant in variants) {
      if (catalog.supports(identity, mode, variant)) {
        return catalog.resolve(
          identity: identity,
          mode: mode,
          promptVariant: variant,
        );
      }
    }
    throw StateError('Exact original mixed-review prompt is unavailable.');
  }

  void _restorePendingOccurrence(AdventureLearningRun run) {
    final occurrence = run.state.pendingOccurrence;
    if (occurrence == null) {
      throw StateError('Pending mixed-review occurrence is unavailable.');
    }
    final prompt = catalog.resolve(
      identity: occurrence.identity,
      mode: occurrence.mode,
      promptVariant: occurrence.promptVariant,
    );
    _prompt = prompt;
    _flashcardRevealed = false;
    _role = occurrence.role;
    _feedback = null;
    _supportMessage = null;
    _failure = null;
    if (occurrence.evidence != null) {
      _pendingEvidence = run.pendingEvidence;
      _pendingFeedbackContext = _feedbackContext(prompt);
      _setPhase(AdventureMixedReviewPhase.evidenceRetryRequired);
      return;
    }
    if (occurrence.checkpointOnlyOutcome == AdventureAttemptOutcome.exposure) {
      _setPhase(AdventureMixedReviewPhase.awaitingFlashcardReveal);
      return;
    }
    if (occurrence.checkpointOnlyOutcome == AdventureAttemptOutcome.skipped) {
      _setPhase(AdventureMixedReviewPhase.skipRetryRequired);
      return;
    }
    throw StateError('Pending checkpoint-only completion intent is invalid.');
  }

  void _showPrompt(
    AdventureMixedReviewPrompt prompt,
    AdventureLearningItemRole role,
  ) {
    _prompt = prompt;
    _flashcardRevealed = false;
    _role = role;
    _feedback = null;
    _supportMessage = null;
    _failure = null;
    _pendingEvidence = null;
    _pendingFeedbackContext = null;
    _setPhase(
      prompt.mode == LessonMode.flashcard
          ? AdventureMixedReviewPhase.awaitingFlashcardReveal
          : AdventureMixedReviewPhase.awaitingAnswer,
    );
  }

  Future<void> _complete(PendingLearningSessionClose close) async {
    _failure = null;
    _pendingClose = close;
    _setPhase(AdventureMixedReviewPhase.completing);
    try {
      await host.runRecoveryOperation(() async {
        host.ownRecoveryClose(
          close,
          () => recovery.checkpointSessionClose(close),
        );
        await recovery.checkpointSessionClose(close);
        final summary = await host.completeRecovery(close);
        await recovery.acknowledgeSessionClosed(close: close, summary: summary);
        _summary = summary;
        _pendingClose = null;
        _setPhase(AdventureMixedReviewPhase.completed);
      });
    } catch (error) {
      _failure = error;
      _setPhase(AdventureMixedReviewPhase.completionRetryRequired);
      rethrow;
    }
  }

  AnswerFeedbackContext _feedbackContext(AdventureMixedReviewPrompt prompt) =>
      AnswerFeedbackContext(
        canonicalCorrectAnswer: prompt.answer ?? '',
        bookmarkIdentity: prompt.mode == LessonMode.meaningQuiz
            ? null
            : prompt.identity,
      );

  LessonModeAdapter _occurrenceAdapter(LessonMode mode) => switch (mode) {
    LessonMode.typedRecall => _adapter<TypedRecallModeAdapter>(mode),
    LessonMode.meaningQuiz => _adapter<MeaningQuizModeAdapter>(mode),
    LessonMode.cloze => _adapter<ClozeModeAdapter>(mode),
    LessonMode.definitionQuiz => _adapter<DefinitionQuizModeAdapter>(mode),
    _ => throw StateError('Unsupported evidence-bearing repair mode.'),
  };

  T _adapter<T extends LessonModeAdapter>(LessonMode mode) {
    final adapter = registry.resolve(mode)?.adapter;
    if (adapter is! T) {
      throw StateError('Canonical ${mode.name} adapter is unavailable.');
    }
    return adapter;
  }

  AdventureLearningRun _requireRun() {
    final run = recovery.currentRun;
    if (run == null) throw StateError('No mixed-review run is accepted.');
    return run;
  }

  AdventureMixedReviewPrompt _requirePrompt() {
    final prompt = _prompt;
    if (prompt == null) throw StateError('No mixed-review prompt is active.');
    return prompt;
  }

  AdventureLearningItemRole _requireRole() {
    final role = _role;
    if (role == null) throw StateError('No mixed-review occurrence is active.');
    return role;
  }

  void _requireCanSubmit(String operation) {
    _requireNotDisposed();
    if (!canSubmit) throw StateError('Cannot $operation now.');
  }

  void _requireNotDisposed() {
    if (_disposed) throw StateError('Mixed-review controller is disposed.');
  }

  static int _responseTime(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'responseTimeMs', 'must be nonnegative');
    }
    return value;
  }

  static String? _messageFor(
    AdventureRepairDecision decision,
    AdventureAttemptOutcome outcome,
    bool wasRepair,
  ) {
    if (wasRepair &&
        decision.disposition ==
            AdventureRepairDisposition.deferredToCanonicalReview) {
      return 'เก็บคำนี้ไว้ทบทวนครั้งถัดไปแล้ว';
    }
    if (outcome != AdventureAttemptOutcome.incorrect) return null;
    const base =
        'คำนี้ยังไม่ผ่านในครั้งนี้ เดี๋ยวระบบจะช่วยทบทวนอีกครั้งโดยไม่ลดความคืบหน้าเดิม';
    return switch (decision.disposition) {
      AdventureRepairDisposition.scheduled =>
        '$base\nจะกลับมาอีกครั้งหลังทำข้ออื่นสักครู่',
      AdventureRepairDisposition.deferredToCanonicalReview =>
        '$base\nเก็บคำนี้ไว้ทบทวนครั้งถัดไปแล้ว',
      _ => base,
    };
  }

  void _setPhase(AdventureMixedReviewPhase value) {
    _phase = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _CapturedAdventureOccurrence {
  const _CapturedAdventureOccurrence({
    required this.pending,
    required this.feedbackContext,
    required this.adapter,
  });

  final PendingCurrentActivityEvidence pending;
  final AnswerFeedbackContext feedbackContext;
  final LessonModeAdapter adapter;
}
