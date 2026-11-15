import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_failure.dart';

Future<void> seed(AppDatabase db) async {
  await db.customStatement(
    "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('owner-a','localGuest',1,1),('owner-b','localGuest',1,0)",
  );
  await db.customStatement(
    "INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('cat-a','owner-a','A','a',1,1),('cat-b','owner-b','B','b',1,1)",
  );
  await db.customStatement(
    "INSERT INTO vocabulary_words (id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES ('word-a','owner-a','cat-a','station','station','สถานี','สถานี','noun',1,1),('word-b','owner-b','cat-b','ticket','ticket','ตั๋ว','ตั๋ว','noun',1,1)",
  );
}

void main() {
  test(
    'desired state is durable and retry does not change revision, outbox or rewards',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-bookmark-test-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}synthetic.sqlite',
      );
      var db = AppDatabase(NativeDatabase(file));
      try {
        await seed(db);
        var repository = DriftVocabularyRepository(db);
        final before =
            (await db
                    .customSelect(
                      "SELECT local_revision,cloud_revision,updated_at_utc_ms FROM vocabulary_words WHERE id='word-a'",
                    )
                    .getSingle())
                .data;
        await repository.setBookmarked(
          expectedOwnerId: 'owner-a',
          wordId: 'word-a',
          bookmarked: true,
        );
        await repository.setBookmarked(
          expectedOwnerId: 'owner-a',
          wordId: 'word-a',
          bookmarked: true,
        );
        expect(
          (await repository.watchBookmarkedWords('owner-a').first).map(
            (w) => w.id,
          ),
          ['word-a'],
        );
        expect(
          (await db
                  .customSelect(
                    "SELECT local_revision,cloud_revision,updated_at_utc_ms FROM vocabulary_words WHERE id='word-a'",
                  )
                  .getSingle())
              .data,
          before,
        );
        expect(await db.select(db.outboxOperations).get(), isEmpty);
        expect(await db.select(db.pointsLedgerEntries).get(), isEmpty);
        expect(await db.select(db.rewardTransactions).get(), isEmpty);
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        repository = DriftVocabularyRepository(db);
        expect(
          (await repository.watchBookmarkedWords('owner-a').first).map(
            (w) => w.id,
          ),
          ['word-a'],
        );
        await repository.setBookmarked(
          expectedOwnerId: 'owner-a',
          wordId: 'word-a',
          bookmarked: false,
        );
        await repository.setBookmarked(
          expectedOwnerId: 'owner-a',
          wordId: 'word-a',
          bookmarked: false,
        );
        expect(await repository.watchBookmarkedWords('owner-a').first, isEmpty);
        expect(
          (await db
                  .customSelect(
                    "SELECT local_revision,cloud_revision,updated_at_utc_ms FROM vocabulary_words WHERE id='word-a'",
                  )
                  .getSingle())
              .data,
          before,
        );
        expect(await db.select(db.outboxOperations).get(), isEmpty);
      } finally {
        await db.close();
        final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
        final actual = await directory.resolveSymbolicLinks();
        expect(
          actual.startsWith(
            '$tempRoot${Platform.pathSeparator}lexiquest-bookmark-test-',
          ),
          isTrue,
        );
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'owner and live word/category are enforced without side effects',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await seed(db);
        final repository = DriftVocabularyRepository(db);
        await expectLater(
          repository.setBookmarked(
            expectedOwnerId: 'owner-b',
            wordId: 'word-b',
            bookmarked: true,
          ),
          throwsStateError,
        );
        await expectLater(
          repository.setBookmarked(
            expectedOwnerId: 'owner-a',
            wordId: 'word-b',
            bookmarked: true,
          ),
          throwsA(isA<VocabularyNotFoundFailure>()),
        );
        await db.customStatement(
          "UPDATE vocabulary_words SET is_deleted=1 WHERE id='word-a'",
        );
        await expectLater(
          repository.setBookmarked(
            expectedOwnerId: 'owner-a',
            wordId: 'word-a',
            bookmarked: true,
          ),
          throwsA(isA<VocabularyNotFoundFailure>()),
        );
        await db.customStatement(
          "UPDATE vocabulary_words SET is_deleted=0 WHERE id='word-a'",
        );
        await db.customUpdate(
          "UPDATE vocabulary_categories SET is_deleted=1 WHERE id='cat-a'",
          updates: {db.vocabularyCategories},
        );
        await expectLater(
          repository.setBookmarked(
            expectedOwnerId: 'owner-a',
            wordId: 'word-a',
            bookmarked: true,
          ),
          throwsA(isA<VocabularyNotFoundFailure>()),
        );
        expect(await repository.watchBookmarkedWords('owner-a').first, isEmpty);
        expect(await db.select(db.outboxOperations).get(), isEmpty);
        expect(await db.select(db.pointsLedgerEntries).get(), isEmpty);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'list is owner isolated, excludes deleted words and categories',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await seed(db);
        await db.customStatement("UPDATE vocabulary_words SET is_bookmarked=1");
        final repository = DriftVocabularyRepository(db);
        expect(
          (await repository.watchBookmarkedWords('owner-a').first).map(
            (w) => w.id,
          ),
          ['word-a'],
        );
        expect(
          (await repository.watchBookmarkedWords('owner-b').first).map(
            (w) => w.id,
          ),
          ['word-b'],
        );
        await db.customUpdate(
          "UPDATE vocabulary_categories SET is_deleted=1 WHERE id='cat-a'",
          updates: {db.vocabularyCategories},
        );
        expect(await repository.watchBookmarkedWords('owner-a').first, isEmpty);
        await db.customUpdate(
          "UPDATE vocabulary_words SET is_deleted=1 WHERE id='word-b'",
          updates: {db.vocabularyWords},
        );
        expect(await repository.watchBookmarkedWords('owner-b').first, isEmpty);
      } finally {
        await db.close();
      }
    },
  );
}
