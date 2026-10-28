import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';

final class ExportVocabularyRow {
  const ExportVocabularyRow({
    required this.id,
    required this.category,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    required this.cefrLevel,
    required this.source,
  });

  final String id;
  final String category;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
  final String? cefrLevel;
  final String source;
}

final class ExportAttemptRow {
  const ExportAttemptRow({
    required this.id,
    required this.sessionId,
    required this.wordId,
    required this.spelling,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.occurredAtUtc,
    required this.providerProvenance,
  });

  final String id;
  final String sessionId;
  final String wordId;
  final String spelling;
  final String promptMode;
  final bool isCorrect;
  final int? responseTimeMs;
  final DateTime occurredAtUtc;
  final String? providerProvenance;
}

final class ExportReadingRow {
  const ExportReadingRow({
    required this.documentId,
    required this.documentRevision,
    required this.lastPosition,
    required this.isCompleted,
    required this.updatedAtUtc,
  });

  final String documentId;
  final int documentRevision;
  final int lastPosition;
  final bool isCompleted;
  final DateTime updatedAtUtc;
}

final class ExportDataSet {
  const ExportDataSet({
    required this.vocabulary,
    required this.attempts,
    required this.reading,
  });

  final List<ExportVocabularyRow> vocabulary;
  final List<ExportAttemptRow> attempts;
  final List<ExportReadingRow> reading;

  int get recordCount => vocabulary.length + attempts.length + reading.length;
}

final class DriftExportReader {
  const DriftExportReader(this.database);

  final AppDatabase database;

  Future<ExportDataSet> load({
    required String ownerId,
    required bool vocabulary,
    required bool attempts,
    required bool reading,
  }) async {
    final vocabularyRows = vocabulary
        ? await database
              .customSelect(
                '''
                SELECT w.id, c.name AS category, w.spelling, w.meaning,
                       w.part_of_speech, w.cefr_level, w.source
                FROM vocabulary_words w
                INNER JOIN vocabulary_categories c
                  ON c.id = w.category_id AND c.owner_id = w.owner_id
                WHERE w.owner_id = ? AND w.is_deleted = 0 AND c.is_deleted = 0
                ORDER BY c.sort_order, c.name, w.spelling, w.id
                ''',
                variables: [Variable<String>(ownerId)],
                readsFrom: {
                  database.vocabularyWords,
                  database.vocabularyCategories,
                },
              )
              .get()
        : const <QueryRow>[];
    final attemptRows = attempts
        ? await database
              .customSelect(
                '''
                SELECT a.id, a.session_id, a.word_id, w.spelling,
                       a.prompt_mode, a.is_correct, a.response_time_ms,
                       a.occurred_at_utc_ms, a.provider_provenance
                FROM answer_attempts a
                INNER JOIN vocabulary_words w
                  ON w.id = a.word_id AND w.owner_id = a.owner_id
                WHERE a.owner_id = ?
                ORDER BY a.occurred_at_utc_ms, a.id
                ''',
                variables: [Variable<String>(ownerId)],
                readsFrom: {database.answerAttempts, database.vocabularyWords},
              )
              .get()
        : const <QueryRow>[];
    final readingRows = reading
        ? await (database.select(database.readingProgressEntries)
                ..where((row) => row.ownerId.equals(ownerId))
                ..orderBy([
                  (row) => OrderingTerm.asc(row.updatedAtUtcMs),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get()
        : const <ReadingProgressEntry>[];
    return ExportDataSet(
      vocabulary: vocabularyRows
          .map(
            (row) => ExportVocabularyRow(
              id: row.read<String>('id'),
              category: row.read<String>('category'),
              spelling: row.read<String>('spelling'),
              meaning: row.read<String>('meaning'),
              partOfSpeech: row.read<String>('part_of_speech'),
              cefrLevel: row.readNullable<String>('cefr_level'),
              source: row.read<String>('source'),
            ),
          )
          .toList(growable: false),
      attempts: attemptRows
          .map(
            (row) => ExportAttemptRow(
              id: row.read<String>('id'),
              sessionId: row.read<String>('session_id'),
              wordId: row.read<String>('word_id'),
              spelling: row.read<String>('spelling'),
              promptMode: row.read<String>('prompt_mode'),
              isCorrect: row.read<bool>('is_correct'),
              responseTimeMs: row.readNullable<int>('response_time_ms'),
              occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('occurred_at_utc_ms'),
                isUtc: true,
              ),
              providerProvenance: row.readNullable<String>(
                'provider_provenance',
              ),
            ),
          )
          .toList(growable: false),
      reading: readingRows
          .map(
            (row) => ExportReadingRow(
              documentId: row.documentId,
              documentRevision: row.documentRevision,
              lastPosition: row.lastPosition,
              isCompleted: row.isCompleted,
              updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                row.updatedAtUtcMs,
                isUtc: true,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}
