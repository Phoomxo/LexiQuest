import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_achievement_share_reader.dart';

import '../quest/support/quest_repository_harness.dart';

void main() {
  test(
    'all five actual canonical achievement definitions are shareable pure reads',
    () async {
      final h = await QuestHarness.open();
      try {
        for (var i = 0; i < 10; i++) {
          await h.answer(
            id: 'synthetic-share-canonical-$i',
            at: h.now.add(Duration(milliseconds: i)),
          );
        }
        h.now = h.now.add(const Duration(seconds: 1));
        await h.learning.finishSession(
          ownerId: configuredOwnerId,
          sessionId: 'synthetic-learning-1',
          endedAtUtc: h.now,
        );
        final progress = await DriftProgressQueries(
          h.database,
        ).load(ownerId: configuredOwnerId, nowUtc: h.now);
        expect(progress.achievements.map((row) => row.id).toSet(), {
          'first_answer',
          'first_correct',
          'ten_correct',
          'first_session',
          'perfect_session',
        });
        final before = await h.storage.snapshot();
        final reader = DriftAchievementShareReader(
          h.database,
          h.storage.ownerWrites,
        );
        for (final achievement in progress.achievements) {
          await reader.requireEvidence(
            ownerId: configuredOwnerId,
            achievement: achievement,
            stillCurrent: () => true,
          );
        }
        expect(await h.storage.snapshot(), before);
      } finally {
        await h.close();
      }
    },
  );
}
