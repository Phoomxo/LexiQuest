import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

/// Synthetic local-only owner fixture. It never creates sync or Research facts.
Future<Map<String, Object?>> insertOwnerSavedWord(
  AppDatabase database,
  String ownerId, {
  String? wordId,
  String? categoryId,
  bool isSaved = true,
  int localRevision = 3,
  int firstSavedAtUtcMs = 10,
  int updatedAtUtcMs = 20,
  String? mutationId,
}) async {
  final word = wordId ?? 'synthetic-saved-word:$ownerId';
  final existing = await database
      .customSelect(
        'SELECT owner_id, category_id FROM vocabulary_words WHERE id = ?',
        variables: [Variable<String>(word)],
      )
      .getSingleOrNull();
  if (existing == null) {
    final category = categoryId ?? 'synthetic-saved-category:$ownerId';
    final parent = await database
        .customSelect(
          'SELECT owner_id FROM vocabulary_categories WHERE id = ?',
          variables: [Variable<String>(category)],
        )
        .getSingleOrNull();
    if (parent == null) {
      await database.customStatement(
        'INSERT INTO vocabulary_categories '
        '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
        'VALUES (?, ?, ?, ?, 1, 1)',
        [
          category,
          ownerId,
          'Synthetic saved $ownerId',
          'synthetic saved $ownerId',
        ],
      );
    } else if (parent.read<String>('owner_id') != ownerId) {
      throw StateError('Synthetic saved category has another owner');
    }
    await database.customStatement(
      'INSERT INTO vocabulary_words '
      '(id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
      [
        word,
        ownerId,
        category,
        'saved fixture $word',
        'saved fixture $word',
        'synthetic saved gloss',
        'synthetic saved gloss',
        'noun',
      ],
    );
  } else if (existing.read<String>('owner_id') != ownerId ||
      (categoryId != null &&
          existing.read<String>('category_id') != categoryId)) {
    throw StateError('Synthetic saved word has another owner or category');
  }
  await database.customStatement(
    'INSERT INTO saved_words '
    '(owner_id, word_id, is_saved, local_revision, first_saved_at_utc_ms, updated_at_utc_ms, last_mutation_id) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      ownerId,
      word,
      isSaved ? 1 : 0,
      localRevision,
      firstSavedAtUtcMs,
      updatedAtUtcMs,
      mutationId ?? 'synthetic-saved-mutation:$word',
    ],
  );
  return (await database
          .customSelect(
            'SELECT * FROM saved_words WHERE owner_id = ? AND word_id = ?',
            variables: [Variable<String>(ownerId), Variable<String>(word)],
          )
          .getSingle())
      .data;
}

Future<List<Map<String, Object?>>> savedWordOwnerRows(
  AppDatabase database, {
  String? ownerId,
}) async =>
    (await database
            .customSelect(
              ownerId == null
                  ? 'SELECT * FROM saved_words ORDER BY owner_id, word_id'
                  : 'SELECT * FROM saved_words WHERE owner_id = ? ORDER BY word_id',
              variables: ownerId == null
                  ? const []
                  : [Variable<String>(ownerId)],
            )
            .get())
        .map((row) => row.data)
        .toList();
