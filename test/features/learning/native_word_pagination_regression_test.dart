import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/cloze_content.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/cloze_session_harness.dart' show ClozeSessionHarness;
import '../../support/configured_quiz_harness.dart';
import '../../support/word_scramble_session_harness.dart'
    show WordScrambleSessionHarness;

void main() {
  for (final variant in ClozeVariant.values) {
    test(
      'Cloze ${variant.name} finds the same owned exercise after 100 unsupported phrases',
      () async {
        final h = await ClozeSessionHarness.open();
        try {
          final original = (await h.prepare(variant))!;
          await _prependPhrases(h.storage, 100);
          final firstPage = await h.repository.listQuizWords(
            ownerId: configuredOwnerId,
            categoryId: configuredCategoryId,
            limit: 100,
          );
          expect(firstPage, hasLength(100));
          expect(
            firstPage.any((word) => ClozeContent.supportsTarget(word.spelling)),
            isFalse,
          );
          final before = await h.storage.snapshot();
          final pages = _PageProbe();
          final prepared = await h.database.runWithInterceptor(
            () => h.prepare(variant),
            interceptor: pages,
          );
          expect(prepared, isNotNull);
          expect(prepared!.word.id, original.word.id);
          expect(
            prepared.evidenceContentRevision,
            original.evidenceContentRevision,
          );
          if (variant == ClozeVariant.choice) {
            expect(
              (prepared as ChoiceClozeSession).choices.map((word) => word.id),
              (original as ChoiceClozeSession).choices.map((word) => word.id),
            );
          }
          expect(pages.sizes, [100, 4]);
          expect(h.provider.requests, hasLength(2));
          expect(h.provider.transactionStates, everyElement(isFalse));
          expect(await h.storage.snapshot(), before);
        } finally {
          await h.close();
        }
      },
    );
  }

  test(
    'Word Scramble scans multiple 100-row pages to the first playable word',
    () async {
      final h = await WordScrambleSessionHarness.open();
      try {
        await _prependPhrases(h.storage, 200);
        final before = await h.storage.snapshot();
        final pages = _PageProbe();
        final prepared = await h.database.runWithInterceptor(
          h.prepare,
          interceptor: pages,
        );
        expect(prepared, isNotNull);
        expect(prepared!.word.id, configuredWordIds.first);
        expect(prepared.word.categoryId, configuredCategoryId);
        expect(pages.sizes, [100, 100, 4]);
        expect(await h.storage.snapshot(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'choice keeps only distinct normalized spellings across page boundaries',
    () async {
      final h = await ClozeSessionHarness.open();
      try {
        await _prependPhrases(h.storage, 100);
        for (var index = 0; index < 100; index++) {
          await h.storage.addWord(
            id: '001-duplicate-${index.toString().padLeft(3, '0')}',
            spelling: 'same',
            meaning: 'synthetic duplicate $index',
          );
        }
        await h.database.customStatement(
          'UPDATE vocabulary_words SET spelling = ? WHERE owner_id = ? AND id LIKE ?',
          ['same', configuredOwnerId, 'synthetic-configured-word-%'],
        );
        await h.storage.addWord(
          id: 'zz-distinct-a',
          spelling: 'different',
          meaning: 'synthetic distinct a',
        );
        await h.storage.addWord(
          id: 'zz-distinct-b',
          spelling: 'other',
          meaning: 'synthetic distinct b',
        );
        final before = await h.storage.snapshot();
        final pages = _PageProbe();
        final prepared = await h.database.runWithInterceptor(
          () => h.prepare(ClozeVariant.choice),
          interceptor: pages,
        );
        expect(prepared, isA<ChoiceClozeSession>());
        final choice = prepared! as ChoiceClozeSession;
        expect(choice.word.id, '001-duplicate-000');
        expect(choice.choices.map((word) => word.id).toSet(), {
          '001-duplicate-000',
          'zz-distinct-a',
          'zz-distinct-b',
        });
        expect(
          choice.choices.map((word) => word.spelling.toLowerCase()).toSet(),
          {'same', 'different', 'other'},
        );
        expect(pages.sizes, [100, 100, 6]);
        expect(h.provider.requests, hasLength(1));
        expect(await h.storage.snapshot(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'page exhaustion never borrows a target from another owned category',
    () async {
      final h = await ClozeSessionHarness.open();
      try {
        await h.database.customStatement(
          'UPDATE vocabulary_words SET spelling = ? WHERE owner_id = ?',
          ['two words', configuredOwnerId],
        );
        await _prependPhrases(h.storage, 100);
        await h.database.customStatement(
          'INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES (?,?,?, ?,1,1)',
          [
            'synthetic-other-owned-category',
            configuredOwnerId,
            'other owned',
            'other owned',
          ],
        );
        await h.storage.addWord(
          id: 'zz-other-owned-word',
          spelling: 'playable',
          meaning: 'synthetic other owned meaning',
          categoryId: 'synthetic-other-owned-category',
        );
        final before = await h.storage.snapshot();
        expect(await h.prepare(ClozeVariant.typed), isNull);
        expect(await h.prepare(ClozeVariant.choice), isNull);
        expect(h.provider.requests, isEmpty);
        expect(await h.storage.snapshot(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'visibility invalidation after the second page stops before provider or allocation',
    () async {
      final h = await ClozeSessionHarness.open();
      try {
        await _prependPhrases(h.storage, 200);
        final before = await h.storage.snapshot();
        final pages = _PageProbe(
          afterPage: (count) async {
            if (count == 2) {
              h.current = false;
            }
          },
        );
        await expectLater(
          h.database.runWithInterceptor(
            () => h.prepare(ClozeVariant.typed),
            interceptor: pages,
          ),
          throwsStateError,
        );
        expect(pages.sizes, [100, 100]);
        expect(h.provider.requests, isEmpty);
        expect(await h.storage.snapshot(), before);
      } finally {
        await h.close();
      }
    },
  );
}

Future<void> _prependPhrases(ConfiguredQuizHarness storage, int count) async {
  for (var index = 0; index < count; index++) {
    await storage.addWord(
      id: '000-phrase-${index.toString().padLeft(3, '0')}',
      spelling: 'two words',
      meaning: 'synthetic owned phrase $index',
    );
  }
}

final class _PageProbe extends drift.QueryInterceptor {
  _PageProbe({this.afterPage});
  final Future<void> Function(int count)? afterPage;
  final sizes = <int>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.toLowerCase().contains('from "vocabulary_words"')) {
      sizes.add(rows.length);
      await afterPage?.call(sizes.length);
    }
    return rows;
  }
}
