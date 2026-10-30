import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' show AppDatabase;
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

/// Synthetic storage seed. Live collection authority is tested by its own writer.
Future<StoredWordReport> insertOwnerWordReport(
  AppDatabase database,
  String ownerId, {
  String? wordId,
  String? categoryId,
  String? id,
  ReportReason reason = ReportReason.incorrectMeaning,
  String? comment = 'Synthetic local report',
  DateTime? queuedAtUtc,
}) async {
  final word = wordId ?? 'synthetic-reported-word:$ownerId';
  var row = await database
      .customSelect(
        'SELECT * FROM vocabulary_words WHERE id = ?',
        variables: [Variable<String>(word)],
      )
      .getSingleOrNull();
  if (row == null) {
    final category = categoryId ?? 'synthetic-report-category:$ownerId';
    final parent = await database
        .customSelect(
          'SELECT owner_id FROM vocabulary_categories WHERE id = ?',
          variables: [Variable<String>(category)],
        )
        .getSingleOrNull();
    if (parent == null) {
      await database.customStatement(
        'INSERT INTO vocabulary_categories '
        '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, 1, 1)',
        [
          category,
          ownerId,
          'Synthetic report $ownerId',
          'synthetic report $ownerId',
        ],
      );
    } else if (parent.read<String>('owner_id') != ownerId) {
      throw StateError('Synthetic report category has another owner');
    }
    await database.customStatement(
      'INSERT INTO vocabulary_words '
      '(id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, source, local_revision, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 2, 1, 1)',
      [
        word,
        ownerId,
        category,
        'reported fixture',
        'reported fixture',
        'synthetic report meaning',
        'synthetic report meaning',
        'noun',
        'manual',
      ],
    );
    row = await database
        .customSelect(
          'SELECT * FROM vocabulary_words WHERE id = ?',
          variables: [Variable<String>(word)],
        )
        .getSingle();
  }
  if (row.read<String>('owner_id') != ownerId ||
      (categoryId != null && row.read<String>('category_id') != categoryId)) {
    throw StateError('Synthetic reported word has another owner or category');
  }
  final report = StoredWordReport(
    id: id ?? 'word-report:synthetic:$word',
    ownerId: ownerId,
    target: WordReportTarget.fromWord(
      VocabularyWord(
        id: word,
        ownerId: ownerId,
        categoryId: row.read<String>('category_id'),
        spelling: row.read<String>('spelling'),
        normalizedSpelling: row.read<String>('normalized_spelling'),
        meaning: row.read<String>('meaning'),
        normalizedMeaning: row.read<String>('normalized_meaning'),
        partOfSpeech: row.read<String>('part_of_speech'),
        cefrLevel: row.readNullable<String>('cefr_level'),
        source: row.read<String>('source'),
        isGlobal: row.read<bool>('is_global'),
        localRevision: row.read<int>('local_revision'),
        isDeleted: row.read<bool>('is_deleted'),
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('created_at_utc_ms'),
          isUtc: true,
        ),
        updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('updated_at_utc_ms'),
          isUtc: true,
        ),
      ),
    ),
    reason: reason,
    comment: comment,
    queuedAtUtc: queuedAtUtc ?? DateTime.utc(2026, 10, 30),
  );
  await insertStoredOwnerWordReport(database, report);
  return report;
}

Future<void> insertStoredOwnerWordReport(
  AppDatabase database,
  StoredWordReport report,
) {
  final row = report.toStorage();
  return database.customStatement(
    'INSERT INTO word_reports (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
    row.values.toList(),
  );
}

Future<List<StoredWordReport>> wordReportOwnerRows(
  AppDatabase database, {
  String? ownerId,
}) async =>
    (await database
            .customSelect(
              ownerId == null
                  ? 'SELECT * FROM word_reports ORDER BY id'
                  : 'SELECT * FROM word_reports WHERE owner_id = ? ORDER BY id',
              variables: ownerId == null
                  ? const []
                  : [Variable<String>(ownerId)],
            )
            .get())
        .map((row) => StoredWordReport.fromStorage(row.data))
        .toList();
