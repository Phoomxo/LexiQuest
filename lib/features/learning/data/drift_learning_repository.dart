import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import '../domain/srs_policy.dart';

final class DriftLearningRepository implements LearningRepository {
  DriftLearningRepository(
    this.database, {
    this.srsPolicy = const BinarySm2SrsPolicy(),
  });

  final db.AppDatabase database;
  final SrsPolicy srsPolicy;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final query = database.select(database.vocabularyWords)
      ..where(
        (row) =>
            row.ownerId.equals(ownerId) &
            row.isDeleted.equals(false) &
            (categoryId == null
                ? const Constant(true)
                : row.categoryId.equals(categoryId)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.id)])
      ..limit(limit);
    final rows = await query.get();
    return rows
        .map(
          (row) => QuizWord(
            id: row.id,
            categoryId: row.categoryId,
            spelling: row.spelling,
            meaning: row.meaning,
            partOfSpeech: row.partOfSpeech,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> startSession(LearningSessionDraft session) async {
    final startedAt = _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    await database
        .into(database.learningSessions)
        .insert(
          db.LearningSessionsCompanion.insert(
            id: _required(session.id, 'id'),
            ownerId: _required(session.ownerId, 'ownerId'),
            activityType: _required(session.activityType, 'activityType'),
            state: 'active',
            startedAtUtcMs: startedAt.millisecondsSinceEpoch,
            appVersion: _required(session.appVersion, 'appVersion'),
            buildId: _required(session.buildId, 'buildId'),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) {
    _validateAnswer(command);
    return database.transaction(() async {
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingleOrNull();
      if (existing != null) {
        if (!_sameAttempt(existing, command)) {
          throw StateError('attempt id already exists with different evidence');
        }
        return AnswerRecordResult(
          inserted: false,
          srs: await _requiredSrs(command.ownerId, command.wordId),
        );
      }

      final session =
          await (database.select(database.learningSessions)..where(
                (row) =>
                    row.id.equals(command.sessionId) &
                    row.ownerId.equals(command.ownerId) &
                    row.state.equals('active'),
              ))
              .getSingleOrNull();
      if (session == null) {
        throw StateError('active learning session not found');
      }
      final word =
          await (database.select(database.vocabularyWords)..where(
                (row) =>
                    row.id.equals(command.wordId) &
                    row.ownerId.equals(command.ownerId) &
                    row.isDeleted.equals(false),
              ))
              .getSingleOrNull();
      if (word == null) {
        throw StateError('active vocabulary word not found');
      }

      await database
          .into(database.answerAttempts)
          .insert(
            db.AnswerAttemptsCompanion.insert(
              id: command.id,
              ownerId: command.ownerId,
              sessionId: command.sessionId,
              wordId: command.wordId,
              promptMode: command.promptMode,
              isCorrect: command.isCorrect,
              responseTimeMs: Value(command.responseTimeMs),
              attemptNumber: command.attemptNumber,
              occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
              providerProvenance: Value(command.providerProvenance),
            ),
          );
      await (database.update(
        database.learningSessions,
      )..where((row) => row.id.equals(command.sessionId))).write(
        command.isCorrect
            ? db.LearningSessionsCompanion(
                correctCount: Value(session.correctCount + 1),
              )
            : db.LearningSessionsCompanion(
                wrongCount: Value(session.wrongCount + 1),
              ),
      );

      final prior = await _srs(command.ownerId, command.wordId);
      final next = srsPolicy.review(
        previous: prior,
        isCorrect: command.isCorrect,
        nowUtc: command.occurredAtUtc,
      );
      await database
          .into(database.srsStates)
          .insertOnConflictUpdate(
            db.SrsStatesCompanion.insert(
              id: 'srs:${command.ownerId}:${command.wordId}',
              ownerId: command.ownerId,
              wordId: command.wordId,
              stability: Value(next.stability),
              difficulty: Value(next.difficulty),
              intervalDays: Value(next.intervalDays),
              repetitions: Value(next.repetitions),
              lapses: Value(next.lapses),
              lastReviewAtUtcMs: Value(
                next.lastReviewAtUtc?.millisecondsSinceEpoch,
              ),
              dueAtUtcMs: next.dueAtUtc!.millisecondsSinceEpoch,
              algorithmVersion: next.algorithmVersion,
            ),
          );
      if (command.isCorrect) {
        await database
            .into(database.pointsLedgerEntries)
            .insert(
              db.PointsLedgerEntriesCompanion.insert(
                id: 'points:${command.id}',
                ownerId: command.ownerId,
                idempotencyKey: 'correct-answer:${command.id}',
                entryType: 'quizCorrect',
                amount: 1,
                sourceEventId: Value(command.id),
                occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      return AnswerRecordResult(inserted: true, srs: next);
    });
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) {
    _requiredUtc(endedAtUtc, 'endedAtUtc');
    return database.transaction(() async {
      final row =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(sessionId) &
                    candidate.ownerId.equals(ownerId),
              ))
              .getSingleOrNull();
      if (row == null) throw StateError('learning session not found');
      final total = row.correctCount + row.wrongCount;
      final score = total == 0 ? 0 : ((row.correctCount * 100) / total).round();
      if (row.state != 'completed') {
        await (database.update(
          database.learningSessions,
        )..where((candidate) => candidate.id.equals(sessionId))).write(
          db.LearningSessionsCompanion(
            state: const Value('completed'),
            endedAtUtcMs: Value(endedAtUtc.millisecondsSinceEpoch),
            score: Value(score),
          ),
        );
      }
      return LearningSessionSummary(
        id: row.id,
        state: 'completed',
        correctCount: row.correctCount,
        wrongCount: row.wrongCount,
        score: score,
      );
    });
  }

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async {
    _requiredUtc(nowUtc, 'nowUtc');
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final query =
        database.select(database.vocabularyWords).join([
            innerJoin(
              database.srsStates,
              database.srsStates.wordId.equalsExp(database.vocabularyWords.id) &
                  database.srsStates.ownerId.equals(ownerId) &
                  database.srsStates.dueAtUtcMs.isSmallerOrEqualValue(
                    nowUtc.millisecondsSinceEpoch,
                  ),
            ),
          ])
          ..where(
            database.vocabularyWords.ownerId.equals(ownerId) &
                database.vocabularyWords.isDeleted.equals(false),
          )
          ..orderBy([OrderingTerm.asc(database.srsStates.dueAtUtcMs)])
          ..limit(limit);
    final rows = await query.get();
    return rows
        .map((row) => row.readTable(database.vocabularyWords))
        .map(
          (word) => QuizWord(
            id: word.id,
            categoryId: word.categoryId,
            spelling: word.spelling,
            meaning: word.meaning,
            partOfSpeech: word.partOfSpeech,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async {
    final row =
        await (database.select(database.readingProgressEntries)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.documentId.equals(documentId) &
                  candidate.documentRevision.equals(documentRevision),
            ))
            .getSingleOrNull();
    return row == null ? null : _readingSnapshot(row);
  }

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) {
    _validateReading(command);
    return database.transaction(() async {
      final priorEvent = await (database.select(
        database.readingEvents,
      )..where((row) => row.id.equals(command.eventId))).getSingleOrNull();
      if (priorEvent != null) {
        final current = await readReadingProgress(
          ownerId: command.ownerId,
          documentId: command.documentId,
          documentRevision: command.documentRevision,
        );
        if (current == null) {
          throw StateError('reading event exists without progress');
        }
        return current;
      }
      final current = await readReadingProgress(
        ownerId: command.ownerId,
        documentId: command.documentId,
        documentRevision: command.documentRevision,
      );
      final nextPosition = math.max(
        current?.lastPosition ?? 0,
        command.position,
      );
      final nextCompleted =
          (current?.isCompleted ?? false) || command.isCompleted;
      final progressId =
          'reading:${command.ownerId}:${command.documentId}:${command.documentRevision}';
      await database
          .into(database.readingProgressEntries)
          .insertOnConflictUpdate(
            db.ReadingProgressEntriesCompanion.insert(
              id: progressId,
              ownerId: command.ownerId,
              documentId: command.documentId,
              documentRevision: Value(command.documentRevision),
              lastPosition: Value(nextPosition),
              isCompleted: Value(nextCompleted),
              updatedAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
            ),
          );
      await database
          .into(database.readingEvents)
          .insert(
            db.ReadingEventsCompanion.insert(
              id: command.eventId,
              ownerId: command.ownerId,
              documentId: command.documentId,
              eventType: command.isCompleted ? 'completed' : 'checkpoint',
              position: Value(command.position),
              occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
            ),
          );
      return ReadingProgressSnapshot(
        documentId: command.documentId,
        documentRevision: command.documentRevision,
        lastPosition: nextPosition,
        isCompleted: nextCompleted,
        updatedAtUtc: command.occurredAtUtc,
      );
    });
  }

  Future<SrsSnapshot?> _srs(String ownerId, String wordId) async {
    final row =
        await (database.select(database.srsStates)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.wordId.equals(wordId),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return SrsSnapshot(
      intervalDays: row.intervalDays,
      repetitions: row.repetitions,
      lapses: row.lapses,
      stability: row.stability,
      difficulty: row.difficulty,
      lastReviewAtUtc: _fromEpoch(row.lastReviewAtUtcMs),
      dueAtUtc: _fromEpoch(row.dueAtUtcMs),
      algorithmVersion: row.algorithmVersion,
    );
  }

  Future<SrsSnapshot> _requiredSrs(String ownerId, String wordId) async {
    final result = await _srs(ownerId, wordId);
    if (result == null) throw StateError('attempt exists without SRS state');
    return result;
  }

  bool _sameAttempt(db.AnswerAttempt row, RecordAnswerCommand command) {
    return row.ownerId == command.ownerId &&
        row.sessionId == command.sessionId &&
        row.wordId == command.wordId &&
        row.promptMode == command.promptMode &&
        row.isCorrect == command.isCorrect &&
        row.responseTimeMs == command.responseTimeMs &&
        row.attemptNumber == command.attemptNumber &&
        row.occurredAtUtcMs == command.occurredAtUtc.millisecondsSinceEpoch;
  }

  ReadingProgressSnapshot _readingSnapshot(db.ReadingProgressEntry row) {
    return ReadingProgressSnapshot(
      documentId: row.documentId,
      documentRevision: row.documentRevision,
      lastPosition: row.lastPosition,
      isCompleted: row.isCompleted,
      updatedAtUtc: _fromEpoch(row.updatedAtUtcMs)!,
    );
  }

  void _validateAnswer(RecordAnswerCommand command) {
    _required(command.id, 'id');
    _required(command.ownerId, 'ownerId');
    _required(command.sessionId, 'sessionId');
    _required(command.wordId, 'wordId');
    _required(command.promptMode, 'promptMode');
    _requiredUtc(command.occurredAtUtc, 'occurredAtUtc');
    if (command.attemptNumber < 1) {
      throw ArgumentError.value(command.attemptNumber, 'attemptNumber');
    }
    if (command.responseTimeMs != null && command.responseTimeMs! < 0) {
      throw ArgumentError.value(command.responseTimeMs, 'responseTimeMs');
    }
  }

  void _validateReading(ReadingProgressCommand command) {
    _required(command.eventId, 'eventId');
    _required(command.ownerId, 'ownerId');
    _required(command.documentId, 'documentId');
    _requiredUtc(command.occurredAtUtc, 'occurredAtUtc');
    if (command.documentRevision < 1 || command.position < 0) {
      throw ArgumentError('invalid reading revision or position');
    }
  }

  String _required(String value, String field) {
    final result = value.trim();
    if (result.isEmpty) throw ArgumentError.value(value, field, 'blank');
    return result;
  }

  DateTime _requiredUtc(DateTime? value, String field) {
    if (value == null || !value.isUtc) {
      throw ArgumentError.value(value, field, 'must be UTC');
    }
    return value;
  }

  DateTime? _fromEpoch(int? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}
