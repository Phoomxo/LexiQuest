import 'package:flutter/foundation.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../../vocabulary/application/vocabulary_use_cases.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../domain/answer_feedback.dart';
import '../domain/contrastive_explanation.dart';
import '../domain/evidence_context.dart';
import '../domain/hint_policy.dart';
import '../domain/learning_models.dart';
import '../domain/lesson_mode.dart';
import '../domain/session_configuration.dart';
import 'current_activity_evidence.dart';
import 'learning_use_cases.dart';

typedef ClozeSessionCompleter =
    Future<LearningSessionSummary> Function(PendingLearningSessionClose close);
typedef ClozeInteractionRecorder = void Function();
typedef ClozeOperationAcceptance = bool Function();
typedef ClozeEvidenceOperation =
    Future<AnswerRecordResult> Function(
      Future<AnswerRecordResult> Function() operation,
    );
typedef ClozeHintUsage = HintUsageSnapshot Function();
typedef ClozeHintReset = void Function();

enum ClozeInputMode { selected, typed }

enum ClozeReviewPhase {
  awaitingAnswer,
  skipped,
  savingEvidence,
  evidenceRetryRequired,
  answered,
  completing,
  completionRetryRequired,
  completed,
}

enum ClozeSkipReason {
  missingExample,
  unreviewedContent,
  staleContent,
  ambiguousExample,
}

final class ClozeQuestion {
  const ClozeQuestion({
    required this.wordId,
    required this.identity,
    required this.checksumSha256,
    required this.prompt,
    required this.correctAnswer,
    required this.options,
    this.optionIdentities = const <String, String>{},
  });

  final String wordId;
  final ContentIdentity identity;
  final String checksumSha256;
  final String prompt;
  final String correctAnswer;
  final List<String> options;
  final Map<String, String> optionIdentities;

  String? optionIdentity(String option) => optionIdentities[option];

  String get contentRevision =>
      'lexical-cloze:$wordId@${identity.revision}:$checksumSha256';
}

final class ClozeItem {
  const ClozeItem.question(this.question) : skipReason = null;

  const ClozeItem.skipped(this.skipReason) : question = null;

  final ClozeQuestion? question;
  final ClozeSkipReason? skipReason;

  String get semanticAnnouncement => switch (skipReason) {
    ClozeSkipReason.missingExample =>
      'Skipped. A reviewed cloze example is unavailable.',
    ClozeSkipReason.unreviewedContent =>
      'Skipped. The cloze example has not been approved.',
    ClozeSkipReason.staleContent =>
      'Skipped. The cloze example no longer matches this session.',
    ClozeSkipReason.ambiguousExample =>
      'Skipped. The reviewed example cannot make one unambiguous blank.',
    null => '',
  };
}

final class _PinnedClozeCandidate {
  const _PinnedClozeCandidate({
    required this.word,
    required this.lexical,
    required this.prompt,
    required this.checksumSha256,
  });

  final QuizWord word;
  final VocabularyWord lexical;
  final String prompt;
  final String checksumSha256;
}

/// Typed production boundary for reviewed, pinned cloze evidence.
final class ClozeModeAdapter
    implements
        FocusTimerSupportingLessonModeAdapter,
        HintSupportingLessonModeAdapter,
        SessionConfigurableLessonModeAdapter {
  const ClozeModeAdapter();

  @override
  LessonMode get mode => LessonMode.cloze;

  @override
  SessionConfigurationCapabilities get sessionConfigurationCapabilities =>
      const SessionConfigurationCapabilities(
        minimumItemCount: 1,
        maximumItemCount: 100,
        defaultItemCount: 10,
        directions: <SessionDirection>{SessionDirection.forward},
        difficulties: <SessionDifficulty>{SessionDifficulty.standard},
        maximumHintBudget: 2,
        supportsTimed: true,
        supportsUntimedAlternative: true,
        supportsPackSelection: false,
      );

  @override
  HintPolicy get hintPolicy => HintPolicy.staged(
    strategy: 'Use the words around the blank to identify its role.',
    context: 'Recall the exact reviewed vocabulary word for this sentence.',
  );

  HintEvidenceClassification classifyResponse({
    required ClozeInputMode inputMode,
    required HintUsageSnapshot hint,
  }) {
    final level = switch (hint.availability) {
      HintAvailability.available => hint.hintLevel ?? 2,
      HintAvailability.unavailable => 0,
      HintAvailability.unknown => 2,
    };
    return HintEvidenceClassification(
      evidenceClass: level > 0
          ? EvidenceClass.guidedPractice
          : inputMode == ClozeInputMode.selected
          ? EvidenceClass.recognition
          : EvidenceClass.independentRecall,
      hintLevel: level,
    );
  }

  bool scoresCorrect(ClozeQuestion question, String answer) =>
      normalizeVocabularyText(answer) ==
      normalizeVocabularyText(question.correctAnswer);

  /// Read-only readiness uses the same reviewed-artifact contract as pinning.
  bool hasDeliverableReviewedExample(Iterable<VocabularyWord> words) =>
      words.any((word) {
        final checksum = word.contentChecksumSha256;
        final artifactChecksum =
            word.richMetadata?.verifiedArtifactChecksumSha256;
        if (!_isReviewedPackagedWord(word) ||
            word.contentRevision <= 0 ||
            checksum == null ||
            !_isCanonicalSha256(checksum) ||
            artifactChecksum == null ||
            !_isCanonicalSha256(artifactChecksum)) {
          return false;
        }
        return word.richMetadata!.examples.any(
          (example) => _blankOneOccurrence(example, word.spelling) != null,
        );
      });

  List<ClozeItem> pinItems({
    required QuizSession session,
    required Iterable<VocabularyWord> lexicalWords,
  }) {
    final lexicalById = <String, VocabularyWord?>{};
    for (final word in lexicalWords) {
      lexicalById.update(word.id, (_) => null, ifAbsent: () => word);
    }
    final candidates = <String, _PinnedClozeCandidate>{};
    final skips = <String, ClozeSkipReason>{};
    for (final question in session.questions) {
      final word = question.word;
      final lexical = lexicalById[word.id];
      if (lexical == null) {
        skips[word.id] = ClozeSkipReason.missingExample;
        continue;
      }
      if (!_isReviewedPackagedWord(lexical)) {
        skips[word.id] = ClozeSkipReason.unreviewedContent;
        continue;
      }
      final pinnedRevision = word.contentRevision;
      final pinnedChecksum = word.contentChecksumSha256;
      if (pinnedRevision == null ||
          pinnedRevision <= 0 ||
          pinnedChecksum == null ||
          !_isCanonicalSha256(pinnedChecksum) ||
          pinnedRevision != lexical.contentRevision ||
          pinnedChecksum != lexical.contentChecksumSha256) {
        skips[word.id] = ClozeSkipReason.staleContent;
        continue;
      }
      final artifactChecksum =
          lexical.richMetadata?.verifiedArtifactChecksumSha256;
      if (artifactChecksum == null || !_isCanonicalSha256(artifactChecksum)) {
        skips[word.id] = ClozeSkipReason.missingExample;
        continue;
      }
      String? prompt;
      var sawExample = false;
      for (final example in lexical.richMetadata!.examples) {
        sawExample = true;
        prompt = _blankOneOccurrence(example, lexical.spelling);
        if (prompt != null) break;
      }
      if (prompt == null) {
        skips[word.id] = sawExample
            ? ClozeSkipReason.ambiguousExample
            : ClozeSkipReason.missingExample;
        continue;
      }
      candidates[word.id] = _PinnedClozeCandidate(
        word: word,
        lexical: lexical,
        prompt: prompt,
        checksumSha256: artifactChecksum,
      );
    }

    return List<ClozeItem>.unmodifiable(
      session.questions.map((sessionQuestion) {
        final candidate = candidates[sessionQuestion.word.id];
        if (candidate == null) {
          return ClozeItem.skipped(
            skips[sessionQuestion.word.id] ?? ClozeSkipReason.missingExample,
          );
        }
        final correct = _canonicalDisplay(candidate.lexical.spelling);
        final answerKey = normalizeVocabularyText(correct);
        final byKey = <String, String>{};
        final identityByKey = <String, String>{};
        for (final distractor in candidates.values) {
          if (distractor.word.id == candidate.word.id) continue;
          final display = _canonicalDisplay(distractor.lexical.spelling);
          final key = normalizeVocabularyText(display);
          if (key == answerKey) continue;
          if (!byKey.containsKey(key)) {
            byKey[key] = display;
            identityByKey[key] = distractor.word.id;
          }
        }
        final keys = byKey.keys.toList()..sort();
        return ClozeItem.question(
          ClozeQuestion(
            wordId: candidate.word.id,
            identity: ContentIdentity(
              type: ContentType.lexicalMetadata,
              id: candidate.word.id,
              revision: candidate.lexical.contentRevision,
            ),
            checksumSha256: candidate.checksumSha256,
            prompt: candidate.prompt,
            correctAnswer: correct,
            options: _pinOptions(
              correctOption: correct,
              candidates: keys.map((key) => byKey[key]!).toList(),
              seed: _stableSeed(
                '${candidate.word.id}:${candidate.lexical.contentRevision}:'
                '${candidate.checksumSha256}',
              ),
            ),
            optionIdentities: <String, String>{
              correct: candidate.word.id,
              for (final key in keys) byKey[key]!: identityByKey[key]!,
            },
          ),
        );
      }),
    );
  }

  ClozeReviewController createReview({
    required QuizSession session,
    required Iterable<VocabularyWord> lexicalWords,
    required LearningUseCases learning,
    required CurrentActivityEvidenceAdapter evidence,
    required ClozeHintUsage hintUsage,
    ClozeHintReset? resetHintsAfterCommit,
    ClozeSessionCompleter? completeSession,
    ClozeInteractionRecorder? recordInteraction,
    ClozeOperationAcceptance? acceptsOperation,
    ClozeEvidenceOperation? runEvidenceOperation,
  }) {
    if (session.isEmpty) {
      throw ArgumentError.value(session, 'session', 'must contain an item');
    }
    if (!identical(evidence.learning, learning)) {
      throw ArgumentError(
        'Cloze evidence must use the session LearningUseCases authority.',
      );
    }
    return ClozeReviewController._(
      session: session,
      items: pinItems(session: session, lexicalWords: lexicalWords),
      learning: learning,
      evidence: evidence,
      hintUsage: hintUsage,
      resetHintsAfterCommit: resetHintsAfterCommit ?? () {},
      completeSession:
          completeSession ??
          (close) => close.requiresRetry ? close.retry() : close.finish(),
      recordInteraction: recordInteraction ?? () {},
      acceptsOperation: acceptsOperation ?? () => true,
      runEvidenceOperation: runEvidenceOperation ?? (operation) => operation(),
      scoreAnswer: scoresCorrect,
      classifyResponse: classifyResponse,
    );
  }

  bool _isCanonicalSha256(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  bool _isReviewedPackagedWord(VocabularyWord word) =>
      word.isGlobal &&
      word.contentProvenance == ContentProvenance.packaged &&
      word.contentReviewState == ContentReviewState.approved &&
      word.contentPublicationState == ContentPublicationState.published;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final context = support.evidenceContext;
    final selected =
        response.promptMode == 'clozeSelected' &&
        ((context.hintLevel == 0 &&
                context.evidenceClass == EvidenceClass.recognition) ||
            (context.hintLevel > 0 &&
                context.evidenceClass == EvidenceClass.guidedPractice));
    final typed =
        response.promptMode == 'clozeTyped' &&
        ((context.hintLevel == 0 &&
                context.evidenceClass == EvidenceClass.independentRecall) ||
            (context.hintLevel > 0 &&
                context.evidenceClass == EvidenceClass.guidedPractice));
    if ((!selected && !typed) ||
        context.skillId != 'cloze-context' ||
        !_isPinnedContentRevision(context.contentRevision, response.wordId)) {
      throw StateError('Cloze answers require pinned input-specific evidence.');
    }
    return context;
  }

  bool _isPinnedContentRevision(String value, String wordId) {
    final prefix = 'lexical-cloze:$wordId@';
    return value.startsWith(prefix) &&
        RegExp(
          r'^[1-9][0-9]*:[0-9a-f]{64}$',
        ).hasMatch(value.substring(prefix.length));
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('Cloze review owns pinned item selection.'),
  );
}

final class ClozeReviewController extends ChangeNotifier {
  ClozeReviewController._({
    required this.session,
    required List<ClozeItem> items,
    required this._learning,
    required this._evidence,
    required this._hintUsage,
    required this._resetHintsAfterCommit,
    required this._completeSession,
    required this._recordInteraction,
    required this._acceptsOperation,
    required this._runEvidenceOperation,
    required this._scoreAnswer,
    required this._classifyResponse,
  }) : items = List<ClozeItem>.unmodifiable(items),
       _phase = items.first.question == null
           ? ClozeReviewPhase.skipped
           : ClozeReviewPhase.awaitingAnswer;

  final QuizSession session;
  final List<ClozeItem> items;
  final LearningUseCases _learning;
  final CurrentActivityEvidenceAdapter _evidence;
  final ClozeHintUsage _hintUsage;
  final ClozeHintReset _resetHintsAfterCommit;
  final ClozeSessionCompleter _completeSession;
  final ClozeInteractionRecorder _recordInteraction;
  final ClozeOperationAcceptance _acceptsOperation;
  final ClozeEvidenceOperation _runEvidenceOperation;
  final bool Function(ClozeQuestion, String) _scoreAnswer;
  final HintEvidenceClassification Function({
    required ClozeInputMode inputMode,
    required HintUsageSnapshot hint,
  })
  _classifyResponse;

  var _index = 0;
  ClozeReviewPhase _phase;
  PendingCurrentActivityEvidence? _pendingEvidence;
  FrozenAnswerFeedbackContext? _pendingFeedbackContext;
  PendingLearningSessionClose? _pendingClose;
  AnswerFeedback? _feedback;
  String? _submittedAnswer;
  ClozeInputMode? _submittedMode;
  bool _disposed = false;

  int get index => _index;
  ClozeItem get currentItem => items[_index];
  ClozeReviewPhase get phase => _phase;
  AnswerFeedback? get feedback => _feedback;
  String? get submittedAnswer => _submittedAnswer;
  ClozeInputMode? get submittedMode => _submittedMode;
  bool get isAnswered => _phase == ClozeReviewPhase.answered;
  bool get isSkipped => _phase == ClozeReviewPhase.skipped;
  bool get isSaving =>
      _phase == ClozeReviewPhase.savingEvidence ||
      _phase == ClozeReviewPhase.completing;
  bool get requiresRetry =>
      _phase == ClozeReviewPhase.evidenceRetryRequired ||
      _phase == ClozeReviewPhase.completionRetryRequired;
  bool get persistenceLocked =>
      isSaving ||
      requiresRetry ||
      _pendingEvidence != null ||
      _pendingClose != null;
  bool get actionLocked =>
      !_acceptsOperation() ||
      (_phase != ClozeReviewPhase.awaitingAnswer &&
          _phase != ClozeReviewPhase.answered &&
          _phase != ClozeReviewPhase.skipped);

  Future<AnswerRecordResult> answerSelected({
    required String option,
    required int responseTimeMs,
  }) {
    final question = _requireAnswer(ClozeInputMode.selected, responseTimeMs);
    if (!question.options.contains(option)) {
      throw ArgumentError.value(option, 'option', 'is not a pinned option');
    }
    return _captureAndCommit(
      question: question,
      answer: option,
      inputMode: ClozeInputMode.selected,
      responseTimeMs: responseTimeMs,
    );
  }

  Future<AnswerRecordResult> answerTyped({
    required String text,
    required int responseTimeMs,
  }) {
    final question = _requireAnswer(ClozeInputMode.typed, responseTimeMs);
    final normalized = normalizeVocabularyText(text);
    if (normalized.isEmpty || text.runes.length > 160) {
      throw ArgumentError.value(text, 'text', 'must be a bounded answer');
    }
    return _captureAndCommit(
      question: question,
      answer: text,
      inputMode: ClozeInputMode.typed,
      responseTimeMs: responseTimeMs,
    );
  }

  ClozeQuestion _requireAnswer(ClozeInputMode mode, int responseTimeMs) {
    _requireOperationAccepted();
    _requirePhase(ClozeReviewPhase.awaitingAnswer, 'answer');
    if (responseTimeMs < 0) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must not be negative',
      );
    }
    final question = currentItem.question;
    if (question == null) {
      throw StateError('Cannot submit ${mode.name} input for a skipped item.');
    }
    return question;
  }

  Future<AnswerRecordResult> _captureAndCommit({
    required ClozeQuestion question,
    required String answer,
    required ClozeInputMode inputMode,
    required int responseTimeMs,
  }) {
    final feedbackContext = AnswerFeedbackContext(
      canonicalCorrectAnswer: question.correctAnswer,
      bookmarkIdentity: question.identity,
    ).freeze();
    final classification = _classifyResponse(
      inputMode: inputMode,
      hint: _hintUsage(),
    );
    final isCorrect = _scoreAnswer(question, answer);
    final selectedOptionId = inputMode == ClozeInputMode.selected
        ? question.optionIdentity(answer)
        : null;
    final correctOptionId = question.optionIdentity(question.correctAnswer);
    final contrastiveFeedback =
        !isCorrect && selectedOptionId != null && correctOptionId != null
        ? ContrastiveFeedbackContext(
            manifestIdentity: question.identity,
            manifestChecksumSha256: question.checksumSha256,
            promptMode: 'clozeSelected',
            evidenceContentRevision: question.contentRevision,
            correctOptionId: correctOptionId,
            selectedDistractorId: selectedOptionId,
          )
        : null;
    _recordInteraction();
    final pending = _evidence.captureCloze(
      sessionId: session.id,
      wordId: question.wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: _index + 1,
      contentRevision: question.identity.revision,
      checksumSha256: question.checksumSha256,
      typed: inputMode == ClozeInputMode.typed,
      classification: classification,
      contrastiveFeedback: contrastiveFeedback,
    );
    _pendingEvidence = pending;
    _pendingFeedbackContext = feedbackContext;
    _submittedAnswer = answer;
    _submittedMode = inputMode;
    _setPhase(ClozeReviewPhase.savingEvidence);
    return _commitEvidence(
      pending,
      feedbackContext: feedbackContext,
      retry: false,
    );
  }

  Future<AnswerRecordResult> retryEvidence() {
    _requireOperationAccepted();
    _requirePhase(ClozeReviewPhase.evidenceRetryRequired, 'retry evidence');
    final pending = _pendingEvidence;
    final feedbackContext = _pendingFeedbackContext;
    if (pending == null || !pending.requiresRetry || feedbackContext == null) {
      throw StateError('Exact cloze evidence retry is unavailable.');
    }
    _setPhase(ClozeReviewPhase.savingEvidence);
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
      try {
        _resetHintsAfterCommit();
      } on Object {
        // Durable evidence and frozen feedback already exist.
      }
      _setPhase(ClozeReviewPhase.answered);
      return result;
    } catch (_) {
      if (pending.requiresRetry) {
        _setPhase(ClozeReviewPhase.evidenceRetryRequired);
      } else {
        _pendingEvidence = null;
        _pendingFeedbackContext = null;
        _submittedAnswer = null;
        _submittedMode = null;
        _setPhase(ClozeReviewPhase.awaitingAnswer);
      }
      rethrow;
    }
  }

  Future<LearningSessionSummary?> advance() async {
    _requireOperationAccepted();
    if (_phase != ClozeReviewPhase.answered &&
        _phase != ClozeReviewPhase.skipped) {
      throw StateError('Cannot advance cloze from ${_phase.name}.');
    }
    if (_phase == ClozeReviewPhase.skipped) {
      try {
        _resetHintsAfterCommit();
      } on Object {
        // A skip has no evidence mutation.
      }
    }
    if (_index < items.length - 1) {
      _index += 1;
      _submittedAnswer = null;
      _submittedMode = null;
      _feedback = null;
      _setPhase(
        currentItem.question == null
            ? ClozeReviewPhase.skipped
            : ClozeReviewPhase.awaitingAnswer,
      );
      return null;
    }
    return _complete();
  }

  Future<LearningSessionSummary> retryCompletion() {
    _requireOperationAccepted();
    _requirePhase(ClozeReviewPhase.completionRetryRequired, 'retry completion');
    return _complete();
  }

  Future<LearningSessionSummary> _complete() async {
    _requireOperationAccepted();
    final close = _pendingClose ??= _learning.captureSessionClose(
      sessionId: session.id,
    );
    _setPhase(ClozeReviewPhase.completing);
    try {
      final summary = await _completeSession(close);
      _pendingClose = null;
      _setPhase(ClozeReviewPhase.completed);
      return summary;
    } catch (_) {
      _setPhase(ClozeReviewPhase.completionRetryRequired);
      rethrow;
    }
  }

  void _requireOperationAccepted() {
    _requireNotDisposed();
    if (!_acceptsOperation()) {
      throw StateError('The cloze route is no longer accepting actions.');
    }
  }

  void _requirePhase(ClozeReviewPhase required, String action) {
    _requireNotDisposed();
    if (_phase != required) {
      throw StateError('Cannot $action cloze from ${_phase.name}.');
    }
  }

  void _requireNotDisposed() {
    if (_disposed) throw StateError('Cloze review is disposed.');
  }

  void _setPhase(ClozeReviewPhase next) {
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

String? _blankOneOccurrence(String example, String spelling) {
  final canonicalExample = _canonicalDisplay(example);
  final canonicalSpelling = _canonicalDisplay(spelling);
  if (canonicalExample.isEmpty || canonicalSpelling.isEmpty) return null;
  final escaped = RegExp.escape(canonicalSpelling).replaceAll(r'\ ', r'\s+');
  final expression = RegExp(escaped, caseSensitive: false, unicode: true);
  final matches = expression
      .allMatches(canonicalExample)
      .where((match) {
        final before = match.start == 0
            ? ''
            : canonicalExample[match.start - 1];
        final after = match.end == canonicalExample.length
            ? ''
            : canonicalExample[match.end];
        return !_isWordCharacter(before) && !_isWordCharacter(after);
      })
      .toList(growable: false);
  if (matches.length != 1) return null;
  final match = matches.single;
  return '${canonicalExample.substring(0, match.start)}_____'
      '${canonicalExample.substring(match.end)}';
}

bool _isWordCharacter(String value) =>
    value.isNotEmpty && RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(value);

String _canonicalDisplay(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

List<String> _pinOptions({
  required String correctOption,
  required List<String> candidates,
  required int seed,
}) {
  final rotated = candidates.isEmpty
      ? const <String>[]
      : <String>[
          ...candidates.skip(seed % candidates.length),
          ...candidates.take(seed % candidates.length),
        ];
  final options = <String>[correctOption, ...rotated.take(3)];
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
