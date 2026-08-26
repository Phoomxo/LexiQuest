import '../domain/evidence_context.dart';
import '../domain/lesson_mode.dart';

enum HandwritingSelfCheckSelection { looksCorrect, needsMorePractice }

enum HandwritingInputMethod { none, handwriting, typedAlternative, combined }

/// Explicit policy for the local scratchpad. This mode never creates a
/// learning command; its result is for learner reflection only.
final class HandwritingScratchpadDefaultPolicy {
  const HandwritingScratchpadDefaultPolicy();

  bool get writesSrs => false;
  bool get writesAssessment => false;
  bool get writesQuest => false;
  bool get writesStreak => false;
  bool get writesAchievement => false;
  bool get writesXp => false;
  bool get writesCoins => false;
}

final class HandwritingSelfCheckOutcome {
  const HandwritingSelfCheckOutcome._({
    required this.selection,
    required this.inputMethod,
    required this.responseCode,
    required this.evidenceClass,
    required this.policy,
  });

  final HandwritingSelfCheckSelection selection;
  final HandwritingInputMethod inputMethod;
  final String responseCode;
  final EvidenceClass evidenceClass;
  final HandwritingScratchpadDefaultPolicy policy;
}

/// Classification boundary for an explicitly learner-reported handwriting
/// check. It deliberately has no capture method: neither strokes nor typed
/// alternative text can become durable lesson evidence.
final class HandwritingSelfCheckAdapter implements LessonModeAdapter {
  const HandwritingSelfCheckAdapter();

  static const HandwritingScratchpadDefaultPolicy defaultPolicy =
      HandwritingScratchpadDefaultPolicy();

  @override
  LessonMode get mode => LessonMode.handwritingScratchpad;

  HandwritingSelfCheckOutcome selfCheck({
    required HandwritingSelfCheckSelection selection,
    required bool hasHandwriting,
    required bool hasTypedAlternative,
  }) {
    final inputMethod = switch ((hasHandwriting, hasTypedAlternative)) {
      (false, false) => HandwritingInputMethod.none,
      (true, false) => HandwritingInputMethod.handwriting,
      (false, true) => HandwritingInputMethod.typedAlternative,
      (true, true) => HandwritingInputMethod.combined,
    };
    final responseCode = inputMethod == HandwritingInputMethod.typedAlternative
        ? 'typed-alternative-self-check'
        : 'handwriting-self-check';
    return HandwritingSelfCheckOutcome._(
      selection: selection,
      inputMethod: inputMethod,
      responseCode: responseCode,
      evidenceClass: EvidenceClass.guidedPractice,
      policy: defaultPolicy,
    );
  }

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final context = support.evidenceContext;
    final isGuidedSelfCheck =
        response.promptMode == 'handwritingSelfCheck' &&
        context.evidenceClass == EvidenceClass.guidedPractice &&
        context.skillId == 'handwriting-self-check' &&
        context.hintLevel > 0;
    if (!isGuidedSelfCheck) {
      throw StateError('Handwriting self-check requires guided-only context.');
    }
    throw StateError(
      'Handwriting self-check is local-only and cannot create lesson evidence.',
    );
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('Handwriting scratchpad does not own session item selection.'),
  );
}
