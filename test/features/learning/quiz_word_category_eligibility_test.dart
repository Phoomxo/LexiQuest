import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  late ConfiguredQuizHarness h;
  late DriftLearningRepository repository;
  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    repository = DriftLearningRepository(
      h.database,
      ownerWrites: h.ownerWrites,
    );
  });
  tearDown(() => h.close());

  test(
    'live words under a tombstoned category are not eligible learning targets',
    () async {
      await h.database.customStatement(
        'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
        [configuredCategoryId],
      );
      final rows = await h.database
          .customSelect(
            'SELECT is_deleted FROM vocabulary_words WHERE owner_id = ?',
            variables: [Variable(configuredOwnerId)],
          )
          .get();
      expect(rows, hasLength(4));
      expect(rows.every((row) => row.read<int>('is_deleted') == 0), isTrue);
      expect(
        await repository.listQuizWords(ownerId: configuredOwnerId, limit: 100),
        isEmpty,
      );
      expect(
        await repository.listQuizWords(
          ownerId: configuredOwnerId,
          categoryId: configuredCategoryId,
          limit: 100,
        ),
        isEmpty,
      );
    },
  );

  test(
    'a word cannot borrow another owner category during partial remote ordering',
    () async {
      await h.database.customStatement(
        'UPDATE vocabulary_words SET category_id = ? WHERE owner_id = ?',
        [configuredOtherCategoryId, configuredOwnerId],
      );
      expect(
        await repository.listQuizWords(ownerId: configuredOwnerId, limit: 100),
        isEmpty,
      );
      expect(
        await repository.listQuizWords(
          ownerId: configuredOwnerId,
          categoryId: configuredOtherCategoryId,
          limit: 100,
        ),
        isEmpty,
      );
      expect(
        await repository.listQuizWords(
          ownerId: configuredOtherOwnerId,
          limit: 100,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'valid legacy word category and selected-ID paths preserve original order and limit',
    () async {
      expect(
        (await repository.listQuizWords(
          ownerId: configuredOwnerId,
          limit: 2,
        )).map((word) => word.id),
        configuredWordIds.take(2),
      );
      expect(
        (await repository.listQuizWords(
          ownerId: configuredOwnerId,
          categoryId: configuredCategoryId,
          limit: 1,
        )).single.id,
        configuredWordIds.first,
      );
      expect(
        (await repository.listQuizWords(
          ownerId: configuredOwnerId,
          wordIds: [configuredWordIds[3], configuredWordIds[1]],
          limit: 100,
        )).map((word) => word.id),
        [configuredWordIds[1], configuredWordIds[3]],
      );
      final original = (await repository.listQuizWords(
        ownerId: configuredOwnerId,
        limit: 1,
      )).single;
      expect(
        (
          original.spelling,
          original.meaning,
          original.partOfSpeech,
          original.contentRevision,
        ),
        ('station', 'สถานี', 'noun', 'local-vocabulary-v1:1'),
      );
    },
  );
}
