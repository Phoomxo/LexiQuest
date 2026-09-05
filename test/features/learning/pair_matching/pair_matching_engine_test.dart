import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'pair_matching_source_composer_test.dart' as f;

void main() {
  for (final direction in PairDirection.values) {
    for (final first in PairTileSide.values) {
      test('neutral selection and prompt role $direction $first', () {
        final plan =
            (f.compose(
                      List.generate(4, f.fixture),
                      launch: f.intent(direction: direction),
                    )
                    as PairPlanReady)
                .plan;
        var state = PairMatchingState.initial(plan);
        PairMatchingTransition tap(String id, PairTileSide side) {
          final t = PairMatchingEngine.reduce(
            state,
            PairSelectTile(
              operationId: '${state.operationRevision}:tap',
              ownerId: plan.ownerId,
              sessionId: plan.learningSessionId,
              roundOrdinal: state.roundOrdinal,
              expectedRevision: state.operationRevision,
              tile: PairTile(side, id),
              responseTimeMs: 20,
            ),
          );
          state = t.state;
          return t;
        }

        expect(tap('synthetic-0', first).attempt, isNull);
        expect(tap('synthetic-0', first).state.selected, isNull);
        tap('synthetic-0', first);
        expect(tap('synthetic-1', first).attempt, isNull);
        final other = first == PairTileSide.prompt
            ? PairTileSide.target
            : PairTileSide.prompt;
        final wrong = tap('synthetic-2', other).attempt!;
        expect(
          wrong.promptWordId,
          first == PairTileSide.prompt ? 'synthetic-1' : 'synthetic-2',
        );
        expect(wrong.isCorrect, false);
        final tamperedPending = state.toJson();
        (tamperedPending['pending'] as Map)['targetWordId'] = 'synthetic-3';
        expect(
          () => PairMatchingState.fromJson(plan, tamperedPending),
          throwsFormatException,
        );
        expect(wrong.role, PairAttemptRole.firstOpportunity);
        expect(state.matchedWordIds, isEmpty);
        state = PairMatchingEngine.acknowledge(state, wrong.operationId);
        expect(state.matchedWordIds, isEmpty);
        tap(wrong.promptWordId, PairTileSide.prompt);
        final correct = tap(wrong.promptWordId, PairTileSide.target).attempt!;
        expect(correct.role, PairAttemptRole.independentRetry);
        state = PairMatchingEngine.acknowledge(state, correct.operationId);
        expect(state.matchedWordIds, {wrong.promptWordId});
        expect(() => state.matchedWordIds.add('bad'), throwsUnsupportedError);
      });
    }
  }
  test('duplicate payload conflict and stale owner/round are fenced', () {
    final plan = (f.compose(List.generate(4, f.fixture)) as PairPlanReady).plan;
    final initial = PairMatchingState.initial(plan);
    PairSelectTile command({
      String word = 'synthetic-0',
      String? owner,
      String? session,
      int round = 0,
    }) => PairSelectTile(
      operationId: '0:tap',
      ownerId: owner ?? plan.ownerId,
      sessionId: session ?? plan.learningSessionId,
      roundOrdinal: round,
      expectedRevision: 0,
      tile: PairTile(PairTileSide.prompt, word),
      responseTimeMs: 0,
    );
    final state = PairMatchingEngine.reduce(initial, command()).state;
    expect(
      identical(PairMatchingEngine.reduce(state, command()).state, state),
      true,
    );
    expect(
      () => PairMatchingEngine.reduce(state, command(word: 'synthetic-1')),
      throwsStateError,
    );
    expect(
      () => PairMatchingEngine.reduce(initial, command(owner: 'other')),
      throwsStateError,
    );
    expect(
      () => PairMatchingEngine.reduce(initial, command(round: 1)),
      throwsStateError,
    );
    expect(
      () => PairMatchingEngine.reduce(initial, command(session: 'other')),
      throwsStateError,
    );
  });
  test('later reveal preserves historical first opportunity on restore', () {
    final plan = (f.compose(List.generate(4, f.fixture)) as PairPlanReady).plan;
    var state = PairMatchingState.initial(plan);
    for (final tile in [
      const PairTile(PairTileSide.prompt, 'synthetic-0'),
      const PairTile(PairTileSide.target, 'synthetic-1'),
    ]) {
      state = PairMatchingEngine.reduce(
        state,
        PairSelectTile(
          operationId: '${state.operationRevision}:tap',
          ownerId: plan.ownerId,
          sessionId: plan.learningSessionId,
          roundOrdinal: 0,
          expectedRevision: state.operationRevision,
          tile: tile,
          responseTimeMs: 5,
        ),
      ).state;
    }
    state = PairMatchingEngine.acknowledge(state, state.pending!.operationId);
    state = PairMatchingEngine.reduce(
      state,
      PairRevealMapping(
        operationId: '${state.operationRevision}:reveal',
        ownerId: plan.ownerId,
        sessionId: plan.learningSessionId,
        roundOrdinal: 0,
        expectedRevision: state.operationRevision,
        wordId: 'synthetic-0',
      ),
    ).state;
    expect(
      PairMatchingState.fromJson(plan, state.toJson()).attempts.single.role,
      PairAttemptRole.firstOpportunity,
    );
    for (final tile in [
      const PairTile(PairTileSide.prompt, 'synthetic-0'),
      const PairTile(PairTileSide.target, 'synthetic-1'),
    ]) {
      state = PairMatchingEngine.reduce(
        state,
        PairSelectTile(
          operationId: '${state.operationRevision}:tap',
          ownerId: plan.ownerId,
          sessionId: plan.learningSessionId,
          roundOrdinal: 0,
          expectedRevision: state.operationRevision,
          tile: tile,
          responseTimeMs: 5,
        ),
      ).state;
    }
    state = PairMatchingEngine.acknowledge(state, state.pending!.operationId);
    final tampered = state.toJson();
    final guided = state.attempts.last;
    (tampered['attempts'] as List)[1] = PairAttemptRequested(
      operationId: guided.operationId,
      fingerprint: guided.fingerprint,
      promptWordId: guided.promptWordId,
      targetWordId: guided.targetWordId,
      roundOrdinal: guided.roundOrdinal,
      role: PairAttemptRole.independentRetry,
      responseTimeMs: guided.responseTimeMs,
    ).toJson();
    expect(
      () => PairMatchingState.fromJson(plan, tampered),
      throwsFormatException,
    );
  });
}
