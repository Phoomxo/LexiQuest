import 'dart:io';
import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';

const manualQaWords = [
  ('station', 'สถานี'),
  ('book', 'หนังสือ'),
  ('house', 'บ้าน'),
  ('cat', 'แมว'),
  ('water', 'น้ำ'),
  ('school', 'โรงเรียน'),
];

/// Dedicated synthetic store under app support, never Android code_cache.
/// The ordinary app database and production bootstrap do not use this helper.
Future<Directory> openPersistentManualQaDirectory(Directory appSupport) async {
  return Directory(
    '${appSupport.path}/lexiquest-manual-uat-v1',
  ).create(recursive: true);
}

Future<bool> seedManualQaVocabulary(
  AppDatabase database,
  VocabularyUseCases vocabulary,
) async {
  final owner = await vocabulary.owners.getOrCreateActiveOwner();
  return database.transaction(() async {
    const name = 'คำตัวอย่างสำหรับทดสอบ';
    final existing =
        await (database.select(database.vocabularyCategories)..where(
              (row) => row.ownerId.equals(owner.id) & row.name.equals(name),
            ))
            .get();
    if (existing.isNotEmpty) return false;
    final category = await vocabulary.createCategory(name);
    for (final (english, thai) in manualQaWords) {
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: english,
          meaning: thai,
          partOfSpeech: 'noun',
          cefrLevel: english == 'station' ? 'A1' : null,
        ),
      );
    }
    return true;
  });
}
