import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../account_deletion/domain/owner_write_coordinator.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../domain/vocabulary_word.dart';
import '../domain/word_report.dart';

final class DriftWordReportRepository implements WordReportRepository {
  DriftWordReportRepository({
    required this.database,
    required OwnerWriteCoordinator ownerWriteCoordinator,
  }) {
    if (ownerWriteCoordinator is! DriftOwnerWriteCoordinator ||
        !identical(database, ownerWriteCoordinator.database)) {
      throw ArgumentError(
        'Word reports require the real same-database owner coordinator',
      );
    }
    _ownerWrites = ownerWriteCoordinator;
  }

  final db.AppDatabase database;
  late final DriftOwnerWriteCoordinator _ownerWrites;

  @override
  Future<SubmitResult> submit(WordReportCommand command) async {
    if (await _ownerWrites.hasAmbientTransaction()) {
      _unavailable();
    }
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: command.expectedOwnerId,
      write: () async {
        final existing = await _row(command.id);
        final StoredWordReport expected;
        final bool inserted;
        if (existing != null) {
          if (existing.data['owner_id'] != command.expectedOwnerId) {
            _unavailable();
          }
          expected = _decode(existing);
          if (!expected.matchesCommand(command)) {
            throw const WordReportException(WordReportFailureCode.collision);
          }
          inserted = false;
        } else {
          await _requireFreshTarget(command.expectedOwnerId, command.target);
          expected = StoredWordReport(
            id: command.id,
            ownerId: command.expectedOwnerId,
            target: command.target,
            reason: command.reason,
            comment: command.comment,
            queuedAtUtc: command.queuedAtUtc,
          );
          await database.customInsert(
            'INSERT INTO word_reports '
            '(id,owner_id,word_id,category_id,word_revision,snapshot_json,snapshot_sha256,reason,comment,queued_at_utc_ms) '
            'VALUES (?,?,?,?,?,?,?,?,?,?)',
            variables: [
              Variable<String>(expected.id),
              Variable<String>(expected.ownerId),
              Variable<String>(expected.target.wordId),
              Variable<String>(expected.target.categoryId),
              Variable<int>(expected.target.wordRevision),
              Variable<String>(expected.target.snapshotJson),
              Variable<String>(expected.target.snapshotSha256),
              Variable<String>(expected.reason.name),
              Variable<String>(expected.comment),
              Variable<int>(expected.queuedAtUtc.millisecondsSinceEpoch),
            ],
            updates: {database.wordReports},
          );
          inserted = true;
        }
        return _ownerWrites.writeForActiveOwner(
          expectedOwnerId: command.expectedOwnerId,
          write: () async {
            if (inserted) {
              await _requireFreshTarget(
                command.expectedOwnerId,
                command.target,
              );
            }
            final finalRow = await _row(command.id);
            if (finalRow == null ||
                finalRow.data['owner_id'] != command.expectedOwnerId) {
              _unavailable();
            }
            final stored = _decode(finalRow);
            if (!stored.sameFacts(expected) ||
                !stored.matchesCommand(command)) {
              _unavailable();
            }
            return SubmitResult(
              status: inserted ? SubmitStatus.queued : SubmitStatus.replayed,
              report: stored,
            );
          },
        );
      },
    );
  }

  @override
  Stream<List<StoredWordReport>> watchOwner(String expectedOwnerId) {
    if (expectedOwnerId.trim().isEmpty ||
        expectedOwnerId.runes.length > wordReportIdentifierMaxRunes) {
      throw ArgumentError('Invalid word-report owner');
    }
    return database
        .customSelect(
          'SELECT * FROM word_reports WHERE owner_id = ? ORDER BY queued_at_utc_ms,id',
          variables: [Variable<String>(expectedOwnerId)],
          readsFrom: {database.wordReports},
        )
        .watch()
        .map(
          (rows) => List<StoredWordReport>.unmodifiable(
            rows.map((row) {
              if (row.data['owner_id'] != expectedOwnerId) {
                _unavailable();
              }
              return _decode(row);
            }),
          ),
        );
  }

  Future<QueryRow?> _row(String id) => database
      .customSelect(
        'SELECT * FROM word_reports WHERE id = ?',
        variables: [Variable<String>(id)],
      )
      .getSingleOrNull();

  Future<void> _requireFreshTarget(
    String ownerId,
    WordReportTarget expected,
  ) async {
    final row = await database
        .customSelect(
          'SELECT w.* FROM vocabulary_words w JOIN vocabulary_categories c '
          'ON c.id = w.category_id AND c.owner_id = w.owner_id AND c.is_deleted = 0 '
          'WHERE w.id = ? AND w.owner_id = ? AND w.is_deleted = 0',
          variables: [
            Variable<String>(expected.wordId),
            Variable<String>(ownerId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      _staleTarget();
    }
    try {
      final word = VocabularyWord(
        id: row.read<String>('id'),
        ownerId: row.read<String>('owner_id'),
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
        isDeleted: false,
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('created_at_utc_ms'),
          isUtc: true,
        ),
        updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('updated_at_utc_ms'),
          isUtc: true,
        ),
      );
      final current = WordReportTarget.fromWord(word);
      if (!current.sameTarget(expected)) {
        _staleTarget();
      }
    } on ArgumentError {
      _staleTarget();
    } on FormatException {
      _staleTarget();
    }
  }

  StoredWordReport _decode(QueryRow row) {
    try {
      return StoredWordReport.fromStorage(row.data);
    } on FormatException {
      _unavailable();
    }
  }

  Never _unavailable() =>
      throw const WordReportException(WordReportFailureCode.unavailable);
  Never _staleTarget() =>
      throw const WordReportException(WordReportFailureCode.staleTarget);
}
