import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';

import 'pair_matching_evidence_contract_test.dart' show PairHarness;

void main() {
  test(
    'microsecond clock completion survives canonical storage and reopen',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final original = h.learning;
      final instant = DateTime.utc(2026, 9, 5, 0, 1, 0, 123, 456);
      h.learning = LearningUseCases(
        owners: original.owners,
        repository: original.repository,
        generateId: original.generateId,
        nowUtc: () => instant,
        buildInfo: original.buildInfo,
      );
      final c = await h.restore();
      for (final item in h.operation.plan.orderedLexicalItems) {
        await h.tap(c, item.wordId, PairTileSide.prompt);
        await h.tap(c, item.wordId, PairTileSide.target);
      }
      final summary = await c.finish();
      expect(summary.state, 'completed');
      expect(
        summary.endedAtUtc,
        DateTime.fromMillisecondsSinceEpoch(
          instant.millisecondsSinceEpoch,
          isUtc: true,
        ),
      );
      c.dispose();
      final reopened = await h.restore();
      expect(reopened.completedSummary?.endedAtUtc, summary.endedAtUtc);
      await reopened.markSummaryPresented();
      reopened.dispose();
      final presented = await h.restore();
      expect(presented.summaryPresented, isTrue);
      presented.dispose();
      expect(await h.db.select(h.db.learningSessions).get(), hasLength(1));
    },
  );
}
