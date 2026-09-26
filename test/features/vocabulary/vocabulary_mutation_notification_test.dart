import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_import.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';

const _operations = [
  'category',
  'create',
  'update',
  'delete',
  'import',
  'renameCategory',
  'deleteCategory',
  'atomicCreate',
];

Future<Map<String, List<String>>> _snapshot(AppDatabase db) async => {
  for (final table in [
    'vocabulary_categories',
    'vocabulary_words',
    'vocabulary_imports',
    'vocabulary_import_rows',
    'outbox_operations',
  ])
    table:
        (await db.customSelect('SELECT * FROM $table').get())
            .map((row) => jsonEncode(row.data))
            .toList()
          ..sort(),
};

void main() {
  for (final operation in _operations) {
    for (final abort in [false, true]) {
      test(
        '$operation preserves commit outcome with notifier fault (abort: $abort)',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'lexiquest-notifier-',
          );
          final file = File('${directory.path}/test.sqlite');
          var db = AppDatabase(NativeDatabase(file));
          addTearDown(() async {
            await db.close();
            await directory.delete(recursive: true);
          });
          final now = DateTime.utc(2026, 9, 24);
          final owners = DriftLocalOwnerRepository(
            db,
            generateId: () => 'owner',
            nowUtc: () => now,
          );
          final repo = DriftVocabularyRepository(db);
          var id = 0;
          var calls = 0;
          var fault = false;
          void notify() {
            calls++;
            if (fault) throw StateError('injected sync notification failure');
          }

          final vocabulary = VocabularyUseCases(
            owners: owners,
            vocabulary: repo,
            generateId: () => 'id-${id++}',
            nowUtc: () => now,
            onLocalMutation: notify,
          );
          final category = await vocabulary.createCategory('Original');
          final word = await vocabulary.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: 'book',
              meaning: 'original',
              partOfSpeech: 'noun',
            ),
          );
          final before = await _snapshot(db);
          calls = 0;
          fault = true;
          if (abort) {
            await db.customStatement(
              "CREATE TRIGGER reject_outbox BEFORE INSERT ON outbox_operations BEGIN SELECT RAISE(ABORT, 'injected precommit failure'); END",
            );
          }
          Object? result;
          Object? failure;
          try {
            switch (operation) {
              case 'category':
                result = await vocabulary.createCategory('New');
              case 'create':
                result = await vocabulary.createWord(
                  CreateWordCommand(
                    categoryId: category.id,
                    spelling: 'pen',
                    meaning: 'new',
                    partOfSpeech: 'noun',
                  ),
                );
              case 'update':
                result = await vocabulary.updateWord(
                  UpdateWordCommand(
                    id: word.id,
                    categoryId: category.id,
                    spelling: 'book',
                    meaning: 'edited',
                    partOfSpeech: 'noun',
                  ),
                );
              case 'delete':
                await vocabulary.deleteWord(word.id);
              case 'import':
                result =
                    await ImportVocabulary(
                      owners: owners,
                      repository: DriftVocabularyImportRepository(db),
                      generateId: () => 'id-${id++}',
                      nowUtc: () => now,
                      onLocalMutation: notify,
                    )(
                      categoryId: category.id,
                      sourceName: 'test.csv',
                      rows: const [
                        {
                          'word': 'pen',
                          'meaning': 'new',
                          'partOfSpeech': 'noun',
                        },
                        {
                          'word': 'pen',
                          'meaning': 'new',
                          'partOfSpeech': 'noun',
                        },
                        {
                          'word': 'invalid',
                          'meaning': '',
                          'partOfSpeech': 'noun',
                        },
                      ],
                    );
              case 'renameCategory':
                result = await vocabulary.renameCategory(
                  category.id,
                  'Renamed',
                );
              case 'deleteCategory':
                await vocabulary.deleteCategory(category.id);
              case 'atomicCreate':
                result = await vocabulary.createOrReuseWordInCategory(
                  expectedOwnerId: category.ownerId,
                  categoryName: 'Atomic',
                  spelling: 'cup',
                  meaning: 'new',
                  partOfSpeech: 'noun',
                  cefrLevel: null,
                  source: 'manual',
                  mutationAllowed: () => true,
                );
            }
          } catch (error) {
            failure = error;
          }
          final after = await _snapshot(db);
          if (abort) {
            expect(failure, isNotNull);
            expect(failure.toString(), contains('injected precommit failure'));
            expect(calls, 0);
            expect(after, before);
          } else {
            expect(calls, 1);
            expect(after, isNot(before));
            final outbox = await db.select(db.outboxOperations).get();
            expect(outbox.length, operation == 'atomicCreate' ? 4 : 3);
            expect(
              outbox.every((row) => row.ownerId == category.ownerId),
              isTrue,
            );
            final words = await db.select(db.vocabularyWords).get();
            if (operation == 'update') {
              expect(words.single.meaning, 'edited');
              expect(words.single.localRevision, 2);
            } else if (operation == 'delete' || operation == 'deleteCategory') {
              expect(words.single.isDeleted, isTrue);
            } else {
              expect(
                words.singleWhere((row) => row.id == word.id).meaning,
                'original',
              );
            }
            if (operation == 'import') {
              expect(
                (await db.select(db.vocabularyImports).get())
                    .single
                    .acceptedCount,
                1,
              );
              expect(
                await db.select(db.vocabularyImportRows).get(),
                hasLength(3),
              );
            }
          }
          await db.close();
          db = AppDatabase(NativeDatabase(file));
          expect(
            await _snapshot(db),
            after,
            reason: 'all persisted rows survive reopen',
          );
          if (!abort) {
            // Assert after inspecting durable rows, so RED proves commit preceded failure.
            expect(
              failure,
              isNull,
              reason:
                  'optional sync notification must not report a committed mutation as failed',
            );
            if (operation == 'category' || operation == 'renameCategory') {
              expect(result, isA<VocabularyCategory>());
            }
            if (operation == 'create' ||
                operation == 'update' ||
                operation == 'atomicCreate') {
              expect(result, isA<VocabularyWord>());
            }
            if (operation == 'import') {
              final imported = result! as VocabularyImportResult;
              expect(imported.accepted, 1);
              expect(imported.duplicates, 1);
              expect(imported.rejected, hasLength(1));
            }
          }
        },
      );
    }
  }
}
