import '../application/learning_use_cases.dart';
import '../domain/learning_models.dart';
import '../domain/learning_evidence_contract.dart';

final class NativeExerciseCheckpointBinding {
  NativeExerciseCheckpointBinding({
    required this.learning,
    required this.display,
    required this.stillCurrent,
    this.resumeState,
  });

  final LearningUseCases learning;
  final AcceptedNativeExercise display;
  final NativeExerciseState? resumeState;
  final bool Function() stillCurrent;
  NativeExerciseState? state;
  NativeExerciseState? _draftBase;
  NativeExerciseDraft? _pendingDraft;
  NativeExerciseState? _answerBase;
  NativeAnswerInput? _pendingInput;
  NativeExerciseState? _finishBase;
  RecordAnswerCommand? answer;
  NativeFinishIntent? finishIntent;
  bool _retired = false;

  AcceptedNativeExercise get exercise => state?.exercise ?? display;
  bool get hasPendingDraft => _pendingDraft != null;
  bool get hasPendingInput => _pendingInput != null;
  Duration get acknowledgedLatency =>
      Duration(milliseconds: state?.checkpoint.draft.responseTimeMs ?? 0);
  int elapsedMilliseconds(Duration foreground) =>
      (acknowledgedLatency + foreground).inMilliseconds
          .clamp(0, LearningEvidenceContract.maxResponseTimeMs)
          .toInt();
  bool get _current => !_retired && stillCurrent();
  void retire() {
    _retired = true;
  }

  void _requireCurrent() {
    if (!_current) {
      throw StateError('Native checkpoint view is no longer current');
    }
  }

  NativeExerciseState _adopt(NativeExerciseState value) {
    _requireCurrent();
    if (value.exercise.id != display.id ||
        value.exercise.ownerId != display.ownerId ||
        value.plan.stableSerialization !=
            AcceptedNativePlan(display).stableSerialization) {
      throw StateError('Native checkpoint differs from its displayed snapshot');
    }
    state = value;
    answer ??= value.checkpoint.answer;
    return value;
  }

  Future<NativeExerciseState> initialize() async {
    _requireCurrent();
    final supplied = resumeState;
    if (supplied == null) {
      await learning.startNativeExercise(display, stillCurrent: () => _current);
      _requireCurrent();
      _adopt(
        await learning.readNativeExerciseState(
          display,
          stillCurrent: () => _current,
        ),
      );
    } else {
      if (!identical(supplied.exercise, display)) {
        throw StateError(
          'Native resume requires its issued displayed exercise',
        );
      }
      await learning.readNativeExerciseState(
        display,
        stillCurrent: () => _current,
      );
      _requireCurrent();
      _adopt(
        await learning.resumeNativeExercise(
          sessionId: display.id,
          expectedOwnerId: display.ownerId,
          stillCurrent: () => _current,
        ),
      );
    }
    final checkpoint = state!.checkpoint;
    if (checkpoint is PendingNativeAnswer) {
      _answerBase = state;
      _pendingInput = _input(exercise, checkpoint.draft);
    }
    if (checkpoint is ClosingNativeExercise) {
      _finishBase = state;
      finishIntent = NativeFinishIntent(
        exercise: exercise,
        answer: answer!,
        endedAtUtc: checkpoint.endedAtUtc,
      );
    }
    return state!;
  }

  Future<NativeExerciseState> saveDraft(NativeExerciseDraft? draft) async {
    _requireCurrent();
    _draftBase ??=
        state ?? (throw StateError('Native start is not acknowledged'));
    _pendingDraft ??=
        draft ?? (throw StateError('Original native draft is unavailable'));
    final saved = _adopt(
      await learning.saveNativeDraft(
        state: _draftBase!,
        draft: _pendingDraft!,
        stillCurrent: () => _current,
      ),
    );
    _draftBase = null;
    _pendingDraft = null;
    return saved;
  }

  Future<NativeExerciseState> saveAnswer(
    NativeExerciseDraft? draft, {
    Future<void> Function()? beforeCommit,
  }) async {
    _requireCurrent();
    _answerBase ??=
        state ?? (throw StateError('Native start is not acknowledged'));
    if (_pendingInput == null &&
        _answerBase!.checkpoint is AwaitingNativeAnswer) {
      await learning.prepareOrdinaryAnswer(
        expectedOwnerId: exercise.ownerId,
        sessionId: exercise.id,
        stillCurrent: () => _current,
      );
      _requireCurrent();
    }
    _pendingInput ??= _input(exercise, draft ?? state!.checkpoint.draft);
    final staged = _adopt(
      await learning.stageNativeAnswer(
        state: _answerBase!,
        input: _pendingInput!,
        stillCurrent: () => _current,
      ),
    );
    final original = staged.checkpoint.answer;
    if (original == null || answer?.id != original.id) {
      throw StateError('Native answer receipt changed');
    }
    await beforeCommit?.call();
    _requireCurrent();
    await learning.commitNativeAnswer(
      exercise,
      answer!,
      stillCurrent: () => _current,
    );
    final saved = _adopt(
      await learning.readNativeExerciseState(
        exercise,
        stillCurrent: () => _current,
      ),
    );
    _answerBase = null;
    _pendingInput = null;
    return saved;
  }

  Future<LearningSessionSummary> finish({
    Future<void> Function()? beforeCommit,
  }) async {
    _requireCurrent();
    if (state == null) throw StateError('Native start is not acknowledged');
    if (state!.completedSummary != null && finishIntent == null) {
      final saved = _adopt(
        await learning.readNativeExerciseState(
          exercise,
          stillCurrent: () => _current,
        ),
      );
      return saved.completedSummary ??
          (throw StateError('Canonical native result is unavailable'));
    }
    _finishBase ??= state;
    final staged = _adopt(
      await learning.stageNativeFinish(
        state: _finishBase!,
        stillCurrent: () => _current,
      ),
    );
    if (staged.completedSummary != null && finishIntent == null) {
      return staged.completedSummary!;
    }
    finishIntent ??= NativeFinishIntent(
      exercise: exercise,
      answer: answer!,
      endedAtUtc: staged.checkpoint.endedAtUtc!,
    );
    await beforeCommit?.call();
    _requireCurrent();
    final summary = await learning.finishNativeExercise(
      finishIntent!,
      stillCurrent: () => _current,
    );
    _adopt(
      await learning.readNativeExerciseState(
        exercise,
        stillCurrent: () => _current,
      ),
    );
    return summary;
  }

  NativeAnswerInput _input(
    AcceptedNativeExercise exercise,
    NativeExerciseDraft draft,
  ) {
    draft.validate(exercise);
    final elapsed = Duration(milliseconds: draft.responseTimeMs);
    return switch (exercise) {
      DictationSession() => DictationAnswerInput(
        exercise: exercise,
        response: draft.text,
        assisted: draft.assisted,
        responseTime: elapsed,
      ),
      WordScrambleSession() => WordScrambleAnswerInput(
        exercise: exercise,
        response: draft.text,
        tileSlots: draft.tileSlots,
        responseTime: elapsed,
      ),
      SentenceScrambleSession() => SentenceScrambleAnswerInput(
        exercise: exercise,
        response: draft.text,
        tileSlots: draft.tileSlots,
        responseTime: elapsed,
      ),
      TypedClozeSession() => TypedClozeAnswerInput(
        exercise: exercise,
        response: draft.text,
        responseTime: elapsed,
      ),
      ChoiceClozeSession() => ChoiceClozeAnswerInput(
        exercise: exercise,
        optionId:
            draft.optionId ??
            (throw StateError('Original native choice is unavailable')),
        responseTime: elapsed,
      ),
    };
  }
}
