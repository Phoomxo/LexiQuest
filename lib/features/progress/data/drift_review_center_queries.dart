import 'dart:async';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../learning/domain/learning_evidence_contract.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../domain/review_center_models.dart';

class DriftReviewCenterQueries {
  const DriftReviewCenterQueries(this.database);
  final db.AppDatabase database;

  Stream<ReviewReadFacts> watchOwner({
    required String expectedOwnerId,
    required DateTime evaluatedAtUtc,
    required bool Function() stillCurrent,
  }) {
    late final StreamController<_QueuedReviewFacts> output;
    StreamSubscription<dynamic>? ownerUpdates;
    StreamSubscription<List<QueryRow>>? rows;
    var retired = false;
    var generation = 0;

    Future<void> cancel() async {
      retired = true;
      await Future.wait([
        if (ownerUpdates != null) ownerUpdates!.cancel(),
        if (rows != null) rows!.cancel(),
      ]);
    }

    void fail(Object error, [StackTrace? stack]) {
      if (retired) return;
      retired = true;
      final publicError =
          error is ReviewCenterReadException &&
              error.code == ReviewReadFailureCode.ownerInvalidated
          ? error
          : const ReviewCenterReadException(ReviewReadFailureCode.readFailed);
      output.addError(publicError, stack);
      unawaited(output.close());
      unawaited(ownerUpdates?.cancel());
      unawaited(rows?.cancel());
    }

    Future<void> emit(List<QueryRow> stored) async {
      final captured = ++generation;
      try {
        await requireReviewReadOwner(
          database,
          expectedOwnerId: expectedOwnerId,
          stillCurrent: () => !retired && stillCurrent(),
        );
        final result = _facts(expectedOwnerId, evaluatedAtUtc, stored);
        await requireReviewReadOwner(
          database,
          expectedOwnerId: expectedOwnerId,
          stillCurrent: () => !retired && stillCurrent(),
        );
        if (retired) return;
        if (!stillCurrent()) {
          fail(
            const ReviewCenterReadException(
              ReviewReadFailureCode.ownerInvalidated,
            ),
          );
          return;
        }
        if (captured == generation) {
          output.add((revision: captured, value: result));
        }
      } catch (error, stack) {
        fail(error, stack);
      }
    }

    Future<void> begin() async {
      try {
        ownerUpdates = database
            .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
            .listen(
              (_) => fail(
                const ReviewCenterReadException(
                  ReviewReadFailureCode.ownerInvalidated,
                ),
              ),
              onError: (Object _, StackTrace stack) => fail(
                const ReviewCenterReadException(
                  ReviewReadFailureCode.ownerInvalidated,
                ),
                stack,
              ),
              onDone: () => fail(
                const ReviewCenterReadException(
                  ReviewReadFailureCode.ownerInvalidated,
                ),
              ),
            );
        await requireReviewReadOwner(
          database,
          expectedOwnerId: expectedOwnerId,
          stillCurrent: () => !retired && stillCurrent(),
        );
        if (retired) return;
        if (!evaluatedAtUtc.isUtc ||
            evaluatedAtUtc.microsecondsSinceEpoch < 0 ||
            evaluatedAtUtc.microsecondsSinceEpoch % 1000 != 0) {
          throw ArgumentError('Review cutoff must be UTC milliseconds');
        }
        rows = database
            .customSelect(
              '''
WITH candidates AS (
  SELECT s.word_id AS review_word_id,s.due_at_utc_ms AS review_due_at,
         NULL AS review_occurred_at,NULL AS review_evidence_class,NULL AS review_context
  FROM srs_states s
  JOIN vocabulary_words eligible_word
    ON eligible_word.id=s.word_id AND eligible_word.owner_id=s.owner_id
    AND eligible_word.is_deleted=0
  JOIN vocabulary_categories eligible_category
    ON eligible_category.id=eligible_word.category_id AND eligible_category.owner_id=s.owner_id
    AND eligible_category.is_deleted=0
  WHERE s.owner_id=? AND s.due_at_utc_ms<=?
  UNION ALL
  SELECT a.word_id,NULL,a.occurred_at_utc_ms,a.evidence_class,a.evidence_context_json
  FROM answer_attempts a
  JOIN learning_sessions session ON session.id=a.session_id AND session.owner_id=a.owner_id
  WHERE a.owner_id=? AND a.is_correct=0 AND session.activity_type<>'assessment'
)
SELECT candidates.*,w.*,c.id AS review_category_id,c.name AS review_category_name
FROM candidates
LEFT JOIN vocabulary_words w
  ON w.id=candidates.review_word_id AND w.owner_id=? AND w.is_deleted=0
LEFT JOIN vocabulary_categories c
  ON c.id=w.category_id AND c.owner_id=w.owner_id AND c.is_deleted=0
ORDER BY candidates.review_word_id
''',
              variables: [
                Variable<String>(expectedOwnerId),
                Variable<int>(evaluatedAtUtc.millisecondsSinceEpoch),
                Variable<String>(expectedOwnerId),
                Variable<String>(expectedOwnerId),
              ],
              readsFrom: {
                database.srsStates,
                database.answerAttempts,
                database.learningSessions,
                database.vocabularyWords,
                database.vocabularyCategories,
              },
            )
            .watch()
            .listen(
              (stored) => unawaited(emit(stored)),
              onError: fail,
              onDone: () => fail(
                const ReviewCenterReadException(
                  ReviewReadFailureCode.readFailed,
                ),
              ),
            );
      } catch (error, stack) {
        fail(error, stack);
      }
    }

    output = StreamController<_QueuedReviewFacts>(
      onListen: () => unawaited(begin()),
      onCancel: cancel,
    );
    return output.stream.transform(
      StreamTransformer<_QueuedReviewFacts, ReviewReadFacts>.fromHandlers(
        handleData: (event, sink) {
          if (retired) return;
          try {
            if (!stillCurrent()) {
              fail(
                const ReviewCenterReadException(
                  ReviewReadFailureCode.ownerInvalidated,
                ),
              );
              return;
            }
            if (event.revision == generation) sink.add(event.value);
          } catch (error, stack) {
            fail(error, stack);
          }
        },
      ),
    );
  }

  ReviewReadFacts _facts(String ownerId, DateTime cutoff, List<QueryRow> rows) {
    final byWord = <String, _WordFacts>{};
    for (final row in rows) {
      final due = row.readNullable<int>('review_due_at');
      final occurred = row.readNullable<int>('review_occurred_at');
      if (due == null &&
          !LearningEvidenceContract.validEvidenceMetadata(
            evidenceClass: row.read<String>('review_evidence_class'),
            evidenceContextJson: row.read<String>('review_context'),
          )) {
        continue;
      }
      final id = row.read<String>('review_word_id');
      final current = row.readNullable<String>('review_category_id') == null
          ? null
          : _word(row);
      final facts = byWord.putIfAbsent(
        id,
        () => _WordFacts(
          word: current,
          categoryName: current == null
              ? null
              : row.read<String>('review_category_name'),
        ),
      );
      if (due != null) {
        facts.dueAt = due;
      } else if (occurred != null) {
        facts.incorrectCount++;
        if (facts.lastIncorrectAt == null ||
            occurred > facts.lastIncorrectAt!) {
          facts.lastIncorrectAt = occurred;
        }
      }
    }
    final result = byWord.entries.map((entry) {
      final facts = entry.value;
      return ReviewWordRow(
        ownerId: ownerId,
        wordId: entry.key,
        word: facts.word,
        categoryName: facts.categoryName,
        reasons: [
          if (facts.dueAt != null) DueReason(dueAtUtc: _utc(facts.dueAt!)),
          if (facts.incorrectCount > 0)
            IncorrectReason(
              incorrectCount: facts.incorrectCount,
              lastIncorrectAtUtc: _utc(facts.lastIncorrectAt!),
            ),
        ],
      );
    }).toList();
    result.sort((a, b) {
      final aDue = byWord[a.wordId]!.dueAt;
      final bDue = byWord[b.wordId]!.dueAt;
      if (aDue != null || bDue != null) {
        if (aDue == null) return 1;
        if (bDue == null) return -1;
        final time = aDue.compareTo(bDue);
        if (time != 0) return time;
      } else {
        final time = byWord[b.wordId]!.lastIncorrectAt!.compareTo(
          byWord[a.wordId]!.lastIncorrectAt!,
        );
        if (time != 0) return time;
      }
      return a.wordId.compareTo(b.wordId);
    });
    return ReviewReadFacts(
      ownerId: ownerId,
      evaluatedAtUtc: cutoff,
      wordRows: result,
    );
  }

  VocabularyWord _word(QueryRow row) => VocabularyWord(
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
    createdAtUtc: _utc(row.read<int>('created_at_utc_ms')),
    updatedAtUtc: _utc(row.read<int>('updated_at_utc_ms')),
  );
}

typedef _QueuedReviewFacts = ({int revision, ReviewReadFacts value});

Future<void> requireReviewReadOwner(
  db.AppDatabase database, {
  required String expectedOwnerId,
  required bool Function() stillCurrent,
}) async {
  const failure = ReviewCenterReadException(
    ReviewReadFailureCode.ownerInvalidated,
  );
  if (expectedOwnerId.trim().isEmpty || !stillCurrent()) throw failure;
  final List<QueryRow> rows;
  try {
    rows = await database
        .customSelect('SELECT id FROM local_owners WHERE is_active=1 LIMIT 2')
        .get();
  } catch (_) {
    throw failure;
  }
  if (!stillCurrent() ||
      rows.length != 1 ||
      rows.single.read<String>('id') != expectedOwnerId) {
    throw failure;
  }
}

DateTime _utc(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

final class _WordFacts {
  _WordFacts({required this.word, required this.categoryName});
  final VocabularyWord? word;
  final String? categoryName;
  int? dueAt;
  int incorrectCount = 0;
  int? lastIncorrectAt;
}
