import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/learning_models.dart';
import '../domain/srs_policy.dart';

final class DriftLearningProjectionRebuilder {
  const DriftLearningProjectionRebuilder(
    this.database, {
    this.srsPolicy = const BinarySm2SrsPolicy(),
  });

  final db.AppDatabase database;
  final SrsPolicy srsPolicy;

  Future<SrsSnapshot> rebuildWord({
    required String ownerId,
    required String wordId,
  }) async {
    final attempts =
        await (database.select(database.answerAttempts)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) & row.wordId.equals(wordId),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    if (attempts.isEmpty) {
      throw StateError('cannot rebuild SRS without answer evidence');
    }

    SrsSnapshot? state;
    for (final attempt in attempts) {
      state = srsPolicy.review(
        previous: state,
        isCorrect: attempt.isCorrect,
        nowUtc: _utc(attempt.occurredAtUtcMs),
      );
      if (attempt.isCorrect) {
        await database
            .into(database.pointsLedgerEntries)
            .insert(
              db.PointsLedgerEntriesCompanion.insert(
                id: 'points:${attempt.id}',
                ownerId: ownerId,
                idempotencyKey: 'correct-answer:${attempt.id}',
                entryType: 'quizCorrect',
                amount: 1,
                sourceEventId: Value(attempt.id),
                occurredAtUtcMs: attempt.occurredAtUtcMs,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }

    final next = state!;
    await database
        .into(database.srsStates)
        .insertOnConflictUpdate(
          db.SrsStatesCompanion.insert(
            id: 'srs:$ownerId:$wordId',
            ownerId: ownerId,
            wordId: wordId,
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
    return next;
  }

  Future<void> rebuildSession({
    required String ownerId,
    required String sessionId,
  }) async {
    final session =
        await (database.select(database.learningSessions)..where(
              (row) => row.id.equals(sessionId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (session == null) {
      throw StateError('owner-scoped learning session not found');
    }
    final attempts =
        await (database.select(database.answerAttempts)..where(
              (row) =>
                  row.ownerId.equals(ownerId) & row.sessionId.equals(sessionId),
            ))
            .get();
    final correct = attempts.where((attempt) => attempt.isCorrect).length;
    final wrong = attempts.length - correct;
    final score = attempts.isEmpty
        ? 0
        : ((correct * 100) / attempts.length).round();
    await (database.update(database.learningSessions)..where(
          (row) => row.id.equals(sessionId) & row.ownerId.equals(ownerId),
        ))
        .write(
          db.LearningSessionsCompanion(
            correctCount: Value(correct),
            wrongCount: Value(wrong),
            score: session.state == 'completed'
                ? Value(score)
                : const Value.absent(),
          ),
        );
  }

  Future<void> rebuildAchievements(String ownerId) async {
    final attempts =
        await (database.select(database.answerAttempts)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    if (attempts.isEmpty) return;
    await _insertAchievement(
      ownerId: ownerId,
      achievementId: 'first_answer',
      source: attempts.first,
    );
    final correct = attempts
        .where((attempt) => attempt.isCorrect)
        .toList(growable: false);
    if (correct.isNotEmpty) {
      await _insertAchievement(
        ownerId: ownerId,
        achievementId: 'first_correct',
        source: correct.first,
      );
    }
    if (correct.length >= 10) {
      await _insertAchievement(
        ownerId: ownerId,
        achievementId: 'ten_correct',
        source: correct[9],
      );
    }
  }

  Future<ReadingProgressSnapshot> rebuildReading({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async {
    final events =
        await (database.select(database.readingEvents)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.documentId.equals(documentId) &
                    row.documentRevision.equals(documentRevision),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    if (events.isEmpty) {
      throw StateError('cannot rebuild reading progress without evidence');
    }
    var position = 0;
    var completed = false;
    var updatedAtUtcMs = 0;
    for (final event in events) {
      final eventPosition = event.position ?? 0;
      if (eventPosition > position) position = eventPosition;
      if (event.eventType == 'completed') completed = true;
      if (event.occurredAtUtcMs > updatedAtUtcMs) {
        updatedAtUtcMs = event.occurredAtUtcMs;
      }
    }
    await database
        .into(database.readingProgressEntries)
        .insertOnConflictUpdate(
          db.ReadingProgressEntriesCompanion.insert(
            id: 'reading:$ownerId:$documentId:$documentRevision',
            ownerId: ownerId,
            documentId: documentId,
            documentRevision: Value(documentRevision),
            lastPosition: Value(position),
            isCompleted: Value(completed),
            updatedAtUtcMs: updatedAtUtcMs,
          ),
        );
    return ReadingProgressSnapshot(
      documentId: documentId,
      documentRevision: documentRevision,
      lastPosition: position,
      isCompleted: completed,
      updatedAtUtc: _utc(updatedAtUtcMs),
    );
  }

  Future<void> _insertAchievement({
    required String ownerId,
    required String achievementId,
    required db.AnswerAttempt source,
  }) async {
    const definitionVersion = 1;
    await database
        .into(database.achievementUnlocks)
        .insertOnConflictUpdate(
          db.AchievementUnlocksCompanion.insert(
            id: 'achievement:$ownerId:$achievementId:$definitionVersion',
            ownerId: ownerId,
            achievementId: achievementId,
            definitionVersion: definitionVersion,
            sourceEventId: source.id,
            unlockedAtUtcMs: source.occurredAtUtcMs,
          ),
        );
  }
}

DateTime _utc(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);
