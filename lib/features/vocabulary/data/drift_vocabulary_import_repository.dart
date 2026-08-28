import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../learning_packs/domain/content_quality_policy.dart';
import '../domain/vocabulary_import.dart';
import '../domain/vocabulary_import_repository.dart';
import '../domain/vocabulary_word.dart';
import 'drift_vocabulary_repository.dart';

final class DriftVocabularyImportRepository
    implements VocabularyImportRepository {
  const DriftVocabularyImportRepository(this.database);

  final db.AppDatabase database;

  @override
  Future<VocabularyImportResult> persist(
    PreparedVocabularyImport import, {
    required bool Function() isCancelled,
  }) {
    return database.transaction(() async {
      if (isCancelled()) {
        throw const VocabularyImportCancelled();
      }
      final replay =
          await (database.select(database.vocabularyImports)..where(
                (row) =>
                    row.ownerId.equals(import.ownerId) &
                    row.categoryId.equals(import.categoryId) &
                    row.sourceHash.equals(import.sourceHash),
              ))
              .getSingleOrNull();
      if (replay != null) {
        return _restoreResult(replay);
      }
      final category =
          await (database.select(database.vocabularyCategories)..where(
                (row) =>
                    row.id.equals(import.categoryId) &
                    row.ownerId.equals(import.ownerId) &
                    row.isDeleted.equals(false),
              ))
              .getSingleOrNull();
      if (category == null) {
        throw StateError('active import category was not found');
      }

      final existingWords =
          await (database.select(database.vocabularyWords)..where(
                (row) =>
                    row.ownerId.equals(import.ownerId) &
                    row.categoryId.equals(import.categoryId) &
                    row.isDeleted.equals(false),
              ))
              .get();
      final naturalKeys = existingWords
          .map(
            (word) =>
                '${word.normalizedSpelling}\u001f${word.normalizedMeaning}',
          )
          .toSet();
      var available =
          DriftVocabularyRepository.categoryWordLimit - existingWords.length;
      var accepted = 0;
      var duplicates = 0;
      final rejected = <VocabularyImportRowFailure>[];
      final storedRows = <_StoredImportRow>[];

      for (final row in import.rows) {
        if (isCancelled()) {
          throw const VocabularyImportCancelled();
        }
        final word = row.word;
        if (row.failureCode != null || word == null) {
          final code = row.failureCode ?? 'invalidRow';
          rejected.add(
            VocabularyImportRowFailure(rowNumber: row.rowNumber, code: code),
          );
          storedRows.add(_StoredImportRow(row, 'rejected', code, null));
          continue;
        }
        final naturalKey =
            '${word.normalizedSpelling}\u001f${word.normalizedMeaning}';
        if (!naturalKeys.add(naturalKey)) {
          duplicates++;
          storedRows.add(_StoredImportRow(row, 'duplicate', null, null));
          continue;
        }
        if (available <= 0) {
          const code = 'categoryWordLimit';
          rejected.add(
            VocabularyImportRowFailure(rowNumber: row.rowNumber, code: code),
          );
          storedRows.add(_StoredImportRow(row, 'rejected', code, null));
          continue;
        }

        await _insertWord(word);
        accepted++;
        available--;
        storedRows.add(_StoredImportRow(row, 'accepted', null, word.id));
      }

      await database
          .into(database.vocabularyImports)
          .insert(
            db.VocabularyImportsCompanion.insert(
              id: import.importId,
              ownerId: import.ownerId,
              categoryId: import.categoryId,
              sourceType: 'rows',
              sourceName: import.sourceName,
              sourceHash: import.sourceHash,
              status: 'completed',
              acceptedCount: Value(accepted),
              duplicateCount: Value(duplicates),
              rejectedCount: Value(rejected.length),
              createdAtUtcMs: import.nowUtc.millisecondsSinceEpoch,
              completedAtUtcMs: Value(import.nowUtc.millisecondsSinceEpoch),
            ),
          );
      for (final stored in storedRows) {
        await database
            .into(database.vocabularyImportRows)
            .insert(
              db.VocabularyImportRowsCompanion.insert(
                id: '${import.importId}:row:${stored.row.rowNumber}',
                importId: import.importId,
                rowNumber: stored.row.rowNumber,
                payloadHash: stored.row.payloadHash,
                status: stored.status,
                failureCode: Value(stored.failureCode),
                wordId: Value(stored.wordId),
              ),
            );
      }

      return VocabularyImportResult(
        importId: import.importId,
        accepted: accepted,
        duplicates: duplicates,
        rejected: List.unmodifiable(rejected),
      );
    });
  }

  Future<void> _insertWord(VocabularyWord word) async {
    await database
        .into(database.vocabularyWords)
        .insert(
          db.VocabularyWordsCompanion.insert(
            id: word.id,
            ownerId: word.ownerId,
            categoryId: word.categoryId,
            spelling: word.spelling,
            normalizedSpelling: word.normalizedSpelling,
            meaning: word.meaning,
            normalizedMeaning: word.normalizedMeaning,
            partOfSpeech: word.partOfSpeech,
            cefrLevel: Value(word.cefrLevel),
            source: Value(word.source),
            isGlobal: Value(word.isGlobal),
            contentRevision: const Value(1),
            contentChecksumSha256: Value(
              ContentQualityPolicy.vocabularyChecksumSha256(
                categoryId: word.categoryId,
                spelling: word.spelling,
                normalizedSpelling: word.normalizedSpelling,
                meaning: word.meaning,
                normalizedMeaning: word.normalizedMeaning,
                partOfSpeech: word.partOfSpeech,
                cefrLevel: word.cefrLevel,
                source: word.source,
                isGlobal: word.isGlobal,
              ),
            ),
            createdAtUtcMs: word.createdAtUtc.millisecondsSinceEpoch,
            updatedAtUtcMs: word.updatedAtUtc.millisecondsSinceEpoch,
          ),
        );
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId: 'word:${word.id}:1',
            ownerId: word.ownerId,
            entityType: 'word',
            entityId: word.id,
            operationKind: 'upsert',
            createdAtUtcMs: word.updatedAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<VocabularyImportResult> _restoreResult(
    db.VocabularyImport replay,
  ) async {
    final rows =
        await (database.select(database.vocabularyImportRows)
              ..where((row) => row.importId.equals(replay.id))
              ..orderBy([(row) => OrderingTerm.asc(row.rowNumber)]))
            .get();
    return VocabularyImportResult(
      importId: replay.id,
      accepted: replay.acceptedCount,
      duplicates: replay.duplicateCount,
      rejected: [
        for (final row in rows)
          if (row.status == 'rejected')
            VocabularyImportRowFailure(
              rowNumber: row.rowNumber,
              code: row.failureCode ?? 'invalidRow',
            ),
      ],
    );
  }
}

final class _StoredImportRow {
  const _StoredImportRow(this.row, this.status, this.failureCode, this.wordId);

  final PreparedVocabularyImportRow row;
  final String status;
  final String? failureCode;
  final String? wordId;
}
