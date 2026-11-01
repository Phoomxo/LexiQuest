import '../../../runtime/app_build_info.dart';
import '../domain/learning_models.dart';
import '../domain/matching_exercise.dart';

final class MatchingUseCases {
  const MatchingUseCases({
    required this.repository,
    required this.generateId,
    required this.nowUtc,
    required this.buildInfo,
    this.onLocalMutation,
  });
  final MatchingRepository repository;
  final String Function() generateId;
  final DateTime Function() nowUtc;
  final AppBuildInfo buildInfo;
  final void Function()? onLocalMutation;

  DateTime _now() => DateTime.fromMillisecondsSinceEpoch(
    nowUtc().toUtc().millisecondsSinceEpoch,
    isUtc: true,
  );

  Future<MatchingPlan?> prepare({
    required String expectedOwnerId,
    String? categoryId,
    Iterable<String>? wordIds,
    int limit = 4,
    required bool Function() stillCurrent,
  }) => repository.prepare(
    session: LearningSessionDraft(
      id: '${MatchingPlan.sessionPrefix}${generateId()}',
      ownerId: expectedOwnerId,
      activityType: MatchingPlan.activityType,
      startedAtUtc: _now(),
      appVersion: buildInfo.version,
      buildId: buildInfo.buildId,
    ),
    categoryId: categoryId,
    wordIds: wordIds,
    limit: limit,
    stillCurrent: stillCurrent,
  );

  Future<MatchingState> start(
    MatchingPlan plan, {
    required bool Function() stillCurrent,
  }) => repository.start(plan, stillCurrent: stillCurrent);

  Future<MatchingState> resume({
    required String sessionId,
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => repository.resume(
    sessionId: sessionId,
    expectedOwnerId: expectedOwnerId,
    stillCurrent: stillCurrent,
  );

  Future<MatchingState> saveSelection(
    MatchingState state, {
    required int? wordIndex,
    required int? meaningIndex,
    required bool Function() stillCurrent,
  }) => save(
    state,
    MatchingCheckpoint(
      phase: MatchingPhase.selecting,
      attemptCount: state.checkpoint.attemptCount,
      matched: state.checkpoint.matched,
      selectedWord: wordIndex,
      selectedMeaning: meaningIndex,
    ),
    stillCurrent: stillCurrent,
  );

  MatchingCheckpoint preparePair(
    MatchingState state, {
    required Duration responseTime,
  }) {
    final checkpoint = state.checkpoint;
    if (checkpoint.phase != MatchingPhase.selecting ||
        checkpoint.selectedWord == null ||
        checkpoint.selectedMeaning == null) {
      throw StateError('Select one word and one meaning first');
    }
    final next = MatchingCheckpoint(
      phase: MatchingPhase.pending,
      attemptCount: checkpoint.attemptCount,
      matched: checkpoint.matched,
      answer: MatchingPairIntent(
        id: 'attempt:matching:${state.plan.session.id}:${checkpoint.attemptCount + 1}',
        ordinal: checkpoint.attemptCount + 1,
        wordIndex: checkpoint.selectedWord!,
        meaningIndex: checkpoint.selectedMeaning!,
        occurredAtUtcMs: _now().millisecondsSinceEpoch,
        responseTimeMs: responseTime.inMilliseconds,
      ),
    );
    next.validate(state.plan);
    return next;
  }

  Future<MatchingState> save(
    MatchingState state,
    MatchingCheckpoint next, {
    required bool Function() stillCurrent,
  }) async {
    final result = await repository.save(
      state,
      next,
      stillCurrent: stillCurrent,
    );
    onLocalMutation?.call();
    return result;
  }

  Future<MatchingState> commit(
    MatchingState state, {
    required bool Function() stillCurrent,
  }) async {
    final result = await repository.commit(state, stillCurrent: stillCurrent);
    onLocalMutation?.call();
    return result;
  }

  Future<MatchingState> next(
    MatchingState state, {
    required bool Function() stillCurrent,
  }) => save(
    state,
    MatchingCheckpoint(
      phase: MatchingPhase.selecting,
      attemptCount: state.checkpoint.attemptCount,
      matched: state.checkpoint.matched,
    ),
    stillCurrent: stillCurrent,
  );

  MatchingCheckpoint prepareFinish(MatchingState state) {
    final checkpoint = state.checkpoint;
    final next = MatchingCheckpoint(
      phase: MatchingPhase.closing,
      attemptCount: checkpoint.attemptCount,
      matched: checkpoint.matched,
      endedAtUtcMs: _now().millisecondsSinceEpoch,
    );
    next.validate(state.plan);
    return next;
  }

  Future<MatchingState> finish(
    MatchingState state, {
    required bool Function() stillCurrent,
  }) async {
    final result = await repository.finish(state, stillCurrent: stillCurrent);
    onLocalMutation?.call();
    return result;
  }

  MatchingCheckpoint prepareAbandon(MatchingState state) => MatchingCheckpoint(
    phase: MatchingPhase.abandoned,
    attemptCount: state.checkpoint.attemptCount,
    matched: state.checkpoint.matched,
    endedAtUtcMs: _now().millisecondsSinceEpoch,
  );
}
