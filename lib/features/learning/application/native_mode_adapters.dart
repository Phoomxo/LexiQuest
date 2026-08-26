import '../domain/evidence_context.dart';
import '../domain/hint_policy.dart';
import '../domain/lesson_mode.dart';
import '../../media_practice/domain/media_practice_contracts.dart';
import 'current_activity_evidence.dart';
import 'typed_recall_mode_adapter.dart';

final class NativeModeEvaluation {
  const NativeModeEvaluation._({
    required this.isCorrect,
    required this.evidenceClass,
    required this.hintLevel,
    required this.skillId,
    required this.promptMode,
    required this.providerProvenance,
  });

  final bool isCorrect;
  final EvidenceClass evidenceClass;
  final int hintLevel;
  final String skillId;
  final String promptMode;
  final String providerProvenance;
}

/// One immutable typed submission. Screens may render [evaluation], but only
/// the adapter creates the canonical pending evidence command.
final class CapturedNativeModeSubmission {
  const CapturedNativeModeSubmission({
    required this.evaluation,
    required this.pending,
  });

  final NativeModeEvaluation evaluation;
  final PendingCurrentActivityEvidence pending;
}

abstract base class _NativeModeAdapter implements LessonModeAdapter {
  const _NativeModeAdapter({
    required this.mode,
    required this.promptModes,
    required this.skillId,
    required this.evidenceClasses,
    required this.provenancePrefix,
    required this.correctCodes,
    required this.incorrectCodes,
  });

  @override
  final LessonMode mode;
  final Set<String> promptModes;
  final String skillId;
  final Set<EvidenceClass> evidenceClasses;
  final String provenancePrefix;
  final Set<String> correctCodes;
  final Set<String> incorrectCodes;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final context = support.evidenceContext;
    final provenance = response.providerProvenance;
    final code = provenance == null || !provenance.startsWith(provenancePrefix)
        ? null
        : provenance.substring(provenancePrefix.length).split(':').last;
    final correctnessMatches =
        code != null &&
        (response.isCorrect
            ? correctCodes.contains(code)
            : incorrectCodes.contains(code));
    final supportMatches = switch (context.evidenceClass) {
      EvidenceClass.independentRecall => context.hintLevel == 0,
      EvidenceClass.guidedPractice => context.hintLevel > 0,
      _ => context.hintLevel == 0,
    };
    if (!promptModes.contains(response.promptMode) ||
        context.skillId != skillId ||
        !evidenceClasses.contains(context.evidenceClass) ||
        !supportMatches ||
        !correctnessMatches) {
      throw StateError('${mode.id} evidence declaration is invalid.');
    }
    return context;
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('${mode.id} keeps item selection in its domain repository.'),
  );
}

final class AssociativeReadingModeAdapter extends _NativeModeAdapter
    implements
        FocusTimerSupportingLessonModeAdapter,
        HintSupportingLessonModeAdapter {
  const AssociativeReadingModeAdapter()
    : super(
        mode: LessonMode.associativeReading,
        promptModes: const <String>{'associativeRecall'},
        skillId: 'associative-recall',
        evidenceClasses: const <EvidenceClass>{
          EvidenceClass.independentRecall,
          EvidenceClass.guidedPractice,
        },
        provenancePrefix: 'native-associative:v1:',
        correctCodes: const <String>{'exact', 'accepted-variant'},
        incorrectCodes: const <String>{'incorrect'},
      );

  @override
  HintPolicy get hintPolicy => const TypedRecallModeAdapter().hintPolicy;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      const TypedRecallModeAdapter().classify(response, support);
}

final class DictationModeAdapter extends _NativeModeAdapter
    implements FocusTimerSupportingLessonModeAdapter {
  const DictationModeAdapter()
    : super(
        mode: LessonMode.dictation,
        promptModes: const <String>{'dictation'},
        skillId: 'dictation-spelling',
        evidenceClasses: const <EvidenceClass>{
          EvidenceClass.independentRecall,
          EvidenceClass.guidedPractice,
        },
        provenancePrefix: 'native-dictation:v1:',
        correctCodes: const <String>{'exact'},
        incorrectCodes: const <String>{'incorrect'},
      );

  NativeModeEvaluation evaluate({
    required String target,
    required String response,
    required bool supportUsed,
  }) {
    _validateLearnerText(target, 'target');
    _validateLearnerText(response, 'response', allowEmpty: true);
    final isCorrect = _normalizeLexical(response) == _normalizeLexical(target);
    return NativeModeEvaluation._(
      isCorrect: isCorrect,
      evidenceClass: supportUsed
          ? EvidenceClass.guidedPractice
          : EvidenceClass.independentRecall,
      hintLevel: supportUsed ? 1 : 0,
      skillId: skillId,
      promptMode: promptModes.single,
      providerProvenance:
          'native-dictation:v1:${isCorrect ? 'exact' : 'incorrect'}',
    );
  }

  CapturedNativeModeSubmission capture({
    required CurrentActivityEvidenceAdapter evidence,
    required String sessionId,
    required String wordId,
    required String target,
    required String response,
    required bool supportUsed,
    required int? responseTimeMs,
    required int attemptNumber,
  }) {
    final evaluation = evaluate(
      target: target,
      response: response,
      supportUsed: supportUsed,
    );
    return CapturedNativeModeSubmission(
      evaluation: evaluation,
      pending: evidence.capture(
        input: CurrentActivityInput.dictation,
        sessionId: sessionId,
        wordId: wordId,
        isCorrect: evaluation.isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: evaluation.providerProvenance,
        hintLevel: evaluation.hintLevel,
      ),
    );
  }
}

final class SpeakingModeAdapter extends _NativeModeAdapter
    implements TrustworthyActiveEffortLessonModeAdapter {
  const SpeakingModeAdapter()
    : super(
        mode: LessonMode.speaking,
        promptModes: const <String>{'pronunciationTranscript'},
        skillId: 'pronunciation-transcript',
        evidenceClasses: const <EvidenceClass>{EvidenceClass.pronunciation},
        provenancePrefix: 'native-speaking:v1:',
        correctCodes: const <String>{'exact'},
        incorrectCodes: const <String>{'nonexact'},
      );

  NativeModeEvaluation evaluate({
    required TranscriptPronunciationAssessment assessment,
  }) => _speechEvaluation(
    adapter: this,
    assessment: assessment,
    isCorrect: assessment.isExactMatch,
    code: assessment.isExactMatch ? 'exact' : 'nonexact',
  );

  CapturedNativeModeSubmission capture({
    required CurrentActivityEvidenceAdapter evidence,
    required String sessionId,
    required String wordId,
    required TranscriptPronunciationAssessment assessment,
    required int? responseTimeMs,
    required int attemptNumber,
  }) {
    final evaluation = evaluate(assessment: assessment);
    return CapturedNativeModeSubmission(
      evaluation: evaluation,
      pending: evidence.capture(
        input: CurrentActivityInput.speakToText,
        sessionId: sessionId,
        wordId: wordId,
        isCorrect: evaluation.isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: evaluation.providerProvenance,
      ),
    );
  }
}

final class ShadowingModeAdapter extends _NativeModeAdapter
    implements TrustworthyActiveEffortLessonModeAdapter {
  const ShadowingModeAdapter()
    : super(
        mode: LessonMode.shadowing,
        promptModes: const <String>{'shadowing'},
        skillId: 'shadowing-pronunciation',
        evidenceClasses: const <EvidenceClass>{EvidenceClass.pronunciation},
        provenancePrefix: 'native-shadowing:v1:',
        correctCodes: const <String>{'threshold-pass'},
        incorrectCodes: const <String>{'threshold-fail'},
      );

  static const int similarityThresholdPercent = 80;

  NativeModeEvaluation evaluate({
    required TranscriptPronunciationAssessment assessment,
  }) {
    final isCorrect =
        assessment.similarityPercent >= similarityThresholdPercent;
    return _speechEvaluation(
      adapter: this,
      assessment: assessment,
      isCorrect: isCorrect,
      code: isCorrect ? 'threshold-pass' : 'threshold-fail',
    );
  }

  CapturedNativeModeSubmission capture({
    required CurrentActivityEvidenceAdapter evidence,
    required String sessionId,
    required String wordId,
    required TranscriptPronunciationAssessment assessment,
    required int? responseTimeMs,
    required int attemptNumber,
  }) {
    final evaluation = evaluate(assessment: assessment);
    return CapturedNativeModeSubmission(
      evaluation: evaluation,
      pending: evidence.capture(
        input: CurrentActivityInput.shadowing,
        sessionId: sessionId,
        wordId: wordId,
        isCorrect: evaluation.isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: evaluation.providerProvenance,
      ),
    );
  }
}

final class CefrReadingModeAdapter extends _NativeModeAdapter
    implements TrustworthyActiveEffortLessonModeAdapter {
  const CefrReadingModeAdapter()
    : super(
        mode: LessonMode.cefrReading,
        promptModes: const <String>{'readingExposure'},
        skillId: 'reading-exposure',
        evidenceClasses: const <EvidenceClass>{EvidenceClass.exposure},
        provenancePrefix: 'native-cefr-reading:v1:',
        correctCodes: const <String>{},
        incorrectCodes: const <String>{'exposure'},
      );

  static const Set<String> canonicalCefrLevels = <String>{
    'A1',
    'A2',
    'B1',
    'B2',
    'C1',
    'C2',
  };

  String requireCanonicalCefrLevel(String? level) {
    if (level == null || !canonicalCefrLevels.contains(level)) {
      throw StateError('CEFR reading requires a canonical vocabulary level.');
    }
    return level;
  }

  NativeModeEvaluation evaluate() => NativeModeEvaluation._(
    isCorrect: false,
    evidenceClass: EvidenceClass.exposure,
    hintLevel: 0,
    skillId: skillId,
    promptMode: promptModes.single,
    providerProvenance: 'native-cefr-reading:v1:exposure',
  );

  CapturedNativeModeSubmission capture({
    required CurrentActivityEvidenceAdapter evidence,
    required String sessionId,
    required String wordId,
    required int responseTimeMs,
    required int attemptNumber,
  }) {
    final evaluation = evaluate();
    return CapturedNativeModeSubmission(
      evaluation: evaluation,
      pending: evidence.capture(
        input: CurrentActivityInput.readingExposure,
        sessionId: sessionId,
        wordId: wordId,
        isCorrect: evaluation.isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: evaluation.providerProvenance,
      ),
    );
  }
}

final class SentenceScrambleModeAdapter extends _NativeModeAdapter {
  const SentenceScrambleModeAdapter()
    : super(
        mode: LessonMode.sentenceScramble,
        promptModes: const <String>{'sentenceScramble'},
        skillId: 'sentence-scramble',
        evidenceClasses: const <EvidenceClass>{EvidenceClass.recreational},
        provenancePrefix: 'native-sentence-scramble:v1:',
        correctCodes: const <String>{'correct'},
        incorrectCodes: const <String>{'incorrect'},
      );

  NativeModeEvaluation evaluate({
    required String target,
    required String response,
  }) {
    _validateLearnerText(target, 'target');
    _validateLearnerText(response, 'response', allowEmpty: true);
    final isCorrect = _normalizeSpacing(response) == _normalizeSpacing(target);
    return NativeModeEvaluation._(
      isCorrect: isCorrect,
      evidenceClass: EvidenceClass.recreational,
      hintLevel: 0,
      skillId: skillId,
      promptMode: promptModes.single,
      providerProvenance:
          'native-sentence-scramble:v1:${isCorrect ? 'correct' : 'incorrect'}',
    );
  }

  CapturedNativeModeSubmission capture({
    required CurrentActivityEvidenceAdapter evidence,
    required String sessionId,
    required String wordId,
    required String target,
    required String response,
    required int? responseTimeMs,
    required int attemptNumber,
  }) {
    final evaluation = evaluate(target: target, response: response);
    return CapturedNativeModeSubmission(
      evaluation: evaluation,
      pending: evidence.capture(
        input: CurrentActivityInput.sentenceScramble,
        sessionId: sessionId,
        wordId: wordId,
        isCorrect: evaluation.isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: evaluation.providerProvenance,
      ),
    );
  }
}

final class WordScrambleModeAdapter extends _NativeModeAdapter {
  const WordScrambleModeAdapter()
    : super(
        mode: LessonMode.wordScramble,
        promptModes: const <String>{'wordScramble'},
        skillId: 'word-scramble',
        evidenceClasses: const <EvidenceClass>{EvidenceClass.recreational},
        provenancePrefix: 'native-word-scramble:v1:',
        correctCodes: const <String>{'correct'},
        incorrectCodes: const <String>{'incorrect'},
      );

  NativeModeEvaluation evaluate({
    required String target,
    required String response,
  }) {
    _validateLearnerText(target, 'target');
    _validateLearnerText(response, 'response', allowEmpty: true);
    final isCorrect = response == target;
    return NativeModeEvaluation._(
      isCorrect: isCorrect,
      evidenceClass: EvidenceClass.recreational,
      hintLevel: 0,
      skillId: skillId,
      promptMode: promptModes.single,
      providerProvenance:
          'native-word-scramble:v1:${isCorrect ? 'correct' : 'incorrect'}',
    );
  }

  CapturedNativeModeSubmission capture({
    required CurrentActivityEvidenceAdapter evidence,
    required String sessionId,
    required String wordId,
    required String target,
    required String response,
    required int? responseTimeMs,
    required int attemptNumber,
  }) {
    final evaluation = evaluate(target: target, response: response);
    return CapturedNativeModeSubmission(
      evaluation: evaluation,
      pending: evidence.capture(
        input: CurrentActivityInput.wordScramble,
        sessionId: sessionId,
        wordId: wordId,
        isCorrect: evaluation.isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: evaluation.providerProvenance,
      ),
    );
  }
}

NativeModeEvaluation _speechEvaluation({
  required _NativeModeAdapter adapter,
  required TranscriptPronunciationAssessment assessment,
  required bool isCorrect,
  required String code,
}) {
  if (assessment.similarityPercent < 0 ||
      assessment.similarityPercent > 100 ||
      !assessment.occurredAtUtc.isUtc) {
    throw ArgumentError.value(assessment, 'assessment', 'is invalid');
  }
  for (final entry in <String>[
    assessment.engine,
    assessment.locale,
    assessment.method,
  ]) {
    if (!RegExp(r'^[A-Za-z0-9._-]{1,48}$').hasMatch(entry)) {
      throw ArgumentError.value(entry, 'assessment provenance', 'is invalid');
    }
  }
  final providerProvenance =
      '${adapter.provenancePrefix}${assessment.engine}|'
      '${assessment.locale}|${assessment.method}:$code';
  if (providerProvenance.runes.length > 96) {
    throw ArgumentError.value(
      providerProvenance.length,
      'assessment provenance',
      'must not exceed 96 Unicode scalars',
    );
  }
  return NativeModeEvaluation._(
    isCorrect: isCorrect,
    evidenceClass: EvidenceClass.pronunciation,
    hintLevel: 0,
    skillId: adapter.skillId,
    promptMode: adapter.promptModes.single,
    providerProvenance: providerProvenance,
  );
}

void _validateLearnerText(
  String value,
  String name, {
  bool allowEmpty = false,
}) {
  if (value.runes.length > 256 || (!allowEmpty && value.trim().isEmpty)) {
    throw ArgumentError.value(value, name, 'is invalid');
  }
}

String _normalizeLexical(String value) =>
    _normalizeSpacing(value).toLowerCase();

String _normalizeSpacing(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');
