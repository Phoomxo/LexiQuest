import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import '../../integration_test/support/persistent_manual_qa_storage.dart';

void main() {
  test(
    'manual QA reopens persistent storage without duplicate seed or lost edits',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'lq-manual-storage-test-',
      );
      var nextId = 0;
      Future<(Directory, AppDatabase, VocabularyUseCases)> open() async {
        final directory = await openPersistentManualQaDirectory(support);
        final db = AppDatabase(
          NativeDatabase(File('${directory.path}/learning.sqlite')),
        );
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'synthetic-owner',
          nowUtc: () => DateTime.utc(2026, 9, 12),
        );
        final vocabulary = VocabularyUseCases(
          owners: owners,
          vocabulary: DriftVocabularyRepository(db),
          generateId: () => 'synthetic-${nextId++}',
          nowUtc: () => DateTime.utc(2026, 9, 12),
        );
        return (directory, db, vocabulary);
      }

      final first = await open();
      expect(await seedManualQaVocabulary(first.$2, first.$3), isTrue);
      final category =
          (await first.$2.select(first.$2.vocabularyCategories).get()).single;
      await first.$3.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'retained',
          meaning: 'synthetic retained addition',
          partOfSpeech: 'adjective',
        ),
      );
      final words = await first.$2.select(first.$2.vocabularyWords).get();
      final before = words.map((word) => word.toJson()).toList();
      await first.$2.close();
      final second = await open();
      addTearDown(second.$2.close);
      expect(second.$1.path, first.$1.path);
      expect(await seedManualQaVocabulary(second.$2, second.$3), isFalse);
      expect(
        (await second.$2.select(second.$2.vocabularyWords).get())
            .map((word) => word.toJson())
            .toList(),
        before,
      );
      expect(before, hasLength(7));
    },
  );
}
