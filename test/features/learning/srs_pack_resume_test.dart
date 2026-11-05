import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';

import '../../support/authored_lexical_pack.dart';
import '../../support/srs_review_harness.dart';

void main() {
  test(
    'detail-origin SRS reopens retained words after an offline file is removed',
    () async {
      final h = await SrsReviewHarness.open();
      var sequence = 0;
      final packs = LearningPackUseCases(
        repository: DriftLearningPackRepository(
          database: h.database,
          ownerWrites: h.storage.ownerWrites,
        ),
        nowUtc: () => h.now,
        generateId: () => 'synthetic-resume-pack-${++sequence}',
      );
      addTearDown(() async {
        await packs.dispose();
        await h.close();
      });
      final owner = (await packs.captureOwner(stillCurrent: () => true))!;
      final stored = await packs.importPack(
        packs.prepareImport(
          scope: owner,
          pack: authoredLexicalPack(),
          pinned: true,
        ),
      );
      final detail = await packs.detail(owner, stored.id);
      final ids = [for (final binding in detail.bindings) binding.wordId];
      final origin = SrsPackOrigin(
        packId: stored.id,
        packageSha256: stored.packageSha256,
        requireVerifiedBytes: false,
      );
      final review = (await h.learning.prepareSrsReview(
        expectedOwnerId: configuredOwnerId,
        sourceWordIds: ids,
        packOrigin: origin,
        stillCurrent: () => true,
      ))!;
      await h.learning.startSrsReview(review, stillCurrent: () => true);
      await h.learning.saveSrsCardPosition(
        review,
        cardIndex: 0,
        revealed: true,
        stillCurrent: () => true,
      );
      await packs.changeCache(
        packs.prepareCacheChange(
          scope: owner,
          stored: stored,
          pinned: false,
          remove: true,
        ),
      );
      final cold = h.useCases(repository: DriftLearningRepository(h.database));
      final saved = await cold.resumeSrsReview(
        sessionId: review.id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(saved.review.packOrigin, origin);
      expect(saved.review.words.map((word) => word.id), ids);
      expect(
        (saved.cardIndex, saved.revealed, saved.answers.length),
        (0, true, 0),
      );
      expect(saved.review.id, review.id);
      expect(await h.storage.count('learning_sessions'), 1);
      expect(await h.storage.count('answer_attempts'), 0);
    },
  );
}
