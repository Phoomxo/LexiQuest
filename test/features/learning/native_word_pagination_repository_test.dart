import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/cloze_session_harness.dart' show ClozeSessionHarness;
import '../../support/configured_quiz_harness.dart';

void main() {
  late ClozeSessionHarness h;
  setUp(() async => h = await ClozeSessionHarness.open());
  tearDown(() => h.close());

  test(
    'optional null cursor preserves the exact old owned ordered limited read',
    () async {
      final before = await h.storage.snapshot();
      final original = await h.repository.listQuizWords(
        ownerId: configuredOwnerId,
        categoryId: configuredCategoryId,
        limit: 2,
      );
      final explicitNull = await h.repository.listQuizWords(
        ownerId: configuredOwnerId,
        categoryId: configuredCategoryId,
        afterWordId: null,
        limit: 2,
      );
      expect(original.map((word) => word.id), configuredWordIds.take(2));
      expect(
        explicitNull.map((word) => word.id),
        original.map((word) => word.id),
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'keyset pages are exclusive and retain owner category selected-ID filters',
    () async {
      final before = await h.storage.snapshot();
      final page = await h.repository.listQuizWords(
        ownerId: configuredOwnerId,
        categoryId: configuredCategoryId,
        afterWordId: configuredWordIds[1],
        limit: 2,
      );
      expect(page.map((word) => word.id), configuredWordIds.skip(2));
      expect(
        await h.repository.listQuizWords(
          ownerId: configuredOwnerId,
          categoryId: configuredCategoryId,
          afterWordId: configuredWordIds.last,
          limit: 100,
        ),
        isEmpty,
      );
      final selected = await h.repository.listQuizWords(
        ownerId: configuredOwnerId,
        wordIds: [
          configuredWordIds[3],
          configuredWordIds[1],
          'synthetic-configured-other-word',
        ],
        afterWordId: configuredWordIds.first,
        limit: 100,
      );
      expect(selected.map((word) => word.id), [
        configuredWordIds[1],
        configuredWordIds[3],
      ]);
      expect(
        await h.repository.listQuizWords(
          ownerId: configuredOwnerId,
          categoryId: configuredOtherCategoryId,
          afterWordId: '',
          limit: 100,
        ),
        isEmpty,
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'pagination retains 1..100 limit and deleted category exclusion',
    () async {
      for (final limit in [0, 101]) {
        await expectLater(
          h.repository.listQuizWords(
            ownerId: configuredOwnerId,
            afterWordId: configuredWordIds.first,
            limit: limit,
          ),
          throwsRangeError,
        );
      }
      await h.database.customStatement(
        'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
        [configuredCategoryId],
      );
      final before = await h.storage.snapshot();
      expect(
        await h.repository.listQuizWords(
          ownerId: configuredOwnerId,
          afterWordId: configuredWordIds.first,
          limit: 100,
        ),
        isEmpty,
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'null-category choice preserves earliest complete category and accepted order',
    () async {
      final original =
          (await h.prepare(ClozeVariant.choice))! as ChoiceClozeSession;
      await h.database.customStatement(
        'INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES (?,?,?, ?,1,1)',
        [
          'synthetic-small-owned-category',
          configuredOwnerId,
          'small owned',
          'small owned',
        ],
      );
      await h.storage.addWord(
        id: '000-small-a',
        spelling: 'first',
        meaning: 'synthetic first',
        categoryId: 'synthetic-small-owned-category',
      );
      await h.storage.addWord(
        id: '000-small-b',
        spelling: 'second',
        meaning: 'synthetic second',
        categoryId: 'synthetic-small-owned-category',
      );
      final before = await h.storage.snapshot();
      final prepared = await h.prepare(ClozeVariant.choice, categoryId: null);
      expect(prepared, isA<ChoiceClozeSession>());
      final choice = prepared! as ChoiceClozeSession;
      expect(choice.word.id, original.word.id);
      expect(
        choice.choices.map((word) => word.id),
        original.choices.map((word) => word.id),
      );
      expect(choice.evidenceContentRevision, original.evidenceContentRevision);
      expect(h.provider.requests, hasLength(2));
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'null-category choice scans an insufficient duplicate category only once',
    () async {
      final original =
          (await h.prepare(ClozeVariant.choice))! as ChoiceClozeSession;
      await h.database.customStatement(
        'INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES (?,?,?, ?,1,1)',
        [
          'synthetic-duplicate-owned-category',
          configuredOwnerId,
          'duplicate owned',
          'duplicate owned',
        ],
      );
      for (var index = 0; index < 100; index++) {
        await h.storage.addWord(
          id: '000-duplicate-${index.toString().padLeft(3, '0')}',
          spelling: 'same',
          meaning: 'synthetic duplicate $index',
          categoryId: 'synthetic-duplicate-owned-category',
        );
      }
      final before = await h.storage.snapshot();
      final reads = _VocabularyReads();
      final prepared = await h.database.runWithInterceptor(
        () => h.prepare(ClozeVariant.choice, categoryId: null),
        interceptor: reads,
      );
      expect(prepared, isA<ChoiceClozeSession>());
      final choice = prepared! as ChoiceClozeSession;
      expect(choice.word.id, original.word.id);
      expect(
        choice.choices.map((word) => word.id),
        original.choices.map((word) => word.id),
      );
      expect(reads.count, lessThanOrEqualTo(6));
      expect(h.provider.requests, hasLength(2));
      expect(await h.storage.snapshot(), before);
    },
  );
}

final class _VocabularyReads extends drift.QueryInterceptor {
  int count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.toLowerCase().contains('from "vocabulary_words"')) {
      count++;
    }
    return executor.runSelect(statement, args);
  }
}
