import 'package:flutter/foundation.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../../vocabulary/application/vocabulary_use_cases.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../domain/answer_feedback.dart';
import '../domain/contrastive_explanation.dart';
import '../domain/evidence_context.dart';
import '../domain/hint_policy.dart';
import '../domain/learning_models.dart';
import '../domain/lexical_prompt_artifact_identity.dart';
import '../domain/lesson_mode.dart';
import '../domain/session_configuration.dart';
import 'current_activity_evidence.dart';
import 'learning_use_cases.dart';

typedef DefinitionQuizSessionCompleter =
    Future<LearningSessionSummary> Function(PendingLearningSessionClose close);
typedef DefinitionQuizInteractionRecorder = void Function();
typedef DefinitionQuizOperationAcceptance = bool Function();
typedef DefinitionQuizEvidenceOperation =
    Future<AnswerRecordResult> Function(
      Future<AnswerRecordResult> Function() operation,
    );
typedef DefinitionQuizHintUsage = HintUsageSnapshot Function();
typedef DefinitionQuizHintReset = void Function();

enum DefinitionQuizReviewPhase {
  awaitingAnswer,
  skipped,
  savingEvidence,
  evidenceRetryRequired,
  answered,
  completing,
  completionRetryRequired,
  completed,
}

enum DefinitionQuizSkipReason {
  missingDefinition,
  unreviewedDefinition,
  staleDefinition,
}

final class DefinitionQuizQuestion {
  const DefinitionQuizQuestion({
    required this.wordId,
    required this.identity,
    required this.checksumSha256,
    required this.manifestChecksumSha256,
    required this.definition,
    required this.correctOption,
    required this.options,
    required this.partOfSpeech,
    this.optionIdentities = const <String, String>{},
  });

  final String wordId;
  final ContentIdentity identity;
  final String checksumSha256;
  final String manifestChecksumSha256;
  final String definition;
  final String correctOption;
  final List<String> options;
  final String partOfSpeech;
  final Map<String, String> optionIdentities;

  String? optionIdentity(String option) => optionIdentities[option];

  String get contentRevision =>
      'lexical-definition:$wordId@${identity.revision}:$checksumSha256';
}

final class DefinitionQuizItem {
  const DefinitionQuizItem.question(this.question) : skipReason = null;

  const DefinitionQuizItem.skipped(this.skipReason) : question = null;

  final DefinitionQuizQuestion? question;
  final DefinitionQuizSkipReason? skipReason;

  String get semanticAnnouncement => switch (skipReason) {
    DefinitionQuizSkipReason.missingDefinition =>
      'Skipped. A reviewed English definition is unavailable.',
    DefinitionQuizSkipReason.unreviewedDefinition =>
      'Skipped. The English definition has not been approved.',
    DefinitionQuizSkipReason.staleDefinition =>
      'Skipped. The English definition no longer matches this session.',
    null => '',
  };
}

final class _PinnedDefinitionCandidate {
  const _PinnedDefinitionCandidate({
    required this.word,
    required this.lexical,
    required this.definition,
    required this.checksumSha256,
    required this.manifestChecksumSha256,
  });

  final QuizWord word;
  final VocabularyWord lexical;
  final String definition;
  final String checksumSha256;
  final String manifestChecksumSha256;
}

/// Typed production boundary for reviewed English-definition recognition.
final class DefinitionQuizModeAdapter
    implements
        FocusTimerSupportingLessonModeAdapter,
        HintSupportingLessonModeAdapter,
        SessionConfigurableLessonModeAdapter {
  const DefinitionQuizModeAdapter();

  @override
  LessonMode get mode => LessonMode.definitionQuiz;

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
    strategy: 'Use the part of speech and the definition wording as clues.',
    context: 'Compare every visible word with the complete definition.',
  );

  DefinitionQuizReviewController createReview({
    required QuizSession session,
    required Iterable<VocabularyWord> lexicalWords,
    required LearningUseCases learning,
    required CurrentActivityEvidenceAdapter evidence,
    required DefinitionQuizHintUsage hintUsage,
    DefinitionQuizHintReset? resetHintsAfterCommit,
    DefinitionQuizSessionCompleter? completeSession,
    DefinitionQuizInteractionRecorder? recordInteraction,
    DefinitionQuizOperationAcceptance? acceptsOperation,
    DefinitionQuizEvidenceOperation? runEvidenceOperation,
  }) {
    if (session.isEmpty) {
      throw ArgumentError.value(session, 'session', 'must contain an item');
    }
    if (!identical(evidence.learning, learning)) {
      throw ArgumentError(
        'Definition quiz evidence must use the session LearningUseCases '
        'authority.',
      );
    }
    return DefinitionQuizReviewController._(
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
      classifyHintUsage: classifyHintUsage,
    );
  }

  bool scoresCorrect(DefinitionQuizQuestion question, String option) =>
      normalizeVocabularyText(option) ==
      normalizeVocabularyText(question.correctOption);

  HintEvidenceClassification classifyHintUsage(HintUsageSnapshot hint) {
    final level = switch (hint.availability) {
      HintAvailability.available => hint.hintLevel ?? 2,
      HintAvailability.unavailable => 0,
      HintAvailability.unknown => 2,
    };
    return HintEvidenceClassification(
      evidenceClass: level == 0
          ? EvidenceClass.recognition
          : EvidenceClass.guidedPractice,
      hintLevel: level,
    );
  }

  /// Pack-detail readiness uses the same reviewed artifact contract as quiz
  /// pinning, without starting a session or creating evidence.
  bool hasDeliverableReviewedDefinition(
    Iterable<VocabularyWord> lexicalWords,
  ) => lexicalWords.any((word) {
    final checksum = word.contentChecksumSha256;
    return _isReviewedPackagedWord(word) &&
        word.contentRevision > 0 &&
        checksum != null &&
        _isCanonicalSha256(checksum) &&
        _verifiedDefinitionArtifact(word) != null;
  });

  List<DefinitionQuizItem> pinItems({
    required QuizSession session,
    required Iterable<VocabularyWord> lexicalWords,
  }) {
    final lexicalById = <String, VocabularyWord?>{};
    for (final word in lexicalWords) {
      lexicalById.update(word.id, (_) => null, ifAbsent: () => word);
    }
    final candidates = <String, _PinnedDefinitionCandidate>{};
    final skips = <String, DefinitionQuizSkipReason>{};
    for (final question in session.questions) {
      final word = question.word;
      final lexical = lexicalById[word.id];
      if (lexical == null) {
        skips[word.id] = DefinitionQuizSkipReason.missingDefinition;
        continue;
      }
      if (!_isReviewedPackagedWord(lexical)) {
        skips[word.id] = DefinitionQuizSkipReason.unreviewedDefinition;
        continue;
      }
      final pinnedRevision = word.contentRevision;
      final pinnedChecksum = word.contentChecksumSha256;
      if (pinnedRevision == null ||
          pinnedRevision <= 0 ||
          pinnedChecksum == null ||
          !_isCanonicalSha256(pinnedChecksum) ||
          pinnedChecksum != lexical.contentChecksumSha256 ||
          pinnedRevision != lexical.contentRevision) {
        skips[word.id] = DefinitionQuizSkipReason.staleDefinition;
        continue;
      }
      final artifact = _verifiedDefinitionArtifact(lexical);
      if (artifact == null) {
        skips[word.id] = DefinitionQuizSkipReason.missingDefinition;
        continue;
      }
      candidates[word.id] = _PinnedDefinitionCandidate(
        word: word,
        lexical: lexical,
        definition: artifact.definition,
        checksumSha256: artifact.checksumSha256,
        manifestChecksumSha256: artifact.manifestChecksumSha256,
      );
    }

    return List<DefinitionQuizItem>.unmodifiable(
      session.questions.map((sessionQuestion) {
        final candidate = candidates[sessionQuestion.word.id];
        if (candidate == null) {
          return DefinitionQuizItem.skipped(
            skips[sessionQuestion.word.id] ??
                DefinitionQuizSkipReason.missingDefinition,
          );
        }
        final correctOption = _canonicalDisplay(candidate.lexical.spelling);
        final promptKey = normalizeVocabularyText(candidate.definition);
        final answerKey = normalizeVocabularyText(correctOption);
        final byAnswerKey = <String, String>{};
        final identityByAnswerKey = <String, String>{};
        for (final distractor in candidates.values) {
          if (distractor.word.id == candidate.word.id ||
              normalizeVocabularyText(distractor.definition) == promptKey) {
            continue;
          }
          final display = _canonicalDisplay(distractor.lexical.spelling);
          final key = normalizeVocabularyText(display);
          if (key == answerKey) continue;
          if (!byAnswerKey.containsKey(key)) {
            byAnswerKey[key] = display;
            identityByAnswerKey[key] = distractor.word.id;
          }
        }
        final keys = byAnswerKey.keys.toList()..sort();
        final options = _pinOptions(
          correctOption: correctOption,
          candidates: keys.map((key) => byAnswerKey[key]!).toList(),
          seed: _stableSeed(
            '${candidate.word.id}:${candidate.lexical.contentRevision}:'
            '${candidate.checksumSha256}',
          ),
        );
        return DefinitionQuizItem.question(
          DefinitionQuizQuestion(
            wordId: candidate.word.id,
            identity: ContentIdentity(
              type: ContentType.lexicalMetadata,
              id: candidate.word.id,
              revision: candidate.lexical.contentRevision,
            ),
            checksumSha256: candidate.checksumSha256,
            manifestChecksumSha256: candidate.manifestChecksumSha256,
            definition: candidate.definition,
            correctOption: correctOption,
            options: options,
            partOfSpeech: candidate.lexical.partOfSpeech,
            optionIdentities: <String, String>{
              correctOption: candidate.word.id,
              for (final key in keys)
                byAnswerKey[key]!: identityByAnswerKey[key]!,
            },
          ),
        );
      }),
    );
  }

  bool _isCanonicalSha256(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  bool _isReviewedPackagedWord(VocabularyWord word) =>
      word.isGlobal &&
      word.contentProvenance == ContentProvenance.packaged &&
      word.contentReviewState == ContentReviewState.approved &&
      word.contentPublicationState == ContentPublicationState.published;

  ({String definition, String checksumSha256, String manifestChecksumSha256})?
  _verifiedDefinitionArtifact(VocabularyWord word) {
    final metadata = word.richMetadata;
    final definition = metadata?.englishDefinition;
    final identity = LexicalPromptArtifactResolver.resolveForAdapter(
      promptMode: 'definitionChoice',
      wordId: word.id,
      coreRevision: word.contentRevision,
      coreChecksumSha256: word.contentChecksumSha256,
      verifiedArtifactRevision: metadata?.verifiedContentRevision,
      verifiedArtifactChecksumSha256: metadata?.verifiedArtifactChecksumSha256,
    );
    if (definition == null ||
        definition.trim().isEmpty ||
        definition != definition.trim() ||
        identity == null) {
      return null;
    }
    return (
      definition: definition,
      checksumSha256: identity.checksumSha256,
      manifestChecksumSha256: identity.verifiedArtifactChecksumSha256!,
    );
  }

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final context = support.evidenceContext;
    final unhinted =
        context.hintLevel == 0 &&
        context.evidenceClass == EvidenceClass.recognition;
    final hinted =
        context.hintLevel > 0 &&
        context.evidenceClass == EvidenceClass.guidedPractice;
    if (response.promptMode != 'definitionChoice' ||
        context.skillId != 'definition-recognition' ||
        !_isPinnedContentRevision(context.contentRevision, response.wordId) ||
        (!unhinted && !hinted)) {
      throw StateError(
        'Definition answers require pinned recognition or guided evidence.',
      );
    }
    return context;
  }

  bool _isPinnedContentRevision(String value, String wordId) {
    final prefix = 'lexical-definition:$wordId@';
    return value.startsWith(prefix) &&
        RegExp(
          r'^[1-9][0-9]*:[0-9a-f]{64}$',
        ).hasMatch(value.substring(prefix.length));
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('Definition quiz review owns pinned item selection.'),
  );
}

final class DefinitionQuizReviewController extends ChangeNotifier {
  DefinitionQuizReviewController._({
    required this.session,
    required List<DefinitionQuizItem> items,
    required this._learning,
    required this._evidence,
    required this._hintUsage,
    required this._resetHintsAfterCommit,
    required this._completeSession,
    required this._recordInteraction,
    required this._acceptsOperation,
    required this._runEvidenceOperation,
    required this._scoreAnswer,
    required this._classifyHintUsage,
  }) : items = List<DefinitionQuizItem>.unmodifiable(items),
       _phase = items.first.question == null
           ? DefinitionQuizReviewPhase.skipped
           : DefinitionQuizReviewPhase.awaitingAnswer;

  final QuizSession session;
  final List<DefinitionQuizItem> items;
  final LearningUseCases _learning;
  final CurrentActivityEvidenceAdapter _evidence;
  final DefinitionQuizHintUsage _hintUsage;
  final DefinitionQuizHintReset _resetHintsAfterCommit;
  final DefinitionQuizSessionCompleter _completeSession;
  final DefinitionQuizInteractionRecorder _recordInteraction;
  final DefinitionQuizOperationAcceptance _acceptsOperation;
  final DefinitionQuizEvidenceOperation _runEvidenceOperation;
  final bool Function(DefinitionQuizQuestion, String) _scoreAnswer;
  final HintEvidenceClassification Function(HintUsageSnapshot)
  _classifyHintUsage;

  var _index = 0;
  DefinitionQuizReviewPhase _phase;
  PendingCurrentActivityEvidence? _pendingEvidence;
  FrozenAnswerFeedbackContext? _pendingFeedbackContext;
  PendingLearningSessionClose? _pendingClose;
  AnswerFeedback? _feedback;
  String? _selectedOption;
  bool _disposed = false;

  int get index => _index;
  DefinitionQuizItem get currentItem => items[_index];
  DefinitionQuizReviewPhase get phase => _phase;
  AnswerFeedback? get feedback => _feedback;
  String? get selectedOption => _selectedOption;
  bool get isAnswered => _phase == DefinitionQuizReviewPhase.answered;
  bool get isSkipped => _phase == DefinitionQuizReviewPhase.skipped;
  bool get isSaving =>
      _phase == DefinitionQuizReviewPhase.savingEvidence ||
      _phase == DefinitionQuizReviewPhase.completing;
  bool get requiresRetry =>
      _phase == DefinitionQuizReviewPhase.evidenceRetryRequired ||
      _phase == DefinitionQuizReviewPhase.completionRetryRequired;
  bool get persistenceLocked =>
      isSaving ||
      requiresRetry ||
      _pendingEvidence != null ||
      _pendingClose != null;
  bool get actionLocked =>
      !_acceptsOperation() ||
      (_phase != DefinitionQuizReviewPhase.awaitingAnswer &&
          _phase != DefinitionQuizReviewPhase.answered &&
          _phase != DefinitionQuizReviewPhase.skipped);

  Future<AnswerRecordResult> answer({
    required String option,
    required int responseTimeMs,
  }) {
    _requireOperationAccepted();
    _requirePhase(DefinitionQuizReviewPhase.awaitingAnswer, 'answer');
    if (responseTimeMs < 0) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must not be negative',
      );
    }
    final question = currentItem.question!;
    if (!question.options.contains(option)) {
      throw ArgumentError.value(option, 'option', 'is not a pinned option');
    }
    final feedbackContext = AnswerFeedbackContext(
      canonicalCorrectAnswer: question.correctOption,
      bookmarkIdentity: question.identity,
    ).freeze();
    final hintClassification = _classifyHintUsage(_hintUsage());
    final isCorrect = _scoreAnswer(question, option);
    final selectedOptionId = question.optionIdentity(option);
    final correctOptionId = question.optionIdentity(question.correctOption);
    final contrastiveFeedback =
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
    _recordInteraction();
    final pending = _evidence.captureDefinitionRecognition(
      ownerId: session.ownerId,
      sessionId: session.id,
      wordId: question.wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: _index + 1,
      contentRevision: question.identity.revision,
      checksumSha256: question.checksumSha256,
      classification: hintClassification,
      contrastiveFeedback: contrastiveFeedback,
    );
    _pendingEvidence = pending;
    _pendingFeedbackContext = feedbackContext;
    _selectedOption = option;
    _setPhase(DefinitionQuizReviewPhase.savingEvidence);
    return _commitEvidence(
      pending,
      feedbackContext: feedbackContext,
      retry: false,
    );
  }

  Future<AnswerRecordResult> retryEvidence() {
    _requireOperationAccepted();
    _requirePhase(
      DefinitionQuizReviewPhase.evidenceRetryRequired,
      'retry evidence',
    );
    final pending = _pendingEvidence;
    final feedbackContext = _pendingFeedbackContext;
    if (pending == null || !pending.requiresRetry || feedbackContext == null) {
      throw StateError('Exact definition recognition retry is unavailable.');
    }
    _setPhase(DefinitionQuizReviewPhase.savingEvidence);
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
        // Evidence is durable and presentation is already frozen. Hint reset
        // is route-local state and must not manufacture a retryable write.
      }
      _setPhase(DefinitionQuizReviewPhase.answered);
      return result;
    } catch (_) {
      if (pending.requiresRetry) {
        _setPhase(DefinitionQuizReviewPhase.evidenceRetryRequired);
      } else {
        _pendingEvidence = null;
        _pendingFeedbackContext = null;
        _selectedOption = null;
        _setPhase(DefinitionQuizReviewPhase.awaitingAnswer);
      }
      rethrow;
    }
  }

  Future<LearningSessionSummary?> advance() async {
    _requireOperationAccepted();
    if (_phase != DefinitionQuizReviewPhase.answered &&
        _phase != DefinitionQuizReviewPhase.skipped) {
      throw StateError('Cannot advance definition quiz from ${_phase.name}.');
    }
    if (_phase == DefinitionQuizReviewPhase.skipped) {
      try {
        _resetHintsAfterCommit();
      } on Object {
        // A skip never writes evidence; local hint cleanup remains best effort.
      }
    }
    if (_index < items.length - 1) {
      _index += 1;
      _selectedOption = null;
      _feedback = null;
      _setPhase(
        currentItem.question == null
            ? DefinitionQuizReviewPhase.skipped
            : DefinitionQuizReviewPhase.awaitingAnswer,
      );
      return null;
    }
    return _complete();
  }

  Future<LearningSessionSummary> retryCompletion() {
    _requireOperationAccepted();
    _requirePhase(
      DefinitionQuizReviewPhase.completionRetryRequired,
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
    _setPhase(DefinitionQuizReviewPhase.completing);
    try {
      final summary = await _completeSession(close);
      _pendingClose = null;
      _setPhase(DefinitionQuizReviewPhase.completed);
      return summary;
    } catch (_) {
      _setPhase(DefinitionQuizReviewPhase.completionRetryRequired);
      rethrow;
    }
  }

  void _requireOperationAccepted() {
    _requireNotDisposed();
    if (!_acceptsOperation()) {
      throw StateError(
        'The definition quiz route is no longer accepting actions.',
      );
    }
  }

  void _requirePhase(DefinitionQuizReviewPhase required, String action) {
    _requireNotDisposed();
    if (_phase != required) {
      throw StateError('Cannot $action definition quiz from ${_phase.name}.');
    }
  }

  void _requireNotDisposed() {
    if (_disposed) throw StateError('Definition quiz review is disposed.');
  }

  void _setPhase(DefinitionQuizReviewPhase next) {
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

String _canonicalDisplay(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

List<String> _pinOptions({
  required String correctOption,
  required List<String> candidates,
  required int seed,
}) {
  final rotatedDistractors = candidates.isEmpty
      ? const <String>[]
      : <String>[
          ...candidates.skip(seed % candidates.length),
          ...candidates.take(seed % candidates.length),
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
