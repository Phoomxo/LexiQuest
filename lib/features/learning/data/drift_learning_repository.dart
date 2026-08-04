import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import 'drift_learning_projection_rebuilder.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import '../domain/srs_policy.dart';

final class DriftLearningRepository implements LearningRepository {
  DriftLearningRepository(
    this.database, {
    SrsPolicy srsPolicy = const BinarySm2SrsPolicy(),
  }) : projections = DriftLearningProjectionRebuilder(
         database,
         srsPolicy: srsPolicy,
       ),
       rewardProjections = DriftRewardProjectionRebuilder(database);

  final db.AppDatabase database;
  final DriftLearningProjectionRebuilder projections;
  final DriftRewardProjectionRebuilder rewardProjections;

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
        final srs = await projections.rebuildWord(
          ownerId: command.ownerId,
          wordId: command.wordId,
        );
        await projections.rebuildSession(
          ownerId: command.ownerId,
          sessionId: command.sessionId,
        );
        await projections.rebuildAchievements(command.ownerId);
        await rewardProjections.rebuild(command.ownerId);
        return AnswerRecordResult(inserted: false, srs: srs);
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
      final next = await projections.rebuildWord(
        ownerId: command.ownerId,
        wordId: command.wordId,
      );
      await projections.rebuildSession(
        ownerId: command.ownerId,
        sessionId: command.sessionId,
      );
      await projections.rebuildAchievements(command.ownerId);
      await rewardProjections.rebuild(command.ownerId);
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'attempt',
        entityId: command.id,
        occurredAtUtc: command.occurredAtUtc,
      );
      // Outbox hook — push updated SRS state to Firestore (Phase 0 Week 12-13).
      // Entity ID is wordId (unique per owner-word pair).
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'srsState',
        entityId: command.wordId,
        occurredAtUtc: command.occurredAtUtc,
      );
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
        await _unlockAchievement(
          ownerId: ownerId,
          achievementId: 'first_session',
          sourceEventId: sessionId,
          unlockedAtUtc: endedAtUtc,
        );
        if (total > 0 && row.wrongCount == 0) {
          await _unlockAchievement(
            ownerId: ownerId,
            achievementId: 'perfect_session',
            sourceEventId: sessionId,
            unlockedAtUtc: endedAtUtc,
          );
        }
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
        if (!_sameReadingEvent(priorEvent, command)) {
          throw StateError(
            'reading event id already exists with different evidence',
          );
        }
        return projections.rebuildReading(
          ownerId: command.ownerId,
          documentId: command.documentId,
          documentRevision: command.documentRevision,
        );
      }
      await database
          .into(database.readingEvents)
          .insert(
            db.ReadingEventsCompanion.insert(
              id: command.eventId,
              ownerId: command.ownerId,
              documentId: command.documentId,
              documentRevision: Value(command.documentRevision),
              eventType: command.isCompleted ? 'completed' : 'checkpoint',
              position: Value(command.position),
              occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
            ),
          );
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'readingEvent',
        entityId: command.eventId,
        occurredAtUtc: command.occurredAtUtc,
      );
      return projections.rebuildReading(
        ownerId: command.ownerId,
        documentId: command.documentId,
        documentRevision: command.documentRevision,
      );
    });
  }

  Future<void> _unlockAchievement({
    required String ownerId,
    required String achievementId,
    required String sourceEventId,
    required DateTime unlockedAtUtc,
  }) async {
    const definitionVersion = 1;
    final achievementId_ = 'achievement:$ownerId:$achievementId:$definitionVersion';
    await database
        .into(database.achievementUnlocks)
        .insert(
          db.AchievementUnlocksCompanion.insert(
            id: achievementId_,
            ownerId: ownerId,
            achievementId: achievementId,
            definitionVersion: definitionVersion,
            sourceEventId: sourceEventId,
            unlockedAtUtcMs: unlockedAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    // Outbox hook — sync achievement unlock to Firestore (Phase 0 Week 12-13).
    await _appendImmutableOutbox(
      ownerId: ownerId,
      entityType: 'achievementUnlock',
      entityId: achievementId_,
      occurredAtUtc: unlockedAtUtc,
    );
  }

  Future<void> _appendImmutableOutbox({
    required String ownerId,
    required String entityType,
    required String entityId,
    required DateTime occurredAtUtc,
  }) async {
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId: '$entityType:$entityId:1',
            ownerId: ownerId,
            entityType: entityType,
            entityId: entityId,
            operationKind: 'upsert',
            baseRevision: const Value(0),
            createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  bool _sameAttempt(db.AnswerAttempt row, RecordAnswerCommand command) {
    return row.ownerId == command.ownerId &&
        row.sessionId == command.sessionId &&
        row.wordId == command.wordId &&
        row.promptMode == command.promptMode &&
        row.isCorrect == command.isCorrect &&
        row.responseTimeMs == command.responseTimeMs &&
        row.attemptNumber == command.attemptNumber &&
        row.occurredAtUtcMs == command.occurredAtUtc.millisecondsSinceEpoch &&
        row.providerProvenance == command.providerProvenance;
  }

  bool _sameReadingEvent(db.ReadingEvent row, ReadingProgressCommand command) {
    return row.ownerId == command.ownerId &&
        row.documentId == command.documentId &&
        row.documentRevision == command.documentRevision &&
        row.eventType == (command.isCompleted ? 'completed' : 'checkpoint') &&
        row.position == command.position &&
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
    final occurredAt = _requiredUtc(command.occurredAtUtc, 'occurredAtUtc');
    if (!LearningEvidenceContract.validAttempt(
      id: command.id,
      ownerId: command.ownerId,
      sessionId: command.sessionId,
      wordId: command.wordId,
      promptMode: command.promptMode,
      responseTimeMs: command.responseTimeMs,
      attemptNumber: command.attemptNumber,
      occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
      providerProvenance: command.providerProvenance,
    )) {
      throw ArgumentError.value(command, 'command', 'invalid answer evidence');
    }
  }

  void _validateReading(ReadingProgressCommand command) {
    final occurredAt = _requiredUtc(command.occurredAtUtc, 'occurredAtUtc');
    if (!LearningEvidenceContract.validReading(
      eventId: command.eventId,
      ownerId: command.ownerId,
      documentId: command.documentId,
      documentRevision: command.documentRevision,
      eventType: command.isCompleted ? 'completed' : 'checkpoint',
      position: command.position,
      occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
    )) {
      throw ArgumentError.value(command, 'command', 'invalid reading evidence');
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
