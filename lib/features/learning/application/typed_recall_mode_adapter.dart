import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../domain/answer_feedback.dart';
import '../domain/evidence_context.dart';
import '../domain/hint_policy.dart';
import '../domain/learning_models.dart';
import '../domain/lesson_mode.dart';
import '../domain/session_configuration.dart';
import 'current_activity_evidence.dart';
import 'learning_use_cases.dart';
import 'meaning_quiz_mode_adapter.dart';

const String typedRecallNormalizationRevisionV1 = 'vocabulary-text-v1';

String typedRecallAnswerSetChecksumSha256({
  required String coreChecksumSha256,
  int? acceptedVariantsRevision,
  String? acceptedVariantsChecksumSha256,
}) {
  final checksumPattern = RegExp(r'^[0-9a-f]{64}$');
  if (!checksumPattern.hasMatch(coreChecksumSha256)) {
    throw ArgumentError.value(
      coreChecksumSha256,
      'coreChecksumSha256',
      'must be lowercase SHA-256',
    );
  }
  if (acceptedVariantsRevision == null &&
      acceptedVariantsChecksumSha256 == null) {
    return coreChecksumSha256;
  }
  if (acceptedVariantsRevision == null ||
      acceptedVariantsRevision <= 0 ||
      acceptedVariantsChecksumSha256 == null ||
      !checksumPattern.hasMatch(acceptedVariantsChecksumSha256)) {
    throw ArgumentError(
      'accepted spelling variants require a positive revision and checksum',
    );
  }
  return sha256
      .convert(
        utf8.encode(
          'typed-recall-answer-set-v1\u0000$coreChecksumSha256\u0000'
          '$acceptedVariantsRevision\u0000$acceptedVariantsChecksumSha256',
        ),
      )
      .toString();
}

/// Bounded canonical decomposition table for the Latin vocabulary supported
/// by normalization revision v1. Decomposition happens before Dart's
/// locale-independent lowercase mapping, so composed/decomposed spellings are
/// equivalent without inheriting the device locale (notably Turkish casing).
const Map<int, String> _canonicalLatinDecomposition = <int, String>{
  0x00c0: 'A\u0300',
  0x00c1: 'A\u0301',
  0x00c2: 'A\u0302',
  0x00c3: 'A\u0303',
  0x00c4: 'A\u0308',
  0x00c5: 'A\u030a',
  0x00c7: 'C\u0327',
  0x00c8: 'E\u0300',
  0x00c9: 'E\u0301',
  0x00ca: 'E\u0302',
  0x00cb: 'E\u0308',
  0x00cc: 'I\u0300',
  0x00cd: 'I\u0301',
  0x00ce: 'I\u0302',
  0x00cf: 'I\u0308',
  0x00d1: 'N\u0303',
  0x00d2: 'O\u0300',
  0x00d3: 'O\u0301',
  0x00d4: 'O\u0302',
  0x00d5: 'O\u0303',
  0x00d6: 'O\u0308',
  0x00d9: 'U\u0300',
  0x00da: 'U\u0301',
  0x00db: 'U\u0302',
  0x00dc: 'U\u0308',
  0x00dd: 'Y\u0301',
  0x00e0: 'a\u0300',
  0x00e1: 'a\u0301',
  0x00e2: 'a\u0302',
  0x00e3: 'a\u0303',
  0x00e4: 'a\u0308',
  0x00e5: 'a\u030a',
  0x00e7: 'c\u0327',
  0x00e8: 'e\u0300',
  0x00e9: 'e\u0301',
  0x00ea: 'e\u0302',
  0x00eb: 'e\u0308',
  0x00ec: 'i\u0300',
  0x00ed: 'i\u0301',
  0x00ee: 'i\u0302',
  0x00ef: 'i\u0308',
  0x00f1: 'n\u0303',
  0x00f2: 'o\u0300',
  0x00f3: 'o\u0301',
  0x00f4: 'o\u0302',
  0x00f5: 'o\u0303',
  0x00f6: 'o\u0308',
  0x00f9: 'u\u0300',
  0x00fa: 'u\u0301',
  0x00fb: 'u\u0302',
  0x00fc: 'u\u0308',
  0x00fd: 'y\u0301',
  0x00ff: 'y\u0308',
  0x0100: 'A\u0304',
  0x0101: 'a\u0304',
  0x0102: 'A\u0306',
  0x0103: 'a\u0306',
  0x0104: 'A\u0328',
  0x0105: 'a\u0328',
  0x0106: 'C\u0301',
  0x0107: 'c\u0301',
  0x0108: 'C\u0302',
  0x0109: 'c\u0302',
  0x010a: 'C\u0307',
  0x010b: 'c\u0307',
  0x010c: 'C\u030c',
  0x010d: 'c\u030c',
  0x010e: 'D\u030c',
  0x010f: 'd\u030c',
  0x0112: 'E\u0304',
  0x0113: 'e\u0304',
  0x0114: 'E\u0306',
  0x0115: 'e\u0306',
  0x0116: 'E\u0307',
  0x0117: 'e\u0307',
  0x0118: 'E\u0328',
  0x0119: 'e\u0328',
  0x011a: 'E\u030c',
  0x011b: 'e\u030c',
  0x011c: 'G\u0302',
  0x011d: 'g\u0302',
  0x011e: 'G\u0306',
  0x011f: 'g\u0306',
  0x0120: 'G\u0307',
  0x0121: 'g\u0307',
  0x0122: 'G\u0327',
  0x0123: 'g\u0327',
  0x0124: 'H\u0302',
  0x0125: 'h\u0302',
  0x0128: 'I\u0303',
  0x0129: 'i\u0303',
  0x012a: 'I\u0304',
  0x012b: 'i\u0304',
  0x012c: 'I\u0306',
  0x012d: 'i\u0306',
  0x012e: 'I\u0328',
  0x012f: 'i\u0328',
  0x0130: 'I\u0307',
  0x0134: 'J\u0302',
  0x0135: 'j\u0302',
  0x0136: 'K\u0327',
  0x0137: 'k\u0327',
  0x0139: 'L\u0301',
  0x013a: 'l\u0301',
  0x013b: 'L\u0327',
  0x013c: 'l\u0327',
  0x013d: 'L\u030c',
  0x013e: 'l\u030c',
  0x0143: 'N\u0301',
  0x0144: 'n\u0301',
  0x0145: 'N\u0327',
  0x0146: 'n\u0327',
  0x0147: 'N\u030c',
  0x0148: 'n\u030c',
  0x014c: 'O\u0304',
  0x014d: 'o\u0304',
  0x014e: 'O\u0306',
  0x014f: 'o\u0306',
  0x0150: 'O\u030b',
  0x0151: 'o\u030b',
  0x0154: 'R\u0301',
  0x0155: 'r\u0301',
  0x0156: 'R\u0327',
  0x0157: 'r\u0327',
  0x0158: 'R\u030c',
  0x0159: 'r\u030c',
  0x015a: 'S\u0301',
  0x015b: 's\u0301',
  0x015c: 'S\u0302',
  0x015d: 's\u0302',
  0x015e: 'S\u0327',
  0x015f: 's\u0327',
  0x0160: 'S\u030c',
  0x0161: 's\u030c',
  0x0162: 'T\u0327',
  0x0163: 't\u0327',
  0x0164: 'T\u030c',
  0x0165: 't\u030c',
  0x0168: 'U\u0303',
  0x0169: 'u\u0303',
  0x016a: 'U\u0304',
  0x016b: 'u\u0304',
  0x016c: 'U\u0306',
  0x016d: 'u\u0306',
  0x016e: 'U\u030a',
  0x016f: 'u\u030a',
  0x0170: 'U\u030b',
  0x0171: 'u\u030b',
  0x0172: 'U\u0328',
  0x0173: 'u\u0328',
  0x0174: 'W\u0302',
  0x0175: 'w\u0302',
  0x0176: 'Y\u0302',
  0x0177: 'y\u0302',
  0x0178: 'Y\u0308',
  0x0179: 'Z\u0301',
  0x017a: 'z\u0301',
  0x017b: 'Z\u0307',
  0x017c: 'z\u0307',
  0x017d: 'Z\u030c',
  0x017e: 'z\u030c',
};

enum TypedRecallPromptKind { meaning, audio, context }

enum TypedRecallResponseCode {
  exact('exact'),
  acceptedVariant('accepted-variant'),
  incorrect('incorrect');

  const TypedRecallResponseCode(this.code);

  final String code;
}

final class TypedRecallPrompt {
  TypedRecallPrompt({
    required this.wordId,
    required this.canonicalAnswer,
    required this.promptKind,
    required this.normalizationRevision,
    required this.contentRevision,
    required this.contentChecksumSha256,
    Iterable<String> acceptedVariants = const <String>[],
    this.acceptedVariantsRevision,
    this.acceptedVariantsChecksumSha256,
  }) : acceptedVariants = List<String>.unmodifiable(acceptedVariants);

  final String wordId;
  final String canonicalAnswer;
  final List<String> acceptedVariants;
  final TypedRecallPromptKind promptKind;
  final String normalizationRevision;
  final int contentRevision;
  final String contentChecksumSha256;
  final int? acceptedVariantsRevision;
  final String? acceptedVariantsChecksumSha256;
}

final class TypedRecallSupport {
  const TypedRecallSupport({
    required this.hint,
    this.additionalSupportUsed = false,
  });

  const TypedRecallSupport.unassisted()
    : hint = const HintUsageSnapshot.unavailable(),
      additionalSupportUsed = false;

  final HintUsageSnapshot hint;
  final bool additionalSupportUsed;
}

final class TypedRecallEvaluation {
  const TypedRecallEvaluation._({
    required this.isCorrect,
    required this.responseCode,
    required this.evidenceClass,
    required this.hintLevel,
    required this.normalizationRevision,
    required this.promptKind,
  });

  final bool isCorrect;
  final TypedRecallResponseCode responseCode;
  final EvidenceClass evidenceClass;
  final int hintLevel;
  final String normalizationRevision;
  final TypedRecallPromptKind promptKind;

  String get controlledResponseCode => responseCode.code;

  String get providerProvenance =>
      'typed-recall:$normalizationRevision:${promptKind.name}:'
      '$controlledResponseCode';
}

final class CapturedTypedRecallSubmission {
  const CapturedTypedRecallSubmission({
    required this.evaluation,
    required this.pending,
  });

  final TypedRecallEvaluation evaluation;
  final PendingCurrentActivityEvidence pending;
}

typedef TypedRecallQuizSessionCompleter =
    Future<LearningSessionSummary> Function(PendingLearningSessionClose close);
typedef TypedRecallInteractionRecorder = void Function();
typedef TypedRecallOperationAcceptance = bool Function();
typedef TypedRecallEvidenceOperation =
    Future<AnswerRecordResult> Function(
      Future<AnswerRecordResult> Function() operation,
    );
typedef TypedRecallSupportUsage = TypedRecallSupport Function();
typedef TypedRecallHintReset = void Function();

/// The single correctness and evidence-class boundary for productive spelling
/// recall. Raw learner text is reduced synchronously to a controlled response
/// code before the immutable Evidence Gateway command is captured.
final class TypedRecallModeAdapter
    implements
        FocusTimerSupportingLessonModeAdapter,
        HintSupportingLessonModeAdapter,
        SessionConfigurableLessonModeAdapter {
  const TypedRecallModeAdapter();

  static const int maxAnswerScalars = 120;
  static const int maxAcceptedVariants = 8;

  @override
  LessonMode get mode => LessonMode.typedRecall;

  @override
  SessionConfigurationCapabilities get sessionConfigurationCapabilities =>
      const SessionConfigurationCapabilities(
        minimumItemCount: 1,
        maximumItemCount: 100,
        defaultItemCount: 10,
        directions: <SessionDirection>{SessionDirection.mixed},
        difficulties: <SessionDifficulty>{SessionDifficulty.standard},
        maximumHintBudget: 2,
        supportsTimed: true,
        supportsUntimedAlternative: true,
        supportsPackSelection: false,
      );

  @override
  HintPolicy get hintPolicy => HintPolicy.staged(
    strategy: 'Recall the spelling pattern before entering the whole word.',
    context: 'Use the available meaning, audio, or sentence context.',
  );

  TypedRecallEvaluation evaluate({
    required TypedRecallPrompt prompt,
    required String response,
    required TypedRecallSupport support,
  }) {
    _validatePrompt(prompt);
    if (response.runes.length > maxAnswerScalars) {
      throw ArgumentError.value(
        response.runes.length,
        'response',
        'must not exceed $maxAnswerScalars Unicode scalars',
      );
    }
    final normalizedResponse = _normalize(
      response,
      revision: prompt.normalizationRevision,
    );
    final canonicalKey = _normalize(
      prompt.canonicalAnswer,
      revision: prompt.normalizationRevision,
    );
    final acceptedKeys = <String>{
      for (final variant in prompt.acceptedVariants)
        _normalize(variant, revision: prompt.normalizationRevision),
    }..remove(canonicalKey);
    final responseCode = normalizedResponse == canonicalKey
        ? TypedRecallResponseCode.exact
        : acceptedKeys.contains(normalizedResponse)
        ? TypedRecallResponseCode.acceptedVariant
        : TypedRecallResponseCode.incorrect;
    final hintLevel = _supportLevel(support);
    final evaluation = TypedRecallEvaluation._(
      isCorrect: responseCode != TypedRecallResponseCode.incorrect,
      responseCode: responseCode,
      evidenceClass: hintLevel == 0
          ? EvidenceClass.independentRecall
          : EvidenceClass.guidedPractice,
      hintLevel: hintLevel,
      normalizationRevision: prompt.normalizationRevision,
      promptKind: prompt.promptKind,
    );
    if (evaluation.controlledResponseCode.length > 32 ||
        evaluation.providerProvenance.length > 96) {
      throw StateError('typed recall controlled response identity is invalid');
    }
    return evaluation;
  }

  CapturedTypedRecallSubmission capture({
    required CurrentActivityEvidenceAdapter evidence,
    required String sessionId,
    required TypedRecallPrompt prompt,
    required String response,
    required int? responseTimeMs,
    required int attemptNumber,
    required TypedRecallSupport support,
  }) {
    final evaluation = evaluate(
      prompt: prompt,
      response: response,
      support: support,
    );
    final answerSetChecksum = typedRecallAnswerSetChecksumSha256(
      coreChecksumSha256: prompt.contentChecksumSha256,
      acceptedVariantsRevision: prompt.acceptedVariantsRevision,
      acceptedVariantsChecksumSha256: prompt.acceptedVariantsChecksumSha256,
    );
    final pending = evidence.captureTypedRecall(
      sessionId: sessionId,
      wordId: prompt.wordId,
      isCorrect: evaluation.isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      contentRevision: prompt.contentRevision,
      checksumSha256: answerSetChecksum,
      contextual: prompt.promptKind == TypedRecallPromptKind.context,
      providerProvenance: evaluation.providerProvenance,
      classification: HintEvidenceClassification(
        evidenceClass: evaluation.evidenceClass,
        hintLevel: evaluation.hintLevel,
      ),
    );
    return CapturedTypedRecallSubmission(
      evaluation: evaluation,
      pending: pending,
    );
  }

  TypedRecallQuizReviewController createQuizReview({
    required QuizSession session,
    MeaningQuizModeAdapter meaningQuiz = const MeaningQuizModeAdapter(),
    required LearningUseCases learning,
    required CurrentActivityEvidenceAdapter evidence,
    TypedRecallSupportUsage? supportUsage,
    TypedRecallHintReset? resetHintsAfterCommit,
    TypedRecallQuizSessionCompleter? completeSession,
    TypedRecallInteractionRecorder? recordInteraction,
    TypedRecallOperationAcceptance? acceptsOperation,
    TypedRecallEvidenceOperation? runEvidenceOperation,
  }) {
    if (session.isEmpty) {
      throw ArgumentError.value(session, 'session', 'must contain a question');
    }
    if (!identical(evidence.learning, learning)) {
      throw ArgumentError(
        'Typed recall evidence must use the session LearningUseCases authority.',
      );
    }
    final questions = meaningQuiz.pinQuestions(session);
    final typedPrompts = <TypedRecallPrompt?>[
      for (final question in questions)
        if (question.direction == MeaningQuizDirection.meaningToWord)
          pinQuizPrompt(question.word)
        else
          null,
    ];
    return TypedRecallQuizReviewController._(
      adapter: this,
      session: session,
      questions: questions,
      typedPrompts: typedPrompts,
      learning: learning,
      evidence: evidence,
      supportUsage: supportUsage ?? () => const TypedRecallSupport.unassisted(),
      resetHintsAfterCommit: resetHintsAfterCommit ?? () {},
      completeSession:
          completeSession ??
          (close) => close.requiresRetry ? close.retry() : close.finish(),
      recordInteraction: recordInteraction ?? () {},
      acceptsOperation: acceptsOperation ?? () => true,
      runEvidenceOperation: runEvidenceOperation ?? (operation) => operation(),
    );
  }

  TypedRecallPrompt pinQuizPrompt(QuizWord word) {
    final contentRevision = word.contentRevision;
    final checksum = word.contentChecksumSha256;
    if (contentRevision == null || checksum == null) {
      throw StateError('typed recall lexical content identity is unavailable');
    }
    final prompt = TypedRecallPrompt(
      wordId: word.id,
      canonicalAnswer: word.normalizedSpelling ?? word.spelling,
      acceptedVariants: word.acceptedSpellingVariants,
      acceptedVariantsRevision: word.acceptedSpellingVariantsRevision,
      acceptedVariantsChecksumSha256:
          word.acceptedSpellingVariantsChecksumSha256,
      promptKind: TypedRecallPromptKind.meaning,
      normalizationRevision: typedRecallNormalizationRevisionV1,
      contentRevision: contentRevision,
      contentChecksumSha256: checksum,
    );
    validateSubmission(prompt: prompt, response: '');
    return prompt;
  }

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final provenance = response.providerProvenance;
    if (provenance == null) {
      throw StateError('typed recall controlled response code is unavailable');
    }
    final parts = provenance.split(':');
    if (parts.length != 4 || parts.first != 'typed-recall') {
      throw StateError('typed recall controlled response code is invalid');
    }
    final revision = parts[1];
    if (revision != typedRecallNormalizationRevisionV1) {
      throw StateError('typed recall normalization revision is unsupported');
    }
    final promptKind = _enumByName(TypedRecallPromptKind.values, parts[2]);
    final responseCode = _responseCode(parts[3]);
    final expectedPromptMode = promptKind == TypedRecallPromptKind.context
        ? 'associativeRecall'
        : 'typedRecall';
    final expectedSkill = promptKind == TypedRecallPromptKind.context
        ? 'associative-recall'
        : 'typed-recall';
    final context = support.evidenceContext;
    final unassisted =
        context.hintLevel == 0 &&
        context.evidenceClass == EvidenceClass.independentRecall;
    final assisted =
        context.hintLevel > 0 &&
        context.evidenceClass == EvidenceClass.guidedPractice;
    final correctCode = responseCode != TypedRecallResponseCode.incorrect;
    final expectedContentPrefix = 'lexical-typed-recall:${response.wordId}@';
    final contentIdentity = context.contentRevision;
    final contentIdentityPattern = RegExp(
      r'^lexical-typed-recall:[^@]+@[1-9][0-9]*:[0-9a-f]{64}$',
    );
    if (response.promptMode != expectedPromptMode ||
        context.skillId != expectedSkill ||
        !contentIdentity.startsWith(expectedContentPrefix) ||
        !contentIdentityPattern.hasMatch(contentIdentity) ||
        (!unassisted && !assisted) ||
        response.isCorrect != correctCode) {
      throw StateError(
        'Typed recall requires approved normalized and assistance-aware evidence.',
      );
    }
    return context;
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('TypedRecallQuizReviewController owns pinned item selection.'),
  );

  void validateSubmission({
    required TypedRecallPrompt prompt,
    required String response,
  }) {
    _validatePrompt(prompt);
    if (response.runes.length > maxAnswerScalars) {
      throw ArgumentError.value(
        response.runes.length,
        'response',
        'must not exceed $maxAnswerScalars Unicode scalars',
      );
    }
  }

  void _validatePrompt(TypedRecallPrompt prompt) {
    if (prompt.normalizationRevision != typedRecallNormalizationRevisionV1) {
      throw StateError('typed recall normalization revision is unsupported');
    }
    if (prompt.contentRevision <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(prompt.contentChecksumSha256)) {
      throw StateError('typed recall content revision is unsupported');
    }
    final hasAcceptedVariantSource =
        prompt.acceptedVariantsRevision != null ||
        prompt.acceptedVariantsChecksumSha256 != null;
    if (prompt.acceptedVariants.isEmpty) {
      if (hasAcceptedVariantSource) {
        throw StateError(
          'typed recall variant identity requires configured variants',
        );
      }
    } else {
      final variantRevision = prompt.acceptedVariantsRevision;
      final variantChecksum = prompt.acceptedVariantsChecksumSha256;
      if (variantRevision == null ||
          variantRevision != prompt.contentRevision ||
          variantChecksum == null ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(variantChecksum)) {
        throw StateError('typed recall variant identity is unsupported');
      }
    }
    if (prompt.wordId.isEmpty ||
        prompt.wordId != prompt.wordId.trim() ||
        prompt.wordId.runes.length > 256) {
      throw ArgumentError.value(prompt.wordId, 'wordId', 'invalid identity');
    }
    _validateAnswer(prompt.canonicalAnswer, 'canonicalAnswer');
    if (prompt.acceptedVariants.length > maxAcceptedVariants) {
      throw ArgumentError.value(
        prompt.acceptedVariants.length,
        'acceptedVariants',
        'must contain at most $maxAcceptedVariants values',
      );
    }
    final seen = <String>{
      _normalize(
        prompt.canonicalAnswer,
        revision: prompt.normalizationRevision,
      ),
    };
    for (final variant in prompt.acceptedVariants) {
      _validateAnswer(variant, 'acceptedVariants');
      final normalized = _normalize(
        variant,
        revision: prompt.normalizationRevision,
      );
      if (!seen.add(normalized)) {
        throw ArgumentError.value(
          prompt.acceptedVariants,
          'acceptedVariants',
          'must be normalization-distinct',
        );
      }
    }
  }

  void _validateAnswer(String value, String field) {
    if (value.trim().isEmpty || value.runes.length > maxAnswerScalars) {
      throw ArgumentError.value(
        value,
        field,
        'must be nonblank and at most $maxAnswerScalars Unicode scalars',
      );
    }
  }

  String _normalize(String value, {required String revision}) {
    if (revision != typedRecallNormalizationRevisionV1) {
      throw StateError('typed recall normalization revision is unsupported');
    }
    final decomposed = StringBuffer();
    for (final scalar in value.runes) {
      decomposed.write(
        _canonicalLatinDecomposition[scalar] ?? String.fromCharCode(scalar),
      );
    }
    return decomposed
        .toString()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  int _supportLevel(TypedRecallSupport support) {
    final hintLevel = switch (support.hint.availability) {
      HintAvailability.available => support.hint.hintLevel,
      HintAvailability.unavailable => 0,
      HintAvailability.unknown => 2,
    };
    if (hintLevel == null || hintLevel < 0 || hintLevel > 2) {
      throw StateError('typed recall hint snapshot is invalid');
    }
    if (support.additionalSupportUsed && hintLevel == 0) return 1;
    return hintLevel;
  }

  T _enumByName<T extends Enum>(Iterable<T> values, String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw StateError('typed recall prompt kind is unsupported');
  }

  TypedRecallResponseCode _responseCode(String code) {
    for (final value in TypedRecallResponseCode.values) {
      if (value.code == code) return value;
    }
    throw StateError('typed recall response code is unsupported');
  }
}

/// Mixed Quiz controller: the word-to-meaning leg remains f07 recognition,
/// while meaning-to-word is reduced by [TypedRecallModeAdapter].
final class TypedRecallQuizReviewController extends ChangeNotifier {
  TypedRecallQuizReviewController._({
    required this.session,
    required List<MeaningQuizQuestion> questions,
    required List<TypedRecallPrompt?> typedPrompts,
    required this._adapter,
    required this._learning,
    required this._evidence,
    required this._supportUsage,
    required this._resetHintsAfterCommit,
    required this._completeSession,
    required this._recordInteraction,
    required this._acceptsOperation,
    required this._runEvidenceOperation,
  }) : questions = List<MeaningQuizQuestion>.unmodifiable(questions),
       _typedPrompts = List<TypedRecallPrompt?>.unmodifiable(typedPrompts) {
    if (questions.length != typedPrompts.length) {
      throw ArgumentError('typed prompt count must match quiz questions');
    }
  }

  final QuizSession session;
  final List<MeaningQuizQuestion> questions;
  final List<TypedRecallPrompt?> _typedPrompts;
  final TypedRecallModeAdapter _adapter;
  final LearningUseCases _learning;
  final CurrentActivityEvidenceAdapter _evidence;
  final TypedRecallSupportUsage _supportUsage;
  final TypedRecallHintReset _resetHintsAfterCommit;
  final TypedRecallQuizSessionCompleter _completeSession;
  final TypedRecallInteractionRecorder _recordInteraction;
  final TypedRecallOperationAcceptance _acceptsOperation;
  final TypedRecallEvidenceOperation _runEvidenceOperation;

  var _index = 0;
  var _phase = MeaningQuizReviewPhase.awaitingAnswer;
  PendingCurrentActivityEvidence? _pendingEvidence;
  FrozenAnswerFeedbackContext? _pendingFeedbackContext;
  PendingLearningSessionClose? _pendingClose;
  AnswerFeedback? _feedback;
  String? _selectedOption;
  TypedRecallResponseCode? _typedResponseCode;
  bool _disposed = false;

  int get index => _index;
  MeaningQuizReviewPhase get phase => _phase;
  MeaningQuizQuestion get currentQuestion => questions[_index];
  AnswerFeedback? get feedback => _feedback;
  String? get selectedOption => _selectedOption;
  TypedRecallResponseCode? get typedResponseCode => _typedResponseCode;
  bool get expectsTypedResponse =>
      currentQuestion.direction == MeaningQuizDirection.meaningToWord;
  bool get isAnswered => _phase == MeaningQuizReviewPhase.answered;
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

  Future<AnswerRecordResult> answerChoice({
    required String option,
    required int responseTimeMs,
  }) {
    _requireAwaiting('answer');
    final question = currentQuestion;
    if (question.direction != MeaningQuizDirection.wordToMeaning) {
      throw StateError('This quiz item requires a typed response.');
    }
    if (!question.options.contains(option)) {
      throw ArgumentError.value(option, 'option', 'is not a pinned option');
    }
    _validateResponseTime(responseTimeMs);
    final feedbackContext = AnswerFeedbackContext(
      canonicalCorrectAnswer: question.correctOption,
    ).freeze();
    final hintLevel = _adapter._supportLevel(_supportUsage());
    _recordInteraction();
    final pending = _evidence.captureSupportedMeaningRecognition(
      sessionId: session.id,
      wordId: question.word.id,
      isCorrect: option == question.correctOption,
      responseTimeMs: responseTimeMs,
      attemptNumber: _index + 1,
      classification: HintEvidenceClassification(
        evidenceClass: hintLevel == 0
            ? EvidenceClass.recognition
            : EvidenceClass.guidedPractice,
        hintLevel: hintLevel,
      ),
    );
    _selectedOption = option;
    return _startEvidence(pending, feedbackContext: feedbackContext);
  }

  Future<AnswerRecordResult> answerTyped({
    required String response,
    required int responseTimeMs,
  }) {
    _requireAwaiting('answer');
    final question = currentQuestion;
    if (question.direction != MeaningQuizDirection.meaningToWord) {
      throw StateError('This quiz item requires a selected response.');
    }
    _validateResponseTime(responseTimeMs);
    final feedbackContext = AnswerFeedbackContext(
      canonicalCorrectAnswer: question.correctOption,
    ).freeze();
    _recordInteraction();
    final prompt = _typedPrompts[_index];
    if (prompt == null) throw StateError('typed recall prompt is unavailable');
    final captured = _adapter.capture(
      evidence: _evidence,
      sessionId: session.id,
      prompt: prompt,
      response: response,
      responseTimeMs: responseTimeMs,
      attemptNumber: _index + 1,
      support: _supportUsage(),
    );
    _typedResponseCode = captured.evaluation.responseCode;
    return _startEvidence(captured.pending, feedbackContext: feedbackContext);
  }

  Future<AnswerRecordResult> _startEvidence(
    PendingCurrentActivityEvidence pending, {
    required FrozenAnswerFeedbackContext feedbackContext,
  }) {
    _pendingEvidence = pending;
    _pendingFeedbackContext = feedbackContext;
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
    final feedbackContext = _pendingFeedbackContext;
    if (pending == null || !pending.requiresRetry || feedbackContext == null) {
      throw StateError('Exact typed recall retry is unavailable.');
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
      _feedback = AnswerFeedback.fromFrozenCommittedResult(
        result: result,
        context: feedbackContext,
      );
      _pendingEvidence = null;
      _pendingFeedbackContext = null;
      try {
        _resetHintsAfterCommit();
      } on Object {
        // Evidence is durable and feedback is frozen. Route-local hint cleanup
        // must never manufacture a retryable persistence failure.
      }
      _setPhase(MeaningQuizReviewPhase.answered);
      return result;
    } catch (_) {
      if (pending.requiresRetry) {
        _setPhase(MeaningQuizReviewPhase.evidenceRetryRequired);
      } else {
        _pendingEvidence = null;
        _pendingFeedbackContext = null;
        _selectedOption = null;
        _typedResponseCode = null;
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
      _typedResponseCode = null;
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

  void _validateResponseTime(int responseTimeMs) {
    if (responseTimeMs < 0) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must not be negative',
      );
    }
  }

  void _requireAwaiting(String action) {
    _requireOperationAccepted();
    _requirePhase(MeaningQuizReviewPhase.awaitingAnswer, action);
  }

  void _requireOperationAccepted() {
    _requireNotDisposed();
    if (!_acceptsOperation()) {
      throw StateError(
        'The typed recall route is no longer accepting actions.',
      );
    }
  }

  void _requirePhase(MeaningQuizReviewPhase required, String action) {
    _requireNotDisposed();
    if (_phase != required) {
      throw StateError('Cannot $action typed recall from ${_phase.name}.');
    }
  }

  void _requireNotDisposed() {
    if (_disposed) throw StateError('Typed recall review is disposed.');
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
