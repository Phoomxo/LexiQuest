import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_star_policy.dart';
import 'pair_matching_evidence_contract_test.dart' show PairHarness;

void main() {
  for (final row in [
    (4, 4, 3),
    (4, 3, 2),
    (6, 6, 3),
    (6, 5, 2),
    (6, 4, 1),
    (4, 0, 1),
  ]) {
    test(
      'committed terminal ${row.$2}/${row.$1} independent gives ${row.$3} stars',
      () async {
        final h = PairHarness(
          density: row.$1 == 4 ? PairDensity.compact4 : PairDensity.standard6,
        );
        addTearDown(h.db.close);
        await h.initialize();
        final c = await h.restore();
        expect(
          PairStarPolicy.project(c.state, terminalAcknowledged: false).stars,
          isNull,
        );
        for (var index = 0; index < row.$1; index++) {
          final id = 'synthetic-$index';
          if (index >= row.$2) {
            await c.dispatch(
              PairRevealMapping(
                operationId: '${c.state.operationRevision}:reveal',
                ownerId: h.owner,
                sessionId: h.operation.plan.learningSessionId,
                roundOrdinal: c.state.roundOrdinal,
                expectedRevision: c.state.operationRevision,
                wordId: id,
              ),
            );
          }
          await h.tap(c, id, PairTileSide.prompt);
          await h.tap(c, id, PairTileSide.target);
        }
        expect(
          PairStarPolicy.project(c.state, terminalAcknowledged: false).stars,
          isNull,
        );
        final result = PairStarPolicy.project(
          c.state,
          terminalAcknowledged: true,
        );
        expect(result.stars, row.$3);
        expect(result.independent, row.$2);
        expect(result.assisted, row.$1 - row.$2);
        expect(result.matched, row.$1);
      },
    );
  }
  test(
    'delayed self correction is independent but cannot earn perfect stars',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-1', PairTileSide.target);
      for (final index in [1, 2, 0, 3]) {
        await h.tap(c, 'synthetic-$index', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$index', PairTileSide.target);
      }
      final result = PairStarPolicy.project(
        c.state,
        terminalAcknowledged: true,
      );
      expect(result.independent, 4);
      expect(result.stars, 2);
      expect(result.policyVersion, 1);
    },
  );
}
