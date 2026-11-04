import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'accepted_quiz_plan.dart';
import 'cloze_content.dart';
import 'native_sentence_source.dart';
import 'evidence_context.dart';
import 'learning_evidence_contract.dart';
import 'native_exercise_checkpoint.dart';
import 'sentence_scramble_content.dart';
import 'word_scramble_letters.dart';

export 'native_exercise_checkpoint.dart';

final class QuizWord {
  const QuizWord({
    required this.id,
    required this.categoryId,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    this.contentRevision,
  });

  final String id;
  final String categoryId;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
  final String? contentRevision;
}

final class QuizQuestion {
  const QuizQuestion({
    required this.word,
    required this.options,
    this.direction = MeaningQuizDirection.forward,
  }) : lexical = null;

  QuizQuestion.lexical(LexicalQuestionContent content)
    : word = content.target.word,
      options = List.unmodifiable(content.optionLabels),
      direction = MeaningQuizDirection.forward,
      lexical = content;

  final QuizWord word;
  final List<String> options;
  final MeaningQuizDirection direction;
  final LexicalQuestionContent? lexical;

  String get correctAnswer =>
      lexical != null || direction == MeaningQuizDirection.reverse
      ? word.spelling
      : word.meaning;
  String get prompt =>
      lexical?.target.entry.definition ??
      (direction == MeaningQuizDirection.reverse
          ? word.meaning
          : word.spelling);
  String get promptMode => lexical?.input.name ?? 'meaningChoice';
  String get skillId =>
      lexical == null ? 'meaning-recall' : 'definition-recall';
  String get evidenceContentRevision =>
      lexical?.contentRevision ?? word.contentRevision!;
  EvidenceClass get unassistedEvidenceClass => lexical is DefinitionTypedContent
      ? EvidenceClass.independentRecall
      : EvidenceClass.recognition;
}

final class QuizSession {
  const QuizSession({
    required this.id,
    required this.questions,
    required this.startedAtUtc,
    this.configured,
  });

  final String id;
  final List<QuizQuestion> questions;
  final DateTime? startedAtUtc;
  final ConfiguredQuizState? configured;

  bool get isEmpty => questions.isEmpty;
}

final class LearningSessionDraft {
  const LearningSessionDraft({
    required this.id,
    required this.ownerId,
    required this.activityType,
    required this.startedAtUtc,
    required this.appVersion,
    required this.buildId,
  });

  final String id;
  final String ownerId;
  final String activityType;
  final DateTime? startedAtUtc;
  final String appVersion;
  final String buildId;

  LearningSessionDraft copyWith({DateTime? startedAtUtc}) {
    return LearningSessionDraft(
      id: id,
      ownerId: ownerId,
      activityType: activityType,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      appVersion: appVersion,
      buildId: buildId,
    );
  }
}

final class RecordAnswerCommand {
  const RecordAnswerCommand({
    required this.id,
    required this.ownerId,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.attemptNumber,
    required this.occurredAtUtc,
    this.providerProvenance,
    this.nativeDraft,
    this._evidenceContext,
  });

  final String id;
  final String ownerId;
  final String sessionId;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final int? responseTimeMs;
  final int attemptNumber;
  final DateTime occurredAtUtc;
  final String? providerProvenance;
  final NativeExerciseDraft? nativeDraft;
  final EvidenceContext? _evidenceContext;

  EvidenceContext get evidenceContext =>
      _evidenceContext ??
      LearningEvidenceContract.frozenV13LegacyEvidenceContext();
}

enum SrsReviewSelection { due, source }

final class SrsReviewSession {
  SrsReviewSession({
    required this.session,
    required Iterable<QuizWord> words,
    required this.selection,
  }) : words = List<QuizWord>.unmodifiable(words) {
    final started = session.startedAtUtc;
    if (!session.id.startsWith(idPrefix) ||
        session.id.length == idPrefix.length ||
        !LearningEvidenceContract.validIdentifier(session.id) ||
        !LearningEvidenceContract.validIdentifier(session.ownerId) ||
        session.activityType != 'srsReview' ||
        started == null ||
        !_srsMillisecondUtc(started) ||
        this.words.isEmpty ||
        this.words.length > 20) {
      throw ArgumentError('Invalid owned SRS review');
    }
    final ids = <String>{};
    for (final word in this.words) {
      if (!ids.add(word.id) ||
          !LearningEvidenceContract.validIdentifier(word.id) ||
          !LearningEvidenceContract.validIdentifier(word.categoryId) ||
          word.spelling.trim().isEmpty ||
          word.meaning.trim().isEmpty ||
          word.contentRevision == null ||
          !LearningEvidenceContract.validIdentifier(word.contentRevision!)) {
        throw ArgumentError('Invalid owned SRS target');
      }
    }
  }

  static const idPrefix = 'session:srs-review-v1:';
  final LearningSessionDraft session;
  final List<QuizWord> words;
  final SrsReviewSelection selection;

  String get id => session.id;
  String get ownerId => session.ownerId;
  DateTime get startedAtUtc => session.startedAtUtc!;
}

final class SrsReviewAnswerIntent {
  SrsReviewAnswerIntent({
    required this.review,
    required this.cardIndex,
    required this.command,
  }) {
    if (cardIndex < 0 ||
        cardIndex >= review.words.length ||
        command.id != 'attempt:srs:${review.id}:$cardIndex' ||
        command.ownerId != review.ownerId ||
        command.sessionId != review.id ||
        command.wordId != review.words[cardIndex].id ||
        command.promptMode != 'srsRecall' ||
        command.attemptNumber != cardIndex + 1 ||
        command.providerProvenance != null ||
        !_srsMillisecondUtc(command.occurredAtUtc) ||
        command.occurredAtUtc.isBefore(review.startedAtUtc)) {
      throw ArgumentError('SRS rating does not match its original card');
    }
  }

  final SrsReviewSession review;
  final int cardIndex;
  final RecordAnswerCommand command;
}

final class SrsReviewFinishIntent {
  SrsReviewFinishIntent({required this.review, required this.endedAtUtc}) {
    if (!_srsMillisecondUtc(endedAtUtc) ||
        endedAtUtc.isBefore(review.startedAtUtc)) {
      throw ArgumentError('Invalid original SRS end');
    }
  }

  final SrsReviewSession review;
  final DateTime endedAtUtc;
}

final class SrsReviewStartResult {
  const SrsReviewStartResult({required this.review, required this.inserted});
  final SrsReviewSession review;
  final bool inserted;
}

final class SrsReviewFinishResult {
  const SrsReviewFinishResult({required this.summary, required this.inserted});
  final LearningSessionSummary summary;
  final bool inserted;
}

bool _srsMillisecondUtc(DateTime value) =>
    value.isUtc &&
    value.microsecondsSinceEpoch >= 0 &&
    value.microsecondsSinceEpoch % 1000 == 0;

final class SrsSnapshot {
  const SrsSnapshot({
    required this.intervalDays,
    required this.repetitions,
    required this.lapses,
    required this.stability,
    required this.difficulty,
    required this.lastReviewAtUtc,
    required this.dueAtUtc,
    required this.algorithmVersion,
  });

  final int intervalDays;
  final int repetitions;
  final int lapses;
  final double stability;
  final double difficulty;
  final DateTime? lastReviewAtUtc;
  final DateTime? dueAtUtc;
  final int algorithmVersion;
}

final class AnswerRecordResult {
  const AnswerRecordResult({required this.inserted, required this.srs});

  final bool inserted;
  final SrsSnapshot? srs;
}

enum NativeCheckpointPhase {
  awaitingAnswer,
  pendingAnswer,
  answered,
  closing,
  completed,
  abandoned,
}

abstract interface class NativeExerciseState {
  AcceptedNativeExercise get exercise;
  AcceptedNativePlan get plan;
  NativeCheckpoint get checkpoint;
  NativeCheckpointPhase get phase;
  int get checkpointRevision;
  LearningSessionSummary? get completedSummary;
}

sealed class AcceptedNativeExercise {
  const AcceptedNativeExercise();

  LearningSessionDraft get session;
  QuizWord get word;
  String get wordContentRevision;
  String get evidenceContentRevision;

  String get id => session.id;
  String get ownerId => session.ownerId;
  DateTime get startedAtUtc => session.startedAtUtc!;
}

final class DictationSession extends AcceptedNativeExercise {
  static const idPrefix = 'session:dictation-v1:';

  DictationSession({required this.session, required this.word}) {
    if (!session.id.startsWith(idPrefix) ||
        session.id.length == idPrefix.length ||
        !LearningEvidenceContract.validIdentifier(session.id) ||
        session.activityType != 'dictation' ||
        session.startedAtUtc?.isUtc != true ||
        word.contentRevision == null ||
        word.contentRevision!.trim().isEmpty) {
      throw ArgumentError(
        'Dictation requires a native session ID, original UTC start and content pin',
      );
    }
  }

  @override
  final LearningSessionDraft session;
  @override
  final QuizWord word;

  @override
  String get wordContentRevision => word.contentRevision!;
  @override
  String get evidenceContentRevision => wordContentRevision;
}

final class WordScrambleSession extends AcceptedNativeExercise {
  factory WordScrambleSession({
    required LearningSessionDraft session,
    required QuizWord word,
  }) {
    if (!session.id.startsWith(idPrefix) ||
        session.id.length == idPrefix.length ||
        !LearningEvidenceContract.validIdentifier(session.id) ||
        !LearningEvidenceContract.validIdentifier(session.ownerId) ||
        session.activityType != 'wordScramble' ||
        session.startedAtUtc?.isUtc != true ||
        !supportsTarget(word)) {
      throw ArgumentError(
        'Word Scramble requires its original session and a supported pinned target',
      );
    }
    return WordScrambleSession._(
      session: session,
      word: word,
      letters: List<String>.unmodifiable(createStableScramble(word.spelling)),
    );
  }

  WordScrambleSession._({
    required this.session,
    required this.word,
    required this.letters,
  }) : evidenceContentRevision =
           'word-scramble-v1:${sha256.convert(utf8.encode(jsonEncode([
             'word-scramble-v1',
             [word.id, word.categoryId, word.spelling, word.meaning, word.partOfSpeech, word.contentRevision],
             letters,
           ])))}';

  static const idPrefix = 'session:word-scramble-v1:';

  static bool supportsTarget(QuizWord word) {
    if (!LearningEvidenceContract.validIdentifier(word.id) ||
        !LearningEvidenceContract.validIdentifier(word.categoryId) ||
        word.spelling.isEmpty ||
        word.spelling.length > 120 ||
        RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(word.spelling) ||
        word.contentRevision == null ||
        RegExp(
              r'local-vocabulary-v1:[1-9][0-9]*',
            ).stringMatch(word.contentRevision!) !=
            word.contentRevision) {
      return false;
    }
    final letters = createStableScramble(word.spelling);
    return letters.length >= 2 && letters.join() != word.spelling;
  }

  @override
  final LearningSessionDraft session;
  @override
  final QuizWord word;
  final List<String> letters;
  @override
  String get wordContentRevision => word.contentRevision!;
  @override
  final String evidenceContentRevision;
}

final class SentenceScrambleSession extends AcceptedNativeExercise {
  factory SentenceScrambleSession({
    required LearningSessionDraft session,
    required QuizWord word,
    required SentenceScrambleContent content,
  }) {
    if (!session.id.startsWith(idPrefix) ||
        session.id.length == idPrefix.length ||
        !LearningEvidenceContract.validIdentifier(session.id) ||
        !LearningEvidenceContract.validIdentifier(session.ownerId) ||
        session.activityType != 'sentenceScramble' ||
        session.startedAtUtc?.isUtc != true ||
        !LearningEvidenceContract.validIdentifier(word.id) ||
        !LearningEvidenceContract.validIdentifier(word.categoryId) ||
        !SentenceScrambleContent.supportsTarget(word.spelling) ||
        word.contentRevision == null ||
        RegExp(
              r'local-vocabulary-v1:[1-9][0-9]*',
            ).stringMatch(word.contentRevision!) !=
            word.contentRevision ||
        content.targetSpelling != word.spelling ||
        !_nativeSourceMatches(content.source, session, word)) {
      throw ArgumentError(
        'Sentence Scramble requires its original session, owned anchor and admitted sentence',
      );
    }
    return SentenceScrambleSession._(
      session: session,
      word: word,
      content: content,
    );
  }

  SentenceScrambleSession._({
    required this.session,
    required this.word,
    required this.content,
  }) : providerProvenance = _nativeProvenance(
         content.source,
         'sentence-scramble-model-v1',
       ),
       evidenceContentRevision =
           'sentence-scramble-v1:${sha256.convert(utf8.encode(jsonEncode([
             'sentence-scramble-v1',
             [word.id, word.categoryId, word.spelling, word.meaning, word.partOfSpeech, word.contentRevision],
             [content.sentence, content.tokens, content.tokenOrder, ..._nativeSourceRevision(content.source)],
           ])))}';

  static const idPrefix = 'session:sentence-scramble-v1:';

  @override
  final LearningSessionDraft session;
  @override
  final QuizWord word;
  final SentenceScrambleContent content;
  final String providerProvenance;
  @override
  final String evidenceContentRevision;
  @override
  String get wordContentRevision => word.contentRevision!;
  List<int> get tokenOrder => content.tokenOrder;
}

sealed class NativeAnswerInput {
  const NativeAnswerInput();

  AcceptedNativeExercise get exercise;
  Duration get responseTime;
}

enum ClozeVariant { typed, choice }

sealed class ClozeSession extends AcceptedNativeExercise {
  ClozeSession._({
    required this.session,
    required this.word,
    required this.content,
  }) : providerProvenance = _nativeProvenance(
         content.source,
         'cloze-model-v1',
       ) {
    if (!session.id.startsWith(idPrefix) ||
        session.id.length == idPrefix.length ||
        !LearningEvidenceContract.validIdentifier(session.id) ||
        !LearningEvidenceContract.validIdentifier(session.ownerId) ||
        session.activityType != 'cloze' ||
        session.startedAtUtc?.isUtc != true ||
        !_validClozeWord(word) ||
        content.gapText.toLowerCase() != word.spelling.toLowerCase() ||
        !_nativeSourceMatches(content.source, session, word)) {
      throw ArgumentError(
        'Cloze requires its original session, target and admitted gap',
      );
    }
  }

  static const idPrefix = 'session:cloze-v1:';

  @override
  final LearningSessionDraft session;
  @override
  final QuizWord word;
  final ClozeContent content;
  final String providerProvenance;
  ClozeVariant get variant;

  @override
  String get wordContentRevision => word.contentRevision!;
}

final class TypedClozeSession extends ClozeSession {
  TypedClozeSession({
    required super.session,
    required super.word,
    required super.content,
  }) : evidenceContentRevision = _clozeContentRevision(
         ClozeVariant.typed,
         word,
         content,
         const [],
       ),
       super._();

  @override
  final String evidenceContentRevision;
  @override
  ClozeVariant get variant => ClozeVariant.typed;
}

final class ChoiceClozeSession extends ClozeSession {
  factory ChoiceClozeSession({
    required LearningSessionDraft session,
    required QuizWord word,
    required ClozeContent content,
    required Iterable<QuizWord> choices,
  }) {
    final frozen = List<QuizWord>.unmodifiable(choices);
    if (frozen.length != 3 ||
        frozen.map((option) => option.id).toSet().length != 3 ||
        frozen
                .map((option) => option.spelling.trim().toLowerCase())
                .toSet()
                .length !=
            3 ||
        frozen.any(
          (option) =>
              !_validClozeWord(option) || option.categoryId != word.categoryId,
        ) ||
        !frozen.any(
          (option) =>
              jsonEncode(_clozeWordSnapshot(option)) ==
              jsonEncode(_clozeWordSnapshot(word)),
        )) {
      throw ArgumentError(
        'Cloze choices require the exact original target and two distinct same-category snapshots',
      );
    }
    return ChoiceClozeSession._(session, word, content, frozen);
  }

  ChoiceClozeSession._(
    LearningSessionDraft session,
    QuizWord word,
    ClozeContent content,
    this.choices,
  ) : evidenceContentRevision = _clozeContentRevision(
        ClozeVariant.choice,
        word,
        content,
        choices,
      ),
      super._(session: session, word: word, content: content);

  final List<QuizWord> choices;
  @override
  final String evidenceContentRevision;
  @override
  ClozeVariant get variant => ClozeVariant.choice;
}

bool _validClozeWord(QuizWord word) =>
    LearningEvidenceContract.validIdentifier(word.id) &&
    LearningEvidenceContract.validIdentifier(word.categoryId) &&
    ClozeContent.supportsTarget(word.spelling) &&
    word.contentRevision != null &&
    RegExp(
          r'local-vocabulary-v1:[1-9][0-9]*',
        ).stringMatch(word.contentRevision!) ==
        word.contentRevision;

List<Object?> _clozeWordSnapshot(QuizWord word) => [
  word.id,
  word.categoryId,
  word.spelling,
  word.meaning,
  word.partOfSpeech,
  word.contentRevision,
];

String _clozeContentRevision(
  ClozeVariant variant,
  QuizWord word,
  ClozeContent content,
  List<QuizWord> choices,
) =>
    'cloze-v1:${sha256.convert(utf8.encode(jsonEncode([
      'cloze-v1',
      variant.name,
      _clozeWordSnapshot(word),
      [content.sentence, content.gapStart, content.gapEnd, ..._nativeSourceRevision(content.source)],
      [for (final option in choices) _clozeWordSnapshot(option)],
    ])))}';

List<Object?> _nativeSourceRevision(NativeSentenceSource source) =>
    switch (source) {
      GeneratedSentenceSource() => [
        source.kind.wire,
        source.cefr.wire,
        source.language,
        source.modelVersion,
        source.cached,
      ],
      AuthoredSentenceSource() => [source.toJson()],
    };

String _nativeProvenance(NativeSentenceSource source, String prefix) =>
    switch (source) {
      GeneratedSentenceSource() =>
        '$prefix:${sha256.convert(utf8.encode(source.modelVersion))}',
      AuthoredSentenceSource() => source.provenance,
    };

bool _nativeSourceMatches(
  NativeSentenceSource source,
  LearningSessionDraft session,
  QuizWord word,
) => switch (source) {
  GeneratedSentenceSource() => true,
  AuthoredSentenceSource() =>
    source.pack.ownerId == session.ownerId &&
        jsonEncode(_clozeWordSnapshot(source.target.word)) ==
            jsonEncode(_clozeWordSnapshot(word)),
};

final class TypedClozeAnswerInput extends NativeAnswerInput {
  const TypedClozeAnswerInput({
    required this.exercise,
    required this.response,
    required this.responseTime,
  });
  @override
  final TypedClozeSession exercise;
  final String response;
  @override
  final Duration responseTime;
}

final class ChoiceClozeAnswerInput extends NativeAnswerInput {
  const ChoiceClozeAnswerInput({
    required this.exercise,
    required this.optionId,
    required this.responseTime,
  });
  @override
  final ChoiceClozeSession exercise;
  final String optionId;
  @override
  final Duration responseTime;
}

final class WordScrambleAnswerInput extends NativeAnswerInput {
  const WordScrambleAnswerInput({
    required this.exercise,
    required this.response,
    required this.responseTime,
    this.tileSlots,
  });

  @override
  final WordScrambleSession exercise;
  final String response;
  final List<int?>? tileSlots;
  @override
  final Duration responseTime;
}

final class SentenceScrambleAnswerInput extends NativeAnswerInput {
  const SentenceScrambleAnswerInput({
    required this.exercise,
    required this.response,
    required this.responseTime,
    this.tileSlots,
  });

  @override
  final SentenceScrambleSession exercise;
  final String response;
  final List<int?>? tileSlots;
  @override
  final Duration responseTime;
}

final class DictationAnswerInput extends NativeAnswerInput {
  const DictationAnswerInput({
    required this.exercise,
    required this.response,
    required this.assisted,
    required this.responseTime,
  });

  @override
  final DictationSession exercise;
  final String response;
  final bool assisted;
  @override
  final Duration responseTime;
}

final class NativeFinishIntent {
  const NativeFinishIntent({
    required this.exercise,
    required this.answer,
    required this.endedAtUtc,
  });

  final AcceptedNativeExercise exercise;
  final RecordAnswerCommand answer;
  final DateTime endedAtUtc;
}

final class LearningSessionSummary {
  const LearningSessionSummary({
    required this.id,
    required this.state,
    required this.correctCount,
    required this.wrongCount,
    required this.score,
  });

  final String id;
  final String state;
  final int correctCount;
  final int wrongCount;
  final int score;
}

final class LearningSessionResult {
  LearningSessionResult({
    required this.summary,
    required Iterable<String> mistakeWordIds,
  }) : mistakeWordIds = List.unmodifiable(mistakeWordIds);

  final LearningSessionSummary summary;
  final List<String> mistakeWordIds;
}

final class ReadingProgressCommand {
  const ReadingProgressCommand({
    required this.eventId,
    required this.ownerId,
    required this.documentId,
    required this.documentRevision,
    required this.position,
    required this.isCompleted,
    required this.occurredAtUtc,
  });

  final String eventId;
  final String ownerId;
  final String documentId;
  final int documentRevision;
  final int position;
  final bool isCompleted;
  final DateTime occurredAtUtc;
}

final class ReadingProgressSnapshot {
  const ReadingProgressSnapshot({
    required this.documentId,
    required this.documentRevision,
    required this.lastPosition,
    required this.isCompleted,
    required this.updatedAtUtc,
  });

  final String documentId;
  final int documentRevision;
  final int lastPosition;
  final bool isCompleted;
  final DateTime updatedAtUtc;

  @override
  bool operator ==(Object other) {
    return other is ReadingProgressSnapshot &&
        other.documentId == documentId &&
        other.documentRevision == documentRevision &&
        other.lastPosition == lastPosition &&
        other.isCompleted == isCompleted &&
        other.updatedAtUtc == updatedAtUtc;
  }

  @override
  int get hashCode => Object.hash(
    documentId,
    documentRevision,
    lastPosition,
    isCompleted,
    updatedAtUtc,
  );
}

enum LexicalQuizInput { definitionChoice, definitionTyped }

final class ConfiguredQuizLaunch {
  const ConfiguredQuizLaunch({
    required this.session,
    required this.configuration,
    this.preparedPlan,
  });

  final LearningSessionDraft session;
  final QuizConfiguration configuration;
  final AcceptedQuizPlan? preparedPlan;
}

enum ConfiguredQuizUnavailableReason {
  emptySelection,
  notFound,
  legacy,
  syncedEvidence,
  corrupt,
  ownerChanged,
  contentChanged,
  unsupportedPolicy,
}

final class ConfiguredQuizUnavailable implements Exception {
  const ConfiguredQuizUnavailable(this.reason);
  final ConfiguredQuizUnavailableReason reason;

  @override
  String toString() => 'Configured quiz unavailable: ${reason.name}';
}

abstract interface class ConfiguredQuizReadBinding {
  void requireCurrent();
  QuizCheckpoint bindCheckpointWrite(QuizCheckpoint checkpoint);
}

final class ConfiguredQuizState {
  ConfiguredQuizState({
    required this.sessionId,
    required this.ownerId,
    required this.activityType,
    required this.startedAtUtc,
    required this.appVersion,
    required this.buildId,
    required this.state,
    required this.endedAtUtc,
    required this.plan,
    required this.checkpointRevision,
    required this.checkpoint,
    Iterable<QuizWord> mistakeWords = const [],
    this.restored = false,
    this._readBinding,
  }) : mistakeWords = List.unmodifiable(mistakeWords);

  final String sessionId;
  final String ownerId;
  final String activityType;
  final DateTime startedAtUtc;
  final String appVersion;
  final String buildId;
  final String state;
  final DateTime? endedAtUtc;
  final AcceptedQuizPlan plan;
  final int checkpointRevision;
  final QuizCheckpoint checkpoint;
  final List<QuizWord> mistakeWords;
  final bool restored;
  final ConfiguredQuizReadBinding? _readBinding;

  void requireCurrent() {
    final binding = _readBinding;
    if (binding == null) {
      throw StateError('Original configured quiz read is required');
    }
    binding.requireCurrent();
  }

  QuizCheckpoint bindCheckpointWrite(QuizCheckpoint checkpoint) {
    requireCurrent();
    return _readBinding!.bindCheckpointWrite(checkpoint);
  }

  String? get acknowledgedContrastiveExplanation {
    final checkpoint = this.checkpoint;
    if (checkpoint is! AnsweredQuizQuestion ||
        checkpoint.answer.isCorrect ||
        checkpoint.answer.revealed) {
      return null;
    }
    final content = plan.questions[checkpoint.questionOrdinal].lexical;
    final selected = checkpoint.answer.selectedOptionOrdinal;
    if (content is! DefinitionChoiceContent || selected == null) return null;
    return content.authoredOptions[selected].contrastiveExplanation;
  }

  QuizSession get asQuizSession => QuizSession(
    id: sessionId,
    questions: plan.questions,
    startedAtUtc: startedAtUtc,
    configured: this,
  );

  ConfiguredQuizState asRestored() => ConfiguredQuizState(
    sessionId: sessionId,
    ownerId: ownerId,
    activityType: activityType,
    startedAtUtc: startedAtUtc,
    appVersion: appVersion,
    buildId: buildId,
    state: state,
    endedAtUtc: endedAtUtc,
    plan: plan,
    checkpointRevision: checkpointRevision,
    checkpoint: checkpoint,
    mistakeWords: mistakeWords,
    restored: true,
    readBinding: _readBinding,
  );
}

final class ConfiguredQuizAnswerResult {
  const ConfiguredQuizAnswerResult({required this.state, required this.record});
  final ConfiguredQuizState state;
  final AnswerRecordResult record;
}

final class ConfiguredQuizFinishResult {
  const ConfiguredQuizFinishResult({
    required this.state,
    required this.summary,
  });
  final ConfiguredQuizState state;
  final LearningSessionSummary summary;
}
