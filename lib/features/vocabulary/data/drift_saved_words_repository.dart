import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../domain/saved_words.dart';
import '../domain/vocabulary_word.dart';

final class DriftSavedWordsRepository implements SavedWordsRepository {
  DriftSavedWordsRepository(
    this.database, {
    required DriftOwnerWriteCoordinator ownerWrites,
  }) : _ownerWrites = ownerWrites {
    if (!identical(database, ownerWrites.database)) {
      throw ArgumentError('Saved words require the same owner-write database');
    }
  }

  final db.AppDatabase database;
  final DriftOwnerWriteCoordinator _ownerWrites;

  @override
  Stream<SavedWordsSnapshot> watchOwner(String expectedOwnerId) => database
      .customSelect(
        '''
SELECT b.owner_id,b.word_id,b.is_saved,b.local_revision,
       b.first_saved_at_utc_ms,b.updated_at_utc_ms,b.last_mutation_id,
       w.id AS current_word_id,w.owner_id AS current_word_owner,
       w.category_id AS current_category_id,w.spelling,w.normalized_spelling,
       w.meaning,w.normalized_meaning,w.part_of_speech,w.cefr_level,w.source,
       w.is_global,w.local_revision AS current_word_revision,
       w.is_deleted AS word_deleted,w.created_at_utc_ms AS word_created_at,
       w.updated_at_utc_ms AS word_updated_at,
       c.id AS joined_category_id,c.name AS category_name,
       c.is_deleted AS category_deleted
FROM saved_words b
LEFT JOIN vocabulary_words w ON w.id = b.word_id AND w.owner_id = b.owner_id
LEFT JOIN vocabulary_categories c ON c.id = w.category_id AND c.owner_id = b.owner_id
WHERE b.owner_id = ?
ORDER BY b.first_saved_at_utc_ms DESC,b.word_id
''',
        variables: [Variable<String>(expectedOwnerId)],
        readsFrom: {
          database.savedWords,
          database.vocabularyWords,
          database.vocabularyCategories,
        },
      )
      .watch()
      .map((rows) => _snapshot(expectedOwnerId, rows));

  @override
  Future<SavedWordApplyResult> apply(SavedWordMutation command) async {
    if (await _ownerWrites.hasAmbientTransaction()) {
      _unavailable();
    }
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: command.expectedOwnerId,
      write: () async {
        final current = await _readState(
          command.expectedOwnerId,
          command.wordId,
        );
        final SavedWordApplyResult result;
        if (current is StoredSavedWordState &&
            current.lastMutationId == command.mutationId) {
          if (current.isSaved != command.desiredIsSaved ||
              current.localRevision - 1 != command.expectedRevision ||
              current.updatedAtUtc != command.occurredAtUtc) {
            throw const SavedWordsException(SavedWordsFailureCode.collision);
          }
          result = SavedWordApplyResult(
            status: SavedWordApplyStatus.replayed,
            state: current,
          );
        } else if (current.localRevision != command.expectedRevision) {
          result = SavedWordApplyResult(
            status: SavedWordApplyStatus.conflict,
            state: current,
          );
        } else if (current is AbsentSavedWordState && !command.desiredIsSaved) {
          result = SavedWordApplyResult(
            status: SavedWordApplyStatus.unchanged,
            state: current,
          );
        } else {
          await _requireParents(
            command.expectedOwnerId,
            command.wordId,
            active: command.desiredIsSaved,
          );
          if (current.localRevision == savedWordsMaxRevision) {
            _unavailable();
          }
          final next = StoredSavedWordState(
            ownerId: command.expectedOwnerId,
            wordId: command.wordId,
            isSaved: command.desiredIsSaved,
            localRevision: current.localRevision + 1,
            firstSavedAtUtc: current.firstSavedAtUtc ?? command.occurredAtUtc,
            updatedAtUtc: command.occurredAtUtc,
            lastMutationId: command.mutationId,
          );
          if (current is AbsentSavedWordState) {
            await database.customInsert(
              'INSERT INTO saved_words '
              '(owner_id,word_id,is_saved,local_revision,first_saved_at_utc_ms,updated_at_utc_ms,last_mutation_id) '
              'VALUES (?,?,?,?,?,?,?)',
              variables: [
                Variable<String>(next.ownerId),
                Variable<String>(next.wordId),
                Variable<bool>(next.isSaved),
                Variable<int>(next.localRevision),
                Variable<int>(next.firstSavedAtUtc.millisecondsSinceEpoch),
                Variable<int>(next.updatedAtUtc.millisecondsSinceEpoch),
                Variable<String>(next.lastMutationId),
              ],
              updates: {database.savedWords},
            );
          } else {
            final updated = await database.customUpdate(
              'UPDATE saved_words SET is_saved = ?,local_revision = ?,updated_at_utc_ms = ?,last_mutation_id = ? '
              'WHERE owner_id = ? AND word_id = ? AND local_revision = ?',
              variables: [
                Variable<bool>(next.isSaved),
                Variable<int>(next.localRevision),
                Variable<int>(next.updatedAtUtc.millisecondsSinceEpoch),
                Variable<String>(next.lastMutationId),
                Variable<String>(next.ownerId),
                Variable<String>(next.wordId),
                Variable<int>(current.localRevision),
              ],
              updates: {database.savedWords},
            );
            if (updated != 1) {
              _unavailable();
            }
          }
          result = SavedWordApplyResult(
            status: SavedWordApplyStatus.applied,
            state: next,
          );
        }
        return _ownerWrites.writeForActiveOwner(
          expectedOwnerId: command.expectedOwnerId,
          write: () async {
            final persisted = await _readState(
              command.expectedOwnerId,
              command.wordId,
            );
            if (!persisted.sameFacts(result.state)) {
              _unavailable();
            }
            await _requireParents(
              command.expectedOwnerId,
              command.wordId,
              active:
                  result.status == SavedWordApplyStatus.applied &&
                  command.desiredIsSaved,
            );
            return result;
          },
        );
      },
    );
  }

  Future<SavedWordState> _readState(String ownerId, String wordId) async {
    final row = await database
        .customSelect(
          'SELECT * FROM saved_words WHERE owner_id = ? AND word_id = ?',
          variables: [Variable<String>(ownerId), Variable<String>(wordId)],
        )
        .getSingleOrNull();
    return row == null
        ? SavedWordState.absent(ownerId: ownerId, wordId: wordId)
        : _stored(row);
  }

  Future<void> _requireParents(
    String ownerId,
    String wordId, {
    required bool active,
  }) async {
    final row = await database
        .customSelect(
          'SELECT w.is_deleted AS word_deleted,c.is_deleted AS category_deleted '
          'FROM vocabulary_words w JOIN vocabulary_categories c '
          'ON c.id = w.category_id AND c.owner_id = w.owner_id '
          'WHERE w.id = ? AND w.owner_id = ?',
          variables: [Variable<String>(wordId), Variable<String>(ownerId)],
        )
        .getSingleOrNull();
    if (row == null ||
        (active &&
            (row.read<bool>('word_deleted') ||
                row.read<bool>('category_deleted')))) {
      _unavailable();
    }
  }

  SavedWordsSnapshot _snapshot(String ownerId, List<QueryRow> rows) {
    final states = <StoredSavedWordState>[];
    final items = <SavedWordItem>[];
    for (final row in rows) {
      final state = _stored(row);
      states.add(state);
      if (!state.isSaved) {
        continue;
      }
      VocabularyWord? word;
      String? categoryName;
      if (row.readNullable<String>('current_word_id') != null &&
          row.readNullable<String>('joined_category_id') != null &&
          !row.read<bool>('word_deleted') &&
          !row.read<bool>('category_deleted')) {
        word = VocabularyWord(
          id: row.read<String>('current_word_id'),
          ownerId: row.read<String>('current_word_owner'),
          categoryId: row.read<String>('current_category_id'),
          spelling: row.read<String>('spelling'),
          normalizedSpelling: row.read<String>('normalized_spelling'),
          meaning: row.read<String>('meaning'),
          normalizedMeaning: row.read<String>('normalized_meaning'),
          partOfSpeech: row.read<String>('part_of_speech'),
          cefrLevel: row.readNullable<String>('cefr_level'),
          source: row.read<String>('source'),
          isGlobal: row.read<bool>('is_global'),
          localRevision: row.read<int>('current_word_revision'),
          isDeleted: false,
          createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('word_created_at'),
            isUtc: true,
          ),
          updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('word_updated_at'),
            isUtc: true,
          ),
        );
        categoryName = row.read<String>('category_name');
      }
      items.add(
        SavedWordItem(state: state, word: word, categoryName: categoryName),
      );
    }
    return SavedWordsSnapshot(
      ownerId: ownerId,
      states: states,
      savedItems: items,
    );
  }

  StoredSavedWordState _stored(QueryRow row) {
    try {
      return StoredSavedWordState.fromStorage({
        for (final name in const [
          'owner_id',
          'word_id',
          'is_saved',
          'local_revision',
          'first_saved_at_utc_ms',
          'updated_at_utc_ms',
          'last_mutation_id',
        ])
          name: row.data[name],
      });
    } on FormatException {
      _unavailable();
    }
  }

  Never _unavailable() =>
      throw const SavedWordsException(SavedWordsFailureCode.unavailable);
}
