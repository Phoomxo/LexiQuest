import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/rewards/domain/motivation_rewards.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  for (final type in [
    MotivationRewardPolicy.questXp,
    MotivationRewardPolicy.weeklyFreeze,
    MotivationRewardPolicy.protection,
  ]) {
    test(
      'remote $type is quarantined without minting or poisoning the cursor',
      () async {
        final h = await ConfiguredQuizHarness.open();
        addTearDown(h.close);
        final store = DriftSyncStore(h.database);
        final entity = SyncEntity(
          collection: SyncCollection.rewardTransactions,
          entityId: 'synthetic-remote-$type',
          revision: 1,
          isDeleted: false,
          payloadVersion: 1,
          clientUpdatedAtUtc: h.now,
          serverUpdatedAtUtc: h.now,
          payload: {
            'idempotencyKey': 'synthetic-remote-$type',
            'transactionType': type,
            'amount': type == MotivationRewardPolicy.protection ? -1 : 200,
            'itemId': null,
            'slot': 'theme',
            'catalogVersion': 1,
            'sourceEventId': 'synthetic-forged-quest-source',
            'occurredAtUtcMs': h.now.millisecondsSinceEpoch,
          },
        );
        final before = await h.snapshot();
        final page = PullPage(
          changes: [entity],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
            documentId: entity.entityId,
          ),
          hasMore: false,
        );
        await store.applyPullPage(
          ownerId: configuredOwnerId,
          collection: SyncCollection.rewardTransactions,
          page: page,
        );
        expect(
          await h.database.select(h.database.rewardTransactions).get(),
          isEmpty,
        );
        final conflicts = await h.database
            .select(h.database.syncConflicts)
            .get();
        expect(conflicts.single.outcome, 'quarantined');
        final checkpoint = await store.readCheckpoint(
          configuredOwnerId,
          SyncCollection.rewardTransactions,
        );
        expect(checkpoint!.documentId, entity.entityId);
        final after = await h.snapshot();
        after['sync_conflicts'] = before['sync_conflicts']!;
        after['sync_checkpoints'] = before['sync_checkpoints']!;
        expect(after, before);
        expect((await h.researchCounts()).values, everyElement(0));
        await store.applyPullPage(
          ownerId: configuredOwnerId,
          collection: SyncCollection.rewardTransactions,
          page: page,
        );
        expect(
          await h.database.select(h.database.rewardTransactions).get(),
          isEmpty,
        );
        expect(
          (await h.database.select(h.database.syncConflicts).get()),
          hasLength(1),
        );
      },
    );
  }
}
