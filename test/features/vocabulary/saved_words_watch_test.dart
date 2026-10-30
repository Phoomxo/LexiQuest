import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/saved_words.dart';

import '../../support/saved_words_data_harness.dart';

void main() {
  late SavedWordsDataHarness h;
  setUp(() async => h = await SavedWordsDataHarness.open());
  tearDown(() => h.close());

  test('watch is pure for absent or unknown captured owners', () async {
    final before = await h.storage.snapshot();
    expect((await h.snapshot()).savedItems, isEmpty);
    expect((await h.snapshot('synthetic-unknown-owner')).savedItems, isEmpty);
    expect(await h.storage.snapshot(), before);
  });

  test(
    'one live joined watch tracks committed save content category availability and tombstone',
    () async {
      final iterator = StreamIterator<SavedWordsSnapshot>(
        h.repository.watchOwner(configuredOwnerId),
      );
      try {
        expect(await iterator.moveNext(), isTrue);
        expect(iterator.current.savedItems, isEmpty);
        final saved = iterator.moveNext();
        await h.set(true);
        expect(await saved, isTrue);
        expect(iterator.current.savedItems.single.word!.spelling, 'station');
        final edited = iterator.moveNext();
        await h.database.customUpdate(
          'UPDATE vocabulary_words SET meaning = ? WHERE id = ?',
          variables: [
            const drift.Variable<String>('synthetic current meaning'),
            drift.Variable<String>(configuredWordIds.first),
          ],
          updates: {h.database.vocabularyWords},
        );
        expect(await edited, isTrue);
        expect(
          iterator.current.savedItems.single.word!.meaning,
          'synthetic current meaning',
        );
        final unavailable = iterator.moveNext();
        await h.database.customUpdate(
          'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
          variables: [const drift.Variable<String>(configuredCategoryId)],
          updates: {h.database.vocabularyCategories},
        );
        expect(await unavailable, isTrue);
        expect(iterator.current.savedItems.single.isEligible, isFalse);
        expect(iterator.current.savedItems.single.word, isNull);
        expect(iterator.current.savedItems.single.state.isSaved, isTrue);
        final unsaved = iterator.moveNext();
        await h.set(false);
        expect(await unsaved, isTrue);
        expect(iterator.current.savedItems, isEmpty);
        expect(
          iterator.current.stateFor(configuredWordIds.first).localRevision,
          2,
        );
      } finally {
        await iterator.cancel();
      }
    },
  );

  test(
    'malformed cross-owner reference exposes no foreign parent text',
    () async {
      await h.set(true);
      await h.database.customStatement('UPDATE saved_words SET word_id = ?', [
        'synthetic-configured-other-word',
      ]);
      final own = await h.snapshot();
      expect(own.savedItems.single.isEligible, isFalse);
      expect(own.savedItems.single.word, isNull);
      expect(own.savedItems.single.categoryName, isNull);
      expect((await h.snapshot(configuredOtherOwnerId)).savedItems, isEmpty);
    },
  );
}
