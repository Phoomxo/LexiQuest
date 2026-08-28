import 'package:flutter/foundation.dart';

import '../../vocabulary/application/vocabulary_use_cases.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../domain/evidence_context.dart';
import '../domain/answer_feedback.dart';
import '../domain/contrastive_explanation.dart';
import '../domain/learning_models.dart';
import '../domain/lexical_prompt_artifact_identity.dart';
import '../domain/lesson_mode.dart';
import '../domain/session_configuration.dart';
import 'current_activity_evidence.dart';
import 'learning_use_cases.dart';

typedef MeaningQuizSessionCompleter =
    Future<LearningSessionSummary> Function(PendingLearningSessionClose close);
typedef MeaningQuizInteractionRecorder = void Function();
typedef MeaningQuizOperationAcceptance = bool Function();
typedef MeaningQuizEvidenceOperation =
    Future<AnswerRecordResult> Function(
      Future<AnswerRecordResult> Function() operation,
    );

enum MeaningQuizDirection { wordToMeaning, meaningToWord }

final class MeaningQuizQuestion {
  const MeaningQuizQuestion({
    required this.word,
    required this.direction,
    required this.prompt,
    required this.correctOption,
    required this.options,
    this.optionIdentities = const <String, String>{},
    this.contrastiveIdentity,
    this.contrastiveChecksumSha256,
    this.evidenceChecksumSha256,
  });

  final QuizWord word;
  final MeaningQuizDirection direction;
  final String prompt;
  final String correctOption;
  final List<String> options;
  final Map<String, String> optionIdentities;
  final ContentIdentity? contrastiveIdentity;
  final String? contrastiveChecksumSha256;
  final String? evidenceChecksumSha256;

  String? optionIdentity(String option) => optionIdentities[option];
}

enum MeaningQuizReviewPhase {
  awaitingAnswer,
  savingEvidence,
  evidenceRetryRequired,
  answered,
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
  }) {
    final lexicalById = <String, VocabularyWord>{
      for (final word in lexicalWords) word.id: word,
    };
    final words = session.questions
        .map((question) => question.word)
        .toList(growable: false);
    return List<MeaningQuizQuestion>.unmodifiable(
      words.indexed.map((entry) {
        final index = entry.$1;
        final word = entry.$2;
        final questionDirection = switch (direction) {
          SessionDirection.forward => MeaningQuizDirection.wordToMeaning,
          SessionDirection.reverse => MeaningQuizDirection.meaningToWord,
          SessionDirection.mixed =>
            index.isEven
                ? MeaningQuizDirection.wordToMeaning
                : MeaningQuizDirection.meaningToWord,
        };
        final correctOption =
            questionDirection == MeaningQuizDirection.wordToMeaning
            ? word.meaning
            : word.spelling;
        final pool = _equivalentDistinctDistractors(
          words: words,
          word: word,
          direction: questionDirection,
        );
        final lexical = lexicalById[word.id];
        final rich = lexical?.richMetadata;
        final promptMode =
            questionDirection == MeaningQuizDirection.wordToMeaning
            ? 'meaningChoice'
            : 'wordChoice';
        final artifactIdentity = lexical == null
            ? null
            : LexicalPromptArtifactResolver.resolveForAdapter(
                promptMode: promptMode,
                wordId: word.id,
                coreRevision: word.contentRevision ?? 0,
                coreChecksumSha256: word.contentChecksumSha256,
                verifiedArtifactRevision: rich?.verifiedContentRevision,
                verifiedArtifactChecksumSha256:
                    rich?.verifiedArtifactChecksumSha256,
              );
        final hasVerifiedLexicalMetadata =
            lexical != null &&
            lexical.isGlobal &&
            lexical.contentProvenance == ContentProvenance.packaged &&
            lexical.contentReviewState == ContentReviewState.approved &&
            lexical.contentPublicationState ==
                ContentPublicationState.published &&
            lexical.contentRevision == word.contentRevision &&
            rich?.verifiedContentRevision == lexical.contentRevision &&
            artifactIdentity != null;
        return MeaningQuizQuestion(
          word: word,
          direction: questionDirection,
          prompt: questionDirection == MeaningQuizDirection.wordToMeaning
              ? word.spelling
              : word.meaning,
          correctOption: correctOption,
          options: _pinOptions(
            correctOption: correctOption,
            candidates: pool.map((candidate) => candidate.label).toList(),
            seed: _stableSeed('${word.id}:${questionDirection.name}'),
          ),
          optionIdentities: <String, String>{
            correctOption: word.id,
            for (final candidate in pool) candidate.label: candidate.wordId,
          },
          contrastiveIdentity: hasVerifiedLexicalMetadata
              ? ContentIdentity(
                  type: ContentType.lexicalMetadata,
                  id: word.id,
                  revision: lexical.contentRevision,
                )
              : null,
          contrastiveChecksumSha256: hasVerifiedLexicalMetadata
              ? artifactIdentity.verifiedArtifactChecksumSha256
              : null,
          evidenceChecksumSha256: hasVerifiedLexicalMetadata
              ? artifactIdentity.checksumSha256
              : null,
        );
      }),
    );
  }

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final context = support.evidenceContext;
    if ((response.promptMode != 'meaningChoice' &&
            response.promptMode != 'wordChoice') ||
        context.evidenceClass != EvidenceClass.recognition ||
        context.hintLevel != 0) {
      throw StateError(
        'Meaning quiz answers must remain unassisted recognition evidence.',
      );
    }
    return context;
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('MeaningQuizReviewController owns pinned item selection.'),
  );
}

List<({String wordId, String label})> _equivalentDistinctDistractors({
  required List<QuizWord> words,
  required QuizWord word,
  required MeaningQuizDirection direction,
}) {
  final promptKey = direction == MeaningQuizDirection.wordToMeaning
      ? _spellingKey(word)
      : _meaningKey(word);
  final answerKey = direction == MeaningQuizDirection.wordToMeaning
      ? _meaningKey(word)
      : _spellingKey(word);
  final byAnswerKey = <String, ({String wordId, String label})>{};
  for (final candidate in words) {
    final candidatePromptKey = direction == MeaningQuizDirection.wordToMeaning
        ? _spellingKey(candidate)
        : _meaningKey(candidate);
    final candidateAnswerKey = direction == MeaningQuizDirection.wordToMeaning
        ? _meaningKey(candidate)
        : _spellingKey(candidate);
    if (candidatePromptKey == promptKey || candidateAnswerKey == answerKey) {
      continue;
    }
    byAnswerKey.putIfAbsent(
      candidateAnswerKey,
      () => (
        wordId: candidate.id,
        label: direction == MeaningQuizDirection.wordToMeaning
            ? candidate.meaning
            : candidate.spelling,
      ),
    );
  }
  final keys = byAnswerKey.keys.toList()..sort();
  return keys.map((key) => byAnswerKey[key]!).toList(growable: false);
}

String _spellingKey(QuizWord word) =>
    normalizeVocabularyText(word.normalizedSpelling ?? word.spelling);

String _meaningKey(QuizWord word) =>
    normalizeVocabularyText(word.normalizedMeaning ?? word.meaning);

List<String> _pinOptions({
  required String correctOption,
  required List<String> candidates,
  required int seed,
}) {
  final distractors = candidates
      .where((candidate) => candidate != correctOption)
      .toList(growable: false);
  final rotatedDistractors = distractors.isEmpty
      ? const <String>[]
      : <String>[
          ...distractors.skip(seed % distractors.length),
          ...distractors.take(seed % distractors.length),
        ];
  final options = <String>[correctOption, ...rotatedDistractors.take(3)];
  final offset = seed % options.length;
  return List<String>.unmodifiable(<String>[
    ...options.skip(offset),
    ...options.take(offset),
  ]);
}

int _stableSeed(String value) => value.codeUnits.fold<int>(
  17,
  (hash, unit) => ((hash * 31) + unit) & 0x7fffffff,
);

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

  int get index => _index;
  MeaningQuizReviewPhase get phase => _phase;
  MeaningQuizQuestion get currentQuestion => questions[_index];
  AnswerFeedback? get feedback => _feedback;
  String? get selectedOption => _selectedOption;
  bool get isAnswered => _phase == MeaningQuizReviewPhase.answered;
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
          _phase != MeaningQuizReviewPhase.answered);

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
    if (pending == null || !pending.requiresRetry) {
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
      final result = await _runEvidenceOperation(
        () => retry ? pending.retry() : pending.record(),
      );
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
      if (pending.requiresRetry) {
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
    _requirePhase(MeaningQuizReviewPhase.answered, 'advance');
    if (_index < questions.length - 1) {
      _index += 1;
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
    final close = _pendingClose ??= _learning.captureSessionClose(
      sessionId: session.id,
      ownerId: session.ownerId,
    );
    _setPhase(MeaningQuizReviewPhase.completing);
    try {
      final summary = await _completeSession(close);
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
